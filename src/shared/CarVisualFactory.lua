-- 玩具車只負責顯示。車款、等級與性能的權威資料仍在伺服器車庫。
local CarVisualFactory = {}

local function palette()
	return {
		Common = Color3.fromRGB(245, 245, 245),
		Uncommon = Color3.fromRGB(64, 196, 96),
		Rare = Color3.fromRGB(58, 132, 255),
		Epic = Color3.fromRGB(168, 78, 255),
		Legendary = Color3.fromRGB(255, 140, 32),
	}
end

function CarVisualFactory.qualityColor(qualityId: any): Color3
	local color = palette()[qualityId]
	if color == nil then
		return Color3.fromRGB(150, 150, 150)
	end
	return color
end

function CarVisualFactory.poseCFrame(pose, rideHeight: number?, lateral: number?)
	local look = Vector3.new(pose.lookX, pose.lookY, pose.lookZ)
	local up = Vector3.new(pose.upX, pose.upY, pose.upZ)
	if look.Magnitude < 1e-4 then
		look = Vector3.xAxis
	else
		look = look.Unit
	end
	if up.Magnitude < 1e-4 or math.abs(look:Dot(up)) > 0.99 then
		up = Vector3.yAxis
	else
		up = up.Unit
	end
	local right = look:Cross(up)
	if right.Magnitude < 1e-4 then
		right = Vector3.zAxis
	else
		right = right.Unit
	end

	local position = Vector3.new(pose.x, pose.y, pose.z)
		+ up * (rideHeight or 0.45)
		+ right * (lateral or 0)
	return CFrame.lookAt(position, position + look, up)
end

local function addPart(props)
	local item = Instance.new("Part")
	if props.cylinder == true then
		item.Shape = Enum.PartType.Cylinder
	end
	item.Name = props.name
	item.Size = props.size
	item.Color = props.color
	item.Material = props.material or Enum.Material.SmoothPlastic
	item.Transparency = props.transparency or 0
	item.Anchored = true
	item.CanCollide = false
	item.CanTouch = false
	item.CanQuery = false
	item.CastShadow = props.shadow ~= false
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.CFrame = props.cframe
	item.Parent = props.parent
	return item
end

