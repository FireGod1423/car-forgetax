-- 玩具車只負責顯示。車款、等級與性能的權威資料仍在伺服器車庫。
-- 品質色只用於介面與特效。車身烤漆來自車款目錄。
local function importShared(moduleName: string)
	if game ~= nil then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild(moduleName))
	end
	return require("./" .. moduleName)
end

local CarConfig = importShared("CarConfig")
local CarCatalog = importShared("CarCatalog")

local CarVisualFactory = {}

function CarVisualFactory.qualityColor(qualityId: any): Color3
	local quality = if type(qualityId) == "string" then CarConfig.getQuality(qualityId) else nil
	local channels = if quality ~= nil then quality.UiColor else nil
	if type(channels) ~= "table" then
		return Color3.fromRGB(150, 150, 150)
	end
	return Color3.fromRGB(channels[1], channels[2], channels[3])
end

function CarVisualFactory.qualityTextColor(qualityId: any): Color3
	if type(qualityId) == "string" and CarConfig.needsLightRim(qualityId) then
		return Color3.fromRGB(226, 230, 236)
	end
	return CarVisualFactory.qualityColor(qualityId)
end

function CarVisualFactory.applyQualityText(item: Instance, qualityId: any)
	if not item:IsA("TextLabel") and not item:IsA("TextButton") then
		return
	end
	item.TextColor3 = CarVisualFactory.qualityTextColor(qualityId)
	local existing = item:FindFirstChild("QualityInk")
	if existing ~= nil then
		existing:Destroy()
	end
	local stroke = Instance.new("UIStroke")
	stroke.Name = "QualityInk"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Thickness = 1
	if type(qualityId) == "string" and CarConfig.needsDarkInk(qualityId) then
		stroke.Color = Color3.fromRGB(42, 32, 18)
		stroke.Parent = item
	elseif type(qualityId) == "string" and CarConfig.needsLightRim(qualityId) then
		stroke.Color = Color3.fromRGB(226, 230, 236)
		stroke.Parent = item
	else
		stroke:Destroy()
	end
end

function CarVisualFactory.markChip(chip: Instance, qualityId: any)
	if not chip:IsA("GuiObject") then
		return
	end
	chip.BackgroundColor3 = CarVisualFactory.qualityColor(qualityId)
	local rimColor = nil
	if type(qualityId) == "string" and CarConfig.needsLightRim(qualityId) then
		rimColor = Color3.fromRGB(226, 230, 236)
	elseif type(qualityId) == "string" and CarConfig.needsDarkInk(qualityId) then
		rimColor = Color3.fromRGB(42, 32, 18)
	end
	if rimColor ~= nil then
		local rim = Instance.new("UIStroke")
		rim.Name = "QualityRim"
		rim.Color = rimColor
		rim.Thickness = 1.5
		rim.Parent = chip
	end
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

-- 車頭朝向 -Z，方便用 CFrame.lookAt 對齊賽道前進方向。強化數字只留在介面文字，不浮在車身上。
function CarVisualFactory.build(spec)
	spec = spec or {}
	local qualityId = if type(spec.qualityId) == "string" then spec.qualityId else "Common"
	local upgradeLevel = if type(spec.upgradeLevel) == "number" then spec.upgradeLevel else 0
	local record = if type(spec.modelId) == "string" then CarCatalog.getByModelId(spec.modelId) else nil
	local bodyColor = Color3.fromRGB(120, 122, 126)
	if record ~= nil and type(record.Paint) == "table" then
		bodyColor = Color3.fromRGB(record.Paint[1], record.Paint[2], record.Paint[3])
	end
	if record ~= nil and type(record.MeshKey) == "string" then
		local mesh = CarVisualFactory.findMesh(record.MeshKey)
		if mesh ~= nil then
			return CarVisualFactory.cloneMesh(mesh, spec, record)
		end
		return CarVisualFactory.missingMesh(spec, record)
	end
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
		glow.Color = CarVisualFactory.qualityColor(qualityId)
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
		spark.Color = ColorSequence.new(CarVisualFactory.qualityColor(qualityId))
		spark.Parent = body
	end

	model:SetAttribute("ModelId", spec.modelId)
	model:SetAttribute("QualityId", qualityId)
	model:SetAttribute("UpgradeLevel", upgradeLevel)
	model:SetAttribute("DisplayName", spec.displayName)
	return model
end

function CarVisualFactory.findMesh(meshKey: string): Instance?
	if game == nil or type(meshKey) ~= "string" then
		return nil
	end
	local folders = {
		game:GetService("ReplicatedStorage"):FindFirstChild("CarMeshKit"),
		game:GetService("ServerStorage"):FindFirstChild("CarMeshKit"),
	}
	for _, folder in ipairs(folders) do
		if folder ~= nil then
			local found = folder:FindFirstChild(meshKey)
			if found ~= nil then
				return found
			end
		end
	end
	return nil
end

function CarVisualFactory.cloneMesh(source: Instance, spec, record)
	local model = source:Clone()
	model.Name = "OfficialCar"
	if not model:IsA("Model") then
		local wrapper = Instance.new("Model")
		wrapper.Name = "OfficialCar"
		model.Parent = wrapper
		if model:IsA("BasePart") then
			wrapper.PrimaryPart = model
		end
		model = wrapper
	end
	if model.PrimaryPart == nil then
		local part = model:FindFirstChildWhichIsA("BasePart", true)
		if part ~= nil then
			model.PrimaryPart = part
		end
	end
	model:SetAttribute("ModelId", spec.modelId)
	model:SetAttribute("QualityId", spec.qualityId)
	model:SetAttribute("UpgradeLevel", spec.upgradeLevel or 0)
	model:SetAttribute("DisplayName", spec.displayName)
	model:SetAttribute("MeshKey", record.MeshKey)
	model:SetAttribute("OfficialMesh", true)
	return model
end

function CarVisualFactory.missingMesh(spec, record)
	local model = Instance.new("Model")
	model.Name = "MissingCarMesh"
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Parent = model
	model.PrimaryPart = anchor
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MissingLabel"
	billboard.Size = UDim2.fromOffset(180, 40)
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextSize = 14
	text.TextColor3 = Color3.fromRGB(236, 232, 220)
	text.Text = "Not imported"
	text.Parent = billboard
	model:SetAttribute("ModelId", spec.modelId)
	model:SetAttribute("QualityId", spec.qualityId)
	model:SetAttribute("UpgradeLevel", spec.upgradeLevel or 0)
	model:SetAttribute("DisplayName", spec.displayName)
	model:SetAttribute("MeshKey", record.MeshKey)
	model:SetAttribute("MissingMesh", true)
	return model
end

return CarVisualFactory
