-- 概念場景只建立一次。玩家加入時不重建，避免重複物件與競速被清掉。
local function importShared(moduleName: string)
	if game ~= nil then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild(moduleName))
	end
	return require("../shared/" .. moduleName)
end

local RaceConfig = importShared("RaceConfig")
local CarVisualFactory = importShared("CarVisualFactory")
local PrivateGarage = require(script.Parent:WaitForChild("PrivateGarage"))
local RustyProps = require(script.Parent:WaitForChild("RustyProps"))

local PlaygroundBuilder = {}

PlaygroundBuilder.FolderName = "CarForgeTaxPlayground"
-- 場景結構有變時提高版本，已完成的舊場景才會整座重建。
PlaygroundBuilder.Version = 39

local ORANGE_DARK = Color3.fromRGB(196, 78, 16)
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
	billboard.Size = UDim2.fromOffset(148, 40)
	billboard.StudsOffset = Vector3.new(0, 3.15, 0)
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
	titleLabel.Text = "T0 · Wandering Dealer"
	titleLabel.TextColor3 = Color3.fromRGB(232, 214, 186)
	titleLabel.TextStrokeTransparency = 0.5
	titleLabel.TextScaled = true
	titleLabel.Parent = billboard
end

local function buildMerchant(origin: CFrame): Model
	-- 仍是官方方塊骨架。衣服用焊在身上的零件，不用會擠歪骨架的配件。
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = Color3.fromRGB(236, 196, 92)
	description.TorsoColor = Color3.fromRGB(118, 78, 48)
	description.LeftArmColor = Color3.fromRGB(186, 148, 92)
	description.RightArmColor = Color3.fromRGB(176, 136, 82)
	description.LeftLegColor = Color3.fromRGB(72, 56, 40)
	description.RightLegColor = Color3.fromRGB(64, 50, 36)
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

	local function wear(host: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?)
		local item = Instance.new("Part")
		item.Name = name
		item.Size = size
		item.Color = color
		item.Material = material
		item.Anchored = false
		item.CanCollide = false
		item.CanTouch = false
		item.CanQuery = false
		item.Massless = true
		item.TopSurface = Enum.SurfaceType.Smooth
		item.BottomSurface = Enum.SurfaceType.Smooth
		if shape ~= nil then
			item.Shape = shape
		end
		item.CFrame = host.CFrame * offset
		item.Parent = npc
		local weld = Instance.new("WeldConstraint")
		weld.Name = name .. "Weld"
		weld.Part0 = host
		weld.Part1 = item
		weld.Parent = item
		return item
	end

	local upright = CFrame.Angles(0, 0, math.rad(90))
	local hat = Color3.fromRGB(92, 62, 38)
	local crownY = head.Size.Y * 0.5 + 0.2
	wear(head, "HatBrim", Vector3.new(0.08, 1.45, 1.45), CFrame.new(0, head.Size.Y * 0.5 + 0.04, 0) * upright, hat, Enum.Material.Fabric, Enum.PartType.Cylinder)
	wear(head, "HatCrown", Vector3.new(0.26, 0.92, 0.92), CFrame.new(0, crownY, 0) * upright, Color3.fromRGB(74, 50, 32), Enum.Material.Fabric, Enum.PartType.Cylinder)
	local torso = npc:FindFirstChild("UpperTorso")
	if torso ~= nil and torso:IsA("BasePart") then
		local vestBrown = Color3.fromRGB(102, 66, 40)
		local front = -(torso.Size.Z * 0.5 + 0.06)
		wear(torso, "Vest", Vector3.new(torso.Size.X + 0.08, torso.Size.Y * 0.78, 0.1), CFrame.new(0, -0.04, front), vestBrown, Enum.Material.Fabric)
		wear(torso, "VestPatch", Vector3.new(0.32, 0.26, 0.04), CFrame.new(0.28, -0.12, front - 0.06), Color3.fromRGB(78, 86, 62), Enum.Material.Fabric)
		wear(torso, "OilStain", Vector3.new(0.22, 0.16, 0.03), CFrame.new(-0.22, 0.16, front - 0.05), Color3.fromRGB(36, 32, 28), Enum.Material.SmoothPlastic)
	end
	return npc
