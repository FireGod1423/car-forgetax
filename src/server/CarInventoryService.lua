-- 玩家車輛庫存。第一版只放在伺服器記憶體，關服後測試車會消失，尚未接 DataStore。
local function importShared(moduleName: string)
	if game ~= nil then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild(moduleName))
	end
	return require("../shared/" .. moduleName)
end

local CarConfig = importShared("CarConfig")
local CarCatalog = importShared("CarCatalog")
local RandomSource = importShared("RandomSource")

local CarInventoryService = {}

CarInventoryService.Reason = table.freeze({
	InvalidPlayer = "InvalidPlayer",
	UnknownModel = "UnknownModel",
	InvalidQuality = "InvalidQuality",
	InvalidRebirth = "InvalidRebirth",
	LockedModel = "LockedModel",
	IdCollision = "IdCollision",
	UnknownCar = "UnknownCar",
	InvalidUpgradeLevel = "InvalidUpgradeLevel",
	InvalidRecord = "InvalidRecord",
	DuplicateInstanceId = "DuplicateInstanceId",
	InvalidInstanceId = "InvalidInstanceId",
	InvalidTimestamp = "InvalidTimestamp",
})

local function isPlayerKey(playerKey: any): boolean
	if type(playerKey) == "string" then
		return playerKey ~= ""
	end
	if type(playerKey) == "number" then
		return CarConfig.isInteger(playerKey) and playerKey > 0
	end
	return false
end

local function copyRecord(record)
	-- 回傳複本並凍結，呼叫端改欄位不會影響庫存。
	return table.freeze({
		InstanceId = record.InstanceId,
		ModelId = record.ModelId,
		UpgradeLevel = record.UpgradeLevel,
		AcquiredRebirth = record.AcquiredRebirth,
		CreatedAt = record.CreatedAt,
	})
end

local function validateRecord(data, model)
	if type(data) ~= "table" then
		return false, CarInventoryService.Reason.InvalidRecord
	end
	if type(data.InstanceId) ~= "string" or data.InstanceId == "" then
		return false, CarInventoryService.Reason.InvalidInstanceId
	end
	if data.ModelId ~= model.ModelId then
		return false, CarInventoryService.Reason.UnknownModel
	end
	if not CarConfig.isValidQuality(model.Quality) then
		return false, CarInventoryService.Reason.InvalidQuality
	end
	if data.Quality ~= nil and data.Quality ~= model.Quality then
		return false, CarInventoryService.Reason.InvalidQuality
	end
	if not CarConfig.isValidUpgradeLevel(data.UpgradeLevel) then
		return false, CarInventoryService.Reason.InvalidUpgradeLevel
	end
	if not CarConfig.isInteger(data.AcquiredRebirth) or data.AcquiredRebirth < 0 then
		return false, CarInventoryService.Reason.InvalidRebirth
	end
	if data.AcquiredRebirth < model.UnlockRebirth then
		return false, CarInventoryService.Reason.LockedModel
	end
	if not CarConfig.isInteger(data.CreatedAt) or data.CreatedAt < 0 then
		return false, CarInventoryService.Reason.InvalidTimestamp
	end
	return true, nil
end

