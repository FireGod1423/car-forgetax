-- R0 抽車介面、橫向卡片與圖鑑。動畫只使用伺服器已經發下來的結果。
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local CarConfig = require(sharedFolder:WaitForChild("CarConfig"))
local AutoSellConfig = require(sharedFolder:WaitForChild("AutoSellConfig"))
local CarCatalog = require(sharedFolder:WaitForChild("CarCatalog"))
local CarVisualFactory = require(sharedFolder:WaitForChild("CarVisualFactory"))
local GachaSound = require(script.Parent:WaitForChild("GachaSound"))

local GachaBoard = {}

local INK = Color3.fromRGB(18, 22, 32)
local INK_SOFT = Color3.fromRGB(28, 34, 46)
local ROW = Color3.fromRGB(44, 52, 68)
local PAPER = Color3.fromRGB(236, 238, 242)
local ORANGE = Color3.fromRGB(255, 148, 48)
local CLOUD = Color3.fromRGB(210, 214, 220)

local GREETINGS = {
	"嘿，小子，要不要看看我的寶貝？",
	"這台車雖然舊了點，但還能跑！",
	"500 金幣，試試手氣吧。",
	"別看我這樣，以前也是個車王。",
}
local LEGENDARY_LINE = "等等……這台車怎麼會在我的箱子裡？！"

local CARD_W = 96
local STEP = 104
local WIN_INDEX = 34
local CARD_COUNT = 42
local DURATION = 4.2
local RANK = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
}

local function corner(parent: Instance, radius: number)
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, radius)
	uiCorner.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = color
	uiStroke.Thickness = thickness
	uiStroke.Parent = parent
	return uiStroke
end

local function label(parent: Instance, size: number)
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.GothamMedium
	item.TextSize = size
	item.TextColor3 = PAPER
	item.TextWrapped = true
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Parent = parent
	return item
end

local function button(parent: Instance, text: string, color: Color3)
	local item = Instance.new("TextButton")
	item.BackgroundColor3 = color
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.TextSize = 16
	item.TextColor3 = Color3.fromRGB(24, 26, 32)
	item.Text = text
	item.AutoButtonColor = true
	item.Parent = parent
	corner(item, 8)
	return item
end

local function r0Cars()
	local cars = {}
	for _, car in ipairs(CarCatalog.getAll()) do
		if car.UnlockRebirth == 0 then
			table.insert(cars, car)
		end
	end
	return cars
end

local function entryFromCatalog(car)
	return {
		modelId = car.ModelId,
		displayName = car.DisplayName,
		qualityId = car.Quality,
	}
end

local function commonEntry()
	local eligible = CarCatalog.getEligible("Common", 0)
	if #eligible == 0 then
		return nil
	end
	return entryFromCatalog(eligible[1])
end

