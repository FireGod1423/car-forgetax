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

-- AbilityId、ModelAsset 先留空，之後再接特殊能力與 3D 模型。
local definitions = {
	{
		ModelId = "test_common_r0",
		DisplayName = "Common Test Car",
		Quality = "Common",
		UnlockRebirth = 0,
	},
	{
		ModelId = "test_uncommon_r0",
		DisplayName = "Uncommon Test Car",
		Quality = "Uncommon",
		UnlockRebirth = 0,
	},
	{
		ModelId = "test_rare_r0",
		DisplayName = "Rare Test Car",
		Quality = "Rare",
		UnlockRebirth = 0,
	},
	{
		ModelId = "test_epic_r0",
		DisplayName = "Epic Test Car",
		Quality = "Epic",
		UnlockRebirth = 0,
	},
	{
		ModelId = "test_legendary_r0",
		DisplayName = "Legendary Test Car",
		Quality = "Legendary",
		UnlockRebirth = 0,
	},
	{
		ModelId = "test_common_r1",
		DisplayName = "Rebirth 1 Test Car",
		Quality = "Common",
		UnlockRebirth = 1,
	},
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
	})
	table.insert(cars, car)
	carsById[car.ModelId] = car
end

cars = table.freeze(cars)

function CarCatalog.getAll()
	return cars
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
