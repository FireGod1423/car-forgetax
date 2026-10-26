-- 概念原型的玩家流程。抽車、強化與發獎都走既有伺服器服務，客戶端不能指定結果。
local function importShared(moduleName: string)
	if game ~= nil then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild(moduleName))
	end
	return require("../shared/" .. moduleName)
end

local function importServer(moduleName: string)
	if game ~= nil then
		return require(script.Parent:WaitForChild(moduleName))
	end
	return require("./" .. moduleName)
end

local CarConfig = importShared("CarConfig")
local CarCatalog = importShared("CarCatalog")
local UpgradeConfig = importShared("UpgradeConfig")
local RaceConfig = importShared("RaceConfig")
local GoldWallet = importServer("GoldWallet")
local CarInventoryService = importServer("CarInventoryService")
local CarGachaService = importServer("CarGachaService")
local CarUpgradeService = importServer("CarUpgradeService")

local PlaySessionService = {}

PlaySessionService.MemoryNotice = "關服後車庫與金幣會消失。目前是記憶體測試資料，不是正式存檔。"
PlaySessionService.StarterModelId = "test_common_r0"
PlaySessionService.PullInterval = 1.5
PlaySessionService.UpgradeInterval = 0.75

PlaySessionService.Reason = table.freeze({
	InvalidPlayer = "InvalidPlayer",
	InvalidRequest = "InvalidRequest",
	InvalidToken = "InvalidToken",
	UnknownAction = "UnknownAction",
	RateLimited = "RateLimited",
	UnknownCar = "UnknownCar",
	UnknownModel = "UnknownModel",
	NoSelectedCar = "NoSelectedCar",
	RaceInProgress = "RaceInProgress",
	InvalidPower = "InvalidPower",
})

local ACTIONS = {
	GetState = true,
	Pull = true,
	Upgrade = true,
	SelectCar = true,
	StartRace = true,
	StartBoss = true,
}

local function isPlayerKey(playerKey: any): boolean
	if type(playerKey) == "string" then
		return playerKey ~= ""
	end
	if type(playerKey) == "number" then
		return playerKey == playerKey and playerKey % 1 == 0 and playerKey > 0
	end
	return false
end

local function copyShallow(source)
	local copy = {}
	if source == nil then
		return copy
	end
	for key, value in pairs(source) do
		copy[key] = value
	end
	return copy
end

