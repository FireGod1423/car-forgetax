-- 車款目錄。同一品質的車型在第一版沒有額外性能差，性能只看 CarConfig。
local function importCarConfig()
	if game ~= nil then
		local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require(sharedFolder:WaitForChild("CarConfig"))
	end
	return require("./CarConfig")
end

local CarConfig = importCarConfig()

local CarCatalog = {}

-- Paint 是車身烤漆，和品質介面色無關。Official 車款的外型來自 Blender。
-- 測試車留在前面，腳本抽車的第 1、第 2 台順序才不會被新車插掉。
local definitions = {
	{ ModelId = "test_common_r0", DisplayName = "Common Test Car", Quality = "Common", UnlockRebirth = 0, PaintName = "Slate", Paint = { 90, 94, 98 } },
	{ ModelId = "test_uncommon_r0", DisplayName = "Uncommon Test Car", Quality = "Uncommon", UnlockRebirth = 0, PaintName = "Sand", Paint = { 196, 168, 120 } },
	{ ModelId = "test_rare_r0", DisplayName = "Rare Test Car", Quality = "Rare", UnlockRebirth = 0, PaintName = "Steel Blue", Paint = { 48, 70, 88 } },
	{ ModelId = "test_epic_r0", DisplayName = "Epic Test Car", Quality = "Epic", UnlockRebirth = 0, PaintName = "Brown", Paint = { 120, 72, 64 } },
	{ ModelId = "test_legendary_r0", DisplayName = "Legendary Test Car", Quality = "Legendary", UnlockRebirth = 0, PaintName = "Charcoal", Paint = { 64, 66, 70 } },
	{ ModelId = "test_common_r1", DisplayName = "Rebirth 1 Test Car", Quality = "Common", UnlockRebirth = 1, PaintName = "Gray Green", Paint = { 140, 144, 138 } },
	{ ModelId = "hatch_common", DisplayName = "Block Hatch", Quality = "Common", UnlockRebirth = 0, PaintName = "Low-sat Red", Paint = { 176, 72, 78 }, MeshKey = "hatch_common", Official = true },
	{ ModelId = "coupe_uncommon", DisplayName = "Ivory Coupe", Quality = "Uncommon", UnlockRebirth = 0, PaintName = "Deep Green", Paint = { 46, 96, 62 }, MeshKey = "coupe_uncommon", Official = true },
	{ ModelId = "sedan_rare", DisplayName = "Wine Sedan", Quality = "Rare", UnlockRebirth = 0, PaintName = "Silver Gray", Paint = { 176, 180, 184 }, MeshKey = "sedan_rare", Official = true },
	{ ModelId = "muscle_epic", DisplayName = "Redline Muscle", Quality = "Epic", UnlockRebirth = 0, PaintName = "Deep Blue", Paint = { 36, 64, 128 }, MeshKey = "muscle_epic", Official = true },
	{ ModelId = "rally_legendary", DisplayName = "Forest Rally", Quality = "Legendary", UnlockRebirth = 1, PaintName = "Forest Green", Paint = { 46, 92, 58 }, MeshKey = "rally_legendary", Official = true },
	{ ModelId = "sports_mythic", DisplayName = "Navy Wedge", Quality = "Mythic", UnlockRebirth = 2, PaintName = "Navy", Paint = { 28, 48, 92 }, MeshKey = "sports_mythic", Official = true },
	{ ModelId = "gt_divine", DisplayName = "Cream GT", Quality = "Divine", UnlockRebirth = 3, PaintName = "Cream", Paint = { 196, 164, 72 }, MeshKey = "gt_divine", Official = true },
	{ ModelId = "super_celestial", DisplayName = "Silver Aero", Quality = "Celestial", UnlockRebirth = 4, PaintName = "Silver", Paint = { 168, 172, 176 }, MeshKey = "super_celestial", Official = true },
	{ ModelId = "hyper_transcendent", DisplayName = "Teal Hypercar", Quality = "Transcendent", UnlockRebirth = 5, PaintName = "Dark Teal", Paint = { 22, 72, 74 }, MeshKey = "hyper_transcendent", Official = true },
	{ ModelId = "proto_eternal", DisplayName = "Amber Prototype", Quality = "Eternal", UnlockRebirth = 6, PaintName = "Low-sat Orange", Paint = { 176, 92, 42 }, MeshKey = "proto_eternal", Official = true },
	{ ModelId = "night_immortal", DisplayName = "Night Coupe", Quality = "Immortal", UnlockRebirth = 7, PaintName = "Black", Paint = { 28, 28, 30 }, MeshKey = "night_immortal", Official = true },
	{ ModelId = "brake_astral", DisplayName = "Burgundy Brake", Quality = "Astral", UnlockRebirth = 8, PaintName = "Burgundy", Paint = { 92, 28, 36 }, MeshKey = "brake_astral", Official = true },
	{ ModelId = "hyper_cosmic", DisplayName = "Gunmetal Cab", Quality = "Cosmic", UnlockRebirth = 9, PaintName = "Gunmetal", Paint = { 58, 64, 72 }, MeshKey = "hyper_cosmic", Official = true },
	{ ModelId = "proto_primordial", DisplayName = "Olive Prototype", Quality = "Primordial", UnlockRebirth = 10, PaintName = "Olive", Paint = { 92, 96, 58 }, MeshKey = "proto_primordial", Official = true },
	{ ModelId = "apex_singularity", DisplayName = "Pearl Apex", Quality = "Singularity", UnlockRebirth = 10, PaintName = "Pearl", Paint = { 232, 232, 228 }, MeshKey = "apex_singularity", Official = true },
}

