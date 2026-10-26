-- Studio 啟動時跑強化測試。正式伺服器直接返回，而且使用測試自己的車庫。
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local CarUpgradeTests = require(script.Parent:WaitForChild("CarUpgradeTests"))
local summary = CarUpgradeTests.run()

print(string.format("[CarForgeTax 強化測試] 通過 %d，失敗 %d。此結果不寫入玩家資料。", summary.passed, summary.failed))
for _, result in ipairs(summary.results) do
	local line = string.format("[%s] %s %s", if result.ok then "PASS" else "FAIL", result.name, result.detail or "")
	if result.ok then
		print(line)
	else
		warn(line)
	end
end
