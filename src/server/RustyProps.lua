-- T0 廢車場道具。網格與貼圖來自已上傳的 Blender 匯入，場景重建時照這份清單複製。
local RustyProps = {}

local ROUGH = "rbxassetid://109813250176199"
local METAL = "rbxassetid://89540688808687"

local COLOR = {
	steel = "rbxassetid://119497658467092",
	paint = "rbxassetid://139737416280749",
	lid = "rbxassetid://96160499953996",
	wood = "rbxassetid://78664783976114",
	nail = "rbxassetid://88636122574361",
	rim = "rbxassetid://87568078127607",
	tireSteel = "rbxassetid://114383446316498",
	rubber = "rbxassetid://119249496868945",
	engineSteel = "rbxassetid://108139404879361",
	enginePaint = "rbxassetid://127937168782822",
	scrapGray = "rbxassetid://81659271875579",
	scrapRed = "rbxassetid://121956559561533",
}

-- name, mesh, size, local position, color key. 旋轉在匯入時都是正放。
local function mesh(name: string, id: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, colorKey: string)
	return { name, id, sx, sy, sz, x, y, z, colorKey }
end

local OIL_DRUM = {
	mesh("DrumBandA", "rbxassetid://75088512764150", 0.995, 0.055, 1.010, 0, 0.420, 0, "steel"),
	mesh("DrumBandB", "rbxassetid://125697950364272", 0.995, 0.055, 1.010, 0, 0.900, 0, "steel"),
	mesh("DrumBody", "rbxassetid://117342914853673", 0.945, 1.180, 0.960, 0, 0.650, 0, "paint"),
	mesh("DrumBung", "rbxassetid://107384879347144", 0.110, 0.045, 0.110, -0.160, 1.355, 0, "steel"),
	mesh("DrumLid", "rbxassetid://114841277173801", 0.896, 0.050, 0.910, 0, 1.315, 0, "lid"),
	mesh("DrumRimBot", "rbxassetid://110557157123273", 1.044, 0.070, 1.060, 0, 0.045, 0, "steel"),
	mesh("DrumRimTop", "rbxassetid://74169694549910", 1.044, 0.070, 1.060, 0, 1.255, 0, "steel"),
}

local PARTS_CRATE = {
	mesh("CornerPost", "rbxassetid://103297282501392", 0.080, 0.780, 0.080, 0.620, 0.390, -0.480, "wood"),
	mesh("CornerPost", "rbxassetid://103297282501392", 0.080, 0.780, 0.080, -0.620, 0.390, -0.480, "wood"),
	mesh("CornerPost", "rbxassetid://103297282501392", 0.080, 0.780, 0.080, 0.620, 0.390, 0.480, "wood"),
	mesh("CornerPost", "rbxassetid://103297282501392", 0.080, 0.780, 0.080, -0.620, 0.390, 0.480, "wood"),
	mesh("EndPlank", "rbxassetid://139851017283426", 0.055, 0.120, 0.880, 0.640, 0.200, 0, "wood"),
	mesh("EndPlank", "rbxassetid://139851017283426", 0.055, 0.120, 0.880, -0.640, 0.200, 0, "wood"),
	mesh("EndPlank", "rbxassetid://107071670918402", 0.055, 0.120, 0.880, 0.640, 0.400, 0, "wood"),
	mesh("EndPlank", "rbxassetid://107071670918402", 0.055, 0.120, 0.880, -0.640, 0.400, 0, "wood"),
	mesh("EndPlank", "rbxassetid://107071670918402", 0.055, 0.120, 0.880, 0.640, 0.600, 0, "wood"),
	mesh("EndPlank", "rbxassetid://107071670918402", 0.055, 0.120, 0.880, -0.640, 0.600, 0, "wood"),
	mesh("FloorPlank", "rbxassetid://95094860507394", 0.240, 0.060, 0.960, 0.420, 0.030, 0, "wood"),
	mesh("FloorPlank", "rbxassetid://126889708002637", 0.240, 0.060, 0.960, 0.140, 0.030, 0, "wood"),
	mesh("FloorPlank", "rbxassetid://75423487436649", 0.240, 0.060, 0.960, -0.140, 0.030, 0, "wood"),
	mesh("FloorPlank", "rbxassetid://108644695248851", 0.240, 0.060, 0.960, -0.420, 0.030, 0, "wood"),
	mesh("Nail", "rbxassetid://90173946224612", 0.031, 0.020, 0.036, 0.580, 0.760, -0.460, "nail"),
	mesh("Nail", "rbxassetid://90173946224612", 0.031, 0.020, 0.036, -0.580, 0.760, -0.460, "nail"),
	mesh("Nail", "rbxassetid://90173946224612", 0.031, 0.020, 0.036, 0.580, 0.760, 0.460, "nail"),
	mesh("Nail", "rbxassetid://90173946224612", 0.031, 0.020, 0.036, -0.580, 0.760, 0.460, "nail"),
	mesh("SidePlank", "rbxassetid://122946386043451", 1.160, 0.120, 0.055, 0, 0.200, -0.500, "wood"),
	mesh("SidePlank", "rbxassetid://86342114553256", 1.160, 0.120, 0.055, 0, 0.200, 0.500, "wood"),
	mesh("SidePlank", "rbxassetid://78780673848301", 1.160, 0.120, 0.055, 0, 0.400, -0.500, "wood"),
	mesh("SidePlank", "rbxassetid://100232468814320", 1.160, 0.120, 0.055, 0, 0.400, 0.500, "wood"),
	mesh("SidePlank", "rbxassetid://78780673848301", 1.160, 0.120, 0.055, 0, 0.600, -0.500, "wood"),
	mesh("SidePlank", "rbxassetid://100232468814320", 1.160, 0.120, 0.055, 0, 0.600, 0.500, "wood"),
	mesh("TopRail", "rbxassetid://88095764688449", 1.280, 0.060, 0.070, 0, 0.740, -0.500, "wood"),
	mesh("TopRail", "rbxassetid://129929930598663", 1.280, 0.060, 0.070, 0, 0.740, 0.500, "wood"),
	mesh("TopRail", "rbxassetid://92767528316942", 0.070, 0.060, 0.960, 0.640, 0.740, 0, "wood"),
	mesh("TopRail", "rbxassetid://92767528316942", 0.070, 0.060, 0.960, -0.640, 0.740, 0, "wood"),
}

