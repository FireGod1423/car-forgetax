-- 強化機率只放在這裡。報廢、損壞、維持、成功、大成功的數字不要寫進其他程式。
local function importCarConfig()
	if game ~= nil then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild("CarConfig"))
	end
	return require("./CarConfig")
end

local CarConfig = importCarConfig()

local UpgradeConfig = {}

UpgradeConfig.Outcome = table.freeze({
	Destroy = "Destroy",
	Damage = "Damage",
	Keep = "Keep",
	Success = "Success",
	GreatSuccess = "GreatSuccess",
})

-- 保護券尚未接道具背包。規則先集中在這，避免以後散落在強化流程裡。
UpgradeConfig.Protection = table.freeze({
	None = "None",
	Basic = "Basic",
	Advanced = "Advanced",
})

local outcomes = {
	{ Id = "Destroy", DisplayName = "報廢" },
	{ Id = "Damage", DisplayName = "損壞" },
	{ Id = "Keep", DisplayName = "維持" },
	{ Id = "Success", DisplayName = "成功" },
	{ Id = "GreatSuccess", DisplayName = "大成功" },
}

local bands = {
	{
		MinLevel = 0,
		MaxLevel = 2,
		Weights = { Destroy = 0, Damage = 5, Keep = 10, Success = 70, GreatSuccess = 15 },
	},
	{
		MinLevel = 3,
		MaxLevel = 4,
		Weights = { Destroy = 3, Damage = 12, Keep = 20, Success = 55, GreatSuccess = 10 },
	},
	{
		MinLevel = 5,
		MaxLevel = 6,
		Weights = { Destroy = 12, Damage = 20, Keep = 25, Success = 37, GreatSuccess = 6 },
	},
	{
		MinLevel = 7,
		MaxLevel = 7,
		Weights = { Destroy = 30, Damage = 25, Keep = 25, Success = 17, GreatSuccess = 3 },
	},
	{
		MinLevel = 8,
		MaxLevel = 8,
		Weights = { Destroy = 50, Damage = 25, Keep = 16, Success = 8, GreatSuccess = 1 },
	},
	{
		MinLevel = 9,
		MaxLevel = 9,
		Weights = { Destroy = 80, Damage = 12, Keep = 5, Success = 3, GreatSuccess = 0 },
	},
}

local function isInteger(value: any): boolean
	return type(value) == "number" and value == value and value % 1 == 0
end

local function isOutcome(outcomeId: any): boolean
	return type(outcomeId) == "string" and UpgradeConfig.Outcome[outcomeId] == outcomeId
end

local function validateConfig()
	local covered = {}
	for _, band in ipairs(bands) do
		if not isInteger(band.MinLevel) or not isInteger(band.MaxLevel) or band.MinLevel > band.MaxLevel then
			error("強化區間無效")
		end

		local total = 0
		for _, outcome in ipairs(outcomes) do
			local weight = band.Weights[outcome.Id]
			if not isInteger(weight) or weight < 0 then
				error(string.format("+%d 的%s機率無效", band.MinLevel, outcome.DisplayName))
			end
			total += weight
		end
		if total ~= 100 then
			error(string.format("+%d～+%d 的機率合計必須是 100，目前是 %d", band.MinLevel, band.MaxLevel, total))
		end

		for level = band.MinLevel, band.MaxLevel do
			if covered[level] then
				error("強化區間重疊：" .. tostring(level))
			end
			covered[level] = true
		end
	end

	for level = CarConfig.MinUpgradeLevel, CarConfig.MaxUpgradeLevel - 1 do
		if not covered[level] then
			error("缺少強化機率：" .. tostring(level))
		end
	end
end

validateConfig()

for index, outcome in ipairs(outcomes) do
	outcomes[index] = table.freeze(outcome)
end
outcomes = table.freeze(outcomes)

for index, band in ipairs(bands) do
	band.Weights = table.freeze(band.Weights)
	bands[index] = table.freeze(band)
end
bands = table.freeze(bands)

function UpgradeConfig.getOutcomes()
	return outcomes
end

function UpgradeConfig.isOutcome(outcomeId: any): boolean
	return isOutcome(outcomeId)
