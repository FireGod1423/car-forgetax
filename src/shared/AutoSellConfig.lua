-- R0 自動販賣售價。客戶端與伺服器都讀這一份，售價不由玩家提交。
local AutoSellConfig = {}

local ORDER = table.freeze({ "Common", "Uncommon", "Rare", "Epic", "Legendary" })

local RANK = table.freeze({
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
})

-- 目前只有重生 0。之後的重生等級要加售價時，只改這裡。
local PRICES_R0 = table.freeze({
	Common = 100,
	Uncommon = 175,
	Rare = 300,
	Epic = 650,
	Legendary = 2000,
})

AutoSellConfig.Order = ORDER

function AutoSellConfig.rank(qualityId: string): number?
	if type(qualityId) ~= "string" then
		return nil
	end
	return RANK[qualityId]
end

function AutoSellConfig.price(rebirthLevel: number, qualityId: string): number?
	if rebirthLevel ~= 0 or type(qualityId) ~= "string" then
		return nil
	end
	return PRICES_R0[qualityId]
end

-- 只接受品質名稱陣列。空陣列代表全部不賣。不認識的項目整筆拒絕，避免沿用最高品質門檻。
function AutoSellConfig.readList(value: any): ({ [string]: boolean }?, { string }?)
	if type(value) ~= "table" then
		return nil, nil
	end
	local set = {}
	for index, qualityId in ipairs(value) do
		if index > #ORDER or type(qualityId) ~= "string" or RANK[qualityId] == nil then
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

function AutoSellConfig.split(set: any): ({ string }, { string })
	local sells = {}
	local keeps = {}
	for _, qualityId in ipairs(ORDER) do
		if AutoSellConfig.contains(set, qualityId) then
			table.insert(sells, qualityId)
		else
			table.insert(keeps, qualityId)
		end
	end
	return sells, keeps
end

return AutoSellConfig
