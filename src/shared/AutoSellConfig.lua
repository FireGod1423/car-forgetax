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

function AutoSellConfig.covers(maxQuality: string, qualityId: string): boolean
	local maxRank = AutoSellConfig.rank(maxQuality)
	local rank = AutoSellConfig.rank(qualityId)
	if maxRank == nil or rank == nil then
		return false
	end
	return rank <= maxRank
end

function AutoSellConfig.split(maxQuality: string): ({ string }, { string })
	local sells = {}
	local keeps = {}
	for _, qualityId in ipairs(ORDER) do
		if AutoSellConfig.covers(maxQuality, qualityId) then
			table.insert(sells, qualityId)
		else
			table.insert(keeps, qualityId)
		end
	end
	return sells, keeps
end

return AutoSellConfig
