-- 車輛與抽車測試。每次都建立新的錢包和庫存，不會寫入正式玩家資料。
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
local CarCatalog = importShared("CarCatalog")
local PoolConfig = importShared("PoolConfig")
local RandomSource = importShared("RandomSource")
local GoldWallet = importServer("GoldWallet")
local CarInventoryService = importServer("CarInventoryService")
local CarGachaService = importServer("CarGachaService")

local Tests = {}

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

local function scriptedRng(values)
	local index = 0
	local rng = {
		NextInteger = function(_self, minValue, maxValue)
			index += 1
			local value = values[index]
			if type(value) ~= "number" or value < minValue or value > maxValue then
				error(string.format(
					"腳本隨機數越界：第 %d 次，值 %s，範圍 %d-%d",
					index,
					tostring(value),
					minValue,
					maxValue
				))
			end
			return value
		end,
	}
	return rng, function()
		return index
	end
end

local function newServices(options)
	options = options or {}
	local wallet = GoldWallet.new()
	local inventory = options.inventory
	if inventory == nil then
		inventory = CarInventoryService.new({
			now = options.now or function()
				return 1700000000
			end,
			newId = options.newId,
		})
	end
	local gacha = CarGachaService.new({
		inventory = inventory,
		wallet = wallet,
		rng = options.rng,
		catalog = options.catalog,
	})
	return wallet, inventory, gacha
end

