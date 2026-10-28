-- T0～T10 抽車池。價格、品質與機率只維護這一份。
-- 權重總和 10000，1 點等於 0.01%。這是目前指定的開發測試機率。
-- 每個池只包含表上的品質，不再從 Common 一路排到該池上限。
local function importCarConfig()
	if game ~= nil then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild("CarConfig"))
	end
	return require("./CarConfig")
end

local CarConfig = importCarConfig()

local PoolConfig = {}

local ORDER = {
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
	"Divine",
	"Celestial",
	"Transcendent",
	"Eternal",
	"Immortal",
	"Astral",
	"Cosmic",
	"Primordial",
	"Singularity",
}

local function weights(entries: { [string]: number }): { [string]: number }
	return entries
end

local definitions = {
	{
		Id = "T0",
		MinRank = 0,
		DealerName = "Rusty's Scrap Lottery",
		NpcName = "Rusty",
		MaxQuality = "Epic",
		Price = nil,
		UseLivePrice = true,
		PriceStatus = "live",
		OddsStatus = "specified",
		Accent = { 196, 122, 64 },
		Weights = weights({ Common = 5000, Uncommon = 3000, Rare = 1500, Epic = 500 }),
	},
	{
		Id = "T1",
		MinRank = 1,
		DealerName = "Used Car Market",
		NpcName = "Mick",
		MaxQuality = "Legendary",
		Price = 1000,
		PriceStatus = "test",
		OddsStatus = "specified",
		Accent = { 126, 140, 112 },
		Weights = weights({ Common = 4900, Uncommon = 3000, Rare = 1500, Epic = 400, Legendary = 200 }),
	},
	{
		Id = "T2",
		MinRank = 2,
		DealerName = "Street Garage",
		NpcName = "Nora",
		MaxQuality = "Mythic",
		Price = 2000,
		PriceStatus = "test",
		OddsStatus = "specified",
		Accent = { 214, 168, 64 },
		Weights = weights({ Uncommon = 4900, Rare = 3000, Epic = 1500, Legendary = 500, Mythic = 100 }),
	},
	{
		Id = "T3",
		MinRank = 3,
		DealerName = "Performance Motors",
		NpcName = "Victor",
		MaxQuality = "Divine",
		Price = 4000,
		PriceStatus = "test",
		OddsStatus = "specified",
		Accent = { 176, 64, 58 },
		Weights = weights({ Rare = 4950, Epic = 3000, Legendary = 1500, Mythic = 500, Divine = 50 }),
	},
	{
		Id = "T4",
		MinRank = 4,
		DealerName = "Elite Auto Gallery",
		NpcName = "Elise",
		MaxQuality = "Celestial",
		Price = 7500,
		PriceStatus = "test",
		OddsStatus = "specified",
		Accent = { 212, 196, 150 },
		Weights = weights({ Epic = 4980, Legendary = 3000, Mythic = 1500, Divine = 500, Celestial = 20 }),
	},
	{
		Id = "T5",
		MinRank = 5,
		DealerName = "Motorsport Division",
		NpcName = "Marco",
		MaxQuality = "Transcendent",
		Price = 14000,
		PriceStatus = "test",
		OddsStatus = "specified",
		Accent = { 72, 122, 196 },
		Weights = weights({ Legendary = 4990, Mythic = 3000, Divine = 1500, Celestial = 500, Transcendent = 10 }),
	},
	{
		Id = "T6",
		MinRank = 6,
		DealerName = "Grand Prix Workshop",
		NpcName = "Helen",
		MaxQuality = "Eternal",
		Price = 25000,
		PriceStatus = "test",
		OddsStatus = "specified",
		Accent = { 168, 48, 52 },
		Weights = weights({ Mythic = 4990, Divine = 3000, Celestial = 1500, Transcendent = 500, Eternal = 10 }),
	},
	{
		Id = "T7",
		MinRank = 7,
		DealerName = "Hypercar Vault",
		NpcName = "Quinn",
		MaxQuality = "Immortal",
		Price = 45000,
		PriceStatus = "test",
		OddsStatus = "specified",
		Accent = { 126, 108, 168 },
		Weights = weights({ Divine = 4990, Celestial = 3000, Transcendent = 1500, Eternal = 500, Immortal = 10 }),
	},
	{
		Id = "T8",
		MinRank = 8,
		DealerName = "Future Performance Lab",
		NpcName = "Iris",
		MaxQuality = "Astral",
		Price = 80000,
		PriceStatus = "test",
		OddsStatus = "specified",
		Accent = { 64, 186, 196 },
		Weights = weights({ Celestial = 4990, Transcendent = 3000, Eternal = 1500, Immortal = 500, Astral = 10 }),
	},
	{
		Id = "T9",
		MinRank = 9,
		DealerName = "Mythic Motors",
		NpcName = "Cass",
		MaxQuality = "Cosmic",
		Price = 140000,
		PriceStatus = "test",
		OddsStatus = "specified",
		Accent = { 196, 72, 96 },
		Weights = weights({ Transcendent = 4990, Eternal = 3000, Immortal = 1500, Astral = 500, Cosmic = 10 }),
	},
	{
		Id = "T10",
		MinRank = 10,
		DealerName = "Apex Collection",
		NpcName = "Apex",
		MaxQuality = "Singularity",
		Price = 250000,
		PriceStatus = "test",
		OddsStatus = "specified",
		Accent = { 228, 226, 220 },
		Weights = weights({ Immortal = 4999, Astral = 3000, Cosmic = 1500, Primordial = 500, Singularity = 1 }),
	},
}

