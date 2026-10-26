-- Studio 啟動時跑車輛測試。正式伺服器直接返回，而且測試使用自己的記憶體資料。
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local CarSystemTests = require(script.Parent:WaitForChild("CarSystemTests"))
local summary = CarSystemTests.run()

print(string.format("[CarForgeTax 測試] 通過 %d，失敗 %d。此結果不寫入玩家資料。", summary.passed, summary.failed))
for _, result in ipairs(summary.results) do
	local line = string.format("[%s] %s %s", if result.ok then "PASS" else "FAIL", result.name, result.detail or "")
	if result.ok then
		print(line)
	else
		warn(line)
	end
end