function CarInventoryService.new(options)
	options = options or {}
	local catalog = options.catalog or CarCatalog
	local now = options.now or os.time
	local idRng = options.rng
	local sequence = 0

	local function defaultNewId()
		-- 有自訂 ID 時不會用到隨機數，避免測試環境沒有 Roblox Random 就失敗。
		if idRng == nil then
			idRng = RandomSource.new()
		end
		sequence += 1
		return string.format("car_%d_%08x", sequence, idRng:NextInteger(0, 0x7fffffff))
	end

	local newId = options.newId or defaultNewId
	local carsByPlayer = {}
	local orderByPlayer = {}
	local usedIds = {}
	local service = {}

	local function findStored(instanceId: string)
		for _, bucket in pairs(carsByPlayer) do
			local record = bucket[instanceId]
			if record ~= nil then
				return record
			end
		end
		return nil
	end

	function service:ValidateCar(data)
		if type(data) ~= "table" or type(data.ModelId) ~= "string" then
			return false, CarInventoryService.Reason.InvalidRecord
		end

		local model = catalog.getByModelId(data.ModelId)
		if model == nil then
			return false, CarInventoryService.Reason.UnknownModel
		end

		local ok, reason = validateRecord(data, model)
		if not ok then
			return false, reason
		end

		-- 同一個 ID 若已經屬於另一筆內容，就視為重複，不覆蓋舊車。
		local stored = findStored(data.InstanceId)
		if stored ~= nil then
			local sameRecord = stored.ModelId == data.ModelId
				and stored.UpgradeLevel == data.UpgradeLevel
				and stored.AcquiredRebirth == data.AcquiredRebirth
				and stored.CreatedAt == data.CreatedAt
			if not sameRecord then
				return false, CarInventoryService.Reason.DuplicateInstanceId
			end
		end

		return true, nil
	end

	function service:CreateCar(playerKey, modelId, acquiredRebirth)
		if not isPlayerKey(playerKey) then
			return nil, CarInventoryService.Reason.InvalidPlayer
		end

		local model = catalog.getByModelId(modelId)
		if model == nil then
			return nil, CarInventoryService.Reason.UnknownModel
		end
		if not CarConfig.isValidQuality(model.Quality) then
			return nil, CarInventoryService.Reason.InvalidQuality
		end
		if not CarConfig.isInteger(acquiredRebirth) or acquiredRebirth < 0 then
			return nil, CarInventoryService.Reason.InvalidRebirth
		end
		if acquiredRebirth < model.UnlockRebirth then
			return nil, CarInventoryService.Reason.LockedModel
		end

		-- ID 只由伺服器產生。碰撞時重試，仍碰撞就放棄，不寫入半筆資料。
		local instanceId = nil
		for _ = 1, 8 do
			local candidate = newId()
			if type(candidate) == "string" and candidate ~= "" and usedIds[candidate] ~= true then
				instanceId = candidate
				break
			end
		end
		if instanceId == nil then
			return nil, CarInventoryService.Reason.IdCollision
		end

		local record = {
			InstanceId = instanceId,
			ModelId = model.ModelId,
			UpgradeLevel = CarConfig.MinUpgradeLevel,
			AcquiredRebirth = acquiredRebirth,
			CreatedAt = now(),
		}
		local ok, reason = validateRecord(record, model)
		if not ok then
			return nil, reason
		end

		record = table.freeze(record)
		usedIds[instanceId] = true

		local bucket = carsByPlayer[playerKey]
		if bucket == nil then
			bucket = {}
			carsByPlayer[playerKey] = bucket
			orderByPlayer[playerKey] = {}
		end
		bucket[instanceId] = record
		table.insert(orderByPlayer[playerKey], instanceId)
		return copyRecord(record), nil
	end

	function service:GetCar(playerKey, instanceId)
		if not isPlayerKey(playerKey) then
			return nil, CarInventoryService.Reason.InvalidPlayer
		end
		local bucket = carsByPlayer[playerKey]
		local record = if bucket ~= nil then bucket[instanceId] else nil
		if record == nil then
			return nil, CarInventoryService.Reason.UnknownCar
		end
		return copyRecord(record), nil
	end

	function service:ListCars(playerKey)
		if not isPlayerKey(playerKey) then
			return nil, CarInventoryService.Reason.InvalidPlayer
		end

		local list = {}
		local order = orderByPlayer[playerKey]
		local bucket = carsByPlayer[playerKey]
		if order ~= nil and bucket ~= nil then
			for _, instanceId in ipairs(order) do
				local record = bucket[instanceId]
				if record ~= nil then
					table.insert(list, copyRecord(record))
				end
			end
		end
		return table.freeze(list), nil
	end

	-- 刪車後不回收 ID，避免之後的新車拿到舊識別碼。
	function service:RemoveCar(playerKey, instanceId)
		if not isPlayerKey(playerKey) then
			return false, CarInventoryService.Reason.InvalidPlayer
		end

		local bucket = carsByPlayer[playerKey]
		if bucket == nil or bucket[instanceId] == nil then
			return false, CarInventoryService.Reason.UnknownCar
		end

		bucket[instanceId] = nil
		local order = orderByPlayer[playerKey]
		for index, storedId in ipairs(order) do
			if storedId == instanceId then
				table.remove(order, index)
				break
			end
		end
		return true, nil
	end

	return service
end

return CarInventoryService