end

function UpgradeConfig.getBand(upgradeLevel: number)
	if not CarConfig.isValidUpgradeLevel(upgradeLevel) then
		return nil, "InvalidUpgradeLevel"
	end
	if upgradeLevel >= CarConfig.MaxUpgradeLevel then
		return nil, "MaxUpgradeLevel"
	end

	for _, band in ipairs(bands) do
		if upgradeLevel >= band.MinLevel and upgradeLevel <= band.MaxLevel then
			return band, nil
		end
	end
	return nil, "MissingBand"
end

function UpgradeConfig.getWeights(upgradeLevel: number)
	local band, reason = UpgradeConfig.getBand(upgradeLevel)
	if band == nil then
		return nil, reason
	end
	return band.Weights, nil
end

function UpgradeConfig.sumWeights(upgradeLevel: number): (number?, string?)
	local weights, reason = UpgradeConfig.getWeights(upgradeLevel)
	if weights == nil then
		return nil, reason
	end

	local total = 0
	for _, outcome in ipairs(outcomes) do
		total += weights[outcome.Id]
	end
	return total, nil
end

-- 依這個等級的設定抽結果。權重為 0 的結果抽不到，也不會把機率分給別的結果。
function UpgradeConfig.rollOutcome(upgradeLevel: number, rng): (string?, string?)
	local weights, reason = UpgradeConfig.getWeights(upgradeLevel)
	if weights == nil then
		return nil, reason
	end
	if rng == nil or type(rng.NextInteger) ~= "function" then
		return nil, "InvalidRandom"
	end

	local total = UpgradeConfig.sumWeights(upgradeLevel)
	local roll = rng:NextInteger(1, total)
	local cursor = 0
	for _, outcome in ipairs(outcomes) do
		cursor += weights[outcome.Id]
		if roll <= cursor then
			return outcome.Id, nil
		end
	end
	return nil, "RollFailed"
end

-- 只有原始結果是報廢時，保護券才會改寫結果並被消耗。其他結果不消耗。
function UpgradeConfig.applyProtection(rawOutcome: string, protectionId: string?): (string?, boolean, string?)
	if not isOutcome(rawOutcome) then
		return nil, false, "InvalidOutcome"
	end

	local protection = if protectionId == nil then UpgradeConfig.Protection.None else protectionId
	if protection == UpgradeConfig.Protection.None then
		return rawOutcome, false, nil
	end
	if protection ~= UpgradeConfig.Protection.Basic and protection ~= UpgradeConfig.Protection.Advanced then
		return nil, false, "InvalidProtection"
	end
	if rawOutcome ~= UpgradeConfig.Outcome.Destroy then
		return rawOutcome, false, nil
	end
	if protection == UpgradeConfig.Protection.Basic then
		return UpgradeConfig.Outcome.Damage, true, nil
	end
	return UpgradeConfig.Outcome.Keep, true, nil
end

-- 把抽到的結果換成下一個強化等級。報廢沒有下一級，呼叫端要刪車。
function UpgradeConfig.nextLevel(currentLevel: number, outcomeId: string): (number?, string?)
	if not CarConfig.isValidUpgradeLevel(currentLevel) then
		return nil, "InvalidUpgradeLevel"
	end
	if not isOutcome(outcomeId) then
		return nil, "InvalidOutcome"
	end
	if outcomeId == UpgradeConfig.Outcome.Destroy then
		return nil, "Destroyed"
	end

	local nextUpgradeLevel = currentLevel
	if outcomeId == UpgradeConfig.Outcome.Damage then
		nextUpgradeLevel = math.max(CarConfig.MinUpgradeLevel, currentLevel - 1)
	elseif outcomeId == UpgradeConfig.Outcome.Success then
		nextUpgradeLevel = math.min(CarConfig.MaxUpgradeLevel, currentLevel + 1)
	elseif outcomeId == UpgradeConfig.Outcome.GreatSuccess then
		nextUpgradeLevel = math.min(CarConfig.MaxUpgradeLevel, currentLevel + 2)
	end
	return nextUpgradeLevel, nil
end

return UpgradeConfig
