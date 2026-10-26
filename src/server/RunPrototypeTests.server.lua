-- Studio 啟動時跑概念原型測試。正式伺服器直接返回，而且不使用玩家的車庫。
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local PrototypeTests = require(script.Parent:WaitForChild("PrototypeTests"))
local summary = PrototypeTests.run()

print(string.format("[CarForgeTax 原型測試] 通過 %d，失敗 %d。此結果不寫入玩家資料。", summary.passed, summary.failed))
for _, result in ipairs(summary.results) do
	local line = string.format("[%s] %s %s", if result.ok then "PASS" else "FAIL", result.name, result.detail or "")
	if result.ok then
		print(line)
	else
		warn(line)
	end
end
