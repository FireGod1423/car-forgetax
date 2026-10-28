-- 工作台鏡頭、展示車和鐵鎚只存在這個客戶端。強化結果由伺服器先寫入，這裡只負責演出。
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CarVisualFactory = require(sharedFolder:WaitForChild("CarVisualFactory"))

local WorkbenchView = {}

local LOCK = "CarForgeTaxBenchLock"
local CAMERA_BIND = "CarForgeTaxBenchCamera"

local EFFECT = {
	Destroy = {
		color = Color3.fromRGB(255, 64, 54),
		count = 46,
		speed = 13,
		size = 0.5,
		light = 3.4,
		sound = "rbxassetid://5801257793",
		volume = 0.55,
	},
	Damage = {
		color = Color3.fromRGB(255, 148, 48),
		count = 20,
		speed = 8,
		size = 0.26,
		light = 1.8,
		sound = "rbxassetid://12222216",
		volume = 0.45,
	},
	Keep = {
		color = Color3.fromRGB(88, 214, 120),
		count = 8,
		speed = 2.4,
		size = 0.32,
		light = 1.1,
		sound = "rbxassetid://12221967",
		volume = 0.3,
	},
	Success = {
		color = Color3.fromRGB(64, 148, 255),
		count = 22,
		speed = 7,
		size = 0.3,
		light = 2.2,
		sound = "rbxassetid://12222216",
		volume = 0.45,
	},
	GreatSuccess = {
		color = Color3.fromRGB(186, 96, 255),
		count = 36,
		speed = 10,
		size = 0.4,
		light = 2.8,
		sound = "rbxassetid://12222216",
		volume = 0.55,
	},
}

local function part(props)
	local item = Instance.new("Part")
	item.Name = props.name
	item.Size = props.size
	item.Color = props.color
	item.Material = props.material or Enum.Material.SmoothPlastic
	item.Anchored = true
	item.CanCollide = false
	item.CanTouch = false
	item.CanQuery = false
	item.CastShadow = true
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.CFrame = props.cframe
	item.Parent = props.parent
	return item
end

local function buildHammer(): Model
	local model = Instance.new("Model")
	model.Name = "UpgradeHammer"
	model:SetAttribute("DisplayOnly", true)
	local handle = part({
		name = "Handle",
		size = Vector3.new(0.1, 0.1, 0.92),
		color = Color3.fromRGB(92, 58, 36),
		material = Enum.Material.Wood,
		cframe = CFrame.new(0, 0, 0.28),
		parent = model,
	})
	local head = part({
		name = "Head",
		size = Vector3.new(0.28, 0.28, 0.46),
		color = Color3.fromRGB(186, 190, 196),
		material = Enum.Material.Metal,
		cframe = CFrame.new(0, 0, -0.16),
		parent = model,
	})
	part({
		name = "Cheek",
		size = Vector3.new(0.18, 0.18, 0.18),
		color = Color3.fromRGB(92, 96, 102),
		material = Enum.Material.Metal,
		cframe = CFrame.new(0, 0, -0.34),
		parent = model,
	})
	model.PrimaryPart = handle
	head.Material = Enum.Material.Metal
	return model
end

