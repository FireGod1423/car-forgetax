-- 車庫、抽車與強化介面。顯示的數字來自伺服器狀態與 UpgradeConfig，客戶端不改車庫。
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local UpgradeConfig = require(sharedFolder:WaitForChild("UpgradeConfig"))
local CarConfig = require(sharedFolder:WaitForChild("CarConfig"))
local CarVisualFactory = require(sharedFolder:WaitForChild("CarVisualFactory"))

local GarageUI = {}

local FLASH = {
	Success = Color3.fromRGB(72, 220, 120),
	GreatSuccess = Color3.fromRGB(255, 214, 70),
	Keep = Color3.fromRGB(168, 172, 178),
	Damage = Color3.fromRGB(255, 150, 48),
	Destroy = Color3.fromRGB(255, 72, 64),
}

local function corner(parent: Instance, radius: number)
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, radius)
	uiCorner.Parent = parent
end

local function button(parent: Instance, text: string, color: Color3)
	local item = Instance.new("TextButton")
	item.Size = UDim2.new(0.48, 0, 0, 36)
	item.BackgroundColor3 = color
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.Text = text
	item.TextColor3 = Color3.fromRGB(24, 26, 32)
	item.TextSize = 16
	item.AutoButtonColor = true
	item.Parent = parent
	corner(item, 8)
	return item
end

local function oddsText(upgradeLevel: number): string
	if upgradeLevel >= CarConfig.MaxUpgradeLevel then
		return "已達 +10，不能再強化。"
	end
	local weights, reason = UpgradeConfig.getWeights(upgradeLevel)
	local total = UpgradeConfig.sumWeights(upgradeLevel)
	if weights == nil or total == nil or total <= 0 then
		return "無法讀取機率：" .. tostring(reason)
	end
	local lines = {}
	for _, outcome in ipairs(UpgradeConfig.getOutcomes()) do
		local weight = weights[outcome.Id] or 0
		local percent = weight / total * 100
		table.insert(lines, string.format("%s %.0f%%", outcome.DisplayName, percent))
	end
	return table.concat(lines, "   ")
end

