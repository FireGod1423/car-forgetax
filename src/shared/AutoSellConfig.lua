-- 自動販賣售價。客戶端與伺服器都讀這一份，售價不由玩家提交。
-- 前五種沿用既有售價。後面十種是測試售價，還沒定案。
local function importCarConfig()
	if game ~= nil then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild("CarConfig"))
	end
	return require("./CarConfig")
end

local CarConfig = importCarConfig()

local AutoSellConfig = {}

local ORDER = {}
local RANK = {}
for index, quality in ipairs(CarConfig.getQualities()) do
	ORDER[index] = quality.Id
	RANK[quality.Id] = index
end
ORDER = table.freeze(ORDER)
RANK = table.freeze(RANK)

local PRICES = table.freeze({
	Common = 100,
	Uncommon = 175,
	Rare = 300,
	Epic = 650,
	Legendary = 2000,
	Mythic = 4500,
	Divine = 9000,
	Celestial = 16000,
	Transcendent = 28000,
	Eternal = 48000,
	Immortal = 80000,
	Astral = 130000,
	Cosmic = 210000,
	Primordial = 340000,
	Singularity = 560000,
})

-- 傳說和更高品質第一次勾選要再確認一次。
local CONFIRM_FROM = RANK.Legendary or 5

AutoSellConfig.Order = ORDER

function AutoSellConfig.rank(qualityId: string): number?
	if type(qualityId) ~= "string" then
		return nil
	end
	return RANK[qualityId]
end

function AutoSellConfig.needsConfirm(qualityId: string): boolean
	local rank = AutoSellConfig.rank(qualityId)
	return rank ~= nil and rank >= CONFIRM_FROM
end

function AutoSellConfig.price(rebirthLevel: number, qualityId: string): number?
	if type(rebirthLevel) ~= "number" or rebirthLevel < 0 or rebirthLevel > 10 or rebirthLevel % 1 ~= 0 or type(qualityId) ~= "string" then
		return nil
	end
	return PRICES[qualityId]
end

-- 只接受品質名稱陣列。空陣列代表全部不賣。不認識的項目整筆拒絕。
function AutoSellConfig.readList(value: any): ({ [string]: boolean }?, { string }?)
	if type(value) ~= "table" then
		return nil, nil
	end
	local set = {}
	local count = 0
	for _, qualityId in ipairs(value) do
		count += 1
		if count > #ORDER or type(qualityId) ~= "string" or RANK[qualityId] == nil then
			return nil, nil
		end
		set[qualityId] = true
	end
	local list = {}
	for _, qualityId in ipairs(ORDER) do
		if set[qualityId] == true then
			table.insert(list, qualityId)
		end
	end
	return set, list
end

function AutoSellConfig.contains(set: any, qualityId: string): boolean
	return type(set) == "table" and type(qualityId) == "string" and set[qualityId] == true
end

function AutoSellConfig.split(set: any, allowed: { string }?): ({ string }, { string })
	local source = if type(allowed) == "table" then allowed else ORDER
	local sells = {}
	local keeps = {}
	for _, qualityId in ipairs(source) do
		if AutoSellConfig.contains(set, qualityId) then
			table.insert(sells, qualityId)
		else
			table.insert(keeps, qualityId)
		end
	end
	return sells, keeps
end

return AutoSellConfig