-- 每個車商只對應一個池。T1～T10 的攤位還沒做進場景，代號先留在這裡，避免客戶端自己挑池。
local STATION_BY_POOL = {
	T0 = "R0Dealer",
	T1 = "T1Dealer",
	T2 = "T2Dealer",
	T3 = "T3Dealer",
	T4 = "T4Dealer",
	T5 = "T5Dealer",
	T6 = "T6Dealer",
	T7 = "T7Dealer",
	T8 = "T8Dealer",
	T9 = "T9Dealer",
	T10 = "T10Dealer",
}

local pools = {}
local poolsById = {}
local poolByStation = {}

local function validate()
	if #definitions ~= 11 then
		error("抽車池必須是 T0 到 T10")
	end
	for index, definition in ipairs(definitions) do
		if definition.MinRank ~= index - 1 then
			error("抽車池等級不連續：" .. definition.Id)
		end
		if definition.Id ~= "T" .. tostring(definition.MinRank) then
			error("抽車池代號不對：" .. definition.Id)
		end
		local included = {}
		local total = 0
		local lastId = nil
		for _, qualityId in ipairs(ORDER) do
			local weight = definition.Weights[qualityId]
			if weight ~= nil then
				if weight <= 0 or weight % 1 ~= 0 then
					error("抽車權重必須是正整數：" .. definition.Id .. " " .. qualityId)
				end
				if CarConfig.getQuality(qualityId) == nil then
					error("抽車池用了不存在的品質：" .. qualityId)
				end
				total += weight
				lastId = qualityId
				table.insert(included, qualityId)
			end
		end
		if total ~= 10000 then
			error(definition.Id .. " 機率合計不是 10000，而是 " .. tostring(total))
		end
		local expectedCount = if definition.Id == "T0" then 4 else 5
		if #included ~= expectedCount then
			error(definition.Id .. " 品質數量應為 " .. tostring(expectedCount))
		end
		if lastId ~= definition.MaxQuality then
			error(definition.Id .. " 最高品質不是權重表的最後一檔")
		end
		local maxQuality = CarConfig.getQuality(definition.MaxQuality)
		if maxQuality == nil or maxQuality.AvailableFromRebirth > definition.MinRank then
			error(definition.Id .. " 的最高品質還沒到這個等級")
		end
		for _, qualityId in ipairs(included) do
			local quality = CarConfig.getQuality(qualityId)
			if quality.AvailableFromRebirth > definition.MinRank then
				error(definition.Id .. " 含有尚未開放的品質 " .. qualityId)
			end
		end
		if definition.UseLivePrice ~= true then
			if type(definition.Price) ~= "number" or definition.Price <= 0 or definition.Price % 1 ~= 0 then
				error("抽車價格無效：" .. definition.Id)
			end
		end
		local stationId = STATION_BY_POOL[definition.Id]
		if type(stationId) ~= "string" or poolByStation[stationId] ~= nil then
			error("抽車池缺少專用車商：" .. definition.Id)
		end
		local frozenWeights = table.freeze(definition.Weights)
		local pool = table.freeze({
			Id = definition.Id,
			StationId = stationId,
			MinRank = definition.MinRank,
			DealerName = definition.DealerName,
			NpcName = definition.NpcName,
			MaxQuality = definition.MaxQuality,
			Price = definition.Price,
			UseLivePrice = definition.UseLivePrice == true,
			PriceStatus = definition.PriceStatus,
			OddsStatus = definition.OddsStatus,
			Accent = table.freeze(definition.Accent),
			Weights = frozenWeights,
			Qualities = table.freeze(included),
		})
		table.insert(pools, pool)
		poolsById[pool.Id] = pool
		poolByStation[stationId] = pool
	end