function GarageUI.mount(playerGui: PlayerGui, handlers)
	local state = nil
	local page = "garage"
	local selectedId = nil
	local previewModel = nil
	local spin = 0

	local gui = Instance.new("ScreenGui")
	gui.Name = "CarForgeTaxGarage"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.Parent = playerGui

	local hud = Instance.new("TextLabel")
	hud.Name = "Hud"
	hud.AnchorPoint = Vector2.new(0.5, 0)
	hud.Position = UDim2.new(0.5, 0, 0, 10)
	hud.Size = UDim2.new(0.92, 0, 0, 36)
	hud.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
	hud.BackgroundTransparency = 0.15
	hud.BorderSizePixel = 0
	hud.Font = Enum.Font.GothamMedium
	hud.TextSize = 16
	hud.TextColor3 = Color3.new(1, 1, 1)
	hud.Text = "讀取車庫中…"
	hud.Parent = gui
	corner(hud, 8)

	local openButton = button(gui, "車庫", Color3.fromRGB(255, 148, 48))
	openButton.AnchorPoint = Vector2.new(1, 0)
	openButton.Position = UDim2.new(0.96, 0, 0, 52)
	openButton.Size = UDim2.fromOffset(88, 34)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.54)
	panel.Size = UDim2.fromScale(0.9, 0.78)
	panel.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
	panel.BackgroundTransparency = 0.04
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 12)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.03, 0.02)
	title.Size = UDim2.fromScale(0.7, 0.08)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "車庫"
	title.Parent = panel

	local closeButton = button(panel, "關閉", Color3.fromRGB(210, 214, 220))
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(0.97, 0, 0.025, 0)
	closeButton.Size = UDim2.fromOffset(72, 32)

	local list = Instance.new("ScrollingFrame")
	list.Name = "CarList"
	list.BackgroundColor3 = Color3.fromRGB(28, 34, 46)
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	corner(list, 8)
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = list
	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 6)
	listPadding.PaddingLeft = UDim.new(0, 6)
	listPadding.PaddingRight = UDim.new(0, 6)
	listPadding.Parent = list

	local preview = Instance.new("ViewportFrame")
	preview.Name = "Preview"
	preview.BackgroundColor3 = Color3.fromRGB(232, 240, 246)
	preview.BorderSizePixel = 0
	preview.Ambient = Color3.fromRGB(190, 190, 190)
	preview.LightColor = Color3.new(1, 1, 1)
	preview.LightDirection = Vector3.new(-1, -1, -0.4)
	preview.Parent = panel
	corner(preview, 8)
	local world = Instance.new("WorldModel")
	world.Parent = preview
	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.7, -7.2), Vector3.new(0, 0.45, 0))
	preview.CurrentCamera = camera

	local detail = Instance.new("TextLabel")
	detail.BackgroundTransparency = 1
	detail.Font = Enum.Font.GothamMedium
	detail.TextSize = 16
	detail.TextWrapped = true
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextYAlignment = Enum.TextYAlignment.Top
	detail.TextColor3 = Color3.fromRGB(232, 236, 242)
	detail.Text = ""
	detail.Parent = panel

	local actions = Instance.new("Frame")
	actions.BackgroundTransparency = 1
	actions.Parent = panel
	local actionLayout = Instance.new("UIListLayout")
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	actionLayout.Padding = UDim.new(0, 8)
	actionLayout.Wraps = true
	actionLayout.Parent = actions

	local pullButton = button(actions, "抽車", Color3.fromRGB(255, 148, 48))
	local upgradeButton = button(actions, "強化", Color3.fromRGB(255, 214, 70))
	local raceButton = button(actions, "開始競速", Color3.fromRGB(96, 220, 150))
	local bossButton = button(actions, "挑戰機械暴君", Color3.fromRGB(186, 198, 214))

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 6
	flash.Parent = gui

	local toast = Instance.new("TextLabel")
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 1, -16)
	toast.Size = UDim2.new(0.8, 0, 0, 64)
	toast.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
	toast.BackgroundTransparency = 0.1
	toast.BorderSizePixel = 0
	toast.Font = Enum.Font.GothamMedium
	toast.TextSize = 16
	toast.TextWrapped = true
	toast.TextColor3 = Color3.new(1, 1, 1)
	toast.Visible = false
	toast.ZIndex = 7
	toast.Parent = gui
	corner(toast, 8)

	local banner = Instance.new("TextLabel")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 96)
	banner.Size = UDim2.new(0.7, 0, 0, 32)
	banner.BackgroundTransparency = 0.2
	banner.BackgroundColor3 = Color3.fromRGB(255, 122, 28)
	banner.Font = Enum.Font.GothamBold
	banner.TextSize = 16
	banner.TextColor3 = Color3.fromRGB(24, 26, 32)
	banner.Visible = false
	banner.ZIndex = 5
	banner.Parent = gui
	corner(banner, 8)

	local function selectedCar()
		if state == nil or type(state.cars) ~= "table" then
			return nil
		end
		for _, car in ipairs(state.cars) do
			if car.instanceId == selectedId then
				return car
			end
		end
		return nil
	end

	local function showPreview(car)
		previewModel = nil
		for _, child in ipairs(world:GetChildren()) do
			child:Destroy()
		end
		if car == nil then
			return
		end
		previewModel = CarVisualFactory.build({
			modelId = car.modelId,
			qualityId = car.qualityId,
			upgradeLevel = car.upgradeLevel,
			displayName = car.displayName,
		})
		previewModel.Parent = world
	end

	local function applyLayout()
		local width = 1000
		local currentCamera = workspace.CurrentCamera
		if currentCamera ~= nil then
			width = currentCamera.ViewportSize.X
		end
		local compact = width < 760
		if compact then
			list.Position = UDim2.fromScale(0.04, 0.12)
			list.Size = UDim2.fromScale(0.92, 0.28)
			preview.Position = UDim2.fromScale(0.04, 0.42)
			preview.Size = UDim2.fromScale(0.92, 0.24)
			detail.Position = UDim2.fromScale(0.04, 0.67)
			detail.Size = UDim2.fromScale(0.92, 0.14)
			actions.Position = UDim2.fromScale(0.04, 0.82)
			actions.Size = UDim2.fromScale(0.92, 0.16)
		else
			list.Position = UDim2.fromScale(0.03, 0.12)
			list.Size = UDim2.fromScale(0.36, 0.84)
			preview.Position = UDim2.fromScale(0.42, 0.12)
			preview.Size = UDim2.fromScale(0.55, 0.42)
			detail.Position = UDim2.fromScale(0.42, 0.56)
			detail.Size = UDim2.fromScale(0.55, 0.2)
			actions.Position = UDim2.fromScale(0.42, 0.78)
			actions.Size = UDim2.fromScale(0.55, 0.18)
		end
	end

	local function render()
		local balance = if state ~= nil then state.balance else "—"
		local notice = if state ~= nil and state.memoryNotice ~= nil then state.memoryNotice else "關服後資料會消失"
		hud.Text = string.format("測試金幣 %s    %s", tostring(balance), notice)
		local car = selectedCar()
		if page == "gacha" then
			title.Text = "抽車機"
			detail.Text = string.format(
				"單抽 %d 測試金幣。品質、車款與重生階級都由伺服器決定。\n抽到的車會進入伺服器車庫。",
				CarConfig.SinglePullPrice
			)
		elseif page == "upgrade" then
			title.Text = "強化工作台"
			if car == nil then
				detail.Text = "請先在車庫選擇一台屬於你的車。強化不扣金幣。"
			else
				detail.Text = string.format(
					"%s　%s　+%d　性能 %s\n%s\n結果只顯示伺服器實際抽到的那一個。",
					car.displayName,
					car.qualityName,
					car.upgradeLevel,
					tostring(car.power),
					oddsText(car.upgradeLevel)
				)
			end
		elseif page == "boss" then
			title.Text = "機械暴君"
			detail.Text = "基準完成時間 35 秒。賽道中段速度降低 20%，持續 3 秒。時間與勝負由伺服器計算，勝利才發測試金幣。"
		else
			title.Text = "車庫"
			if car == nil then
				detail.Text = "還沒有車輛。到抽車機花費測試金幣取得第一台車。"
			else
				detail.Text = string.format(
					"%s\n%s　%s　強化 +%d　性能 %s\n這台車會用來競速。視覺模型不是車庫資料。",
					car.displayName,
					car.qualityName,
					car.colorName,
					car.upgradeLevel,
					tostring(car.power)
				)
			end
		end

		for _, child in ipairs(list:GetChildren()) do
			if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end
		local cars = if state ~= nil and type(state.cars) == "table" then state.cars else {}
		if #cars == 0 then
			local empty = Instance.new("TextLabel")
			empty.BackgroundTransparency = 1
			empty.Size = UDim2.new(1, -12, 0, 40)
			empty.Font = Enum.Font.Gotham
			empty.TextSize = 16
			empty.TextXAlignment = Enum.TextXAlignment.Left
			empty.TextColor3 = Color3.fromRGB(210, 214, 220)
			empty.Text = "車庫是空的"
			empty.Parent = list
		end
		for _, entry in ipairs(cars) do
			local row = Instance.new("TextButton")
			row.Size = UDim2.new(1, -12, 0, 52)
			row.BackgroundColor3 = if entry.instanceId == selectedId
				then Color3.fromRGB(255, 148, 48)
				else Color3.fromRGB(44, 52, 68)
			row.BorderSizePixel = 0
			row.Font = Enum.Font.GothamMedium
			row.TextSize = 15
			row.TextWrapped = true
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextColor3 = if entry.instanceId == selectedId
				then Color3.fromRGB(24, 26, 32)
				else Color3.new(1, 1, 1)
			row.Text = string.format(
				"  %s　%s　+%d　性能 %s",
				entry.displayName,
				entry.qualityName,
				entry.upgradeLevel,
				tostring(entry.power)
			)
			row.Parent = list
			corner(row, 6)
			row.MouseButton1Click:Connect(function()
				if handlers.onSelect ~= nil then
					handlers.onSelect(entry.instanceId)
				end
			end)
		end
		showPreview(car)
		upgradeButton.Visible = page == "upgrade"
		upgradeButton.Active = car ~= nil and car.upgradeLevel < CarConfig.MaxUpgradeLevel
		upgradeButton.Text = if car ~= nil and car.upgradeLevel >= CarConfig.MaxUpgradeLevel
			then "已達 +10"
			else "強化"
		pullButton.Text = string.format("抽車 %d", CarConfig.SinglePullPrice)
		applyLayout()
	end

	openButton.MouseButton1Click:Connect(function()
		page = "garage"
		panel.Visible = true
		if handlers.onRefresh ~= nil then
			handlers.onRefresh()
		end
		render()
	end)
	closeButton.MouseButton1Click:Connect(function()
		panel.Visible = false
	end)
	pullButton.MouseButton1Click:Connect(function()
		if handlers.onPull ~= nil then
			handlers.onPull()
		end
	end)
	upgradeButton.MouseButton1Click:Connect(function()
		if handlers.onUpgrade ~= nil then
			handlers.onUpgrade(selectedId)
		end
	end)
	raceButton.MouseButton1Click:Connect(function()
		if handlers.onRace ~= nil then
			handlers.onRace(selectedId)
		end
	end)
	bossButton.MouseButton1Click:Connect(function()
		if handlers.onBoss ~= nil then
			handlers.onBoss(selectedId)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		if previewModel == nil or previewModel.Parent == nil then
			return
		end
		spin += dt * 0.7
		previewModel:PivotTo(CFrame.Angles(0, spin, 0))
	end)

	local ui = {}

	function ui.setState(nextState)
		state = nextState
		if state ~= nil and type(state.selectedInstanceId) == "string" and state.selectedInstanceId ~= "" then
			selectedId = state.selectedInstanceId
		elseif selectedCar() == nil then
			selectedId = nil
		end
		render()
	end

	function ui.open(nextPage: string)
		page = nextPage
		panel.Visible = true
		render()
	end

	function ui.isOpen(): boolean
		return panel.Visible
	end

	function ui.toast(text: string)
		toast.Text = text
		toast.Visible = true
		task.delay(3.2, function()
			if toast.Text == text then
				toast.Visible = false
			end
		end)
	end

	function ui.flash(outcomeId: string)
		local color = FLASH[outcomeId] or Color3.new(1, 1, 1)
		flash.BackgroundColor3 = color
		flash.BackgroundTransparency = 0.45
		task.delay(0.28, function()
			flash.BackgroundTransparency = 1
		end)
	end

	function ui.setRacing(active: boolean, text: string?)
		banner.Visible = active
		banner.Text = text or "競速進行中"
	end

	applyLayout()
	render()
	return ui
end

return GarageUI