local WORN_RIM = {
	mesh("Hub", "rbxassetid://111864427519814", 0.280, 0.280, 0.090, 0, 0.540, 0.020, "rim"),
	mesh("OuterLip", "rbxassetid://107193204826355", 1.080, 1.080, 0.035, 0, 0.540, 0.045, "rim"),
	mesh("RimDisc", "rbxassetid://112013432706745", 1.040, 1.040, 0.080, 0, 0.540, 0, "rim"),
	mesh("Spoke", "rbxassetid://92925142744522", 0.263, 0.108, 0.070, -0.242, 0.602, 0.020, "rim"),
	mesh("Spoke", "rbxassetid://123830570903898", 0.062, 0.262, 0.070, -0.016, 0.789, 0.020, "rim"),
	mesh("Spoke", "rbxassetid://122483147918173", 0.258, 0.138, 0.070, 0.232, 0.632, 0.020, "rim"),
	mesh("Spoke", "rbxassetid://76560849999122", 0.201, 0.229, 0.070, 0.160, 0.348, 0.020, "rim"),
	mesh("Spoke", "rbxassetid://78696738635667", 0.177, 0.244, 0.070, -0.134, 0.329, 0.020, "rim"),
}

local OLD_TIRE = {
	mesh("Hub", "rbxassetid://76871586400804", 0.280, 0.280, 0.120, 0, 0.735, 0, "tireSteel"),
	mesh("RimBarrel", "rbxassetid://88280755155439", 0.920, 0.920, 0.200, 0, 0.735, 0, "tireSteel"),
	mesh("RimFlange", "rbxassetid://97998542308802", 1.000, 1.000, 0.028, 0, 0.735, -0.090, "tireSteel"),
	mesh("RimFlange", "rbxassetid://113788842890662", 1.000, 1.000, 0.028, 0, 0.735, 0.090, "tireSteel"),
	mesh("Sidewall", "rbxassetid://104566246941878", 1.470, 1.470, 0.045, 0, 0.735, -0.190, "rubber"),
	mesh("Sidewall", "rbxassetid://109696629729427", 1.470, 1.470, 0.045, 0, 0.735, 0.190, "rubber"),
	mesh("Spoke", "rbxassetid://133153076561857", 0.320, 0.036, 0.055, -0.280, 0.735, 0, "tireSteel"),
	mesh("Spoke", "rbxassetid://79123795043424", 0.133, 0.315, 0.055, -0.087, 1.001, 0, "tireSteel"),
	mesh("Spoke", "rbxassetid://119454509790800", 0.280, 0.217, 0.055, 0.227, 0.900, 0, "tireSteel"),
	mesh("Spoke", "rbxassetid://117458648425040", 0.280, 0.217, 0.055, 0.227, 0.570, 0, "tireSteel"),
	mesh("Spoke", "rbxassetid://71969404756149", 0.133, 0.315, 0.055, -0.087, 0.469, 0, "tireSteel"),
	mesh("TreadCore", "rbxassetid://92023636647416", 1.360, 1.360, 0.360, 0, 0.735, 0, "rubber"),
	mesh("TreadRib", "rbxassetid://127496945001694", 1.450, 1.450, 0.050, 0, 0.735, -0.110, "rubber"),
	mesh("TreadRib", "rbxassetid://111368338239986", 1.450, 1.450, 0.050, 0, 0.735, 0, "rubber"),
	mesh("TreadRib", "rbxassetid://119525680339371", 1.450, 1.450, 0.050, 0, 0.735, 0.110, "rubber"),
	mesh("Valve", "rbxassetid://131925475087365", 0.032, 0.050, 0.032, 0, 1.485, 0, "rubber"),
}