local function weightedEntry(rng): any
	local total = CarConfig.sumWeights()
	local roll = rng:NextInteger(1, total)
	local cursor = 0
	for _, quality in ipairs(CarConfig.getQualities()) do
		cursor += quality.Weight
		if roll <= cursor then
			local eligible = CarCatalog.getEligible(quality.Id, 0)
			if #eligible == 0 then
				return commonEntry()
			end
			return entryFromCatalog(eligible[rng:NextInteger(1, #eligible)])
		end
	end
	return commonEntry()
end

local function buildStrip(result, rng)
	local winner = {
		modelId = result.modelId,
		displayName = result.displayName,
		qualityId = result.qualityId,
	}
	local cards = {}
	for _ = 1, CARD_COUNT do
		table.insert(cards, weightedEntry(rng) or winner)
	end
	cards[WIN_INDEX] = winner
	local winnerRank = RANK[winner.qualityId] or 1
	local fallback = commonEntry() or winner
	for index = WIN_INDEX - 4, WIN_INDEX + 2 do
		local card = cards[index]
		if index ~= WIN_INDEX and card ~= nil and (RANK[card.qualityId] or 1) > winnerRank then
			cards[index] = fallback
		end
	end
	return cards
end

local function clearViewport(world: WorldModel)
	for _, child in ipairs(world:GetChildren()) do
		child:Destroy()
	end
end

local function presentCar(world: WorldModel, camera: Camera, spec, silhouette: boolean)
	clearViewport(world)
	local model
	if silhouette then
		model = Instance.new("Model")
		model.Name = "Silhouette"
		local black = Color3.fromRGB(10, 10, 12)
		local function block(name: string, size: Vector3, cf: CFrame, cylinder: boolean)
			local part = Instance.new("Part")
			part.Name = name
			part.Size = size
			part.Color = black
			part.Material = Enum.Material.SmoothPlastic
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CastShadow = false
			if cylinder then
				part.Shape = Enum.PartType.Cylinder
			end
			part.CFrame = cf
			part.Parent = model
			return part
		end
		local body = block("Body", Vector3.new(1.2, 0.4, 2.4), CFrame.new(0, 0.5, 0), false)
		model.PrimaryPart = body
		block("Cabin", Vector3.new(1, 0.32, 1), CFrame.new(0, 0.78, 0.1), false)
		block("WheelFL", Vector3.new(0.2, 0.42, 0.42), CFrame.new(-0.66, 0.24, -0.7), true)
		block("WheelFR", Vector3.new(0.2, 0.42, 0.42), CFrame.new(0.66, 0.24, -0.7), true)
		block("WheelRL", Vector3.new(0.2, 0.42, 0.42), CFrame.new(-0.66, 0.24, 0.74), true)
		block("WheelRR", Vector3.new(0.2, 0.42, 0.42), CFrame.new(0.66, 0.24, 0.74), true)
	else
		model = CarVisualFactory.build({
			modelId = spec.modelId,
			qualityId = spec.qualityId,
			upgradeLevel = 0,
			displayName = spec.displayName,
		})
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BillboardGui") then
				descendant:Destroy()
			end
		end
	end
	model.Parent = world
	local boxCf = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() - boxCf.Position)
	local focus = Vector3.zero
	local distance = if silhouette then 4.6 else 5.2
	camera.FieldOfView = 32
	camera.CFrame = CFrame.lookAt(focus + Vector3.new(distance * 0.45, distance * 0.28, -distance * 0.72), focus)
	return model
end

function GachaBoard.mount(panel: Frame)
	local board = {}
	local discovered = {}
	local discoveredSignature = ""
	local page = "main"
	local autoSellState = {
		enabled = false,
		maxQuality = nil,
	}
	local pendingConfirm = false
	local sellSignature = ""
	local playing = false
	local locked = false
	local revealStarted = false
	local settled = false
	local spinConnection: RBXScriptConnection? = nil
	local spinModel = nil
	local spinRest: CFrame? = nil
	local lastResult = nil

	local subtitle = label(panel, 16)
	subtitle.Name = "DealerTitle"
	subtitle.Font = Enum.Font.GothamBold
	subtitle.Position = UDim2.fromOffset(16, 46)
	subtitle.Size = UDim2.new(1, -120, 0, 22)
	subtitle.Text = "老破　·　R0 流浪車商"
	subtitle.ZIndex = 5

	local dialogue = label(panel, 15)
	dialogue.Name = "Dialogue"
	dialogue.Position = UDim2.fromOffset(16, 70)
	dialogue.Size = UDim2.new(1, -32, 0, 24)
	dialogue.Text = GREETINGS[1]
	dialogue.ZIndex = 5

	local info = label(panel, 15)
	info.Name = "Wallet"
	info.Position = UDim2.fromOffset(16, 96)
	info.Size = UDim2.new(1, -32, 0, 22)
	info.Text = "金幣 —　　單抽 500"
	info.ZIndex = 5

	local clip = Instance.new("Frame")
	clip.Name = "ReelClip"
	clip.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
	clip.BorderSizePixel = 0
	clip.ClipsDescendants = true
	clip.Position = UDim2.fromOffset(16, 126)
	clip.Size = UDim2.new(1, -32, 0, 116)
	clip.ZIndex = 5
	clip.Parent = panel
	corner(clip, 8)
	stroke(clip, Color3.fromRGB(255, 176, 72), 1)

	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.Size = UDim2.fromOffset(CARD_COUNT * STEP, 116)
	strip.ZIndex = 5
	strip.Parent = clip

	local pointer = Instance.new("Frame")
	pointer.Name = "Pointer"
	pointer.AnchorPoint = Vector2.new(0.5, 0)
	pointer.BackgroundColor3 = Color3.fromRGB(255, 214, 70)
	pointer.BorderSizePixel = 0
	pointer.Position = UDim2.new(0.5, 0, 0, 0)
	pointer.Size = UDim2.new(0, 3, 1, 0)
	pointer.ZIndex = 7
	pointer.Parent = clip

	local resultFrame = Instance.new("Frame")
	resultFrame.Name = "Result"
	resultFrame.BackgroundColor3 = INK_SOFT
	resultFrame.BorderSizePixel = 0
	resultFrame.Position = UDim2.fromOffset(16, 250)
	resultFrame.Size = UDim2.new(1, -32, 0, 132)
	resultFrame.Visible = false
	resultFrame.ZIndex = 5
	resultFrame.Parent = panel
	corner(resultFrame, 8)
	local resultStroke = stroke(resultFrame, CLOUD, 1.5)

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "ResultViewport"
	viewport.BackgroundColor3 = Color3.fromRGB(214, 222, 230)
	viewport.BorderSizePixel = 0
	viewport.Position = UDim2.fromOffset(8, 8)
	viewport.Size = UDim2.fromOffset(168, 116)
	viewport.Ambient = Color3.fromRGB(180, 180, 180)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -1, -0.4)
	viewport.ZIndex = 6
	viewport.Parent = resultFrame
	corner(viewport, 8)
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local resultTitle = label(resultFrame, 18)
	resultTitle.Name = "ResultTitle"
	resultTitle.Font = Enum.Font.GothamBold
	resultTitle.Position = UDim2.fromOffset(188, 16)
	resultTitle.Size = UDim2.new(1, -200, 0, 28)
	resultTitle.ZIndex = 6

	local resultBody = label(resultFrame, 15)
	resultBody.Name = "ResultBody"
	resultBody.Position = UDim2.fromOffset(188, 48)
	resultBody.Size = UDim2.new(1, -200, 0, 68)
	resultBody.TextYAlignment = Enum.TextYAlignment.Top
	resultBody.ZIndex = 6

	local banner = label(resultFrame, 16)
	banner.Name = "LegendaryBanner"
	banner.Font = Enum.Font.GothamBold
	banner.Text = "傳說車輛解鎖"
	banner.TextColor3 = Color3.fromRGB(255, 186, 64)
	banner.TextXAlignment = Enum.TextXAlignment.Left
	banner.Position = UDim2.fromOffset(188, 96)
	banner.Size = UDim2.new(1, -200, 0, 24)
	banner.Visible = false
	banner.ZIndex = 6

	local pullButton = button(panel, "抽一台車", ORANGE)
	pullButton.Name = "PullButton"
	pullButton.Position = UDim2.fromOffset(16, 392)
	pullButton.Size = UDim2.new(0.46, -12, 0, 40)
	pullButton.ZIndex = 6

	local skipButton = button(panel, "跳過動畫", CLOUD)
	skipButton.Name = "SkipButton"
	skipButton.Position = UDim2.new(0.46, 8, 0, 392)
	skipButton.Size = UDim2.new(0.27, -8, 0, 40)
	skipButton.Visible = false
	skipButton.ZIndex = 6

	local soundButton = button(panel, "音效：開", CLOUD)
	soundButton.Name = "SoundToggle"
	soundButton.Position = UDim2.new(0.73, 4, 0, 392)
	soundButton.Size = UDim2.new(0.27, -20, 0, 40)
	soundButton.ZIndex = 6

	local oddsButton = button(panel, "查看機率", CLOUD)
	oddsButton.Name = "OddsButton"
	oddsButton.Position = UDim2.fromOffset(16, 440)
	oddsButton.Size = UDim2.new(0.5, -20, 0, 36)
	oddsButton.ZIndex = 6

	local catalogButton = button(panel, "車款圖鑑", CLOUD)
	catalogButton.Name = "CatalogButton"
	catalogButton.Position = UDim2.new(0.5, 4, 0, 440)
	catalogButton.Size = UDim2.new(0.5, -20, 0, 36)
	catalogButton.ZIndex = 6

	local autoButton = button(panel, "自動販賣：關", CLOUD)
	autoButton.Name = "AutoSellButton"
	autoButton.Position = UDim2.fromOffset(16, 484)
	autoButton.Size = UDim2.new(1, -32, 0, 36)
	autoButton.ZIndex = 6

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundColor3 = INK
	overlay.BorderSizePixel = 0
	overlay.Position = UDim2.fromOffset(12, 100)
	overlay.Size = UDim2.new(1, -24, 0, 440)
	overlay.Visible = false
	overlay.ZIndex = 8
	overlay.Parent = panel
	corner(overlay, 8)

	local overlayTitle = label(overlay, 18)
	overlayTitle.Name = "OverlayTitle"
	overlayTitle.Font = Enum.Font.GothamBold
	overlayTitle.Position = UDim2.fromOffset(12, 8)
	overlayTitle.Size = UDim2.new(1, -120, 0, 28)
	overlayTitle.ZIndex = 9

	local backButton = button(overlay, "返回", CLOUD)
	backButton.Name = "BackButton"
	backButton.AnchorPoint = Vector2.new(1, 0)
	backButton.Position = UDim2.new(1, -8, 0, 8)
	backButton.Size = UDim2.fromOffset(72, 28)
	backButton.ZIndex = 9

	local overlayBody = Instance.new("ScrollingFrame")
	overlayBody.Name = "OverlayBody"
	overlayBody.BackgroundTransparency = 1
	overlayBody.BorderSizePixel = 0
	overlayBody.Position = UDim2.fromOffset(8, 44)
	overlayBody.Size = UDim2.new(1, -16, 1, -52)
	overlayBody.ScrollBarThickness = 6
	overlayBody.AutomaticCanvasSize = Enum.AutomaticSize.Y
	overlayBody.CanvasSize = UDim2.new()
	overlayBody.ZIndex = 9
	overlayBody.Parent = overlay
	local overlayLayout = Instance.new("UIListLayout")
	overlayLayout.Padding = UDim.new(0, 6)
	overlayLayout.SortOrder = Enum.SortOrder.LayoutOrder
	overlayLayout.Parent = overlayBody

	local reelConnection: RBXScriptConnection? = nil

	local function setPage(nextPage: string)
		page = nextPage
		local showing = nextPage ~= "main"
		overlay.Visible = showing
		clip.Visible = not showing
		resultFrame.Visible = not showing and lastResult ~= nil
	end

	local function clearOverlay()
		for _, child in ipairs(overlayBody:GetChildren()) do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		overlayBody.CanvasPosition = Vector2.zero
	end

	local function discoveredSet(): { [string]: boolean }
		local set = {}
		for _, modelId in ipairs(discovered) do
			if type(modelId) == "string" then
				set[modelId] = true
			end
		end
		return set
	end

	local function showOdds()
		clearOverlay()
		overlayTitle.Text = "抽車機率"
		local total = CarConfig.sumWeights()
		local note = label(overlayBody, 14)
		note.Size = UDim2.new(1, -8, 0, 64)
		note.Text = "下面是品質機率，資料來自伺服器使用的 CarConfig。R0 目前每個品質各有一款車，所以該車的取得機率等於品質機率。同一品質若有多款，伺服器會在其中平均選一台。"
		note.TextYAlignment = Enum.TextYAlignment.Top
		note.ZIndex = 9
		for _, quality in ipairs(CarConfig.getQualities()) do
			local row = Instance.new("Frame")
			row.BackgroundColor3 = ROW
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, -8, 0, 36)
			row.ZIndex = 9
			row.Parent = overlayBody
			corner(row, 6)
			stroke(row, CarVisualFactory.qualityColor(quality.Id), 2)
			local text = label(row, 16)
			text.Size = UDim2.new(1, -16, 1, 0)
			text.Position = UDim2.fromOffset(8, 0)
			text.Font = Enum.Font.GothamBold
			local percent = if total > 0 then (quality.Weight / total) * 100 else 0
			text.Text = string.format("%s　%d%%", quality.DisplayName, percent)
			text.ZIndex = 10
		end
		setPage("odds")
	end

	local function showCatalog()
		clearOverlay()
		local cars = r0Cars()
		local known = discoveredSet()
		local foundCount = 0
		for _, car in ipairs(cars) do
			if known[car.ModelId] == true then
				foundCount += 1
			end
		end
		overlayTitle.Text = string.format("已發現 %d／%d", foundCount, #cars)
		local note = label(overlayBody, 14)
		note.Size = UDim2.new(1, -8, 0, 40)
		note.Text = "圖鑑是發現紀錄，不是目前車庫。報廢後仍算已發現。關服後這份紀錄會消失。"
		note.TextYAlignment = Enum.TextYAlignment.Top
		note.ZIndex = 9
		for _, car in ipairs(cars) do
			local knownCar = known[car.ModelId] == true
			local quality = CarConfig.getQuality(car.Quality)
			local row = Instance.new("Frame")
			row.Name = car.ModelId
			row.BackgroundColor3 = ROW
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, -8, 0, 78)
			row.ZIndex = 9
			row.Parent = overlayBody
			corner(row, 6)
			stroke(row, if knownCar then CarVisualFactory.qualityColor(car.Quality) else Color3.fromRGB(40, 40, 44), 2)
			local preview = Instance.new("ViewportFrame")
			preview.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
			preview.BorderSizePixel = 0
			preview.Position = UDim2.fromOffset(6, 6)
			preview.Size = UDim2.fromOffset(92, 66)
			preview.ZIndex = 10
			preview.Parent = row
			corner(preview, 6)
			local previewWorld = Instance.new("WorldModel")
			previewWorld.Parent = preview
			local previewCamera = Instance.new("Camera")
			previewCamera.Parent = preview
			preview.CurrentCamera = previewCamera
			presentCar(previewWorld, previewCamera, entryFromCatalog(car), not knownCar)
			local name = label(row, 16)
			name.Font = Enum.Font.GothamBold
			name.Position = UDim2.fromOffset(108, 8)
			name.Size = UDim2.new(1, -116, 0, 22)
			name.Text = if knownCar then car.DisplayName else "???"
			name.ZIndex = 10
			local detail = label(row, 14)
			detail.Position = UDim2.fromOffset(108, 32)
			detail.Size = UDim2.new(1, -116, 0, 38)
			detail.TextYAlignment = Enum.TextYAlignment.Top
			local qualityName = if quality ~= nil then quality.DisplayName else car.Quality
			if knownCar then
				local power = CarConfig.calculatePower(0, car.Quality, 0)
				detail.Text = string.format("%s　基礎性能 %s\n已發現", qualityName, tostring(power))
			else
				detail.Text = string.format("%s\n未解鎖", qualityName)
			end
			detail.ZIndex = 10
		end
		setPage("catalog")
	end

	local SELL_MODES = {
		{ id = "Common", label = "普通以下" },
		{ id = "Uncommon", label = "優良以下" },
		{ id = "Rare", label = "稀有以下" },
		{ id = "Epic", label = "史詩以下" },
		{ id = "Legendary", label = "所有品質" },
	}

	local function qualityLabel(qualityId: string): string
		local quality = CarConfig.getQuality(qualityId)
		return if quality ~= nil then quality.DisplayName else qualityId
	end

	local function modeLabel(maxQuality): string
		for _, mode in ipairs(SELL_MODES) do
			if mode.id == maxQuality then
				return mode.label
			end
		end
		return "關"
	end

	local function sellLine(qualityId: string): string
		return string.format("%s　%d 金幣", qualityLabel(qualityId), AutoSellConfig.price(0, qualityId) or 0)
	end

	local function submitAutoSell(enabled: boolean, maxQuality, confirmAll: boolean)
		if board._onAutoSell ~= nil then
			board._onAutoSell(enabled, maxQuality, confirmAll)
		end
	end

	local function showAutoSell()
		pendingConfirm = false
		clearOverlay()
		overlayTitle.Text = "自動販賣設定"
		local enabled = autoSellState.enabled == true and type(autoSellState.maxQuality) == "string"
		local summary = label(overlayBody, 15)
		summary.LayoutOrder = 1
		summary.Size = UDim2.new(1, -8, 0, 88)
		summary.TextYAlignment = Enum.TextYAlignment.Top
		summary.ZIndex = 9
		if not enabled then
			summary.Text = "自動販賣：關\n抽到的車都會留在車庫。\n只會賣掉之後新抽到、而且符合條件的車。"
		else
			local sells, keeps = AutoSellConfig.split(autoSellState.maxQuality)
			local sellText = {}
			local keepText = {}
			for _, qualityId in ipairs(sells) do
				table.insert(sellText, sellLine(qualityId))
			end
			for _, qualityId in ipairs(keeps) do
				table.insert(keepText, qualityLabel(qualityId))
			end
			local keepLine = if #keepText > 0 then table.concat(keepText, "、") else "沒有"
			summary.Text = string.format(
				"會自動販賣：\n%s\n會保留：%s",
				table.concat(sellText, "\n"),
				keepLine
			)
			summary.Size = UDim2.new(1, -8, 0, 36 + #sellText * 22)
		end

		if enabled then
			local toggle = button(overlayBody, "關閉自動販賣", Color3.fromRGB(180, 84, 72))
			toggle.LayoutOrder = 2
			toggle.Size = UDim2.new(1, -8, 0, 36)
			toggle.ZIndex = 9
			toggle.MouseButton1Click:Connect(function()
				submitAutoSell(false, nil, false)
			end)
		end

		for index, qualityId in ipairs(AutoSellConfig.Order) do
			local priceRow = label(overlayBody, 15)
			priceRow.LayoutOrder = 10 + index
			priceRow.Size = UDim2.new(1, -8, 0, 22)
			priceRow.Text = "售價　" .. sellLine(qualityId)
			priceRow.ZIndex = 9
		end

		for index, mode in ipairs(SELL_MODES) do
			local chosen = enabled and autoSellState.maxQuality == mode.id
			local modeButton = button(overlayBody, mode.label, if chosen then ORANGE else CLOUD)
			modeButton.Name = "SellMode" .. mode.id
			modeButton.LayoutOrder = 20 + index
			modeButton.Size = UDim2.new(1, -8, 0, 34)
			modeButton.ZIndex = 9
			modeButton.MouseButton1Click:Connect(function()
				if mode.id == "Legendary" then
					pendingConfirm = true
					clearOverlay()
					overlayTitle.Text = "確認出售傳說"
					local warning = label(overlayBody, 16)
					warning.LayoutOrder = 1
					warning.TextColor3 = Color3.fromRGB(255, 186, 64)
					warning.Size = UDim2.new(1, -8, 0, 96)
					warning.TextYAlignment = Enum.TextYAlignment.Top
					warning.ZIndex = 9
					warning.Text = "所有品質包含傳說車。\n傳說會以 2000 金幣自動賣掉，無法在這次抽車裡留在車庫。\n請再確認一次。"
					local confirm = button(overlayBody, "確定連傳說一起賣", Color3.fromRGB(180, 84, 72))
					confirm.LayoutOrder = 2
					confirm.Size = UDim2.new(1, -8, 0, 36)
					confirm.ZIndex = 9
					confirm.MouseButton1Click:Connect(function()
						pendingConfirm = false
						submitAutoSell(true, "Legendary", true)
					end)
					local cancel = button(overlayBody, "取消", CLOUD)
					cancel.LayoutOrder = 3
					cancel.Size = UDim2.new(1, -8, 0, 36)
					cancel.ZIndex = 9
					cancel.MouseButton1Click:Connect(function()
						pendingConfirm = false
						showAutoSell()
					end)
					setPage("sell")
					return
				end
				submitAutoSell(true, mode.id, false)
			end)
		end
		sellSignature = tostring(autoSellState.enabled) .. ":" .. tostring(autoSellState.maxQuality)
		setPage("sell")
	end

	local function stopSpin()
		if spinConnection ~= nil then
			spinConnection:Disconnect()
			spinConnection = nil
		end
		spinModel = nil
		spinRest = nil
	end

	local function stopReel()
		if reelConnection ~= nil then
			reelConnection:Disconnect()
			reelConnection = nil
		end
	end

	local function showResult(result, legendary: boolean)
		lastResult = result
		resultFrame.Visible = page == "main"
		local quality = CarConfig.getQuality(result.qualityId)
		local qualityName = if quality ~= nil then quality.DisplayName else tostring(result.qualityId)
		resultStroke.Color = CarVisualFactory.qualityColor(result.qualityId)
		resultTitle.Text = tostring(result.displayName)
		resultTitle.TextColor3 = CarVisualFactory.qualityColor(result.qualityId)
		local powerText = if result.power ~= nil then tostring(result.power) else "—"
		if result.sold == true then
			resultBody.Text = string.format("%s\n已自動販賣，獲得 %s 金幣", qualityName, tostring(result.sellPrice))
		else
			resultBody.Text = string.format("%s\n已放入車庫　性能 %s", qualityName, powerText)
		end
		banner.Visible = legendary
		stopSpin()
		local model = presentCar(world, camera, {
			modelId = result.modelId,
			displayName = result.displayName,
			qualityId = result.qualityId,
		}, false)
		spinModel = model
		spinRest = model:GetPivot()
		local angle = 0
		spinConnection = RunService.Heartbeat:Connect(function(dt)
			if spinModel == nil or spinRest == nil or spinModel.Parent == nil then
				return
			end
			angle += dt * 0.55
			spinModel:PivotTo(spinRest * CFrame.Angles(0, angle, 0))
		end)
		if legendary then
			dialogue.Text = LEGENDARY_LINE
		end
	end

	local function makeCard(card, index: number): Frame
		local item = Instance.new("Frame")
		item.Name = "Card" .. index
		item.BackgroundColor3 = Color3.fromRGB(32, 36, 48)
		item.BorderSizePixel = 0
		item.Position = UDim2.fromOffset((index - 1) * STEP, 10)
		item.Size = UDim2.fromOffset(CARD_W, 96)
		item.ZIndex = 5
		item.Parent = strip
		corner(item, 8)
		stroke(item, CarVisualFactory.qualityColor(card.qualityId), 2)
		local quality = CarConfig.getQuality(card.qualityId)
		local qualityLabel = label(item, 13)
		qualityLabel.Font = Enum.Font.GothamBold
		qualityLabel.Position = UDim2.fromOffset(6, 8)
		qualityLabel.Size = UDim2.new(1, -12, 0, 18)
		qualityLabel.Text = if quality ~= nil then quality.DisplayName else tostring(card.qualityId)
		qualityLabel.TextColor3 = CarVisualFactory.qualityColor(card.qualityId)
		qualityLabel.ZIndex = 6
		local nameLabel = label(item, 14)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Position = UDim2.fromOffset(6, 32)
		nameLabel.Size = UDim2.new(1, -12, 0, 52)
		nameLabel.Text = card.displayName
		nameLabel.TextYAlignment = Enum.TextYAlignment.Top
		nameLabel.ZIndex = 6
		if index == WIN_INDEX then
			item:SetAttribute("WinningCard", true)
		end
		return item
	end

	local function offsetFor(index: number, width: number): number
		return width * 0.5 - ((index - 1) * STEP + CARD_W * 0.5)
	end

	local function finishPlayback(result, playSound: boolean, onDone)
		if settled then
			return
		end
		settled = true
		stopReel()
		playing = false
		skipButton.Visible = false
		local width = math.max(clip.AbsoluteSize.X, 200)
		strip.Position = UDim2.fromOffset(offsetFor(WIN_INDEX, width), 0)
		local legendary = result.qualityId == "Legendary"
		showResult(result, legendary)
		if playSound and not revealStarted then
			revealStarted = true
			GachaSound.stopAll()
			GachaSound.playLock()
			GachaSound.playReveal(result.qualityId)
		end
		if onDone ~= nil then
			onDone()
		end
	end

	local activeDone = nil

	function board.play(result, onDone)
		if type(result) ~= "table" or type(result.modelId) ~= "string" or type(result.qualityId) ~= "string" then
			if onDone ~= nil then
				onDone()
			end
			return
		end
		stopReel()
		stopSpin()
		GachaSound.stopAll()
		playing = true
		revealStarted = false
		settled = false
		activeDone = onDone
		skipButton.Visible = true
		setPage("main")
		for _, child in ipairs(strip:GetChildren()) do
			child:Destroy()
		end
		local cards = buildStrip(result, Random.new())
		for index, card in ipairs(cards) do
			makeCard(card, index)
		end
		local width = math.max(clip.AbsoluteSize.X, 200)
		local startOffset = offsetFor(WIN_INDEX - 26, width)
		local endOffset = offsetFor(WIN_INDEX, width)
		strip.Position = UDim2.fromOffset(startOffset, 0)
		GachaSound.playStart()
		local elapsed = 0
		local lastIndex = nil
		reelConnection = RunService.Heartbeat:Connect(function(dt)
			if not playing then
				return
			end
			elapsed += dt
			local alpha = math.clamp(elapsed / DURATION, 0, 1)
			local eased = 1 - (1 - alpha) ^ 3
			local widthNow = math.max(clip.AbsoluteSize.X, 200)
			local startNow = offsetFor(WIN_INDEX - 26, widthNow)
			local endNow = offsetFor(WIN_INDEX, widthNow)
			local offset = startNow + (endNow - startNow) * eased
			local shake = 0
			if alpha > 0.94 then
				shake = math.sin(elapsed * 48) * (1 - alpha) * 18
			end
			strip.Position = UDim2.fromOffset(offset + shake, 0)
			local center = widthNow * 0.5
			local pointerX = center - offset
			local index = math.floor(pointerX / STEP) + 1
			if lastIndex == nil then
				lastIndex = index
			elseif index ~= lastIndex then
				lastIndex = index
				GachaSound.playTick()
			end
			if alpha >= 1 then
				local done = activeDone
				activeDone = nil
				finishPlayback(result, true, done)
			end
		end)
	end

	function board.skip()
		if not playing then
			return
		end
		if settled then
			return
		end
		settled = true
		local result = board._activeResult
		local done = activeDone
		activeDone = nil
		local shouldSound = not revealStarted
		playing = false
		stopReel()
		GachaSound.stopAll()
		if result ~= nil then
			showResult(result, result.qualityId == "Legendary")
			strip.Position = UDim2.fromOffset(offsetFor(WIN_INDEX, math.max(clip.AbsoluteSize.X, 200)), 0)
		end
		skipButton.Visible = false
		board._activeResult = nil
		if shouldSound and result ~= nil then
			revealStarted = true
			GachaSound.playLock()
			GachaSound.playReveal(result.qualityId)
		else
			revealStarted = true
		end
		if done ~= nil then
			done()
		end
	end

	local playOriginal = board.play
	function board.play(result, onDone)
		board._activeResult = result
		playOriginal(result, function()
			board._activeResult = nil
			if onDone ~= nil then
				onDone()
			end
		end)
	end

	function board.isBusy(): boolean
		return playing or locked
	end

	function board.setLocked(nextLocked: boolean)
		locked = nextLocked == true
		pullButton.Active = not locked and not playing
		pullButton.AutoButtonColor = pullButton.Active
		pullButton.BackgroundTransparency = if pullButton.Active then 0 else 0.4
	end

	function board.update(state)
		local balance = if state ~= nil then state.balance else "—"
		info.Text = string.format("金幣 %s　　單抽 %d", tostring(balance), CarConfig.SinglePullPrice)
		local ids = if state ~= nil and type(state.discovered) == "table" then state.discovered else {}
		local parts = {}
		for _, modelId in ipairs(ids) do
			if type(modelId) == "string" then
				table.insert(parts, modelId)
			end
		end
		table.sort(parts)
		local signature = table.concat(parts, ",")
		discovered = parts
		if signature ~= discoveredSignature then
			discoveredSignature = signature
			if page == "catalog" then
				showCatalog()
			end
		end
		board.setLocked(locked)
		if state ~= nil and type(state.autoSell) == "table" then
			autoSellState = state.autoSell
		end
		autoButton.Text = if autoSellState.enabled == true then ("自動販賣：" .. modeLabel(autoSellState.maxQuality)) else "自動販賣：關"
		local signature = tostring(autoSellState.enabled) .. ":" .. tostring(autoSellState.maxQuality)
		if page == "sell" and not pendingConfirm and signature ~= sellSignature then
			showAutoSell()
		end
	end

	function board.onOpen()
		if not playing then
			dialogue.Text = GREETINGS[math.random(1, #GREETINGS)]
		end
	end

	function board.dismiss()
		if not playing then
			GachaSound.stopAll()
			return
		end
		settled = true
		local result = board._activeResult
		local done = activeDone
		activeDone = nil
		playing = false
		stopReel()
		GachaSound.stopAll()
		skipButton.Visible = false
		board._activeResult = nil
		if result ~= nil then
			showResult(result, result.qualityId == "Legendary")
		end
		if done ~= nil then
			done()
		end
	end

	pullButton.MouseButton1Click:Connect(function()
		if board.isBusy() then
			return
		end
		if board._onPull ~= nil then
			board._onPull()
		end
	end)
	skipButton.MouseButton1Click:Connect(function()
		board.skip()
	end)
	soundButton.MouseButton1Click:Connect(function()
		local nextMuted = not GachaSound.isMuted()
		GachaSound.setMuted(nextMuted)
		soundButton.Text = if nextMuted then "音效：關" else "音效：開"
	end)
	oddsButton.MouseButton1Click:Connect(showOdds)
	catalogButton.MouseButton1Click:Connect(showCatalog)
	autoButton.MouseButton1Click:Connect(showAutoSell)
	backButton.MouseButton1Click:Connect(function()
		setPage("main")
	end)

	function board.setPullHandler(handler)
		board._onPull = handler
	end

	function board.setAutoSellHandler(handler)
		board._onAutoSell = handler
	end

	board.update(nil)
	return board
end

return GachaBoard