function WorkbenchView.mount(player: Player, onForcedExit)
	local active = false
	local playing = false
	local generation = 0
	local goal = CFrame.new()
	local savedType = Enum.CameraType.Custom
	local savedSubject = nil
	local savedFov = 70
	local savedWalk = 16
	local savedJump = 7.2
	local savedRotate = true
	local folder: Folder? = nil
	local hammer: Model? = nil
	local hammerValue: CFrameValue? = nil
	local display: Model? = nil
	local displayKey = ""
	local benchPrompt: ProximityPrompt? = nil
	local cradle: BasePart? = nil
	local top: BasePart? = nil
	local hidden = {}
	local savedRoot: CFrame? = nil

	local function camera()
		return workspace.CurrentCamera
	end

	local function humanoid(): Humanoid?
		local character = player.Character
		if character == nil then
			return nil
		end
		local found = character:FindFirstChildOfClass("Humanoid")
		if found ~= nil and found:IsA("Humanoid") then
			return found
		end
		return nil
	end

	local function clearDisplay()
		displayKey = ""
		if display ~= nil then
			display:Destroy()
			display = nil
		end
	end

	local function hideCharacter()
		local character = player.Character
		if character == nil or top == nil then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if root ~= nil and root:IsA("BasePart") then
			savedRoot = root.CFrame
			root.CFrame = top.CFrame * CFrame.new(0, 4, 10)
		end
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") then
				hidden[descendant] = descendant.LocalTransparencyModifier
				descendant.LocalTransparencyModifier = 1
			elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
				hidden[descendant] = descendant.Transparency
				descendant.Transparency = 1
			end
		end
	end

	local function showCharacter()
		for inst, value in pairs(hidden) do
			if inst.Parent ~= nil then
				if inst:IsA("BasePart") then
					inst.LocalTransparencyModifier = value
				elseif inst:IsA("Decal") or inst:IsA("Texture") then
					inst.Transparency = value
				end
			end
		end
		table.clear(hidden)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root ~= nil and root:IsA("BasePart") and savedRoot ~= nil then
			root.CFrame = savedRoot
		end
		savedRoot = nil
	end

	local function restoreCharacter()
		local found = humanoid()
		if found ~= nil then
			found.WalkSpeed = savedWalk
			found.JumpHeight = savedJump
			found.AutoRotate = savedRotate
		end
	end

	local function restoreCamera()
		local current = camera()
		if current ~= nil then
			current.CameraType = savedType or Enum.CameraType.Custom
			current.FieldOfView = savedFov
			local subject = savedSubject
			if subject == nil or subject.Parent == nil then
				subject = humanoid()
			end
			if subject ~= nil then
				current.CameraSubject = subject
			end
		end
	end

	local function placeCar(model: Model)
		if cradle == nil or top == nil then
			return
		end
		model.Parent = folder
		local _, rawSize = model:GetBoundingBox()
		local scale = math.min(
			2.2 / math.max(rawSize.X, 0.05),
			1.25 / math.max(rawSize.Y, 0.05),
			3.15 / math.max(rawSize.Z, 0.05)
		)
		scale = math.clamp(scale, 0.35, 1.2)
		model:ScaleTo(scale)
		local look = top.CFrame.LookVector
		if look.Magnitude < 0.01 then
			look = Vector3.new(0, 0, -1)
		end
		model:PivotTo(CFrame.lookAt(Vector3.zero, look, Vector3.yAxis))
		local boxCf, boxSize = model:GetBoundingBox()
		local surface = cradle.Position + cradle.CFrame.UpVector * (cradle.Size.Y * 0.5 + 0.04)
		local bottomY = boxCf.Position.Y - boxSize.Y * 0.5
		local delta = Vector3.new(surface.X - boxCf.Position.X, surface.Y - bottomY, surface.Z - boxCf.Position.Z)
		model:PivotTo(model:GetPivot() + delta)
	end

	local api = {}

	function api.isOpen(): boolean
		return active
	end

	function api.showCar(car)
		if active ~= true or folder == nil then
			return
		end
		if car == nil then
			clearDisplay()
			return
		end
		local key = tostring(car.modelId) .. ":" .. tostring(car.qualityId) .. ":" .. tostring(car.upgradeLevel)
		if key == displayKey and display ~= nil and display.Parent ~= nil then
			return
		end
		clearDisplay()
		displayKey = key
		local model = CarVisualFactory.build({
			modelId = car.modelId,
			qualityId = car.qualityId,
			upgradeLevel = car.upgradeLevel,
			displayName = car.displayName,
		})
		model.Name = "UpgradePreview"
		model:SetAttribute("DisplayOnly", true)
		model:SetAttribute("UpgradePreview", true)
		placeCar(model)
		display = model
	end

	function api.enter(bench: Instance?): boolean
		if bench == nil or not bench:IsA("Model") then
			return false
		end
		local benchTop = bench:FindFirstChild("BenchTop")
		local benchCradle = bench:FindFirstChild("BenchCradle")
		if benchTop == nil or not benchTop:IsA("BasePart") or benchCradle == nil or not benchCradle:IsA("BasePart") then
			return false
		end
		if active then
			api.leave()
		end
		top = benchTop
		cradle = benchCradle
		generation += 1
		local current = camera()
		if current ~= nil then
			savedType = current.CameraType
			savedSubject = current.CameraSubject
			savedFov = current.FieldOfView
			current.CameraType = Enum.CameraType.Scriptable
			current.FieldOfView = 46
		end
		local found = humanoid()
		if found ~= nil then
			savedWalk = found.WalkSpeed
			savedJump = found.JumpHeight
			savedRotate = found.AutoRotate
			found.WalkSpeed = 0
			found.JumpHeight = 0
			found.AutoRotate = false
		end
		ContextActionService:BindActionAtPriority(LOCK, function()
			return Enum.ContextActionResult.Sink
		end, false, 3000, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space, Enum.KeyCode.LeftShift)
		local prompt = benchTop:FindFirstChildOfClass("ProximityPrompt")
		if prompt ~= nil then
			benchPrompt = prompt
			prompt.Enabled = false
		end
		folder = Instance.new("Folder")
		folder.Name = "LocalUpgradePreview"
		folder.Parent = bench
		hammer = buildHammer()
		hammer.Parent = folder
		local tray = bench:FindFirstChild("ToolTray")
		local restCf = if tray ~= nil and tray:IsA("BasePart")
			then tray.CFrame * CFrame.new(0.15, 0.42, 0.05)
			else benchTop.CFrame * CFrame.new(2.15, 0.7, 1.05)
		local restAt = restCf.Position
		local restLook = restAt + benchTop.CFrame.RightVector
		hammer:PivotTo(CFrame.lookAt(restAt, restLook, benchTop.CFrame.UpVector) * CFrame.Angles(math.rad(-78), 0, 0))
		hammerValue = Instance.new("CFrameValue")
		hammerValue.Value = hammer:GetPivot()
		hammerValue.Changed:Connect(function(nextCf)
			if hammer ~= nil and hammer.Parent ~= nil then
				hammer:PivotTo(nextCf)
			end
		end)
		local eye = benchTop.CFrame:PointToWorldSpace(Vector3.new(0.2, 3.15, -6.6))
		local focus = benchCradle.CFrame:PointToWorldSpace(Vector3.new(0, 0.55, 0))
		goal = CFrame.lookAt(eye, focus, Vector3.yAxis)
		active = true
		player:SetAttribute("BenchCamera", true)
		hideCharacter()
		if current ~= nil then
			current.CFrame = goal
		end
		return true
	end

	function api.leave()
		if active ~= true and folder == nil then
			return
		end
		generation += 1
		playing = false
		active = false
		player:SetAttribute("BenchCamera", nil)
		clearDisplay()
		if hammerValue ~= nil then
			hammerValue:Destroy()
			hammerValue = nil
		end
		if folder ~= nil then
			folder:Destroy()
			folder = nil
		end
		hammer = nil
		display = nil
		if benchPrompt ~= nil then
			benchPrompt.Enabled = true
			benchPrompt = nil
		end
		showCharacter()
		pcall(function()
			ContextActionService:UnbindAction(LOCK)
		end)
		restoreCharacter()
		restoreCamera()
		top = nil
		cradle = nil
	end

	local function tweenHammer(target: CFrame, duration: number, style: Enum.EasingStyle, direction: Enum.EasingDirection, token: number): boolean
		if hammerValue == nil or token ~= generation then
			return false
		end
		local tween = TweenService:Create(
			hammerValue,
			TweenInfo.new(duration, style, direction),
			{ Value = target }
		)
		tween:Play()
		tween.Completed:Wait()
		return token == generation and active
	end

	local function burst(host: BasePart, spec)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "UpgradeBurst"
		emitter.Color = ColorSequence.new(spec.color)
		emitter.LightEmission = 0.7
		emitter.LightInfluence = 0
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(0.18, 0.42)
		emitter.Speed = NumberRange.new(spec.speed * 0.45, spec.speed)
		emitter.SpreadAngle = Vector2.new(28, 28)
		emitter.Drag = 3
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, spec.size),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Parent = host
		emitter:Emit(spec.count)
		local glow = Instance.new("PointLight")
		glow.Color = spec.color
		glow.Brightness = spec.light
		glow.Range = 10
		glow.Shadows = false
		glow.Parent = host
		local sound = Instance.new("Sound")
		sound.SoundId = spec.sound
		sound.Volume = spec.volume
		sound.RollOffMaxDistance = 40
		sound.Parent = host
		sound:Play()
		task.delay(0.7, function()
			if glow.Parent ~= nil then
				glow:Destroy()
			end
			if emitter.Parent ~= nil then
				emitter:Destroy()
			end
			if sound.Parent ~= nil then
				sound:Destroy()
			end
		end)
	end

	local function shake(token: number)
		if display == nil or display.Parent == nil then
			return
		end
		local base = display:GetPivot()
		for _ = 1, 4 do
			if token ~= generation or display == nil then
				return
			end
			display:PivotTo(base * CFrame.new((math.random() - 0.5) * 0.07, 0, (math.random() - 0.5) * 0.05))
			task.wait(0.025)
		end
		if display ~= nil and token == generation then
			display:PivotTo(base)
		end
	end

	function api.play(outcomeId: string, onImpact)
		if active ~= true or playing or top == nil or cradle == nil or hammerValue == nil then
			return false
		end
		local spec = EFFECT[outcomeId]
		if spec == nil then
			return false
		end
		playing = true
		local token = generation
		local above = cradle.CFrame:PointToWorldSpace(Vector3.new(0.1, 2.15, 0.15))
		local impact = cradle.CFrame:PointToWorldSpace(Vector3.new(0, 0.72, 0))
		local raised = CFrame.lookAt(above, impact, top.CFrame.RightVector)
		local struck = CFrame.lookAt(impact, impact - Vector3.yAxis, top.CFrame.RightVector)
		local rest = hammerValue.Value
		local ok = tweenHammer(raised, 0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, token)
		if ok then
			ok = tweenHammer(struck, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In, token)
		end
		if ok then
			local sparkHost = Instance.new("Part")
			sparkHost.Name = "UpgradeSpark"
			sparkHost.Size = Vector3.new(0.2, 0.2, 0.2)
			sparkHost.Transparency = 1
			sparkHost.Anchored = true
			sparkHost.CanCollide = false
			sparkHost.CanTouch = false
			sparkHost.CanQuery = false
			sparkHost.CFrame = cradle.CFrame * CFrame.new(0, 0.8, 0)
			sparkHost.Parent = folder
			burst(sparkHost, spec)
			task.delay(0.85, function()
				if sparkHost.Parent ~= nil then
					sparkHost:Destroy()
				end
			end)
			if outcomeId == "Destroy" then
				clearDisplay()
			else
				task.spawn(shake, token)
			end
			if onImpact ~= nil then
				onImpact()
			end
			task.wait(0.08)
			ok = token == generation and active
		end
		if ok then
			tweenHammer(rest, 0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, token)
		end
		if token == generation then
			playing = false
		end
		return true
	end

	function api.preview(outcomeId: string)
		if active ~= true then
			return "closed"
		end
		if display == nil then
			api.showCar({
				modelId = "preview",
				qualityId = "Common",
				upgradeLevel = 0,
				displayName = "Preview",
			})
		end
		api.play(outcomeId, function() end)
		return "played"
	end

	pcall(function()
		RunService:UnbindFromRenderStep(CAMERA_BIND)
	end)
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, function()
		if active ~= true then
			return
		end
		local current = camera()
		if current == nil then
			return
		end
		current.CameraType = Enum.CameraType.Scriptable
		current.CFrame = goal
	end)

	local function forcedLeave()
		if active ~= true then
			return
		end
		api.leave()
		if onForcedExit ~= nil then
			onForcedExit()
		end
	end

	player.CharacterAdded:Connect(forcedLeave)
	local function watch(character: Model)
		local found = character:WaitForChild("Humanoid", 8)
		if found ~= nil and found:IsA("Humanoid") then
			found.Died:Connect(forcedLeave)
		end
	end
	if player.Character ~= nil then
		task.spawn(watch, player.Character)
	end

	if RunService:IsStudio() then
		_G.CarForgeTaxPreviewUpgrade = api.preview
	end

	return api
end

return WorkbenchView
