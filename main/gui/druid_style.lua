-- Druid style for Gem Vanguard: juicy press/hover feedback, smooth scrolls, virtual-canvas drag.
local settings = require "druid.system.settings"

local M = {}
local V3 = vmath.vector3

local PRESS_SCALE = 0.93
local HOVER_SCALE = 1.045

local function scaled(base, k)
	return V3(base.x * k, base.y * k, base.z)
end

M["button"] = {
	LONGTAP_TIME = 0.4,
	AUTOHOLD_TRIGGER = 0.8,
	DOUBLETAP_TIME = 0.4,
	BTN_SOUND = "button",
	BTN_SOUND_DISABLED = "blocked",

	on_init = function(self) end,

	-- Finger / mouse is down on the button: squash it
	on_hover = function(self, node, state)
		local target = state and scaled(self.start_scale, PRESS_SCALE) or self.start_scale
		gui.animate(node, gui.PROP_SCALE, target, state and gui.EASING_OUTQUAD or gui.EASING_OUTBACK, state and 0.06 or 0.18)
	end,

	-- Desktop hover: grow a little and brighten
	on_mouse_hover = function(self, node, state)
		if self.hover:is_hovered() then return end
		local target = state and scaled(self.start_scale, HOVER_SCALE) or self.start_scale
		gui.animate(node, gui.PROP_SCALE, target, gui.EASING_OUTSINE, 0.1)
		if not self.disabled then
			local c = state and vmath.vector4(1.12, 1.12, 1.12, 1) or vmath.vector4(1, 1, 1, 1)
			if self.base_color then c = vmath.vector4(self.base_color.x * c.x, self.base_color.y * c.y, self.base_color.z * c.z, self.base_color.w) end
			gui.animate(node, "color", c, gui.EASING_OUTSINE, 0.1)
		end
	end,

	-- Release: punch then settle
	on_click = function(self, node)
		gui.set_scale(node, scaled(self.start_scale, 1.08))
		gui.animate(node, gui.PROP_SCALE, self.start_scale, gui.EASING_OUTBACK, 0.22)
		if not self.silent then settings.play_sound(M.button.BTN_SOUND) end
	end,

	on_click_disabled = function(self, node)
		settings.play_sound(M.button.BTN_SOUND_DISABLED)
		local p = self.start_pos
		gui.animate(node, "position.x", p.x - 6, gui.EASING_OUTSINE, 0.04, 0, function()
			gui.animate(node, "position.x", p.x + 6, gui.EASING_OUTSINE, 0.08, 0, function()
				gui.animate(node, "position.x", p.x, gui.EASING_OUTSINE, 0.04)
			end)
		end)
	end,

	on_set_enabled = function(self, node, state)
		local k = state and 1 or 0.55
		local c = self.base_color or vmath.vector4(1)
		gui.set_color(node, vmath.vector4(c.x * k, c.y * k, c.z * k, c.w))
	end,
}

M["hover"] = {
	ON_HOVER_CURSOR = nil,
	ON_MOUSE_HOVER_CURSOR = nil,
}

M["drag"] = {
	DRAG_DEADZONE = 6,
	-- Input coordinates are already converted to the virtual canvas in game.gui_script
	NO_USE_SCREEN_KOEF = true,
}

M["scroll"] = {
	ANIM_SPEED = 0.25,
	BACK_SPEED = 0.18,
	FRICT = 0.93,
	FRICT_HOLD = 0.79,
	INERT_THRESHOLD = 2.5,
	INERT_SPEED = 30,
	EXTRA_STRETCH_SIZE = 90,
	POINTS_DEADZONE = 20,
	WHEEL_SCROLL_SPEED = 40,
	WHEEL_SCROLL_INVERTED = false,
	WHEEL_SCROLL_BY_INERTION = false,
	SMALL_CONTENT_SCROLL = false,
}

M["progress"] = {
	SPEED = 6,
	MIN_DELTA = 0.004,
}

M["text"] = {
	TRIM_POSTFIX = "...",
	DEFAULT_ADJUST = "downscale",
}

M["swipe"] = {
	SWIPE_THRESHOLD = 40,
	SWIPE_TIME = 0.4,
	SWIPE_TRIGGER_ON_MOVE = true,
}

return M
