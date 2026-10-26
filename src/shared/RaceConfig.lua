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

-- 單場目標時間。最低性能對應較長時間，目前公式能到的最高性能對應較短時間。
RaceConfig.MinDuration = 20
RaceConfig.MaxDuration = 40

-- 機械暴君的固定基準。玩家完成時間必須低於這個秒數才算贏。
RaceConfig.BossTargetTime = 35
RaceConfig.BossSlowStart = 0.4
RaceConfig.BossSlowDuration = 3
RaceConfig.BossSlowFactor = 0.8

-- 測試金幣。正式經濟尚未實作，關服後會跟著錢包一起消失。
RaceConfig.NormalReward = 180
RaceConfig.BossWinReward = 450
RaceConfig.BossLoseReward = 0

RaceConfig.Layout = table.freeze({
	originX = 36,
	originY = 5,
	originZ = 0,
	width = 8,
	radius = 8,
	straight1 = 48,
	afterLoop = 24,
	jump = 20,
	jumpHorizontal = 18,
	jumpHeight = 5,
	finish = 34,
})

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function RaceConfig.loopLength(): number
	return 2 * math.pi * RaceConfig.Layout.radius
end

function RaceConfig.trackLength(): number
	local layout = RaceConfig.Layout
	return layout.straight1 + RaceConfig.loopLength() + layout.afterLoop + layout.jump + layout.finish
end

function RaceConfig.markers()
	local layout = RaceConfig.Layout
	local straightEnd = layout.straight1
	local loopEnd = straightEnd + RaceConfig.loopLength()
	local afterEnd = loopEnd + layout.afterLoop
	local jumpEnd = afterEnd + layout.jump
	local finishEnd = jumpEnd + layout.finish
	return {
		straightEnd = straightEnd,
		loopEnd = loopEnd,
		afterEnd = afterEnd,
		jumpEnd = jumpEnd,
		finishEnd = finishEnd,
	}
end

-- 競速換算用的性能兩端都從 CarConfig 讀，避免再寫一份性能公式。
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

local function normalize(x: number, y: number, z: number): (number, number, number)
	local magnitude = math.sqrt(x * x + y * y + z * z)
	if magnitude < 1e-6 then
		return 0, 0, 0
	end
	return x / magnitude, y / magnitude, z / magnitude
end

local function point(distance: number)
	local layout = RaceConfig.Layout
	local markers = RaceConfig.markers()
	local segment = "Finish"
	local x = 0
	local y = 0
	local z = 0

	if distance <= markers.straightEnd then
		segment = "Straight"
		x = distance
	elseif distance <= markers.loopEnd then
		segment = "Loop"
		local along = distance - markers.straightEnd
		local theta = -math.pi / 2 + (along / RaceConfig.loopLength()) * math.pi * 2
		local centerX = layout.straight1
		local centerY = layout.radius
		x = centerX + layout.radius * math.cos(theta)
		y = centerY + layout.radius * math.sin(theta)
	elseif distance <= markers.afterEnd then
		segment = "Straight"
		local along = distance - markers.loopEnd
		x = layout.straight1 + along
	elseif distance <= markers.jumpEnd then
		segment = "Jump"
		local along = distance - markers.afterEnd
		local alpha = if layout.jump <= 0 then 0 else along / layout.jump
		x = layout.straight1 + layout.afterLoop + layout.jumpHorizontal * alpha
		y = math.sin(math.pi * alpha) * layout.jumpHeight
	else
		segment = "Finish"
		local along = distance - markers.jumpEnd
		x = layout.straight1 + layout.afterLoop + layout.jumpHorizontal + along
	end

	return {
		segment = segment,
		x = layout.originX + x,
		y = layout.originY + y,
		z = layout.originZ + z,
		localX = x,
		localY = y,
	}
end

-- 迴圈的車頂朝向圓心，底部才會維持正立，頂部才會翻轉。
function RaceConfig.sample(distance: number)
	local length = RaceConfig.trackLength()
	local clamped = distance
	if not isFiniteNumber(clamped) then
		clamped = 0
	end
	clamped = math.clamp(clamped, 0, length)

	local here = point(clamped)
	local ahead = point(math.min(length, clamped + 0.4))
	local behind = point(math.max(0, clamped - 0.4))
	local lookX, lookY, lookZ = normalize(ahead.x - behind.x, ahead.y - behind.y, ahead.z - behind.z)
	if lookX == 0 and lookY == 0 and lookZ == 0 then
		lookX = 1
	end

	local upX, upY, upZ = 0, 1, 0
	if here.segment == "Loop" then
		local layout = RaceConfig.Layout
		local centerX = layout.originX + layout.straight1
		local centerY = layout.originY + layout.radius
		local centerZ = layout.originZ
		upX, upY, upZ = normalize(centerX - here.x, centerY - here.y, centerZ - here.z)
		if upX == 0 and upY == 0 and upZ == 0 then
			upX, upY, upZ = 0, 1, 0
		end
	end

	return {
		x = here.x,
		y = here.y,
		z = here.z,
		lookX = lookX,
		lookY = lookY,
		lookZ = lookZ,
		upX = upX,
		upY = upY,
		upZ = upZ,
		segment = here.segment,
	}
end

return RaceConfig
