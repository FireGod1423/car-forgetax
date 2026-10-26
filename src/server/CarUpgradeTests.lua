-- 強化測試使用自己的車庫，不會寫入正式玩家資料。
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
local RandomSource = importShared("RandomSource")
local GoldWallet = importServer("GoldWallet")
local CarInventoryService = importServer("CarInventoryService")
local CarUpgradeService = importServer("CarUpgradeService")

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

local function firstRoll(level: number, outcomeId: string): number
	local weights = UpgradeConfig.getWeights(level)
	local cursor = 0
	for _, outcome in ipairs(UpgradeConfig.getOutcomes()) do
		local weight = weights[outcome.Id]
		if outcome.Id == outcomeId then
			if weight <= 0 then
				error(outcomeId .. " 在 +" .. tostring(level) .. " 的機率是 0")
			end
			return cursor + 1
		end
		cursor += weight
	end
	error("找不到強化結果")
end

local function newInventory()
	return CarInventoryService.new({
		now = function()
			return 50
		end,
	})
end

local function makeCar(inventory, player: string, level: number, rebirth: number?)
	local car, reason = inventory:CreateCar(player, "test_common_r0", rebirth or 0)
	if car == nil then
		error(reason or "無法建立測試車")
	end
	if level ~= 0 then
		car, reason = inventory:SetUpgradeLevel(player, car.InstanceId, level)
		if car == nil then
			error(reason or "無法設定強化等級")
		end
	end
	return car
end

local expectedWeights = {
	[0] = { Destroy = 0, Damage = 5, Keep = 10, Success = 70, GreatSuccess = 15 },
	[1] = { Destroy = 0, Damage = 5, Keep = 10, Success = 70, GreatSuccess = 15 },
	[2] = { Destroy = 0, Damage = 5, Keep = 10, Success = 70, GreatSuccess = 15 },
	[3] = { Destroy = 3, Damage = 12, Keep = 20, Success = 55, GreatSuccess = 10 },
	[4] = { Destroy = 3, Damage = 12, Keep = 20, Success = 55, GreatSuccess = 10 },
	[5] = { Destroy = 12, Damage = 20, Keep = 25, Success = 37, GreatSuccess = 6 },
	[6] = { Destroy = 12, Damage = 20, Keep = 25, Success = 37, GreatSuccess = 6 },
	[7] = { Destroy = 30, Damage = 25, Keep = 25, Success = 17, GreatSuccess = 3 },
	[8] = { Destroy = 50, Damage = 25, Keep = 16, Success = 8, GreatSuccess = 1 },
	[9] = { Destroy = 80, Damage = 12, Keep = 5, Success = 3, GreatSuccess = 0 },
}

local function testWeightSums()
	for level = 0, 9 do
		local weights, reason = UpgradeConfig.getWeights(level)
		assertEqual(reason, nil, "+" .. tostring(level) .. " 應該有機率")
		local total = 0
		for _, outcome in ipairs(UpgradeConfig.getOutcomes()) do
			assertEqual(weights[outcome.Id], expectedWeights[level][outcome.Id], "+" .. tostring(level) .. outcome.DisplayName)
			total += weights[outcome.Id]
		end
		assertEqual(total, 100, "+" .. tostring(level) .. " 機率合計")
		assertEqual(UpgradeConfig.sumWeights(level), 100, "+" .. tostring(level) .. " 權重函式")
	end
	return "+0 到 +9 每個階段都是 100%"
end

local function testPlusEightGreat()
	local weights = UpgradeConfig.getWeights(8)
	assertEqual(weights.GreatSuccess, 1, "+8 大成功率")
	return "+8 大成功 1%"
end

local function testPlusNineGreat()
	local weights = UpgradeConfig.getWeights(9)
	assertEqual(weights.GreatSuccess, 0, "+9 大成功率")
	return "+9 大成功 0%"
end

