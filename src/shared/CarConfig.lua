-- 車輛品質、重生加成與性能公式。正式抽車必須讀這裡的數字，不要在別處再寫一份。
local CarConfig = {}

CarConfig.MinUpgradeLevel = 0
CarConfig.MaxUpgradeLevel = 10
CarConfig.MaxRebirthLevel = 10
CarConfig.BasePower = 100
CarConfig.PowerPerUpgradeLevel = 10

-- 單抽價格。之後只改這個數字，不要改抽車流程。
CarConfig.SinglePullPrice = 500

-- 僅供測試環境呼叫，不是正式遊戲經濟。
CarConfig.TestStartingGold = 50000

local qualities = {
	{
		Id = "Common",
		DisplayName = "Common",
		ColorName = "White",
		Weight = 50,
		Bonus = 0,
		AvailableFromRebirth = 0,
	},
	{
		Id = "Uncommon",
		DisplayName = "Uncommon",
		ColorName = "Green",
		Weight = 30,
		Bonus = 8,
		AvailableFromRebirth = 0,
	},
	{
		Id = "Rare",
		DisplayName = "Rare",
		ColorName = "Blue",
		Weight = 15,
		Bonus = 20,
		AvailableFromRebirth = 0,
	},
	{
		Id = "Epic",
		DisplayName = "Epic",
		ColorName = "Purple",
		Weight = 4,
		Bonus = 38,
		AvailableFromRebirth = 0,
	},
	{
		Id = "Legendary",
		DisplayName = "Legendary",
		ColorName = "Orange",
		Weight = 1,
		Bonus = 65,
		AvailableFromRebirth = 0,
	},
}

-- 重生加成先用固定表。R11 以上尚未定義，公式會拒絕，避免算出假性能。
local rebirthBonusByLevel = {
	[0] = 0,
	[1] = 12,
	[2] = 27,
	[3] = 45,
	[4] = 66,
	[5] = 90,
	[6] = 117,
	[7] = 147,
	[8] = 180,
	[9] = 216,
	[10] = 255,
}

local qualityById = {}

local function isInteger(value: any): boolean
	return type(value) == "number" and value == value and value % 1 == 0
end

local function validateConfig()
	local seen = {}
	for _, quality in ipairs(qualities) do
		if seen[quality.Id] then
			error("重複的車輛品質：" .. quality.Id)
		end
		seen[quality.Id] = true
		if quality.AvailableFromRebirth ~= 0 then
			error("所有品質目前都必須從 R0 開放：" .. quality.Id)
		end
		if not isInteger(quality.Weight) or quality.Weight < 0 then
			error("品質權重必須是非負整數：" .. quality.Id)
		end
		if not isInteger(quality.Bonus) then
			error("品質加成必須是整數：" .. quality.Id)
		end
		qualityById[quality.Id] = quality
	end

	for level = 0, CarConfig.MaxRebirthLevel do
		if not isInteger(rebirthBonusByLevel[level]) then
			error("缺少重生加成：" .. tostring(level))
		end
	end
end

validateConfig()

for index, quality in ipairs(qualities) do
	qualities[index] = table.freeze(quality)
end
qualities = table.freeze(qualities)
rebirthBonusByLevel = table.freeze(rebirthBonusByLevel)

CarConfig.isInteger = isInteger

function CarConfig.getQualities()
	return qualities
end

function CarConfig.isValidQuality(qualityId: any): boolean
	return type(qualityId) == "string" and qualityById[qualityId] ~= nil
end

function CarConfig.getQuality(qualityId: string)
	return qualityById[qualityId]
end

function CarConfig.sumWeights(): number
	local total = 0
	for _, quality in ipairs(qualities) do
		total += quality.Weight
	end
	return total
end

function CarConfig.getQualityBonus(qualityId: string): (number?, string?)
	local quality = qualityById[qualityId]
	if quality == nil then
		return nil, "InvalidQuality"
	end
	return quality.Bonus, nil
end

function CarConfig.getRebirthBonus(rebirthLevel: number): (number?, string?)
	if not isInteger(rebirthLevel) then
		return nil, "InvalidRebirth"
	end
	local bonus = rebirthBonusByLevel[rebirthLevel]
	if bonus == nil then
		return nil, "InvalidRebirth"
	end
	return bonus, nil
end

function CarConfig.isValidUpgradeLevel(upgradeLevel: any): boolean
	return isInteger(upgradeLevel)
		and upgradeLevel >= CarConfig.MinUpgradeLevel
		and upgradeLevel <= CarConfig.MaxUpgradeLevel
end

-- Power = 100 + (10 × 強化等級) + 品質加成 + 重生加成
function CarConfig.calculatePower(upgradeLevel: number, qualityId: string, rebirthLevel: number): (number?, string?)
	if not CarConfig.isValidUpgradeLevel(upgradeLevel) then
		return nil, "InvalidUpgradeLevel"
	end

	local qualityBonus, qualityReason = CarConfig.getQualityBonus(qualityId)
	if qualityBonus == nil then
		return nil, qualityReason
	end

	local rebirthBonus, rebirthReason = CarConfig.getRebirthBonus(rebirthLevel)
	if rebirthBonus == nil then
		return nil, rebirthReason
	end

	local power = CarConfig.BasePower
		+ (CarConfig.PowerPerUpgradeLevel * upgradeLevel)
		+ qualityBonus
		+ rebirthBonus
	return power, nil
end

-- 依設定權重抽品質。沒有車款時也不能改走別的品質。
function CarConfig.rollQuality(rng): (string?, string?)
	local total = CarConfig.sumWeights()
	if total <= 0 then
		return nil, "InvalidWeight"
	end
	if rng == nil or type(rng.NextInteger) ~= "function" then
		return nil, "InvalidRandom"
	end

	local roll = rng:NextInteger(1, total)
	local cursor = 0
	for _, quality in ipairs(qualities) do
		cursor += quality.Weight
		if roll <= cursor then
			return quality.Id, nil
		end
	end

	return nil, "RollFailed"
end

return CarConfig
