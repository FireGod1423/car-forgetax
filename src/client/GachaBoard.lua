-- R0 抽車介面。主畫面依玩家手繪圖排，動畫只使用伺服器已經發下來的結果。
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

local LEGENDARY_LINE = "Wait… how did this car end up in my crate?!"

local WIN_INDEX = 34
local CARD_COUNT = 42
local DURATION = 4.2
-- 與 PlaySessionService.PullInterval 相同。按鈕上的倒數用這個，不另外加長。
local PULL_COOLDOWN = 1.5
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

local METAL = Color3.fromRGB(46, 48, 54)
local METAL_DARK = Color3.fromRGB(24, 26, 30)
local PANEL = Color3.fromRGB(32, 34, 38)
local GOLD_TEXT = Color3.fromRGB(242, 186, 64)
local MUTED = Color3.fromRGB(176, 172, 164)
local BOTTOM_H = 188
local RESULT_H = 44

local function formatGold(value): string
	local amount = tonumber(value)
	if amount == nil then
		return "—"
	end
	local negative = amount < 0
	local digits = tostring(math.floor(math.abs(amount)))
	local parts = {}
	while #digits > 3 do
		table.insert(parts, 1, string.sub(digits, -3))
		digits = string.sub(digits, 1, -4)
	end
	table.insert(parts, 1, digits)
	local text = table.concat(parts, ",")
	return if negative then "-" .. text else text
end

local function percentText(weight: number, total: number): string
	local percent = if total > 0 then (weight / total) * 100 else 0
	return tostring(math.floor(percent + 0.5))
end

