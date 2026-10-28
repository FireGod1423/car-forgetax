-- 密閉改車場。圓環只轉向、不改尺寸。測試圈不發錢。正式賽道在另一區。
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarVisualFactory = require(Shared:WaitForChild("CarVisualFactory"))
local RaceConfig = require(Shared:WaitForChild("RaceConfig"))

local PrivateGarage = {}

-- 一間車庫沿 Z 約 65 studs。四間先排好，88 的間距讓牆和屋頂不會疊到隔壁。
PrivateGarage.Stride = 88
PrivateGarage.BayCount = 4
PrivateGarage.TrackOrigin = Vector3.new(46, 2.2, 1)
PrivateGarage.TrackYaw = -math.pi / 2
PrivateGarage.GarageTrackCenter = Vector3.new(20, 2.2, 32)
-- 正式賽道中心放到 (320, 2.2, 0)。只平移，不改 RaceConfig。
PrivateGarage.RaceShift = Vector3.new(274, 0, -1)
PrivateGarage.BoosterAlong = 6
PrivateGarage.Zones = {
	Garage = Vector3.new(34, 0, 32),
	Lobby = Vector3.new(24, 0, -300),
	Gacha = Vector3.new(320, 0, -300),
	Racetrack = Vector3.new(320, 0, 0),
}

local STRIDE = PrivateGarage.Stride
local SLATE = Color3.fromRGB(34, 34, 36)
local TIN = Color3.fromRGB(112, 116, 112)
local TIN_DARK = Color3.fromRGB(72, 76, 74)
local RUST = Color3.fromRGB(122, 78, 52)
local STEEL = Color3.fromRGB(86, 90, 94)
local INK = Color3.fromRGB(16, 16, 18)
local WOOD = Color3.fromRGB(128, 92, 58)
local CREAM = Color3.fromRGB(214, 206, 190)

local state = {
	folder = nil,
	template = nil,
	track = nil,
	byPlayer = {},
	byIndex = {},
	hops = {},
	lobbySpawn = nil,
}

local hooked = {}

local function part(props)
	local item = Instance.new(props.className or "Part")
	item.Name = props.name or "Part"
	item.Anchored = true
	item.Size = props.size
	item.CFrame = props.cframe
	item.Color = props.color or TIN
	item.Material = props.material or Enum.Material.SmoothPlastic
	item.CanCollide = props.collide ~= false
	item.CanTouch = props.touch == true
	item.CanQuery = props.query ~= false
	item.CastShadow = props.shadow ~= false
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	if props.transparency ~= nil then
		item.Transparency = props.transparency
	end
	if props.shape ~= nil then
		item.Shape = props.shape
	end
	item.Parent = props.parent
	return item
end

local function prompt(host: BasePart, actionText: string, objectText: string)
	local interaction = Instance.new("ProximityPrompt")
	interaction.ActionText = actionText
	interaction.ObjectText = objectText
	interaction.KeyboardKeyCode = Enum.KeyCode.E
	interaction.HoldDuration = 0
	interaction.MaxActivationDistance = 10
	interaction.RequiresLineOfSight = false
	interaction.Parent = host
	return interaction
end

local function light(host: BasePart, color: Color3, brightness: number, range: number)
	local lamp = Instance.new("PointLight")
	lamp.Color = color
	lamp.Brightness = brightness
	lamp.Range = range
	lamp.Shadows = false
	lamp.Parent = host
	return lamp
end

local function shiftTree(root: Instance, delta: Vector3)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CFrame = descendant.CFrame + delta
		end
	end
end

local function rotateAbout(cf: CFrame, pivot: Vector3, yaw: number): CFrame
	local spin = CFrame.new(pivot) * CFrame.Angles(0, yaw, 0) * CFrame.new(-pivot)
	return spin * cf
end

local function teleportPlayer(player: Player, destination: string)
	local key = tostring(player.UserId)
	local now = os.clock()
	local previous = state.hops[key]
	if type(previous) == "number" and now - previous < 1.5 then
		return
	end
	local cf = nil
	if destination == "Lobby" then
		cf = state.lobbySpawn
	elseif destination == "Gacha" then
		cf = state.gachaSpawn
	elseif destination == "Racetrack" then
		cf = state.raceSpawn
	elseif destination == "Garage" then
		local bay = state.byPlayer[key]
		if bay == nil then
			bay = PrivateGarage.claim(key)
		end
		if bay ~= nil and bay.spawn ~= nil then
			cf = bay.spawn.CFrame + Vector3.new(0, 5, 0)
		end
	end
	if cf == nil then
		return
	end
	state.hops[key] = now
	local character = player.Character
	if character ~= nil then
		character:PivotTo(cf)
	end
end

local function hookDoor(inst: Instance)
	if hooked[inst] == true then
		return
	end
	local destination = inst:GetAttribute("Destination")
	if destination ~= "Lobby" and destination ~= "Garage" and destination ~= "Gacha" and destination ~= "Racetrack" then
		return
	end
	hooked[inst] = true
	if inst:IsA("ProximityPrompt") then
		inst.Triggered:Connect(function(player)
			teleportPlayer(player, destination)
		end)
	elseif inst:IsA("BasePart") then
		inst.Touched:Connect(function(hit)
			local character = hit.Parent
			if character == nil then
				return
			end
			local player = Players:GetPlayerFromCharacter(character)
			if player ~= nil then
				teleportPlayer(player, destination)
			end
		end)
	end
end

