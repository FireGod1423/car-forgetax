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
	assertEqual(plain.duration, 40, "普通車基準時間")
	assertClose(boss.duration - plain.duration, 0.6, "緩速應多 0.6 秒")
	assertEqual(boss.won, false, "40.6 秒不該贏過 35 秒")
	assertEqual(boss.reward, RaceConfig.BossLoseReward, "落敗獎金")
	local strong = RaceConfig.describe(maxPower, true)
	assertEqual(strong.won, true, "最高性能應贏過 Boss")
	assertTrue(strong.duration < RaceConfig.BossTargetTime, "勝利時間")
	assertEqual(RaceConfig.bossVictory(35), false, "剛好 35 秒不算勝利")
	assertEqual(RaceConfig.bossVictory(34.999), true, "低於 35 秒才勝利")

	local length = RaceConfig.trackLength()
	local duringSlow = boss.slow.startDistance / boss.speed + 1.5
	local slowed = RaceConfig.distanceAtTime(duringSlow, boss.speed, boss.slow, length)
	local linear = RaceConfig.distanceAtTime(duringSlow, boss.speed, nil, length)
	assertTrue(slowed < linear, "緩速期間行進距離沒有變短")

	local markers = RaceConfig.markers()
	local loop = RaceConfig.sample(markers.straightEnd + RaceConfig.loopLength() * 0.5)
	assertEqual(loop.segment, "Loop", "迴圈段")
	assertClose(loop.y, RaceConfig.Layout.originY + RaceConfig.Layout.radius * 2, "迴圈頂端高度")
	local jump = RaceConfig.sample(markers.afterEnd + RaceConfig.Layout.jump * 0.5)
	assertEqual(jump.segment, "Jump", "跳台段")
	assertClose(jump.y, RaceConfig.Layout.originY + RaceConfig.Layout.jumpHeight, "跳台高度")
	local weights = UpgradeConfig.getWeights(8)
	assertEqual(weights.GreatSuccess, 1, "+8 大成功權重被改掉")
	assertEqual(UpgradeConfig.sumWeights(9), 100, "+9 權重總和")
	assertEqual(UpgradeConfig.getWeights(9).GreatSuccess, 0, "+9 大成功權重")
	assertEqual(CarConfig.SinglePullPrice, 500, "抽車價格")
	return "時間 20～40 秒，Boss 緩速生效"
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
	assertClose(started.duration, 40, "客戶端改寫了完賽時間")
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
	assertTrue(math.abs(expected.y - linear.y) > 0.05 or math.abs(expected.x - linear.x) > 0.05, "緩速位置與全速相同")
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
	assertTrue(folder:FindFirstChild("GachaMachine") ~= nil, "沒有抽車機")
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
	local gachaPrompt = folder:FindFirstChild("GachaMachine"):FindFirstChildWhichIsA("ProximityPrompt", true)
	local upgradePrompt = folder:FindFirstChild("UpgradeBench"):FindFirstChildWhichIsA("ProximityPrompt", true)
	local racePrompt = folder:FindFirstChild("RaceKiosk"):FindFirstChildWhichIsA("ProximityPrompt", true)
	assertTrue(gachaPrompt ~= nil, "抽車機沒有互動")
	assertTrue(upgradePrompt ~= nil, "強化台沒有互動")
	assertTrue(racePrompt ~= nil, "競速入口沒有互動")
	assertEqual(racePrompt.ActionText, "開啟競速", "競速入口不該直接開賽")
	assertTrue(folder:FindFirstChild("RaceStart", true) ~= nil, "沒有起點")
	assertTrue(folder:FindFirstChild("RaceFinish", true) ~= nil, "沒有終點")
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

function Tests.run()
	local cases = {
		{ "競速時間、跳台與 Boss 緩速", testRaceMath },
		{ "Studio 起始車與抽車", testStudioStarterAndPull },
		{ "免費強化、報廢與 +10", testUpgradeRules },
		{ "單場競速發獎", testRaceAuthority },
		{ "Boss、所有權與拒絕加金幣", testBossAndOwnership },
		{ "正式環境不發測試資源", testLiveServerHasNoTestGrant },
		{ "場景與玩具車模型", testSceneAndVisuals },
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
