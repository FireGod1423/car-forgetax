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
PlaygroundBuilder.Version = 2

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

local function lay(parent: Instance, fromDistance: number, toDistance: number, step: number, name: string, collide: boolean)
	local cursor = fromDistance
	local index = 1
	while cursor < toDistance - 0.05 do
		local nextDistance = math.min(toDistance, cursor + step)
		local pose = RaceConfig.sample((cursor + nextDistance) * 0.5)
		local piece = part({
			name = string.format("%s%d", name, index),
			size = Vector3.new(RaceConfig.Layout.width, 0.35, math.max(0.6, nextDistance - cursor + 0.15)),
			cframe = CarVisualFactory.poseCFrame(pose, -0.05, 0),
			color = ORANGE,
			parent = parent,
			collide = collide,
		})
		piece:SetAttribute("TrackDistance", pose.segment)
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
	lay(track, 0, markers.straightEnd, 8, "Straight", true)
	lay(track, markers.straightEnd, markers.loopEnd, RaceConfig.loopLength() / 18, "Loop", false)
	lay(track, markers.loopEnd, markers.afterEnd, 6, "Approach", true)
	lay(track, markers.jumpEnd, markers.finishEnd, 8, "Finish", true)

	local jumpStart = RaceConfig.sample(markers.afterEnd)
	local jumpEnd = RaceConfig.sample(markers.jumpEnd)
	part({
		name = "JumpRamp",
		size = Vector3.new(RaceConfig.Layout.width, 0.35, 7),
		cframe = CarVisualFactory.poseCFrame(jumpStart, 0.35, 0) * CFrame.Angles(math.rad(-18), 0, 0),
		color = ORANGE_DARK,
		parent = track,
	})
	part({
		name = "LandingRamp",
		size = Vector3.new(RaceConfig.Layout.width, 0.35, 7),
		cframe = CarVisualFactory.poseCFrame(jumpEnd, 0.35, 0) * CFrame.Angles(math.rad(16), 0, 0),
		color = ORANGE_DARK,
		parent = track,
	})

	local startPose = RaceConfig.sample(0)
	local finishPose = RaceConfig.sample(RaceConfig.trackLength())
	local startArch = part({
		name = "RaceStart",
		size = Vector3.new(10, 1, 1),
		cframe = CarVisualFactory.poseCFrame(startPose, 4.2, 0),
		color = Color3.fromRGB(96, 230, 140),
		material = Enum.Material.Neon,
		parent = track,
		collide = false,
	})
	caption(startArch, "起點", 2)
	local finishArch = part({
		name = "RaceFinish",
		size = Vector3.new(10, 1, 1),
		cframe = CarVisualFactory.poseCFrame(finishPose, 4.2, 0),
		color = Color3.fromRGB(255, 226, 80),
		material = Enum.Material.Neon,
		parent = track,
		collide = false,
	})
	caption(finishArch, "終點", 2)

	local layout = RaceConfig.Layout
	for index = 0, 3 do
		local pose = RaceConfig.sample(index * 12 + 4)
		part({
			name = "Pillar" .. index,
			size = Vector3.new(1.2, 4.2, 1.2),
			cframe = CFrame.new(pose.x, 2.9, pose.z),
			color = ORANGE_DARK,
			parent = track,
		})
	end
	local rampStart = Vector3.new(16, 1.1, layout.originZ)
	local rampEnd = Vector3.new(layout.originX, layout.originY, layout.originZ)
	part({
		name = "WatchRamp",
		size = Vector3.new(8, 0.45, (rampEnd - rampStart).Magnitude),
		cframe = CFrame.lookAt((rampStart + rampEnd) / 2, rampEnd),
		color = ORANGE,
		parent = track,
	})
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

	kiosk(folder, "GachaMachine", Vector3.new(-28, 3.3, -18), ORANGE, "抽車機", "抽車")
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
