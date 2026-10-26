-- 概念場景只建立一次。玩家加入時不重建，避免重複物件與競速被清掉。
local function importShared(moduleName: string)
	if game ~= nil then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild(moduleName))
	end
	return require("../shared/" .. moduleName)
end

local RaceConfig = importShared("RaceConfig")
local CarCatalog = importShared("CarCatalog")
local CarVisualFactory = importShared("CarVisualFactory")

local PlaygroundBuilder = {}

PlaygroundBuilder.FolderName = "CarForgeTaxPlayground"
-- 場景結構有變時提高版本，已完成的舊場景才會重建。
PlaygroundBuilder.Version = 10

local ORANGE = Color3.fromRGB(255, 122, 28)
local ORANGE_DARK = Color3.fromRGB(196, 78, 16)
local TABLE = Color3.fromRGB(186, 214, 232)
local INK = Color3.fromRGB(32, 38, 48)
local CREAM = Color3.fromRGB(255, 246, 230)

local function part(props)
	local item = Instance.new(props.className or "Part")
	item.Name = props.name or "Part"
	item.Anchored = true
	item.Size = props.size
	item.CFrame = props.cframe
	item.Color = props.color or CREAM
	item.Material = props.material or Enum.Material.SmoothPlastic
	item.CanCollide = props.collide ~= false
	item.CanTouch = props.touch == true
	item.CanQuery = props.query ~= false
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = props.parent
	return item
end

local function caption(host: BasePart, text: string, offsetY: number?)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Caption"
	billboard.Size = UDim2.fromOffset(220, 52)
	billboard.StudsOffset = Vector3.new(0, offsetY or 3.4, 0)
	billboard.MaxDistance = 120
	billboard.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.TextWrapped = true
	label.Parent = billboard
	billboard.Parent = host
end

local function prompt(host: BasePart, actionText: string, objectText: string)
	local interaction = Instance.new("ProximityPrompt")
	interaction.ActionText = actionText
	interaction.ObjectText = objectText
	interaction.KeyboardKeyCode = Enum.KeyCode.E
	interaction.HoldDuration = 0
	interaction.MaxActivationDistance = 12
	interaction.RequiresLineOfSight = false
	interaction.Parent = host
	return interaction
end

local ROAD = Color3.fromRGB(255, 132, 28)
local SHOULDER = Color3.fromRGB(232, 108, 20)
local RAIL = Color3.fromRGB(196, 72, 12)
local STRIPE = Color3.fromRGB(255, 248, 236)

-- 中心是槽底。左右是水平墊高的護邊，外緣同時高於中心，不會把整塊路面往一側翻。
local CENTER_WIDTH = 5.2
local CURB_WIDTH = 0.62
local DECK_THICK = 0.28
local CURB_HEIGHT = 0.34

local function roadPiece(parent: Instance, name: string, pose, length: number, width: number, height: number, yOffset: number, lateral: number, color: Color3, collide: boolean)
	local piece = part({
		name = name,
		size = Vector3.new(width, height, math.max(0.4, length)),
		cframe = CarVisualFactory.poseCFrame(pose, yOffset, lateral),
		color = color,
		parent = parent,
		collide = collide,
	})
	piece:SetAttribute("TrackSegment", pose.segment)
	return piece
end