function GachaBoard.mount(panel: Frame)
	local board = {}
	local discovered = {}
	local discoveredSignature = ""
	local page = "main"
	local autoSellState = {
		enabled = false,
		qualities = {},
	}
	local pendingConfirm = false
	local playing = false
	local locked = false
	local skipEnabled = false
	local cooldownEndsAt = 0
	local revealStarted = false
	local settled = false
	local rolled = false
	local focusIndex = 1
	local cardW = 160
	local cardH = 120
	local step = 174
	local activeDone = nil
	local reelConnection: RBXScriptConnection? = nil

	panel.BackgroundColor3 = PANEL
	panel.BackgroundTransparency = 0
	stroke(panel, Color3.fromRGB(110, 74, 46), 1.5)

	local title = panel:FindFirstChild("Title")
	if title ~= nil and title:IsA("TextLabel") then
		title.TextSize = 18
		title.Size = UDim2.new(1, -210, 0, 32)
	end

	local catalogButton = button(panel, "COLLECTION", METAL)
	catalogButton.Name = "CatalogButton"
	catalogButton.AnchorPoint = Vector2.new(1, 0)
	catalogButton.Position = UDim2.new(1, -54, 0, 10)
	catalogButton.Size = UDim2.fromOffset(124, 28)
	catalogButton.TextSize = 13
	catalogButton.TextColor3 = PAPER
	catalogButton.ZIndex = 7

	local root = Instance.new("Frame")
	root.Name = "Lottery"
	root.BackgroundTransparency = 1
	root.Position = UDim2.fromOffset(14, 50)
	root.Size = UDim2.new(1, -28, 1, -62)
	root.ZIndex = 5
	root.Parent = panel

	local reelWrap = Instance.new("Frame")
	reelWrap.Name = "ReelWrap"
	reelWrap.BackgroundColor3 = Color3.fromRGB(38, 40, 46)
	reelWrap.BorderSizePixel = 0
	reelWrap.Position = UDim2.fromOffset(0, 0)
	reelWrap.Size = UDim2.new(1, 0, 1, -(BOTTOM_H + RESULT_H + 10))
	reelWrap.ZIndex = 5
	reelWrap.Parent = root
	corner(reelWrap, 10)
	stroke(reelWrap, Color3.fromRGB(92, 78, 66), 1)

	local badge = Instance.new("Frame")
	badge.Name = "RankBadge"
	badge.BackgroundColor3 = METAL_DARK
	badge.BorderSizePixel = 0
	badge.Position = UDim2.fromOffset(10, 8)
	badge.Size = UDim2.fromOffset(36, 20)
	badge.ZIndex = 6
	badge.Parent = reelWrap
	corner(badge, 4)
	stroke(badge, MUTED, 1)
	local badgeText = label(badge, 12)
	badgeText.Font = Enum.Font.GothamBold
	badgeText.Size = UDim2.fromScale(1, 1)
	badgeText.Text = "R0"
	badgeText.TextXAlignment = Enum.TextXAlignment.Center
	badgeText.ZIndex = 7

	local prizeTitle = label(reelWrap, 14)
	prizeTitle.Name = "PrizeRoll"
	prizeTitle.Font = Enum.Font.GothamBold
	prizeTitle.Position = UDim2.fromOffset(52, 6)
	prizeTitle.Size = UDim2.fromOffset(180, 24)
	prizeTitle.Text = "PRIZE ROLL"
	prizeTitle.ZIndex = 6

	local skipToggle = Instance.new("TextButton")
	skipToggle.Name = "SkipToggle"
	skipToggle.AnchorPoint = Vector2.new(1, 0)
	skipToggle.AutoButtonColor = true
	skipToggle.BackgroundColor3 = METAL
	skipToggle.BorderSizePixel = 0
	skipToggle.Position = UDim2.new(1, -88, 0, 6)
	skipToggle.Size = UDim2.fromOffset(78, 24)
	skipToggle.Text = ""
	skipToggle.ZIndex = 8
	skipToggle.Parent = reelWrap
	corner(skipToggle, 6)
	local skipStroke = stroke(skipToggle, MUTED, 1)
	local skipMark = Instance.new("Frame")
	skipMark.Active = false
	skipMark.Name = "Mark"
	skipMark.AnchorPoint = Vector2.new(0, 0.5)
	skipMark.BackgroundColor3 = ORANGE
	skipMark.BackgroundTransparency = 1
	skipMark.BorderSizePixel = 0
	skipMark.Position = UDim2.new(0, 6, 0.5, 0)
	skipMark.Size = UDim2.fromOffset(12, 12)
	skipMark.ZIndex = 9
	skipMark.Parent = skipToggle
	corner(skipMark, 2)
	stroke(skipMark, ORANGE, 1)
	local skipLabel = label(skipToggle, 12)
	skipLabel.Font = Enum.Font.GothamBold
	skipLabel.Position = UDim2.fromOffset(22, 0)
	skipLabel.Size = UDim2.new(1, -26, 1, 0)
	skipLabel.Text = "SKIP"
	skipLabel.TextXAlignment = Enum.TextXAlignment.Left
	skipLabel.ZIndex = 9

	local soundButton = button(reelWrap, "SOUND", METAL)
	soundButton.Name = "SoundToggle"
	soundButton.AnchorPoint = Vector2.new(1, 0)
	soundButton.Position = UDim2.new(1, -10, 0, 6)
	soundButton.Size = UDim2.fromOffset(70, 24)
	soundButton.TextSize = 12
	soundButton.TextColor3 = PAPER
	soundButton.ZIndex = 8

	local clip = Instance.new("Frame")
	clip.Name = "ReelClip"
	clip.BackgroundColor3 = METAL_DARK
	clip.BorderSizePixel = 0
	clip.ClipsDescendants = true
	clip.Position = UDim2.fromOffset(10, 34)
	clip.Size = UDim2.new(1, -20, 1, -56)
	clip.ZIndex = 5
	clip.Parent = reelWrap
	corner(clip, 8)

	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.Size = UDim2.fromOffset(CARD_COUNT * step, 140)
	strip.ZIndex = 5
	strip.Parent = clip

	local pointer = Instance.new("Frame")
	pointer.Name = "Pointer"
	pointer.AnchorPoint = Vector2.new(0.5, 1)
	pointer.BackgroundTransparency = 1
	pointer.Position = UDim2.new(0.5, 0, 1, -4)
	pointer.Size = UDim2.fromOffset(22, 14)
	pointer.ZIndex = 8
	pointer.Parent = reelWrap
	local function chevronArm(xScale: number, rotation: number)
		local arm = Instance.new("Frame")
		arm.AnchorPoint = Vector2.new(0.5, 0.5)
		arm.BackgroundColor3 = Color3.fromRGB(255, 206, 72)
		arm.BorderSizePixel = 0
		arm.Position = UDim2.fromScale(xScale, 0.55)
		arm.Size = UDim2.fromOffset(12, 3)
		arm.Rotation = rotation
		arm.ZIndex = 8
		arm.Parent = pointer
	end
	chevronArm(0.32, -40)
	chevronArm(0.68, 40)

	local resultBar = Instance.new("Frame")
	resultBar.Name = "Result"
	resultBar.BackgroundColor3 = METAL
	resultBar.BackgroundTransparency = 1
	resultBar.BorderSizePixel = 0
	resultBar.Position = UDim2.new(0, 0, 1, -(BOTTOM_H + RESULT_H))
	resultBar.Size = UDim2.new(1, 0, 0, RESULT_H)
	resultBar.Visible = false
	resultBar.ZIndex = 6
	resultBar.Parent = root
	corner(resultBar, 8)
	local resultStroke = stroke(resultBar, CLOUD, 1.5)
	local resultLabel = label(resultBar, 13)
	resultLabel.Name = "ResultText"
	resultLabel.Font = Enum.Font.GothamBold
	resultLabel.Size = UDim2.new(1, -16, 1, 0)
	resultLabel.Position = UDim2.fromOffset(8, 0)
	resultLabel.TextXAlignment = Enum.TextXAlignment.Center
	resultLabel.TextYAlignment = Enum.TextYAlignment.Center
	resultLabel.ZIndex = 7

	local columns = Instance.new("Frame")
	columns.Name = "Columns"
	columns.BackgroundTransparency = 1
	columns.Position = UDim2.new(0, 0, 1, -BOTTOM_H)
	columns.Size = UDim2.new(1, 0, 0, BOTTOM_H)
	columns.ZIndex = 5
	columns.Parent = root

	local function box(parent: Instance, name: string): Frame
		local item = Instance.new("Frame")
		item.Name = name
		item.BackgroundColor3 = METAL
		item.BorderSizePixel = 0
		item.ZIndex = 5
		item.Parent = parent
		corner(item, 8)
		stroke(item, Color3.fromRGB(78, 72, 66), 1)
		return item
	end

	local left = Instance.new("Frame")
	left.Name = "GoldColumn"
	left.BackgroundTransparency = 1
	left.Size = UDim2.new(0.32, -6, 1, 0)
	left.ZIndex = 5
	left.Parent = columns

	local goldBox = box(left, "GoldBox")
	goldBox.Size = UDim2.new(1, 0, 0.34, -4)
	local goldCaption = label(goldBox, 13)
	goldCaption.Font = Enum.Font.GothamBold
	goldCaption.Position = UDim2.fromOffset(8, 6)
	goldCaption.Size = UDim2.new(1, -16, 0, 16)
	goldCaption.Text = "YOUR GOLD"
	goldCaption.TextXAlignment = Enum.TextXAlignment.Center
	goldCaption.TextColor3 = MUTED
	goldCaption.ZIndex = 6
	local goldValue = label(goldBox, 26)
	goldValue.Name = "GoldValue"
	goldValue.Font = Enum.Font.GothamBold
	goldValue.Position = UDim2.fromOffset(8, 24)
	goldValue.Size = UDim2.new(1, -16, 1, -30)
	goldValue.Text = "—"
	goldValue.TextXAlignment = Enum.TextXAlignment.Center
	goldValue.TextColor3 = GOLD_TEXT
	goldValue.TextScaled = true
	goldValue.ZIndex = 6
	local goldLimit = Instance.new("UITextSizeConstraint")
	goldLimit.MaxTextSize = 32
	goldLimit.MinTextSize = 16
	goldLimit.Parent = goldValue

	local ratesBox = box(left, "DropRates")
	ratesBox.Position = UDim2.new(0, 0, 0.34, 4)
	ratesBox.Size = UDim2.new(1, 0, 0.66, -4)
	local ratesCaption = label(ratesBox, 13)
	ratesCaption.Font = Enum.Font.GothamBold
	ratesCaption.Position = UDim2.fromOffset(8, 6)
	ratesCaption.Size = UDim2.new(1, -16, 0, 16)
	ratesCaption.Text = "DROP RATES"
	ratesCaption.TextXAlignment = Enum.TextXAlignment.Center
	ratesCaption.TextColor3 = MUTED
	ratesCaption.ZIndex = 6
	local rateTotal = CarConfig.sumWeights()
	for index, quality in ipairs(CarConfig.getQualities()) do
		local row = label(ratesBox, 14)
		row.Name = "Rate" .. quality.Id
		row.Font = Enum.Font.GothamBold
		row.TextSize = 13
		row.Position = UDim2.new(0, 12, 0, 24 + (index - 1) * 16)
		row.Size = UDim2.new(1, -20, 0, 16)
		row.Text = string.format("%s  %s%%", string.upper(quality.DisplayName), percentText(quality.Weight, rateTotal))
		row.TextColor3 = CarVisualFactory.qualityColor(quality.Id)
		row.TextTruncate = Enum.TextTruncate.AtEnd
		row.ZIndex = 6
	end

	local center = Instance.new("Frame")
	center.Name = "RollColumn"
	center.BackgroundTransparency = 1
	center.Position = UDim2.new(0.32, 4, 0, 0)
	center.Size = UDim2.new(0.36, -8, 1, 0)
	center.ZIndex = 5
	center.Parent = columns

	local costBar = box(center, "CostBar")
	costBar.Size = UDim2.new(1, 0, 0, 40)
	local costLabel = label(costBar, 16)
	costLabel.Font = Enum.Font.GothamBold
	costLabel.Size = UDim2.fromScale(1, 1)
	costLabel.Text = string.format("COST: %d GOLD", CarConfig.SinglePullPrice)
	costLabel.TextXAlignment = Enum.TextXAlignment.Center
	costLabel.TextColor3 = Color3.fromRGB(214, 210, 204)
	costLabel.ZIndex = 6

	local pullButton = button(center, "ROLL ×1", ORANGE)
	pullButton.Name = "PullButton"
	pullButton.Position = UDim2.new(0, 0, 0, 48)
	pullButton.Size = UDim2.new(1, 0, 1, -48)
	pullButton.TextSize = 28
	pullButton.ZIndex = 6

	local right = Instance.new("Frame")
	right.Name = "SellColumn"
	right.BackgroundTransparency = 1
	right.Position = UDim2.new(0.68, 4, 0, 0)
	right.Size = UDim2.new(0.32, -4, 1, 0)
	right.ZIndex = 5
	right.Parent = columns

	local sellBox = box(right, "AutoSell")
	sellBox.Size = UDim2.fromScale(1, 1)
	local sellCaption = label(sellBox, 14)
	sellCaption.Font = Enum.Font.GothamBold
	sellCaption.Position = UDim2.fromOffset(10, 8)
	sellCaption.Size = UDim2.new(1, -70, 0, 22)
	sellCaption.Text = "AUTO SELL"
	sellCaption.ZIndex = 6
	local status = label(sellBox, 13)
	status.Name = "AutoSellStatus"
	status.AnchorPoint = Vector2.new(1, 0)
	status.BackgroundColor3 = Color3.fromRGB(70, 72, 78)
	status.Font = Enum.Font.GothamBold
	status.Position = UDim2.new(1, -8, 0, 8)
	status.Size = UDim2.fromOffset(52, 22)
	status.Text = "OFF"
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.BackgroundTransparency = 0
	status.BorderSizePixel = 0
	status.ZIndex = 7
	corner(status, 6)
	local hint = label(sellBox, 12)
	hint.Name = "SellHint"
	hint.Position = UDim2.fromOffset(10, 32)
	hint.Size = UDim2.new(1, -20, 0, 16)
	hint.Text = "Checked: sell. Empty: keep."
	hint.TextColor3 = MUTED
	hint.ZIndex = 6

	local marks = {}
	local choices = {}
	local confirm

	local function selectedMap(): { [string]: boolean }
		local set = {}
		local list = autoSellState.qualities
		if type(list) ~= "table" then
			return set
		end
		for _, qualityId in ipairs(list) do
			if type(qualityId) == "string" then
				set[qualityId] = true
			end
		end
		return set
	end

	local function selectedList(set: { [string]: boolean }): { string }
		local list = {}
		for _, qualityId in ipairs(AutoSellConfig.Order) do
			if set[qualityId] == true then
				table.insert(list, qualityId)
			end
		end
		return list
	end

	local function sendAutoSell(set: { [string]: boolean }, confirmLegendary: boolean)
		if board._onAutoSell ~= nil then
			board._onAutoSell(selectedList(set), confirmLegendary == true)
		end
	end

	for index, qualityId in ipairs(AutoSellConfig.Order) do
		local quality = CarConfig.getQuality(qualityId)
		local color = CarVisualFactory.qualityColor(qualityId)
		local row = Instance.new("TextButton")
		row.Name = "SellMode" .. qualityId
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.AutoButtonColor = false
		row.Text = ""
		row.Position = UDim2.new(0, 8, 0, 50 + (index - 1) * 26)
		row.Size = UDim2.new(1, -16, 0, 24)
		row.ZIndex = 6
		row.Parent = sellBox
		local mark = Instance.new("Frame")
		mark.Name = "Mark"
		mark.Active = false
		mark.AnchorPoint = Vector2.new(0, 0.5)
		mark.BackgroundColor3 = color
		mark.BackgroundTransparency = 1
		mark.BorderSizePixel = 0
		mark.Position = UDim2.new(0, 2, 0.5, 0)
		mark.Size = UDim2.fromOffset(14, 14)
		mark.ZIndex = 7
		mark.Parent = row
		corner(mark, 3)
		stroke(mark, color, 2)
		local name = label(row, 14)
		name.Font = Enum.Font.GothamBold
		name.Position = UDim2.fromOffset(24, 0)
		name.Size = UDim2.new(1, -78, 1, 0)
		name.Text = string.upper(if quality ~= nil then quality.DisplayName else qualityId)
		name.TextColor3 = color
		name.ZIndex = 7
		local choice = label(row, 12)
		choice.Name = "Choice"
		choice.AnchorPoint = Vector2.new(1, 0.5)
		choice.Font = Enum.Font.GothamBold
		choice.Position = UDim2.new(1, -2, 0.5, 0)
		choice.Size = UDim2.fromOffset(46, 18)
		choice.Text = "KEEP"
		choice.TextColor3 = MUTED
		choice.TextXAlignment = Enum.TextXAlignment.Right
		choice.ZIndex = 7
		marks[qualityId] = mark
		choices[qualityId] = choice
		row.MouseButton1Click:Connect(function()
			if playing or locked or pendingConfirm then
				return
			end
			local set = selectedMap()
			if qualityId == "Legendary" and set[qualityId] ~= true then
				pendingConfirm = true
				confirm.Visible = true
				return
			end
			if set[qualityId] == true then
				set[qualityId] = nil
			else
				set[qualityId] = true
			end
			sendAutoSell(set, false)
		end)
	end

	confirm = Instance.new("Frame")
	confirm.Name = "LegendaryConfirm"
	confirm.BackgroundColor3 = Color3.fromRGB(28, 26, 24)
	confirm.BorderSizePixel = 0
	confirm.Position = UDim2.fromOffset(6, 46)
	confirm.Size = UDim2.new(1, -12, 1, -52)
	confirm.Visible = false
	confirm.ZIndex = 9
	confirm.Parent = sellBox
	corner(confirm, 8)
	stroke(confirm, Color3.fromRGB(176, 98, 48), 1.5)
	local warning = label(confirm, 13)
	warning.Position = UDim2.fromOffset(8, 6)
	warning.Size = UDim2.new(1, -16, 1, -46)
	warning.TextYAlignment = Enum.TextYAlignment.Top
	warning.TextColor3 = GOLD_TEXT
	warning.ZIndex = 10
	local legendaryPrice = AutoSellConfig.price(0, "Legendary") or 0
	warning.Text = string.format(
		"Legendary pulls sell for %d gold and will not stay in the garage. Other checked tiers stay as they are.",
		legendaryPrice
	)
	local confirmButton = button(confirm, "CONFIRM", Color3.fromRGB(168, 72, 58))
	confirmButton.Position = UDim2.new(0, 8, 1, -36)
	confirmButton.Size = UDim2.new(0.5, -12, 0, 28)
	confirmButton.TextSize = 13
	confirmButton.TextColor3 = PAPER
	confirmButton.ZIndex = 10
	local cancelButton = button(confirm, "CANCEL", CLOUD)
	cancelButton.AnchorPoint = Vector2.new(1, 0)
	cancelButton.Position = UDim2.new(1, -8, 1, -36)
	cancelButton.Size = UDim2.new(0.5, -12, 0, 28)
	cancelButton.TextSize = 13
	cancelButton.ZIndex = 10

	local overlay = Instance.new("Frame")
	overlay.Name = "CollectionPage"
	overlay.BackgroundColor3 = PANEL
	overlay.BorderSizePixel = 0
	overlay.Position = UDim2.fromOffset(14, 50)
	overlay.Size = UDim2.new(1, -28, 1, -62)
	overlay.Visible = false
	overlay.ZIndex = 10
	overlay.Parent = panel
	corner(overlay, 10)

	local overlayTitle = label(overlay, 18)
	overlayTitle.Name = "OverlayTitle"
	overlayTitle.Font = Enum.Font.GothamBold
	overlayTitle.Position = UDim2.fromOffset(12, 8)
	overlayTitle.Size = UDim2.new(1, -120, 0, 28)
	overlayTitle.ZIndex = 11

	local backButton = button(overlay, "BACK", CLOUD)
	backButton.Name = "BackButton"
	backButton.AnchorPoint = Vector2.new(1, 0)
	backButton.Position = UDim2.new(1, -8, 0, 8)
	backButton.Size = UDim2.fromOffset(72, 28)
	backButton.TextSize = 14
	backButton.ZIndex = 11

	local overlayBody = Instance.new("ScrollingFrame")
	overlayBody.Name = "OverlayBody"
	overlayBody.BackgroundTransparency = 1
	overlayBody.BorderSizePixel = 0
	overlayBody.Position = UDim2.fromOffset(8, 44)
	overlayBody.Size = UDim2.new(1, -16, 1, -52)
	overlayBody.ScrollBarThickness = 6
	overlayBody.AutomaticCanvasSize = Enum.AutomaticSize.Y
	overlayBody.CanvasSize = UDim2.new()
	overlayBody.ZIndex = 11
	overlayBody.Parent = overlay
	local overlayLayout = Instance.new("UIListLayout")
	overlayLayout.Padding = UDim.new(0, 6)
	overlayLayout.SortOrder = Enum.SortOrder.LayoutOrder
	overlayLayout.Parent = overlayBody

	local function setPage(nextPage: string)
		page = nextPage
		local catalogOpen = nextPage == "catalog"
		root.Visible = not catalogOpen
		overlay.Visible = catalogOpen
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
		overlayTitle.Text = string.format("COLLECTION    %d / %d", foundCount, #cars)
		local note = label(overlayBody, 14)
		note.Size = UDim2.new(1, -8, 0, 40)
		note.Text = "The catalog is a discovery log, not your current garage. A scrapped car stays discovered. This log vanishes when the server closes."
		note.TextYAlignment = Enum.TextYAlignment.Top
		note.ZIndex = 12
		for _, car in ipairs(cars) do
			local knownCar = known[car.ModelId] == true
			local quality = CarConfig.getQuality(car.Quality)
			local row = Instance.new("Frame")
			row.Name = car.ModelId
			row.BackgroundColor3 = ROW
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, -8, 0, 78)
			row.ZIndex = 11
			row.Parent = overlayBody
			corner(row, 6)
			stroke(row, if knownCar then CarVisualFactory.qualityColor(car.Quality) else Color3.fromRGB(40, 40, 44), 2)
			local preview = Instance.new("ViewportFrame")
			preview.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
			preview.BorderSizePixel = 0
			preview.Position = UDim2.fromOffset(6, 6)
			preview.Size = UDim2.fromOffset(92, 66)
			preview.ZIndex = 12
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
			name.ZIndex = 12
			local detail = label(row, 14)
			detail.Position = UDim2.fromOffset(108, 32)
			detail.Size = UDim2.new(1, -116, 0, 38)
			detail.TextYAlignment = Enum.TextYAlignment.Top
			local qualityName = if quality ~= nil then quality.DisplayName else car.Quality
			if knownCar then
				local power = CarConfig.calculatePower(0, car.Quality, 0)
				detail.Text = string.format("%s  Base power %s\nDiscovered", qualityName, tostring(power))
			else
				detail.Text = string.format("%s\nLocked", qualityName)
			end
			detail.ZIndex = 12
		end
		setPage("catalog")
	end

	local function paintAutoSell()
		local selected = selectedMap()
		local any = false
		for _, qualityId in ipairs(AutoSellConfig.Order) do
			local mark = marks[qualityId]
			local choice = choices[qualityId]
			local on = selected[qualityId] == true
			if on then
				any = true
			end
			if mark ~= nil then
				mark.BackgroundTransparency = if on then 0 else 1
			end
			if choice ~= nil then
				choice.Text = if on then "SELL" else "KEEP"
				choice.TextColor3 = if on then Color3.fromRGB(242, 186, 64) else MUTED
			end
		end
		status.Text = if any then "ON" else "OFF"
		status.BackgroundColor3 = if any then ORANGE else Color3.fromRGB(70, 72, 78)
		status.TextColor3 = if any then Color3.fromRGB(24, 22, 18) else PAPER
		confirm.Visible = pendingConfirm
	end

	local function localSize(gui: GuiObject): Vector2
		local scale = 1
		local current: Instance? = gui
		while current ~= nil do
			local fitted = current:FindFirstChildOfClass("UIScale")
			if fitted ~= nil and fitted:IsA("UIScale") then
				scale *= (fitted :: UIScale).Scale
			end
			current = current.Parent
		end
		if scale < 0.05 then
			scale = 1
		end
		return gui.AbsoluteSize / scale
	end

	local function captureMetrics()
		local clipSize = localSize(clip)
		local clipW = clipSize.X
		local clipH = clipSize.Y
		if clipW < 80 then
			clipW = 640
		end
		if clipH < 40 then
			clipH = 150
		end
		cardW = math.clamp(math.floor(clipW / 4.35), 108, 240)
		cardH = math.clamp(math.min(clipH - 8, math.floor(cardW * 0.9)), 84, 210)
		step = cardW + 14
	end

	local function offsetFor(index: number, width: number): number
		return width * 0.5 - ((index - 1) * step + cardW * 0.5)
	end

	local function placeStrip()
		local width = math.max(localSize(clip).X, 200)
		strip.Position = UDim2.fromOffset(offsetFor(focusIndex, width), 0)
	end

	local function clearStrip()
		for _, child in ipairs(strip:GetChildren()) do
			child:Destroy()
		end
	end

	local function makeCard(card, index: number)
		local quality = CarConfig.getQuality(card.qualityId)
		local qualityName = if quality ~= nil then quality.DisplayName else tostring(card.qualityId)
		local color = CarVisualFactory.qualityColor(card.qualityId)
		local clipH = math.max(localSize(clip).Y, cardH)
		local y = math.max(0, math.floor((clipH - cardH) * 0.5))
		local item = Instance.new("Frame")
		item.Name = "Card" .. index
		item.BackgroundColor3 = Color3.fromRGB(30, 32, 38)
		item.BorderSizePixel = 0
		item.Position = UDim2.fromOffset((index - 1) * step, y)
		item.Size = UDim2.fromOffset(cardW, cardH)
		item.ZIndex = 5
		item.Parent = strip
		corner(item, 8)
		stroke(item, color, 2)
		local view = Instance.new("ViewportFrame")
		view.Name = "Preview"
		view.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
		view.BorderSizePixel = 0
		view.Position = UDim2.fromOffset(8, 6)
		view.Size = UDim2.new(1, -16, 1, -34)
		view.Ambient = Color3.fromRGB(180, 180, 180)
		view.LightColor = Color3.new(1, 1, 1)
		view.LightDirection = Vector3.new(-1, -1, -0.4)
		view.ZIndex = 6
		view.Parent = item
		corner(view, 6)
		local world = Instance.new("WorldModel")
		world.Parent = view
		local camera = Instance.new("Camera")
		camera.Parent = view
		view.CurrentCamera = camera
		presentCar(world, camera, card, false)
		local name = label(item, 13)
		name.Font = Enum.Font.GothamBold
		name.Position = UDim2.new(0, 6, 1, -26)
		name.Size = UDim2.new(1, -12, 0, 20)
		name.Text = string.upper(qualityName)
		name.TextColor3 = color
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.ZIndex = 6
		if index == WIN_INDEX then
			item:SetAttribute("WinningCard", true)
		end
		return item
	end

	local function layoutStrip(cards, focus: number)
		captureMetrics()
		clearStrip()
		focusIndex = focus
		for index, card in ipairs(cards) do
			makeCard(card, index)
		end
		strip.Size = UDim2.fromOffset(math.max(#cards, 1) * step, math.max(cardH + 8, localSize(clip).Y))
		placeStrip()
	end

	local function showIdle()
		if playing then
			return
		end
		local cards = {}
		for _, quality in ipairs(CarConfig.getQualities()) do
			local eligible = CarCatalog.getEligible(quality.Id, 0)
			if #eligible > 0 then
				table.insert(cards, entryFromCatalog(eligible[1]))
			end
		end
		if #cards == 0 then
			return
		end
		layoutStrip(cards, math.ceil(#cards / 2))
	end

	local function showResult(result, legendary: boolean)
		local quality = CarConfig.getQuality(result.qualityId)
		local qualityName = if quality ~= nil then quality.DisplayName else tostring(result.qualityId)
		local status = if result.sold == true
			then string.format("Sold automatically for %s gold", tostring(result.sellPrice))
			else "Added to garage"
		local headline = string.format("%s  ·  %s", string.upper(qualityName), tostring(result.displayName))
		if legendary then
			resultLabel.Text = string.format("%s\n%s  ·  %s", headline, LEGENDARY_LINE, status)
		else
			resultLabel.Text = string.format("%s\n%s", headline, status)
		end
		local color = CarVisualFactory.qualityColor(result.qualityId)
		resultLabel.TextColor3 = color
		resultStroke.Color = color
		resultBar.BackgroundTransparency = 0
		resultBar.Visible = true
	end

	local function stopReel()
		if reelConnection ~= nil then
			reelConnection:Disconnect()
			reelConnection = nil
		end
	end

	local function finishPlayback(result, playSound: boolean, focus: number?)
		if settled then
			return
		end
		settled = true
		stopReel()
		playing = false
		focusIndex = focus or WIN_INDEX
		placeStrip()
		local legendary = result.qualityId == "Legendary"
		showResult(result, legendary)
		if playSound and not revealStarted then
			revealStarted = true
			GachaSound.stopAll()
			GachaSound.playLock()
			GachaSound.playReveal(result.qualityId)
		end
		local done = activeDone
		activeDone = nil
		board._activeResult = nil
		board.setLocked(locked)
		if done ~= nil then
			done()
		end
	end

	function board.play(result, onDone)
		if type(result) ~= "table" or type(result.modelId) ~= "string" or type(result.qualityId) ~= "string" then
			if onDone ~= nil then
				onDone()
			end
			return
		end
		stopReel()
		GachaSound.stopAll()
		playing = true
		rolled = true
		revealStarted = false
		settled = false
		activeDone = onDone
		board._activeResult = result
		resultBar.Visible = false
		pendingConfirm = false
		confirm.Visible = false
		setPage("main")
		if skipEnabled then
			layoutStrip({
				{
					modelId = result.modelId,
					displayName = result.displayName,
					qualityId = result.qualityId,
				},
			}, 1)
			finishPlayback(result, true, 1)
			return
		end
		local cards = buildStrip(result, Random.new())
		layoutStrip(cards, WIN_INDEX)
		local width = math.max(localSize(clip).X, 200)
		local startOffset = offsetFor(WIN_INDEX - 26, width)
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
			local widthNow = math.max(localSize(clip).X, 200)
			local startNow = offsetFor(WIN_INDEX - 26, widthNow)
			local endNow = offsetFor(WIN_INDEX, widthNow)
			local offset = startNow + (endNow - startNow) * eased
			local shake = 0
			if alpha > 0.94 then
				shake = math.sin(elapsed * 48) * (1 - alpha) * 18
			end
			strip.Position = UDim2.fromOffset(offset + shake, 0)
			local pointerX = widthNow * 0.5 - offset
			local index = math.floor(pointerX / step) + 1
			if lastIndex == nil then
				lastIndex = index
			elseif index ~= lastIndex then
				lastIndex = index
				GachaSound.playTick()
			end
			if alpha >= 1 then
				finishPlayback(result, true)
			end
		end)
		board.setLocked(locked)
	end

	function board.skip()
		if not playing or settled then
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
		board._activeResult = nil
		if result ~= nil then
			focusIndex = WIN_INDEX
			placeStrip()
			showResult(result, result.qualityId == "Legendary")
		end
		if shouldSound and result ~= nil then
			revealStarted = true
			GachaSound.playLock()
			GachaSound.playReveal(result.qualityId)
		else
			revealStarted = true
		end
		board.setLocked(locked)
		if done ~= nil then
			done()
		end
	end

	local function cooldownLeft(): number
		return math.max(0, cooldownEndsAt - os.clock())
	end

	local function refreshPullButton()
		local left = cooldownLeft()
		local cooling = left > 0.05
		local active = not locked and not playing and not cooling
		pullButton.Active = active
		pullButton.AutoButtonColor = active
		pullButton.BackgroundTransparency = if active then 0 else 0.35
		pullButton.Text = if cooling then string.format("%.1fs", left) else "ROLL ×1"
	end

	function board.isBusy(): boolean
		return playing or locked or cooldownLeft() > 0.05
	end

	function board.beginPullCooldown()
		cooldownEndsAt = os.clock() + PULL_COOLDOWN
		refreshPullButton()
	end

	function board.setLocked(nextLocked: boolean)
		locked = nextLocked == true
		refreshPullButton()
	end

	function board.update(state)
		local balance = if state ~= nil then state.balance else nil
		goldValue.Text = if balance == nil then "—" else formatGold(balance)
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
		if state ~= nil and type(state.autoSell) == "table" then
			autoSellState = state.autoSell
		end
		if pendingConfirm and selectedMap().Legendary == true then
			pendingConfirm = false
		end
		paintAutoSell()
		board.setLocked(locked)
	end

	function board.onOpen()
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
		board._activeResult = nil
		if result ~= nil then
			focusIndex = WIN_INDEX
			placeStrip()
			showResult(result, result.qualityId == "Legendary")
		end
		board.setLocked(locked)
		if done ~= nil then
			done()
		end
	end

	function board.setPullHandler(handler)
		board._onPull = handler
	end

	function board.setAutoSellHandler(handler)
		board._onAutoSell = handler
	end

	pullButton.MouseButton1Click:Connect(function()
		if board.isBusy() then
			return
		end
		if board._onPull ~= nil then
			board._onPull()
		end
	end)
	local function paintSkip()
		skipMark.BackgroundTransparency = if skipEnabled then 0 else 1
		skipStroke.Color = if skipEnabled then ORANGE else MUTED
		skipToggle.BackgroundColor3 = if skipEnabled then Color3.fromRGB(72, 48, 28) else METAL
	end
	paintSkip()
	skipToggle.MouseButton1Click:Connect(function()
		skipEnabled = not skipEnabled
		paintSkip()
		if skipEnabled then
			board.skip()
		end
	end)
	RunService.Heartbeat:Connect(function()
		if cooldownEndsAt == 0 then
			return
		end
		if os.clock() >= cooldownEndsAt then
			cooldownEndsAt = 0
		end
		refreshPullButton()
	end)
	soundButton.MouseButton1Click:Connect(function()
		local nextMuted = not GachaSound.isMuted()
		GachaSound.setMuted(nextMuted)
		soundButton.Text = if nextMuted then "MUTED" else "SOUND"
	end)
	catalogButton.MouseButton1Click:Connect(function()
		if playing then
			return
		end
		if page == "catalog" then
			setPage("main")
		else
			showCatalog()
		end
	end)
	backButton.MouseButton1Click:Connect(function()
		setPage("main")
	end)
	confirmButton.MouseButton1Click:Connect(function()
		local set = selectedMap()
		set.Legendary = true
		pendingConfirm = false
		confirm.Visible = false
		sendAutoSell(set, true)
	end)
	cancelButton.MouseButton1Click:Connect(function()
		pendingConfirm = false
		confirm.Visible = false
	end)

	clip:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if playing or rolled then
			if not playing then
				placeStrip()
			end
			return
		end
		showIdle()
	end)

	board.update(nil)
	task.defer(showIdle)
	return board
end

return GachaBoard

