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

local remotes = ReplicatedStorage:WaitForChild("CarForgeTaxRemotes", 30)
local actionRemote = remotes:WaitForChild("Action")
local finishedEvent = remotes:WaitForChild("RaceFinished")

local REASONS = {
	RateLimited = "操作太頻繁，請稍後再試。",
	InsufficientGold = "測試金幣不足。",
	UnknownCar = "這台車不存在，或不屬於你。",
	UnknownModel = "車款資料不存在。",
	NoSelectedCar = "請先選擇一台競速車輛。",
	RaceInProgress = "已經有一場競速在進行。",
	MaxUpgradeLevel = "已經是 +10，不能再強化。",
	InvalidToken = "請求識別碼無效。",
	UnknownAction = "這個操作不能使用。",
	NoUnlockedModel = "這個品質目前沒有可取得的車。",
	InvalidPlayer = "玩家資料尚未建立。",
	InternalError = "伺服器處理失敗。",
	BossDisabled = "機械暴君目前未開放。",
	CarRacing = "這台車正在參賽，不能強化或報廢。",
}

local busy = false

local function reasonText(result): string
	if type(result) ~= "table" then
		return "伺服器沒有回應。"
	end
	if result.reason ~= nil and REASONS[result.reason] ~= nil then
		return REASONS[result.reason]
	end
	if result.reason ~= nil then
		return "操作沒有成功（" .. tostring(result.reason) .. "）。"
	end
	return "操作沒有成功。"
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

local function pull()
	if busy then
		return
	end
	busy = true
	local result = call("Pull")
	busy = false
	refresh()
	if result.ok ~= true then
		ui.toast(reasonText(result))
		return
	end
	local replay = if result.replayed == true then "（同一請求，沒有再扣款）" else ""
	ui.toast(string.format(
		"抽到 %s　%s　花費 %s 測試金幣%s",
		tostring(result.qualityName),
		tostring(result.displayName),
		tostring(result.price),
		replay
	))
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
		refresh()
		busy = false
		if ui ~= nil then
			ui.setUpgradePending(false)
		end
		if result.outcome ~= nil then
			ui.flash(result.outcome)
		end
		if result.ok ~= true then
			ui.toast(reasonText(result))
			return
		end
		if result.removed == true then
			ui.toast("報廢：這台車已從車庫移除。")
			return
		end
		ui.toast(string.format(
			"%s：+%s → +%s，性能 %s。沒有扣金幣。",
			tostring(result.outcomeName or result.outcome),
			tostring(result.previousLevel),
			tostring(result.upgradeLevel),
			tostring(result.power)
		))
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
		ui.toast("自動競速已在進行，沒有另開一場。")
	else
		ui.toast("自動競速開始。每場由伺服器結算，關閉面板也不會停止。")
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
		ui.toast("目前沒有進行中的自動競速。")
	else
		ui.toast("已立即停止。這一場不發獎，已完成的獎勵會保留。")
	end
end

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
	onUpgrade = upgrade,
	onAutoStart = function(instanceId)
		startAuto(instanceId)
	end,
	onAutoStop = function()
		stopAuto()
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
				if station == "GachaMachine" then
					ui.open("gacha")
				elseif station == "UpgradeBench" then
					ui.open("upgrade")
				elseif station == "RaceKiosk" then
					ui.open("race")
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
	playground:WaitForChild("GaragePad1", 30)
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
			"第 %d 場完成，測試金幣 +%s。下一場已開始。",
			payload.autoCompleted or 0,
			tostring(payload.reward or 0)
		))
	elseif payload.auto == true then
		ui.toast(string.format(
			"自動競速已停止。本場測試金幣 +%s，累積 %s。",
			tostring(payload.reward or 0),
			tostring(payload.autoEarned or 0)
		))
	elseif payload.mode == "boss" then
		local verdict = if payload.won == true then "勝利" else "落敗"
		ui.toast(string.format(
			"機械暴君%s。伺服器時間 %.2f 秒，基準 %.0f 秒，測試金幣 +%s。",
			verdict,
			payload.duration or 0,
			payload.bossTarget or 35,
			tostring(payload.reward or 0)
		))
	else
		ui.toast(string.format(
			"競速完成。伺服器時間 %.2f 秒，測試金幣 +%s。",
			payload.duration or 0,
			tostring(payload.reward or 0)
		))
	end
end)