end

validate()
pools = table.freeze(pools)

function PoolConfig.getAll()
	return pools
end

function PoolConfig.station(poolId: string): string?
	local pool = poolsById[poolId]
	if pool == nil then
		return nil
	end
	return pool.StationId
end

function PoolConfig.poolForStation(stationId: string)
	if type(stationId) ~= "string" then
		return nil
	end
	return poolByStation[stationId]
end

function PoolConfig.get(poolId: string)
	if type(poolId) ~= "string" then
		return nil
	end
	return poolsById[poolId]
end

function PoolConfig.price(poolId: string): number?
	local pool = poolsById[poolId]
	if pool == nil then
		return nil
	end
	if pool.UseLivePrice then
		return CarConfig.SinglePullPrice
	end
	return pool.Price
end

function PoolConfig.sumWeights(poolId: string): number?
	local pool = poolsById[poolId]
	if pool == nil then
		return nil
	end
	local total = 0
	for _, qualityId in ipairs(pool.Qualities) do
		total += pool.Weights[qualityId]
	end
	return total
end

function PoolConfig.contains(poolId: string, qualityId: string): boolean
	local pool = poolsById[poolId]
	if pool == nil or type(qualityId) ~= "string" then
		return false
	end
	local weight = pool.Weights[qualityId]
	return type(weight) == "number" and weight > 0
end

function PoolConfig.unlocked(poolId: string, rebirthLevel: number): boolean
	local pool = poolsById[poolId]
	if pool == nil or type(rebirthLevel) ~= "number" then
		return false
	end
	return rebirthLevel >= pool.MinRank
end

function PoolConfig.roll(poolId: string, rng): (string?, string?)
	local pool = poolsById[poolId]
	if pool == nil then
		return nil, "InvalidPool"
	end
	local total = PoolConfig.sumWeights(poolId)
	if total == nil or total <= 0 then
		return nil, "InvalidWeight"
	end
	if rng == nil or type(rng.NextInteger) ~= "function" then
		return nil, "InvalidRandom"
	end
	local roll = rng:NextInteger(1, total)
	local cursor = 0
	for _, qualityId in ipairs(pool.Qualities) do
		cursor += pool.Weights[qualityId]
		if roll <= cursor then
			return qualityId, nil
		end
	end
	return nil, "RollFailed"
end

-- 1 點權重 = 0.01%。用整數組字，避免 49.5 被四捨五入成 50，或 0.01 被收成 0。
function PoolConfig.percentLabel(weight: number): string
	if type(weight) ~= "number" then
		return "0"
	end
	local whole = math.floor(weight / 100)
	local frac = weight % 100
	if frac == 0 then
		return tostring(whole)
	end
	local digits = string.format("%02d", frac)
	digits = string.gsub(digits, "0+$", "")
	return tostring(whole) .. "." .. digits
end

-- 給介面與 GetState。數字就是這個池真正使用的權重。
function PoolConfig.describe(poolId: string, rebirthLevel: number)
	local pool = poolsById[poolId]
	if pool == nil then
		return nil
	end
	local total = PoolConfig.sumWeights(poolId) or 0
	local rates = {}
	for _, qualityId in ipairs(pool.Qualities) do
		local quality = CarConfig.getQuality(qualityId)
		local weight = pool.Weights[qualityId]
		table.insert(rates, {
			qualityId = qualityId,
			displayName = if quality ~= nil then quality.DisplayName else qualityId,
			weight = weight,
			percent = if total > 0 then (weight / total) * 100 else 0,
			percentText = PoolConfig.percentLabel(weight),
			uiColor = if quality ~= nil then quality.UiColor else { 180, 180, 180 },
		})
	end
	local rank = rebirthLevel
	if type(rank) ~= "number" then
		rank = 0
	end
	return {
		id = pool.Id,
		minRank = pool.MinRank,
		dealerName = pool.DealerName,
		npcName = pool.NpcName,
		maxQuality = pool.MaxQuality,
		price = PoolConfig.price(poolId),
		priceStatus = pool.PriceStatus,
		oddsStatus = pool.OddsStatus,
		accent = pool.Accent,
		unlocked = rank >= pool.MinRank,
		qualities = pool.Qualities,
		rates = rates,
	}
end

return PoolConfig
