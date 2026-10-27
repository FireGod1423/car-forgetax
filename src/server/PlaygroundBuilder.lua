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
PlaygroundBuilder.Version = 17

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

local function prompt(host: Instance, actionText: string, objectText: string)
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

-- Roblox 預設 R15 待機。這是官方 Animate 使用的 idle，不是自製搖晃。
local MERCHANT_IDLE = "rbxassetid://507766666"

local function playMerchantIdle(npc: Model)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animation = npc:FindFirstChild("MerchantIdle")
	if animation == nil or not animation:IsA("Animation") then
		animation = Instance.new("Animation")
		animation.Name = "MerchantIdle"
		animation.Parent = npc
	end
	animation.AnimationId = MERCHANT_IDLE
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track ~= nil then
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Idle
		track:Play()
	end
end

local function merchantNameplate(head: BasePart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Size = UDim2.fromOffset(180, 52)
	billboard.StudsOffset = Vector3.new(0, 2.35, 0)
	billboard.MaxDistance = 48
	billboard.LightInfluence = 0
	billboard.Parent = head
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NpcName"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0.58, 0)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = "Rusty"
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.45
	nameLabel.TextScaled = true
	nameLabel.Parent = billboard
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "NpcTitle"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.new(0, 0, 0.56, 0)
	titleLabel.Size = UDim2.new(1, 0, 0.44, 0)
	titleLabel.Font = Enum.Font.GothamMedium
	titleLabel.Text = "R0 · Wandering Dealer"
	titleLabel.TextColor3 = Color3.fromRGB(232, 214, 186)
	titleLabel.TextStrokeTransparency = 0.5
	titleLabel.TextScaled = true
	titleLabel.Parent = billboard
end

local function buildMerchant(origin: CFrame): Model
	-- 暫時用經典 Noob。帽子和補丁會把骨架擠歪，外觀之後再換。
	local description = Instance.new("HumanoidDescription")
	local noobYellow = Color3.fromRGB(245, 205, 48)
	local noobBlue = Color3.fromRGB(13, 105, 172)
	local noobGreen = Color3.fromRGB(75, 151, 75)
	description.HeadColor = noobYellow
	description.TorsoColor = noobBlue
	description.LeftArmColor = noobYellow
	description.RightArmColor = noobYellow
	description.LeftLegColor = noobGreen
	description.RightLegColor = noobGreen
	description.HeightScale = 1
	description.WidthScale = 1
	description.DepthScale = 1
	description.HeadScale = 1
	description.BodyTypeScale = 0
	description.ProportionScale = 0
	local npc = game:GetService("Players"):CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	npc.Name = "LaoPo"
	for _, child in ipairs(npc:GetChildren()) do
		if child:IsA("Accessory") or child.Name == "Animate" or child.Name == "Health" then
			child:Destroy()
		end
	end
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local root = npc:FindFirstChild("HumanoidRootPart")
	local head = npc:FindFirstChild("Head")
	if humanoid == nil or root == nil or head == nil or not root:IsA("BasePart") or not head:IsA("BasePart") then
		error("官方角色建立失敗")
	end
	humanoid.DisplayName = "Rusty"
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
	humanoid.BreakJointsOnDeath = false
	for _, descendant in ipairs(npc:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
		end
	end
	local standY = origin.Position.Y + humanoid.HipHeight + root.Size.Y * 0.5
	local look = origin.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.001 then
		flatLook = Vector3.new(0, 0, 1)
	end
	local stand = Vector3.new(origin.Position.X, standY, origin.Position.Z)
	root.Anchored = true
	root.CFrame = CFrame.lookAt(stand, stand + flatLook.Unit)
	merchantNameplate(head)
	local marker = Instance.new("Attachment")
	marker.Name = "PromptAnchor"
	marker.Position = Vector3.new(0, 1.55, 0)
	marker.Parent = head
	marker:SetAttribute("Station", "R0Dealer")
	local interaction = prompt(marker, "Check the stall", "Rusty")
	interaction.MaxActivationDistance = 14
	interaction.UIOffset = Vector2.new(0, -8)
	return npc
end

local function buildDealer(parent: Instance)
	-- 玩家從 +Z 走近。老破面向玩家，攤位放在他身後（-Z）。
	local origin = CFrame.new(-28, 0.8, -18)
	local dealer = Instance.new("Model")
	dealer.Name = "R0Dealer"
	dealer.Parent = parent

	local steel = Color3.fromRGB(58, 60, 64)
	local steelDark = Color3.fromRGB(36, 36, 38)
	local rust = Color3.fromRGB(122, 64, 38)
	local wood = Color3.fromRGB(112, 78, 48)
	local woodDark = Color3.fromRGB(78, 54, 34)
	local tarp = Color3.fromRGB(86, 90, 62)
	local soot = Color3.fromRGB(28, 28, 30)

	local function add(name: string, size: Vector3, localCf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?, className: string?)
		return part({
			name = name,
			className = className,
			size = size,
			cframe = origin * localCf,
			color = color,
			material = material,
			parent = dealer,
			collide = collide == true,
		})
	end

	local function wedge(name: string, size: Vector3, localCf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?)
		return add(name, size, localCf, color, material, collide, "WedgePart")
	end

	local function pipe(name: string, length: number, diameter: number, localCf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?)
		local item = add(name, Vector3.new(length, diameter, diameter), localCf, color, material, collide)
		item.Shape = Enum.PartType.Cylinder
		return item
	end

	-- 四根方柱同時撐住桌面和棚頂，樑接在柱頂，桌板嵌在柱子中間。
	local xL, xR = -2.5, 2.5
	local zF, zB = -4.4, -6.9
	local postW = 0.28
	local postTop = 5.05
	local postBase = 0.1
	local postH = postTop - postBase
	local postY = postBase + postH * 0.5
	local beamY = postTop + 0.09
	local spanX = (xR - xL) + postW
	local spanZ = (zB - zF) * -1
	local midZ = (zF + zB) * 0.5
	local upright = CFrame.Angles(0, 0, math.rad(90))

	local function post(name: string, x: number, z: number)
		add(name .. "Foot", Vector3.new(0.72, 0.1, 0.72), CFrame.new(x, 0.05, z), steelDark, Enum.Material.DiamondPlate, true)
		add(name, Vector3.new(postW, postH, postW), CFrame.new(x, postY, z), steel, Enum.Material.Metal, true)
	end

	post("PostFL", xL, zF)
	post("PostFR", xR, zF)
	post("PostBL", xL, zB)
	post("PostBR", xR, zB)
	add("BeamFront", Vector3.new(spanX, 0.18, 0.18), CFrame.new(0, beamY, zF), steelDark, Enum.Material.Metal, false)
	add("BeamBack", Vector3.new(spanX, 0.18, 0.18), CFrame.new(0, beamY, zB), steelDark, Enum.Material.Metal, false)
	add("BeamLeft", Vector3.new(0.18, 0.18, spanZ), CFrame.new(xL, beamY, midZ), steelDark, Enum.Material.Metal, false)
	add("BeamRight", Vector3.new(0.18, 0.18, spanZ), CFrame.new(xR, beamY, midZ), steelDark, Enum.Material.Metal, false)
	add("Canopy", Vector3.new(spanX + 0.35, 0.08, spanZ + 0.28), CFrame.new(0, beamY + 0.13, midZ), tarp, Enum.Material.Fabric, false)
	add("CanopyHem", Vector3.new(spanX + 0.2, 0.16, 0.1), CFrame.new(0, beamY - 0.02, zF + 0.12), Color3.fromRGB(62, 64, 46), Enum.Material.Fabric, false)
	add("CanopyStitch", Vector3.new(spanX - 0.4, 0.02, 0.06), CFrame.new(0, beamY + 0.18, midZ), Color3.fromRGB(48, 46, 40), Enum.Material.Fabric, false)

	local topY = 2.58
	local plankT = 0.16
	local plankY = topY - plankT * 0.5
	add("StallTop", Vector3.new(4.55, plankT, 0.72), CFrame.new(0, plankY, midZ), wood, Enum.Material.Wood, true)
	add("PlankFront", Vector3.new(4.55, plankT, 0.7), CFrame.new(0, plankY, midZ + 0.74), woodDark, Enum.Material.Wood, true)
	add("PlankBack", Vector3.new(4.55, plankT, 0.7), CFrame.new(0, plankY, midZ - 0.74), Color3.fromRGB(96, 66, 40), Enum.Material.Wood, true)
	add("ApronFront", Vector3.new(4.55, 0.18, 0.12), CFrame.new(0, topY - 0.24, zF - 0.18), steel, Enum.Material.DiamondPlate, false)
	add("ApronBack", Vector3.new(4.55, 0.18, 0.12), CFrame.new(0, topY - 0.24, zB + 0.18), steel, Enum.Material.Metal, false)
	add("ApronLeft", Vector3.new(0.12, 0.18, spanZ - 0.5), CFrame.new(xL + 0.22, topY - 0.24, midZ), steel, Enum.Material.Metal, false)
	add("ApronRight", Vector3.new(0.12, 0.18, spanZ - 0.5), CFrame.new(xR - 0.22, topY - 0.24, midZ), steel, Enum.Material.Metal, false)
	add("Stretcher", Vector3.new(spanX - 0.2, 0.14, 0.14), CFrame.new(0, 1.15, midZ), steelDark, Enum.Material.Metal, false)
	add("StretcherZ", Vector3.new(0.14, 0.14, spanZ - 0.4), CFrame.new(0, 1.15, midZ), steelDark, Enum.Material.Metal, false)
	add("BackBrace", Vector3.new(6.45, 0.1, 0.1), CFrame.new(0, 2.45, zB) * CFrame.Angles(0, 0, math.rad(39)), rust, Enum.Material.CorrodedMetal, false)

	local function bolt(name: string, x: number, y: number, z: number)
		pipe(name, 0.06, 0.14, CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(168, 146, 92), Enum.Material.Metal, false)
	end

	bolt("BoltFL", xL, topY - 0.24, zF + 0.18)
	bolt("BoltFR", xR, topY - 0.24, zF + 0.18)
	bolt("BoltBL", xL, topY - 0.24, zB - 0.18)
	bolt("BoltBR", xR, topY - 0.24, zB - 0.18)

	-- 桌上只放小零件，不放車。高度都從桌面往上算。
	add("Toolbox", Vector3.new(1.15, 0.4, 0.58), CFrame.new(-1.25, topY + 0.2, midZ - 0.45), soot, Enum.Material.DiamondPlate, false)
	add("ToolboxLid", Vector3.new(1.15, 0.06, 0.58), CFrame.new(-1.25, topY + 0.43, midZ - 0.45), steel, Enum.Material.Metal, false)
	add("ToolboxHandle", Vector3.new(0.42, 0.08, 0.08), CFrame.new(-1.25, topY + 0.52, midZ - 0.45), steelDark, Enum.Material.Metal, false)
	add("Tray", Vector3.new(1.35, 0.06, 0.8), CFrame.new(1.15, topY + 0.03, midZ + 0.15), steelDark, Enum.Material.DiamondPlate, false)
	pipe("Coil", 0.16, 0.5, CFrame.new(1.35, topY + 0.14, midZ - 0.55) * upright, rust, Enum.Material.CorrodedMetal, false)
	add("Wrench", Vector3.new(0.85, 0.05, 0.14), CFrame.new(0.15, topY + 0.025, midZ + 0.35) * CFrame.Angles(0, 0.4, 0), Color3.fromRGB(150, 150, 148), Enum.Material.Metal, false)
	add("WrenchHead", Vector3.new(0.22, 0.06, 0.22), CFrame.new(-0.22, topY + 0.03, midZ + 0.5), Color3.fromRGB(150, 150, 148), Enum.Material.Metal, false)
	pipe("OilCan", 0.48, 0.32, CFrame.new(-1.45, topY + 0.24, midZ + 0.45) * upright, Color3.fromRGB(92, 48, 28), Enum.Material.SmoothPlastic, false)
	add("CanSpout", Vector3.new(0.1, 0.1, 0.22), CFrame.new(-1.45, topY + 0.5, midZ + 0.62), steel, Enum.Material.Metal, false)

	-- 柱子外側的地面雜物，不壓到桌面。
	pipe("OilDrum", 1.55, 1.2, CFrame.new(3.55, 0.78, midZ) * upright, rust, Enum.Material.CorrodedMetal, true)
	pipe("DrumRim", 0.08, 1.28, CFrame.new(3.55, 1.5, midZ) * upright, steelDark, Enum.Material.Metal, false)
	add("CrateA", Vector3.new(1.15, 0.85, 1.0), CFrame.new(-3.55, 0.48, midZ - 0.2), wood, Enum.Material.Wood, true)
	add("CrateLid", Vector3.new(1.2, 0.08, 1.05), CFrame.new(-3.55, 0.94, midZ - 0.2), woodDark, Enum.Material.Wood, false)
	pipe("OldTire", 0.36, 1.55, CFrame.new(3.15, 0.8, zB + 0.15) * CFrame.Angles(0, math.rad(90), 0), soot, Enum.Material.SmoothPlastic, true)

	-- 泥地範圍不變。重疊的面分開高度，避免兩塊地面貼在同一個平面上閃爍。
	local soil = Color3.fromRGB(96, 70, 44)
	local soilDark = Color3.fromRGB(68, 48, 32)
	local dust = Color3.fromRGB(142, 118, 78)
	local deadGrass = Color3.fromRGB(92, 96, 52)
	add("SoilBed", Vector3.new(16, 0.12, 14), CFrame.new(0.2, 0.08, -5.2) * CFrame.Angles(0, 0.08, 0), soil, Enum.Material.Ground, false)
	add("SoilFront", Vector3.new(9, 0.1, 7), CFrame.new(-0.6, 0.26, -0.4) * CFrame.Angles(0, -0.12, 0), Color3.fromRGB(112, 82, 50), Enum.Material.Ground, false)
	add("SoilBack", Vector3.new(12, 0.1, 8), CFrame.new(0.8, 0.4, -12.2), soilDark, Enum.Material.Mud, false)
	add("SoilSideL", Vector3.new(6, 0.1, 8), CFrame.new(-6.2, 0.52, -6.4) * CFrame.Angles(0, 0.2, 0), Color3.fromRGB(84, 60, 38), Enum.Material.Ground, false)
	add("SoilSideR", Vector3.new(5.5, 0.1, 7), CFrame.new(6.4, 0.64, -7.2) * CFrame.Angles(0, -0.18, 0), Color3.fromRGB(88, 64, 40), Enum.Material.Mud, false)
	add("DustPath", Vector3.new(3.4, 0.08, 8.5), CFrame.new(0.3, 0.48, -0.6), dust, Enum.Material.Sand, false)
	wedge("SoilLipF", Vector3.new(8, 0.16, 1.6), CFrame.new(0.4, 0.08, 2.6) * CFrame.Angles(0, math.pi, 0), soil, Enum.Material.Ground, false)
	wedge("SoilLipB", Vector3.new(10, 0.2, 1.8), CFrame.new(0.6, 0.12, -16.2), soilDark, Enum.Material.Ground, false)
	wedge("SoilLipL", Vector3.new(1.4, 0.16, 7), CFrame.new(-8.4, 0.1, -6) * CFrame.Angles(0, math.rad(90), 0), soil, Enum.Material.Ground, false)
	wedge("SoilLipR", Vector3.new(1.4, 0.16, 6), CFrame.new(8.2, 0.1, -7.4) * CFrame.Angles(0, math.rad(-90), 0), soilDark, Enum.Material.Ground, false)
	add("OilStain", Vector3.new(2.2, 0.04, 1.5), CFrame.new(2.4, 0.36, -4.6) * CFrame.Angles(0, 0.4, 0), Color3.fromRGB(36, 32, 28), Enum.Material.Slate, false)
	add("PebbleA", Vector3.new(0.35, 0.18, 0.28), CFrame.new(-2.2, 0.4, 0.8), Color3.fromRGB(92, 90, 86), Enum.Material.Rock, false)
	add("PebbleB", Vector3.new(0.22, 0.14, 0.2), CFrame.new(1.8, 0.59, 1.4) * CFrame.Angles(0, 0.6, 0), Color3.fromRGB(110, 104, 96), Enum.Material.Rock, false)
	add("PebbleC", Vector3.new(0.45, 0.22, 0.32), CFrame.new(4.6, 0.25, -3.2), Color3.fromRGB(74, 70, 64), Enum.Material.Slate, false)
	add("TuftA", Vector3.new(0.35, 0.55, 0.12), CFrame.new(-4.2, 0.59, -1.2) * CFrame.Angles(0, 0.4, 0.08), deadGrass, Enum.Material.Grass, false)
	add("TuftB", Vector3.new(0.28, 0.42, 0.1), CFrame.new(3.2, 0.52, 0.6) * CFrame.Angles(0, -0.5, -0.1), deadGrass, Enum.Material.Grass, false)
	add("TuftC", Vector3.new(0.4, 0.62, 0.12), CFrame.new(-5.4, 0.88, -9.2) * CFrame.Angles(0, 0.8, 0.12), Color3.fromRGB(78, 82, 44), Enum.Material.Grass, false)
	add("TuftD", Vector3.new(0.22, 0.36, 0.1), CFrame.new(5.8, 0.87, -10.4), deadGrass, Enum.Material.Grass, false)

	-- 路牌立在泥路近端右側，正面朝走近的人。
	local signFace = CFrame.Angles(0, math.pi, 0)
	add("PoolPost", Vector3.new(0.22, 2.35, 0.22), CFrame.new(1.55, 1.2, 2.35), woodDark, Enum.Material.Wood, true)
	local poolSign = add("PoolSign", Vector3.new(2.4, 1.2, 0.12), CFrame.new(1.55, 2.15, 2.35) * signFace, Color3.fromRGB(214, 186, 132), Enum.Material.Wood, false)
	local signGui = Instance.new("SurfaceGui")
	signGui.Name = "PoolLabel"
	signGui.Face = Enum.NormalId.Front
	signGui.LightInfluence = 0
	signGui.Parent = poolSign
	local signText = Instance.new("TextLabel")
	signText.BackgroundTransparency = 1
	signText.Size = UDim2.fromScale(1, 1)
	signText.Font = Enum.Font.GothamBold
	signText.Text = "NO LICENSE\nPRIZE POOL"
	signText.TextColor3 = Color3.fromRGB(42, 28, 18)
	signText.TextScaled = true
	signText.TextWrapped = true
	signText.Parent = signGui

	-- 攤位正後方的回收山。範圍仍在泥地裡，只加高加厚，前緣不壓到棚子。
	local heapZ = -11.4
	add("HeapCore", Vector3.new(8.8, 2.8, 6.2), CFrame.new(0.4, 1.45, heapZ), soilDark, Enum.Material.Ground, true)
	add("HeapMid", Vector3.new(6.4, 2.6, 4.4), CFrame.new(0.1, 3.85, heapZ - 0.25), rust, Enum.Material.CorrodedMetal, true)
	add("HeapTop", Vector3.new(4.2, 2.2, 3.0), CFrame.new(0.45, 5.85, heapZ - 0.35), Color3.fromRGB(92, 50, 32), Enum.Material.CorrodedMetal, true)
	add("HeapCap", Vector3.new(2.2, 1.6, 1.7), CFrame.new(0.05, 7.55, heapZ - 0.15), steelDark, Enum.Material.Metal, false)
	wedge("HeapSlopeF", Vector3.new(7.4, 2.6, 2.4), CFrame.new(0.3, 1.35, heapZ + 2.5) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(78, 56, 36), Enum.Material.Ground, true)
	wedge("HeapSlopeB", Vector3.new(7.6, 3.0, 2.4), CFrame.new(0.5, 1.55, heapZ - 3.4), soil, Enum.Material.Ground, true)
	wedge("HeapSlopeL", Vector3.new(5.2, 2.4, 2.4), CFrame.new(-5.0, 1.25, heapZ) * CFrame.Angles(0, math.rad(90), 0), rust, Enum.Material.CorrodedMetal, false)
	wedge("HeapSlopeR", Vector3.new(5.4, 2.6, 2.5), CFrame.new(5.2, 1.35, heapZ - 0.2) * CFrame.Angles(0, math.rad(-90), 0), Color3.fromRGB(70, 48, 34), Enum.Material.Ground, false)
	pipe("HeapTireL", 0.55, 2.05, CFrame.new(-2.8, 2.45, heapZ + 0.9) * CFrame.Angles(0.4, 0.2, math.rad(70)), soot, Enum.Material.SmoothPlastic, false)
	pipe("HeapTireR", 0.5, 1.8, CFrame.new(3.0, 3.45, heapZ - 0.5) * CFrame.Angles(0.2, -0.5, math.rad(100)), Color3.fromRGB(24, 24, 26), Enum.Material.SmoothPlastic, false)
	pipe("HeapDrum", 2.1, 1.25, CFrame.new(-1.7, 4.15, heapZ - 0.55) * CFrame.Angles(0, 0.3, math.rad(78)), rust, Enum.Material.CorrodedMetal, false)
	add("HeapHood", Vector3.new(2.6, 0.18, 1.4), CFrame.new(1.5, 5.15, heapZ + 0.45) * CFrame.Angles(0.35, -0.6, 0.2), Color3.fromRGB(132, 122, 108), Enum.Material.Metal, false)
	add("HeapPanel", Vector3.new(2.0, 1.15, 0.12), CFrame.new(2.4, 3.85, heapZ + 1.15) * CFrame.Angles(0.15, 0.8, 0.4), steel, Enum.Material.DiamondPlate, false)
	pipe("HeapPipe", 3.1, 0.28, CFrame.new(-0.35, 6.65, heapZ + 0.15) * CFrame.Angles(0.5, 0.8, math.rad(40)), steelDark, Enum.Material.Metal, false)
	add("HeapCloth", Vector3.new(2.8, 0.06, 1.8), CFrame.new(-0.7, 7.05, heapZ - 0.45) * CFrame.Angles(0.4, 0.3, -0.2), Color3.fromRGB(62, 58, 48), Enum.Material.Fabric, false)
	add("HeapCrate", Vector3.new(1.25, 0.9, 1.05), CFrame.new(2.0, 2.15, heapZ + 1.55) * CFrame.Angles(0.1, 0.5, 0.15), woodDark, Enum.Material.Wood, false)
	add("HeapPlank", Vector3.new(2.2, 0.12, 0.32), CFrame.new(-3.1, 1.15, heapZ + 1.5) * CFrame.Angles(0.2, 0.7, 0.8), wood, Enum.Material.Wood, false)

	-- 站在攤位左前側，面朝外，再往攤位斜一點。腳底仍用 origin 的地面高度。
	local npc = buildMerchant(origin * CFrame.new(-3.35, 0, -2.2) * CFrame.Angles(0, math.pi + math.rad(24), 0))
	npc.Parent = dealer
	return dealer
end

function PlaygroundBuilder.stepDealer(folder: Instance?, _time: number)
	-- 老破改由官方 Humanoid 待機動畫負責，不再用位移左右搖。
	if typeof(folder) ~= "Instance" then
		return
	end
end

local function buildShowroom(parent: Instance)
	local podium = part({
		name = "DisplayPodium",
		size = Vector3.new(28, 1, 8),
		cframe = CFrame.new(-50, 1.3, 0),
		color = CREAM,
		parent = parent,
	})
	caption(podium, "Toy Car Display", 5)
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
				displayName = car.DisplayName .. " (Display)",
			})
			model.Name = "DisplayCar"
			model:SetAttribute("DisplayOnly", true)
			model.Parent = parent
			model:PivotTo(pedestal.CFrame * CFrame.new(0, 1.15, 0))
		end
	end
