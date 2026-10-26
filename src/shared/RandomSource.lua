-- Roblox 內使用引擎的 Random。沒有這個全域時才改用內建產生器，讓測試仍可在 Studio 外執行。
local RandomSource = {}

local Fallback = {}
Fallback.__index = Fallback

function Fallback.new(seed: number?)
	local state = if type(seed) == "number" then math.floor(seed) else os.time()
	state = state % 2147483647
	if state <= 0 then
		state = 1
	end
	return setmetatable({
		state = state,
	}, Fallback)
end

-- Park-Miller。只在缺少 Luau Random 時使用。
function Fallback:NextInteger(minValue: number, maxValue: number): number
	self.state = (self.state * 48271) % 2147483647
	local span = maxValue - minValue + 1
	return minValue + (self.state % span)
end

function RandomSource.new(seed: number?)
	if Random ~= nil and type(Random.new) == "function" then
		if seed == nil then
			return Random.new()
		end
		return Random.new(seed)
	end
	return Fallback.new(seed)
end

return RandomSource