end

local function buildDealer(parent: Instance)
	-- 玩家從 +Z 走近。棚子只蓋住身後的桌子，名稱和互動留在頭頂前方。
	local spot = PrivateGarage.Zones.Gacha
	local origin = CFrame.new(spot.X, 0.8, spot.Z)
	local dealer = Instance.new("Model")
	dealer.Name = "R0Dealer"
	dealer.Parent = parent

	local wood = Color3.fromRGB(132, 92, 58)
	local woodDark = Color3.fromRGB(92, 64, 40)
	local tin = Color3.fromRGB(132, 92, 74)
	local tinDark = Color3.fromRGB(98, 64, 48)
	local rust = Color3.fromRGB(122, 64, 38)
	local steel = Color3.fromRGB(78, 76, 72)
	local steelDark = Color3.fromRGB(42, 40, 38)
	local bolt = Color3.fromRGB(168, 148, 112)
	local mudA = Color3.fromRGB(96, 70, 44)
	local mudB = Color3.fromRGB(72, 52, 34)
	local mudC = Color3.fromRGB(118, 88, 56)

	local function add(name: string, size: Vector3, localCf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?, className: string?)
		return part({
			name = name,
			size = size,
			cframe = origin * localCf,
			color = color,
			material = material,
			parent = dealer,
			collide = collide == true,
			className = className,
		})
	end

	local function pipe(name: string, length: number, diameter: number, localCf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?)
		local item = add(name, Vector3.new(length, diameter, diameter), localCf, color, material, collide)
		item.Shape = Enum.PartType.Cylinder
		return item
	end

	local upright = CFrame.Angles(0, 0, math.rad(90))
	local facePlayer = CFrame.Angles(0, math.pi, 0)

	-- 整塊泥地先鋪滿。土台、木板路和垃圾山都坐在這層上面，底部貼齊泥面。
	local GROUND = 0.18
	local YARD = 0.34
	local function slab(name: string, size: Vector3, top: number, x: number, z: number, color: Color3, material: Enum.Material, collide: boolean?)
		local centerY = top - size.Y * 0.5
		return add(name, size, CFrame.new(x, centerY, z), color, material, collide ~= false)
	end
	local function grounded(name: string, size: Vector3, x: number, z: number, surface: number, color: Color3, material: Enum.Material, pitch: number, yaw: number, collide: boolean?)
		local rot = CFrame.Angles(pitch, yaw, 0)
		local half = size * 0.5
		local minY = 0
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local corner = rot * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
					if corner.Y < minY then
						minY = corner.Y
					end
				end
			end
		end
		return add(name, size, CFrame.new(x, surface - minY, z) * rot, color, material, collide == true)
	end

	local function ball(name: string, diameter: number, x: number, y: number, z: number, color: Color3, material: Enum.Material, collide: boolean?)
		local item = add(name, Vector3.new(diameter, diameter, diameter), CFrame.new(x, y, z), color, material, collide == true)
		item.Shape = Enum.PartType.Ball
		return item
	end

	slab("SoilLot", Vector3.new(18, 0.16, 24), GROUND, 0, -0.4, mudB, Enum.Material.Ground)
	slab("WestYard", Vector3.new(4.6, 0.16, 6.2), YARD, -5.7, -4.2, mudA, Enum.Material.Ground)
	slab("EastYard", Vector3.new(4.6, 0.16, 6.0), YARD, 5.7, -4.3, mudC, Enum.Material.Ground)
	-- 下半埋進泥地的圓土堆，前緣停在棚子後面。
	ball("HillCore", 4.2, 0.05, 1.15, -9.65, mudC, Enum.Material.Ground, true)
	ball("HillLumpA", 2.7, -1.85, 0.72, -10.35, mudA, Enum.Material.Ground, true)
	ball("HillLumpB", 2.35, 1.95, 0.62, -8.85, mudB, Enum.Material.Ground, true)
	ball("HillLumpC", 1.8, 1.15, 0.48, -10.7, mudA, Enum.Material.Ground, true)
	for index, boardZ in ipairs({ 2.15, 4.05, 5.95, 7.85, 9.75 }) do
		local name = if index == 1 then "Walkway" else "WalkPlank"
		local yaw = ({ 0.04, -0.07, 0.05, -0.04, 0.03 })[index]
		local x = ({ 0.06, -0.1, 0.08, -0.05, 0.04 })[index]
		add(name, Vector3.new(1.55, 0.05, 1.5), CFrame.new(x, GROUND + 0.025, boardZ) * CFrame.Angles(0, yaw, 0), if index % 2 == 0 then woodDark else wood, Enum.Material.WoodPlanks, true)
	end
	add("OilStain", Vector3.new(2.1, 0.02, 1.45), CFrame.new(4.6, GROUND + 0.02, -2.4), Color3.fromRGB(42, 32, 24), Enum.Material.Ground, false)
	for index, pebble in ipairs({
		Vector3.new(-7.4, -2.4),
		Vector3.new(7.2, -6.2),
		Vector3.new(-2.4, 6.4),
		Vector3.new(1.8, 3.6),
		Vector3.new(6.4, 5.2),
		Vector3.new(-6.8, 4.8),
	}) do
		local span = if index % 2 == 0 then 0.34 else 0.24
		local onYard = math.abs(pebble.X) > 3.4 and pebble.Y < -1.2
		ball("Pebble" .. index, span, pebble.X, (if onYard then YARD else GROUND) + span * 0.5, pebble.Y, Color3.fromRGB(110, 104, 96), Enum.Material.Slate, false)
	end

	add("HeapSheetA", Vector3.new(1.8, 0.08, 1.05), CFrame.new(-0.99, 2.94, -10.12) * CFrame.Angles(math.rad(-22), math.rad(23), math.rad(9)), tin, Enum.Material.CorrodedMetal, false)
	add("HeapSheetB", Vector3.new(1.5, 0.07, 0.95), CFrame.new(1.78, 2.12, -10.41) * CFrame.Angles(math.rad(16), math.rad(-34), 0), tinDark, Enum.Material.CorrodedMetal, false)
	add("HeapPlank", Vector3.new(1.4, 0.1, 0.22), CFrame.new(0.24, 3.24, -9.36) * CFrame.Angles(math.rad(6), math.rad(46), 0), wood, Enum.Material.Wood, false)
	add("HeapPlankB", Vector3.new(1.1, 0.08, 0.18), CFrame.new(-1.88, 1.9, -10.08) * CFrame.Angles(math.rad(14), math.rad(11), math.rad(23)), woodDark, Enum.Material.Wood, false)
	ball("HeapKnob", 0.55, 0.58, 3.38, -9.86, steel, Enum.Material.Metal, false)
	ball("HeapKnobB", 0.38, -0.77, 3.15, -9.06, rust, Enum.Material.CorrodedMetal, false)
	pipe("HeapPipe", 1.45, 0.18, CFrame.new(1.45, 2.76, -10.08) * CFrame.Angles(math.rad(8), math.rad(50), math.rad(70)), steelDark, Enum.Material.Metal, false)
	pipe("HeapRod", 1.05, 0.12, CFrame.new(-0.39, 2.7, -11.09) * CFrame.Angles(math.rad(18), math.rad(23), math.rad(80)), rust, Enum.Material.CorrodedMetal, false)

	local frontZ, backZ = -3.28, -6.42
	local frontY, backY = 4.72, 5.58
	local function support(name: string, x: number, z: number, topY: number)
		local shoeH = 0.07
		add(name .. "Shoe", Vector3.new(0.52, shoeH, 0.52), CFrame.new(x, GROUND + shoeH * 0.5, z), steelDark, Enum.Material.Metal, true)
		local postH = topY - (GROUND + shoeH)
		local post = add(name, Vector3.new(postH, 0.28, 0.28), CFrame.new(x, GROUND + shoeH + postH * 0.5, z) * upright, woodDark, Enum.Material.Wood, true)
		post.Shape = Enum.PartType.Cylinder
		pipe(name .. "Bolt", 0.05, 0.1, CFrame.new(x, topY - 0.02, z) * upright, bolt, Enum.Material.Metal, false)
	end

	support("PostFL", -3.25, frontZ, frontY)
	support("PostFR", 3.25, frontZ, frontY)
	support("PostBL", -3.05, backZ, backY)
	support("PostBR", 3.05, backZ, backY)
	add("BeamFront", Vector3.new(6.7, 0.1, 0.1), CFrame.new(0, frontY - 0.08, frontZ), steel, Enum.Material.Metal, false)
	add("BeamBack", Vector3.new(6.3, 0.1, 0.1), CFrame.new(0, backY - 0.08, backZ), steel, Enum.Material.Metal, false)
	local function slopeBeam(name: string, x0: number, x1: number)
		local from = Vector3.new(x0, frontY - 0.08, frontZ)
		local to = Vector3.new(x1, backY - 0.08, backZ)
		local delta = to - from
		local mid = (from + to) * 0.5
		local flat = Vector3.new(delta.X, 0, delta.Z)
		local pitch = math.atan2(delta.Y, flat.Magnitude)
		add(name, Vector3.new(0.1, 0.1, delta.Magnitude), CFrame.new(mid) * CFrame.Angles(0, math.atan2(delta.X, delta.Z), 0) * CFrame.Angles(-pitch, 0, 0), steelDark, Enum.Material.Metal, false)
	end
	slopeBeam("RafterL", -3.25, -3.05)
	slopeBeam("RafterR", 3.25, 3.05)

	local roofCenter = Vector3.new(0, (frontY + backY) * 0.5, (frontZ + backZ) * 0.5)
	local roofPitch = math.atan2(backY - frontY, frontZ - backZ)
	local roofCf = CFrame.new(roofCenter) * CFrame.Angles(roofPitch, 0, 0)
	add("Canopy", Vector3.new(3.4, 0.07, 3.55), roofCf * CFrame.new(-1.55, 0, 0), tin, Enum.Material.CorrodedMetal, false)
	add("RoofSheet", Vector3.new(3.4, 0.07, 3.55), roofCf * CFrame.new(1.55, 0.025, 0), tinDark, Enum.Material.CorrodedMetal, false)
	add("RoofSeam", Vector3.new(0.16, 0.04, 3.4), roofCf * CFrame.new(0, 0.05, 0), steelDark, Enum.Material.Metal, false)
	add("RustSpotA", Vector3.new(0.85, 0.02, 0.5), roofCf * CFrame.new(-1.3, 0.05, 0.45), rust, Enum.Material.CorrodedMetal, false)
	add("RustSpotB", Vector3.new(0.55, 0.02, 0.38), roofCf * CFrame.new(1.35, 0.07, -0.55), rust, Enum.Material.CorrodedMetal, false)
	add("CanopyHem", Vector3.new(6.8, 0.08, 0.1), CFrame.new(0, frontY - 0.02, frontZ + 0.08), tinDark, Enum.Material.CorrodedMetal, false)

	local signInk = Color3.fromRGB(255, 244, 224)
	local signBoard = Color3.fromRGB(32, 22, 16)
	local signH = 1.62
	local signZ = frontZ + 0.62
	local beamBottom = frontY - 0.13
	local signTop = beamBottom - 0.28
	local signX = -0.7
	local signW = 3.35
	local signCf = CFrame.new(signX, signTop - signH * 0.5, signZ) * facePlayer
	add("SignFrame", Vector3.new(signW + 0.22, signH + 0.18, 0.06), CFrame.new(signX, signTop - signH * 0.5, signZ - 0.07) * facePlayer, woodDark, Enum.Material.Wood, false)
	add("SignStrapL", Vector3.new(0.1, 0.08, 0.62), CFrame.new(signX - signW * 0.5 + 0.12, beamBottom - 0.02, frontZ + 0.34), woodDark, Enum.Material.Wood, false)
	add("SignStrapR", Vector3.new(0.1, 0.08, 0.62), CFrame.new(signX + signW * 0.5 - 0.12, beamBottom - 0.02, frontZ + 0.34), woodDark, Enum.Material.Wood, false)
	add("SignArmL", Vector3.new(0.1, 0.28, 0.08), CFrame.new(signX - signW * 0.5 + 0.12, signTop + 0.1, signZ), woodDark, Enum.Material.Wood, false)
	add("SignArmR", Vector3.new(0.1, 0.28, 0.08), CFrame.new(signX + signW * 0.5 - 0.12, signTop + 0.1, signZ), woodDark, Enum.Material.Wood, false)
	local shopSign = add("ShopSign", Vector3.new(signW, signH, 0.08), signCf, signBoard, Enum.Material.Wood, false)
	local shopGui = Instance.new("SurfaceGui")
	shopGui.Name = "ShopLabel"
	shopGui.Face = Enum.NormalId.Front
	shopGui.LightInfluence = 0
	shopGui.Parent = shopSign
	local shopText = Instance.new("TextLabel")
	shopText.BackgroundTransparency = 1
	shopText.Size = UDim2.fromScale(1, 1)
	shopText.Font = Enum.Font.FredokaOne
	shopText.Text = "RUSTY'S SCRAP LOTTERY"
	shopText.TextColor3 = signInk
	shopText.TextStrokeColor3 = Color3.fromRGB(18, 12, 8)
	shopText.TextStrokeTransparency = 0.45
	shopText.TextScaled = true
	shopText.TextWrapped = true
	local shopPad = Instance.new("UIPadding")
	shopPad.PaddingTop = UDim.new(0.1, 0)
	shopPad.PaddingBottom = UDim.new(0.08, 0)
	shopPad.PaddingLeft = UDim.new(0.06, 0)
	shopPad.PaddingRight = UDim.new(0.06, 0)
	shopPad.Parent = shopText
	shopText.Parent = shopGui

	local tableZ = -4.62
	local topY = 2.28
	add("TablePlankA", Vector3.new(6.6, 0.14, 0.62), CFrame.new(0, topY, tableZ - 0.68), wood, Enum.Material.Wood, true)
	add("StallTop", Vector3.new(6.6, 0.14, 0.62), CFrame.new(0, topY, tableZ), woodDark, Enum.Material.Wood, true)
	add("TablePlankC", Vector3.new(6.6, 0.14, 0.62), CFrame.new(0, topY, tableZ + 0.68), wood, Enum.Material.Wood, true)
	add("TableEdge", Vector3.new(6.7, 0.08, 0.05), CFrame.new(0, topY - 0.02, tableZ + 1.02), woodDark, Enum.Material.Wood, false)
	add("TableEdgeL", Vector3.new(0.05, 0.16, 2.05), CFrame.new(-3.32, topY, tableZ), woodDark, Enum.Material.Wood, false)
	add("TableEdgeR", Vector3.new(0.05, 0.16, 2.05), CFrame.new(3.32, topY, tableZ), woodDark, Enum.Material.Wood, false)
	for _, corner in ipairs({
		Vector3.new(-3.05, -0.9),
		Vector3.new(3.05, -0.9),
		Vector3.new(-3.05, 0.9),
		Vector3.new(3.05, 0.9),
	}) do
		local shoeH = 0.07
		local legTop = topY - 0.07
		local legH = legTop - (GROUND + shoeH)
		add("TableShoe", Vector3.new(0.36, shoeH, 0.36), CFrame.new(corner.X, GROUND + shoeH * 0.5, tableZ + corner.Y), steelDark, Enum.Material.Metal, true)
		local leg = add("TableLeg", Vector3.new(legH, 0.16, 0.16), CFrame.new(corner.X, GROUND + shoeH + legH * 0.5, tableZ + corner.Y) * upright, woodDark, Enum.Material.Wood, true)
		leg.Shape = Enum.PartType.Cylinder
		pipe("TableBolt", 0.04, 0.08, CFrame.new(corner.X, topY + 0.08, tableZ + corner.Y) * upright, bolt, Enum.Material.Metal, false)
	end
	add("TableStretcher", Vector3.new(5.9, 0.08, 0.08), CFrame.new(0, 0.95, tableZ), steel, Enum.Material.Metal, false)
	add("TableStretcherZ", Vector3.new(0.08, 0.08, 1.6), CFrame.new(0, 0.95, tableZ), steel, Enum.Material.Metal, false)
	pipe("LoosePipe", 0.55, 0.1, CFrame.new(2.35, topY + 0.12, tableZ - 0.35) * CFrame.Angles(0, 0.5, math.rad(78)), rust, Enum.Material.CorrodedMetal, false)
	add("LampCord", Vector3.new(0.05, 1.7, 0.05), CFrame.new(0.15, 4.28, -4.7), woodDark, Enum.Material.Wood, false)
	local lamp = ball("StallLamp", 0.36, 0.15, 3.4, -4.7, Color3.fromRGB(255, 214, 156), Enum.Material.SmoothPlastic, false)
	local glow = Instance.new("PointLight")
	glow.Name = "WarmLight"
	glow.Color = Color3.fromRGB(255, 184, 108)
	glow.Brightness = 1.15
	glow.Range = 16
	glow.Shadows = false
	glow.Parent = lamp

	local backH = 2.05
	add("BackTin", Vector3.new(5.7, backH, 0.08), CFrame.new(0, GROUND + backH * 0.5, -6.56), tin, Enum.Material.CorrodedMetal, false)
	add("BackTinRust", Vector3.new(1.5, 0.85, 0.03), CFrame.new(-1.2, GROUND + backH * 0.62, -6.5), rust, Enum.Material.CorrodedMetal, false)
	local fenceH = 1.35
	local fenceA = pipe("FencePostA", fenceH, 0.16, CFrame.new(-7.55, YARD + fenceH * 0.5, -3.55) * upright, woodDark, Enum.Material.Wood, true)
	local fenceB = pipe("FencePostB", fenceH, 0.16, CFrame.new(-7.55, YARD + fenceH * 0.5, -1.85) * upright, woodDark, Enum.Material.Wood, true)
	add("FenceRail", Vector3.new(0.08, 0.1, 1.55), CFrame.new(-7.55, YARD + 0.95, -2.7), tinDark, Enum.Material.CorrodedMetal, false)
	add("StoolSeat", Vector3.new(0.72, 0.08, 0.72), CFrame.new(-2.25, GROUND + 0.62, -1.85), wood, Enum.Material.Wood, false)
	pipe("StoolLeg", 0.58, 0.14, CFrame.new(-2.25, GROUND + 0.29, -1.85) * upright, woodDark, Enum.Material.Wood, false)

	local rankX, rankZ = 2.7, 10.7
	local postH = 2.15
	pipe("PoolPostL", postH, 0.16, CFrame.new(rankX - 0.95, GROUND + postH * 0.5, rankZ) * upright, woodDark, Enum.Material.Wood, true)
	pipe("PoolPostR", postH, 0.16, CFrame.new(rankX + 0.95, GROUND + postH * 0.5, rankZ) * upright, woodDark, Enum.Material.Wood, true)
	local rankCf = CFrame.new(rankX, GROUND + 1.55, rankZ) * facePlayer
	add("PoolFrame", Vector3.new(1.85, 1.28, 0.06), CFrame.new(rankX, GROUND + 1.55, rankZ - 0.07) * facePlayer, woodDark, Enum.Material.Wood, false)
	local poolSign = add("PoolSign", Vector3.new(1.6, 1.08, 0.08), rankCf, signBoard, Enum.Material.Wood, false)
	local poolGui = Instance.new("SurfaceGui")
	poolGui.Name = "RankLabel"
	poolGui.Face = Enum.NormalId.Front
	poolGui.LightInfluence = 0
	poolGui.Parent = poolSign
	local poolText = Instance.new("TextLabel")
	poolText.BackgroundTransparency = 1
	poolText.Size = UDim2.fromScale(1, 1)
	poolText.Font = Enum.Font.FredokaOne
	poolText.Text = "T0 Rookie"
	poolText.TextColor3 = signInk
	poolText.TextStrokeColor3 = Color3.fromRGB(18, 12, 8)
	poolText.TextStrokeTransparency = 0.45
	poolText.TextScaled = true
	local poolPad = Instance.new("UIPadding")
	poolPad.PaddingTop = UDim.new(0.12, 0)
	poolPad.PaddingBottom = UDim.new(0.1, 0)
	poolPad.PaddingLeft = UDim.new(0.08, 0)
	poolPad.PaddingRight = UDim.new(0.08, 0)
	poolPad.Parent = poolText
	poolText.Parent = poolGui

	RustyProps.place(dealer, origin)

	local feet = Vector3.new(2.35, GROUND, -0.45)
	local npc = buildMerchant(origin * CFrame.lookAt(feet, feet + Vector3.new(-0.48, 0, 1)))
	npc.Parent = dealer
	return dealer