local function testWeights()
	local expected = {
		{ id = "Common", bonus = 0, minRank = 0, color = { 154, 163, 174 } },
		{ id = "Uncommon", bonus = 8, minRank = 0, color = { 63, 191, 121 } },
		{ id = "Rare", bonus = 20, minRank = 0, color = { 61, 139, 255 } },
		{ id = "Epic", bonus = 38, minRank = 0, color = { 156, 92, 255 } },
		{ id = "Legendary", bonus = 65, minRank = 1, color = { 245, 184, 65 } },
		{ id = "Mythic", bonus = 95, minRank = 2, color = { 237, 80, 103 } },
		{ id = "Divine", bonus = 130, minRank = 3, color = { 243, 226, 173 } },
		{ id = "Celestial", bonus = 170, minRank = 4, color = { 50, 211, 224 } },
		{ id = "Transcendent", bonus = 215, minRank = 5, color = { 230, 92, 224 } },
		{ id = "Eternal", bonus = 265, minRank = 6, color = { 243, 138, 63 } },
		{ id = "Immortal", bonus = 320, minRank = 7, color = { 26, 175, 148 } },
		{ id = "Astral", bonus = 380, minRank = 8, color = { 157, 141, 255 } },
		{ id = "Cosmic", bonus = 445, minRank = 9, color = { 65, 92, 184 } },
		{ id = "Primordial", bonus = 515, minRank = 10, color = { 183, 100, 71 } },
		{ id = "Singularity", bonus = 590, minRank = 10, color = { 36, 41, 51 } },
	}

	local qualities = CarConfig.getQualities()
	assertEqual(#qualities, #expected, "品質數量")
	for index, spec in ipairs(expected) do
		local quality = qualities[index]
		assertEqual(quality.Id, spec.id, "品質順序")
		assertEqual(quality.Bonus, spec.bonus, spec.id .. " 加成")
		assertEqual(quality.DisplayName, spec.id, spec.id .. " 名稱")
		assertEqual(quality.AvailableFromRebirth, spec.minRank, spec.id .. " 開放等級")
		assertEqual(quality.UiColor[1], spec.color[1], spec.id .. " 介面色")
		assertEqual(quality.UiColor[2], spec.color[2], spec.id .. " 介面色")
		assertEqual(quality.UiColor[3], spec.color[3], spec.id .. " 介面色")
		assertEqual(quality.Weight, nil, spec.id .. " 不該再有全域權重")
	end

	local caps = {
		T0 = "Epic",
		T1 = "Legendary",
		T2 = "Mythic",
		T3 = "Divine",
		T4 = "Celestial",
		T5 = "Transcendent",
		T6 = "Eternal",
		T7 = "Immortal",
		T8 = "Astral",
		T9 = "Cosmic",
		T10 = "Singularity",
	}
	local prices = {
		T0 = 500,
		T1 = 1000,
		T2 = 2000,
		T3 = 4000,
		T4 = 7500,
		T5 = 14000,
		T6 = 25000,
		T7 = 45000,
		T8 = 80000,
		T9 = 140000,
		T10 = 250000,
	}
	local expectedPools = {
		T0 = { Common = 5000, Uncommon = 3000, Rare = 1500, Epic = 500 },
		T1 = { Common = 4900, Uncommon = 3000, Rare = 1500, Epic = 400, Legendary = 200 },
		T2 = { Uncommon = 4900, Rare = 3000, Epic = 1500, Legendary = 500, Mythic = 100 },
		T3 = { Rare = 4950, Epic = 3000, Legendary = 1500, Mythic = 500, Divine = 50 },
		T4 = { Epic = 4980, Legendary = 3000, Mythic = 1500, Divine = 500, Celestial = 20 },
		T5 = { Legendary = 4990, Mythic = 3000, Divine = 1500, Celestial = 500, Transcendent = 10 },
		T6 = { Mythic = 4990, Divine = 3000, Celestial = 1500, Transcendent = 500, Eternal = 10 },
		T7 = { Divine = 4990, Celestial = 3000, Transcendent = 1500, Eternal = 500, Immortal = 10 },
		T8 = { Celestial = 4990, Transcendent = 3000, Eternal = 1500, Immortal = 500, Astral = 10 },
		T9 = { Transcendent = 4990, Eternal = 3000, Immortal = 1500, Astral = 500, Cosmic = 10 },
		T10 = { Immortal = 4999, Astral = 3000, Cosmic = 1500, Primordial = 500, Singularity = 1 },
	}
	assertEqual(#PoolConfig.getAll(), 11, "抽車池數量")
	for _, pool in ipairs(PoolConfig.getAll()) do
		local spec = expectedPools[pool.Id]
		assertEqual(PoolConfig.sumWeights(pool.Id), 10000, pool.Id .. " 機率合計")
		assertEqual(pool.MaxQuality, caps[pool.Id], pool.Id .. " 最高品質")
		assertEqual(PoolConfig.price(pool.Id), prices[pool.Id], pool.Id .. " 價格")
		assertEqual(#pool.Qualities, if pool.Id == "T0" then 4 else 5, pool.Id .. " 品質數量")
		local described = PoolConfig.describe(pool.Id, 0)
		local shown = 0
		for _, rate in ipairs(described.rates) do
			assertEqual(rate.weight, spec[rate.qualityId], pool.Id .. " " .. rate.qualityId .. " 權重")
			assertEqual(rate.percentText, PoolConfig.percentLabel(rate.weight), pool.Id .. " " .. rate.qualityId .. " 顯示機率")
			shown += rate.weight
			spec[rate.qualityId] = nil
		end
		for qualityId in pairs(spec) do
			error(pool.Id .. " 少了品質 " .. qualityId)
		end
		assertEqual(shown, 10000, pool.Id .. " 介面權重")
		assertEqual(#described.qualities, #pool.Qualities, pool.Id .. " 介面品質數量")
		for _, qualityId in ipairs(CarConfig.getQualities()) do
			local listed = false
			for _, rate in ipairs(described.rates) do
				if rate.qualityId == qualityId.Id then
					listed = true
				end
			end
			assertEqual(listed, PoolConfig.contains(pool.Id, qualityId.Id), pool.Id .. " 介面與伺服器品質不一致：" .. qualityId.Id)
		end
	end
	assertEqual(PoolConfig.contains("T0", "Legendary"), false, "T0 不該含傳說")
	assertEqual(PoolConfig.contains("T2", "Common"), false, "T2 不該含普通")
	assertEqual(PoolConfig.get("T10").Weights.Singularity, 1, "T10 奇點權重")
	assertEqual(PoolConfig.percentLabel(1), "0.01", "0.01% 顯示")
	assertEqual(PoolConfig.percentLabel(4999), "49.99", "49.99% 顯示")
	assertEqual(PoolConfig.percentLabel(4950), "49.5", "49.5% 顯示")
	assertEqual(PoolConfig.get("T0").OddsStatus, "specified", "T0 機率狀態")
	assertEqual(PoolConfig.get("T1").OddsStatus, "specified", "T1 機率狀態")
	assertEqual(PoolConfig.get("T1").PriceStatus, "test", "T1 價格不該標成定案")

	local brackets = {
		{ roll = 1, quality = "Common" },
		{ roll = 5000, quality = "Common" },
		{ roll = 5001, quality = "Uncommon" },
		{ roll = 8000, quality = "Uncommon" },
		{ roll = 8001, quality = "Rare" },
		{ roll = 9500, quality = "Rare" },
		{ roll = 9501, quality = "Epic" },
		{ roll = 10000, quality = "Epic" },
	}
	for _, bracket in ipairs(brackets) do
		local rng = scriptedRng({ bracket.roll })
		local qualityId, reason = PoolConfig.roll("T0", rng)
		assertEqual(reason, nil, "T0 區間抽獎不該失敗")
		assertEqual(qualityId, bracket.quality, "T0 點數 " .. tostring(bracket.roll))
	end
	local legendaryRoll = scriptedRng({ 10000 })
	local legendaryId = PoolConfig.roll("T1", legendaryRoll)
	assertEqual(legendaryId, "Legendary", "T1 的 10000 點應該是傳說")
	local t2Roll = scriptedRng({ 1 })
	assertEqual(PoolConfig.roll("T2", t2Roll), "Uncommon", "T2 第一點不該是普通")
	local singularityRoll = scriptedRng({ 10000 })
	assertEqual(PoolConfig.roll("T10", singularityRoll), "Singularity", "T10 最後一點應該是奇點")
	local wallet, _, gacha = newServices({
		rng = scriptedRng({ 1, 1 }),
	})
	assertTrue(wallet:Credit("t2-player", PoolConfig.price("T2")), "T2 測試金幣")
	local blocked = gacha:Pull("t2-player", 2, "t2-block", "T2")
	assertEqual(blocked.ok, true, "T2 抽車失敗")
	assertEqual(blocked.quality, "Uncommon", "T2 抽到了表外品質")
	assertTrue(blocked.quality ~= "Common", "T2 抽到普通")
	return "十一個池合計 10000；T0 無傳說、T2 無普通、T10 奇點 0.01%"
end

local function testDistribution()
	local samples = 10000
	local player = "distribution"
	local wallet, inventory, gacha = newServices({
		rng = RandomSource.new(20261026),
	})
	assertTrue(wallet:Credit(player, samples * CarConfig.SinglePullPrice), "無法準備模擬金幣")

	local counts = {}
	local seen = {}
	for _, quality in ipairs(CarConfig.getQualities()) do
		counts[quality.Id] = 0
	end

	for sample = 1, samples do
		local result = gacha:Pull(player, 0, "sim-" .. tostring(sample))
		assertTrue(result.ok, "模擬抽車失敗：" .. tostring(result.reason) .. " " .. tostring(result.detail))
		counts[result.quality] += 1
		assertEqual(result.car.UpgradeLevel, 0, "模擬車強化等級")
		assertTrue(seen[result.car.InstanceId] ~= true, "模擬出現重複 ID")
		seen[result.car.InstanceId] = true
		assertTrue(result.modelId ~= "test_common_r1", "R0 模擬抽到未解鎖車")
		assertTrue(result.quality ~= "Legendary", "T0 抽到傳說")
	end

	local described = PoolConfig.describe("T0", 0)
	local parts = {}
	for _, rate in ipairs(described.rates) do
		local probability = rate.weight / 10000
		local expected = samples * probability
		local tolerance = math.ceil(5 * math.sqrt(samples * probability * (1 - probability)))
		local actual = counts[rate.qualityId]
		if math.abs(actual - expected) > tolerance then
			error(string.format("%s 出現 %d 次，期望 %.0f，容差 ±%d", rate.qualityId, actual, expected, tolerance))
		end
		table.insert(parts, string.format("%s=%d（±%d）", rate.displayName, actual, tolerance))
	end
	assertEqual(counts.Legendary, 0, "T0 分布出現傳說")
	assertEqual(counts.Singularity, 0, "T0 分布出現奇點")

	assertEqual(wallet:GetBalance(player), 0, "模擬扣完全部金幣")
	assertEqual(#inventory:ListCars(player), samples, "模擬車輛數量")
	return table.concat(parts, " ")
end

local function testRebirthZeroLock()
	local cars = CarCatalog.getAll()
	assertEqual(#cars, 21, "車款數量")
	assertEqual(#CarCatalog.getOfficial(), 15, "正式車款數量")

	local unlockedAtZero = 0
	for _, car in ipairs(cars) do
		if car.ModelId == "test_common_r1" then
			assertEqual(car.UnlockRebirth, 1, "R1 測試車解鎖階級")
			assertEqual(car.Quality, "Common", "R1 測試車品質")
		elseif car.Official == true then
			local quality = CarConfig.getQuality(car.Quality)
			assertEqual(car.UnlockRebirth, quality.AvailableFromRebirth, car.ModelId .. " 解鎖等級")
			local ui = quality.UiColor
			assertTrue(
				car.Paint[1] ~= ui[1] or car.Paint[2] ~= ui[2] or car.Paint[3] ~= ui[3],
				car.ModelId .. " 烤漆用了品質色"
			)
			if car.UnlockRebirth == 0 then
				unlockedAtZero += 1
			end
		else
			assertEqual(car.UnlockRebirth, 0, car.ModelId .. " 應在 R0 解鎖")
			unlockedAtZero += 1
		end
	end
	assertEqual(unlockedAtZero, 9, "R0 可解鎖車款數量")

	local commonAtZero = CarCatalog.getEligible("Common", 0)
	assertEqual(#commonAtZero, 2, "R0 普通車數量")
	assertEqual(commonAtZero[1].ModelId, "test_common_r0", "R0 第一台仍是普通測試車")

	local player = "rebirth-zero"
	local rng = scriptedRng({ 1, 1 })
	local wallet, inventory, gacha = newServices({ rng = rng })
	assertTrue(wallet:Credit(player, CarConfig.SinglePullPrice), "R0 測試金幣")
	local forced = gacha:Pull(player, 0, "forced-common")
	assertTrue(forced.ok, "R0 強制普通抽失敗")
	assertEqual(forced.modelId, "test_common_r0", "R0 強制抽車結果")

	local randomWallet, randomInventory, randomGacha = newServices({
		rng = RandomSource.new(11),
	})
	assertTrue(randomWallet:GrantTestGold(player), "R0 隨機測試金幣")
	for sample = 1, 100 do
		local result = randomGacha:Pull(player, 0, "r0-" .. tostring(sample))
		assertTrue(result.ok, "R0 隨機抽失敗：" .. tostring(result.reason))
		assertTrue(result.modelId ~= "test_common_r1", "R0 抽到一階重生測試車")
		assertTrue(result.quality ~= "Legendary", "R0 抽到傳說")
		local rolled = CarConfig.qualityRank(result.quality)
		assertTrue(rolled ~= nil and rolled <= 4, "R0 抽到 Epic 以上")
	end
	assertEqual(#randomInventory:ListCars(player), 100, "R0 隨機車輛數")
	assertEqual(inventory:ListCars(player)[1].ModelId, "test_common_r0", "獨立環境不被隨機抽車影響")
	return "R0 的 100 次隨機與強制普通抽都沒有一階車"
end

local function testRebirthOneUnlock()
	local commonAtOne = CarCatalog.getEligible("Common", 1)
	assertEqual(#commonAtOne, 3, "R1 普通車數量")
	assertEqual(commonAtOne[2].ModelId, "test_common_r1", "R1 可選車順序")

	local player = "rebirth-one"
	local rng = scriptedRng({ 1, 2 })
	local wallet, inventory, gacha = newServices({ rng = rng })
	assertTrue(wallet:Credit(player, CarConfig.SinglePullPrice), "R1 測試金幣")
	local forced = gacha:Pull(player, 1, "forced-r1")
	assertTrue(forced.ok, "R1 強制抽失敗：" .. tostring(forced.reason))
	assertEqual(forced.modelId, "test_common_r1", "R1 強制抽車結果")
	assertEqual(forced.car.AcquiredRebirth, 1, "取得時的重生階級")
	assertEqual(forced.car.UpgradeLevel, 0, "R1 車初始強化")

	local found = false
	local randomWallet, _, randomGacha = newServices({
		rng = RandomSource.new(19),
	})
	assertTrue(randomWallet:Credit(player, 200 * CarConfig.SinglePullPrice), "R1 隨機測試金幣")
	for sample = 1, 200 do
		local result = randomGacha:Pull(player, 1, "r1-" .. tostring(sample))
		assertTrue(result.ok, "R1 隨機抽失敗")
		if result.modelId == "test_common_r1" then
			found = true
			break
		end
	end
	assertTrue(found, "R1 的 200 次抽取沒有出現新車型")
	assertEqual(inventory:GetCar(player, forced.car.InstanceId).ModelId, "test_common_r1", "強制抽到的車仍在")
	return "腳本抽與隨機抽都取得一階重生測試車"
end

local function testInsufficientGold()
	local player = "poor"
	local rng, calls = scriptedRng({ 1, 1 })
	local wallet, inventory, gacha = newServices({ rng = rng })
	assertEqual(wallet:GetBalance(player), 0, "新玩家不該自帶金幣")
	assertTrue(wallet:Credit(player, CarConfig.SinglePullPrice - 1), "準備不足額金幣")

	local result = gacha:Pull(player, 0, "too-poor")
	assertEqual(result.ok, false, "金幣不足仍成功")
	assertEqual(result.reason, CarGachaService.Reason.InsufficientGold, "不足額原因")
	assertEqual(result.charged, false, "不足額不該扣款")
	assertEqual(wallet:GetBalance(player), 499, "不足額餘額")
	assertEqual(#inventory:ListCars(player), 0, "不足額不該發車")
	assertEqual(calls(), 0, "金幣不足不該消耗抽獎隨機數")

	local replay = gacha:Pull(player, 0, "too-poor")
	assertEqual(replay.reason, CarGachaService.Reason.InsufficientGold, "不足額重送")
	assertEqual(replay.replayed, true, "不足額重送標記")
	assertEqual(wallet:GetBalance(player), 499, "重送後餘額")
	assertEqual(calls(), 0, "重送不該補抽")
	return "499 金幣無法支付 500"
end

local function testDebit()
	assertEqual(CarConfig.SinglePullPrice, 500, "單抽定價")
	assertEqual(CarConfig.TestStartingGold, 50000, "測試起始金幣")

	local player = "buyer"
	local wallet, inventory, gacha = newServices({
		rng = scriptedRng({ 1, 1 }),
	})
	assertEqual(wallet:GetBalance(player), 0, "建立錢包不發正式金幣")
	assertTrue(wallet:GrantTestGold(player), "發放測試金幣")
	assertEqual(wallet:GrantTestGold(player), false, "測試金幣不可領第二次")
	assertEqual(wallet:GetBalance(player), 50000, "測試金幣餘額")

	local result = gacha:Pull(player, 0, "buy-1")
	assertTrue(result.ok, "正常抽車失敗")
	assertEqual(result.charged, true, "成功抽車應扣款")
	assertEqual(result.price, 500, "本次價格")
	assertEqual(result.balance, 49500, "回傳餘額")
	assertEqual(wallet:GetBalance(player), 49500, "實際餘額")
	assertEqual(#inventory:ListCars(player), 1, "購車後車輛數")

	local previousPrice = CarConfig.SinglePullPrice
	CarConfig.SinglePullPrice = 42
	local priceOk, priceErr = pcall(function()
		local customPlayer = "custom-price"
		local customWallet, _, customGacha = newServices({
			rng = scriptedRng({ 10000, 1 }),
		})
		assertTrue(customWallet:Credit(customPlayer, 42), "自訂價格金幣")
		local custom = customGacha:Pull(customPlayer, 0, "custom-price")
		assertTrue(custom.ok, "自訂價格抽車失敗：" .. tostring(custom.reason))
		assertEqual(custom.price, 42, "自訂價格")
		assertEqual(custom.quality, "Epic", "自訂價格仍走 T0 機率")
		assertEqual(customWallet:GetBalance(customPlayer), 0, "自訂價格扣款")
	end)
	CarConfig.SinglePullPrice = previousPrice
	if not priceOk then
		error(priceErr)
	end
	return "50000 - 500 = 49500，設定價 42 也會照扣"
end

local function testUniqueIds()
	local calls = 0
	local sequence = { "dup", "dup", "unique-2", "removed-id", "removed-id", "unique-3" }
	local inventory = CarInventoryService.new({
		now = function()
			return 42
		end,
		newId = function()
			calls += 1
			return sequence[calls]
		end,
	})

	local first, firstReason = inventory:CreateCar("player-a", "test_rare_r0", 0)
	assertEqual(firstReason, nil, "第一台車")
	local second, secondReason = inventory:CreateCar("player-a", "test_epic_r0", 0)
	assertEqual(secondReason, nil, "碰撞後第二台車")
	assertEqual(first.InstanceId, "dup", "第一個 ID")
	assertEqual(second.InstanceId, "unique-2", "碰撞後應改用下一個 ID")
	assertTrue(first.InstanceId ~= second.InstanceId, "兩台車 ID 相同")

	local other = inventory:CreateCar(1200, "test_common_r0", 0)
	assertEqual(other.InstanceId, "removed-id", "數字玩家鍵")
	assertTrue(inventory:RemoveCar(1200, other.InstanceId), "移除車輛")
	assertEqual(inventory:GetCar(1200, other.InstanceId), nil, "移除後仍可查到")
	local replacement = inventory:CreateCar(1200, "test_common_r0", 0)
	assertEqual(replacement.InstanceId, "unique-3", "移除後不該回收舊 ID")

	local stuckCalls = 0
	local stuck = CarInventoryService.new({
		now = function()
			return 7
		end,
		newId = function()
			stuckCalls += 1
			return "always-same"
		end,
	})
	local created = stuck:CreateCar("player-b", "test_common_r0", 0)
	assertEqual(created.InstanceId, "always-same", "固定 ID 第一台")
	local blocked, blockedReason = stuck:CreateCar("player-b", "test_common_r0", 0)
	assertEqual(blocked, nil, "持續碰撞仍寫入")
	assertEqual(blockedReason, CarInventoryService.Reason.IdCollision, "碰撞原因")
	assertEqual(#stuck:ListCars("player-b"), 1, "碰撞失敗不增加車輛")
	assertTrue(stuckCalls >= 9, "沒有重試碰撞的 ID")

	local listed = inventory:ListCars("player-a")
	assertEqual(#listed, 2, "玩家 A 的車輛數")
	assertEqual(#inventory:ListCars("player-b"), 0, "玩家資料互相污染")
	return "碰撞會重試，移除後也不回收舊 ID"
end

local function testInitialUpgrade()
	local wallet, inventory, gacha = newServices({
		rng = scriptedRng({ 8001, 1 }),
		now = function()
			return 99
		end,
	})
	local player = "upgrade"
	assertTrue(wallet:Credit(player, 500), "強化測試金幣")
	local result = gacha:Pull(player, 0, "upgrade-0")
	assertTrue(result.ok, "抽車失敗")
	assertEqual(result.car.UpgradeLevel, CarConfig.MinUpgradeLevel, "抽車結果等級")
	assertEqual(result.quality, "Rare", "這次應為稀有")

	local stored = inventory:GetCar(player, result.car.InstanceId)
	assertEqual(stored.UpgradeLevel, 0, "庫存等級")
	assertEqual(stored.CreatedAt, 99, "建立時間")

	local mutated = pcall(function()
		stored.UpgradeLevel = 10
	end)
	assertEqual(mutated, false, "回傳資料應凍結，不能直接改等級")
	assertEqual(inventory:GetCar(player, stored.InstanceId).UpgradeLevel, 0, "外部修改寫進庫存")
	return "新車等級為 0，外部改不到庫存"
end

local function testInvalidAndDuplicate()
	local inventory = CarInventoryService.new({
		now = function()
			return 5
		end,
	})
	local player = "invalid"

	local missing, missingReason = inventory:CreateCar(player, "no-such-car", 0)
	assertEqual(missing, nil, "無效車款仍建立")
	assertEqual(missingReason, CarInventoryService.Reason.UnknownModel, "無效車款原因")

	local locked, lockedReason = inventory:CreateCar(player, "test_common_r1", 0)
	assertEqual(locked, nil, "未解鎖車款仍建立")
	assertEqual(lockedReason, CarInventoryService.Reason.LockedModel, "未解鎖原因")
	assertEqual(#inventory:ListCars(player), 0, "失敗請求留下車輛")

	local valid = inventory:CreateCar(player, "test_common_r0", 0)
	local function reject(data, reason, message)
		local ok, actual = inventory:ValidateCar(data)
		assertEqual(ok, false, message)
		assertEqual(actual, reason, message)
	end

	reject({
		InstanceId = "x",
		ModelId = "test_common_r0",
		UpgradeLevel = 11,
		AcquiredRebirth = 0,
		CreatedAt = 5,
	}, CarInventoryService.Reason.InvalidUpgradeLevel, "等級 11")
	reject({
		InstanceId = "x2",
		ModelId = "test_common_r0",
		UpgradeLevel = -1,
		AcquiredRebirth = 0,
		CreatedAt = 5,
	}, CarInventoryService.Reason.InvalidUpgradeLevel, "等級 -1")
	reject({
		InstanceId = "x3",
		ModelId = "test_common_r0",
		UpgradeLevel = 1.5,
		AcquiredRebirth = 0,
		CreatedAt = 5,
	}, CarInventoryService.Reason.InvalidUpgradeLevel, "小數等級")
	reject({
		InstanceId = "x4",
		ModelId = "missing",
		UpgradeLevel = 0,
		AcquiredRebirth = 0,
		CreatedAt = 5,
	}, CarInventoryService.Reason.UnknownModel, "驗證無效車款")
	reject({
		InstanceId = valid.InstanceId,
		ModelId = valid.ModelId,
		Quality = "Mythic",
		UpgradeLevel = 0,
		AcquiredRebirth = 0,
		CreatedAt = 5,
	}, CarInventoryService.Reason.InvalidQuality, "無效品質")
	reject({
		InstanceId = valid.InstanceId,
		ModelId = valid.ModelId,
		UpgradeLevel = 1,
		AcquiredRebirth = valid.AcquiredRebirth,
		CreatedAt = valid.CreatedAt,
	}, CarInventoryService.Reason.DuplicateInstanceId, "重複 ID 但內容不同")

	local accepted, acceptedReason = inventory:ValidateCar(valid)
	assertEqual(acceptedReason, nil, "合法車輛驗證")
	assertTrue(accepted, "自己的車輛應通過驗證")

	local wallet, _, gacha = newServices({
		rng = scriptedRng({ 1, 1 }),
	})
	assertTrue(wallet:GrantTestGold(player), "重複請求測試金幣")
	local first = gacha:Pull(player, 0, "same-request")
	local second = gacha:Pull(player, 0, "same-request")
	assertTrue(first.ok, "第一次請求失敗")
	assertTrue(second.ok, "重複請求失敗")
	assertEqual(second.replayed, true, "重複請求標記")
	assertEqual(first.car.InstanceId, second.car.InstanceId, "重複請求發了另一台車")
	assertEqual(wallet:GetBalance(player), 49500, "重複請求再次扣款")

	local failingWallet, _, failingGacha = newServices({
		inventory = {
			CreateCar = function()
				return nil, "UnknownModel"
			end,
		},
		rng = scriptedRng({ 1, 1 }),
	})
	assertTrue(failingWallet:Credit("grant-fail", 500), "發車失敗測試金幣")
	local failed = failingGacha:Pull("grant-fail", 0, "grant-fail")
	assertEqual(failed.ok, false, "發車失敗卻成功")
	assertEqual(failed.reason, CarGachaService.Reason.GrantFailed, "發車失敗原因")
	assertEqual(failingWallet:GetBalance("grant-fail"), 500, "發車失敗沒有退款")
	local failedReplay = failingGacha:Pull("grant-fail", 0, "grant-fail")
	assertEqual(failedReplay.replayed, true, "發車失敗重送")
	assertEqual(failingWallet:GetBalance("grant-fail"), 500, "發車失敗重送又扣款")

	local explodingWallet, _, explodingGacha = newServices({
		inventory = {
			CreateCar = function()
				error("boom")
			end,
		},
		rng = scriptedRng({ 51, 1 }),
	})
	assertTrue(explodingWallet:Credit("explode", 500), "例外測試金幣")
	local exploded = explodingGacha:Pull("explode", 0, "explode")
	assertEqual(exploded.ok, false, "例外被當成成功")
	assertEqual(exploded.reason, CarGachaService.Reason.InternalError, "例外原因")
	assertEqual(explodingWallet:GetBalance("explode"), 500, "例外沒有退款")
	local explodedReplay = explodingGacha:Pull("explode", 0, "explode")
	assertEqual(explodedReplay.replayed, true, "例外重送")
	assertEqual(explodingWallet:GetBalance("explode"), 500, "例外重送又扣款")
	return "無效資料會拒絕，同一請求只扣一次"
end

local function testNoUnlockedModel()
	local player = "empty-legendary"
	local rng, calls = scriptedRng({ 10000 })
	local wallet, inventory, gacha = newServices({
		rng = rng,
		catalog = {
			getEligible = function(qualityId, rebirthLevel)
				if qualityId == "Legendary" then
					return {}
				end
				return CarCatalog.getEligible(qualityId, rebirthLevel)
			end,
		},
	})
	local price = PoolConfig.price("T1")
	assertTrue(wallet:Credit(player, price), "空車池金幣")
	local locked = gacha:Pull(player, 0, "locked-pool", "T1")
	assertEqual(locked.ok, false, "未解鎖的池仍抽成功")
	assertEqual(locked.reason, CarGachaService.Reason.PoolLocked, "未解鎖原因")
	assertEqual(locked.charged, false, "未解鎖仍扣款")
	assertEqual(wallet:GetBalance(player), price, "未解鎖餘額")

	local result = gacha:Pull(player, 1, "no-legendary", "T1")
	assertEqual(result.ok, false, "沒有車款卻成功")
	assertEqual(result.reason, CarGachaService.Reason.NoUnlockedModel, "沒有車款原因")
	assertEqual(result.quality, "Legendary", "失敗時改抽了別的品質")
	assertEqual(result.charged, false, "沒有車款仍扣款")
	assertEqual(wallet:GetBalance(player), price, "空車池餘額")
	assertEqual(#inventory:ListCars(player), 0, "空車池發了車")

	local replay = gacha:Pull(player, 1, "no-legendary", "T1")
	assertEqual(replay.replayed, true, "空車池重送")
	assertEqual(replay.quality, "Legendary", "重送時改抽品質")
	assertEqual(calls(), 1, "重送又抽了一次")
	return "抽中傳說但沒有車時維持傳說結果且不扣款"
end

local function testPower()
	local cases = {
		{ 0, "Common", 0, 100 },
		{ 1, "Common", 0, 110 },
		{ 10, "Common", 0, 200 },
		{ 0, "Uncommon", 0, 108 },
		{ 0, "Rare", 0, 120 },
		{ 0, "Epic", 0, 138 },
		{ 0, "Legendary", 0, 165 },
		{ 0, "Mythic", 0, 195 },
		{ 0, "Common", 1, 100 },
		{ 0, "Common", 10, 100 },
		{ 5, "Epic", 0, 188 },
		{ 5, "Epic", 4, 188 },
		{ 10, "Legendary", 0, 265 },
		{ 10, "Legendary", 10, 265 },
		{ 3, "Rare", 1, 150 },
		{ 2, "Uncommon", 3, 128 },
	}

	for _, case in ipairs(cases) do
		local upgradeLevel, qualityId, rebirthLevel, expected = case[1], case[2], case[3], case[4]
		local power, reason = CarConfig.calculatePower(upgradeLevel, qualityId, rebirthLevel)
		assertEqual(reason, nil, string.format("Power(%d,%s,R%d) 失敗", upgradeLevel, qualityId, rebirthLevel))
		assertEqual(power, expected, string.format("Power(%d,%s,R%d)", upgradeLevel, qualityId, rebirthLevel))
	end

	local function expectReject(upgradeLevel, qualityId, rebirthLevel, reason)
		local power, actual = CarConfig.calculatePower(upgradeLevel, qualityId, rebirthLevel)
		assertEqual(power, nil, "非法輸入仍算出性能")
		assertEqual(actual, reason, "非法輸入原因")
	end

	expectReject(-1, "Common", 0, "InvalidUpgradeLevel")
	expectReject(11, "Common", 0, "InvalidUpgradeLevel")
	expectReject(1.5, "Common", 0, "InvalidUpgradeLevel")
	expectReject(0, "NoSuchQuality", 0, "InvalidQuality")
	expectReject(0, "Common", -1, "InvalidRebirth")
	expectReject(0, "Common", 11, "InvalidRebirth")

	local commonR0 = CarCatalog.getByModelId("test_common_r0")
	local commonR1 = CarCatalog.getByModelId("test_common_r1")
	assertEqual(commonR0.Quality, commonR1.Quality, "兩台普通車品質不同")
	assertEqual(
		CarConfig.calculatePower(4, commonR0.Quality, 2),
		CarConfig.calculatePower(4, commonR1.Quality, 2),
		"同品質車型出現額外性能差"
	)
	assertEqual(
		CarConfig.calculatePower(0, "Common", 0),
		CarConfig.calculatePower(0, "Common", 10),
		"T 等級改了普通車 Power"
	)
	assertEqual(
		CarConfig.calculatePower(5, "Epic", 0),
		CarConfig.calculatePower(5, "Epic", 4),
		"抽車池等級改了史詩車 Power"
	)

	local walletT0, _, gachaT0 = newServices({
		rng = scriptedRng({ 1, 1 }),
	})
	assertTrue(walletT0:Credit("power-t0", PoolConfig.price("T0")), "T0 性能測試金幣")
	local fromT0 = gachaT0:Pull("power-t0", 0, "power-t0", "T0")
	local walletT1, _, gachaT1 = newServices({
		rng = scriptedRng({ 1, 1 }),
	})
	assertTrue(walletT1:Credit("power-t1", PoolConfig.price("T1")), "T1 性能測試金幣")
	local fromT1 = gachaT1:Pull("power-t1", 1, "power-t1", "T1")
	assertEqual(fromT0.quality, "Common", "T0 這次不是普通")
	assertEqual(fromT1.quality, "Common", "T1 這次不是普通")
	assertEqual(fromT0.car.AcquiredRebirth, 0, "T0 取得等級")
	assertEqual(fromT1.car.AcquiredRebirth, 1, "T1 取得等級")
	assertEqual(
		CarConfig.calculatePower(fromT0.car.UpgradeLevel, fromT0.quality, fromT0.car.AcquiredRebirth),
		CarConfig.calculatePower(fromT1.car.UpgradeLevel, fromT1.quality, fromT1.car.AcquiredRebirth),
		"不同車商的同品質車 Power 不同"
	)
	return "同品質同強化等級的 Power 與抽車池、T 等級無關"
end

function Tests.run()
	local cases = {
		{ "十五種品質與 T0～T10 抽車池", testWeights },
		{ "一萬次模擬抽取分布", testDistribution },
		{ "R0 不能取得 R1 車型", testRebirthZeroLock },
		{ "R1 可以取得已解鎖車型", testRebirthOneUnlock },
		{ "金幣不足無法抽車", testInsufficientGold },
		{ "抽到車後正確扣款", testDebit },
		{ "每台車的 ID 唯一", testUniqueIds },
		{ "初始強化等級為 0", testInitialUpgrade },
		{ "無效車款、無效等級與重複請求", testInvalidAndDuplicate },
		{ "沒有可解鎖車款時不改機率", testNoUnlockedModel },
		{ "性能公式", testPower },
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
	print(string.format("CARFORGETAX_TESTS passed=%d failed=%d", summary.passed, summary.failed))
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
