-- 客戶端只送請求與顯示結果。品質、等級、完賽時間和獎金都由伺服器決定。
-- 競速不改玩家鏡頭、不鎖 CameraSubject，也不移動角色。
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local CarVisualFactory = require(sharedFolder:WaitForChild("CarVisualFactory"))
local GarageUI = require(script.Parent:WaitForChild("GarageUI"))
local SpectatorCamera = require(script.Parent:WaitForChild("SpectatorCamera"))
local WorkbenchView = require(script.Parent:WaitForChild("WorkbenchView"))

local remotes = ReplicatedStorage:WaitForChild("CarForgeTaxRemotes", 30)
local actionRemote = remotes:WaitForChild("Action")
local finishedEvent = remotes:WaitForChild("RaceFinished")

local REASONS = {
	RateLimited = "Too many actions. Try again in a moment.",
	InsufficientGold = "Not enough test gold.",
	UnknownCar = "That car does not exist, or it is not yours.",
	UnknownModel = "That car model does not exist.",
	NoSelectedCar = "Pick a race car first.",
	RaceInProgress = "A race is already in progress.",
	MaxUpgradeLevel = "Already +10. It cannot be upgraded again.",
	MaxRank = "Already T10.",
	InvalidToken = "The request id is invalid.",
	UnknownAction = "That action cannot be used.",
	NoUnlockedModel = "No car of this quality is available yet.",
	InvalidPlayer = "Player data is not ready.",
	InternalError = "The server failed to handle that.",
	BossDisabled = "The Machine Tyrant is not open.",
	NeedsConfirm = "Selling Legendaries automatically needs one more confirmation.",
	CarRacing = "This car is racing. It cannot be upgraded or scrapped.",
	RankLocked = "Upgrades unlock at T1 Street Racer.",
}

local busy = false

local function reasonText(result): string
	if type(result) ~= "table" then
		return "The server did not respond."
	end
	if result.reason ~= nil and REASONS[result.reason] ~= nil then
		return REASONS[result.reason]
	end
	if result.reason ~= nil then
		return "That did not work (" .. tostring(result.reason) .. ")."
	end
	return "That did not work."
end

local function token(): string
	return HttpService:GenerateGUID(false)
end

local function call(action: string, fields)
	fields = fields or {}
	fields.action = action
	-- 傳輸失敗時用同一個識別碼重送。伺服器只會接受第一次，避免補送又扣一次錢。
	if action ~= "GetState" and type(fields.attemptToken) ~= "string" then
		fields.attemptToken = token()
	end
	local result = nil
	for _ = 1, 3 do
		local ok, value = pcall(function()
			return actionRemote:InvokeServer(fields)
		end)
		if ok and type(value) == "table" then
			result = value
			break
		end
	end
	if result == nil then
		return {
			ok = false,
			reason = "InternalError",
		}
	end
	return result
end

local ui

local function refreshGarageModels(state)
	local playground = workspace:FindFirstChild("CarForgeTaxPlayground")
	if playground == nil or type(state) ~= "table" or type(state.cars) ~= "table" then
		return
	end
	local folder = playground:FindFirstChild("LocalGaragePreview")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "LocalGaragePreview"
		folder.Parent = playground
	end
	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
	end
	local pads = {}
	for _, descendant in ipairs(playground:GetDescendants()) do
		if descendant:GetAttribute("GarageSlot") ~= nil then
			table.insert(pads, descendant)
		end
	end
	table.sort(pads, function(left, right)
		return (left:GetAttribute("GarageSlot") or 0) < (right:GetAttribute("GarageSlot") or 0)
	end)
	for index, car in ipairs(state.cars) do
		local pad = pads[index]
		if pad == nil then
			break
		end
		local model = CarVisualFactory.build({
			modelId = car.modelId,
			qualityId = car.qualityId,
			upgradeLevel = car.upgradeLevel,
			displayName = car.displayName,
		})
		model.Name = "OwnedPreview"
		model:SetAttribute("DisplayOnly", true)
		model.Parent = folder
		model:PivotTo(pad.CFrame * CFrame.new(0, 1.2, 0))
		if car.instanceId == state.selectedInstanceId then
			local selection = Instance.new("SelectionBox")
			selection.LineThickness = 0.04
			selection.Color3 = Color3.fromRGB(255, 186, 48)
			selection.Adornee = model
			selection.Parent = model
		end
	end
