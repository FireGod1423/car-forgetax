-- 伺服器抽車。品質機率來自 CarConfig；金幣與發車都在伺服器完成。
local function importShared(moduleName: string)
	if game ~= nil then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild(moduleName))
	end
	return require("../shared/" .. moduleName)
end

local CarConfig = importShared("CarConfig")
local CarCatalog = importShared("CarCatalog")
local PoolConfig = importShared("PoolConfig")
local RandomSource = importShared("RandomSource")

local CarGachaService = {}

CarGachaService.Reason = table.freeze({
	InsufficientGold = "InsufficientGold",
	NoUnlockedModel = "NoUnlockedModel",
	InvalidRequest = "InvalidRequest",
	InvalidRebirth = "InvalidRebirth",
	InvalidPlayer = "InvalidPlayer",
	InvalidPrice = "InvalidPrice",
	InvalidPool = "InvalidPool",
	PoolLocked = "PoolLocked",
	RequestInProgress = "RequestInProgress",
	GrantFailed = "GrantFailed",
	InternalError = "InternalError",
})

local function isInteger(value: any): boolean
	return type(value) == "number" and value == value and value % 1 == 0
end

local function isPlayerKey(playerKey: any): boolean
	if type(playerKey) == "string" then
		return playerKey ~= ""
	end
	if type(playerKey) == "number" then
		return isInteger(playerKey) and playerKey > 0
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

function CarGachaService.new(options)
	if type(options) ~= "table" or options.inventory == nil or options.wallet == nil then
		error("CarGachaService 需要 inventory 與 wallet")
	end

	local config = options.config or CarConfig
	local catalog = options.catalog or CarCatalog
	local inventory = options.inventory
	local wallet = options.wallet
	local rng = options.rng or RandomSource.new()
	local cached = {}
	local pending = {}
	local service = {}

	local function cacheKey(playerKey, requestId: string): string
		return tostring(playerKey) .. "\0" .. requestId
	end

	function service:Pull(playerKey, rebirthLevel, requestId, poolId)
		if not isPlayerKey(playerKey) then
			return {
				ok = false,
				reason = CarGachaService.Reason.InvalidPlayer,
				requestId = requestId,
				charged = false,
			}
		end
		if type(requestId) ~= "string" or requestId == "" then
			return {
				ok = false,
				reason = CarGachaService.Reason.InvalidRequest,
				requestId = requestId,
				charged = false,
			}
		end
		-- 重生階級必須由伺服器傳入，不能信任客戶端自己報。
		if not isInteger(rebirthLevel) or rebirthLevel < 0 then
			return {
				ok = false,
				reason = CarGachaService.Reason.InvalidRebirth,
				requestId = requestId,
				charged = false,
			}
		end

		local resolvedPool = if type(poolId) == "string" and poolId ~= "" then poolId else "T0"
		if PoolConfig.get(resolvedPool) == nil then
			return {
				ok = false,
				reason = CarGachaService.Reason.InvalidPool,
				requestId = requestId,
				charged = false,
			}
		end

		local key = cacheKey(playerKey, requestId)
		local previous = cached[key]
		if previous ~= nil then
			local replay = copyResult(previous)
			replay.replayed = true
			return replay
		end
		if pending[key] == true then
			return {
				ok = false,
				reason = CarGachaService.Reason.RequestInProgress,
				requestId = requestId,
				charged = false,
			}
		end

		pending[key] = true
		local debited = false
		local price = PoolConfig.price(resolvedPool)

		local function refund()
			if debited then
				wallet:Credit(playerKey, price)
				debited = false
			end
		end

		local completed, outcome = pcall(function()
			if not isInteger(price) or price <= 0 then
				return {
					ok = false,
					reason = CarGachaService.Reason.InvalidPrice,
					requestId = requestId,
					price = price,
					balance = wallet:GetBalance(playerKey),
					charged = false,
				}
			end

			local balance = wallet:GetBalance(playerKey)
			if balance < price then
				return {
					ok = false,
					reason = CarGachaService.Reason.InsufficientGold,
					requestId = requestId,
					price = price,
					balance = balance,
					charged = false,
				}
			end

			if not PoolConfig.unlocked(resolvedPool, rebirthLevel) then
				return {
					ok = false,
					reason = CarGachaService.Reason.PoolLocked,
					requestId = requestId,
					poolId = resolvedPool,
					price = price,
					balance = wallet:GetBalance(playerKey),
					charged = false,
				}
			end

			-- 先定品質。這個品質沒有可發的車時，不改抽其他品質，也不扣錢。
			local qualityId, rollReason = PoolConfig.roll(resolvedPool, rng)
			if qualityId == nil then
				error(rollReason or "RollFailed")
			end

			local eligible = catalog.getEligible(qualityId, rebirthLevel)
			if #eligible == 0 then
				return {
					ok = false,
					reason = CarGachaService.Reason.NoUnlockedModel,
					requestId = requestId,
					quality = qualityId,
					price = price,
					balance = wallet:GetBalance(playerKey),
					charged = false,
				}
			end

			local model = eligible[rng:NextInteger(1, #eligible)]
			local debitOk, debitReason = wallet:TryDebit(playerKey, price, key)
			if not debitOk then
				local reason = if debitReason == "InsufficientGold"
					then CarGachaService.Reason.InsufficientGold
					else CarGachaService.Reason.GrantFailed
				return {
					ok = false,
					reason = reason,
					detail = debitReason,
					requestId = requestId,
					quality = qualityId,
					price = price,
					balance = wallet:GetBalance(playerKey),
					charged = false,
				}
			end

			debited = true
			local car, createReason = inventory:CreateCar(playerKey, model.ModelId, rebirthLevel)
			if car == nil then
				refund()
				return {
					ok = false,
					reason = CarGachaService.Reason.GrantFailed,
					detail = createReason,
					requestId = requestId,
					quality = qualityId,
					modelId = model.ModelId,
					price = price,
					balance = wallet:GetBalance(playerKey),
					charged = false,
				}
			end

			-- 發車成功後這筆錢要留下，不能被外層的錯誤處理退回。
			debited = false
			return {
				ok = true,
				requestId = requestId,
				quality = qualityId,
				modelId = model.ModelId,
				car = car,
				price = price,
				balance = wallet:GetBalance(playerKey),
				charged = true,
			}
		end)

		pending[key] = nil
		if not completed then
			refund()
			outcome = {
				ok = false,
				reason = CarGachaService.Reason.InternalError,
				detail = tostring(outcome),
				requestId = requestId,
				price = price,
				balance = wallet:GetBalance(playerKey),
				charged = false,
			}
		end

		-- 同一個請求只保留第一次結果，重送不會再扣款或再發一台車。
		cached[key] = outcome
		return copyResult(outcome)
	end

	return service
end

return CarGachaService