function PlaySessionService.new(options)
	options = options or {}
	local clock = options.clock or os.clock
	local isStudio = options.isStudio == true
	local presenter = options.presenter
	local notify = options.notify
	local sessions = {}
	local usedLanes = {}
	local sequence = 0

	local function emit(method: string, ...)
		if presenter == nil or type(presenter[method]) ~= "function" then
			return
		end
		local ok, err = pcall(presenter[method], ...)
		if not ok then
			warn("[CarForgeTax] 場景呈現失敗：" .. tostring(err))
		end
	end

	local function tell(playerKey, payload)
		if notify == nil then
			return
		end
		local ok, err = pcall(notify, playerKey, payload)
		if not ok then
			warn("[CarForgeTax] 競賽通知失敗：" .. tostring(err))
		end
	end

	local function mint(action: string): string
		sequence += 1
		return string.format("%s:%d", action, sequence)
	end

	local function normalizeToken(token: any): (string?, string?)
		if token == nil then
			return nil, nil
		end
		if type(token) ~= "string" or #token < 8 or #token > 48 then
			return nil, PlaySessionService.Reason.InvalidToken
		end
		if string.match(token, "^[%w%-]+$") ~= token then
			return nil, PlaySessionService.Reason.InvalidToken
		end
		return token, nil
	end

	local function readInstanceId(request): (string?, string?)
		if request.instanceId == nil then
			return nil, nil
		end
		if type(request.instanceId) ~= "string" or request.instanceId == "" or #request.instanceId > 80 then
			return nil, CarInventoryService.Reason.InvalidInstanceId
		end
		return request.instanceId, nil
	end

	local function carView(session, record)
		local model = CarCatalog.getByModelId(record.ModelId)
		if model == nil then
			return nil
		end
		local quality = CarConfig.getQuality(model.Quality)
		local power = CarConfig.calculatePower(record.UpgradeLevel, model.Quality, record.AcquiredRebirth)
		return {
			instanceId = record.InstanceId,
			modelId = record.ModelId,
			displayName = model.DisplayName,
			qualityId = model.Quality,
			qualityName = if quality ~= nil then quality.DisplayName else model.Quality,
			colorName = if quality ~= nil then quality.ColorName else "",
			upgradeLevel = record.UpgradeLevel,
			acquiredRebirth = record.AcquiredRebirth,
			power = power,
		}
	end

	local function listCars(session)
		local records = session.inventory:ListCars(session.key)
		local cars = {}
		if records == nil then
			return cars
		end
		for _, record in ipairs(records) do
			local view = carView(session, record)
			if view ~= nil then
				table.insert(cars, view)
			end
		end
		return cars
	end

	local function publicState(session, extra)
		local balance = session.wallet:GetBalance(session.key)
		local state = {
			ok = true,
			balance = balance,
			memoryNotice = PlaySessionService.MemoryNotice,
			studioSession = session.studioTools,
			selectedInstanceId = session.selectedInstanceId,
			pullPrice = CarConfig.SinglePullPrice,
			cars = listCars(session),
			raceActive = session.race ~= nil and session.race.active == true,
			raceId = if session.race ~= nil then session.race.raceId else nil,
			raceMode = if session.race ~= nil then session.race.mode else nil,
		}
		if extra ~= nil then
			for key, value in pairs(extra) do
				state[key] = value
			end
		end
		return state
	end

	local function acquireLane(): number
		for lane = 0, 4 do
			if usedLanes[lane] ~= true then
				usedLanes[lane] = true
				return lane
			end
		end
		return 0
	end

	local function releaseLane(lane: number?)
		if lane ~= nil then
			usedLanes[lane] = nil
		end
	end

	local function finishRace(session, race)
		if race.rewarded == true or race.cancelled == true then
			race.active = false
			releaseLane(race.lane)
			race.lane = nil
			return
		end
		race.rewarded = true
		race.active = false
		local amount = race.plan.reward
		if type(amount) == "number" and amount > 0 then
			session.wallet:Credit(session.key, amount)
		end
		local balance = session.wallet:GetBalance(session.key)
		emit("onRaceFinished", race.raceId)
		releaseLane(race.lane)
		race.lane = nil
		tell(session.key, {
			ok = true,
			raceId = race.raceId,
			mode = race.mode,
			duration = race.plan.duration,
			power = race.plan.power,
			reward = amount,
			balance = balance,
			won = race.plan.won,
			bossTarget = race.plan.bossTarget,
			memoryNotice = PlaySessionService.MemoryNotice,
		})
	end

	local function stepRace(session, now: number)
		local race = session.race
		if race == nil or race.active ~= true then
			return
		end
		local elapsed = now - race.startedAt
		local length = RaceConfig.trackLength()
		local distance = RaceConfig.distanceAtTime(elapsed, race.plan.speed, race.plan.slow, length)
		local pose = RaceConfig.sample(distance)
		emit("onRaceStepped", race.raceId, pose)
		-- 浮點數會讓「剛好等於完賽時間」少一點點，用很小的容差補上，避免卡在終點前。
		if elapsed + 1e-4 >= race.plan.duration then
			finishRace(session, race)
		end
	end

	local service = {}

	function service:createSession(playerKey, sessionOptions)
		if not isPlayerKey(playerKey) then
			return nil, PlaySessionService.Reason.InvalidPlayer
		end
		local existing = sessions[playerKey]
		if existing ~= nil then
			return existing, nil
		end

		sessionOptions = sessionOptions or {}
		local studioTools = isStudio
		if sessionOptions.isStudio ~= nil then
			studioTools = sessionOptions.isStudio == true
		end

		-- 車庫自己的 ID 產生器不要跟抽車、強化共用，避免測試隨機序列被起始車吃掉。
		local inventory = CarInventoryService.new()
		local wallet = GoldWallet.new()
		local gacha = CarGachaService.new({
			inventory = inventory,
			wallet = wallet,
			rng = sessionOptions.gachaRng or sessionOptions.rng,
		})
		local upgrade = CarUpgradeService.new({
			inventory = inventory,
			rng = sessionOptions.upgradeRng or sessionOptions.rng,
		})
		local session = {
			key = playerKey,
			inventory = inventory,
			wallet = wallet,
			gacha = gacha,
			upgrade = upgrade,
			-- 還沒有重生服務。抽車階級只由伺服器固定為 0，不讀客戶端。
			rebirthLevel = 0,
			selectedInstanceId = nil,
			tokens = {},
			raceStarts = {},
			lastPull = -math.huge,
			lastUpgrade = -math.huge,
			race = nil,
			studioTools = studioTools,
		}
		sessions[playerKey] = session

		if studioTools then
			wallet:GrantTestGold(playerKey)
			local starter, starterReason = inventory:CreateCar(playerKey, PlaySessionService.StarterModelId, 0)
			if starter ~= nil then
				session.selectedInstanceId = starter.InstanceId
			else
				warn("[CarForgeTax] 起始測試車建立失敗：" .. tostring(starterReason))
			end
		end
		return session, nil
	end

	function service:removeSession(playerKey)
		local session = sessions[playerKey]
		if session == nil then
			return
		end
		if session.race ~= nil and session.race.active == true then
			session.race.cancelled = true
			session.race.active = false
			emit("onRaceFinished", session.race.raceId)
			releaseLane(session.race.lane)
		end
		sessions[playerKey] = nil
	end

	function service:advanceAll(now: number)
		local keys = {}
		for playerKey in pairs(sessions) do
			table.insert(keys, playerKey)
		end
		for _, playerKey in ipairs(keys) do
			local session = sessions[playerKey]
			if session ~= nil then
				stepRace(session, now)
			end
		end
	end

	local function beginRace(session, mode: string, request, token: string)
		local storageKey = mode .. "\0" .. token
		local previous = session.raceStarts[storageKey]
		if previous ~= nil then
			local replay = copyShallow(previous)
			replay.replayed = true
			return replay
		end
		if session.race ~= nil and session.race.active == true then
			return {
				ok = false,
				reason = PlaySessionService.Reason.RaceInProgress,
				raceId = session.race.raceId,
			}
		end

		local requestedId = request.instanceId
		if requestedId ~= nil and type(requestedId) ~= "string" then
			requestedId = nil
		end
		if type(requestedId) == "string" and (requestedId == "" or #requestedId > 80) then
			return {
				ok = false,
				reason = CarInventoryService.Reason.InvalidInstanceId,
			}
		end
		local instanceId = requestedId or session.selectedInstanceId
		if type(instanceId) ~= "string" or instanceId == "" then
			return {
				ok = false,
				reason = PlaySessionService.Reason.NoSelectedCar,
			}
		end
		local record, carReason = session.inventory:GetCar(session.key, instanceId)
		if record == nil then
			return {
				ok = false,
				reason = carReason or PlaySessionService.Reason.UnknownCar,
			}
		end
		local model = CarCatalog.getByModelId(record.ModelId)
		if model == nil then
			return {
				ok = false,
				reason = PlaySessionService.Reason.UnknownModel,
			}
		end
		local power, powerReason = CarConfig.calculatePower(record.UpgradeLevel, model.Quality, record.AcquiredRebirth)
		if power == nil then
			return {
				ok = false,
				reason = powerReason or PlaySessionService.Reason.InvalidPower,
			}
		end

		local bossSlow = mode == "boss"
		local plan, planReason = RaceConfig.describe(power, bossSlow)
		if plan == nil then
			return {
				ok = false,
				reason = planReason or PlaySessionService.Reason.InvalidPower,
			}
		end

		local raceId = mint(mode)
		local lane = acquireLane()
		local pose = RaceConfig.sample(0)
		local startedAt = clock()
		local slowStart = nil
		if plan.slow ~= nil then
			slowStart = plan.slow.startDistance / plan.speed
		end
		local ack = {
			ok = true,
			replayed = false,
			raceId = raceId,
			mode = mode,
			duration = plan.duration,
			power = power,
			bossTarget = plan.bossTarget,
			slowStart = slowStart,
			slowDuration = if plan.slow ~= nil then plan.slow.duration else nil,
			slowFactor = if plan.slow ~= nil then plan.slow.factor else nil,
			displayName = model.DisplayName,
			modelId = model.ModelId,
			qualityId = model.Quality,
			upgradeLevel = record.UpgradeLevel,
			instanceId = record.InstanceId,
		}
		session.race = {
			active = true,
			rewarded = false,
			cancelled = false,
			raceId = raceId,
			mode = mode,
			lane = lane,
			plan = plan,
			startedAt = startedAt,
			instanceId = record.InstanceId,
		}
		session.selectedInstanceId = record.InstanceId
		session.tokens[storageKey] = raceId
		session.raceStarts[storageKey] = copyShallow(ack)
		emit("onRaceStarted", raceId, {
			modelId = model.ModelId,
			qualityId = model.Quality,
			upgradeLevel = record.UpgradeLevel,
			displayName = model.DisplayName,
			lane = lane,
			pose = pose,
		})
		return copyShallow(ack)
	end

	local function reservedCall(session, action: string, token: string, interval: number, invoke)
		local storageKey = action .. "\0" .. token
		local requestId = session.tokens[storageKey]
		if requestId == nil then
			local last = if action == "Pull" then session.lastPull else session.lastUpgrade
			if clock() - last < interval then
				return {
					ok = false,
					reason = PlaySessionService.Reason.RateLimited,
					balance = session.wallet:GetBalance(session.key),
				}
			end
			requestId = mint(action)
			session.tokens[storageKey] = requestId
			if action == "Pull" then
				session.lastPull = clock()
			else
				session.lastUpgrade = clock()
			end
		end
		local result = invoke(requestId)
		result.replayed = result.replayed == true
		return result
	end

	function service:dispatch(playerKey, request)
		if not isPlayerKey(playerKey) then
			return {
				ok = false,
				reason = PlaySessionService.Reason.InvalidPlayer,
			}
		end
		local session = sessions[playerKey]
		if session == nil then
			return {
				ok = false,
				reason = PlaySessionService.Reason.InvalidPlayer,
			}
		end
		if type(request) ~= "table" then
			return {
				ok = false,
				reason = PlaySessionService.Reason.InvalidRequest,
			}
		end
		local action = request.action
		if type(action) ~= "string" or ACTIONS[action] ~= true then
			return {
				ok = false,
				reason = PlaySessionService.Reason.UnknownAction,
				balance = session.wallet:GetBalance(session.key),
			}
		end

		if action == "GetState" then
			return publicState(session)
		end

		local token, tokenReason = normalizeToken(request.attemptToken)
		if tokenReason ~= nil then
			return {
				ok = false,
				reason = tokenReason,
			}
		end
		if token == nil then
			token = mint("client")
		end

		if action == "SelectCar" then
			local instanceId, idReason = readInstanceId(request)
			if idReason ~= nil or instanceId == nil then
				return {
					ok = false,
					reason = idReason or CarInventoryService.Reason.InvalidInstanceId,
				}
			end
			local record, carReason = session.inventory:GetCar(session.key, instanceId)
			if record == nil then
				return {
					ok = false,
					reason = carReason or PlaySessionService.Reason.UnknownCar,
				}
			end
			session.selectedInstanceId = record.InstanceId
			return publicState(session)
		end

		if action == "Pull" then
			local outcome = reservedCall(session, action, token, PlaySessionService.PullInterval, function(requestId)
				local result = session.gacha:Pull(session.key, session.rebirthLevel, requestId)
				local view = nil
				if result.car ~= nil then
					view = carView(session, result.car)
				elseif result.modelId ~= nil then
					local model = CarCatalog.getByModelId(result.modelId)
					local quality = if result.quality ~= nil then CarConfig.getQuality(result.quality) else nil
					view = {
						modelId = result.modelId,
						displayName = if model ~= nil then model.DisplayName else result.modelId,
						qualityId = result.quality,
						qualityName = if quality ~= nil then quality.DisplayName else result.quality,
					}
				end
				return {
					ok = result.ok == true,
					reason = result.reason,
					replayed = result.replayed == true,
					price = result.price,
					balance = result.balance or session.wallet:GetBalance(session.key),
					charged = result.charged == true,
					qualityId = if view ~= nil then view.qualityId else result.quality,
					qualityName = if view ~= nil then view.qualityName else nil,
					modelId = if view ~= nil then view.modelId else result.modelId,
					displayName = if view ~= nil then view.displayName else nil,
					instanceId = if view ~= nil then view.instanceId else nil,
					upgradeLevel = if view ~= nil then view.upgradeLevel else nil,
					power = if view ~= nil then view.power else nil,
				}
			end)
			return outcome
		end

		if action == "Upgrade" then
			local instanceId, idReason = readInstanceId(request)
			if instanceId == nil and session.selectedInstanceId ~= nil then
				instanceId = session.selectedInstanceId
				idReason = nil
			end
			if idReason ~= nil or instanceId == nil then
				return {
					ok = false,
					reason = idReason or CarInventoryService.Reason.InvalidInstanceId,
				}
			end
			return reservedCall(session, action, token, PlaySessionService.UpgradeInterval, function(requestId)
				local result = session.upgrade:Upgrade(session.key, instanceId, requestId)
				local affectedId = result.instanceId or instanceId
				if result.removed == true and session.selectedInstanceId == affectedId then
					session.selectedInstanceId = nil
				end
				local outcomeName = nil
				if result.outcome ~= nil then
					for _, outcome in ipairs(UpgradeConfig.getOutcomes()) do
						if outcome.Id == result.outcome then
							outcomeName = outcome.DisplayName
							break
						end
					end
				end
				return {
					ok = result.ok == true,
					reason = result.reason,
					replayed = result.replayed == true,
					charged = false,
					outcome = result.outcome,
					outcomeName = outcomeName,
					removed = result.removed == true,
					previousLevel = result.previousLevel,
					upgradeLevel = result.upgradeLevel,
					power = result.power,
					instanceId = result.instanceId or instanceId,
					balance = session.wallet:GetBalance(session.key),
				}
			end)
		end

		if action == "StartRace" then
			return beginRace(session, "race", request, token)
		end
		return beginRace(session, "boss", request, token)
	end

	return service
end

return PlaySessionService
