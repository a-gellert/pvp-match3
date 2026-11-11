-- Deterministic Park-Miller PRNG (HTML5 Lua 5.1 / Desktop LuaJIT parity).
local M = {}
M.__index = M

local MOD = 2147483647

function M.new(seed)
	local s = math.floor(math.abs(seed or 1)) % (MOD - 1)
	if s == 0 then s = 1 end
	return setmetatable({ s = s }, M)
end

function M:next()
	self.s = (self.s * 16807) % MOD
	return self.s
end

function M:float()
	return (self:next() - 1) / (MOD - 1)
end

function M:int(a, b)
	return a + math.floor(self:float() * (b - a + 1))
end

function M:pick(list)
	return list[self:int(1, #list)]
end

function M:shuffle(list)
	for i = #list, 2, -1 do
		local j = self:int(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

return M