end

local function refresh()
	local state = call("GetState")
	if state.ok ~= true then
		ui.toast(reasonText(state))
		return nil
	end
	ui.setState(state)
	refreshGarageModels(state)
	return state
end

local openStation = "R0Dealer"

local function pull()
	if busy or ui.isBusy() then
		return
	end
	busy = true
	ui.lockPull(true)
	ui.beginPullCooldown()
	local result = call("Pull", {
		stationId = openStation,
	})
	if result.reason ~= "RateLimited" then
		ui.beginPullCooldown()
	end
	refresh()
	busy = false
	if result.ok ~= true then
		ui.lockPull(false)
		ui.toast(reasonText(result))
		return
	end
	ui.playPull(result, function()
		if result.sold == true then
			ui.toast(string.format("Sold automatically for %s gold", tostring(result.sellPrice)))
			return
		end
		local replay = if result.replayed == true then " (same request, not charged again)" else ""
		ui.toast(string.format(
			"Pulled %s  %s  Spent %s test gold%s",
			tostring(result.qualityName),
			tostring(result.displayName),
			tostring(result.price),
			replay
		))
	end)
end

local function findBench(): Model?
	local playground = workspace:FindFirstChild("CarForgeTaxPlayground")
	if playground == nil then
		return nil
	end
	local key = tostring(player.UserId)
	for _, child in ipairs(playground:GetChildren()) do
		if child.Name == "PrivateGarage" and tostring(child:GetAttribute("OwnerKey")) == key then
			local bench = child:FindFirstChild("UpgradeBench")
			if bench ~= nil and bench:IsA("Model") then
				return bench
			end
		end
	end
	return nil
end

	local function upgrade(instanceId)
		if busy then
			return
		end
		if type(instanceId) ~= "string" or instanceId == "" then
			return
		end
		busy = true
		if ui ~= nil then
			ui.setUpgradePending(true)
		end
		local result = call("Upgrade", {
			instanceId = instanceId,
		})
		if ui ~= nil and result.ok == true and result.outcome ~= nil then
			ui.playUpgrade(result)
		end
		refresh()
		busy = false
		if ui ~= nil then
			ui.setUpgradePending(false)
		end
		if result.ok ~= true then
			ui.toast(reasonText(result))
		end
	end

local function startAuto(instanceId)
	if busy then
		return
	end
	busy = true
	local result = call("StartAutoRace", {
		instanceId = instanceId,
	})
	busy = false
	refresh()
	if result.ok ~= true then
		ui.toast(reasonText(result))
		ui.open("race")
		return
	end
	if result.replayed == true then
		ui.toast("Auto race is already running. No second one was started.")
	else
		ui.toast("Auto race started. The server settles each round. Closing the panel does not stop it.")
	end
end

local function stopAuto()
	if busy then
		return
	end
	busy = true
	local result = call("StopAutoRace")
	busy = false
	refresh()
	if result.ok ~= true then
		ui.toast(reasonText(result))
		return
	end
	if result.replayed == true then
		ui.toast("No auto race is running.")
	else
		ui.toast("Stopped. This round pays nothing. Finished rewards stay.")
	end
end

SpectatorCamera.mount(player, playerGui)
local workbench = WorkbenchView.mount(player, function()
	if ui ~= nil then
		ui.close()
	end
end)
ui = GarageUI.mount(playerGui, {
	onRefresh = refresh,
	onSelect = function(instanceId)
		local result = call("SelectCar", {
			instanceId = instanceId,
		})
		if result.ok ~= true then
			ui.toast(reasonText(result))
			return
		end
		ui.setState(result)
		refreshGarageModels(result)
	end,
	onPull = pull,
	onAutoSell = function(qualities, confirmLegendary)
		local result = call("SetAutoSell", {
			qualities = qualities,
			confirmLegendary = confirmLegendary == true,
			stationId = openStation,
		})
		refresh()
		if result.ok ~= true then
			ui.toast(reasonText(result))
		end
	end,
	onUpgrade = upgrade,
	onEnterBench = function()
		local ok, entered = pcall(function()
			return workbench.enter(findBench())
		end)
		if ok ~= true or entered ~= true then
			ui.toast("The workbench is not ready.")
		end
	end,
	onLeaveBench = function()
		workbench.leave()
	end,
	onPreviewCar = function(car)
		workbench.showCar(car)
	end,
	onUpgradeStrike = function(outcomeId, onImpact)
		return workbench.play(outcomeId, onImpact)
	end,
	onAutoStart = function(instanceId)
		startAuto(instanceId)
	end,
	onAutoStop = function()
		stopAuto()
	end,
	onTestPlace = function(instanceId)
		local picked = call("SelectCar", {
			instanceId = instanceId,
		})
		if picked.ok ~= true then
			ui.toast(reasonText(picked))
			return
		end
		ui.setState(picked)
		local result = call("TestLap")
		refresh()
		if result.ok ~= true then
			ui.toast(reasonText(result))
			return
		end
		ui.close()
	end,
	onRankUp = function()
		local result = call("RankUp")
		refresh()
		if result.ok ~= true then
			ui.toast(reasonText(result))
			return
		end
		local label = if type(result.rankLabel) == "string" then result.rankLabel else "Rank up"
		ui.toast(label)
	end,
})

