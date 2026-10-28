-- 競速時間、性能換算、賽道幾何與測試獎金。性能本體仍只來自 CarConfig。
local function importCarConfig()
	if game ~= nil then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild("CarConfig"))
	end
	return require("./CarConfig")
end

local CarConfig = importCarConfig()

local RaceConfig = {}

-- 單場目標時間。普通車約 10 秒，公式上限也停在 5 秒，避免高性能車接近 0 秒。
RaceConfig.MinDuration = 5
RaceConfig.MaxDuration = 10

-- 機械暴君的固定基準。跟著縮短後的完賽時間，慢車仍輸、高階車仍贏。
RaceConfig.BossTargetTime = 10
RaceConfig.BossSlowStart = 0.4
RaceConfig.BossSlowDuration = 3
RaceConfig.BossSlowFactor = 0.8

-- 測試金幣。正式經濟尚未實作，關服後會跟著錢包一起消失。
-- 概念版測試值。10 秒一場，所以普通獎勵從 180 改為 45，避免金幣產出直接變四倍。
RaceConfig.NormalReward = 45
RaceConfig.BossWinReward = 450
RaceConfig.BossLoseReward = 0

-- 短圈是視覺路線。圈數只決定展示車要繞幾圈，完賽秒數仍由 baseDuration 決定。
RaceConfig.Layout = table.freeze({
	originX = 46,
	originY = 2.2,
	originZ = 1,
	width = 9,
	straight = 22,
	radius = 9.5,
	visualLaps = 2,
})

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function RaceConfig.lapLength(): number
	local layout = RaceConfig.Layout
	return layout.straight * 2 + 2 * math.pi * layout.radius
end

function RaceConfig.trackLength(): number
	return RaceConfig.lapLength() * RaceConfig.Layout.visualLaps
end

function RaceConfig.markers()
	local layout = RaceConfig.Layout
	local half = layout.straight * 0.5
	local arc = math.pi * layout.radius
	local startEnd = half
	local curveEnd = startEnd + arc
	local backEnd = curveEnd + layout.straight
	local returnEnd = backEnd + arc
	return {
		startEnd = startEnd,
		curveEnd = curveEnd,
		backEnd = backEnd,
		returnEnd = returnEnd,
		lapEnd = RaceConfig.lapLength(),
		finishEnd = RaceConfig.trackLength(),
	}
end

-- 起跑先慢、再拉到巡航，終點仍落在正式距離的終點。不改變完賽秒數。
function RaceConfig.visualAlpha(alpha: number): number
	if not isFiniteNumber(alpha) then
		return 0
	end
	local progress = math.clamp(alpha, 0, 1)
	local launch = 0.18
	local startScale = 0.12
	local average = 0.5 * (1 + startScale)
	local cruise = 1 / (average * launch + (1 - launch))
	if progress <= launch then
		local unit = progress / launch
		local curve = unit * unit * unit - 0.5 * unit * unit * unit * unit
		local covered = startScale * unit + (1 - startScale) * curve
		return cruise * launch * covered
	end
	local launchDistance = cruise * launch * average
	return launchDistance + cruise * (progress - launch)
end

-- 競速換算的兩端仍沿用原本的尺度，避免把既有完賽時間整段重排。
-- 這個上限含舊的重生餘量，但 calculatePower 不會再把 T 等級加進車輛。
function RaceConfig.powerBounds(): (number, number)
	local qualityBonus, qualityReason = CarConfig.getQualityBonus("Legendary")
	local rebirthBonus, rebirthReason = CarConfig.getRebirthBonus(CarConfig.MaxRebirthLevel)
	if qualityBonus == nil or rebirthBonus == nil then
		error(qualityReason or rebirthReason or "缺少競速性能範圍")
	end
	local minPower = CarConfig.BasePower
	local maxPower = CarConfig.BasePower
		+ (CarConfig.PowerPerUpgradeLevel * CarConfig.MaxUpgradeLevel)
		+ qualityBonus
		+ rebirthBonus
	return minPower, maxPower
end

function RaceConfig.baseDuration(power: number): (number?, string?)
	if not isFiniteNumber(power) then
		return nil, "InvalidPower"
	end
	local minPower, maxPower = RaceConfig.powerBounds()
	local alpha = 0
	if maxPower > minPower then
		alpha = (power - minPower) / (maxPower - minPower)
	end
	alpha = math.clamp(alpha, 0, 1)
	local duration = RaceConfig.MaxDuration - (RaceConfig.MaxDuration - RaceConfig.MinDuration) * alpha
	return duration, nil
end

-- slow 為 nil 時是一般競速。有緩速時，速度在指定距離後降為 factor，並只持續 duration 秒。
function RaceConfig.travelTime(distance: number, speed: number, slow): (number?, string?)
	if not isFiniteNumber(distance) or distance < 0 or not isFiniteNumber(speed) or speed <= 0 then
		return nil, "InvalidMotion"
	end
	if slow == nil then
		return distance / speed, nil
	end
	if not isFiniteNumber(slow.startDistance) or not isFiniteNumber(slow.duration) or slow.duration < 0 then
		return nil, "InvalidSlow"
	end
	if not isFiniteNumber(slow.factor) or slow.factor <= 0 or slow.factor > 1 then
		return nil, "InvalidSlow"
	end

	local startDistance = math.clamp(slow.startDistance, 0, distance)
	local remaining = distance - startDistance
	local slowSpeed = speed * slow.factor
	local slowDistance = slowSpeed * slow.duration
	local timeToSlow = startDistance / speed
	if remaining <= slowDistance then
		return timeToSlow + (remaining / slowSpeed), nil
	end
	return timeToSlow + slow.duration + ((remaining - slowDistance) / speed), nil