local SCRAP_ENGINE = {
	mesh("Bolt", "rbxassetid://99878251765852", 0.035, 0.025, 0.040, -0.100, 0.330, 0.100, "engineSteel"),
	mesh("Bolt", "rbxassetid://89019091993833", 0.035, 0.025, 0.040, 0.140, 0.330, -0.080, "engineSteel"),
	mesh("Bolt", "rbxassetid://102182838288124", 0.035, 0.025, 0.040, -0.220, 0.030, -0.180, "engineSteel"),
	mesh("Cap", "rbxassetid://120508111555170", 0.056, 0.045, 0.056, 0.120, 0.345, 0, "engineSteel"),
	mesh("Cap", "rbxassetid://97014370832363", 0.056, 0.045, 0.056, 0.040, 0.345, 0, "engineSteel"),
	mesh("Cap", "rbxassetid://130613487328590", 0.056, 0.045, 0.056, -0.040, 0.345, 0, "engineSteel"),
	mesh("Cap", "rbxassetid://102173544750939", 0.056, 0.045, 0.056, -0.120, 0.345, 0, "engineSteel"),
	mesh("EngineBlock", "rbxassetid://96073217540449", 0.460, 0.240, 0.300, 0, 0.120, 0, "enginePaint"),
	mesh("EngineHead", "rbxassetid://114510863890797", 0.400, 0.080, 0.240, 0, 0.280, 0, "enginePaint"),
	mesh("Exhaust", "rbxassetid://121129139109158", 0.229, 0.076, 0.112, -0.280, 0.160, 0.080, "engineSteel"),
	mesh("GearDisc", "rbxassetid://81965478123227", 0.220, 0.045, 0.220, -0.340, 0.110, -0.160, "engineSteel"),
	mesh("GearTooth", "rbxassetid://83262408396118", 0.045, 0.040, 0.050, -0.465, 0.110, -0.160, "engineSteel"),
	mesh("GearTooth", "rbxassetid://86658168188879", 0.067, 0.040, 0.067, -0.428, 0.110, -0.072, "engineSteel"),
	mesh("GearTooth", "rbxassetid://81171293047490", 0.050, 0.040, 0.045, -0.340, 0.110, -0.035, "engineSteel"),
	mesh("GearTooth", "rbxassetid://122303987270365", 0.067, 0.040, 0.067, -0.252, 0.110, -0.072, "engineSteel"),
	mesh("GearTooth", "rbxassetid://125959802090904", 0.045, 0.040, 0.050, -0.215, 0.110, -0.160, "engineSteel"),
	mesh("GearTooth", "rbxassetid://110657444716662", 0.067, 0.040, 0.067, -0.252, 0.110, -0.248, "engineSteel"),
	mesh("GearTooth", "rbxassetid://106190286209113", 0.050, 0.040, 0.045, -0.340, 0.110, -0.285, "engineSteel"),
	mesh("GearTooth", "rbxassetid://84329073183932", 0.067, 0.040, 0.067, -0.428, 0.110, -0.248, "engineSteel"),
	mesh("Pulley", "rbxassetid://129964784749516", 0.040, 0.136, 0.140, 0.280, 0.160, 0, "engineSteel"),
}

