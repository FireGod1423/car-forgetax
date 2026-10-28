-- 把抽車、強化與競速接到玩家。測試金幣只在 Studio 發放。關服後記憶體資料會消失。
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

if ServerScriptService:GetAttribute("CarForgeTaxSessionStarted") == true then
	return
end
ServerScriptService:SetAttribute("CarForgeTaxSessionStarted", true)

local PlaygroundBuilder = require(script.Parent:WaitForChild("PlaygroundBuilder"))
local PlaygroundPresenter = require(script.Parent:WaitForChild("PlaygroundPresenter"))
local PlaySessionService = require(script.Parent:WaitForChild("PlaySessionService"))

local function ensureRemote(parent: Instance, className: string, name: string)
	local existing = parent:FindFirstChild(name)
	if existing ~= nil and existing.ClassName == className then
		return existing
	end
	if existing ~= nil then
		existing:Destroy()
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local remotes = ReplicatedStorage:FindFirstChild("CarForgeTaxRemotes")
if remotes == nil then
	remotes = Instance.new("Folder")
	remotes.Name = "CarForgeTaxRemotes"
	remotes.Parent = ReplicatedStorage
end
local actionRemote = ensureRemote(remotes, "RemoteFunction", "Action")
local finishedEvent = ensureRemote(remotes, "RemoteEvent", "RaceFinished")

local playersByKey = {}
local boundPlayers = {}
local service = PlaySessionService.new({
	isStudio = RunService:IsStudio(),
	-- 不傳 bossEnabled。客戶端的 StartBoss 會被伺服器拒絕。
	presenter = PlaygroundPresenter.new(),
	notify = function(playerKey, payload)
		local player = playersByKey[playerKey]
		if player ~= nil and player.Parent ~= nil then
			finishedEvent:FireClient(player, payload)
		end
	end,
})

local function keyFor(player: Player): string
	return tostring(player.UserId)
end

local function moveToSpawn(player: Player)
	local key = keyFor(player)
	local bay = PlaygroundBuilder.claimBay(key)
	local spawnPart = if bay ~= nil then bay.spawn else nil
	if spawnPart ~= nil and spawnPart:IsA("SpawnLocation") then
		player.RespawnLocation = spawnPart
	end
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root ~= nil and spawnPart ~= nil then
		root.CFrame = spawnPart.CFrame + Vector3.new(0, 5, 0)
	end
end

local function syncLeader(player: Player, key: string)
	local line = service:leaderLine(key)
	if line == nil then
		return
	end
	local stats = player:FindFirstChild("leaderstats")
	if stats == nil then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
		local rank = Instance.new("StringValue")
		rank.Name = "Rank"
		rank.Parent = stats
		local gold = Instance.new("IntValue")
		gold.Name = "Gold"
		gold.Parent = stats
	end
	local rank = stats:FindFirstChild("Rank")
	local gold = stats:FindFirstChild("Gold")
	if rank ~= nil and rank:IsA("StringValue") then
		rank.Value = line.rank
	end
	if gold ~= nil and gold:IsA("IntValue") then
		local amount = line.gold
		gold.Value = if type(amount) == "number" then math.floor(amount) else 0
	end
end

local function attach(player: Player)
	local key = keyFor(player)
	playersByKey[key] = player
	service:createSession(key)
	local bay = PlaygroundBuilder.claimBay(key)
	if bay ~= nil then
		service:setGarageShift(key, bay.offset)
		if bay.spawn ~= nil then
			player.RespawnLocation = bay.spawn
		end
	end
	if boundPlayers[key] ~= true then
		boundPlayers[key] = true
		player.CharacterAdded:Connect(function()
			moveToSpawn(player)
		end)
	end
	moveToSpawn(player)
	syncLeader(player, key)
	PlaygroundBuilder.paintBay(key, service:garageView(key, os.clock()))
end

local function detach(player: Player)
	local key = keyFor(player)
	playersByKey[key] = nil
	service:removeSession(key)
	PlaygroundBuilder.releaseBay(key)
end

local buildOk, buildErr = pcall(function()
	PlaygroundBuilder.build(workspace)
end)
if not buildOk then
	warn("[CarForgeTax] 場景建立失敗：" .. tostring(buildErr))
end

Players.PlayerAdded:Connect(attach)
Players.PlayerRemoving:Connect(detach)
for _, player in ipairs(Players:GetPlayers()) do
	attach(player)
end

actionRemote.OnServerInvoke = function(player: Player, request)
	if player == nil or player.Parent == nil then
		return {
			ok = false,
			reason = PlaySessionService.Reason.InvalidPlayer,
		}
	end
	local key = keyFor(player)
	playersByKey[key] = player
	if service:createSession(key) == nil then
		return {
			ok = false,
			reason = PlaySessionService.Reason.InvalidPlayer,
		}
	end
	local ok, result = pcall(function()
		return service:dispatch(key, request)
	end)
	if not ok then
		warn("[CarForgeTax] 請求失敗：" .. tostring(result))
		return {
			ok = false,
			reason = "InternalError",
		}
	end
	return result
end

-- 客戶端不能呼叫這個事件來領獎。只由伺服器在模擬結束時送出。
finishedEvent.OnServerEvent:Connect(function(player)
	warn("[CarForgeTax] 忽略客戶端送來的完賽事件：" .. player.Name)
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local ok, err = pcall(function()
		service:advanceAll(now)
	end)
	if not ok then
		warn("[CarForgeTax] 競速推進失敗：" .. tostring(err))
	end
	for key, player in pairs(playersByKey) do
		if player.Parent ~= nil then
			pcall(function()
				syncLeader(player, key)
				PlaygroundBuilder.paintBay(key, service:garageView(key, now))
			end)
		end
	end
	pcall(function()
		PlaygroundBuilder.stepDealer(workspace:FindFirstChild(PlaygroundBuilder.FolderName), now)
	end)
end)

print("[CarForgeTax] 概念原型已啟動。車庫與金幣只存在伺服器記憶體，關服後消失。")
