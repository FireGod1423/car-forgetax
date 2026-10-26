-- 車庫、抽車、強化、競速各自一個面板。可以共用同一個 ScreenGui，但按鈕只做自己的事。
-- 預覽用的是 ViewportFrame 自己的相機，不會改玩家鏡頭。
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local UpgradeConfig = require(sharedFolder:WaitForChild("UpgradeConfig"))
local CarConfig = require(sharedFolder:WaitForChild("CarConfig"))
local RaceConfig = require(sharedFolder:WaitForChild("RaceConfig"))
local CarVisualFactory = require(sharedFolder:WaitForChild("CarVisualFactory"))

local GarageUI = {}

local INK = Color3.fromRGB(18, 22, 32)
local INK_SOFT = Color3.fromRGB(28, 34, 46)
local ROW = Color3.fromRGB(44, 52, 68)
local PAPER = Color3.fromRGB(232, 236, 242)
local ORANGE = Color3.fromRGB(255, 148, 48)
local GOLD = Color3.fromRGB(255, 214, 70)
local MINT = Color3.fromRGB(96, 220, 150)
local CLOUD = Color3.fromRGB(210, 214, 220)

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

local function button(parent: Instance, text: string, color: Color3, size: UDim2?)
	local item = Instance.new("TextButton")
	item.Size = size or UDim2.fromOffset(120, 36)
	item.BackgroundColor3 = color
	item.BackgroundTransparency = 0
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.Text = text
	item.TextColor3 = Color3.fromRGB(24, 26, 32)
	item.TextSize = 16
	item.AutoButtonColor = true
	item.Modal = false
	item.Active = true
	item.Parent = parent
	corner(item, 8)
	return item
end

local function label(parent: Instance, textSize: number)
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.GothamMedium
	item.TextSize = textSize
	item.TextWrapped = true
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Top
	item.TextColor3 = PAPER
	item.Text = ""
	item.Active = false
	item.Parent = parent
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
	return table.concat(lines, "　")
end

local function carLine(entry): string
	return string.format(
		"%s　%s　+%d　性能 %s",
		entry.displayName,
		entry.qualityName,
		entry.upgradeLevel,
		tostring(entry.power)
	)
end

