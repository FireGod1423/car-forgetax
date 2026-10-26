-- 伺服器記憶體錢包，只供這一版測試抽車。
-- 伺服器關閉後餘額會消失。50,000 金幣只有測試程式呼叫 GrantTestGold 才會發，不是正式經濟。
local function importCarConfig()
	if game ~= nil then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild("CarConfig"))
	end
	return require("../shared/CarConfig")
end

local CarConfig = importCarConfig()

local GoldWallet = {}

GoldWallet.Reason = table.freeze({
	InvalidPlayer = "InvalidPlayer",
	InvalidAmount = "InvalidAmount",
	InvalidRequest = "InvalidRequest",
	InsufficientGold = "InsufficientGold",
	DuplicateDebit = "DuplicateDebit",
	TestGoldAlreadyGranted = "TestGoldAlreadyGranted",
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

function GoldWallet.new()
	-- 餘額放在閉包裡，外部拿不到這張表。
	local balances = {}
	local receipts = {}
	local testGranted = {}
	local wallet = {}

	function wallet:GetBalance(playerKey)
		if not isPlayerKey(playerKey) then
			return nil, GoldWallet.Reason.InvalidPlayer
		end
		return balances[playerKey] or 0, nil
	end

	-- requestId 相同時拒絕第二次扣款，避免重複請求再扣一次。
	function wallet:TryDebit(playerKey, amount, requestId)
		if not isPlayerKey(playerKey) then
			return false, GoldWallet.Reason.InvalidPlayer
		end
		if type(requestId) ~= "string" or requestId == "" then
			return false, GoldWallet.Reason.InvalidRequest
		end
		if not isInteger(amount) or amount <= 0 then
			return false, GoldWallet.Reason.InvalidAmount
		end
		if receipts[requestId] ~= nil then
			return false, GoldWallet.Reason.DuplicateDebit
		end

		local balance = balances[playerKey] or 0
		if balance < amount then
			return false, GoldWallet.Reason.InsufficientGold
		end

		balances[playerKey] = balance - amount
		receipts[requestId] = amount
		return true, nil
	end

	-- 伺服器退款或測試加值用。客戶端沒有這條路徑。
	function wallet:Credit(playerKey, amount)
		if not isPlayerKey(playerKey) then
			return false, GoldWallet.Reason.InvalidPlayer
		end
		if not isInteger(amount) or amount <= 0 then
			return false, GoldWallet.Reason.InvalidAmount
		end

		balances[playerKey] = (balances[playerKey] or 0) + amount
		return true, nil
	end

	-- 每位玩家只發一次測試金幣，避免測試流程反覆灌錢。
	function wallet:GrantTestGold(playerKey)
		if not isPlayerKey(playerKey) then
			return false, GoldWallet.Reason.InvalidPlayer
		end
		if testGranted[playerKey] then
			return false, GoldWallet.Reason.TestGoldAlreadyGranted
		end

		local amount = CarConfig.TestStartingGold
		if not isInteger(amount) or amount <= 0 then
			return false, GoldWallet.Reason.InvalidAmount
		end

		testGranted[playerKey] = true
		balances[playerKey] = (balances[playerKey] or 0) + amount
		return true, nil
	end

	return wallet
end

return GoldWallet
