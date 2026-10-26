-- 開服時建立概念場景。重複執行只會沿用已存在的資料夾。
local ServerScriptService = game:GetService("ServerScriptService")

if ServerScriptService:GetAttribute("CarForgeTaxPlaygroundBuilt") == true then
	return
end
ServerScriptService:SetAttribute("CarForgeTaxPlaygroundBuilt", true)

local PlaygroundBuilder = require(script.Parent:WaitForChild("PlaygroundBuilder"))
local ok, err = pcall(function()
	PlaygroundBuilder.build(workspace)
end)
if not ok then
	ServerScriptService:SetAttribute("CarForgeTaxPlaygroundBuilt", false)
	warn("[CarForgeTax] 場景建立失敗：" .. tostring(err))
end
