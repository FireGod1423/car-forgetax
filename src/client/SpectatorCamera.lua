-- 觀察鏡頭只改這個客戶端的相機。不改伺服器競速，也不鎖角色移動。
local RunService = game:GetService("RunService")

local SpectatorCamera = {}

function SpectatorCamera.mount(player: Player, playerGui: PlayerGui)
	local existing = playerGui:FindFirstChild("CarForgeTaxSpectator")
	if existing ~= nil then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CarForgeTaxSpectator"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "SpectatorPanel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -16, 0, 48)
	panel.Size = UDim2.fromOffset(168, 54)
	panel.BackgroundColor3 = Color3.fromRGB(16, 18, 22)
	panel.BackgroundTransparency = 0.28
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 8)
	panelCorner.Parent = panel

	local caption = Instance.new("TextLabel")
	caption.Name = "Mode"
	caption.BackgroundTransparency = 1
	caption.Position = UDim2.fromOffset(8, 4)
	caption.Size = UDim2.new(1, -16, 0, 14)
	caption.Font = Enum.Font.Gotham
	caption.TextSize = 11
	caption.TextXAlignment = Enum.TextXAlignment.Center
	caption.TextColor3 = Color3.fromRGB(186, 192, 200)
	caption.Text = "FIRST PERSON"
	caption.Parent = panel

	local button = Instance.new("TextButton")
	button.Name = "SpectateButton"
	button.Position = UDim2.fromOffset(8, 20)
	button.Size = UDim2.new(1, -16, 0, 28)
	button.BackgroundColor3 = Color3.fromRGB(232, 236, 240)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 12
	button.TextColor3 = Color3.fromRGB(20, 22, 26)
	button.Text = "SPECTATE"
	button.AutoButtonColor = true
	button.Parent = panel
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 6)
	buttonCorner.Parent = button

	local active = false
	local snap = false
	local savedType = Enum.CameraType.Custom
	local savedSubject = nil
	local smoothed = nil

	local function findRaceCar(): Model?
		local playground = workspace:FindFirstChild("CarForgeTaxPlayground")
		if playground == nil then
			return nil
		end
		local races = playground:FindFirstChild("ActiveRaces")
		if races == nil then
			return nil
		end
		local key = tostring(player.UserId)
		for _, child in ipairs(races:GetChildren()) do
			if child:IsA("Model") and child.Name == "ActiveRaceCar" and child:GetAttribute("OwnerKey") == key then
				return child
			end
		end
		return nil
	end

	local function currentHumanoid(): Humanoid?
		local character = player.Character
		if character == nil then
			return nil
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil and humanoid:IsA("Humanoid") then
			return humanoid
		end
		return nil
	end

	local function restore()
		local camera = workspace.CurrentCamera
		if camera ~= nil then
			camera.CameraType = savedType or Enum.CameraType.Custom
			local subject = savedSubject
			if subject == nil or subject.Parent == nil then
				subject = currentHumanoid()
			end
			if subject ~= nil then
				camera.CameraSubject = subject
			end
		end
		smoothed = nil
	end

	local function exit()
		if active ~= true then
			button.Text = "SPECTATE"
			return
		end
		active = false
		button.Text = "SPECTATE"
		caption.Text = "FIRST PERSON"
		restore()
	end

	local function enter()
		if findRaceCar() == nil then
			caption.Text = "NO RACE"
			panel.Visible = false
			return
		end
		caption.Text = "FIRST PERSON"
		local camera = workspace.CurrentCamera
		if camera ~= nil then
			savedType = camera.CameraType
			savedSubject = camera.CameraSubject
			camera.CameraType = Enum.CameraType.Scriptable
		end
		active = true
		snap = true
		button.Text = "EXIT SPECTATOR"
	end

	button.MouseButton1Click:Connect(function()
		if active then
			exit()
		else
			enter()
		end
	end)

	local function watchCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 8)
		if humanoid ~= nil and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(exit)
		end
	end
	if player.Character ~= nil then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		exit()
		task.spawn(watchCharacter, character)
	end)

	local stepped = RunService.RenderStepped:Connect(function(dt)
		local racingNow = findRaceCar() ~= nil and player:GetAttribute("BenchCamera") ~= true
		panel.Visible = racingNow
		if racingNow ~= true then
			if active then
				exit()
			end
			return
		end
		if active ~= true then
			return
		end
		local camera = workspace.CurrentCamera
		local car = findRaceCar()
		if camera == nil or car == nil or car.Parent == nil then
			exit()
			return
		end
		local humanoid = currentHumanoid()
		if humanoid == nil or humanoid.Health <= 0 then
			exit()
			return
		end
		local pivot = car:GetPivot()
		local eye = pivot.Position + pivot.LookVector * 5.6 + Vector3.new(0, 1.15, 0)
		local focus = pivot.Position + pivot.LookVector * 16 + Vector3.new(0, 0.45, 0)
		local goal = CFrame.lookAt(eye, focus, Vector3.yAxis)
		if snap or smoothed == nil then
			smoothed = goal
			snap = false
		else
			local blend = 1 - math.exp(-8 * dt)
			smoothed = smoothed:Lerp(goal, blend)
		end
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = smoothed
	end)

	gui.Destroying:Connect(function()
		stepped:Disconnect()
		exit()
	end)
end

return SpectatorCamera