local function hookTree(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		hookDoor(descendant)
	end
end

local function showModel(root: Instance, shown: boolean)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if descendant:GetAttribute("RestTransparency") == nil then
				descendant:SetAttribute("RestTransparency", descendant.Transparency)
				descendant:SetAttribute("RestCollide", descendant.CanCollide)
			end
			if shown then
				descendant.Transparency = descendant:GetAttribute("RestTransparency")
				descendant.CanCollide = descendant:GetAttribute("RestCollide") == true
				descendant.CanQuery = true
			else
				descendant.Transparency = 1
				descendant.CanCollide = false
				descendant.CanQuery = false
			end
		elseif descendant:IsA("ProximityPrompt")
			or descendant:IsA("Light")
			or descendant:IsA("BillboardGui")
			or descendant:IsA("SurfaceGui")
		then
			descendant.Enabled = shown
		end
	end
end

local function applyTier(bay, rank: number)
	if bay.tier == rank then
		return
	end
	bay.tier = rank
	local floor = bay.model:FindFirstChild("GarageFloor")
	if floor ~= nil and floor:IsA("BasePart") then
		if floor:GetAttribute("BaseColor") == nil then
			floor:SetAttribute("BaseColor", floor.Color)
		end
		if rank >= 3 then
			floor.Color = Color3.fromRGB(78, 80, 84)
		elseif rank >= 2 then
			floor.Color = Color3.fromRGB(54, 56, 60)
		else
			floor.Color = floor:GetAttribute("BaseColor")
		end
	end
	for _, descendant in ipairs(bay.model:GetDescendants()) do
		if descendant:IsA("PointLight") and descendant:GetAttribute("HomeLight") == true then
			if descendant:GetAttribute("BaseBrightness") == nil then
				descendant:SetAttribute("BaseBrightness", descendant.Brightness)
			end
			local base = descendant:GetAttribute("BaseBrightness")
			if rank >= 3 then
				descendant.Brightness = base + 0.2
			elseif rank >= 2 then
				descendant.Brightness = base + 0.1
			else
				descendant.Brightness = base
			end
		end
	end
	for _, child in ipairs(bay.model:GetChildren()) do
		local unlock = child:GetAttribute("UnlockRank")
		if type(unlock) == "number" then
			showModel(child, rank >= unlock)
		end
	end
end

local function addReadout(glass: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "RaceReadout"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 42
	gui.LightInfluence = 0
	gui.Parent = glass

	local function label(name: string, text: string, position: UDim2, size: UDim2, color: Color3, font: Enum.Font)
		local item = Instance.new("TextLabel")
		item.Name = name
		item.BackgroundTransparency = 1
		item.BorderSizePixel = 0
		item.Position = position
		item.Size = size
		item.Font = font
		item.Text = text
		item.TextColor3 = color
		item.TextScaled = true
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.TextYAlignment = Enum.TextYAlignment.Center
		item.Parent = gui
		return item
	end

	label("Title", "RACE DATA", UDim2.fromScale(0.05, 0.045), UDim2.fromScale(0.4, 0.09), Color3.new(1, 1, 1), Enum.Font.GothamBold)
	label("RaceStatusCaption", "LAP STATUS", UDim2.fromScale(0.46, 0.03), UDim2.fromScale(0.22, 0.055), Color3.fromRGB(168, 176, 188), Enum.Font.Gotham)
	local status = label("RaceStatus", "--", UDim2.fromScale(0.68, 0.045), UDim2.fromScale(0.26, 0.09), Color3.new(1, 1, 1), Enum.Font.GothamBold)
	status.BackgroundTransparency = 0
	status.BackgroundColor3 = Color3.fromRGB(70, 78, 90)
	status.TextXAlignment = Enum.TextXAlignment.Center
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = status

	local dim = Color3.fromRGB(168, 176, 188)
	local function column(x: number, rows)
		for index, row in ipairs(rows) do
			local y = 0.2 + (index - 1) * 0.25
			label(row[1] .. "Caption", row[2], UDim2.fromScale(x, y), UDim2.fromScale(0.4, 0.07), dim, Enum.Font.Gotham)
			label(row[1], "--", UDim2.fromScale(x, y + 0.07), UDim2.fromScale(0.4, 0.12), Color3.fromRGB(244, 246, 248), Enum.Font.GothamBold)
		end
	end

	column(0.05, {
		{ "CurrentCar", "CURRENT CAR" },
		{ "Power", "POWER" },
		{ "RankBoost", "T RANK BOOST" },
	})
	column(0.52, {
		{ "CurrentLap", "CURRENT LAP" },
		{ "BestLap", "BEST LAP" },
		{ "LapsCompleted", "LAPS COMPLETED" },
	})
end

local function zonePad(parent: Instance, name: string, position: Vector3, padSize: Vector3)
	part({
		name = name .. "Pad",
		size = padSize,
		cframe = CFrame.new(position.X, 0.6, position.Z),
		color = SLATE,
		material = Enum.Material.SmoothPlastic,
		parent = parent,
	})
end

function PrivateGarage.buildTemplate(parent: Instance): Model
	local bay = Instance.new("Model")
	bay.Name = "PrivateGarage"
	bay:SetAttribute("BayIndex", 0)
	bay.Parent = parent

	local function add(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?, transparency: number?)
		return part({
			name = name,
			size = size,
			cframe = cf,
			color = color,
			material = material,
			collide = collide,
			transparency = transparency,
			parent = bay,
		})
	end

	-- 地板頂面 y=0.8。牆腳埋進地板。屋頂下緣 18.8，實心鐵皮。
	add("GarageFloor", Vector3.new(68, 0.4, 64), CFrame.new(34, 0.6, 32), SLATE, Enum.Material.SmoothPlastic, true)
	local wallH = 18.4
	local wallY = 9.6
	add("WallWest", Vector3.new(0.6, wallH, 64), CFrame.new(0.3, wallY, 32), TIN, Enum.Material.CorrodedMetal, true)
	add("WallSouth", Vector3.new(68, wallH, 0.6), CFrame.new(34, wallY, 0.3), TIN_DARK, Enum.Material.CorrodedMetal, true)
	add("WallNorth", Vector3.new(68, wallH, 0.6), CFrame.new(34, wallY, 63.7), TIN, Enum.Material.CorrodedMetal, true)
	add("WallEast", Vector3.new(0.6, wallH, 64), CFrame.new(67.7, wallY, 32), TIN_DARK, Enum.Material.CorrodedMetal, true)

	local function rib(cf: CFrame, size: Vector3)
		add("TinRib", size, cf, Color3.fromRGB(146, 150, 146), Enum.Material.CorrodedMetal, false)
	end
	for z = 6, 58, 8 do
		rib(CFrame.new(0.78, 9.2, z), Vector3.new(0.16, 16.4, 0.4))
		rib(CFrame.new(67.28, 9.2, z), Vector3.new(0.16, 16.4, 0.4))
	end
	for x = 8, 60, 10 do
		rib(CFrame.new(x, 9.2, 0.95), Vector3.new(0.4, 16.4, 0.16))
		rib(CFrame.new(x, 9.2, 63.05), Vector3.new(0.4, 16.4, 0.16))
	end
	add("RustPatchA", Vector3.new(0.08, 2.4, 3.2), CFrame.new(0.72, 4.2, 18), RUST, Enum.Material.CorrodedMetal, false)
	add("RustPatchB", Vector3.new(2.6, 1.6, 0.08), CFrame.new(22, 11.2, 0.95), RUST, Enum.Material.CorrodedMetal, false)
	add("RustPatchC", Vector3.new(0.08, 1.8, 2.2), CFrame.new(67.28, 5.4, 58), RUST, Enum.Material.CorrodedMetal, false)

	local roof = add("GarageRoof", Vector3.new(69.4, 0.4, 65.4), CFrame.new(34, 19, 32), TIN_DARK, Enum.Material.CorrodedMetal, true)
	for x = 8, 60, 8 do
		add("RoofRib", Vector3.new(0.22, 0.12, 62), CFrame.new(x, 18.55, 32), TIN, Enum.Material.CorrodedMetal, false)
	end

	local door = Instance.new("Model")
	door.Name = "GarageExit"
	door.Parent = bay
	local doorY = 4.4
	local doorZ = 50
	local leaf = add("ExitDoor", Vector3.new(0.16, 7.2, 3.2), CFrame.new(67.12, doorY, doorZ), Color3.fromRGB(236, 226, 210), Enum.Material.SmoothPlastic, true)
	leaf.Parent = door
	leaf:SetAttribute("Station", "GarageExit")
	leaf:SetAttribute("Destination", "Lobby")
	local doorPrompt = prompt(leaf, "Enter", "Lobby")
	doorPrompt:SetAttribute("Destination", "Lobby")
	local cream = Color3.fromRGB(248, 244, 236)
	local panel = Color3.fromRGB(196, 154, 108)
	local bronze = Color3.fromRGB(92, 62, 40)
	local function doorBit(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material)
		local item = add(name, size, cf, color, material, false)
		item.Parent = door
		return item
	end
	doorBit("DoorFrameL", Vector3.new(0.2, 7.55, 0.18), CFrame.new(67.22, doorY, doorZ - 1.74), cream, Enum.Material.SmoothPlastic)
	doorBit("DoorFrameR", Vector3.new(0.2, 7.55, 0.18), CFrame.new(67.22, doorY, doorZ + 1.74), cream, Enum.Material.SmoothPlastic)
	doorBit("DoorFrameT", Vector3.new(0.2, 0.18, 3.66), CFrame.new(67.22, 8.16, doorZ), cream, Enum.Material.SmoothPlastic)
	doorBit("DoorSill", Vector3.new(0.2, 0.14, 3.66), CFrame.new(67.22, 0.87, doorZ), Color3.fromRGB(74, 58, 42), Enum.Material.Wood).CanCollide = true
	doorBit("DoorPanelTop", Vector3.new(0.05, 1.7, 2.2), CFrame.new(67.01, 6.35, doorZ), panel, Enum.Material.Wood)
	doorBit("DoorPanelLow", Vector3.new(0.05, 2.55, 2.2), CFrame.new(67.01, 2.95, doorZ), panel, Enum.Material.Wood)
	local window = doorBit("DoorWindow", Vector3.new(0.04, 0.85, 1.2), CFrame.new(66.96, 6.45, doorZ), Color3.fromRGB(198, 224, 230), Enum.Material.Glass)
	window.Transparency = 0.28
	doorBit("DoorMuntinH", Vector3.new(0.03, 0.05, 1.2), CFrame.new(66.93, 6.45, doorZ), cream, Enum.Material.SmoothPlastic)
	doorBit("DoorMuntinV", Vector3.new(0.03, 0.85, 0.05), CFrame.new(66.93, 6.45, doorZ), cream, Enum.Material.SmoothPlastic)
	doorBit("DoorHingeT", Vector3.new(0.08, 0.42, 0.12), CFrame.new(67.02, 7.15, 51.42), bronze, Enum.Material.Metal)
	doorBit("DoorHingeB", Vector3.new(0.08, 0.42, 0.12), CFrame.new(67.02, 1.7, 51.42), bronze, Enum.Material.Metal)
	doorBit("DoorRose", Vector3.new(0.05, 0.32, 0.2), CFrame.new(66.96, 4.15, 48.95), bronze, Enum.Material.Metal)
	doorBit("DoorLever", Vector3.new(0.07, 0.07, 0.55), CFrame.new(66.9, 4.15, 48.62), bronze, Enum.Material.Metal)
	local plaque = doorBit("DoorPlaque", Vector3.new(0.04, 0.42, 1.15), CFrame.new(66.95, 5.15, doorZ), cream, Enum.Material.SmoothPlastic)
	local doorGui = Instance.new("SurfaceGui")
	doorGui.Name = "DoorLabel"
	doorGui.Face = Enum.NormalId.Left
	doorGui.LightInfluence = 0
	doorGui.Parent = plaque
	local doorText = Instance.new("TextLabel")
	doorText.BackgroundTransparency = 1
	doorText.Size = UDim2.fromScale(1, 1)
	doorText.Font = Enum.Font.Gotham
	doorText.Text = "Lobby"
	doorText.TextColor3 = Color3.fromRGB(72, 58, 44)
	doorText.TextScaled = true
	doorText.Parent = doorGui

	local screen = Instance.new("Model")
	screen.Name = "DataScreen"
	screen.Parent = bay
	local screenAt = Vector3.new(38, 4.6, 14)
	local screenLook = CFrame.lookAt(screenAt, Vector3.new(67.5, 4.6, 50))
	local function screenPart(name: string, size: Vector3, localCf: CFrame, color: Color3, material: Enum.Material, collide: boolean?)
		local item = add(name, size, screenLook * localCf, color, material, collide == true)
		item.Parent = screen
		return item
	end
	screenPart("ScreenPostL", Vector3.new(0.28, 4.4, 0.28), CFrame.new(-2.55, -2.15, 0.25), STEEL, Enum.Material.Metal, true)
	screenPart("ScreenPostR", Vector3.new(0.28, 4.4, 0.28), CFrame.new(2.55, -2.15, 0.25), STEEL, Enum.Material.Metal, true)
	screenPart("ScreenBezel", Vector3.new(5.7, 4.15, 0.24), CFrame.new(0, 0, 0.22), STEEL, Enum.Material.Metal, false)
	local glass = screenPart("ScreenGlass", Vector3.new(5.2, 3.6, 0.12), CFrame.new(), INK, Enum.Material.SmoothPlastic, false)
	addReadout(glass)
	light(glass, Color3.fromRGB(180, 210, 255), 0.55, 12)

	local startPose = RaceConfig.sample(0)
	local origin = PrivateGarage.TrackOrigin
	local rel = Vector3.new(startPose.x - origin.X, 0, startPose.z - origin.Z)
	local spin = CFrame.Angles(0, PrivateGarage.TrackYaw, 0)
	local turned = spin:VectorToWorldSpace(rel)
	local look = spin:VectorToWorldSpace(Vector3.new(startPose.lookX, 0, startPose.lookZ))
	local inward = Vector3.new(-look.Z, 0, look.X)
	if inward.Magnitude > 0.01 then
		inward = inward.Unit
	else
		inward = Vector3.new(1, 0, 0)
	end
	local buttonAt = PrivateGarage.GarageTrackCenter + turned - inward * 8.4
	local stand = add("TestButtonStand", Vector3.new(0.62, 1.35, 0.62), CFrame.new(buttonAt.X, 1.475, buttonAt.Z), STEEL, Enum.Material.Metal, true)
	local housing = add("TestButtonHousing", Vector3.new(0.92, 0.14, 0.92), CFrame.new(buttonAt.X, 2.2, buttonAt.Z), STEEL, Enum.Material.Metal, true)
	local testPad = add("TestPad", Vector3.new(0.2, 0.72, 0.72), CFrame.new(buttonAt.X, 2.38, buttonAt.Z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 122, 48), Enum.Material.SmoothPlastic, true)
	testPad.Shape = Enum.PartType.Cylinder
	testPad:SetAttribute("Station", "TestLap")
	prompt(testPad, "Choose Car", "Test Lap")
	stand.Parent = bay
	housing.Parent = bay

	local bench = Instance.new("Model")
	bench.Name = "UpgradeBench"
	bench.Parent = bay
	local benchAt = Vector3.new(48, 2.5, 52.6)
	local top = add("BenchTop", Vector3.new(9.4, 0.28, 4.6), CFrame.new(benchAt), WOOD, Enum.Material.Wood, true)
	top.Parent = bench
	top:SetAttribute("Station", "UpgradeBench")
	bench:SetAttribute("UnlockRank", 1)
	prompt(top, "Upgrade", "Upgrade Bench")
	for _, corner in ipairs({
		Vector3.new(-4.2, -1.9),
		Vector3.new(4.2, -1.9),
		Vector3.new(-4.2, 1.9),
		Vector3.new(4.2, 1.9),
	}) do
		local foot = add("BenchFoot", Vector3.new(0.55, 0.12, 0.55), CFrame.new(benchAt.X + corner.X, 0.9, benchAt.Z + corner.Y), STEEL, Enum.Material.Metal, true)
		foot.Parent = bench
		local leg = add("BenchLeg", Vector3.new(0.22, 1.45, 0.22), CFrame.new(benchAt.X + corner.X, 1.68, benchAt.Z + corner.Y), STEEL, Enum.Material.Metal, true)
		leg.Parent = bench
	end
	local cradle = add("BenchCradle", Vector3.new(2.8, 0.08, 1.35), CFrame.new(benchAt.X - 1.8, 2.72, benchAt.Z - 0.35), CREAM, Enum.Material.SmoothPlastic, false)
	cradle.Parent = bench
	local function tool(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material)
		local item = add(name, size, cf, color, material, false)
		item.Parent = bench
		return item
	end
	local function cyl(name: string, length: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material)
		local item = tool(name, Vector3.new(length, diameter, diameter), cf, color, material)
		item.Shape = Enum.PartType.Cylinder
		return item
	end
	local upright = CFrame.Angles(0, 0, math.rad(90))
	local tray = Vector3.new(benchAt.X + 2.15, 2.68, benchAt.Z + 1.15)
	local trayColor = Color3.fromRGB(24, 32, 44)
	local silver = Color3.fromRGB(226, 230, 234)
	local brass = Color3.fromRGB(214, 164, 52)
	tool("ToolTray", Vector3.new(2.7, 0.05, 1.45), CFrame.new(tray), trayColor, Enum.Material.SmoothPlastic)
	tool("TrayRimN", Vector3.new(2.7, 0.08, 0.05), CFrame.new(tray.X, tray.Y + 0.05, tray.Z + 0.7), Color3.fromRGB(64, 78, 96), Enum.Material.Metal)
	tool("TrayRimS", Vector3.new(2.7, 0.08, 0.05), CFrame.new(tray.X, tray.Y + 0.05, tray.Z - 0.7), Color3.fromRGB(64, 78, 96), Enum.Material.Metal)
	cyl("DriverHandle", 0.34, 0.09, CFrame.new(tray.X - 0.85, tray.Y + 0.08, tray.Z + 0.28), Color3.fromRGB(196, 42, 36), Enum.Material.SmoothPlastic)
	cyl("DriverShaft", 0.52, 0.028, CFrame.new(tray.X - 0.4, tray.Y + 0.07, tray.Z + 0.28), silver, Enum.Material.Metal)
	cyl("DriverTip", 0.08, 0.045, CFrame.new(tray.X - 0.1, tray.Y + 0.07, tray.Z + 0.28), Color3.fromRGB(18, 18, 20), Enum.Material.Metal)
	cyl("WrenchBar", 0.7, 0.06, CFrame.new(tray.X - 0.55, tray.Y + 0.08, tray.Z - 0.28), Color3.fromRGB(168, 198, 214), Enum.Material.Metal)
	cyl("WrenchHead", 0.04, 0.16, CFrame.new(tray.X - 0.95, tray.Y + 0.1, tray.Z - 0.28) * upright, Color3.fromRGB(46, 118, 168), Enum.Material.Metal)
	cyl("WrenchJaw", 0.04, 0.16, CFrame.new(tray.X - 0.15, tray.Y + 0.1, tray.Z - 0.28) * upright, Color3.fromRGB(46, 118, 168), Enum.Material.Metal)
	cyl("Battery", 0.28, 0.16, CFrame.new(tray.X + 0.55, tray.Y + 0.2, tray.Z + 0.22) * upright, Color3.fromRGB(186, 36, 42), Enum.Material.SmoothPlastic)
	cyl("BatteryCap", 0.05, 0.07, CFrame.new(tray.X + 0.55, tray.Y + 0.36, tray.Z + 0.22) * upright, brass, Enum.Material.Metal)
	cyl("BatteryB", 0.28, 0.16, CFrame.new(tray.X + 0.82, tray.Y + 0.2, tray.Z + 0.22) * upright, Color3.fromRGB(36, 92, 186), Enum.Material.SmoothPlastic)
	cyl("BatteryCapB", 0.05, 0.07, CFrame.new(tray.X + 0.82, tray.Y + 0.36, tray.Z + 0.22) * upright, silver, Enum.Material.Metal)
	for index = 0, 3 do
		local screwX = tray.X + 0.35 + index * 0.18
		cyl("Screw" .. index, 0.16, 0.045, CFrame.new(screwX, tray.Y + 0.12, tray.Z - 0.32) * upright, Color3.fromRGB(120, 92, 48), Enum.Material.Metal)
		cyl("ScrewHead" .. index, 0.03, 0.08, CFrame.new(screwX, tray.Y + 0.2, tray.Z - 0.32) * upright, brass, Enum.Material.Metal)
	end
	light(top, Color3.fromRGB(255, 214, 160), 0.85, 14)

	local podium = Instance.new("Model")
	podium.Name = "BestCarPodium"
	podium:SetAttribute("UnlockRank", 2)
	podium.Parent = bay
	local podiumAt = Vector3.new(52, 0, 22)
	local stone = Color3.fromRGB(214, 216, 220)
	local stoneDark = Color3.fromRGB(186, 190, 196)
	local function disc(name: string, diameter: number, thick: number, y: number, color: Color3, material: Enum.Material, collide: boolean, transparency: number?)
		local item = add(name, Vector3.new(thick, diameter, diameter), CFrame.new(podiumAt.X, y, podiumAt.Z) * upright, color, material, collide, transparency)
		item.Shape = Enum.PartType.Cylinder
		item.Parent = podium
		return item
	end
	disc("PodiumBase", 6.2, 0.22, 0.91, stone, Enum.Material.SmoothPlastic, true)
	disc("PodiumStep", 4.7, 0.16, 1.1, stoneDark, Enum.Material.SmoothPlastic, true)
	local showcase = disc("ShowcaseTop", 3.35, 0.12, 1.24, stone, Enum.Material.SmoothPlastic, true)
	local glow = disc("PodiumGlow", 5.55, 0.035, 1.03, Color3.fromRGB(150, 186, 214), Enum.Material.Neon, false, 0.78)
	glow.CastShadow = false
	light(glow, Color3.fromRGB(150, 186, 214), 0.05, 3.2)
	local empty = Instance.new("BillboardGui")
	empty.Name = "EmptySign"
	empty.Size = UDim2.fromOffset(120, 28)
	empty.StudsOffset = Vector3.new(0, 1.35, 0)
	empty.MaxDistance = 36
	empty.LightInfluence = 0
	empty.Parent = showcase
	local emptyText = Instance.new("TextLabel")
	emptyText.BackgroundTransparency = 1
	emptyText.Size = UDim2.fromScale(1, 1)
	emptyText.Font = Enum.Font.GothamBold
	emptyText.Text = "EMPTY"
	emptyText.TextColor3 = Color3.fromRGB(232, 236, 240)
	emptyText.TextStrokeTransparency = 0.45
	emptyText.TextScaled = true
	emptyText.Parent = empty

	local fusion = Instance.new("Model")
	fusion.Name = "CarFusion"
	fusion:SetAttribute("UnlockRank", 3)
	fusion.Parent = bay
	local fusionLook = CFrame.lookAt(Vector3.new(60, 1.55, 58), Vector3.new(46, 1.55, 46))
	local function fuse(name: string, size: Vector3, localCf: CFrame, color: Color3, material: Enum.Material, collide: boolean?)
		local item = add(name, size, fusionLook * localCf, color, material, collide == true)
		item.Parent = fusion
		return item
	end
	local graphite = Color3.fromRGB(42, 44, 48)
	local copper = Color3.fromRGB(176, 112, 58)
	fuse("FusionPlinth", Vector3.new(2.2, 0.16, 1.45), CFrame.new(0, -0.7, 0), graphite, Enum.Material.Metal, true)
	local fusionBody = fuse("FusionBody", Vector3.new(1.28, 1.12, 0.86), CFrame.new(), graphite, Enum.Material.Metal, true)
	fusionBody:SetAttribute("Station", "CarFusion")
	prompt(fusionBody, "Open", "Car Fusion")
	fuse("FusionBand", Vector3.new(1.36, 0.08, 0.94), CFrame.new(0, 0.28, 0), copper, Enum.Material.Metal, false)
	fuse("FusionHopper", Vector3.new(0.62, 0.22, 0.48), CFrame.new(0, 0.67, 0), Color3.fromRGB(58, 60, 64), Enum.Material.Metal, false)
	for _, side in ipairs({ -1, 1 }) do
		local chamber = fuse(
			"FusionChamber",
			Vector3.new(0.16, 0.34, 0.34),
			CFrame.new(side * 0.32, 0.02, -0.4) * upright,
			Color3.fromRGB(214, 148, 64),
			Enum.Material.Glass,
			false
		)
		chamber.Transparency = 0.4
		chamber.Shape = Enum.PartType.Cylinder
	end
	local dial = fuse("FusionDial", Vector3.new(0.06, 0.16, 0.16), CFrame.new(0, -0.22, -0.46) * CFrame.Angles(0, math.rad(90), 0), copper, Enum.Material.Metal, false)
	dial.Shape = Enum.PartType.Cylinder
	local fusionSign = fuse("FusionSign", Vector3.new(1.05, 0.26, 0.06), CFrame.new(0, 0.95, 0), Color3.fromRGB(28, 24, 22), Enum.Material.SmoothPlastic, false)
	local fusionGui = Instance.new("SurfaceGui")
	fusionGui.Name = "FusionLabel"
	fusionGui.Face = Enum.NormalId.Front
	fusionGui.LightInfluence = 0
	fusionGui.Parent = fusionSign
	local fusionText = Instance.new("TextLabel")
	fusionText.BackgroundTransparency = 1
	fusionText.Size = UDim2.fromScale(1, 1)
	fusionText.Font = Enum.Font.GothamBold
	fusionText.Text = "CAR FUSION"
	fusionText.TextColor3 = Color3.fromRGB(232, 196, 140)
	fusionText.TextScaled = true
	fusionText.Parent = fusionGui

	local trim = Instance.new("Model")
	trim.Name = "WorkshopTrim"
	trim:SetAttribute("UnlockRank", 2)
	trim.Parent = bay
	local skirt = Color3.fromRGB(92, 96, 102)
	local function skirtPart(name: string, size: Vector3, cf: CFrame)
		local item = add(name, size, cf, skirt, Enum.Material.Metal, false)
		item.Parent = trim
		return item
	end
	skirtPart("SkirtSouth", Vector3.new(62, 0.28, 0.12), CFrame.new(34, 1.02, 0.95))
	skirtPart("SkirtNorth", Vector3.new(62, 0.28, 0.12), CFrame.new(34, 1.02, 63.05))
	skirtPart("SkirtWest", Vector3.new(0.12, 0.28, 58), CFrame.new(0.95, 1.02, 32))
	skirtPart("SkirtEastA", Vector3.new(0.12, 0.28, 42), CFrame.new(67.05, 1.02, 24))
	skirtPart("SkirtEastB", Vector3.new(0.12, 0.28, 10), CFrame.new(67.05, 1.02, 58))

	local studio = Instance.new("Model")
	studio.Name = "StudioTrim"
	studio:SetAttribute("UnlockRank", 3)
	studio.Parent = bay
	local function cabinet(name: string, cf: CFrame)
		local box = add(name, Vector3.new(3.4, 1.35, 0.22), cf, Color3.fromRGB(64, 68, 74), Enum.Material.Metal, false)
		box.Parent = studio
		local rail = add(name .. "Rail", Vector3.new(3.15, 0.06, 0.08), cf * CFrame.new(0, 0.42, -0.12), copper, Enum.Material.Metal, false)
		rail.Parent = studio
	end
	cabinet("StudioCabinetA", CFrame.new(14, 4.4, 63.15))
	cabinet("StudioCabinetB", CFrame.new(28, 4.4, 63.15))

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Size = Vector3.new(4, 0.08, 4)
	spawn.Anchored = true
	spawn.Neutral = false
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.CastShadow = false
	spawn.Color = SLATE
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.CFrame = CFrame.lookAt(Vector3.new(58, 0.5, 36), Vector3.new(40, 0.5, 36))
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = bay

	local function homeLight(x: number, z: number)
		local spin = CFrame.Angles(0, 0, math.rad(90))
		local canopy = add("LightCanopy", Vector3.new(0.1, 1.25, 1.25), CFrame.new(x, 18.72, z) * spin, Color3.fromRGB(248, 244, 236), Enum.Material.SmoothPlastic, false)
		canopy.Shape = Enum.PartType.Cylinder
		local shade = add("LampShade", Vector3.new(0.38, 1.85, 1.85), CFrame.new(x, 18.18, z) * spin, Color3.fromRGB(255, 252, 247), Enum.Material.Fabric, false)
		shade.Shape = Enum.PartType.Cylinder
		local glow = add("LampGlow", Vector3.new(0.05, 1.05, 1.05), CFrame.new(x, 18.16, z) * spin, Color3.fromRGB(255, 246, 228), Enum.Material.Neon, false)
		glow.Shape = Enum.PartType.Cylinder
		glow.Transparency = 0.2
		local home = light(glow, Color3.fromRGB(255, 248, 236), 0.9, 26)
		home:SetAttribute("HomeLight", true)
	end
	homeLight(20, 32)
	homeLight(48, 52)
	homeLight(36, 18)
	homeLight(54, 34)
	light(roof, Color3.fromRGB(255, 248, 240), 0.16, 34)

	for _, descendant in ipairs(bay:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local shell = nil
			if descendant.Name == "TinRib" or descendant.Name == "RoofRib" then
				shell = "Rib"
			elseif descendant.Name == "GarageRoof" then
				shell = "Ceiling"
			elseif descendant.Name == "WallWest"
				or descendant.Name == "WallEast"
				or descendant.Name == "WallNorth"
				or descendant.Name == "WallSouth"
			then
				shell = "Metal"
			elseif descendant.Name == "GarageFloor" then
				shell = "Floor"
			elseif string.sub(descendant.Name, 1, 9) == "RustPatch" then
				shell = "Rust"
			end
			if shell ~= nil then
				descendant:SetAttribute("GarageShell", shell)
			end
		end
	end

	showModel(bench, false)
	showModel(podium, false)
	showModel(fusion, false)
	showModel(trim, false)
	showModel(studio, false)
	hookTree(bay)
	return bay
end

local function buildBooster(parent: Instance)
	local pose = RaceConfig.sample(PrivateGarage.BoosterAlong)
	local basis = CarVisualFactory.poseCFrame(pose, 0, 0)
	local model = Instance.new("Model")
	model.Name = "TrackBooster"
	model.Parent = parent
	local rubber = Color3.fromRGB(28, 28, 30)
	local rubberDark = Color3.fromRGB(14, 14, 16)
	local housing = Color3.fromRGB(54, 56, 60)
	local metal = Color3.fromRGB(168, 172, 178)
	local bolt = Color3.fromRGB(214, 218, 222)
	local orange = Color3.fromRGB(255, 132, 28)
	local orangeDark = Color3.fromRGB(186, 72, 16)

	local function add(name: string, size: Vector3, localCf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?, spin: number?, accentAt: number?)
		local item = part({
			name = name,
			size = size,
			cframe = basis * localCf,
			color = color,
			material = material,
			parent = model,
			collide = false,
			shape = shape,
		})
		if spin ~= nil then
			item:SetAttribute("BoosterSpin", spin)
		end
		if accentAt ~= nil then
			item:SetAttribute("AccentAt", accentAt)
			item.Transparency = 1
		end
		return item
	end

	for _, side in ipairs({ -1, 1 }) do
		-- 輪軸朝上。左右反向轉，貼著車身的那一側都往車頭推，車子從中間被夾出去。
		local spin = if side < 0 then 1 else -1
		local radius = 0.56
		local reach = 0.64 + radius
		local curbX = 1.06
		local shoe = CFrame.new(side * curbX, 0.36, 0.15)
		local upright = CFrame.Angles(0, 0, math.rad(90))
		local wheel = CFrame.new(side * reach, 0.72, 0) * upright
		add("BoosterRoller", Vector3.new(0.42, radius * 2, radius * 2), wheel, rubber, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, spin, nil)
		add("BoosterTread", Vector3.new(0.18, radius * 2 - 0.12, radius * 2 - 0.12), wheel, rubberDark, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, spin, nil)
		add("BoosterHub", Vector3.new(0.06, 0.34, 0.34), wheel * CFrame.new(0.2, 0, 0), metal, Enum.Material.Metal, Enum.PartType.Cylinder, spin, nil)
		add("BoosterCap", Vector3.new(0.05, 0.16, 0.16), wheel * CFrame.new(0.225, 0, 0), bolt, Enum.Material.Metal, Enum.PartType.Cylinder, spin, nil)
		add("BoosterAxle", Vector3.new(0.46, 0.1, 0.1), wheel * CFrame.new(0.16, 0, 0), metal, Enum.Material.Metal, Enum.PartType.Cylinder, spin, nil)
		add("BoosterCheek", Vector3.new(0.05, radius * 1.35, radius * 1.35), wheel * CFrame.new(0.16, 0, 0), orange, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, spin, nil)
		add("BoosterAccent", Vector3.new(0.04, radius * 1.7, radius * 1.7), wheel * CFrame.new(0.2, 0, 0), orangeDark, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, spin, 5)
		add("BoosterSpoke", Vector3.new(0.05, radius * 1.75, 0.08), wheel * CFrame.new(0.22, 0, 0), metal, Enum.Material.Metal, nil, spin, nil)
		add("BoosterSpoke", Vector3.new(0.05, 0.08, radius * 1.75), wheel * CFrame.new(0.22, 0, 0), metal, Enum.Material.Metal, nil, spin, nil)
		-- 底座坐在護邊頂面。柱子從底座升到輪子上方，軸只穿過輪心，不再插入路面。
		add("BoosterShoe", Vector3.new(0.22, 0.06, 2.7), shoe, housing, Enum.Material.Metal, nil, nil, nil)
		for _, boltAt in ipairs({
			Vector3.new(0.06, 0.045, -1.05),
			Vector3.new(-0.06, 0.045, -1.05),
			Vector3.new(0.06, 0.045, 1.2),
			Vector3.new(-0.06, 0.045, 1.2),
		}) do
			add("BoosterBolt", Vector3.new(0.04, 0.045, 0.045), shoe * CFrame.new(boltAt) * upright, bolt, Enum.Material.Metal, Enum.PartType.Cylinder, nil, nil)
		end
		for _, along in ipairs({ -0.78, 0.78 }) do
			add("BoosterPost", Vector3.new(0.11, 0.66, 0.11), CFrame.new(side * curbX, 0.72, along), metal, Enum.Material.Metal, nil, nil, nil)
		end
		add("BoosterBeam", Vector3.new(0.11, 0.08, 1.68), CFrame.new(side * curbX, 1.02, 0), metal, Enum.Material.Metal, nil, nil, nil)
		add("BoosterArm", Vector3.new(0.36, 0.08, 0.12), CFrame.new(side * 1.13, 1.02, 0), metal, Enum.Material.Metal, nil, nil, nil)
		local motor = CFrame.new(side * curbX, 0.55, 1.18)
		add("BoosterHousing", Vector3.new(0.2, 0.28, 0.36), motor, housing, Enum.Material.Metal, nil, nil, nil)
		add("BoosterPlate", Vector3.new(0.22, 0.04, 0.38), motor * CFrame.new(0, 0.16, 0), orange, Enum.Material.SmoothPlastic, nil, nil, nil)
		add("BoosterBell", Vector3.new(0.08, 0.22, 0.22), motor * CFrame.new(0, 0.02, 0.22) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(38, 40, 44), Enum.Material.Metal, Enum.PartType.Cylinder, nil, nil)
		for _, offset in ipairs({
			Vector3.new(0.06, 0.19, 0.1),
			Vector3.new(-0.06, 0.19, 0.1),
			Vector3.new(0.06, 0.19, -0.1),
			Vector3.new(-0.06, 0.19, -0.1),
		}) do
			add("BoosterBolt", Vector3.new(0.035, 0.04, 0.04), motor * CFrame.new(offset) * upright, bolt, Enum.Material.Metal, Enum.PartType.Cylinder, nil, nil)
		end
		for fin = -1, 1 do
			add("BoosterFin", Vector3.new(0.04, 0.2, 0.08), motor * CFrame.new(0.12 * side, 0.02, fin * 0.1), housing, Enum.Material.Metal, nil, nil, nil)
		end
	end
	add("BoosterAccent", Vector3.new(0.08, 0.04, 0.42), CFrame.new(0, 0.04, 0), orange, Enum.Material.SmoothPlastic, nil, nil, 8)
end

local function oldTestMarking(name: string): boolean
	if name == "RaceStart" or name == "RaceFinish" or name == "FinishPostL" or name == "FinishPostR" then
		return true
	end
	if string.sub(name, 1, 7) == "Chevron" then
		return true
	end
	return string.find(name, "Stripe", 1, true) ~= nil
end

function PrivateGarage.adoptTracks(folder: Instance, bay: Model)
	if bay:FindFirstChild("TestTrack") ~= nil then
		return
	end
	local track = folder:FindFirstChild("Track")
	if track == nil then
		return
	end
	local copy = track:Clone()
	copy.Name = "TestTrack"
	local stale = {}
	for _, descendant in ipairs(copy:GetDescendants()) do
		if descendant:IsA("BasePart") and (oldTestMarking(descendant.Name) or string.sub(descendant.Name, 1, 7) == "Support") then
			table.insert(stale, descendant)
		end
	end
	for _, descendant in ipairs(stale) do
		descendant:Destroy()
	end
	buildBooster(copy)
	local origin = PrivateGarage.TrackOrigin
	local delta = PrivateGarage.GarageTrackCenter - origin
	for _, descendant in ipairs(copy:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CFrame = rotateAbout(descendant.CFrame, origin, PrivateGarage.TrackYaw) + delta
		end
	end
	local oldCenter = 5.2
	local oldCurb = 0.62
	local newCenter = 2.0
	local newCurb = 0.28
	local oldLateral = oldCenter * 0.5 + oldCurb * 0.5 - 0.08
	local newLateral = newCenter * 0.5 + newCurb * 0.5 - 0.08
	for _, descendant in ipairs(copy:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local name = descendant.Name
			if string.find(name, "Deck", 1, true) ~= nil then
				descendant.Size = Vector3.new(newCenter, descendant.Size.Y, descendant.Size.Z)
			elseif string.find(name, "Shoulder", 1, true) ~= nil then
				local sign = if string.find(name, "ShoulderL", 1, true) ~= nil then -1 else 1
				local right = descendant.CFrame.RightVector
				local center = descendant.Position - right * (oldLateral * sign)
				descendant.Size = Vector3.new(newCurb, descendant.Size.Y, descendant.Size.Z)
				descendant.CFrame = (descendant.CFrame - descendant.Position) + (center + right * (newLateral * sign))
			end
		end
	end
	local oldSupports = {}
	for _, child in ipairs(copy:GetChildren()) do
		if string.sub(child.Name, 1, 7) == "Support" then
			table.insert(oldSupports, child)
		end
	end
	for _, child in ipairs(oldSupports) do
		child:Destroy()
	end
	local lap = RaceConfig.lapLength()
	local cursor = 0
	local supportIndex = 1
	while cursor < lap - 1 do
		local pose = RaceConfig.sample(cursor)
		local rel = Vector3.new(pose.x - origin.X, 0, pose.z - origin.Z)
		local spin = CFrame.Angles(0, PrivateGarage.TrackYaw, 0)
		local turned = spin:VectorToWorldSpace(rel)
		local pos = PrivateGarage.GarageTrackCenter + turned
		local foot = Instance.new("Part")
		foot.Name = "TestSupportFoot" .. supportIndex
		foot.Anchored = true
		foot.Size = Vector3.new(1.15, 0.16, 1.15)
		foot.CFrame = CFrame.new(pos.X, 0.86, pos.Z)
		foot.Color = STEEL
		foot.Material = Enum.Material.Metal
		foot.TopSurface = Enum.SurfaceType.Smooth
		foot.BottomSurface = Enum.SurfaceType.Smooth
		foot.Parent = copy
		local post = Instance.new("Part")
		post.Name = "TestSupport" .. supportIndex
		post.Anchored = true
		post.Size = Vector3.new(0.38, 0.94, 0.38)
		post.CFrame = CFrame.new(pos.X, 1.39, pos.Z)
		post.Color = STEEL
		post.Material = Enum.Material.Metal
		post.TopSurface = Enum.SurfaceType.Smooth
		post.BottomSurface = Enum.SurfaceType.Smooth
		post.Parent = copy
		local cap = Instance.new("Part")
		cap.Name = "TestSupportCap" .. supportIndex
		cap.Anchored = true
		cap.Size = Vector3.new(1.35, 0.08, 0.72)
		local look = spin:VectorToWorldSpace(Vector3.new(pose.lookX, 0, pose.lookZ))
		local capAt = Vector3.new(pos.X, 1.9, pos.Z)
		if look.Magnitude > 0.05 then
			cap.CFrame = CFrame.lookAt(capAt, capAt + look)
		else
			cap.CFrame = CFrame.new(capAt)
		end
		cap.Color = STEEL
		cap.Material = Enum.Material.Metal
		cap.TopSurface = Enum.SurfaceType.Smooth
		cap.BottomSurface = Enum.SurfaceType.Smooth
		cap.Parent = copy
		cursor += 8
		supportIndex += 1
	end
	copy.Parent = bay
	local shift = PrivateGarage.RaceShift
	for _, descendant in ipairs(track:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CFrame = descendant.CFrame + shift
		end
	end
end

local function rememberSpawns()
	local lobby = PrivateGarage.Zones.Lobby
	local gacha = PrivateGarage.Zones.Gacha
	local race = PrivateGarage.Zones.Racetrack
	state.lobbySpawn = CFrame.lookAt(Vector3.new(lobby.X, 4, lobby.Z - 6), Vector3.new(lobby.X, 4, lobby.Z + 12))
	state.gachaSpawn = CFrame.lookAt(Vector3.new(gacha.X, 4, gacha.Z + 14), Vector3.new(gacha.X, 4, gacha.Z))
	state.raceSpawn = CFrame.lookAt(Vector3.new(race.X + 8, 4, race.Z - 12), Vector3.new(race.X, 4, race.Z))
end

function PrivateGarage.buildZones(folder: Instance)
	local lobby = PrivateGarage.Zones.Lobby
	local gacha = PrivateGarage.Zones.Gacha
	local race = PrivateGarage.Zones.Racetrack
	zonePad(folder, "LobbyZone", lobby, Vector3.new(80, 0.4, 60))
	zonePad(folder, "GachaZone", gacha, Vector3.new(90, 0.4, 90))
	zonePad(folder, "RacetrackZone", race, Vector3.new(100, 0.4, 80))

	local function travelButton(name: string, x: number, objectText: string, destination: string)
		local spot = Vector3.new(x, 0, lobby.Z + 12)
		local stand = part({
			name = name .. "Stand",
			size = Vector3.new(0.62, 1.35, 0.62),
			cframe = CFrame.new(spot.X, 1.475, spot.Z),
			color = STEEL,
			material = Enum.Material.Metal,
			parent = folder,
		})
		local cap = part({
			name = name,
			size = Vector3.new(0.2, 0.72, 0.72),
			cframe = CFrame.new(spot.X, 2.38, spot.Z) * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(255, 122, 48),
			material = Enum.Material.SmoothPlastic,
			parent = folder,
		})
		cap.Shape = Enum.PartType.Cylinder
		cap:SetAttribute("Station", "GarageExit")
		cap:SetAttribute("Destination", destination)
		local travelPrompt = prompt(cap, "Enter", objectText)
		travelPrompt:SetAttribute("Destination", destination)
		local sign = part({
			name = name .. "Label",
			size = Vector3.new(1.8, 0.55, 0.08),
			cframe = CFrame.new(spot.X, 3.35, spot.Z),
			color = INK,
			material = Enum.Material.SmoothPlastic,
			collide = false,
			parent = folder,
		})
		local signGui = Instance.new("SurfaceGui")
		signGui.Face = Enum.NormalId.Front
		signGui.LightInfluence = 0
		signGui.Parent = sign
		local signText = Instance.new("TextLabel")
		signText.BackgroundTransparency = 1
		signText.Size = UDim2.fromScale(1, 1)
		signText.Font = Enum.Font.GothamBold
		signText.Text = string.upper(objectText)
		signText.TextColor3 = Color3.new(1, 1, 1)
		signText.TextScaled = true
		signText.Parent = signGui
		return stand
	end
	travelButton("LobbyGarage", lobby.X - 6, "Garage", "Garage")
	travelButton("LobbyGacha", lobby.X, "Gacha", "Gacha")
	travelButton("LobbyRace", lobby.X + 6, "Racetrack", "Racetrack")
	rememberSpawns()
	local function linkButton(name: string, position: Vector3, destination: string, objectText: string)
		local stand = part({
			name = name .. "Stand",
			size = Vector3.new(0.5, 1.2, 0.5),
			cframe = CFrame.new(position.X, 1.4, position.Z),
			color = STEEL,
			material = Enum.Material.Metal,
			parent = folder,
		})
		local cap = part({
			name = name,
			size = Vector3.new(0.18, 0.64, 0.64),
			cframe = CFrame.new(position.X, 2.1, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(255, 122, 48),
			material = Enum.Material.SmoothPlastic,
			parent = folder,
		})
		cap.Shape = Enum.PartType.Cylinder
		cap:SetAttribute("Station", "GarageExit")
		cap:SetAttribute("Destination", destination)
		local linkPrompt = prompt(cap, "Enter", objectText)
		linkPrompt:SetAttribute("Destination", destination)
		return stand
	end
	linkButton("GachaToLobby", Vector3.new(gacha.X + 6, 0, gacha.Z + 14), "Lobby", "Lobby")
	linkButton("RaceToLobby", Vector3.new(race.X + 14, 0, race.Z - 12), "Lobby", "Lobby")

	local kiosk = part({
		name = "RaceKiosk",
		size = Vector3.new(3.2, 1.6, 0.2),
		cframe = CFrame.new(race.X, 3.3, race.Z - 20),
		color = INK,
		material = Enum.Material.SmoothPlastic,
		collide = false,
		parent = folder,
	})
	kiosk:SetAttribute("Station", "RaceKiosk")
	prompt(kiosk, "Open Race", "Racetrack")
	local raceGui = Instance.new("SurfaceGui")
	raceGui.Face = Enum.NormalId.Front
	raceGui.LightInfluence = 0
	raceGui.Parent = kiosk
	local raceText = Instance.new("TextLabel")
	raceText.BackgroundTransparency = 1
	raceText.Size = UDim2.fromScale(1, 1)
	raceText.Font = Enum.Font.GothamBold
	raceText.Text = "RACE"
	raceText.TextColor3 = Color3.new(1, 1, 1)
	raceText.TextScaled = true
	raceText.Parent = raceGui
	part({
		name = "RaceKioskPost",
		size = Vector3.new(0.24, 2.2, 0.24),
		cframe = CFrame.new(race.X, 1.9, race.Z - 20),
		color = STEEL,
		material = Enum.Material.Metal,
		parent = folder,
	})
	hookTree(folder)
end

local function capture(model: Model, index: number, offset: Vector3)
	local function find(name: string): Instance?
		return model:FindFirstChild(name, true)
	end
	local screen = {}
	for _, name in ipairs({ "CurrentCar", "Power", "RankBoost", "RaceStatus", "CurrentLap", "BestLap", "LapsCompleted" }) do
		local item = find(name)
		if item ~= nil and item:IsA("TextLabel") then
			screen[name] = item
		end
	end
	local showcase = find("ShowcaseTop")
	local cradle = find("BenchCradle")
	local spawn = find("PlayerSpawn")
	local empty = find("EmptySign")
	return {
		model = model,
		index = index,
		offset = offset,
		spawn = if spawn ~= nil and spawn:IsA("SpawnLocation") then spawn else nil,
		screen = screen,
		showcase = if showcase ~= nil and showcase:IsA("BasePart") then showcase else nil,
		cradle = if cradle ~= nil and cradle:IsA("BasePart") then cradle else nil,
		emptySign = if empty ~= nil and empty:IsA("BillboardGui") then empty else nil,
		bestSignature = "",
		benchSignature = "",
		testSignature = "",
		bestModel = nil,
		benchModel = nil,
		testModel = nil,
	}
end

function PrivateGarage.isMounted(): boolean
	return state.template ~= nil and state.byIndex[0] ~= nil
end

function PrivateGarage.mount(folder: Instance, bay: Model, track: Instance?)
	-- 沿用已完成的場景時，傳送點和按 E 的連接不會跟著存檔。每次掛上房間都要重接。
	rememberSpawns()
	hookTree(folder)
	-- 乾淨複本只拿來複製房間。四間先排開，玩家進來只領空房，不再臨時往外疊。
	local pristine = bay:Clone()
	pristine.Name = "PrivateGarageTemplate"
	state.folder = folder
	state.template = pristine
	state.track = track
	state.byIndex[0] = capture(bay, 0, Vector3.zero)
	for index = 1, PrivateGarage.BayCount - 1 do
		local found = nil
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") and child.Name == "PrivateGarage" and child:GetAttribute("BayIndex") == index then
				found = child
				break
			end
		end
		local offset = Vector3.new(0, 0, index * STRIDE)
		local model = found
		if model == nil then
			model = pristine:Clone()
			model.Name = "PrivateGarage"
			model:SetAttribute("BayIndex", index)
			shiftTree(model, offset)
			model.Parent = folder
			hookTree(model)
		end
		state.byIndex[index] = capture(model, index, offset)
	end
end

function PrivateGarage.claim(playerKey: string)
	if type(playerKey) ~= "string" or playerKey == "" or state.template == nil or state.folder == nil then
		return nil
	end
	local existing = state.byPlayer[playerKey]
	if existing ~= nil then
		return existing
	end
	local index = 0
	while index < PrivateGarage.BayCount do
		local slot = state.byIndex[index]
		if slot == nil or slot.owner == nil then
			break
		end
		index += 1
	end
	local bay = state.byIndex[index]
	if index >= PrivateGarage.BayCount or bay == nil then
		return nil
	end
	bay.owner = playerKey
	bay.model:SetAttribute("OwnerKey", playerKey)
	state.byPlayer[playerKey] = bay
	return bay
end

local function clearVisual(bay, field: string, signatureField: string)
	local model = bay[field]
	if model ~= nil then
		model:Destroy()
		bay[field] = nil
	end
	bay[signatureField] = "empty"
	if field == "testModel" then
		bay.testWheels = nil
		bay.testDust = nil
		bay.testTrail = nil
	end
end

function PrivateGarage.release(playerKey: string)
	local bay = state.byPlayer[playerKey]
	if bay == nil then
		return
	end
	state.byPlayer[playerKey] = nil
	bay.owner = nil
	if bay.model ~= nil then
		bay.model:SetAttribute("OwnerKey", nil)
	end
	clearVisual(bay, "bestModel", "bestSignature")
	clearVisual(bay, "benchModel", "benchSignature")
	clearVisual(bay, "testModel", "testSignature")
	if bay.emptySign ~= nil then
		bay.emptySign.Enabled = false
	end
	for _, label in pairs(bay.screen) do
		label.Text = "--"
		if label.Name == "RaceStatus" then
			label.BackgroundColor3 = Color3.fromRGB(70, 78, 90)
		end
	end
	applyTier(bay, 0)
end

local function textOrDash(value): string
	if value == nil or value == "" then
		return "--"
	end
	return tostring(value)
end

local function showCar(bay, field: string, signatureField: string, spec, anchor: BasePart?, look: Vector3)
	local signature = "empty"
	if type(spec) == "table" and type(spec.modelId) == "string" and type(spec.qualityId) == "string" then
		signature = spec.modelId .. ":" .. tostring(spec.upgradeLevel) .. ":" .. spec.qualityId
	end
	if bay[signatureField] == signature then
		return
	end
	clearVisual(bay, field, signatureField)
	bay[signatureField] = signature
	if signature == "empty" or anchor == nil then
		return
	end
	local model = CarVisualFactory.build({
		modelId = spec.modelId,
		qualityId = spec.qualityId,
		upgradeLevel = spec.upgradeLevel,
		displayName = spec.displayName,
	})
	model.Name = if field == "bestModel" then "BestCarVisual" else "BenchCarVisual"
	model:SetAttribute("DisplayOnly", true)
	model.Parent = bay.model
	local half = anchor.Size * 0.5
	local upReach = math.abs(anchor.CFrame.RightVector.Y) * half.X
		+ math.abs(anchor.CFrame.UpVector.Y) * half.Y
		+ math.abs(anchor.CFrame.LookVector.Y) * half.Z
	local padTop = anchor.Position.Y + upReach
	local center = Vector3.new(anchor.Position.X, padTop + 0.54, anchor.Position.Z)
	model:PivotTo(CFrame.lookAt(center, center + look))
	if field == "bestModel" then
		local body = model:FindFirstChild("Body")
		if body ~= nil and body:IsA("BasePart") then
			local board = Instance.new("BillboardGui")
			board.Name = "ShowcaseName"
			board.Size = UDim2.fromOffset(220, 36)
			board.StudsOffset = Vector3.new(0, 1.8, 0)
			board.MaxDistance = 48
			board.LightInfluence = 0
			board.Parent = body
			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.Size = UDim2.fromScale(1, 1)
			name.Font = Enum.Font.GothamBold
			name.Text = if type(spec.power) == "number"
				then string.format("%s  +%d  Power %d", spec.displayName, spec.upgradeLevel or 0, spec.power)
				else string.format("%s  +%d", spec.displayName, spec.upgradeLevel or 0)
			name.TextColor3 = Color3.new(1, 1, 1)
			name.TextStrokeTransparency = 0.4
			name.TextScaled = true
			name.Parent = board
		end
	end
	bay[field] = model
end

local function turnedPose(pose, offset: Vector3)
	local origin = PrivateGarage.TrackOrigin
	local rel = Vector3.new(pose.x - origin.X, pose.y - origin.Y, pose.z - origin.Z)
	local spin = CFrame.Angles(0, PrivateGarage.TrackYaw, 0)
	local turned = spin:VectorToWorldSpace(rel)
	local look = spin:VectorToWorldSpace(Vector3.new(pose.lookX, pose.lookY, pose.lookZ))
	local up = spin:VectorToWorldSpace(Vector3.new(pose.upX, pose.upY, pose.upZ))
	local pos = PrivateGarage.GarageTrackCenter + turned + offset
	return {
		x = pos.X,
		y = pos.Y,
		z = pos.Z,
		lookX = look.X,
		lookY = look.Y,
		lookZ = look.Z,
		upX = up.X,
		upY = up.Y,
		upZ = up.Z,
	}
end

local WHEEL_RADIUS = 0.24
local WHEEL_NAMES = { "WheelFL", "WheelFR", "WheelRL", "WheelRR" }

local function attachTestMotion(model)
	local body = model:FindFirstChild("Body")
	local wheels = {}
	local pivot = model:GetPivot()
	for _, name in ipairs(WHEEL_NAMES) do
		local wheel = model:FindFirstChild(name)
		if wheel ~= nil and wheel:IsA("BasePart") then
			table.insert(wheels, {
				part = wheel,
				rest = pivot:ToObjectSpace(wheel.CFrame),
			})
		end
	end
	if body == nil or not body:IsA("BasePart") then
		return wheels, nil, nil
	end
	local rear = Instance.new("Attachment")
	rear.Name = "LaunchAttach"
	rear.Position = Vector3.new(0, 0.05, 1.15)
	rear.Parent = body
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "LaunchDust"
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Rate = 28
	dust.Lifetime = NumberRange.new(0.12, 0.22)
	dust.Speed = NumberRange.new(2, 4)
	dust.SpreadAngle = Vector2.new(12, 12)
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.28),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Color = ColorSequence.new(Color3.fromRGB(210, 210, 210))
	dust.LightEmission = 0.15
	dust.EmissionDirection = Enum.NormalId.Back
	dust.Enabled = false
	dust.Parent = rear
	local tailA = Instance.new("Attachment")
	tailA.Name = "TrailA"
	tailA.Position = Vector3.new(-0.35, 0.15, 1.25)
	tailA.Parent = body
	local tailB = Instance.new("Attachment")
	tailB.Name = "TrailB"
	tailB.Position = Vector3.new(0.35, 0.15, 1.25)
	tailB.Parent = body
	local trail = Instance.new("Trail")
	trail.Name = "SpeedTrail"
	trail.Attachment0 = tailA
	trail.Attachment1 = tailB
	trail.Lifetime = 0.16
	trail.MinLength = 0.04
	trail.FaceCamera = true
	trail.LightEmission = 0.55
	trail.WidthScale = NumberSequence.new(0.45)
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 246, 220), Color3.fromRGB(255, 150, 40))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Enabled = false
	trail.Parent = body
	local boostA = Instance.new("Attachment")
	boostA.Name = "BoostA"
	boostA.Position = Vector3.new(-0.22, 0.22, 0.9)
	boostA.Parent = body
	local boostB = Instance.new("Attachment")
	boostB.Name = "BoostB"
	boostB.Position = Vector3.new(0.22, 0.22, 0.9)
	boostB.Parent = body
	local boost = Instance.new("Trail")
	boost.Name = "BoosterTrail"
	boost.Attachment0 = boostA
	boost.Attachment1 = boostB
	boost.Lifetime = 0.1
	boost.MinLength = 0.02
	boost.FaceCamera = true
	boost.LightEmission = 0.35
	boost.WidthScale = NumberSequence.new(0.28)
	boost.Color = ColorSequence.new(Color3.fromRGB(255, 176, 64))
	boost.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	boost.Enabled = false
	boost.Parent = body
	return wheels, dust, trail, boost
end

local coastCurve = nil

local function coastDistance(alpha: number): number
	local lap = RaceConfig.lapLength()
	if coastCurve == nil or coastCurve.lap ~= lap then
		local booster = PrivateGarage.BoosterAlong
		local kick = 1.6
		local rise = 5
		local tau = 0.22
		local samples = 128
		local function shape(distance: number): number
			local ahead = (distance - booster) % lap
			if ahead < 0 then
				ahead += lap
			end
			local gain = 0
			if ahead < rise then
				local unit = ahead / rise
				gain = unit * unit * (3 - 2 * unit)
			else
				gain = math.exp(-((ahead - rise) / lap) / tau)
			end
			return 1 + kick * gain
		end
		local cumulative = table.create(samples + 1)
		cumulative[1] = 0
		local total = 0
		for index = 1, samples do
			local startDistance = (index - 1) / samples * lap
			local endDistance = index / samples * lap
			total += (endDistance - startDistance) / shape((startDistance + endDistance) * 0.5)
			cumulative[index + 1] = total
		end
		coastCurve = {
			lap = lap,
			samples = samples,
			cumulative = cumulative,
			total = total,
		}
	end
	local curve = coastCurve
	local target = math.clamp(alpha, 0, 1) * curve.total
	local lo = 1
	local hi = curve.samples + 1
	while lo + 1 < hi do
		local mid = math.floor((lo + hi) * 0.5)
		if curve.cumulative[mid] <= target then
			lo = mid
		else
			hi = mid
		end
	end
	local startTime = curve.cumulative[lo]
	local endTime = curve.cumulative[math.min(lo + 1, curve.samples + 1)]
	local span = endTime - startTime
	local frac = if span > 1e-8 then math.clamp((target - startTime) / span, 0, 1) else 0
	local step = curve.lap / curve.samples
	return math.clamp((lo - 1) * step + frac * step, 0, curve.lap)
end

local function placeTestCar(bay, view)
	local spec = if type(view) == "table" then view.test else nil
	if type(spec) ~= "table" or type(spec.modelId) ~= "string" or type(spec.qualityId) ~= "string" then
		clearVisual(bay, "testModel", "testSignature")
		return
	end
	local signature = spec.modelId .. ":" .. tostring(spec.upgradeLevel) .. ":" .. spec.qualityId
	if bay.testSignature ~= signature or bay.testModel == nil or bay.testModel.Parent == nil then
		clearVisual(bay, "testModel", "testSignature")
		bay.testSignature = signature
		local model = CarVisualFactory.build({
			modelId = spec.modelId,
			qualityId = spec.qualityId,
			upgradeLevel = spec.upgradeLevel,
			displayName = spec.displayName,
		})
		model.Name = "TestLapCar"
		model:SetAttribute("DisplayOnly", true)
		model.Parent = bay.model
		local wheels, dust, trail, boost = attachTestMotion(model)
		bay.testModel = model
		bay.testWheels = wheels
		bay.testDust = dust
		bay.testTrail = trail
		bay.testBoost = boost
	end
	local alpha = if type(view.testAlpha) == "number" then math.clamp(view.testAlpha, 0, 1) else 0
	local distance = coastDistance(alpha)
	local pose = RaceConfig.sample(distance)
	local placed = turnedPose(pose, bay.offset)
	local ride = 0.5 + math.sin(distance * 1.25) * 0.02
	local cf = CarVisualFactory.poseCFrame(placed, ride, 0)
	bay.testModel:PivotTo(cf)
	local spin = CFrame.Angles(distance / WHEEL_RADIUS, 0, 0)
	for _, wheel in ipairs(bay.testWheels or {}) do
		if wheel.part.Parent ~= nil then
			wheel.part.CFrame = cf * wheel.rest * spin
		end
	end
	local lapLength = RaceConfig.lapLength()
	local ahead = distance - PrivateGarage.BoosterAlong
	if lapLength > 0 then
		ahead = ahead % lapLength
		if ahead < 0 then
			ahead += lapLength
		end
	end
	if bay.testDust ~= nil then
		bay.testDust.Enabled = ahead < 4.5 and alpha < 0.995
	end
	if bay.testTrail ~= nil then
		bay.testTrail.Enabled = alpha > 0.02 and alpha < 0.995
	end
	if bay.testBoost ~= nil then
		bay.testBoost.Enabled = ahead < 8 and alpha < 0.995
	end
end

local function spinBoosters(bay, rank: number)
	if bay.boosterRollers == nil then
		bay.boosterRollers = {}
		bay.boosterAccents = {}
		local track = bay.model:FindFirstChild("TestTrack")
		if track ~= nil then
			for _, descendant in ipairs(track:GetDescendants()) do
				if descendant:IsA("BasePart") then
					local spin = descendant:GetAttribute("BoosterSpin")
					if type(spin) == "number" then
						table.insert(bay.boosterRollers, {
							part = descendant,
							rest = descendant.CFrame,
							sign = spin,
						})
					end
					local accentAt = descendant:GetAttribute("AccentAt")
					if type(accentAt) == "number" then
						table.insert(bay.boosterAccents, {
							part = descendant,
							at = accentAt,
						})
					end
				end
			end
		end
	end
	local rate = 18 + rank * 2.4
	local now = os.clock()
	for _, item in ipairs(bay.boosterRollers) do
		if item.part.Parent ~= nil then
			item.part.CFrame = item.rest * CFrame.Angles(now * rate * item.sign, 0, 0)
		end
	end
	for _, item in ipairs(bay.boosterAccents) do
		if item.part.Parent ~= nil then
			item.part.Transparency = if rank >= item.at then 0 else 1
		end
	end
end

local function applyShell(bay, level: number)
	local clean = level >= 1
	if bay.shellClean == clean then
		return
	end
	bay.shellClean = clean
	local cleanColor = Color3.fromRGB(186, 190, 194)
	local ribColor = Color3.fromRGB(46, 78, 108)
	local ceilingColor = Color3.fromRGB(232, 224, 208)
	for _, descendant in ipairs(bay.model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local shell = descendant:GetAttribute("GarageShell")
			if shell == "Metal" or shell == "Rib" or shell == "Ceiling" then
				if bay.shellColor == nil then
					bay.shellColor = {}
				end
				if bay.shellColor[descendant] == nil then
					bay.shellColor[descendant] = descendant.Color
				end
				if clean then
					if shell == "Rib" then
						descendant.Material = Enum.Material.Metal
						descendant.Color = ribColor
					elseif shell == "Ceiling" then
						descendant.Material = Enum.Material.SmoothPlastic
						descendant.Color = ceilingColor
					else
						descendant.Material = Enum.Material.Metal
						descendant.Color = cleanColor
					end
				else
					descendant.Material = Enum.Material.CorrodedMetal
					descendant.Color = bay.shellColor[descendant]
				end
			elseif shell == "Rust" then
				descendant.Transparency = if clean then 1 else 0
			end
		end
	end
end

function PrivateGarage.paint(playerKey: string, view)
	local bay = state.byPlayer[playerKey]
	if bay == nil then
		return
	end
	local rank = if type(view) == "table" and type(view.rebirthLevel) == "number" then view.rebirthLevel else 0
	applyShell(bay, rank)
	applyTier(bay, rank)
	local screen = bay.screen
	local status = if type(view) == "table" then view.status else nil
	local function set(name: string, text: string)
		local label = screen[name]
		if label ~= nil then
			label.Text = text
		end
	end
	if type(view) ~= "table" then
		set("CurrentCar", "--")
		set("Power", "--")
		set("RankBoost", "--")
		set("CurrentLap", "--")
		set("BestLap", "--")
		set("LapsCompleted", "--")
		set("RaceStatus", "--")
		clearVisual(bay, "testModel", "testSignature")
		clearVisual(bay, "bestModel", "bestSignature")
		clearVisual(bay, "benchModel", "benchSignature")
		return
	end
	set("CurrentCar", textOrDash(view.currentName))
	set("Power", if type(view.power) == "number" then tostring(view.power) else "--")
	set("RankBoost", if type(view.rankBoost) == "string" then view.rankBoost else "--")
	set("CurrentLap", if type(view.currentLap) == "number" then tostring(view.currentLap) else "--")
	set("BestLap", if type(view.bestLap) == "number" then string.format("%.2fs", view.bestLap) else "--")
	set("LapsCompleted", if type(view.lapsCompleted) == "number" then tostring(view.lapsCompleted) else "--")
	local badge = screen.RaceStatus
	if badge ~= nil then
		if status == "TESTING" then
			badge.Text = "TESTING"
			badge.BackgroundColor3 = Color3.fromRGB(214, 122, 38)
		elseif status == "IDLE" then
			badge.Text = "IDLE"
			badge.BackgroundColor3 = Color3.fromRGB(70, 78, 90)
		else
			badge.Text = "--"
			badge.BackgroundColor3 = Color3.fromRGB(70, 78, 90)
		end
	end
	spinBoosters(bay, rank)
	if rank >= 2 then
		showCar(bay, "bestModel", "bestSignature", view.best, bay.showcase, Vector3.new(-1, 0, 0))
	else
		clearVisual(bay, "bestModel", "bestSignature")
	end
	if rank >= 1 then
		showCar(bay, "benchModel", "benchSignature", view.bench, bay.cradle, Vector3.new(0, 0, -1))
	else
		clearVisual(bay, "benchModel", "benchSignature")
	end
	placeTestCar(bay, view)
	if bay.emptySign ~= nil then
		bay.emptySign.Enabled = rank >= 2 and view.best == nil
	end
end

return PrivateGarage