end

function RaceConfig.distanceAtTime(elapsed: number, speed: number, slow, distance: number): number
	if not isFiniteNumber(elapsed) or elapsed <= 0 then
		return 0
	end
	if not isFiniteNumber(distance) or distance <= 0 or not isFiniteNumber(speed) or speed <= 0 then
		return 0
	end
	if slow == nil then
		return math.min(distance, speed * elapsed)
	end

	local startDistance = math.clamp(slow.startDistance, 0, distance)
	local timeToSlow = startDistance / speed
	if elapsed <= timeToSlow then
		return math.min(distance, speed * elapsed)
	end

	local slowSpeed = speed * slow.factor
	local slowEnd = timeToSlow + slow.duration
	if elapsed <= slowEnd then
		return math.min(distance, startDistance + slowSpeed * (elapsed - timeToSlow))
	end

	local coveredDuringSlow = math.min(distance - startDistance, slowSpeed * slow.duration)
	local after = startDistance + coveredDuringSlow + speed * (elapsed - slowEnd)
	return math.min(distance, after)
end

function RaceConfig.bossVictory(duration: number): boolean
	return isFiniteNumber(duration) and duration < RaceConfig.BossTargetTime
end

function RaceConfig.describe(power: number, bossSlow: boolean)
	local base, reason = RaceConfig.baseDuration(power)
	if base == nil then
		return nil, reason
	end

	local length = RaceConfig.trackLength()
	local speed = length / base
	local slow = nil
	if bossSlow == true then
		slow = {
			startDistance = length * RaceConfig.BossSlowStart,
			duration = RaceConfig.BossSlowDuration,
			factor = RaceConfig.BossSlowFactor,
		}
	end

	local duration, timeReason = RaceConfig.travelTime(length, speed, slow)
	if duration == nil then
		return nil, timeReason
	end

	local won = nil
	local reward = RaceConfig.NormalReward
	if bossSlow == true then
		won = RaceConfig.bossVictory(duration)
		reward = if won then RaceConfig.BossWinReward else RaceConfig.BossLoseReward
	end

	return {
		power = power,
		baseDuration = base,
		duration = duration,
		speed = speed,
		slow = slow,
		won = won,
		reward = reward,
		bossTarget = if bossSlow == true then RaceConfig.BossTargetTime else nil,
	}, nil
end

-- 閉合短圈：起跑直線、外彎、回頭直線、回彎，最後衝刺直線回到起跑線。
local function pointOnLap(distance: number)
	local layout = RaceConfig.Layout
	local markers = RaceConfig.markers()
	local half = layout.straight * 0.5
	local radius = layout.radius
	local segment = "Start"
	local x = 0
	local z = -radius
	local lookX = 1
	local lookZ = 0

	if distance <= markers.startEnd then
		segment = "Start"
		x = distance
		z = -radius
		lookX, lookZ = 1, 0
	elseif distance <= markers.curveEnd then
		segment = "Curve"
		local arc = markers.curveEnd - markers.startEnd
		local unit = if arc <= 0 then 0 else (distance - markers.startEnd) / arc
		local theta = -math.pi / 2 + unit * math.pi
		x = half + radius * math.cos(theta)
		z = radius * math.sin(theta)
		lookX = -math.sin(theta)
		lookZ = math.cos(theta)
	elseif distance <= markers.backEnd then
		segment = "Straight"
		local along = distance - markers.curveEnd
		x = half - along
		z = radius
		lookX, lookZ = -1, 0
	elseif distance <= markers.returnEnd then
		segment = "Curve"
		local arc = markers.returnEnd - markers.backEnd
		local unit = if arc <= 0 then 0 else (distance - markers.backEnd) / arc
		local theta = math.pi / 2 + unit * math.pi
		x = -half + radius * math.cos(theta)
		z = radius * math.sin(theta)
		lookX = -math.sin(theta)
		lookZ = math.cos(theta)
	else
		segment = "Sprint"
		local along = distance - markers.returnEnd
		x = -half + along
		z = -radius
		lookX, lookZ = 1, 0
	end

	local look = Vector3.new(lookX, 0, lookZ)
	if look.Magnitude < 1e-6 then
		look = Vector3.xAxis
	else
		look = look.Unit
	end
	-- 中心線保持水平。凹槽是左右肩部同時墊高，不是把整塊路面往一側翻。
	return {
		segment = segment,
		x = layout.originX + x,
		y = layout.originY,
		z = layout.originZ + z,
		lookX = look.X,
		lookY = 0,
		lookZ = look.Z,
		upX = 0,
		upY = 1,
		upZ = 0,
	}
end

function RaceConfig.sample(distance: number)
	local length = RaceConfig.trackLength()
	local lap = RaceConfig.lapLength()
	local clamped = distance
	if not isFiniteNumber(clamped) then
		clamped = 0
	end
	clamped = math.clamp(clamped, 0, length)

	local along = 0
	if lap > 0 then
		along = clamped % lap
		if clamped > 0 and along < 1e-4 then
			along = 0
		end
	end

	local here = pointOnLap(along)
	return {
		x = here.x,
		y = here.y,
		z = here.z,
		lookX = here.lookX,
		lookY = here.lookY,
		lookZ = here.lookZ,
		upX = here.upX,
		upY = here.upY,
		upZ = here.upZ,
		segment = here.segment,
		distance = clamped,
	}
end

return RaceConfig