local function testPlusNineDestroy()
	assertEqual(UpgradeConfig.getWeights(9).Destroy, 80, "+9 報廢率")
	local rng = scriptedRng({ 1 })
	assertEqual(UpgradeConfig.rollOutcome(9, rng), UpgradeConfig.Outcome.Destroy, "+9 點數 1 應為報廢")
	local upper = scriptedRng({ 80 })
	assertEqual(UpgradeConfig.rollOutcome(9, upper), UpgradeConfig.Outcome.Destroy, "+9 點數 80 應為報廢")
	local nextRoll = scriptedRng({ 81 })
	assertEqual(UpgradeConfig.rollOutcome(9, nextRoll), UpgradeConfig.Outcome.Damage, "+9 點數 81 應離開報廢")
	return "+9 報廢 80%"
end

local function testMaxLevelBlocked()
	local inventory = newInventory()
	local player = "maxed"
	local car = makeCar(inventory, player, 10, 0)
	local rng, calls = scriptedRng({ 1 })
	local upgrade = CarUpgradeService.new({
		inventory = inventory,
		rng = rng,
	})
	local result = upgrade:Upgrade(player, car.InstanceId, "max-level")
	assertEqual(result.ok, false, "+10 不該強化成功")
	assertEqual(result.reason, CarUpgradeService.Reason.MaxUpgradeLevel, "+10 原因")
	assertEqual(result.charged, false, "+10 不該扣款")
	assertEqual(calls(), 0, "+10 不該抽取")
	assertEqual(inventory:GetCar(player, car.InstanceId).UpgradeLevel, 10, "+10 等級被改掉")
	local missing = UpgradeConfig.getWeights(10)
	assertEqual(missing, nil, "+10 不該有機率表")
	return "+10 拒絕繼續強化"
end

local function testDamageFloor()
	local inventory = newInventory()
	local player = "floor"
	local car = makeCar(inventory, player, 0, 0)
	local upgrade = CarUpgradeService.new({
		inventory = inventory,
		rng = scriptedRng({ firstRoll(0, "Damage") }),
	})
	local result = upgrade:Upgrade(player, car.InstanceId, "damage-zero")
	assertTrue(result.ok, "損壞失敗：" .. tostring(result.reason))
	assertEqual(result.outcome, UpgradeConfig.Outcome.Damage, "損壞結果")
	assertEqual(result.previousLevel, 0, "損壞前等級")
	assertEqual(result.upgradeLevel, 0, "損壞後等級")
	assertEqual(result.removed, false, "損壞不該刪車")
	assertEqual(inventory:GetCar(player, car.InstanceId).UpgradeLevel, 0, "車庫等級")
	return "+0 損壞後仍是 +0"
end

local function testSuccessToTen()
	local inventory = newInventory()
	local player = "success-ten"
	local car = makeCar(inventory, player, 9, 0)
	local upgrade = CarUpgradeService.new({
		inventory = inventory,
		rng = scriptedRng({ firstRoll(9, "Success") }),
	})
	local result = upgrade:Upgrade(player, car.InstanceId, "success-nine")
	assertTrue(result.ok, "+9 成功失敗：" .. tostring(result.reason))
	assertEqual(result.outcome, UpgradeConfig.Outcome.Success, "+9 結果")
	assertEqual(result.upgradeLevel, 10, "+9 成功後等級")
	assertEqual(inventory:GetCar(player, car.InstanceId).UpgradeLevel, 10, "車庫應為 +10")
	local mutated = pcall(function()
		result.car.UpgradeLevel = 0
	end)
	assertEqual(mutated, false, "回傳車輛應凍結")
	assertEqual(inventory:GetCar(player, car.InstanceId).UpgradeLevel, 10, "外部修改寫進車庫")
	return "+9 成功變成 +10"
end

