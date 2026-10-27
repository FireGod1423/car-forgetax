-- 概念原型的規則測試。每次都用新的記憶體車庫，不寫入玩家存檔。
local function runningInRoblox(): boolean
	return game ~= nil
end

local function importServer(moduleName: string)
	if runningInRoblox() then
		return require(script.Parent:WaitForChild(moduleName))
	end
	return require("./" .. moduleName)
end

local function importShared(moduleName: string)
	if runningInRoblox() then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild(moduleName))
	end
	return require("../shared/" .. moduleName)
end

local CarConfig = importShared("CarConfig")
local UpgradeConfig = importShared("UpgradeConfig")
local RaceConfig = importShared("RaceConfig")
local PlaySessionService = importServer("PlaySessionService")

local Tests = {}
local now = 10000
local finishes = {}

local function assertEqual(actual, expected, message: string)
	if actual ~= expected then
		error(string.format("%s：預期 %s，實際 %s", message, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value, message: string)
	if value ~= true then
		error(message)
	end
end

local function assertClose(actual, expected, message: string)
	if type(actual) ~= "number" or math.abs(actual - expected) > 1e-4 then
		error(string.format("%s：預期 %s，實際 %s", message, tostring(expected), tostring(actual)))
	end
end

local function scriptedRng(values)
	local index = 0
	local calls = {}
	local rng = {
		NextInteger = function(_self, minValue, maxValue)
			index += 1
			local value = values[index]
			table.insert(calls, {
				min = minValue,
				max = maxValue,
				value = value,
			})
			if type(value) ~= "number" or value < minValue or value > maxValue then
				error(string.format(
					"腳本隨機數越界：第 %d 次，值 %s，範圍 %s-%s",
					index,
					tostring(value),
					tostring(minValue),
					tostring(maxValue)
				))
			end
			return value
		end,
	}
	return rng, calls
end

local function newService(presenter, options)
	options = options or {}
	return PlaySessionService.new({
		isStudio = true,
		bossEnabled = options.bossEnabled == true,
		clock = function()
			return now
		end,
		presenter = presenter,
		notify = function(playerKey, payload)
			finishes[playerKey] = payload
		end,
	})
end

local function balanceOf(session): number
	return session.wallet:GetBalance(session.key)
end

local function testRaceMath()
	local minPower, maxPower = RaceConfig.powerBounds()
	assertEqual(minPower, CarConfig.BasePower, "最低性能")
	assertEqual(RaceConfig.baseDuration(minPower), RaceConfig.MaxDuration, "最低性能時間")
	assertEqual(RaceConfig.baseDuration(maxPower), RaceConfig.MinDuration, "最高性能時間")
	assertTrue(RaceConfig.baseDuration(minPower + 1) < RaceConfig.MaxDuration, "性能提高後時間沒有變短")
	assertEqual(RaceConfig.baseDuration(maxPower + 50), RaceConfig.MinDuration, "超過上限仍應停在最短時間")
	assertEqual(RaceConfig.describe("fast"), nil, "無效性能不該產生時間")

	local plain = RaceConfig.describe(minPower, false)
	local boss = RaceConfig.describe(minPower, true)
	assertEqual(RaceConfig.MaxDuration, 10, "普通車基準時間應約 10 秒")
	assertEqual(RaceConfig.MinDuration, 5, "最快完賽不該接近 0 秒")
	assertEqual(RaceConfig.NormalReward, 45, "普通獎勵應為 45")
	assertEqual(plain.duration, 10, "普通車基準時間")
	assertEqual(plain.reward, 45, "普通車獎勵")
	assertClose(boss.duration - plain.duration, 0.6, "緩速應多 0.6 秒")
	assertEqual(boss.won, false, "10.6 秒不該贏過 10 秒")
	assertEqual(boss.reward, RaceConfig.BossLoseReward, "落敗獎金")
	local strong = RaceConfig.describe(maxPower, true)
	assertEqual(strong.won, true, "最高性能應贏過 Boss")
	assertTrue(strong.duration < RaceConfig.BossTargetTime, "勝利時間")
	assertEqual(RaceConfig.bossVictory(RaceConfig.BossTargetTime), false, "剛好目標秒數不算勝利")
	assertEqual(RaceConfig.bossVictory(RaceConfig.BossTargetTime - 0.001), true, "低於目標才勝利")
	local legendPower = CarConfig.calculatePower(10, "Legendary", 0)
	local legend = RaceConfig.describe(legendPower, false)
	assertTrue(legend.duration < plain.duration, "傳說滿級沒有比普通車快")
	assertTrue(legend.duration > RaceConfig.MinDuration, "傳說滿級被壓到最短時間")
	assertTrue(legend.duration >= 6, "高性能車完賽時間接近 0 秒")

	local length = RaceConfig.trackLength()
	local duringSlow = boss.slow.startDistance / boss.speed + 1.5
	local slowed = RaceConfig.distanceAtTime(duringSlow, boss.speed, boss.slow, length)
	local linear = RaceConfig.distanceAtTime(duringSlow, boss.speed, nil, length)
	assertTrue(slowed < linear, "緩速期間行進距離沒有變短")

	assertClose(RaceConfig.visualAlpha(0), 0, "視覺起跑不是從零開始")
	assertClose(RaceConfig.visualAlpha(1), 1, "視覺終點沒有對上正式距離")
	assertTrue(RaceConfig.visualAlpha(0.05) < 0.05, "起跑沒有先慢後快")
	local markers = RaceConfig.markers()
	local curve = RaceConfig.sample((markers.startEnd + markers.curveEnd) * 0.5)
	assertEqual(curve.segment, "Curve", "彎道段")
	assertTrue(math.abs(curve.upX) + math.abs(curve.upZ) < 0.02, "彎道中心線被整塊翻起")
	assertTrue(math.abs(curve.y - RaceConfig.Layout.originY) < 0.05, "賽道又被做成高跳台")
	local lap = RaceConfig.lapLength()
	local seamStart = RaceConfig.sample(0)
	local seamEnd = RaceConfig.sample(lap)
	assertClose(seamStart.x, seamEnd.x, "短圈沒有閉合")
	assertClose(seamStart.z, seamEnd.z, "短圈沒有閉合")
	assertTrue(seamStart.lookX * seamEnd.lookX + seamStart.lookZ * seamEnd.lookZ > 0.98, "閉合處車頭方向斷開")
	local previous = RaceConfig.sample(0)
	local step = lap / 48
	for index = 1, 48 do
		local sample = RaceConfig.sample(step * index)
		local deltaX = sample.x - previous.x
		local deltaZ = sample.z - previous.z
		assertTrue(deltaX * deltaX + deltaZ * deltaZ < (step * 1.8) * (step * 1.8), "路徑在節點間跳動")
		local heading = previous.lookX * sample.lookX + previous.lookZ * sample.lookZ
		assertTrue(heading > 0.9, "車頭突然大轉彎")
		previous = sample
	end
	assertEqual(RaceConfig.sample(length).segment, seamStart.segment, "最後一圈沒有回到終點線")
	local weights = UpgradeConfig.getWeights(8)
	assertEqual(weights.GreatSuccess, 1, "+8 大成功權重被改掉")
	assertEqual(UpgradeConfig.sumWeights(9), 100, "+9 權重總和")
	assertEqual(UpgradeConfig.getWeights(9).GreatSuccess, 0, "+9 大成功權重")
	assertEqual(CarConfig.SinglePullPrice, 500, "抽車價格")
	return "普通車 10 秒、45 金幣，Boss 緩速仍生效"
end

local function testStudioStarterAndPull()
	now = 12000
	finishes = {}
	local rng, calls = scriptedRng({ 1, 1, 1, 1 })
	local service = newService()
	local session = service:createSession("pull-player", {
		gachaRng = rng,
	})
	local again = service:createSession("pull-player")
	assertTrue(session == again, "同一玩家不該建立第二份車庫")
	local listed = session.inventory:ListCars(session.key)
	assertEqual(#listed, 1, "起始測試車數量")
	assertEqual(balanceOf(session), CarConfig.TestStartingGold, "Studio 測試金幣")

	local first = service:dispatch(session.key, {
		action = "Pull",
		attemptToken = "pull-token-01",
		modelId = "test_legendary_r0",
		rebirthLevel = 10,
		price = 1,
		quality = "Legendary",
	})
	assertEqual(first.ok, true, "抽車應該成功")
	assertEqual(first.modelId, "test_common_r0", "客戶端指定的車款生效了")
	assertEqual(first.price, 500, "成交價格")
	assertEqual(first.charged, true, "沒有扣款")
	assertEqual(first.balance, CarConfig.TestStartingGold - 500, "餘額")
	assertEqual(calls[1].max, 100, "品質抽籤範圍")
	assertEqual(calls[2].max, 1, "重生階級被客戶端改成可以抽到第二台普通車")
	assertEqual(#session.inventory:ListCars(session.key), 2, "新車沒有進車庫")

	local replay = service:dispatch(session.key, {
		action = "Pull",
		attemptToken = "pull-token-01",
		modelId = "test_legendary_r0",
	})
	assertEqual(replay.replayed, true, "重複請求沒有標記")
	assertEqual(replay.balance, first.balance, "重複請求又扣了金幣")
	assertEqual(#calls, 2, "重複請求又抽了一次")
	assertEqual(#session.inventory:ListCars(session.key), 2, "重複請求又發了一台車")

	now += 0.2
	local limited = service:dispatch(session.key, {
		action = "Pull",
		attemptToken = "pull-token-02",
	})
	assertEqual(limited.reason, PlaySessionService.Reason.RateLimited, "頻率限制")
	assertEqual(#calls, 2, "被限制的請求仍抽了車")
	assertEqual(balanceOf(session), first.balance, "被限制的請求扣了金幣")

	local function hasId(list, modelId: string): boolean
		if type(list) ~= "table" then
			return false
		end
		for _, item in ipairs(list) do
			if item == modelId then
				return true
			end
		end
		return false
	end
	local state = service:dispatch(session.key, {
		action = "GetState",
	})
	assertTrue(hasId(state.discovered, "test_common_r0"), "起始測試車沒有記入圖鑑")
	assertEqual(#state.discovered, 1, "同一款車重複增加發現數")
	assertEqual(state.dealerIntroSeen, false, "首次對話預設已看過")
	local introBalance = balanceOf(session)
	local skipped = service:dispatch(session.key, {
		action = "GetState",
		dealerIntroSeen = true,
	})
	assertEqual(skipped.dealerIntroSeen, false, "客戶端改寫了首次對話")
	local seen = service:dispatch(session.key, {
		action = "CompleteDealerIntro",
	})
	assertEqual(seen.dealerIntroSeen, true, "看完首次對話沒有記下")
	assertEqual(balanceOf(session), introBalance, "首次對話改了金幣")
	service:removeSession(session.key)
	local introReset = service:createSession(session.key)
	local resetIntro = service:dispatch(introReset.key, { action = "GetState" })
	assertEqual(resetIntro.dealerIntroSeen, false, "離線後仍記住首次對話")
	session = introReset
	local forged = service:dispatch(session.key, {
		action = "Discover",
		attemptToken = "discover-token-1",
		modelId = "test_legendary_r0",
	})
	assertEqual(forged.reason, PlaySessionService.Reason.UnknownAction, "客戶端可以宣稱解鎖圖鑑")
	state = service:dispatch(session.key, {
		action = "GetState",
		discovered = { "test_legendary_r0" },
	})
	assertEqual(#state.discovered, 1, "請求內容改寫了圖鑑")
	assertEqual(hasId(state.discovered, "test_legendary_r0"), false, "客戶端塞進了傳說車")

	local GachaSoundConfig = importShared("GachaSoundConfig")
	assertEqual(GachaSoundConfig.tick.soundId, "rbxassetid://9119717523", "Tick 音效")
	assertEqual(GachaSoundConfig.start.soundId, "rbxassetid://9125626478", "啟動音效")
	assertEqual(GachaSoundConfig.lock.soundId, "rbxassetid://9116673944", "鎖定音效")
	for _, quality in ipairs(CarConfig.getQualities()) do
		assertTrue(GachaSoundConfig.reveal[quality.Id] ~= nil, "缺少品質揭曉音效")
	end
	assertTrue(GachaSoundConfig.legendaryMelody.duration >= 2 and GachaSoundConfig.legendaryMelody.duration <= 3, "傳說旋律長度")
	assertTrue(GachaSoundConfig.legendaryMelody.soundId ~= GachaSoundConfig.reveal.Common[1].soundId, "傳說旋律與普通音相同")

	now += 3
	local catalogRng = scriptedRng({ 51, 1 })
	local catalogService = newService()
	local catalogSession = catalogService:createSession("catalog-player", {
		gachaRng = catalogRng,
	})
	local uncommon = catalogService:dispatch(catalogSession.key, {
		action = "Pull",
		attemptToken = "catalog-pull-01",
	})
	assertEqual(uncommon.ok, true, "圖鑑測試抽車失敗")
	assertEqual(uncommon.modelId, "test_uncommon_r0", "圖鑑測試沒有抽到優良車")
	local catalogState = catalogService:dispatch(catalogSession.key, {
		action = "GetState",
	})
	assertEqual(#catalogState.discovered, 2, "新車款沒有記入圖鑑")
	assertEqual(hasId(catalogState.discovered, "test_common_r1"), false, "R1 車被放進發現紀錄")
	catalogService:removeSession(catalogSession.key)
	local returned = catalogService:createSession("catalog-player", {
		isStudio = false,
	})
	local empty = catalogService:dispatch(returned.key, {
		action = "GetState",
	})
	assertEqual(#empty.discovered, 0, "離線後圖鑑還在")
	return "抽車扣 500，重複請求不雙重發車"
end

local function testUpgradeRules()
	now = 14000
	local successRng, successCalls = scriptedRng({ 16 })
	local service = newService()
	local session = service:createSession("upgrade-player", {
		upgradeRng = successRng,
	})
	local before = balanceOf(session)
	local starter = session.inventory:GetCar(session.key, session.selectedInstanceId)
	local success = service:dispatch(session.key, {
		action = "Upgrade",
		attemptToken = "upgrade-token-1",
		instanceId = starter.InstanceId,
		outcome = "GreatSuccess",
		upgradeLevel = 10,
	})
	assertEqual(success.ok, true, "強化失敗")
	assertEqual(success.outcome, "Success", "客戶端指定了強化結果")
	assertEqual(success.upgradeLevel, 1, "成功後等級")
	assertEqual(success.charged, false, "免費強化被扣款")
	assertEqual(balanceOf(session), before, "強化改變了金幣")
	assertEqual(#successCalls, 1, "強化沒有使用既有機率")

	local replay = service:dispatch(session.key, {
		action = "Upgrade",
		attemptToken = "upgrade-token-1",
		instanceId = starter.InstanceId,
		outcome = "GreatSuccess",
	})
	assertEqual(replay.replayed, true, "強化重複請求")
	assertEqual(session.inventory:GetCar(session.key, starter.InstanceId).UpgradeLevel, 1, "重複強化升了兩級")
	assertEqual(#successCalls, 1, "重複強化又抽了一次")

	local scrapRng = scriptedRng({ 1 })
	local scrapService = newService()
	local scrapSession = scrapService:createSession("scrap-player", {
		upgradeRng = scrapRng,
	})
	local scrapCar = scrapSession.inventory:GetCar(scrapSession.key, scrapSession.selectedInstanceId)
	scrapSession.inventory:SetUpgradeLevel(scrapSession.key, scrapCar.InstanceId, 9)
	local destroyed = scrapService:dispatch(scrapSession.key, {
		action = "Upgrade",
		attemptToken = "scrap-token-01",
		instanceId = scrapCar.InstanceId,
	})
	assertEqual(destroyed.outcome, "Destroy", "報廢結果")
	assertEqual(destroyed.removed, true, "報廢沒有移除")
	assertEqual(scrapSession.inventory:GetCar(scrapSession.key, scrapCar.InstanceId), nil, "報廢後車庫還看得到")
	assertEqual(scrapSession.selectedInstanceId, nil, "報廢後仍選著已刪除的車")
	local afterScrap = scrapService:dispatch(scrapSession.key, {
		action = "GetState",
	})
	local stillKnown = false
	for _, modelId in ipairs(afterScrap.discovered) do
		if modelId == "test_common_r0" then
			stillKnown = true
		end
	end
	assertTrue(stillKnown, "報廢後圖鑑發現紀錄被刪掉")

	local capped = scrapService:createSession("capped-player", {
		upgradeRng = scriptedRng({}),
	})
	local cappedCar = capped.inventory:GetCar(capped.key, capped.selectedInstanceId)
	capped.inventory:SetUpgradeLevel(capped.key, cappedCar.InstanceId, 10)
	local blocked = scrapService:dispatch(capped.key, {
		action = "Upgrade",
		attemptToken = "cap-token-001",
		instanceId = cappedCar.InstanceId,
	})
	assertEqual(blocked.reason, "MaxUpgradeLevel", "+10 仍可強化")
	assertEqual(capped.inventory:GetCar(capped.key, cappedCar.InstanceId).UpgradeLevel, 10, "+10 等級被改掉")
	return "強化沿用既有結果，報廢會刪車"
end

local function testRaceAuthority()
	now = 16000
	finishes = {}
	local poses = {}
	local service = newService({
		onRaceStarted = function(raceId, spec)
			poses[raceId] = spec.pose
		end,
		onRaceStepped = function(raceId, pose)
			poses[raceId] = pose
		end,
		onRaceFinished = function() end,
	})
	local session = service:createSession("race-player")
	local before = balanceOf(session)
	local started = service:dispatch(session.key, {
		action = "StartRace",
		attemptToken = "race-token-01",
		reward = 99999,
		duration = 1,
		won = true,
	})
	assertEqual(started.ok, true, "競速沒有開始")
	assertClose(started.duration, 10, "客戶端改寫了完賽時間")
	assertEqual(started.bossTarget, nil, "一般競速被當成 Boss")
	service:advanceAll(now + started.duration - 0.05)
	assertEqual(finishes[session.key], nil, "時間未到就發了獎勵")
	assertEqual(balanceOf(session), before, "時間未到金幣增加")
	service:advanceAll(now + started.duration)
	local finished = finishes[session.key]
	assertEqual(finished.reward, RaceConfig.NormalReward, "獎金不是設定值")
	assertEqual(finished.won, nil, "一般競速不該有 Boss 勝負")
	assertEqual(balanceOf(session), before + RaceConfig.NormalReward, "完成後沒有入帳")
	service:advanceAll(now + started.duration + 30)
	assertEqual(balanceOf(session), before + RaceConfig.NormalReward, "重複推進又發了一次獎金")
	local replay = service:dispatch(session.key, {
		action = "StartRace",
		attemptToken = "race-token-01",
		reward = 99999,
	})
	assertEqual(replay.replayed, true, "同一場競速可以重開")
	service:advanceAll(now + 1000)
	assertEqual(balanceOf(session), before + RaceConfig.NormalReward, "重送起跑又領了獎金")

	now += 1
	local second = service:dispatch(session.key, {
		action = "StartRace",
		attemptToken = "race-token-02",
	})
	assertEqual(second.ok, true, "結束後不能再比一場")
	local blocked = service:dispatch(session.key, {
		action = "StartRace",
		attemptToken = "race-token-03",
	})
	assertEqual(blocked.reason, PlaySessionService.Reason.RaceInProgress, "同時兩場競速")
	service:advanceAll(now + second.duration)
	assertEqual(balanceOf(session), before + RaceConfig.NormalReward * 2, "第二場沒有入帳")
	return "完賽獎金只發一次"
end

local function testBossAndOwnership()
	now = 20000
	finishes = {}
	local blocked = newService()
	local blockedSession = blocked:createSession("boss-blocked")
	local beforeBlock = balanceOf(blockedSession)
	local rejected = blocked:dispatch(blockedSession.key, {
		action = "StartBoss",
		attemptToken = "boss-blocked-01",
		duration = 1,
		reward = 99999,
		won = true,
	})
	assertEqual(rejected.ok, false, "玩家仍可開始 Boss")
	assertEqual(rejected.reason, PlaySessionService.Reason.BossDisabled, "Boss 停用應回傳 BossDisabled，而不是演算法失敗")
	assertEqual(balanceOf(blockedSession), beforeBlock, "被拒絕的 Boss 改變了金幣")
	local blockedState = blocked:dispatch(blockedSession.key, {
		action = "GetState",
	})
	assertEqual(blockedState.raceActive, false, "被拒絕的 Boss 仍進入比賽")
	local stillRaces = blocked:dispatch(blockedSession.key, {
		action = "StartRace",
		attemptToken = "after-boss-block",
	})
	assertEqual(stillRaces.ok, true, "停用 Boss 後不能開始普通競速")
	assertEqual(stillRaces.mode, "race", "普通競速被當成 Boss")

	finishes = {}
	local poses = {}
	local service = newService({
		onRaceStepped = function(raceId, pose)
			poses[raceId] = pose
		end,
	}, {
		bossEnabled = true,
	})
	local weak = service:createSession("boss-weak")
	local weakStart = service:dispatch(weak.key, {
		action = "StartBoss",
		attemptToken = "boss-weak-01",
		duration = 1,
		reward = 99999,
		won = true,
	})
	local plan = RaceConfig.describe(100, true)
	assertClose(weakStart.duration, plan.duration, "Boss 時間沒有套用緩速")
	local sampleTime = plan.slow.startDistance / plan.speed + 1.5
	service:advanceAll(now + sampleTime)
	local length = RaceConfig.trackLength()
	local expected = RaceConfig.sample(RaceConfig.distanceAtTime(sampleTime, plan.speed, plan.slow, length))
	local linear = RaceConfig.sample(RaceConfig.distanceAtTime(sampleTime, plan.speed, nil, length))
	local pose = poses[weakStart.raceId]
	assertClose(pose.y, expected.y, "伺服器車輛沒有跟著緩速模擬")
	assertTrue(
		math.abs(expected.y - linear.y) > 0.05
			or math.abs(expected.x - linear.x) > 0.05
			or math.abs(expected.z - linear.z) > 0.05,
		"緩速位置與全速相同"
	)
	service:advanceAll(now + weakStart.duration)
	assertEqual(finishes[weak.key].won, false, "慢車不該獲勝")
	assertEqual(finishes[weak.key].reward, 0, "落敗仍發了獎金")
	assertEqual(balanceOf(weak), CarConfig.TestStartingGold, "落敗改變了金幣")

	local strong = service:createSession("boss-strong")
	local created = strong.inventory:CreateCar(strong.key, "test_legendary_r0", 0)
	strong.inventory:SetUpgradeLevel(strong.key, created.InstanceId, 10)
	local strongStart = service:dispatch(strong.key, {
		action = "StartBoss",
		attemptToken = "boss-strong-1",
		instanceId = created.InstanceId,
		reward = 1,
	})
	assertTrue(strongStart.duration < RaceConfig.BossTargetTime, "高階傳說車沒有快過基準")
	service:advanceAll(now + strongStart.duration)
	assertEqual(finishes[strong.key].won, true, "伺服器沒有判定勝利")
	assertEqual(finishes[strong.key].reward, RaceConfig.BossWinReward, "勝利獎金")
	assertEqual(balanceOf(strong), CarConfig.TestStartingGold + RaceConfig.BossWinReward, "勝利金幣")

	local owner = service:createSession("owner-player")
	local thief = service:createSession("thief-player")
	local ownedId = owner.selectedInstanceId
	local stolenUpgrade = service:dispatch(thief.key, {
		action = "Upgrade",
		attemptToken = "steal-upgrade",
		instanceId = ownedId,
	})
	assertEqual(stolenUpgrade.reason, "UnknownCar", "可以強化別人的車")
	assertEqual(owner.inventory:GetCar(owner.key, ownedId).UpgradeLevel, 0, "別人的強化改到了這台車")
	local stolenRace = service:dispatch(thief.key, {
		action = "StartRace",
		attemptToken = "steal-race-01",
		instanceId = ownedId,
		reward = 99999,
	})
	assertEqual(stolenRace.reason, "UnknownCar", "可以用別人的車競速")
	local thiefBefore = balanceOf(thief)
	service:advanceAll(now + 120)
	assertEqual(balanceOf(thief), thiefBefore, "失敗的競速仍發了金幣")

	local credited = service:dispatch(thief.key, {
		action = "Credit",
		amount = 99999,
		attemptToken = "credit-token1",
	})
	assertEqual(credited.reason, PlaySessionService.Reason.UnknownAction, "客戶端可以直接加金幣")
	assertEqual(service:dispatch(thief.key, { action = "GrantTestGold" }).reason, PlaySessionService.Reason.UnknownAction, "客戶端可以領測試金幣")
	assertEqual(service:dispatch(thief.key, {
		action = "FinishRace",
		duration = 1,
		reward = 99999,
	}).reason, PlaySessionService.Reason.UnknownAction, "客戶端可以申報完賽")
	assertEqual(balanceOf(thief), thiefBefore, "非法操作改變了金幣")
	return "玩家 Remote 不能開 Boss；演算法、勝負與車輛所有權仍由伺服器決定"
end

local function testAutoRace()
	now = 30000
	finishes = {}
	local startedCount = 0
	local finishedCount = 0
	local service = newService({
		onRaceStarted = function()
			startedCount += 1
		end,
		onRaceFinished = function()
			finishedCount += 1
		end,
	})
	local session = service:createSession("auto-player")
	local carId = session.selectedInstanceId
	local before = balanceOf(session)
	local other = session.inventory:CreateCar(session.key, "test_rare_r0", 0)
	local first = service:dispatch(session.key, {
		action = "StartAutoRace",
		attemptToken = "auto-token-01",
		duration = 1,
		reward = 99999,
		won = true,
	})
	assertEqual(first.ok, true, "自動競速沒有開始")
	assertEqual(first.autoState, "Running", "狀態不是 Running")
	assertEqual(first.autoRound, 1, "第一場場次")
	assertClose(first.duration, 10, "客戶端改寫了自動競速時間")
	local pull = service:dispatch(session.key, {
		action = "Pull",
		attemptToken = "auto-pull-0001",
	})
	assertEqual(pull.ok, true, "自動競速期間不能抽車")
	assertEqual(pull.price, CarConfig.SinglePullPrice, "抽車價格被改掉")
	local denied = service:dispatch(session.key, {
		action = "Upgrade",
		attemptToken = "auto-up-locked1",
		instanceId = carId,
	})
	assertEqual(denied.reason, PlaySessionService.Reason.CarRacing, "參賽車仍可強化")
	assertEqual(session.inventory:GetCar(session.key, carId).UpgradeLevel, 0, "被拒絕的強化改了等級")
	local allowed = service:dispatch(session.key, {
		action = "Upgrade",
		attemptToken = "auto-up-other01",
		instanceId = other.InstanceId,
	})
	assertEqual(allowed.ok, true, "其他車不能強化")
	assertEqual(session.inventory:GetCar(session.key, carId).UpgradeLevel, 0, "強化其他車時改到參賽車")
	service:dispatch(session.key, {
		action = "SelectCar",
		attemptToken = "auto-select-01",
		instanceId = other.InstanceId,
	})
	local locked = service:dispatch(session.key, { action = "GetState" })
	assertEqual(locked.lockedInstanceId, carId, "選別台車就換掉參賽車")
	assertEqual(locked.selectedInstanceId, other.InstanceId, "不能預選下一台車")
	local duplicate = service:dispatch(session.key, {
		action = "StartAutoRace",
		attemptToken = "auto-token-02",
		reward = 1,
		duration = 1,
	})
	assertEqual(duplicate.replayed, true, "重複開始又開了一場")
	assertEqual(duplicate.autoRound, 1, "重複開始重置了場次")
	local blockedSingle = service:dispatch(session.key, {
		action = "StartRace",
		attemptToken = "auto-single-01",
	})
	assertEqual(blockedSingle.reason, PlaySessionService.Reason.RaceInProgress, "自動競速期間又能開單場")

	local duration = first.duration
	local t0 = now
	service:advanceAll(t0 + duration)
	service:advanceAll(t0 + duration * 2)
	service:advanceAll(t0 + duration * 3)
	local midway = service:dispatch(session.key, { action = "GetState" })
	assertEqual(midway.autoCompleted, 3, "沒有連續完成三場")
	assertEqual(midway.autoEarned, RaceConfig.NormalReward * 3, "三場累積不是 135")
	assertEqual(midway.autoState, "Running", "三場後循環停了")
	assertEqual(midway.autoRound, 4, "第四場沒有自動開始")
	assertEqual(midway.raceActive, true, "下一場沒有在跑")
	assertEqual(balanceOf(session), before - CarConfig.SinglePullPrice + RaceConfig.NormalReward * 3, "三場加抽車後的餘額")
	assertEqual(finishes[session.key].reward, RaceConfig.NormalReward, "單場獎金不是 45")
	assertEqual(finishes[session.key].autoContinue, true, "伺服器沒有接下一場")
	assertEqual(startedCount, 4, "展示車沒有每場重建")
	assertEqual(finishedCount, 3, "完賽模型沒有清理")
	local stillOne = service:dispatch(session.key, {
		action = "StartAutoRace",
		attemptToken = "auto-token-03",
	})
	assertEqual(stillOne.replayed, true, "三場後又能開第二個循環")
	assertEqual(stillOne.autoCompleted, 3, "重複開始清掉累積")

	local stop = service:dispatch(session.key, {
		action = "StopAutoRace",
		attemptToken = "auto-stop-0001",
	})
	assertEqual(stop.ok, true, "不能停止")
	assertEqual(stop.autoState, "Idle", "停止後沒有立刻回到 Idle")
	assertEqual(stop.raceActive, false, "停止後比賽還在跑")
	assertEqual(stop.lockedInstanceId, nil, "停止後沒有立刻解鎖")
	assertEqual(stop.autoCompleted, 3, "取消的場次被算進完成數")
	assertEqual(stop.autoEarned, RaceConfig.NormalReward * 3, "取消的場次發了獎")
	assertEqual(balanceOf(session), before - CarConfig.SinglePullPrice + RaceConfig.NormalReward * 3, "停止當下餘額被改掉")
	local stopAgain = service:dispatch(session.key, {
		action = "StopAutoRace",
		attemptToken = "auto-stop-0002",
	})
	assertEqual(stopAgain.replayed, true, "重複停止造成異常")
	assertEqual(stopAgain.autoState, "Idle", "重複停止改了狀態")
	assertEqual(stopAgain.autoEarned, RaceConfig.NormalReward * 3, "重複停止又結算一次")
	local balanceAtStop = balanceOf(session)
	service:advanceAll(t0 + duration * 8)
	assertEqual(balanceOf(session), balanceAtStop, "取消後仍發了獎")
	local stayed = service:dispatch(session.key, { action = "GetState" })
	assertEqual(stayed.autoState, "Idle", "取消後又開始循環")
	assertEqual(stayed.raceActive, false, "取消後場次還在跑")
	assertEqual(stayed.autoCompleted, 3, "取消後完成數增加")
	assertEqual(finishedCount, 4, "停止沒有清掉展示車")
	assertEqual(startedCount, 4, "停止後又開了下一場")
	now += 1
	local freed = service:dispatch(session.key, {
		action = "Upgrade",
		attemptToken = "auto-up-after01",
		instanceId = carId,
	})
	assertEqual(freed.ok, true, "停止後參賽車仍不能強化")
	assertTrue(freed.reason ~= PlaySessionService.Reason.CarRacing, "解鎖後仍回 CarRacing")

	now += 2
	local oldRaceId = stop.raceId
	local restarted = service:dispatch(session.key, {
		action = "StartAutoRace",
		attemptToken = "auto-restart-01",
		duration = 1,
		reward = 99999,
	})
	assertEqual(restarted.ok, true, "停止後不能立刻再開始")
	assertEqual(restarted.autoRound, 1, "新的循環不是第一場")
	assertEqual(restarted.autoCompleted, 0, "新的循環沿用了舊場次")
	assertEqual(restarted.raceActive, true, "新的場次沒有開始")
	assertTrue(restarted.raceId ~= oldRaceId, "新場次沿用了舊場次編號")
	assertTrue(type(restarted.duration) == "number" and restarted.duration >= RaceConfig.MinDuration, "重新開始沒有伺服器時間")
	assertTrue(math.abs(restarted.duration - 1) > 1, "客戶端改寫了重新開始的時間")
	local restartBalance = balanceOf(session)
	service:advanceAll(now + 5)
	assertEqual(balanceOf(session), restartBalance, "舊場次的延遲結算發了獎")
	local restartStop = service:dispatch(session.key, {
		action = "StopAutoRace",
		attemptToken = "auto-restart-stop",
	})
	assertEqual(restartStop.autoState, "Idle", "新場次不能立刻停止")
	assertEqual(restartStop.raceActive, false, "新場次停止後還在跑")
	assertEqual(balanceOf(session), restartBalance, "立刻停止的新場次發了獎")
	service:advanceAll(now + restarted.duration + 5)
	assertEqual(balanceOf(session), restartBalance, "已取消的新場次後來仍發了獎")
	local quiet = service:dispatch(session.key, { action = "GetState" })
	assertEqual(quiet.autoState, "Idle", "取消的新場次又自動開始")
	assertEqual(quiet.raceActive, false, "取消後仍有進行中的場次")

	now = 80000
	local ghost = service:createSession("auto-ghost")
	local ghostId = ghost.selectedInstanceId
	local ghostBefore = balanceOf(ghost)
	local ghostStart = service:dispatch(ghost.key, {
		action = "StartAutoRace",
		attemptToken = "auto-ghost-01",
		reward = 99999,
	})
	assertEqual(ghostStart.ok, true, "缺車測試沒有開始")
	ghost.inventory:RemoveCar(ghost.key, ghostId)
	service:advanceAll(now + ghostStart.duration)
	assertEqual(balanceOf(ghost), ghostBefore, "車被刪掉後仍發了獎")
	local ghostState = service:dispatch(ghost.key, { action = "GetState" })
	assertEqual(ghostState.autoState, "Idle", "缺車後還在循環")
	assertEqual(ghostState.raceActive, false, "缺車後場次還在跑")

	now = 90000
	local leaver = service:createSession("auto-leaver")
	local wallet = leaver.wallet
	local leaveKey = leaver.key
	local leaveBefore = wallet:GetBalance(leaveKey)
	local leaveStart = service:dispatch(leaveKey, {
		action = "StartAutoRace",
		attemptToken = "auto-leave-01",
	})
	assertEqual(leaveStart.ok, true, "離線測試沒有開始")
	service:removeSession(leaveKey)
	service:advanceAll(now + 120)
	assertEqual(wallet:GetBalance(leaveKey), leaveBefore, "離線後仍發了獎")
	local rejoined = service:createSession(leaveKey)
	local rejoinedState = service:dispatch(rejoined.key, { action = "GetState" })
	assertEqual(rejoinedState.autoState, "Idle", "重進後繼承了舊循環")
	assertEqual(rejoinedState.raceActive, false, "重進後還有舊場次")
	assertEqual(rejoinedState.autoCompleted, 0, "重進後繼承了完成場次")

	now = 100000
	local paced = service:createSession("auto-paced")
	local pacedStart = service:dispatch(paced.key, {
		action = "StartAutoRace",
		attemptToken = "auto-rate-0001",
	})
	assertEqual(pacedStart.ok, true, "頻率測試沒有開始")
	local pacedBefore = balanceOf(paced)
	service:dispatch(paced.key, {
		action = "StopAutoRace",
		attemptToken = "auto-rate-stop1",
	})
	service:advanceAll(now + pacedStart.duration)
	assertEqual(balanceOf(paced), pacedBefore, "停止後把未完成場次結算了")
	local resumed = service:dispatch(paced.key, {
		action = "StartAutoRace",
		attemptToken = "auto-rate-0002",
	})
	assertEqual(resumed.ok, true, "停止後不能立刻再開始")
	assertEqual(resumed.autoRound, 1, "新的循環不是第一場")
	assertEqual(resumed.autoCompleted, 0, "新的循環沿用了舊場次")
	service:dispatch(paced.key, {
		action = "StopAutoRace",
		attemptToken = "auto-rate-stop2",
	})
	service:advanceAll(now + pacedStart.duration + 80)
	assertEqual(balanceOf(paced), pacedBefore, "第二次取消的場次發了獎")
	return "背景自動競速連續結算，立即停止不發獎，鎖定參賽車，離線不再發獎"
end

local function testLiveServerHasNoTestGrant()
	now = 24000
	local service = PlaySessionService.new({
		isStudio = false,
		clock = function()
			return now
		end,
	})
	local session = service:createSession("live-player")
	assertEqual(balanceOf(session), 0, "正式環境發了測試金幣")
	assertEqual(#session.inventory:ListCars(session.key), 0, "正式環境發了起始車")
	local pull = service:dispatch(session.key, {
		action = "Pull",
		attemptToken = "live-pull-01",
	})
	assertEqual(pull.reason, "InsufficientGold", "沒金幣仍抽到車")
	assertEqual(balanceOf(session), 0, "失敗抽車改變了餘額")
	local leave = service:createSession("leave-player")
	service:dispatch(leave.key, {
		action = "Credit",
		amount = 50000,
	})
	assertEqual(balanceOf(leave), 0, "正式環境被遠端加錢")
	return "測試金幣只在 Studio 發放"
end

local function testSceneAndVisuals()
	if not runningInRoblox() then
		return "不在 Roblox，略過場景與模型"
	end
	local PlaygroundBuilder = importServer("PlaygroundBuilder")
	local CarVisualFactory = importShared("CarVisualFactory")
	local folder, _created = PlaygroundBuilder.build(workspace)
	local again, createdAgain = PlaygroundBuilder.build(workspace)
	assertEqual(folder, again, "重複建立了另一個場景")
	assertEqual(createdAgain, false, "完整場景被重建")
	assertEqual(folder:GetAttribute("Complete"), true, "場景未完成")
	assertTrue(folder:FindFirstChild("PlayerSpawn") ~= nil, "沒有出生點")
	assertEqual(folder:FindFirstChild("GachaMachine"), nil, "舊抽車機還在")
	assertTrue(folder:FindFirstChild("UpgradeBench") ~= nil, "沒有強化工作台")
	local bossGate = folder:FindFirstChild("BossGate")
	assertTrue(bossGate ~= nil, "Boss 入口模型被刪除")
	assertEqual(bossGate:GetAttribute("Hidden"), true, "Boss 入口沒有隱藏")
	assertEqual(bossGate.Transparency, 1, "Boss 入口仍然看得到")
	assertEqual(bossGate:FindFirstChildWhichIsA("ProximityPrompt", true), nil, "Boss 入口仍可互動")
	local garageSign = folder:FindFirstChild("GarageSign")
	assertTrue(garageSign ~= nil, "車庫展示被刪除")
	assertEqual(garageSign:FindFirstChildWhichIsA("ProximityPrompt", true), nil, "車庫展示台仍有互動入口")
	assertTrue(folder:FindFirstChild("GaragePad1") ~= nil, "沒有車庫展示位")
	local dealer = folder:FindFirstChild("R0Dealer")
	assertTrue(dealer ~= nil and dealer:FindFirstChild("LaoPo", true) ~= nil, "沒有老破")
	assertEqual(dealer:FindFirstChild("PriceSign", true), nil, "攤位還留著價格牌")
	assertEqual(dealer:FindFirstChild("NameSign", true), nil, "攤位還留著店名")
	assertTrue(dealer:FindFirstChild("OilDrum", true) ~= nil, "沒有廢土油桶")
	assertTrue(dealer:FindFirstChild("Canopy", true) ~= nil, "沒有破棚")
	local stallText = 0
	for _, descendant in ipairs(dealer:GetDescendants()) do
		local onPoolSign = descendant.Name == "PoolSign" or descendant:FindFirstAncestor("PoolSign") ~= nil
		if onPoolSign then
			continue
		end
		if descendant:IsA("SurfaceGui") then
			stallText += 1
		elseif descendant:IsA("TextLabel") and descendant:FindFirstAncestor("Nameplate") == nil then
			stallText += 1
		end
	end
	assertEqual(stallText, 0, "攤位上還有字")
	local poolSign = dealer:FindFirstChild("PoolSign", true)
	assertTrue(poolSign ~= nil and poolSign:IsA("BasePart"), "沒有獎池告示牌")
	local poolLabel = poolSign:FindFirstChildWhichIsA("TextLabel", true)
	assertTrue(poolLabel ~= nil and poolLabel.Text == "NO LICENSE\nPRIZE POOL", "告示牌文字不對")
	local dealerPrompts = 0
	local dealerPrompt = nil
	for _, descendant in ipairs(dealer:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			dealerPrompts += 1
			dealerPrompt = descendant
		end
	end
	assertEqual(dealerPrompts, 1, "車商互動入口不是一個")
	assertEqual(dealerPrompt.KeyboardKeyCode, Enum.KeyCode.E, "車商不是按 E")
	assertEqual(dealerPrompt.ObjectText, "Rusty", "互動對象不是老破")
	assertEqual(dealerPrompt.Parent:GetAttribute("Station"), "R0Dealer", "車商站點不對")
	local npc = dealer:FindFirstChild("LaoPo", true)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	assertTrue(humanoid ~= nil, "老破不是 Humanoid")
	assertEqual(humanoid.DisplayName, "Rusty", "老破的顯示名稱被改成階級")
	assertEqual(humanoid.RigType, Enum.HumanoidRigType.R15, "老破不是官方 R15")
	local root = npc:FindFirstChild("HumanoidRootPart")
	assertTrue(root ~= nil and root:IsA("BasePart") and root.Anchored == true, "老破沒有固定站好")
	local _, bounds = npc:GetBoundingBox()
	assertTrue(bounds.Y >= 4.8 and bounds.Y <= 6.6, "老破身高不在玩家範圍：" .. tostring(bounds.Y))
	local stall = dealer:FindFirstChild("StallTop")
	assertTrue(stall ~= nil and stall:IsA("BasePart"), "沒有攤位桌面")
	assertTrue(stall.Position.Z < root.Position.Z - 2, "攤位沒有在老破後面")
	local nameplate = npc:FindFirstChild("Nameplate", true)
	assertTrue(nameplate ~= nil, "沒有老破名牌")
	local idle = npc:FindFirstChild("MerchantIdle")
	assertTrue(idle ~= nil and idle:IsA("Animation") and string.find(idle.AnimationId, "507766666") ~= nil, "沒有官方待機")
	local dealerCount = 0
	for _, child in ipairs(folder:GetChildren()) do
		if child.Name == "R0Dealer" then
			dealerCount += 1
		end
	end
	assertEqual(dealerCount, 1, "重複建立了車商")
	local upgradePrompt = folder:FindFirstChild("UpgradeBench"):FindFirstChildWhichIsA("ProximityPrompt", true)
	local racePrompt = folder:FindFirstChild("RaceKiosk"):FindFirstChildWhichIsA("ProximityPrompt", true)
	assertTrue(upgradePrompt ~= nil, "強化台沒有互動")
	assertTrue(racePrompt ~= nil, "競速入口沒有互動")
	assertEqual(racePrompt.ActionText, "Open Race", "競速入口不該直接開賽")
	local startLine = folder:FindFirstChild("RaceStart", true)
	assertTrue(startLine ~= nil, "沒有起點")
	local finishLine = folder:FindFirstChild("RaceFinish", true)
	assertTrue(finishLine ~= nil, "沒有終點")
	assertEqual(folder:FindFirstChild("StartSign", true), nil, "起跑文字還在")
	assertEqual(folder:FindFirstChild("FinishSign", true), nil, "終點文字還在")
	assertEqual(startLine:FindFirstChildWhichIsA("BillboardGui"), nil, "起點還有浮動文字")
	assertEqual(finishLine:FindFirstChildWhichIsA("BillboardGui"), nil, "終點還有浮動文字")
	local function cornerY(piece: BasePart, xSign: number): number
		local half = piece.Size * 0.5
		return (piece.CFrame * Vector3.new(xSign * half.X, half.Y, 0)).Y
	end
	local deck = folder:FindFirstChild("SweeperDeck7", true)
	local leftShoulder = folder:FindFirstChild("SweeperShoulderL7", true)
	local rightShoulder = folder:FindFirstChild("SweeperShoulderR7", true)
	assertTrue(deck ~= nil and leftShoulder ~= nil and rightShoulder ~= nil, "彎道凹槽零件不存在")
	local deckLeft = cornerY(deck, -1)
	local deckRight = cornerY(deck, 1)
	assertTrue(math.abs(deckLeft - deckRight) < 0.05, "彎道中心被做成單側屋頂")
	local deckTop = (deckLeft + deckRight) * 0.5
	local function topCenter(piece: BasePart): number
		return (piece.CFrame * Vector3.new(0, piece.Size.Y * 0.5, 0)).Y
	end
	assertTrue(topCenter(leftShoulder) > deckTop + 0.12, "左側沒有高於槽底")
	assertTrue(topCenter(rightShoulder) > deckTop + 0.12, "右側沒有高於槽底")
	assertTrue(math.abs(topCenter(leftShoulder) - topCenter(rightShoulder)) < 0.05, "左右邊緣高度不一致")
	local displays = 0
	for _, child in ipairs(folder:GetChildren()) do
		if child.Name == "DisplayCar" then
			displays += 1
			assertEqual(child:GetAttribute("DisplayOnly"), true, "展示車被當成玩家資料")
		end
	end
	assertEqual(displays, 5, "展示車數量")

	local bucket = Instance.new("Folder")
	bucket.Name = "CarForgeTaxVisualTest"
	bucket.Parent = workspace
	local common = CarVisualFactory.build({
		modelId = "test_common_r0",
		qualityId = "Common",
		upgradeLevel = 0,
		displayName = "普通測試車",
	})
	common.Parent = bucket
	local legendary = CarVisualFactory.build({
		modelId = "test_legendary_r0",
		qualityId = "Legendary",
		upgradeLevel = 3,
		displayName = "傳說測試車",
	})
	legendary.Parent = bucket
	for _, name in ipairs({
		"Body",
		"Cabin",
		"Windshield",
		"WheelFL",
		"WheelFR",
		"WheelRL",
		"WheelRR",
		"HeadLightL",
		"HeadLightR",
		"TailLightL",
		"TailLightR",
	}) do
		assertTrue(common:FindFirstChild(name) ~= nil, "玩具車缺少 " .. name)
	end
	local size = common:GetExtentsSize()
	assertTrue(size.X >= 1.3 and size.X <= 2, "車寬超出概念尺寸")
	assertTrue(size.Y >= 0.8 and size.Y <= 1.6, "車高超出概念尺寸")
	assertTrue(size.Z >= 2.4 and size.Z <= 3.4, "車長超出概念尺寸")
	assertEqual(common:FindFirstChild("Body").Color, CarVisualFactory.qualityColor("Common"), "普通車顏色")
	assertEqual(legendary:FindFirstChild("Body").Color, CarVisualFactory.qualityColor("Legendary"), "傳說車顏色")
	assertEqual(common:FindFirstChild("LegendarySpark", true), nil, "普通車不該有粒子")
	assertTrue(legendary:FindFirstChild("LegendarySpark", true) ~= nil, "傳說車沒有粒子")
	assertTrue(legendary:FindFirstChild("LegendaryGlow", true) ~= nil, "傳說車沒有發光")
	bucket:Destroy()
	return "場景可重複建立，玩具車尺寸與顏色正確"
end

local function hasModel(list, modelId: string): boolean
	if type(list) ~= "table" then
		return false
	end
	for _, value in ipairs(list) do
		if value == modelId then
			return true
		end
	end
	return false
end

local function testAutoSell()
	local AutoSellConfig = importShared("AutoSellConfig")
	now = 32000
	local service = newService()
	local session = service:createSession("sell-player", {
		gachaRng = scriptedRng({ 1, 1, 1, 1, 51, 1, 81, 1, 1, 1, 96, 1, 100, 1, 1, 1 }),
	})
	local starterId = session.selectedInstanceId

	local function assertQualities(actual, expected, message: string)
		assertEqual(type(actual), "table", message .. "不是清單")
		assertEqual(#actual, #expected, message)
		for index, qualityId in ipairs(expected) do
			assertEqual(actual[index], qualityId, message)
		end
	end

	local state = service:dispatch(session.key, { action = "GetState" })
	assertEqual(state.autoSell.enabled, false, "自動販賣預設不是關閉")
	assertQualities(state.autoSell.qualities, {}, "預設仍有勾選")
	assertQualities(state.autoSell.keeps, { "Common", "Uncommon", "Rare", "Epic", "Legendary" }, "預設沒有全部保留")
	local tampered = service:dispatch(session.key, {
		action = "GetState",
		autoSell = { enabled = true, qualities = { "Legendary" }, maxQuality = "Legendary" },
		price = 1,
	})
	assertEqual(tampered.autoSell.enabled, false, "客戶端改寫了自動販賣")
	assertQualities(tampered.autoSell.qualities, {}, "客戶端改寫了勾選")

	local before = balanceOf(session)
	local kept = service:dispatch(session.key, {
		action = "Pull",
		attemptToken = "sell-off",
	})
	assertEqual(kept.ok, true, "關閉時抽車失敗")
	assertEqual(kept.sold, false, "關閉時自動賣掉")
	assertEqual(kept.balance, before - 500, "關閉時金額")
	assertEqual(#session.inventory:ListCars(session.key), 2, "關閉時新車不在車庫")
	assertTrue(session.inventory:GetCar(session.key, kept.instanceId) ~= nil, "關閉時的車被刪掉")

	assertEqual(AutoSellConfig.price(0, "Common"), 100, "普通售價")
	assertEqual(AutoSellConfig.price(0, "Uncommon"), 175, "優良售價")
	assertEqual(AutoSellConfig.price(0, "Rare"), 300, "稀有售價")
	assertEqual(AutoSellConfig.price(0, "Epic"), 650, "史詩售價")
	assertEqual(AutoSellConfig.price(0, "Legendary"), 2000, "傳說售價")

	local legacy = service:dispatch(session.key, {
		action = "SetAutoSell",
		attemptToken = "sell-legacy-threshold",
		enabled = true,
		maxQuality = "Legendary",
		confirmAll = true,
	})
	assertEqual(legacy.reason, PlaySessionService.Reason.InvalidRequest, "舊的最高品質門檻仍可設定")
	assertEqual(legacy.autoSell.enabled, false, "舊門檻改寫了設定")

	local epicOnly = service:dispatch(session.key, {
		action = "SetAutoSell",
		attemptToken = "sell-epic-only",
		qualities = { "Epic" },
	})
	assertEqual(epicOnly.ok, true, "不能只勾史詩")
	assertQualities(epicOnly.autoSell.sells, { "Epic" }, "只勾史詩卻連帶較低品質")
	assertQualities(epicOnly.autoSell.keeps, { "Common", "Uncommon", "Rare", "Legendary" }, "只勾史詩時保留清單不對")

	local priced = service:dispatch(session.key, {
		action = "SetAutoSell",
		attemptToken = "sell-set-gap",
		qualities = { "Common", "Rare" },
		price = 999999,
		sellPrice = 1,
		maxQuality = "Legendary",
	})
	assertEqual(priced.ok, true, "不能同時勾普通與稀有")
	assertEqual(priced.autoSell.enabled, true, "有勾選卻顯示關閉")
	assertQualities(priced.autoSell.qualities, { "Common", "Rare" }, "勾選被改成連續門檻")
	assertQualities(priced.autoSell.sells, { "Common", "Rare" }, "會賣的品質不對")
	assertQualities(priced.autoSell.keeps, { "Uncommon", "Epic", "Legendary" }, "中間品質被自動勾上")

	local junk = service:dispatch(session.key, {
		action = "SetAutoSell",
		attemptToken = "sell-junk",
		qualities = { "Common", "Mythic" },
	})
	assertEqual(junk.reason, PlaySessionService.Reason.InvalidRequest, "不存在的品質被接受")
	assertQualities(junk.autoSell.qualities, { "Common", "Rare" }, "錯誤清單改寫了原勾選")

	now += 3
	local common = service:dispatch(session.key, {
		action = "Pull",
		attemptToken = "sell-common",
	})
	assertEqual(common.sold, true, "普通車沒有賣出")
	assertEqual(common.qualityId, "Common", "賣出後抽車結果被換成別的品質")
	assertEqual(common.modelId, "test_common_r0", "賣出後車款被換掉")
	assertEqual(common.sellPrice, 100, "客戶端指定了售價")
	assertEqual(common.balance, priced.balance - 400, "普通車淨支出不是 400")
	assertEqual(session.inventory:GetCar(session.key, common.instanceId), nil, "賣掉的車還在車庫")
	assertEqual(#session.inventory:ListCars(session.key), 2, "其他車輛被一起賣掉")
	assertTrue(hasModel(common.discovered, "test_common_r0"), "賣掉後圖鑑沒有普通車")

	local replay = service:dispatch(session.key, {
		action = "Pull",
		attemptToken = "sell-common",
	})
	assertEqual(replay.replayed, true, "同一請求沒有視為重送")
	assertEqual(replay.balance, common.balance, "重送又入帳")
	assertEqual(replay.sold, true, "重送把出售狀態弄丟")
	assertEqual(replay.modelId, common.modelId, "重送改了抽車結果")
	assertEqual(#session.inventory:ListCars(session.key), 2, "重送又刪了一台車")

	now += 3
	local uncommon = service:dispatch(session.key, {
		action = "Pull",
		attemptToken = "sell-uncommon",
	})
	assertEqual(uncommon.sold, false, "沒勾選的優良車被賣掉")
	assertEqual(uncommon.qualityId, "Uncommon", "優良車結果不對")
	assertEqual(uncommon.balance, common.balance - 500, "保留的車仍退了錢")
	assertTrue(session.inventory:GetCar(session.key, uncommon.instanceId) ~= nil, "保留的優良車不在車庫")

	now += 3
	local rare = service:dispatch(session.key, {
		action = "Pull",
		attemptToken = "sell-rare",
	})
	assertEqual(rare.sold, true, "稀有車沒有賣出")
	assertEqual(rare.qualityId, "Rare", "稀有結果被換掉")
	assertEqual(rare.sellPrice, 300, "稀有售價不對")
	assertEqual(rare.balance, uncommon.balance - 500 + 300, "稀有回收金額不對")
	assertEqual(session.inventory:GetCar(session.key, rare.instanceId), nil, "稀有車還在車庫")
	assertTrue(session.inventory:GetCar(session.key, uncommon.instanceId) ~= nil, "中間沒勾的優良車被一起賣掉")

	local narrowed = service:dispatch(session.key, {
		action = "SetAutoSell",
		attemptToken = "sell-uncheck-common",
		qualities = { "Rare" },
	})
	assertEqual(narrowed.ok, true, "取消勾選沒有更新")
	assertQualities(narrowed.autoSell.qualities, { "Rare" }, "取消普通後仍一起勾著")
	assertQualities(narrowed.autoSell.keeps, { "Common", "Uncommon", "Epic", "Legendary" }, "取消後保留清單不對")

	now += 3
	local commonKept = service:dispatch(session.key, {
		action = "Pull",
		attemptToken = "sell-common-after-uncheck",
	})
	assertEqual(commonKept.sold, false, "取消勾選後仍賣掉普通車")
	assertEqual(commonKept.qualityId, "Common", "取消後的普通車結果不對")
	assertEqual(commonKept.balance, rare.balance - 500, "取消後的普通車金額不對")
	assertTrue(session.inventory:GetCar(session.key, commonKept.instanceId) ~= nil, "取消勾選後的普通車不在車庫")

	now += 3
	local epic = service:dispatch(session.key, {
		action = "Pull",
		attemptToken = "sell-epic",
	})
	assertEqual(epic.sold, false, "沒勾選的史詩被賣掉")
	assertEqual(epic.qualityId, "Epic", "史詩結果被換掉")
	assertEqual(epic.balance, commonKept.balance - 500, "保留史詩時金額不對")
	assertTrue(session.inventory:GetCar(session.key, epic.instanceId) ~= nil, "史詩沒有留在車庫")
	assertTrue(hasModel(epic.discovered, "test_epic_r0"), "史詩沒有記入圖鑑")

	local denied = service:dispatch(session.key, {
		action = "SetAutoSell",
		attemptToken = "sell-legendary-denied",
		qualities = { "Rare", "Legendary" },
		confirmLegendary = false,
		price = 1,
	})
	assertEqual(denied.reason, PlaySessionService.Reason.NeedsConfirm, "傳說沒有要求確認")
	assertQualities(denied.autoSell.qualities, { "Rare" }, "未確認卻勾上傳說")
	assertEqual(denied.autoSell.enabled, true, "未確認把其他勾選清掉")

	local armed = service:dispatch(session.key, {
		action = "SetAutoSell",
		attemptToken = "sell-legendary-arm",
		qualities = { "Rare", "Legendary" },
		confirmLegendary = true,
		sellPrice = 999999,
	})
	assertEqual(armed.autoSell.enabled, true, "確認後沒有啟用")
	assertQualities(armed.autoSell.qualities, { "Rare", "Legendary" }, "確認後把其他品質改掉")
	assertQualities(armed.autoSell.keeps, { "Common", "Uncommon", "Epic" }, "確認傳說時自動勾了較低品質")
	now += 3
	local soldLegendary = service:dispatch(session.key, {
		action = "Pull",
		attemptToken = "sell-legendary",
	})
	assertEqual(soldLegendary.sold, true, "確認後沒有賣掉傳說")
	assertEqual(soldLegendary.qualityId, "Legendary", "傳說出售後結果被換掉")
	assertEqual(soldLegendary.sellPrice, 2000, "傳說售價不對")
	assertEqual(soldLegendary.balance, armed.balance - 500 + 2000, "傳說回收金額不對")
	assertEqual(session.inventory:GetCar(session.key, soldLegendary.instanceId), nil, "已售傳說還在車庫")
	assertTrue(hasModel(soldLegendary.discovered, "test_legendary_r0"), "已售傳說從圖鑑消失")
	assertTrue(session.inventory:GetCar(session.key, epic.instanceId) ~= nil, "沒勾的史詩被自動賣掉")
	assertTrue(session.inventory:GetCar(session.key, kept.instanceId) ~= nil, "原先持有的車被賣掉")
	assertTrue(session.inventory:GetCar(session.key, starterId) ~= nil, "起始測試車被賣掉")

	local dropped = service:dispatch(session.key, {
		action = "SetAutoSell",
		attemptToken = "sell-uncheck-legendary",
		qualities = { "Rare" },
	})
	assertEqual(dropped.ok, true, "取消傳說沒有更新")
	assertQualities(dropped.autoSell.qualities, { "Rare" }, "取消傳說後仍勾著")

	local cleared = service:dispatch(session.key, {
		action = "SetAutoSell",
		attemptToken = "sell-clear",
		qualities = {},
	})
	assertEqual(cleared.ok, true, "全部取消失敗")
	assertEqual(cleared.autoSell.enabled, false, "全部不選仍是開啟")
	assertQualities(cleared.autoSell.qualities, {}, "全部不選仍有勾選")
	assertQualities(cleared.autoSell.keeps, { "Common", "Uncommon", "Rare", "Epic", "Legendary" }, "全部不選沒有全部保留")
	now += 3
	local afterClear = service:dispatch(session.key, {
		action = "Pull",
		attemptToken = "sell-after-clear",
	})
	assertEqual(afterClear.sold, false, "全部不選仍賣掉普通車")
	assertEqual(afterClear.qualityId, "Common", "清空後的抽車結果不對")
	assertEqual(afterClear.balance, soldLegendary.balance - 500, "清空後仍退了錢")
	assertTrue(session.inventory:GetCar(session.key, afterClear.instanceId) ~= nil, "清空後的車不在車庫")

	local direct = service:dispatch(session.key, {
		action = "SellCar",
		attemptToken = "sell-direct",
		instanceId = kept.instanceId,
		price = 100,
	})
	assertEqual(direct.reason, PlaySessionService.Reason.UnknownAction, "客戶端可以直接賣車")
	assertTrue(session.inventory:GetCar(session.key, kept.instanceId) ~= nil, "直接賣車把舊車刪了")

	service:removeSession(session.key)
	local returned = service:createSession(session.key)
	local reset = service:dispatch(returned.key, { action = "GetState" })
	assertEqual(reset.autoSell.enabled, false, "離線後仍保留自動販賣")

	now = 36000
	local raceService = newService()
	local racer = raceService:createSession("race-sell-player", {
		gachaRng = scriptedRng({ 1, 1 }),
	})
	local starterId = racer.selectedInstanceId
	local started = raceService:dispatch(racer.key, {
		action = "StartAutoRace",
		attemptToken = "sell-race",
	})
	assertEqual(started.ok, true, "競速沒有開始")
	raceService:dispatch(racer.key, {
		action = "SetAutoSell",
		attemptToken = "sell-race-setting",
		qualities = { "Common" },
	})
	now += 3
	local during = raceService:dispatch(racer.key, {
		action = "Pull",
		attemptToken = "sell-during-race",
	})
	assertEqual(during.sold, true, "新抽到的普通車沒有賣")
	assertEqual(during.sellPrice, 100, "競速中的新車售價不對")
	assertTrue(racer.inventory:GetCar(racer.key, starterId) ~= nil, "競速中的車被賣掉")
	assertEqual(started.lockedInstanceId or started.autoInstanceId, starterId, "鎖定的不是參賽車")
	local upgrade = raceService:dispatch(racer.key, {
		action = "Upgrade",
		attemptToken = "sell-upgrade-racing",
		instanceId = starterId,
	})
	assertEqual(upgrade.reason, PlaySessionService.Reason.CarRacing, "參賽車可以被改動")

	now = 38000
	local dry = PlaySessionService.new({
		isStudio = false,
		clock = function()
			return now
		end,
	})
	local broke = dry:createSession("broke-sell-player")
	dry:dispatch(broke.key, {
		action = "SetAutoSell",
		attemptToken = "broke-setting",
		qualities = { "Common" },
	})
	local failed = dry:dispatch(broke.key, {
		action = "Pull",
		attemptToken = "broke-pull",
	})
	assertEqual(failed.reason, "InsufficientGold", "沒金幣仍抽到車")
	assertEqual(failed.sold, false, "沒抽到車卻販賣")
	assertEqual(balanceOf(broke), 0, "失敗抽車產生金幣")
	assertEqual(#broke.inventory:ListCars(broke.key), 0, "失敗抽車產生車輛")
	return "自動販賣只處理新抽到的車，售價與重送都由伺服器決定"
end

function Tests.run()
	local cases = {
		{ "競速時間、短圈與 Boss 緩速", testRaceMath },
		{ "Studio 起始車與抽車", testStudioStarterAndPull },
		{ "免費強化、報廢與 +10", testUpgradeRules },
		{ "單場競速發獎", testRaceAuthority },
		{ "背景自動競速", testAutoRace },
		{ "Boss、所有權與拒絕加金幣", testBossAndOwnership },
		{ "正式環境不發測試資源", testLiveServerHasNoTestGrant },
		{ "場景與玩具車模型", testSceneAndVisuals },
		{ "自動販賣", testAutoSell },
	}

	local results = {}
	local passed = 0
	local failed = 0
	for _, case in ipairs(cases) do
		local name, fn = case[1], case[2]
		local ok, detail = pcall(fn)
		if ok then
			passed += 1
		else
			failed += 1
		end
		table.insert(results, {
			name = name,
			ok = ok,
			detail = if ok then detail else tostring(detail),
		})
	end
	return {
		passed = passed,
		failed = failed,
		results = results,
	}
end

local function report(summary)
	print(string.format("CARFORGETAX_PROTOTYPE passed=%d failed=%d", summary.passed, summary.failed))
	for _, result in ipairs(summary.results) do
		local status = if result.ok then "PASS" else "FAIL"
		print(string.format("[%s] %s %s", status, result.name, result.detail or ""))
	end
end

if not runningInRoblox() then
	local summary = Tests.run()
	report(summary)
	local loaded, process = pcall(require, "@lune/process")
	if loaded and process ~= nil and type(process.exit) == "function" then
		process.exit(summary.failed > 0 and 1 or 0)
	end
end

return Tests
