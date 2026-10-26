-- 免費強化。結果只由伺服器抽取，客戶端不能指定機率、等級或保護券。
local function importShared(moduleName: string)
	if game ~= nil then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild(moduleName))
	end
	return require("../shared/" .. moduleName)
end

local CarConfig = importShared("CarConfig")
local CarCatalog = importShared("CarCatalog")
local UpgradeConfig = importShared("UpgradeConfig")
local RandomSource = importShared("RandomSource")

local CarUpgradeService = {}

CarUpgradeService.Reason = table.freeze({
	InvalidPlayer = "InvalidPlayer",
	InvalidRequest = "InvalidRequest",
	InvalidInstanceId = "InvalidInstanceId",
	UnknownCar = "UnknownCar",
	InvalidUpgradeLevel = "InvalidUpgradeLevel",
	MaxUpgradeLevel = "MaxUpgradeLevel",
	UpgradeInProgress = "UpgradeInProgress",
	RequestInProgress = "RequestInProgress",
	InvalidProtection = "InvalidProtection",
	UpdateFailed = "UpdateFailed",
	InternalError = "InternalError",
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

local function copyResult(result)
	local copy = {}
	for key, value in pairs(result) do
		copy[key] = value
	end
	return copy
end

function CarUpgradeService.new(options)
	if type(options) ~= "table" or options.inventory == nil then
		error("CarUpgradeService 需要 inventory")
	end

	local inventory = options.inventory
	local catalog = options.catalog or CarCatalog
	local rng = options.rng or RandomSource.new()
	-- 未來的道具背包必須在伺服器建立服務時注入。Upgrade 不接受客戶端傳來的券。
	local getServerProtection = options.getServerProtection
	local cached = {}
	local pending = {}
	local carLocks = {}
	local service = {}

	local function cacheKey(playerKey, requestId: string): string
		return tostring(playerKey) .. "\0" .. requestId
	end

	local function fail(requestId, reason: string, extra)
		local result = {
			ok = false,
			reason = reason,
			requestId = requestId,
			charged = false,
		}
		if extra ~= nil then
			for key, value in pairs(extra) do
				result[key] = value
			end
		end
		return result
	end

	-- 多出來的參數直接丟掉，避免客戶端把保護券或指定結果塞進來。
	function service:Upgrade(playerKey, instanceId, requestId)
		if not isPlayerKey(playerKey) then
			return fail(requestId, CarUpgradeService.Reason.InvalidPlayer)
		end
		if type(requestId) ~= "string" or requestId == "" then
			return fail(requestId, CarUpgradeService.Reason.InvalidRequest)
		end
		if type(instanceId) ~= "string" or instanceId == "" then
			return fail(requestId, CarUpgradeService.Reason.InvalidInstanceId)
		end

		local key = cacheKey(playerKey, requestId)
		local previous = cached[key]
		if previous ~= nil then
			local replay = copyResult(previous)
			replay.replayed = true
			return replay
		end
		if pending[key] == true then
			return fail(requestId, CarUpgradeService.Reason.RequestInProgress)
		end

		local car, carReason = inventory:GetCar(playerKey, instanceId)
		if car == nil then
			local result = fail(requestId, carReason or CarUpgradeService.Reason.UnknownCar)
			cached[key] = result
			return copyResult(result)
		end
		if not CarConfig.isValidUpgradeLevel(car.UpgradeLevel) then
			local result = fail(requestId, CarUpgradeService.Reason.InvalidUpgradeLevel, {
				previousLevel = car.UpgradeLevel,
			})
			cached[key] = result
			return copyResult(result)
		end
		if car.UpgradeLevel >= CarConfig.MaxUpgradeLevel then
			local result = fail(requestId, CarUpgradeService.Reason.MaxUpgradeLevel, {
				previousLevel = car.UpgradeLevel,
			})
			cached[key] = result
			return copyResult(result)
		end

		-- 同一台車已有強化在進行時直接拒絕，不排隊，也不寫進完成紀錄。
		if carLocks[instanceId] == true then
			return fail(requestId, CarUpgradeService.Reason.UpgradeInProgress, {
				instanceId = instanceId,
			})
		end

		pending[key] = true
		carLocks[instanceId] = true

		local completed, outcome = pcall(function()
			local rawOutcome, rollReason = UpgradeConfig.rollOutcome(car.UpgradeLevel, rng)
			if rawOutcome == nil then
				return fail(requestId, rollReason or CarUpgradeService.Reason.InternalError, {
					instanceId = instanceId,
					previousLevel = car.UpgradeLevel,
				})
			end

			local protectionId = UpgradeConfig.Protection.None
			if getServerProtection ~= nil then
				local resolved = getServerProtection(playerKey, instanceId)
				protectionId = if resolved == nil then UpgradeConfig.Protection.None else resolved
			end

			local outcomeId, consumed, protectionReason = UpgradeConfig.applyProtection(rawOutcome, protectionId)
			if outcomeId == nil then
				return fail(requestId, protectionReason or CarUpgradeService.Reason.InvalidProtection, {
					instanceId = instanceId,
					previousLevel = car.UpgradeLevel,
					rawOutcome = rawOutcome,
				})
			end

			local model = catalog.getByModelId(car.ModelId)
			if model == nil then
				return fail(requestId, CarUpgradeService.Reason.UpdateFailed, {
					detail = "UnknownModel",
					instanceId = instanceId,
					previousLevel = car.UpgradeLevel,
					rawOutcome = rawOutcome,
				})
			end

			if outcomeId == UpgradeConfig.Outcome.Destroy then
				local removed, removeReason = inventory:RemoveCar(playerKey, instanceId)
				if removed ~= true then
					return fail(requestId, CarUpgradeService.Reason.UpdateFailed, {
						detail = removeReason,
						instanceId = instanceId,
						previousLevel = car.UpgradeLevel,
						rawOutcome = rawOutcome,
						outcome = outcomeId,
					})
				end

				-- 報廢後車庫裡不再留這台車，也不能再對它計算性能。
				return {
					ok = true,
					requestId = requestId,
					instanceId = instanceId,
					rawOutcome = rawOutcome,
					outcome = outcomeId,
					protection = protectionId,
					protectionConsumed = consumed,
					previousLevel = car.UpgradeLevel,
					upgradeLevel = nil,
					removed = true,
					car = nil,
					power = nil,
					charged = false,
				}
			end

			local nextLevel, levelReason = UpgradeConfig.nextLevel(car.UpgradeLevel, outcomeId)
			if nextLevel == nil then
				return fail(requestId, levelReason or CarUpgradeService.Reason.UpdateFailed, {
					instanceId = instanceId,
					previousLevel = car.UpgradeLevel,
					rawOutcome = rawOutcome,
					outcome = outcomeId,
				})
			end

			-- 目前沒有重生系統，性能先用這台車取得時的重生階級。
			local power, powerReason = CarConfig.calculatePower(nextLevel, model.Quality, car.AcquiredRebirth)
			if power == nil then
				return fail(requestId, powerReason or CarUpgradeService.Reason.UpdateFailed, {
					instanceId = instanceId,
					previousLevel = car.UpgradeLevel,
					rawOutcome = rawOutcome,
					outcome = outcomeId,
				})
			end

			local stored = car
			if nextLevel ~= car.UpgradeLevel then
				local updated, updateReason = inventory:SetUpgradeLevel(playerKey, instanceId, nextLevel)
				if updated == nil then
					return fail(requestId, CarUpgradeService.Reason.UpdateFailed, {
						detail = updateReason,
						instanceId = instanceId,
						previousLevel = car.UpgradeLevel,
						rawOutcome = rawOutcome,
						outcome = outcomeId,
					})
				end
				stored = updated
			end

			return {
				ok = true,
				requestId = requestId,
				instanceId = instanceId,
				rawOutcome = rawOutcome,
				outcome = outcomeId,
				protection = protectionId,
				protectionConsumed = consumed,
				previousLevel = car.UpgradeLevel,
				upgradeLevel = stored.UpgradeLevel,
				removed = false,
				car = stored,
				power = power,
				charged = false,
			}
		end)

		pending[key] = nil
		carLocks[instanceId] = nil

		if not completed then
			outcome = fail(requestId, CarUpgradeService.Reason.InternalError, {
				detail = tostring(outcome),
				instanceId = instanceId,
			})
		end

		cached[key] = outcome
		return copyResult(outcome)
	end

	return service
end

return CarUpgradeService