local function laySpan(parent: Instance, fromDistance: number, toDistance: number, step: number, name: string)
	local cursor = fromDistance
	local index = 1
	while cursor < toDistance - 0.04 do
		local nextDistance = math.min(toDistance, cursor + step)
		local pose = RaceConfig.sample((cursor + nextDistance) * 0.5)
		local length = (nextDistance - cursor) + 0.42
		roadPiece(
			parent,
			string.format("%sDeck%d", name, index),
			pose,
			length,
			CENTER_WIDTH,
			DECK_THICK,
			-DECK_THICK * 0.5,
			0,
			ROAD,
			true
		)
		for _, side in ipairs({ -1, 1 }) do
			local sideName = if side < 0 then "L" else "R"
			roadPiece(
				parent,
				string.format("%sShoulder%s%d", name, sideName, index),
				pose,
				length,
				CURB_WIDTH,
				CURB_HEIGHT,
				CURB_HEIGHT * 0.5 - 0.02,
				side * (CENTER_WIDTH * 0.5 + CURB_WIDTH * 0.5 - 0.08),
				if side < 0 then SHOULDER else RAIL,
				true
			)
		end
		if name == "Start" or name == "Sprint" or name == "Back" then
			roadPiece(parent, string.format("%sStripe%d", name, index), pose, length * 0.9, 0.14, 0.04, 0.03, 0, STRIPE, false)
		end
		cursor = nextDistance
		index += 1
	end
end

local function kiosk(parent: Instance, name: string, position: Vector3, color: Color3, title: string, actionText: string)
	local booth = part({
		name = name,
		size = Vector3.new(6, 5, 4),
		cframe = CFrame.new(position),
		color = color,
		parent = parent,
	})
	part({
		name = name .. "Screen",
		size = Vector3.new(4.2, 2.2, 0.2),
		cframe = CFrame.new(position + Vector3.new(0, 0.6, -2.05)),
		color = INK,
		material = Enum.Material.SmoothPlastic,
		parent = parent,
		collide = false,
	})
	caption(booth, title, 3.6)
	prompt(booth, actionText, title)
	booth:SetAttribute("Station", name)
	return booth
end

local function buildTrack(parent: Instance)
	local track = Instance.new("Folder")
	track.Name = "Track"
	track.Parent = parent

	local markers = RaceConfig.markers()
	local arc = markers.curveEnd - markers.startEnd
	laySpan(track, 0, markers.startEnd, markers.startEnd, "Start")
	laySpan(track, markers.startEnd, markers.curveEnd, arc / 24, "Sweeper")
	laySpan(track, markers.curveEnd, markers.backEnd, markers.backEnd - markers.curveEnd, "Back")
	laySpan(track, markers.backEnd, markers.returnEnd, arc / 24, "Return")
	laySpan(track, markers.returnEnd, markers.lapEnd, markers.lapEnd - markers.returnEnd, "Sprint")

	local line = RaceConfig.sample(0)
	part({
		name = "RaceStart",
		size = Vector3.new(CENTER_WIDTH * 0.72, 0.05, 0.28),
		cframe = CarVisualFactory.poseCFrame(line, 0.04, 0),
		color = Color3.fromRGB(96, 230, 150),
		material = Enum.Material.Neon,
		parent = track,
		collide = false,
	})

	local postEdge = CENTER_WIDTH * 0.5 + 0.2
	local postHeight = 1.32
	part({
		name = "FinishPostL",
		size = Vector3.new(0.2, postHeight, 0.2),
		cframe = CarVisualFactory.poseCFrame(line, postHeight * 0.5, -postEdge),
		color = ORANGE_DARK,
		parent = track,
		collide = false,
	})
	part({
		name = "FinishPostR",
		size = Vector3.new(0.2, postHeight, 0.2),
		cframe = CarVisualFactory.poseCFrame(line, postHeight * 0.5, postEdge),
		color = ORANGE_DARK,
		parent = track,
		collide = false,
	})
	part({
		name = "RaceFinish",
		size = Vector3.new(CENTER_WIDTH + 0.55, 0.14, 0.18),
		cframe = CarVisualFactory.poseCFrame(line, 1.26, 0),
		color = Color3.fromRGB(255, 226, 90),
		material = Enum.Material.Neon,
		parent = track,
		collide = false,
	})

	for index = 1, 3 do
		local pose = RaceConfig.sample(markers.lapEnd - index * 2.2)
		part({
			name = "Chevron" .. index,
			size = Vector3.new(1.35, 0.04, 0.42),
			cframe = CarVisualFactory.poseCFrame(pose, 0.05, 0),
			color = Color3.fromRGB(255, 236, 170),
			material = Enum.Material.Neon,
			parent = track,
			collide = false,
		})
	end

	for index, distance in ipairs({ 4, markers.backEnd * 0.5, markers.returnEnd + 4 }) do
		local pose = RaceConfig.sample(distance)
		part({
			name = "Support" .. index,
			size = Vector3.new(0.7, 1.15, 0.7),
			cframe = CFrame.new(pose.x, 1.35, pose.z),
			color = ORANGE_DARK,
			parent = track,
		})
	end