local function testGreatSuccessToTen()
	local inventory = newInventory()
	local player = "great-ten"
	local car = makeCar(inventory, player, 8, 0)
	local upgrade = CarUpgradeService.new({
		inventory = inventory,
		rng = scriptedRng({ firstRoll(8, "GreatSuccess") }),
	})
	local result = upgrade:Upgrade(player, car.InstanceId, "great-eight")
	assertTrue(result.ok, "+8 大成功失敗：" .. tostring(result.reason))
	assertEqual(result.rawOutcome, UpgradeConfig.Outcome.GreatSuccess, "+8 原始結果")
	assertEqual(result.upgradeLevel, 10, "+8 大成功後等級")
	assertEqual(result.power, CarConfig.calculatePower(10, "Common", 0), "+8 大成功性能")
	assertEqual(inventory:GetCar(player, car.InstanceId).UpgradeLevel, 10, "車庫應直接到 +10")
	return "+8 大成功變成 +10"
end

local function testDestroyRemovesCar()
	local inventory = newInventory()
	local player = "scrap"
	local car = makeCar(inventory, player, 4, 0)
	local upgrade = CarUpgradeService.new({
		inventory = inventory,
		rng = scriptedRng({ firstRoll(4, "Destroy") }),
	})
	local result = upgrade:Upgrade(player, car.InstanceId, "scrap")
	assertTrue(result.ok, "報廢失敗：" .. tostring(result.reason))
	assertEqual(result.outcome, UpgradeConfig.Outcome.Destroy, "報廢結果")
	assertEqual(result.removed, true, "報廢應標記移除")
	assertEqual(result.car, nil, "報廢不該回傳可用車輛")
	assertEqual(result.power, nil, "報廢不該再有性能")
	local stored, storedReason = inventory:GetCar(player, car.InstanceId)
	assertEqual(stored, nil, "報廢後仍可取得車輛")
	assertEqual(storedReason, CarInventoryService.Reason.UnknownCar, "報廢後原因")
	assertEqual(#inventory:ListCars(player), 0, "報廢後車庫還有車")

	local again = upgrade:Upgrade(player, car.InstanceId, "scrap-again")
	assertEqual(again.ok, false, "報廢後還能再強化")
	assertEqual(again.reason, CarUpgradeService.Reason.UnknownCar, "再次強化原因")
	return "報廢後車庫不再持有這台車"
end

local function testInvalidInstance()
	local inventory = newInventory()
	local player = "invalid-id"
	makeCar(inventory, player, 0, 0)
	local rng, calls = scriptedRng({ 1 })
	local upgrade = CarUpgradeService.new({
		inventory = inventory,
		rng = rng,
	})
	local missing = upgrade:Upgrade(player, "missing-car", "missing")
	assertEqual(missing.ok, false, "不存在的車仍強化成功")
	assertEqual(missing.reason, CarUpgradeService.Reason.UnknownCar, "不存在原因")
	local blank = upgrade:Upgrade(player, "", "blank")
	assertEqual(blank.ok, false, "空 ID 仍強化成功")
	assertEqual(blank.reason, CarUpgradeService.Reason.InvalidInstanceId, "空 ID 原因")
	assertEqual(calls(), 0, "無效 ID 不該抽取")
	assertEqual(#inventory:ListCars(player), 1, "無效請求改到車庫")
	return "無效 InstanceId 會被拒絕"
end

local function testOtherPlayersCar()
	local inventory = newInventory()
	local car = makeCar(inventory, "player-b", 3, 0)
	local rng, calls = scriptedRng({ firstRoll(3, "Success") })
	local upgrade = CarUpgradeService.new({
		inventory = inventory,
		rng = rng,
	})
	local result = upgrade:Upgrade("player-a", car.InstanceId, "steal")
	assertEqual(result.ok, false, "玩家 A 強化了玩家 B 的車")
	assertEqual(result.reason, CarUpgradeService.Reason.UnknownCar, "非持有者原因")
	assertEqual(calls(), 0, "非持有者不該抽取")
	assertEqual(inventory:GetCar("player-b", car.InstanceId).UpgradeLevel, 3, "玩家 B 的等級被改掉")
	assertEqual(#inventory:ListCars("player-a"), 0, "玩家 A 得到了別人的車")
	return "玩家 A 不能強化玩家 B 的車"
end

local function testDuplicateRequest()
	local inventory = newInventory()
	local player = "duplicate"
	local car = makeCar(inventory, player, 0, 0)
	local rng, calls = scriptedRng({ firstRoll(0, "Success") })
	local upgrade = CarUpgradeService.new({
		inventory = inventory,
		rng = rng,
	})
	local first = upgrade:Upgrade(player, car.InstanceId, "same-request")
	local second = upgrade:Upgrade(player, car.InstanceId, "same-request")
	assertTrue(first.ok, "第一次強化失敗")
	assertTrue(second.ok, "重複請求失敗")
	assertEqual(second.replayed, true, "重複請求標記")
	assertEqual(first.upgradeLevel, 1, "第一次應成功到 +1")
	assertEqual(second.upgradeLevel, 1, "重複請求又升級")
	assertEqual(inventory:GetCar(player, car.InstanceId).UpgradeLevel, 1, "車庫被重複強化")
	assertEqual(calls(), 1, "重複請求又抽取")
	return "同一個 requestId 只執行一次"
end

local function testConcurrentUpgrade()
	local inner = newInventory()
	local player = "race"
	local car = makeCar(inner, player, 5, 0)
	local nested = nil
	local writes = 0
	local upgrade
	local inventory = {
		GetCar = function(_self, playerKey, instanceId)
			return inner:GetCar(playerKey, instanceId)
		end,
		ListCars = function(_self, playerKey)
			return inner:ListCars(playerKey)
		end,
		RemoveCar = function(_self, playerKey, instanceId)
			return inner:RemoveCar(playerKey, instanceId)
		end,
		SetUpgradeLevel = function(_self, playerKey, instanceId, level)
			writes += 1
			if writes == 1 then
				nested = upgrade:Upgrade(playerKey, instanceId, "parallel-request")
			end
			return inner:SetUpgradeLevel(playerKey, instanceId, level)
		end,
	}
	upgrade = CarUpgradeService.new({
		inventory = inventory,
		rng = scriptedRng({ firstRoll(5, "Success") }),
	})
	local result = upgrade:Upgrade(player, car.InstanceId, "primary-request")
	assertTrue(result.ok, "主要強化失敗：" .. tostring(result.reason))
	assertEqual(result.upgradeLevel, 6, "主要強化應只 +1")
	assertEqual(nested ~= nil, true, "沒有送出並行請求")
	assertEqual(nested.ok, false, "並行請求不該成功")
	assertEqual(nested.reason, CarUpgradeService.Reason.UpgradeInProgress, "並行請求原因")
	assertEqual(inner:GetCar(player, car.InstanceId).UpgradeLevel, 6, "並行請求造成額外升級")
	assertEqual(writes, 1, "等級被寫入多次")
	return "同一台車的重入請求被拒絕"
end

local function testDistribution()
	local samples = 10000
	local highlights = {}
	for level = 0, 9 do
		local rng = RandomSource.new(20261026 + level)
		local counts = {}
		for _, outcome in ipairs(UpgradeConfig.getOutcomes()) do
			counts[outcome.Id] = 0
		end
		for _ = 1, samples do
			local outcomeId, reason = UpgradeConfig.rollOutcome(level, rng)
			if outcomeId == nil then
				error("+" .. tostring(level) .. " 模擬失敗：" .. tostring(reason))
			end
			counts[outcomeId] += 1
		end

		local weights = expectedWeights[level]
		for _, outcome in ipairs(UpgradeConfig.getOutcomes()) do
			local weight = weights[outcome.Id]
			local actual = counts[outcome.Id]
			if weight == 0 then
				if actual ~= 0 then
					error(string.format("+%d %s 機率為 0 卻出現 %d 次", level, outcome.DisplayName, actual))
				end
			else
				local probability = weight / 100
				local expected = samples * probability
				local tolerance = math.ceil(5 * math.sqrt(samples * probability * (1 - probability)))
				if math.abs(actual - expected) > tolerance then
					error(string.format(
						"+%d %s 出現 %d 次，期望 %.0f，容差 ±%d",
						level,
						outcome.DisplayName,
						actual,
						expected,
						tolerance
					))
				end
			end
		end
		if level == 8 or level == 9 then
			table.insert(highlights, string.format(
				"+%d 報廢=%d 大成功=%d",
				level,
				counts.Destroy,
				counts.GreatSuccess
			))
		end
	end
	return table.concat(highlights, "；")
end

local function testNoGoldCost()
	local inventory = newInventory()
	local player = "free"
	local wallet = GoldWallet.new()
	assertTrue(wallet:Credit(player, 50000), "準備金幣")
	local debits = 0
	local originalDebit = wallet.TryDebit
	wallet.TryDebit = function(self, ...)
		debits += 1
		return originalDebit(self, ...)
	end

	local upgrade = CarUpgradeService.new({
		inventory = inventory,
		wallet = wallet,
		rng = scriptedRng({
			firstRoll(0, "Success"),
			firstRoll(0, "Damage"),
			firstRoll(0, "Keep"),
			firstRoll(4, "Destroy"),
		}),
	})
	local successCar = makeCar(inventory, player, 0, 0)
	local damageCar = makeCar(inventory, player, 0, 0)
	local keepCar = makeCar(inventory, player, 0, 0)
	local destroyCar = makeCar(inventory, player, 4, 0)
	local success = upgrade:Upgrade(player, successCar.InstanceId, "free-success")
	local damage = upgrade:Upgrade(player, damageCar.InstanceId, "free-damage")
	local keep = upgrade:Upgrade(player, keepCar.InstanceId, "free-keep")
	local destroyed = upgrade:Upgrade(player, destroyCar.InstanceId, "free-destroy")
	assertTrue(success.ok and damage.ok and keep.ok and destroyed.ok, "免費強化失敗")
	assertEqual(success.charged, false, "成功仍標記扣款")
	assertEqual(wallet:GetBalance(player), 50000, "強化後金幣改變")
	assertEqual(debits, 0, "強化呼叫了扣款")
	return "成功、損壞、維持、報廢都沒有扣金幣"
end

local function testPower()
	local inventory = newInventory()
	local player = "power"
	local car = makeCar(inventory, player, 3, 2)
	local upgrade = CarUpgradeService.new({
		inventory = inventory,
		rng = scriptedRng({ firstRoll(3, "Success") }),
	})
	local result = upgrade:Upgrade(player, car.InstanceId, "power")
	assertTrue(result.ok, "性能測試強化失敗")
	assertEqual(result.upgradeLevel, 4, "性能測試等級")
	local expected = CarConfig.calculatePower(4, "Common", 2)
	assertEqual(expected, 167, "既有公式的對照值")
	assertEqual(result.power, expected, "強化後性能")
	assertEqual(result.power, 100 + (10 * 4) + 0 + 27, "性能拆解")
	return "+4、R2、普通車性能為 167"
end

local function testClientCannotChooseOutcome()
	local finalOutcome, consumed = UpgradeConfig.applyProtection("Destroy", UpgradeConfig.Protection.Basic)
	assertEqual(finalOutcome, UpgradeConfig.Outcome.Damage, "普通保護券應把報廢改成損壞")
	assertEqual(consumed, true, "普通保護券在報廢時應消耗")
	local advancedOutcome, advancedConsumed = UpgradeConfig.applyProtection("Destroy", UpgradeConfig.Protection.Advanced)
	assertEqual(advancedOutcome, UpgradeConfig.Outcome.Keep, "高級保護券應改成維持")
	assertEqual(advancedConsumed, true, "高級保護券在報廢時應消耗")
	local kept, keepConsumed = UpgradeConfig.applyProtection("Success", UpgradeConfig.Protection.Advanced)
	assertEqual(kept, UpgradeConfig.Outcome.Success, "非報廢不該被保護券改寫")
	assertEqual(keepConsumed, false, "非報廢不該消耗保護券")

	local inventory = newInventory()
	local player = "client-ticket"
	local car = makeCar(inventory, player, 4, 0)
	local upgrade = CarUpgradeService.new({
		inventory = inventory,
		rng = scriptedRng({ firstRoll(4, "Destroy") }),
	})
	local claimed = upgrade:Upgrade(player, car.InstanceId, "client-claims-ticket", UpgradeConfig.Protection.Basic)
	assertTrue(claimed.ok, "忽略客戶端參數時強化失敗")
	assertEqual(claimed.rawOutcome, UpgradeConfig.Outcome.Destroy, "原始結果")
	assertEqual(claimed.outcome, UpgradeConfig.Outcome.Destroy, "客戶端保護券仍改了結果")
	assertEqual(claimed.protection, UpgradeConfig.Protection.None, "客戶端保護券被採用")
	assertEqual(claimed.protectionConsumed, false, "客戶端保護券被消耗")
	assertEqual(inventory:GetCar(player, car.InstanceId), nil, "報廢車還在")

	local protectedInventory = newInventory()
	local protectedCar = makeCar(protectedInventory, player, 5, 0)
	local protected = CarUpgradeService.new({
		inventory = protectedInventory,
		rng = scriptedRng({ firstRoll(5, "Destroy"), firstRoll(4, "Success") }),
		getServerProtection = function()
			return UpgradeConfig.Protection.Basic
		end,
	})
	local saved = protected:Upgrade(player, protectedCar.InstanceId, "server-ticket")
	assertTrue(saved.ok, "伺服器保護券失敗：" .. tostring(saved.reason))
	assertEqual(saved.rawOutcome, UpgradeConfig.Outcome.Destroy, "伺服器券的原始結果")
	assertEqual(saved.outcome, UpgradeConfig.Outcome.Damage, "伺服器券應改成損壞")
	assertEqual(saved.protectionConsumed, true, "伺服器券應消耗")
	assertEqual(saved.upgradeLevel, 4, "普通保護券後應 -1")
	local notConsumed = protected:Upgrade(player, protectedCar.InstanceId, "server-ticket-success")
	assertEqual(notConsumed.outcome, UpgradeConfig.Outcome.Success, "成功不該被券改掉")
	assertEqual(notConsumed.protectionConsumed, false, "成功不該消耗券")
	assertEqual(notConsumed.upgradeLevel, 5, "成功後等級")
	return "客戶端不能啟用保護券；伺服器注入的券只改報廢"
end

function Tests.run()
	local cases = {
		{ "每個強化階段的機率加總為 100%", testWeightSums },
		{ "+8 大成功率為 1%", testPlusEightGreat },
		{ "+9 大成功率為 0%", testPlusNineGreat },
		{ "+9 報廢率為 80%", testPlusNineDestroy },
		{ "+10 無法繼續強化", testMaxLevelBlocked },
		{ "+0 損壞後仍然是 +0", testDamageFloor },
		{ "+9 成功後變成 +10", testSuccessToTen },
		{ "+8 大成功後變成 +10", testGreatSuccessToTen },
		{ "報廢後車輛從車庫移除", testDestroyRemovesCar },
		{ "無效 InstanceId 不能強化", testInvalidInstance },
		{ "玩家 A 不能強化玩家 B 的車", testOtherPlayersCar },
		{ "重複 requestId 不會重複執行", testDuplicateRequest },
		{ "並行請求不會造成非法等級", testConcurrentUpgrade },
		{ "一萬次模擬符合設定機率", testDistribution },
		{ "強化完全不扣除金幣", testNoGoldCost },
		{ "強化後性能公式正確", testPower },
		{ "客戶端不能指定保護券", testClientCannotChooseOutcome },
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
	print(string.format("CARFORGETAX_UPGRADE_TESTS passed=%d failed=%d", summary.passed, summary.failed))
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