local SCRAP_PILE = {
	mesh("BasePlate", "rbxassetid://79980306827636", 1.017, 0.045, 0.729, 0, 0.025, 0, "scrapGray"),
	mesh("Bolt", "rbxassetid://103703622083201", 0.038, 0.020, 0.044, -0.160, 0.100, 0.040, "scrapGray"),
	mesh("BracketFoot", "rbxassetid://97908161559829", 0.226, 0.050, 0.093, 0.380, 0.070, 0.220, "scrapGray"),
	mesh("BracketPost", "rbxassetid://116004471547748", 0.059, 0.220, 0.059, 0.460, 0.160, 0.220, "scrapGray"),
	mesh("Fender", "rbxassetid://111561472591491", 0.377, 0.320, 0.329, -0.180, 0.210, -0.280, "scrapRed"),
	mesh("LeanPlate", "rbxassetid://76891739510671", 0.575, 0.268, 0.403, 0.050, 0.184, -0.020, "scrapRed"),
	mesh("MidPlate", "rbxassetid://79708819053477", 0.795, 0.040, 0.616, -0.060, 0.070, 0.020, "enginePaint"),
	mesh("Pipe", "rbxassetid://133755667914326", 0.710, 0.120, 0.223, -0.620, 0.060, 0.180, "scrapGray"),
}

local function meshKey(meshId: string): string
	return string.match(meshId, "%d+") or meshId
end

local function findKit(): Folder?
	local storage = game:GetService("ServerStorage")
	local stored = storage:FindFirstChild("RustyMeshKit")
	if stored ~= nil and stored:IsA("Folder") then
		return stored
	end
	local loose = workspace:FindFirstChild("RustyMeshKit")
	if loose ~= nil and loose:IsA("Folder") then
		return loose
	end
	return nil
end

local function spawn(parent: Instance, name: string, placement: CFrame, parts, collide: boolean)
	local kit = findKit()
	if kit == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("RustyProp", true)
	for _, item in ipairs(parts) do
		local source = kit:FindFirstChild(meshKey(item[2]))
		if source ~= nil and source:IsA("MeshPart") then
			local piece = source:Clone()
			piece.Name = item[1]
			piece.Size = Vector3.new(item[3], item[4], item[5])
			piece.CFrame = placement * CFrame.new(item[6], item[7], item[8])
			piece.Anchored = true
			piece.CanCollide = collide
			piece.CanTouch = false
			piece.CanQuery = true
			piece.Material = Enum.Material.SmoothPlastic
			piece.Color = Color3.fromRGB(163, 162, 165)
			piece.CollisionFidelity = Enum.CollisionFidelity.Box
			local surface = piece:FindFirstChildOfClass("SurfaceAppearance")
			if surface == nil then
				surface = Instance.new("SurfaceAppearance")
				surface.Parent = piece
			end
			surface.ColorMap = COLOR[item[9]]
			surface.RoughnessMap = ROUGH
			surface.MetalnessMap = METAL
			piece.Parent = model
		end
	end
	if #model:GetChildren() == 0 then
		model:Destroy()
		return nil
	end
	model.Parent = parent
	return model
end

function RustyProps.place(dealer: Instance, origin: CFrame)
	-- 座標是攤位本地座標。玩家從 +Z 走近，道具留在兩側和櫃後。
	local yard = 0.34
	spawn(dealer, "OilDrum", origin * CFrame.new(5.35, yard, -2.7), OIL_DRUM, true)
	spawn(dealer, "OldTire", origin * CFrame.new(-5.7, yard, -2.55), OLD_TIRE, true)
	spawn(dealer, "OldTire", origin * CFrame.new(-5.05, yard, -1.9) * CFrame.Angles(0, 0.45, 0.12), OLD_TIRE, false)
	spawn(dealer, "OldTire", origin * CFrame.new(-5.4, yard + 0.2, -3.35) * CFrame.Angles(math.rad(68), 0.35, 0), OLD_TIRE, false)
	spawn(dealer, "WornRim", origin * CFrame.new(-4.35, yard, -2.2) * CFrame.Angles(math.rad(72), 0.7, 0), WORN_RIM, false)
	spawn(dealer, "PartsCrate", origin * CFrame.new(-5.15, yard, -5.35), PARTS_CRATE, true)
	spawn(dealer, "ScrapEngineParts", origin * CFrame.new(-5.1, yard + 0.08, -5.35), SCRAP_ENGINE, false)
	spawn(dealer, "ScrapPile", origin * CFrame.new(5.55, yard, -5.5) * CFrame.Angles(0, -0.4, 0), SCRAP_PILE, true)
end

function RustyProps.retireImports(parent: Instance)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == "Scene" and child:IsA("Model") then
			local imported = child:FindFirstChild("OilDrum")
				or child:FindFirstChild("PartsCrate")
				or child:FindFirstChild("WornRim")
				or child:FindFirstChild("OldTire")
				or child:FindFirstChild("ScrapEngineParts")
				or child:FindFirstChild("ScrapPile")
			if imported ~= nil then
				child:Destroy()
			end
		end
	end
end

return RustyProps