end

local function priceSign(host: BasePart, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Caption"
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 70
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.LightInfluence = 0
	gui.Parent = host
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 244, 220)
	label.TextScaled = true
	label.Parent = gui
end

local function buildDealer(parent: Instance)
	local origin = CFrame.new(-28, 0.8, -18)
	local dealer = Instance.new("Model")
	dealer.Name = "R0Dealer"
	dealer.Parent = parent

	local wood = Color3.fromRGB(126, 84, 46)
	local woodDark = Color3.fromRGB(84, 54, 32)
	local coat = Color3.fromRGB(98, 62, 36)
	local skin = Color3.fromRGB(214, 176, 138)
	local cloth = Color3.fromRGB(72, 64, 52)
	-- 原模型約 2.7 studs。2 倍後帽頂約 5.5，接近一般玩家身高。
	local SCALE = 2
	-- 鞋子底部原本離地 0.04，放大後下移，讓鞋底貼在地板。
	local FOOT = -0.08

	local function place(localCf: CFrame, scale: number, yShift: number): CFrame
		return localCf.Rotation + (localCf.Position * scale + Vector3.new(0, yShift, 0))
	end

	local function add(model: Model, name: string, size: Vector3, localCf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?, scale: number, yShift: number)
		return part({
			name = name,
			size = size * scale,
			cframe = origin * place(localCf, scale, yShift),
			color = color,
			material = material,
			parent = model,
			collide = collide == true,
		})
	end

	add(dealer, "StallTop", Vector3.new(4.4, 0.22, 2.3), CFrame.new(0, 1.2, 2.5), wood, Enum.Material.Wood, true, SCALE, 0)
	add(dealer, "StallLegL", Vector3.new(0.22, 1.2, 0.22), CFrame.new(-1.9, 0.6, 1.6), woodDark, Enum.Material.Wood, true, SCALE, 0)
	add(dealer, "StallLegR", Vector3.new(0.22, 1.2, 0.22), CFrame.new(1.9, 0.6, 1.6), woodDark, Enum.Material.Wood, true, SCALE, 0)
	add(dealer, "StallLegBL", Vector3.new(0.22, 1.2, 0.22), CFrame.new(-1.9, 0.6, 3.4), woodDark, Enum.Material.Wood, true, SCALE, 0)
	add(dealer, "StallLegBR", Vector3.new(0.22, 1.2, 0.22), CFrame.new(1.9, 0.6, 3.4), woodDark, Enum.Material.Wood, true, SCALE, 0)
	add(dealer, "Canopy", Vector3.new(4.8, 0.12, 2.6), CFrame.new(0, 3.15, 2.5), Color3.fromRGB(168, 92, 48), Enum.Material.Fabric, false, SCALE, 0)
	add(dealer, "CanopyPostL", Vector3.new(0.16, 1.9, 0.16), CFrame.new(-2.15, 2.15, 1.4), woodDark, Enum.Material.Wood, false, SCALE, 0)
	add(dealer, "CanopyPostR", Vector3.new(0.16, 1.9, 0.16), CFrame.new(2.15, 2.15, 1.4), woodDark, Enum.Material.Wood, false, SCALE, 0)
	add(dealer, "CrateA", Vector3.new(1.15, 0.9, 1.05), CFrame.new(-2.7, 0.45, 1.1), wood, Enum.Material.Wood, true, SCALE, 0)
	add(dealer, "CrateB", Vector3.new(0.85, 0.7, 0.8), CFrame.new(-2.5, 1.2, 1.35) * CFrame.Angles(0, 0.4, 0), woodDark, Enum.Material.Wood, true, SCALE, 0)
	local tire = add(dealer, "OldTire", Vector3.new(0.28, 1.15, 1.15), CFrame.new(2.7, 0.575, 1.5), Color3.fromRGB(42, 42, 46), Enum.Material.SmoothPlastic, true, SCALE, 0)
	tire.Shape = Enum.PartType.Cylinder
	local sign = add(dealer, "PriceSign", Vector3.new(1.5, 0.7, 0.08), CFrame.new(0, 1.7, 1.28) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(48, 36, 28), Enum.Material.Wood, false, SCALE, 0)
	priceSign(sign, "500\n金幣一台")
	local nameBoard = add(dealer, "NameSign", Vector3.new(1.8, 0.46, 0.08), CFrame.new(0, 2.55, 1.28) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(58, 42, 30), Enum.Material.Wood, false, SCALE, 0)
	priceSign(nameBoard, "老破的攤")

	local used = CarVisualFactory.build({
		qualityId = "Common",
		upgradeLevel = 0,
		displayName = "二手玩具車",
	})
	used.Name = "UsedCar"
	for _, descendant in ipairs(used:GetDescendants()) do
		if descendant:IsA("BillboardGui") or descendant:IsA("ParticleEmitter") or descendant:IsA("PointLight") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") and string.sub(descendant.Name, 1, 5) ~= "Wheel" then
			descendant.Color = descendant.Color:Lerp(Color3.fromRGB(112, 74, 40), 0.55)
		end
	end
	used.Parent = dealer
	used:PivotTo(origin * CFrame.new(0.3, 3.16, 5.1))

	local npc = Instance.new("Model")
	npc.Name = "LaoPo"
	npc.Parent = dealer
	local torso = add(npc, "Torso", Vector3.new(0.95, 1.05, 0.42), CFrame.new(0, 1.48, 0), coat, Enum.Material.SmoothPlastic, false, SCALE, FOOT)
	npc.PrimaryPart = torso
	add(npc, "PatchGreen", Vector3.new(0.22, 0.18, 0.06), CFrame.new(-0.22, 1.62, 0.22), Color3.fromRGB(58, 122, 74), nil, false, SCALE, FOOT)
	add(npc, "PatchBlue", Vector3.new(0.16, 0.2, 0.06), CFrame.new(0.24, 1.28, 0.22), Color3.fromRGB(52, 86, 150), nil, false, SCALE, FOOT)
	add(npc, "PatchOrange", Vector3.new(0.18, 0.14, 0.06), CFrame.new(0.08, 1.72, 0.22), Color3.fromRGB(186, 102, 42), nil, false, SCALE, FOOT)
	add(npc, "ArmL", Vector3.new(0.22, 0.82, 0.22), CFrame.new(-0.62, 1.38, 0), cloth, nil, false, SCALE, FOOT)
	add(npc, "ArmR", Vector3.new(0.22, 0.82, 0.22), CFrame.new(0.62, 1.38, 0), cloth, nil, false, SCALE, FOOT)
	add(npc, "HandL", Vector3.new(0.2, 0.2, 0.2), CFrame.new(-0.62, 0.9, 0), skin, nil, false, SCALE, FOOT)
	add(npc, "HandR", Vector3.new(0.2, 0.2, 0.2), CFrame.new(0.62, 0.9, 0), skin, nil, false, SCALE, FOOT)
	add(npc, "LegL", Vector3.new(0.24, 0.78, 0.24), CFrame.new(-0.2, 0.58, 0), cloth, nil, false, SCALE, FOOT)
	add(npc, "LegR", Vector3.new(0.24, 0.78, 0.24), CFrame.new(0.2, 0.58, 0), Color3.fromRGB(64, 56, 46), nil, false, SCALE, FOOT)
	add(npc, "ShoeL", Vector3.new(0.26, 0.16, 0.38), CFrame.new(-0.2, 0.12, -0.04), Color3.fromRGB(48, 36, 28), nil, false, SCALE, FOOT)
	add(npc, "ShoeR", Vector3.new(0.26, 0.16, 0.38), CFrame.new(0.2, 0.12, -0.04), Color3.fromRGB(36, 32, 28), nil, false, SCALE, FOOT)
	local head = add(npc, "Head", Vector3.new(0.62, 0.62, 0.62), CFrame.new(0, 2.28, 0), skin, nil, false, SCALE, FOOT)
	add(npc, "EyeL", Vector3.new(0.08, 0.08, 0.04), CFrame.new(-0.14, 2.32, 0.32), Color3.fromRGB(36, 32, 30), nil, false, SCALE, FOOT)
	add(npc, "EyeR", Vector3.new(0.08, 0.08, 0.04), CFrame.new(0.14, 2.32, 0.32), Color3.fromRGB(36, 32, 30), nil, false, SCALE, FOOT)
	add(npc, "Mouth", Vector3.new(0.16, 0.04, 0.04), CFrame.new(0, 2.12, 0.32), Color3.fromRGB(120, 72, 64), nil, false, SCALE, FOOT)
	add(npc, "Beard", Vector3.new(0.28, 0.16, 0.08), CFrame.new(0, 2.02, 0.3), Color3.fromRGB(72, 56, 40), nil, false, SCALE, FOOT)
	add(npc, "Hat", Vector3.new(0.68, 0.22, 0.68), CFrame.new(0, 2.66, 0), Color3.fromRGB(58, 44, 32), nil, false, SCALE, FOOT)
	add(npc, "HatBrim", Vector3.new(0.92, 0.08, 0.92), CFrame.new(0, 2.54, -0.04), Color3.fromRGB(48, 36, 28), nil, false, SCALE, FOOT)
	add(npc, "ToolBag", Vector3.new(0.36, 0.32, 0.18), CFrame.new(0.58, 1.12, 0.02), Color3.fromRGB(86, 58, 34), Enum.Material.Fabric, false, SCALE, FOOT)
	head:SetAttribute("Station", "R0Dealer")
	local interaction = prompt(head, "看看攤位", "老破")
	interaction.MaxActivationDistance = 14
	interaction.UIOffset = Vector2.new(0, -20)
	local pivot = npc:GetPivot()
	local _, yaw = pivot:ToOrientation()
	npc:SetAttribute("RestX", pivot.Position.X)
	npc:SetAttribute("RestY", pivot.Position.Y)
	npc:SetAttribute("RestZ", pivot.Position.Z)
	npc:SetAttribute("RestYaw", yaw)
	return dealer
