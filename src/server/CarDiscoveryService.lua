-- 車款圖鑑的發現紀錄。這不是車庫清單，車輛報廢後仍保留。
-- 只存在這次伺服器記憶體，關服或玩家離線就清掉。沒有 DataStore。
local function importShared(moduleName: string)
	if game ~= nil then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild(moduleName))
	end
	return require("../shared/" .. moduleName)
end

local CarCatalog = importShared("CarCatalog")

local CarDiscoveryService = {}

local function isPlayerKey(playerKey: any): boolean
	if type(playerKey) == "string" then
		return playerKey ~= ""
	end
	if type(playerKey) == "number" then
		return playerKey == playerKey and playerKey % 1 == 0 and playerKey > 0
	end
	return false
end

function CarDiscoveryService.new()
	local found = {}
	local service = {}

	function service:record(playerKey, modelId: string): boolean
		if not isPlayerKey(playerKey) or type(modelId) ~= "string" or modelId == "" then
			return false
		end
		if CarCatalog.getByModelId(modelId) == nil then
			return false
		end
		local bucket = found[playerKey]
		if bucket == nil then
			bucket = {}
			found[playerKey] = bucket
		end
		bucket[modelId] = true
		return true
	end

	function service:list(playerKey): { string }
		local ids = {}
		local bucket = found[playerKey]
		if bucket ~= nil then
			for modelId in pairs(bucket) do
				table.insert(ids, modelId)
			end
			table.sort(ids)
		end
		return ids
	end

	function service:clear(playerKey)
		found[playerKey] = nil
	end

	return service
end

return CarDiscoveryService
