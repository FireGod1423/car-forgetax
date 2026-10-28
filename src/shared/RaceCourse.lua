-- 未來正式賽道的接點。現在不建造賽道，也不決定長度或獎金。
-- 私人車庫測試圈不走這裡發獎。
local function importRankConfig()
	if game ~= nil then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild("RankConfig"))
	end
	return require("./RankConfig")
end

local RankConfig = importRankConfig()

local RaceCourse = {}

RaceCourse.Kind = {
	TestOval = "TestOval",
	PointToPoint = "PointToPoint",
}

function RaceCourse.testOval()
	return {
		id = "garage-test",
		kind = RaceCourse.Kind.TestOval,
		pays = false,
		closedLoop = true,
		autoRepeat = true,
		length = nil,
		reward = 0,
		built = true,
	}
end

function RaceCourse.officialSlot(id: string)
	return {
		id = id,
		kind = RaceCourse.Kind.PointToPoint,
		pays = true,
		closedLoop = false,
		autoRepeat = true,
		length = nil,
		reward = nil,
		built = false,
	}
end

function RaceCourse.ready(course): boolean
	return type(course) == "table"
		and course.built == true
		and course.kind == RaceCourse.Kind.PointToPoint
		and type(course.length) == "number"
		and course.length > 0
		and type(course.reward) == "number"
end

-- 長度或獎金還沒設定時拒絕開賽，避免測試圈被這條路發錢。
function RaceCourse.begin(course, baseDuration: number, rankLevel: number)
	if type(course) ~= "table" or course.pays ~= true or course.built ~= true then
		return nil, "CourseNotReady"
	end
	if course.kind ~= RaceCourse.Kind.PointToPoint or type(course.length) ~= "number" or course.length <= 0 or type(course.reward) ~= "number" then
		return nil, "CourseNotConfigured"
	end
	local duration = RankConfig.scaleDuration(baseDuration, rankLevel)
	if duration == nil then
		return nil, "InvalidDuration"
	end
	return {
		id = course.id,
		kind = course.kind,
		duration = duration,
		reward = course.reward,
		rankLevel = rankLevel,
		length = course.length,
	}, nil
end

return RaceCourse