end

function PlaygroundBuilder.stepDealer(folder: Instance?, time: number)
	if typeof(folder) ~= "Instance" or type(time) ~= "number" then
		return
	end
	local npc = folder:FindFirstChild("LaoPo", true)
	if npc == nil or not npc:IsA("Model") then
		return
	end
	local x = npc:GetAttribute("RestX")
	local y = npc:GetAttribute("RestY")
	local z = npc:GetAttribute("RestZ")
	local yaw = npc:GetAttribute("RestYaw")
	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" or type(yaw) ~= "number" then
		return
	end
	local sway = math.sin(time * 1.15) * 0.07
	local bob = math.abs(math.sin(time * 1.15)) * 0.035
	npc:PivotTo(CFrame.new(x, y + bob, z) * CFrame.Angles(0, yaw + sway, 0))
end

local function buildShowroom(parent: Instance)
	local podium = part({
		name = "DisplayPodium",
		size = Vector3.new(28, 1, 8),
		cframe = CFrame.new(-50, 1.3, 0),
		color = CREAM,
		parent = parent,
	})
	caption(podium, "玩具車展示台", 5)
	local index = 0
	for _, car in ipairs(CarCatalog.getAll()) do
		if car.UnlockRebirth == 0 then
			index += 1
			local pedestal = part({
				name = "Pedestal" .. index,
				size = Vector3.new(3.2, 0.4, 3.2),
				cframe = CFrame.new(-62 + index * 4.4, 2, 0),
				color = CarVisualFactory.qualityColor(car.Quality),
				parent = parent,
				collide = false,
			})
			local model = CarVisualFactory.build({
				modelId = car.ModelId,
				qualityId = car.Quality,
				upgradeLevel = 0,
				displayName = car.DisplayName .. "（展示）",
			})
			model.Name = "DisplayCar"
			model:SetAttribute("DisplayOnly", true)
			model.Parent = parent
			model:PivotTo(pedestal.CFrame * CFrame.new(0, 1.15, 0))
		end
	end
