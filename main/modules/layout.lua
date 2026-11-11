-- Virtual canvas shared by the render script and the GUI.
local M = {}

M.PORTRAIT = "portrait"
M.LANDSCAPE = "landscape"

local P_W, P_H = 720, 1280
local L_W, L_H = 1600, 900

function M.virtual_size(w, h)
	if not w or not h or w <= 0 or h <= 0 then return P_W, P_H, M.PORTRAIT end
	if w / h < 0.9 then
		local s = math.min(w / P_W, h / P_H)
		return w / s, h / s, M.PORTRAIT
	end
	local s = math.min(w / L_W, h / L_H)
	return w / s, h / s, M.LANDSCAPE
end

return M