local function bindPrompts(playground: Instance)
	for _, descendant in ipairs(playground:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and descendant:GetAttribute("Bound") ~= true then
			descendant:SetAttribute("Bound", true)
			descendant.Triggered:Connect(function(who)
				if who ~= player then
					return
				end
				local station = descendant.Parent and descendant.Parent:GetAttribute("Station")
				if station == "R0Dealer" then
					openStation = "R0Dealer"
					if ui.isDealerIntroOpen() then
						return
					end
					local state = call("GetState", {
						stationId = "R0Dealer",
					})
					if state.dealerIntroSeen == true then
						ui.open("gacha")
					else
						ui.showDealerIntro(function()
							call("CompleteDealerIntro")
							ui.open("gacha")
						end)
					end
				elseif station == "UpgradeBench" then
					local state = call("GetState")
					if type(state) ~= "table" or type(state.rebirthLevel) ~= "number" or state.rebirthLevel < 1 then
						ui.toast("Upgrades unlock at T1 Street Racer.")
						return
					end
					if state.ok == true then
						ui.setState(state)
					end
					ui.open("upgrade")
				elseif station == "CarFusion" then
					local state = call("GetState")
					if type(state) ~= "table" or type(state.rebirthLevel) ~= "number" or state.rebirthLevel < 3 then
						ui.toast("Car Fusion unlocks at T3 Pro Racer.")
						return
					end
					ui.open("fusion")
				elseif station == "RaceKiosk" then
					ui.open("race")
				elseif station == "TestLap" then
					local state = call("GetState")
					if state.ok == true then
						ui.setState(state)
					end
					ui.open("test")
				end
			end)
		end
	end
end

local function attachPlayground(playground: Instance)
	if playground:GetAttribute("ClientBound") == true then
		return
	end
	playground:SetAttribute("ClientBound", true)
	playground:WaitForChild("PrivateGarage", 30)
	if playground.Parent == nil then
		return
	end
	bindPrompts(playground)
	playground.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			bindPrompts(playground)
		end
	end)
	refresh()
end

local existingPlayground = workspace:FindFirstChild("CarForgeTaxPlayground")
if existingPlayground ~= nil then
	task.spawn(attachPlayground, existingPlayground)
end
workspace.ChildAdded:Connect(function(child)
	if child.Name == "CarForgeTaxPlayground" then
		task.spawn(attachPlayground, child)
	end
end)

finishedEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	refresh()
	if payload.autoContinue == true then
		ui.toast(string.format(
			"Round %d finished. Test gold +%s. The next round has started.",
			payload.autoCompleted or 0,
			tostring(payload.reward or 0)
		))
	elseif payload.auto == true then
		ui.toast(string.format(
			"Auto race stopped. This round +%s test gold, %s earned in total.",
			tostring(payload.reward or 0),
			tostring(payload.autoEarned or 0)
		))
	elseif payload.mode == "boss" then
		local verdict = if payload.won == true then "win" else "loss"
		ui.toast(string.format(
			"Machine Tyrant %s. Server time %.2f s, target %.0f s, test gold +%s.",
			verdict,
			payload.duration or 0,
			payload.bossTarget or 35,
			tostring(payload.reward or 0)
		))
	else
		ui.toast(string.format(
			"Race finished. Server time %.2f s, test gold +%s.",
			payload.duration or 0,
			tostring(payload.reward or 0)
		))
	end
end)
