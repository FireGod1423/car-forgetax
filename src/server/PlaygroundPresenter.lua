-- 伺服器移動展示用的玩具車。位置來自競速模擬，客戶端不能回報成績。
local function importShared(moduleName: string)
	if game ~= nil then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild(moduleName))
	end
	return require("../shared/" .. moduleName)
end

local CarVisualFactory = importShared("CarVisualFactory")

local PlaygroundPresenter = {}

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

function PlaygroundPresenter.new()
	local models = {}
	local lanes = {}

	local function racesFolder()
		local playground = workspace:FindFirstChild("CarForgeTaxPlayground")
		if playground == nil then
			return nil
		end
		return playground:FindFirstChild("ActiveRaces")
	end

	return {
		onRaceStarted = function(raceId: string, spec)
			local parent = racesFolder()
			if parent == nil or type(raceId) ~= "string" then
				return
			end
			local existing = models[raceId]
			if existing ~= nil then
				existing:Destroy()
			end
			local model = CarVisualFactory.build({
				modelId = spec.modelId,
				qualityId = spec.qualityId,
				upgradeLevel = spec.upgradeLevel,
				displayName = spec.displayName,
			})
			model.Name = "ActiveRaceCar"
			model:SetAttribute("RaceId", raceId)
			model:SetAttribute("DisplayOnly", true)
			model.Parent = parent
			models[raceId] = model
			lanes[raceId] = laneOffset(spec.lane or 0)
			if spec.pose ~= nil then
				model:PivotTo(CarVisualFactory.poseCFrame(spec.pose, 0.45, lanes[raceId]))
			end
		end,
		onRaceStepped = function(raceId: string, pose)
			local model = models[raceId]
			if model == nil or model.Parent == nil or pose == nil then
				return
			end
			model:PivotTo(CarVisualFactory.poseCFrame(pose, 0.45, lanes[raceId] or 0))
		end,
		onRaceFinished = function(raceId: string)
			local model = models[raceId]
			models[raceId] = nil
			lanes[raceId] = nil
			if model ~= nil then
				model:Destroy()
			end
		end,
	}
end

return PlaygroundPresenter