end

function PlaygroundBuilder.stepDealer(folder: Instance?, _time: number)
	-- 老破改由官方 Humanoid 待機動畫負責，不再用位移左右搖。
	if typeof(folder) ~= "Instance" then
		return
	end
end

function PlaygroundBuilder.claimBay(playerKey: string)
	return PrivateGarage.claim(playerKey)
end

function PlaygroundBuilder.releaseBay(playerKey: string)
	PrivateGarage.release(playerKey)
end

function PlaygroundBuilder.paintBay(playerKey: string, view)
	PrivateGarage.paint(playerKey, view)
end

function PlaygroundBuilder.build(parent: Instance)
	-- 匯入預覽留在 Workspace 時，重建或沿用場景都先收掉，避免和攤位各出現一份。
	RustyProps.retireImports(parent)
	-- 建立官方角色會讓出執行權。鎖住避免測試與開局同時各做一份場景。
	while PlaygroundBuilder._building == true do
		task.wait()
	end
	local existing = parent:FindFirstChild(PlaygroundBuilder.FolderName)
	if existing ~= nil
		and existing:GetAttribute("Complete") == true
		and existing:GetAttribute("BuildVersion") == PlaygroundBuilder.Version
	then
		if not PrivateGarage.isMounted() then
			local bay0 = nil
			for _, child in ipairs(existing:GetChildren()) do
				if child.Name == "PrivateGarage" and child:GetAttribute("BayIndex") == 0 and child:IsA("Model") then
					bay0 = child
					break
				end
			end
			if bay0 ~= nil then
				PrivateGarage.mount(existing, bay0, existing:FindFirstChild("Track"))
			end
		end
		return existing, false
	end
	PlaygroundBuilder._building = true
	local function finish(folder: Instance, created: boolean)
		PlaygroundBuilder._building = false
		return folder, created
	end

	-- 先在場景外組好。成功後才換掉舊場景，避免中途失敗把地圖清掉。
	local folder = Instance.new("Folder")
	folder.Name = PlaygroundBuilder.FolderName
	folder:SetAttribute("CarForgeTaxPlayground", true)

	local builtOk, builtErr = pcall(buildDealer, folder)
	if not builtOk then
		folder:Destroy()
		PlaygroundBuilder._building = false
		error(builtErr)
	end
	local garage = PrivateGarage.buildTemplate(folder)
	-- 模型留著，方便以後加回提示。現在沒有 ProximityPrompt，玩家看不到也按不到。
	local bossGate = part({
		name = "BossGate",
		size = Vector3.new(6, 5, 4),
		cframe = CFrame.new(0, -20, 0),
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
	PrivateGarage.adoptTracks(folder, garage)
	PrivateGarage.buildZones(folder)
	PrivateGarage.mount(folder, garage, folder:FindFirstChild("Track"))
	folder:SetAttribute("BuildVersion", PlaygroundBuilder.Version)
	folder:SetAttribute("Complete", true)
	if existing ~= nil then
		existing:Destroy()
	end
	folder.Parent = parent
	local merchant = folder:FindFirstChild("LaoPo", true)
	if merchant ~= nil and merchant:IsA("Model") then
		playMerchantIdle(merchant)
	end
	return finish(folder, true)
end

return PlaygroundBuilder
