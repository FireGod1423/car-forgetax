-- 車輛品質、重生加成與性能公式。
-- 抽車機率與價格在 PoolConfig。這裡不放各池權重，避免和池設定各寫一份。
local CarConfig = {}

CarConfig.MinUpgradeLevel = 0
CarConfig.MaxUpgradeLevel = 10
CarConfig.MaxRebirthLevel = 10
CarConfig.BasePower = 100
CarConfig.PowerPerUpgradeLevel = 10

-- T0 單抽價格。T1～T10 的測試價格在 PoolConfig。
CarConfig.SinglePullPrice = 500

-- 僅供測試環境呼叫，不是正式遊戲經濟。
CarConfig.TestStartingGold = 50000

-- UiColor 只給介面、標籤、邊框與特效。車身烤漆在車款目錄，不讀這個色碼。
-- Bonus 前五種沿用既有公式。後面十種是測試加成，還沒定案。
local qualities = {
	{ Id = "Common", DisplayName = "Common", ColorName = "石板灰", UiHex = "#9AA3AE", UiColor = { 154, 163, 174 }, Bonus = 0, AvailableFromRebirth = 0 },
	{ Id = "Uncommon", DisplayName = "Uncommon", ColorName = "草綠", UiHex = "#3FBF79", UiColor = { 63, 191, 121 }, Bonus = 8, AvailableFromRebirth = 0 },
	{ Id = "Rare", DisplayName = "Rare", ColorName = "寶藍", UiHex = "#3D8BFF", UiColor = { 61, 139, 255 }, Bonus = 20, AvailableFromRebirth = 0 },
	{ Id = "Epic", DisplayName = "Epic", ColorName = "紫羅蘭", UiHex = "#9C5CFF", UiColor = { 156, 92, 255 }, Bonus = 38, AvailableFromRebirth = 0 },
	{ Id = "Legendary", DisplayName = "Legendary", ColorName = "金黃", UiHex = "#F5B841", UiColor = { 245, 184, 65 }, Bonus = 65, AvailableFromRebirth = 1 },
	{ Id = "Mythic", DisplayName = "Mythic", ColorName = "玫瑰紅", UiHex = "#ED5067", UiColor = { 237, 80, 103 }, Bonus = 95, AvailableFromRebirth = 2 },
	{ Id = "Divine", DisplayName = "Divine", ColorName = "珍珠白金", UiHex = "#F3E2AD", UiColor = { 243, 226, 173 }, Bonus = 130, AvailableFromRebirth = 3 },
	{ Id = "Celestial", DisplayName = "Celestial", ColorName = "天青", UiHex = "#32D3E0", UiColor = { 50, 211, 224 }, Bonus = 170, AvailableFromRebirth = 4 },
	{ Id = "Transcendent", DisplayName = "Transcendent", ColorName = "洋紅", UiHex = "#E65CE0", UiColor = { 230, 92, 224 }, Bonus = 215, AvailableFromRebirth = 5 },
	{ Id = "Eternal", DisplayName = "Eternal", ColorName = "琥珀橙", UiHex = "#F38A3F", UiColor = { 243, 138, 63 }, Bonus = 265, AvailableFromRebirth = 6 },
	{ Id = "Immortal", DisplayName = "Immortal", ColorName = "翡翠綠", UiHex = "#1AAF94", UiColor = { 26, 175, 148 }, Bonus = 320, AvailableFromRebirth = 7 },
	{ Id = "Astral", DisplayName = "Astral", ColorName = "星光紫", UiHex = "#9D8DFF", UiColor = { 157, 141, 255 }, Bonus = 380, AvailableFromRebirth = 8 },
	{ Id = "Cosmic", DisplayName = "Cosmic", ColorName = "宇宙藍", UiHex = "#415CB8", UiColor = { 65, 92, 184 }, Bonus = 445, AvailableFromRebirth = 9 },
	{ Id = "Primordial", DisplayName = "Primordial", ColorName = "原始銅", UiHex = "#B76447", UiColor = { 183, 100, 71 }, Bonus = 515, AvailableFromRebirth = 10 },
	{ Id = "Singularity", DisplayName = "Singularity", ColorName = "黑曜石", UiHex = "#242933", UiColor = { 36, 41, 51 }, Bonus = 590, AvailableFromRebirth = 10 },
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
local qualityIndex = {}

local function isInteger(value: any): boolean
	return type(value) == "number" and value == value and value % 1 == 0
end

local function validateConfig()
	local seen = {}
	for index, quality in ipairs(qualities) do
		if seen[quality.Id] then
			error("重複的車輛品質：" .. quality.Id)
		end
		seen[quality.Id] = true
		if not isInteger(quality.AvailableFromRebirth) or quality.AvailableFromRebirth < 0 or quality.AvailableFromRebirth > CarConfig.MaxRebirthLevel then
			error("品質開放等級無效：" .. quality.Id)
		end
		if not isInteger(quality.Bonus) then
			error("品質加成必須是整數：" .. quality.Id)
		end
		local color = quality.UiColor
		if type(color) ~= "table" or #color ~= 3 then
			error("品質介面色無效：" .. quality.Id)
		end
		if type(quality.UiHex) ~= "string" or string.sub(quality.UiHex, 1, 1) ~= "#" or #quality.UiHex ~= 7 then
			error("品質色碼無效：" .. quality.Id)
		end
		for channel = 1, 3 do
			local parsed = tonumber(string.sub(quality.UiHex, channel * 2, channel * 2 + 1), 16)
			if not isInteger(color[channel]) or color[channel] < 0 or color[channel] > 255 or color[channel] ~= parsed then
				error("品質介面色與色碼不一致：" .. quality.Id)
			end
		end
		qualityById[quality.Id] = quality
		qualityIndex[quality.Id] = index
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

function CarConfig.qualityRank(qualityId: string): number?
	if type(qualityId) ~= "string" then
		return nil
	end
	return qualityIndex[qualityId]
end

-- 深色介面上幾乎看不見的品質，文字與色塊要另外加亮邊。
	function CarConfig.needsLightRim(qualityId: string): boolean
		return qualityId == "Singularity"
	end

	function CarConfig.needsDarkInk(qualityId: string): boolean
		return qualityId == "Divine"
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

-- Power = 100 + (10 × 強化等級) + 品質加成。
-- 玩家 T 等級與抽車池都不加進這台車。競速加速只走 RankConfig.speedBonus。
function CarConfig.calculatePower(upgradeLevel: number, qualityId: string, rebirthLevel: number): (number?, string?)
	if not CarConfig.isValidUpgradeLevel(upgradeLevel) then
		return nil, "InvalidUpgradeLevel"
	end

	local qualityBonus, qualityReason = CarConfig.getQualityBonus(qualityId)
	if qualityBonus == nil then
		return nil, qualityReason
	end

	local _, rebirthReason = CarConfig.getRebirthBonus(rebirthLevel)
	if rebirthReason ~= nil then
		return nil, rebirthReason
	end

	local power = CarConfig.BasePower
		+ (CarConfig.PowerPerUpgradeLevel * upgradeLevel)
		+ qualityBonus
	return power, nil
end

return CarConfig