end

function PlaygroundBuilder.build(parent: Instance)
	local existing = parent:FindFirstChild(PlaygroundBuilder.FolderName)
	if existing ~= nil
		and existing:GetAttribute("Complete") == true
		and existing:GetAttribute("BuildVersion") == PlaygroundBuilder.Version
	then
		return existing, false
	end
	if existing ~= nil then
		existing:Destroy()
	end

	-- 先在場景外組好，再一次放進 Workspace，避免客戶端只等到空資料夾。
	local folder = Instance.new("Folder")
	folder.Name = PlaygroundBuilder.FolderName
	folder:SetAttribute("CarForgeTaxPlayground", true)

	part({
		name = "PlaygroundFloor",
		size = Vector3.new(300, 0.4, 180),
		cframe = CFrame.new(40, 0.6, 0),
		color = TABLE,
		parent = folder,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(96, 220, 150)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.CFrame = CFrame.new(-78, 1.3, 8)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder
	caption(spawn, "出生區\n關服後測試資料會消失", 4)

	buildShowroom(folder)

	for slot = 1, 8 do
		local pad = part({
			name = "GaragePad" .. slot,
			size = Vector3.new(4, 0.35, 3.2),
			cframe = CFrame.new(-4, 1, -18 + (slot - 1) * 5),
			color = INK,
			parent = folder,
		})
		pad:SetAttribute("GarageSlot", slot)
	end
	local garageSign = part({
		name = "GarageSign",
		size = Vector3.new(4, 3, 0.4),
		cframe = CFrame.new(-8, 2.6, -22),
		color = ORANGE,
		parent = folder,
		collide = false,
	})
	caption(garageSign, "車庫展示", 2.2)
	garageSign:SetAttribute("Station", "GarageDisplay")

	buildDealer(folder)
	kiosk(folder, "UpgradeBench", Vector3.new(-28, 3.3, 16), Color3.fromRGB(255, 186, 64), "強化工作台", "強化")
	kiosk(folder, "RaceKiosk", Vector3.new(12, 3.3, 16), Color3.fromRGB(255, 132, 48), "競速", "開啟競速")
	-- 模型留著，方便以後加回提示。現在沒有 ProximityPrompt，玩家看不到也按不到。
	local bossGate = part({
		name = "BossGate",
		size = Vector3.new(6, 5, 4),
		cframe = CFrame.new(12, 3.3, -16),
		color = Color3.fromRGB(92, 104, 122),
		parent = folder,
		collide = false,
		query = false,
	})
	bossGate.Transparency = 1
	bossGate.CastShadow = false
	bossGate.CanTouch = false
	bossGate:SetAttribute("Station", "BossGate")
	bossGate:SetAttribute("Hidden", true)
	bossGate:SetAttribute("PlayerStartEnabled", false)

	local races = Instance.new("Folder")
	races.Name = "ActiveRaces"
	races.Parent = folder

	buildTrack(folder)
	folder:SetAttribute("BuildVersion", PlaygroundBuilder.Version)
	folder:SetAttribute("Complete", true)
	folder.Parent = parent
	return folder, true
end

return PlaygroundBuilder