function GarageUI.mount(playerGui: PlayerGui, handlers)
	handlers = handlers or {}
	for _, name in ipairs({ "CarForgeTaxInterface", "CarForgeTaxGarage" }) do
		local existing = playerGui:FindFirstChild(name)
		if existing ~= nil then
			existing:Destroy()
		end
	end

	local state = nil
	local selectedId = nil
	local upgradeId = nil
	local currentPage = nil
	local racing = false
	local racingText = ""
	local previewModel = nil
	local spin = 0

	local gui = Instance.new("ScreenGui")
	gui.Name = "CarForgeTaxInterface"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 10
	gui.Enabled = true
	gui.Parent = playerGui

	local hud = label(gui, 15)
	hud.Name = "Hud"
	hud.Font = Enum.Font.GothamMedium
	hud.BackgroundColor3 = INK
	hud.BackgroundTransparency = 0.15
	hud.TextXAlignment = Enum.TextXAlignment.Center
	hud.TextYAlignment = Enum.TextYAlignment.Center
	hud.Text = "讀取車庫中…"
	corner(hud, 8)

	local banner = label(gui, 15)
	banner.Name = "RaceBanner"
	banner.Font = Enum.Font.GothamBold
	banner.BackgroundColor3 = ORANGE
	banner.BackgroundTransparency = 0.08
	banner.TextColor3 = Color3.fromRGB(24, 26, 32)
	banner.TextXAlignment = Enum.TextXAlignment.Center
	banner.TextYAlignment = Enum.TextYAlignment.Center
	banner.Visible = false
	banner.ZIndex = 5
	corner(banner, 8)

	local garageButton = Instance.new("TextButton")
	garageButton.Name = "GarageButton"
	garageButton.Size = UDim2.fromOffset(72, 72)
	garageButton.Position = UDim2.fromOffset(12, 8)
	garageButton.BackgroundColor3 = ORANGE
	garageButton.BorderSizePixel = 0
	garageButton.Text = ""
	garageButton.AutoButtonColor = true
	garageButton.Modal = false
	garageButton.Active = true
	garageButton.ZIndex = 8
	garageButton.Parent = gui
	corner(garageButton, 12)
	local body = Instance.new("Frame")
	body.Name = "CarBody"
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.new(0.5, 0, 0, 22)
	body.Size = UDim2.fromOffset(34, 12)
	body.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
	body.BorderSizePixel = 0
	body.ZIndex = 8
	body.Active = false
	body.Parent = garageButton
	corner(body, 3)
	local roof = Instance.new("Frame")
	roof.Name = "CarRoof"
	roof.AnchorPoint = Vector2.new(0.5, 1)
	roof.Position = UDim2.new(0.5, 0, 0, 1)
	roof.Size = UDim2.fromOffset(18, 8)
	roof.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
	roof.BorderSizePixel = 0
	roof.ZIndex = 8
	roof.Active = false
	roof.Parent = body
	corner(roof, 3)
	local garageCaption = label(garageButton, 14)
	garageCaption.Name = "Caption"
	garageCaption.Font = Enum.Font.GothamBold
	garageCaption.Position = UDim2.new(0, 0, 1, -22)
	garageCaption.Size = UDim2.new(1, 0, 0, 20)
	garageCaption.Text = "車庫"
	garageCaption.TextXAlignment = Enum.TextXAlignment.Center
	garageCaption.TextColor3 = Color3.fromRGB(24, 26, 32)
	garageCaption.ZIndex = 8

	local function shell(name: string, titleText: string)
		local panel = Instance.new("Frame")
		panel.Name = name
		panel.BackgroundColor3 = INK
		panel.BackgroundTransparency = 0.04
		panel.BorderSizePixel = 0
		panel.Visible = false
		panel.Active = true
		panel.ZIndex = 4
		panel.Parent = gui
		corner(panel, 12)
		local title = label(panel, 22)
		title.Name = "Title"
		title.Font = Enum.Font.GothamBold
		title.Position = UDim2.fromOffset(16, 12)
		title.Size = UDim2.new(1, -104, 0, 32)
		title.Text = titleText
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextYAlignment = Enum.TextYAlignment.Center
		title.ZIndex = 4
		local closeButton = button(panel, "關閉", CLOUD, UDim2.fromOffset(72, 32))
		closeButton.Name = "Close"
		closeButton.AnchorPoint = Vector2.new(1, 0)
		closeButton.Position = UDim2.new(1, -12, 0, 12)
		closeButton.ZIndex = 5
		return panel, closeButton
	end

	local function makeList(parent: Instance, name: string)
		local list = Instance.new("ScrollingFrame")
		list.Name = name
		list.BackgroundColor3 = INK_SOFT
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 6
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.CanvasSize = UDim2.new()
		list.Active = true
		list.ZIndex = 4
		list.Parent = parent
		corner(list, 8)
		local listLayout = Instance.new("UIListLayout")
		listLayout.Padding = UDim.new(0, 6)
		listLayout.Parent = list
		local listPadding = Instance.new("UIPadding")
		listPadding.PaddingTop = UDim.new(0, 6)
		listPadding.PaddingLeft = UDim.new(0, 6)
		listPadding.PaddingRight = UDim.new(0, 6)
		listPadding.PaddingBottom = UDim.new(0, 6)
		listPadding.Parent = list
		return list
	end

	local garagePanel, garageClose = shell("GaragePanel", "車庫")
	local garageList = makeList(garagePanel, "CarList")
	local preview = Instance.new("ViewportFrame")
	preview.Name = "Preview"
	preview.BackgroundColor3 = Color3.fromRGB(232, 240, 246)
	preview.BorderSizePixel = 0
	preview.Ambient = Color3.fromRGB(190, 190, 190)
	preview.LightColor = Color3.new(1, 1, 1)
	preview.LightDirection = Vector3.new(-1, -1, -0.4)
	preview.ZIndex = 4
	preview.Parent = garagePanel
	corner(preview, 8)
	local world = Instance.new("WorldModel")
	world.Parent = preview
	local previewCamera = Instance.new("Camera")
	previewCamera.CFrame = CFrame.lookAt(Vector3.new(0, 1.7, -7.2), Vector3.new(0, 0.45, 0))
	preview.CurrentCamera = previewCamera
	local garageDetail = label(garagePanel, 16)
	garageDetail.Name = "Detail"
	garageDetail.ZIndex = 4

	local gachaPanel, gachaClose = shell("GachaPanel", "抽車")
	local gachaDetail = label(gachaPanel, 18)
	gachaDetail.Name = "Detail"
	gachaDetail.ZIndex = 4
	local pullButton = button(gachaPanel, "抽車", ORANGE, UDim2.fromOffset(180, 44))
	pullButton.Name = "PullButton"
	pullButton.ZIndex = 5

	local upgradePanel, upgradeClose = shell("UpgradePanel", "強化")
	local upgradeList = makeList(upgradePanel, "CarList")
	local upgradeDetail = label(upgradePanel, 16)
	upgradeDetail.Name = "Detail"
	upgradeDetail.ZIndex = 4
	local upgradeButton = button(upgradePanel, "強化", GOLD, UDim2.fromOffset(180, 44))
	upgradeButton.Name = "UpgradeButton"
	upgradeButton.ZIndex = 5

	local racePanel, raceClose = shell("RacePanel", "競速")
	local raceList = makeList(racePanel, "CarList")
	local raceDetail = label(racePanel, 16)
	raceDetail.Name = "Detail"
	raceDetail.ZIndex = 4
	local raceButton = button(racePanel, "開始競速", MINT, UDim2.fromOffset(180, 44))
	raceButton.Name = "StartRaceButton"
	raceButton.ZIndex = 5

	local panels = {
		garage = garagePanel,
		gacha = gachaPanel,
		upgrade = upgradePanel,
		race = racePanel,
	}

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Active = false
	flash.Interactable = false
	flash.ZIndex = 6
	flash.Parent = gui

	local toast = label(gui, 16)
	toast.Name = "Toast"
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 1, -16)
	toast.Size = UDim2.new(0.72, 0, 0, 64)
	toast.BackgroundColor3 = INK
	toast.BackgroundTransparency = 0.1
	toast.Font = Enum.Font.GothamMedium
	toast.TextXAlignment = Enum.TextXAlignment.Center
	toast.TextYAlignment = Enum.TextYAlignment.Center
	toast.Visible = false
	toast.ZIndex = 7
	corner(toast, 8)

	local function cars()
		if state ~= nil and type(state.cars) == "table" then
			return state.cars
		end
		return {}
	end

	local function findCar(instanceId)
		if instanceId == nil then
			return nil
		end
		for _, car in ipairs(cars()) do
			if car.instanceId == instanceId then
				return car
			end
		end
		return nil
	end

	local function clearRows(list: ScrollingFrame)
		for _, child in ipairs(list:GetChildren()) do
			if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end
	end

	local function fillCars(list: ScrollingFrame, highlightId, onPick, emptyText: string)
		clearRows(list)
		local entries = cars()
		if #entries == 0 then
			local empty = label(list, 16)
			empty.Size = UDim2.new(1, -12, 0, 40)
			empty.Text = emptyText
			empty.TextColor3 = CLOUD
			empty.ZIndex = 4
			return
		end
		for _, entry in ipairs(entries) do
			local selected = entry.instanceId == highlightId
			local row = Instance.new("TextButton")
			row.Size = UDim2.new(1, -12, 0, 52)
			row.BackgroundColor3 = if selected then ORANGE else ROW
			row.BorderSizePixel = 0
			row.Font = Enum.Font.GothamMedium
			row.TextSize = 15
			row.TextWrapped = true
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextColor3 = if selected then Color3.fromRGB(24, 26, 32) else Color3.new(1, 1, 1)
			row.Text = "    " .. carLine(entry)
			row.AutoButtonColor = true
			row.Modal = false
			row.Active = true
			row.ZIndex = 4
			row.Parent = list
			corner(row, 6)
			local chip = Instance.new("Frame")
			chip.Position = UDim2.fromOffset(8, 12)
			chip.Size = UDim2.fromOffset(8, 28)
			chip.BackgroundColor3 = CarVisualFactory.qualityColor(entry.qualityId)
			chip.BorderSizePixel = 0
			chip.Active = false
			chip.ZIndex = 5
			chip.Parent = row
			corner(chip, 3)
			row.MouseButton1Click:Connect(function()
				onPick(entry.instanceId)
			end)
		end
	end

	local function showPreview(car)
		previewModel = nil
		for _, child in ipairs(world:GetChildren()) do
			child:Destroy()
		end
		if car == nil or garagePanel.Visible ~= true then
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
		local width = 1280
		local height = 720
		local currentCamera = workspace.CurrentCamera
		if currentCamera ~= nil then
			width = currentCamera.ViewportSize.X
			height = currentCamera.ViewportSize.Y
		end
		local compact = width < 760
		hud.Position = UDim2.fromOffset(96, 8)
		hud.Size = UDim2.new(1, -112, 0, 32)
		banner.AnchorPoint = Vector2.new(1, 0)
		banner.Position = UDim2.new(1, -12, 0, 46)
		banner.Size = UDim2.fromOffset(if compact then 220 else 320, 28)
		local panelPosition
		local panelSize
		if compact then
			panelPosition = UDim2.fromOffset(12, 96)
			panelSize = UDim2.new(0.88, 0, 0, math.max(300, height - 168))
		else
			panelPosition = UDim2.fromOffset(104, 88)
			panelSize = UDim2.fromOffset(440, math.clamp(height - 140, 420, 680))
		end
		for _, panel in pairs(panels) do
			panel.Position = panelPosition
			panel.Size = panelSize
		end
		garageList.Position = UDim2.fromOffset(16, 56)
		garageList.Size = UDim2.new(1, -32, 0.4, -28)
		preview.Position = UDim2.new(0, 16, 0.4, 36)
		preview.Size = UDim2.new(1, -32, 0.28, 0)
		garageDetail.Position = UDim2.new(0, 16, 0.7, 40)
		garageDetail.Size = UDim2.new(1, -32, 0.28, -52)

		gachaDetail.Position = UDim2.fromOffset(16, 64)
		gachaDetail.Size = UDim2.new(1, -32, 0, 140)
		pullButton.Position = UDim2.fromOffset(16, 214)
		pullButton.Size = UDim2.new(1, -32, 0, 44)

		upgradeList.Position = UDim2.fromOffset(16, 56)
		upgradeList.Size = UDim2.new(1, -32, 0.46, -24)
		upgradeDetail.Position = UDim2.new(0, 16, 0.46, 40)
		upgradeDetail.Size = UDim2.new(1, -32, 0.34, -8)
		upgradeButton.Position = UDim2.new(0, 16, 1, -60)
		upgradeButton.Size = UDim2.new(1, -32, 0, 44)

		raceList.Position = UDim2.fromOffset(16, 56)
		raceList.Size = UDim2.new(1, -32, 0.46, -24)
		raceDetail.Position = UDim2.new(0, 16, 0.46, 40)
		raceDetail.Size = UDim2.new(1, -32, 0.34, -8)
		raceButton.Position = UDim2.new(0, 16, 1, -60)
		raceButton.Size = UDim2.new(1, -32, 0, 44)
	end

	local function setEnabled(control: TextButton, enabled: boolean)
		control.Active = enabled
		control.AutoButtonColor = enabled
		control.BackgroundTransparency = if enabled then 0 else 0.4
	end

	local function render()
		local balance = if state ~= nil then state.balance else "—"
		local notice = if state ~= nil and state.memoryNotice ~= nil then state.memoryNotice else "關服後資料會消失"
		hud.Text = string.format("測試金幣 %s    %s", tostring(balance), notice)
		garageButton.BackgroundColor3 = if currentPage == "garage" then GOLD else ORANGE

		local selected = findCar(selectedId)
		local upgradeCar = findCar(upgradeId)
		local raceRunning = racing or (state ~= nil and state.raceActive == true)

		if selected == nil then
			garageDetail.Text = "還沒有車輛。到場景裡的抽車機花費測試金幣取得第一台車。"
		else
			garageDetail.Text = string.format(
				"%s\n%s　%s　強化 +%d　性能 %s\n點選列表會把這台車設為競速用車。",
				selected.displayName,
				selected.qualityName,
				selected.colorName,
				selected.upgradeLevel,
				tostring(selected.power)
			)
		end
		fillCars(garageList, selectedId, function(instanceId)
			if handlers.onSelect ~= nil then
				handlers.onSelect(instanceId)
			end
		end, "車庫是空的")
		showPreview(selected)

		gachaDetail.Text = string.format(
			"單抽 %d 測試金幣。\n品質、車款與重生階級都由伺服器決定，這個面板不能指定結果。\n抽到的車會進入伺服器車庫。",
			CarConfig.SinglePullPrice
		)
		pullButton.Text = string.format("抽車 %d", CarConfig.SinglePullPrice)

		if upgradeCar == nil then
			upgradeDetail.Text = "請選擇一台你的車。下面會顯示伺服器實際使用的五種結果機率。強化不扣金幣。"
		else
			upgradeDetail.Text = string.format(
				"%s　%s　目前 +%d　性能 %s\n%s\n結果只顯示伺服器實際抽到的那一個。",
				upgradeCar.displayName,
				upgradeCar.qualityName,
				upgradeCar.upgradeLevel,
				tostring(upgradeCar.power),
				oddsText(upgradeCar.upgradeLevel)
			)
		end
		local canUpgrade = upgradeCar ~= nil and upgradeCar.upgradeLevel < CarConfig.MaxUpgradeLevel
		upgradeButton.Text = if upgradeCar ~= nil and upgradeCar.upgradeLevel >= CarConfig.MaxUpgradeLevel
			then "已達 +10"
			else "強化"
		setEnabled(upgradeButton, canUpgrade)
		fillCars(upgradeList, upgradeId, function(instanceId)
			upgradeId = instanceId
			render()
		end, "沒有可強化的車")

		local status = if raceRunning
			then (if racingText ~= "" then racingText else "單場競速進行中")
			else "目前沒有進行中的競速。"
		if selected == nil then
			raceDetail.Text = "請先選擇一台你的車。\n" .. status
		else
			raceDetail.Text = string.format(
				"目前選擇：%s　+%d　性能 %s\n%s\n單場競速。完賽後伺服器發放 %d 測試金幣，不會自動開始下一場。",
				selected.displayName,
				selected.upgradeLevel,
				tostring(selected.power),
				status,
				RaceConfig.NormalReward
			)
		end
		local canStart = selected ~= nil and not raceRunning
		raceButton.Text = if raceRunning then "競速進行中" else "開始競速"
		setEnabled(raceButton, canStart)
		fillCars(raceList, selectedId, function(instanceId)
			if handlers.onSelect ~= nil then
				handlers.onSelect(instanceId)
			end
		end, "車庫是空的")
		applyLayout()
	end

	local api = {}

	function api.setState(nextState)
		state = nextState
		if state ~= nil and type(state.selectedInstanceId) == "string" and state.selectedInstanceId ~= "" then
			selectedId = state.selectedInstanceId
		elseif findCar(selectedId) == nil then
			selectedId = nil
		end
		if upgradeId ~= nil and findCar(upgradeId) == nil then
			upgradeId = nil
		end
		render()
	end

	function api.open(nextPage: string)
		if panels[nextPage] == nil then
			return
		end
		currentPage = nextPage
		for pageName, panel in pairs(panels) do
			panel.Visible = pageName == nextPage
		end
		render()
	end

	function api.close()
		currentPage = nil
		for _, panel in pairs(panels) do
			panel.Visible = false
		end
		render()
	end

	function api.isOpen(): boolean
		return currentPage ~= nil
	end

	function api.toast(text: string)
		toast.Text = text
		toast.Visible = true
		task.delay(3.2, function()
			if toast.Text == text then
				toast.Visible = false
			end
		end)
	end

	function api.flash(outcomeId: string)
		local color = FLASH[outcomeId] or Color3.new(1, 1, 1)
		flash.BackgroundColor3 = color
		flash.BackgroundTransparency = 0.55
		task.delay(0.28, function()
			flash.BackgroundTransparency = 1
		end)
	end

	function api.setRacing(active: boolean, text: string?)
		racing = active
		racingText = if active then (text or "單場競速進行中") else ""
		banner.Visible = active
		banner.Text = racingText
		render()
	end

	local function toggleGarage()
		if currentPage == "garage" then
			api.close()
			return
		end
		api.open("garage")
		if handlers.onRefresh ~= nil then
			handlers.onRefresh()
		end
	end

	garageButton.MouseButton1Click:Connect(toggleGarage)
	garageClose.MouseButton1Click:Connect(api.close)
	gachaClose.MouseButton1Click:Connect(api.close)
	upgradeClose.MouseButton1Click:Connect(api.close)
	raceClose.MouseButton1Click:Connect(api.close)
	pullButton.MouseButton1Click:Connect(function()
		if handlers.onPull ~= nil then
			handlers.onPull()
		end
	end)
	upgradeButton.MouseButton1Click:Connect(function()
		if handlers.onUpgrade ~= nil then
			handlers.onUpgrade(upgradeId)
		end
	end)
	raceButton.MouseButton1Click:Connect(function()
		if handlers.onRace ~= nil then
			handlers.onRace(selectedId)
		end
	end)

	local spinConn = RunService.RenderStepped:Connect(function(dt)
		if previewModel == nil or previewModel.Parent == nil or garagePanel.Visible ~= true then
			return
		end
		spin += dt * 0.7
		previewModel:PivotTo(CFrame.Angles(0, spin, 0))
	end)
	local viewportConn = nil
	local function bindViewport()
		if viewportConn ~= nil then
			viewportConn:Disconnect()
			viewportConn = nil
		end
		local currentCamera = workspace.CurrentCamera
		if currentCamera ~= nil then
			viewportConn = currentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
		end
		applyLayout()
	end
	local cameraConn = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindViewport)
	gui.Destroying:Connect(function()
		spinConn:Disconnect()
		cameraConn:Disconnect()
		if viewportConn ~= nil then
			viewportConn:Disconnect()
		end
	end)

	bindViewport()
	render()
	return api
end

return GarageUI
