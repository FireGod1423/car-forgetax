-- 伺服器移動展示用的玩具車。位置來自競速模擬，客戶端不能回報成績。
local function importShared(moduleName: string)
	if game ~= nil then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild(moduleName))
	end
	return require("../shared/" .. moduleName)
end

local CarVisualFactory = importShared("CarVisualFactory")
local RaceConfig = importShared("RaceConfig")

local PlaygroundPresenter = {}

local WHEEL_RADIUS = 0.24
local WHEEL_NAMES = { "WheelFL", "WheelFR", "WheelRL", "WheelRR" }

local function laneOffset(lane: number): number
	if lane == 1 then
		return 2.2
	elseif lane == 2 then
		return -2.2
	elseif lane == 3 then
		return 3.3
	elseif lane == 4 then
		return -3.3
	end
	return 0
end

-- 跟 PrivateGarage.RaceShift 同一組數字。付費賽車只出現在賽車場，不跟著車庫平移。
local RACE_SHIFT = Vector3.new(274, 0, -1)

local function withShift(pose)
	if pose == nil then
		return pose
	end
	return {
		x = pose.x + RACE_SHIFT.X,
		y = pose.y + RACE_SHIFT.Y,
		z = pose.z + RACE_SHIFT.Z,
		lookX = pose.lookX,
		lookY = pose.lookY,
		lookZ = pose.lookZ,
		upX = pose.upX,
		upY = pose.upY,
		upZ = pose.upZ,
		segment = pose.segment,
		distance = pose.distance,
	}
end

local function visualPose(pose)
	local official = 0
	if pose ~= nil and type(pose.distance) == "number" then
		official = pose.distance
	end
	local total = RaceConfig.trackLength()
	local alpha = 0
	if total > 0 then
		alpha = math.clamp(official / total, 0, 1)
	end
	local visualDistance = RaceConfig.visualAlpha(alpha) * total
	return RaceConfig.sample(visualDistance), alpha, visualDistance
end

local function placeCar(model, pose, lateral: number, alpha: number, visualDistance: number, wheels)
	local ride = 0.5 + math.sin(visualDistance * 1.25) * 0.02
	local placed = CarVisualFactory.poseCFrame(pose, ride, lateral)
	if alpha < 0.18 then
		local launch = 1 - alpha / 0.18
		placed = placed * CFrame.Angles(-0.045 * launch, 0, 0)
	end
	model:PivotTo(placed)
	local spin = CFrame.Angles(visualDistance / WHEEL_RADIUS, 0, 0)
	for _, wheel in ipairs(wheels) do
		if wheel.part.Parent ~= nil then
			wheel.part.CFrame = placed * wheel.rest * spin
		end
	end
	return placed
end

local function attachEffects(model)
	local body = model:FindFirstChild("Body")
	if body == nil or not body:IsA("BasePart") then
		return nil, nil
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
	dust.Color = ColorSequence.new(Color3.fromRGB(255, 214, 150))
	dust.LightEmission = 0.25
	dust.EmissionDirection = Enum.NormalId.Back
	dust.Enabled = true
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
	return dust, trail
end

local function finishBurst(cframe: CFrame, parent: Instance?)
	if parent == nil then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "FinishBurst"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = cframe
	anchor.Parent = parent
	local burst = Instance.new("ParticleEmitter")
	burst.Name = "FinishSparks"
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Rate = 0
	burst.Lifetime = NumberRange.new(0.18, 0.35)
	burst.Speed = NumberRange.new(3, 7)
	burst.SpreadAngle = Vector2.new(35, 35)
	burst.Size = NumberSequence.new(0.32, 0)
	burst.LightEmission = 0.65
	burst.Color = ColorSequence.new(Color3.fromRGB(255, 226, 110))
	burst.Parent = anchor
	burst:Emit(14)
	game:GetService("Debris"):AddItem(anchor, 0.6)
end

function PlaygroundPresenter.new()
	local models = {}
	local lanes = {}
	local shifts = {}
	local wheelSets = {}
	local dusts = {}
	local trails = {}

	local function racesFolder()
		local playground = workspace:FindFirstChild("CarForgeTaxPlayground")
		if playground == nil then
			return nil
		end
		return playground:FindFirstChild("ActiveRaces")
	end

	local function clearRace(raceId: string)
		local model = models[raceId]
		models[raceId] = nil
		lanes[raceId] = nil
		shifts[raceId] = nil
		wheelSets[raceId] = nil
		dusts[raceId] = nil
		trails[raceId] = nil
		if model ~= nil then
			model:Destroy()
		end
	end

	return {
		onRaceStarted = function(raceId: string, spec)
			local parent = racesFolder()
			if parent == nil or type(raceId) ~= "string" then
				return
			end
			clearRace(raceId)
			local model = CarVisualFactory.build({
				modelId = spec.modelId,
				qualityId = spec.qualityId,
				upgradeLevel = spec.upgradeLevel,
				displayName = spec.displayName,
			})
			model.Name = "ActiveRaceCar"
			model:SetAttribute("RaceId", raceId)
			model:SetAttribute("DisplayOnly", true)
			if type(spec.ownerKey) == "string" then
				model:SetAttribute("OwnerKey", spec.ownerKey)
			end
			model.Parent = parent
			models[raceId] = model
			lanes[raceId] = laneOffset(spec.lane or 0)
			shifts[raceId] = spec.shift

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
			wheelSets[raceId] = wheels
			local dust, trail = attachEffects(model)
			dusts[raceId] = dust
			trails[raceId] = trail
			if spec.pose ~= nil then
				local pose, alpha, visualDistance = visualPose(spec.pose)
				placeCar(model, withShift(pose), lanes[raceId], alpha, visualDistance, wheels)
			end
		end,
		onRaceStepped = function(raceId: string, pose)
			local model = models[raceId]
			if model == nil or model.Parent == nil or pose == nil then
				return
			end
			local shown, alpha, visualDistance = visualPose(pose)
			placeCar(model, withShift(shown), lanes[raceId] or 0, alpha, visualDistance, wheelSets[raceId] or {})
			local dust = dusts[raceId]
			if dust ~= nil then
				dust.Enabled = alpha < 0.045
			end
			local trail = trails[raceId]
			if trail ~= nil then
				trail.Enabled = alpha > 0.08
			end
		end,
		onRaceFinished = function(raceId: string, completed: boolean?)
			local model = models[raceId]
			if completed == true and model ~= nil and model.Parent ~= nil then
				finishBurst(model:GetPivot(), racesFolder())
			end
			clearRace(raceId)
		end,
	}
end

return PlaygroundPresenter