local function levelTag(parent: BasePart, upgradeLevel: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LevelTag"
	billboard.Size = UDim2.fromOffset(64, 22)
	billboard.StudsOffset = Vector3.new(0, 1.35, 0)
	billboard.MaxDistance = 90
	billboard.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	label.BackgroundTransparency = 0.2
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Text = string.format("+%d", upgradeLevel)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = billboard
	billboard.Parent = parent
end

-- 車頭朝向 -Z，方便用 CFrame.lookAt 對齊賽道前進方向。
function CarVisualFactory.build(spec)
	spec = spec or {}
	local qualityId = if type(spec.qualityId) == "string" then spec.qualityId else "Common"
	local upgradeLevel = if type(spec.upgradeLevel) == "number" then spec.upgradeLevel else 0
	local bodyColor = CarVisualFactory.qualityColor(qualityId)
	local dark = Color3.fromRGB(28, 30, 34)
	local glass = Color3.fromRGB(188, 226, 236)
	local model = Instance.new("Model")
	model.Name = "ToyCar"

	local body = addPart({
		name = "Body",
		size = Vector3.new(1.28, 0.42, 2.7),
		color = bodyColor,
		cframe = CFrame.new(0, 0.5, 0.05),
		parent = model,
	})
	model.PrimaryPart = body

	addPart({
		name = "Cabin",
		size = Vector3.new(1.12, 0.36, 1.15),
		color = bodyColor:Lerp(Color3.new(1, 1, 1), 0.18),
		cframe = CFrame.new(0, 0.82, 0.18),
		parent = model,
	})
	addPart({
		name = "Hood",
		size = Vector3.new(1.16, 0.16, 0.72),
		color = bodyColor:Lerp(dark, 0.12),
		cframe = CFrame.new(0, 0.62, -0.72),
		parent = model,
	})
	addPart({
		name = "Windshield",
		size = Vector3.new(1.05, 0.38, 0.08),
		color = glass,
		material = Enum.Material.Glass,
		transparency = 0.35,
		cframe = CFrame.new(0, 0.86, -0.38) * CFrame.Angles(math.rad(28), 0, 0),
		parent = model,
	})
	addPart({
		name = "RearWindow",
		size = Vector3.new(1.02, 0.28, 0.08),
		color = glass,
		material = Enum.Material.Glass,
		transparency = 0.4,
		cframe = CFrame.new(0, 0.8, 0.72) * CFrame.Angles(math.rad(-24), 0, 0),
		parent = model,
	})

	local wheelColor = Color3.fromRGB(32, 32, 36)
	local wheelPositions = {
		WheelFL = Vector3.new(-0.7, 0.24, -0.82),
		WheelFR = Vector3.new(0.7, 0.24, -0.82),
		WheelRL = Vector3.new(-0.7, 0.24, 0.86),
		WheelRR = Vector3.new(0.7, 0.24, 0.86),
	}
	for name, position in pairs(wheelPositions) do
		addPart({
			name = name,
			cylinder = true,
			size = Vector3.new(0.22, 0.48, 0.48),
			color = wheelColor,
			cframe = CFrame.new(position),
			parent = model,
		})
	end

	addPart({
		name = "HeadLightL",
		size = Vector3.new(0.24, 0.16, 0.1),
		color = Color3.fromRGB(255, 244, 186),
		material = Enum.Material.Neon,
		shadow = false,
		cframe = CFrame.new(-0.38, 0.5, -1.32),
		parent = model,
	})
	addPart({
		name = "HeadLightR",
		size = Vector3.new(0.24, 0.16, 0.1),
		color = Color3.fromRGB(255, 244, 186),
		material = Enum.Material.Neon,
		shadow = false,
		cframe = CFrame.new(0.38, 0.5, -1.32),
		parent = model,
	})
	addPart({
		name = "TailLightL",
		size = Vector3.new(0.26, 0.14, 0.1),
		color = Color3.fromRGB(255, 64, 54),
		material = Enum.Material.Neon,
		shadow = false,
		cframe = CFrame.new(-0.4, 0.52, 1.38),
		parent = model,
	})
	addPart({
		name = "TailLightR",
		size = Vector3.new(0.26, 0.14, 0.1),
		color = Color3.fromRGB(255, 64, 54),
		material = Enum.Material.Neon,
		shadow = false,
		cframe = CFrame.new(0.4, 0.52, 1.38),
		parent = model,
	})
	addPart({
		name = "Badge",
		cylinder = true,
		size = Vector3.new(0.08, 0.22, 0.22),
		color = dark,
		cframe = CFrame.new(0, 0.58, -1.2) * CFrame.Angles(0, math.rad(90), 0),
		parent = model,
	})

	if qualityId == "Rare" or qualityId == "Epic" or qualityId == "Legendary" then
		addPart({
			name = "Scoop",
			size = Vector3.new(0.36, 0.14, 0.42),
			color = dark,
			cframe = CFrame.new(0, 0.74, -0.55),
			parent = model,
		})
	end
	if qualityId == "Epic" or qualityId == "Legendary" then
		addPart({
			name = "Spoiler",
			size = Vector3.new(1.2, 0.08, 0.28),
			color = dark,
			cframe = CFrame.new(0, 0.98, 1.15),
			parent = model,
		})
	end
	if qualityId == "Legendary" then
		local glow = Instance.new("PointLight")
		glow.Name = "LegendaryGlow"
		glow.Color = bodyColor
		glow.Brightness = 1.1
		glow.Range = 8
		glow.Shadows = false
		glow.Parent = body

		local spark = Instance.new("ParticleEmitter")
		spark.Name = "LegendarySpark"
		spark.Rate = 6
		spark.Lifetime = NumberRange.new(0.25, 0.45)
		spark.Speed = NumberRange.new(0.4, 1)
		spark.Size = NumberSequence.new(0.12)
		spark.LightEmission = 0.35
		spark.Color = ColorSequence.new(bodyColor)
		spark.Parent = body
	end

	levelTag(body, upgradeLevel)
	model:SetAttribute("ModelId", spec.modelId)
	model:SetAttribute("QualityId", qualityId)
	model:SetAttribute("UpgradeLevel", upgradeLevel)
	model:SetAttribute("DisplayName", spec.displayName)
	return model
end

return CarVisualFactory
