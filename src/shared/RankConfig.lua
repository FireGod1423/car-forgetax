-- 職業等級就是重生等級。顯示用 T0 到 T10。
-- 速度加成只縮短完賽時間，不寫進 CarConfig.calculatePower。
local RankConfig = {}

local RANKS = {
	[0] = { id = "T0", name = "Rookie" },
	[1] = { id = "T1", name = "Street Racer" },
	[2] = { id = "T2", name = "Amateur Racer" },
	[3] = { id = "T3", name = "Pro Racer" },
	[4] = { id = "T4", name = "Elite Racer" },
	[5] = { id = "T5", name = "Racing Champion" },
	[6] = { id = "T6", name = "Track Master" },
	[7] = { id = "T7", name = "Grandmaster" },
	[8] = { id = "T8", name = "Racing Legend" },
	[9] = { id = "T9", name = "Racing Myth" },
	[10] = { id = "T10", name = "Racing God" },
}

function RankConfig.get(level: number)
	if type(level) ~= "number" then
		return nil
	end
	return RANKS[level]
end

function RankConfig.label(level: number): string
	local rank = RankConfig.get(level)
	if rank == nil then
		return "--"
	end
	return rank.id .. " " .. rank.name
end

function RankConfig.speedBonus(level: number): number
	if RankConfig.get(level) == nil then
		return 0
	end
	return level * 0.05
end

function RankConfig.boostLabel(level: number): string
	local rank = RankConfig.get(level)
	if rank == nil then
		return "--"
	end
	return string.format("%s +%d%%", rank.id, level * 5)
end

function RankConfig.scaleDuration(duration: number, level: number): number?
	if type(duration) ~= "number" or duration ~= duration or duration <= 0 or duration >= math.huge then
		return nil
	end
	return duration / (1 + RankConfig.speedBonus(level))
end

-- 最短時間已經含在原始完賽時間裡。這裡不再夾回 MinDuration，避免高 T 完全沒有加速。
function RankConfig.scalePlan(plan, level: number)
	if type(plan) ~= "table" or type(plan.duration) ~= "number" or type(plan.speed) ~= "number" then
		return nil
	end
	local factor = 1 + RankConfig.speedBonus(level)
	local scaled = {
		power = plan.power,
		baseDuration = plan.baseDuration,
		duration = plan.duration / factor,
		speed = plan.speed * factor,
		slow = nil,
		won = plan.won,
		reward = plan.reward,
		bossTarget = plan.bossTarget,
		rankLevel = level,
		rankBonus = factor - 1,
	}
	if type(plan.slow) == "table" then
		scaled.slow = {
			startDistance = plan.slow.startDistance,
			duration = plan.slow.duration / factor,
			factor = plan.slow.factor,
		}
		if plan.bossTarget ~= nil and type(scaled.duration) == "number" then
			scaled.won = scaled.duration < plan.bossTarget
		end
	end
	return scaled
end

return RankConfig