local cars = {}
local carsById = {}

local function validateDefinition(car)
	if type(car.ModelId) ~= "string" or car.ModelId == "" then
		error("車款缺少 ModelId")
	end
	if carsById[car.ModelId] ~= nil then
		error("重複的車款：" .. car.ModelId)
	end
	if type(car.DisplayName) ~= "string" or car.DisplayName == "" then
		error("車款缺少顯示名稱：" .. car.ModelId)
	end
	if not CarConfig.isValidQuality(car.Quality) then
		error("車款品質無效：" .. car.ModelId)
	end
	if not CarConfig.isInteger(car.UnlockRebirth) or car.UnlockRebirth < 0 then
		error("車款解鎖重生無效：" .. car.ModelId)
	end
	if car.AbilityId ~= nil and type(car.AbilityId) ~= "string" then
		error("AbilityId 必須是字串或空值：" .. car.ModelId)
	end
	if car.ModelAsset ~= nil and type(car.ModelAsset) ~= "string" then
		error("ModelAsset 必須是字串或空值：" .. car.ModelId)
	end
	if type(car.Paint) ~= "table" or #car.Paint ~= 3 then
		error("車身烤漆無效：" .. car.ModelId)
	end
	local quality = CarConfig.getQuality(car.Quality)
	if quality ~= nil then
		local ui = quality.UiColor
		if car.Paint[1] == ui[1] and car.Paint[2] == ui[2] and car.Paint[3] == ui[3] then
			error("車身烤漆不能直接使用品質色碼：" .. car.ModelId)
		end
	end
end

for _, definition in ipairs(definitions) do
	validateDefinition(definition)
	local car = table.freeze({
		ModelId = definition.ModelId,
		DisplayName = definition.DisplayName,
		Quality = definition.Quality,
		UnlockRebirth = definition.UnlockRebirth,
		AbilityId = definition.AbilityId,
		ModelAsset = definition.ModelAsset,
		PaintName = definition.PaintName,
		Paint = table.freeze(definition.Paint),
		MeshKey = definition.MeshKey,
		Official = definition.Official == true,
	})
	table.insert(cars, car)
	carsById[car.ModelId] = car
end

cars = table.freeze(cars)

function CarCatalog.getAll()
	return cars
end

function CarCatalog.getOfficial()
	local official = {}
	for _, car in ipairs(cars) do
		if car.Official == true then
			table.insert(official, car)
		end
	end
	return table.freeze(official)
end

function CarCatalog.getByModelId(modelId: string)
	if type(modelId) ~= "string" then
		return nil
	end
	return carsById[modelId]
end

-- 只回傳這個品質、而且重生階級已經解鎖的車。沒有符合的就回空表。
function CarCatalog.getEligible(qualityId: string, rebirthLevel: number)
	if not CarConfig.isValidQuality(qualityId) or not CarConfig.isInteger(rebirthLevel) or rebirthLevel < 0 then
		return table.freeze({})
	end

	local eligible = {}
	for _, car in ipairs(cars) do
		if car.Quality == qualityId and rebirthLevel >= car.UnlockRebirth then
			table.insert(eligible, car)
		end
	end
	return table.freeze(eligible)
end

return CarCatalog