end

function PlaygroundBuilder.build(parent: Instance)
	-- 建立官方角色會讓出執行權。鎖住避免測試與開局同時各做一份場景。
	while PlaygroundBuilder._building == true do
		task.wait()
	end
	local existing = parent:FindFirstChild(PlaygroundBuilder.FolderName)
	if existing ~= nil
		and existing:GetAttribute("Complete") == true
		and existing:GetAttribute("BuildVersion") == PlaygroundBuilder.Version
	then
		return existing, false
	end
	PlaygroundBuilder._building = true
	local function finish(folder: Instance, created: boolean)
		PlaygroundBuilder._building = false
		return folder, created
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
	caption(spawn, "Spawn\nTest data vanishes when the server closes", 4)

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
	caption(garageSign, "Garage Display", 2.2)
	garageSign:SetAttribute("Station", "GarageDisplay")

	local builtOk, builtErr = pcall(buildDealer, folder)
	if not builtOk then
		PlaygroundBuilder._building = false
		error(builtErr)
	end
	kiosk(folder, "UpgradeBench", Vector3.new(-28, 3.3, 16), Color3.fromRGB(255, 186, 64), "Upgrade Bench", "Upgrade")
	kiosk(folder, "RaceKiosk", Vector3.new(12, 3.3, 16), Color3.fromRGB(255, 132, 48), "Race", "Open Race")
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
	local merchant = folder:FindFirstChild("LaoPo", true)
	if merchant ~= nil and merchant:IsA("Model") then
		playMerchantIdle(merchant)
	end
	return finish(folder, true)
end

return PlaygroundBuilder
