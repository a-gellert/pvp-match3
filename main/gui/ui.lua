-- GUI helpers: Casual Dark Fantasy palette, node factories, buttons, bars, tweens and FX.
local audio = require "main.modules.audio"
local sizes = require "main.gui.sprite_sizes"

local M = {}
local V3 = vmath.vector3

M.TEX = "game"
M.FONT = "main"
M.FONT_SIZE = 44

function M.hex(s, a)
	local v = tonumber(string.sub(s, 2), 16)
	return vmath.vector4(math.floor(v / 65536) / 255, math.floor(v / 256) % 256 / 255, v % 256 / 255, a or 1)
end

-- Casual Dark Fantasy palette
M.WHITE    = vmath.vector4(1, 1, 1, 1)
M.INK      = M.hex("#0c0f18")      -- deep outline
M.BG_DARK  = M.hex("#111521")      -- midnight slate
M.BG_PANEL = M.hex("#1c2233")      -- dark stone
M.BG_CARD  = M.hex("#262e45")
M.BONE     = M.hex("#f3eee6")      -- warm readable text
M.DIM      = M.hex("#9aa6bf")      -- muted slate text
M.GOLD     = M.hex("#f2bd47")      -- coins / CTAs / highlights
M.DIAMOND  = M.hex("#59d8ff")      -- premium gems
M.PRESTIGE = M.hex("#d26eff")      -- prestige / epic accent
M.RED      = M.hex("#ff4a64")      -- Damage tier 1 / HP damage
M.YELLOW   = M.hex("#ffd644")      -- Damage tier 2
M.PURPLE   = M.hex("#b95cff")      -- Damage tier 3 / rewarded ads
M.GREEN    = M.hex("#48e58b")      -- Heal / ready upgrade
M.BLUE     = M.hex("#4fb8ff")      -- Shield / armor
M.CRIMSON  = M.hex("#c93048")

M.GEM_COLOR = {
	red = M.RED,
	yellow = M.YELLOW,
	purple = M.PURPLE,
	green = M.GREEN,
	blue = M.BLUE,
	prism = M.WHITE,
}

M.RARITY_FRAME = {
	common = "card_common",
	rare = "card_rare",
	epic = "card_epic",
}

M.gen = 0
M.popup_gen = 0
M.buttons = {}
M.layer = "screen"

-- ---------------------------------------------------------------- nodes

function M.pane(parent, x, y, s)
	local n = gui.new_box_node(V3(x or 0, y or 0, 0), V3(1, 1, 0))
	gui.set_visible(n, false)
	if s then gui.set_scale(n, V3(s, s, 1)) end
	if parent then gui.set_parent(n, parent) end
	return n
end

function M.box(parent, sprite, x, y, w, h, color)
	local n = gui.new_box_node(V3(x, y, 0), V3(w, h, 0))
	if sprite then
		gui.set_texture(n, M.TEX)
		gui.play_flipbook(n, sprite)
	end
	gui.set_color(n, color or M.WHITE)
	gui.set_inherit_alpha(n, true)
	if parent then gui.set_parent(n, parent) end
	return n
end

function M.slice(parent, sprite, x, y, w, h, color, border)
	local n = M.box(parent, sprite, x, y, w, h, color)
	gui.set_slice9(n, vmath.vector4(border, border, border, border))
	return n
end

function M.text(parent, str, x, y, size, color, outline)
	local n = gui.new_text_node(V3(x, y, 0), str)
	gui.set_font(n, M.FONT)
	gui.set_line_break(n, true)
	gui.set_size(n, V3(3000, 220, 0))
	local s = size / M.FONT_SIZE
	gui.set_scale(n, V3(s, s, 1))
	gui.set_color(n, color or M.BONE)
	gui.set_outline(n, outline or M.INK)
	gui.set_shadow(n, vmath.vector4(0, 0, 0, 0.45))
	gui.set_inherit_alpha(n, true)
	if parent then gui.set_parent(n, parent) end
	return n
end

function M.text_width(n)
	M.font_res = M.font_res or gui.get_font_resource(M.FONT)
	local w = 0
	for line in string.gmatch(gui.get_text(n) .. "\n", "([^\n]*)\n") do
		if line ~= "" then w = math.max(w, resource.get_text_metrics(M.font_res, line).width) end
	end
	return w
end

function M.fit(n, max_w, size)
	local s = size / M.FONT_SIZE
	local w = M.text_width(n)
	if w * s > max_w and w > 0 then s = max_w / w end
	gui.set_scale(n, V3(s, s, 1))
end

function M.set_text(n, str, max_w, size)
	gui.set_text(n, str)
	if max_w then M.fit(n, max_w, size) end
end

function M.icon(parent, sprite, x, y, size, color)
	local wh = sizes[sprite] or { 1, 1 }
	local k = size / math.max(wh[1], wh[2])
	return M.box(parent, sprite, x, y, wh[1] * k, wh[2] * k, color)
end

function M.delete(n)
	if n then gui.delete_node(n) end
end

-- ---------------------------------------------------------------- composite widgets

function M.btn(parent, sprite, x, y, w, h, label, tsize, fn, opts)
	local br = math.min(20, math.floor(math.min(w, h) * 0.42))
	local b_node = M.slice(parent, sprite, x, y, w, h, opts and opts.color or M.WHITE, br)
	local txt = nil
	if label and label ~= "" then
		txt = M.text(b_node, label, 0, 2, tsize or 24, M.BONE)
		M.fit(txt, w - 20, tsize or 24)
	end
	local b = M.button(b_node, w, h, fn, opts)
	b.text_node = txt
	return b_node, b
end

function M.currency_pill(parent, sprite, val, x, y, w, h)
	local bg = M.slice(parent, "panel_dark", x, y, w, h, M.WHITE, 18)
	M.icon(bg, sprite, -w / 2 + 22, 0, h - 10)
	local lbl = M.text(bg, tostring(val), 12, 0, 22, M.BONE)
	M.fit(lbl, w - 50, 22)
	return bg, lbl
end

function M.hp_bar(parent, x, y, w, h, cur, max, shield, bar_col)
	local bg = M.slice(parent, "bar_bg", x, y, w, h, M.WHITE, 8)
	local ratio = math.max(0, math.min(1, cur / math.max(1, max)))
	local fill = M.slice(bg, "bar_fill", -w / 2 + 3 + (w - 6) * ratio / 2, 0, math.max(4, (w - 6) * ratio), h - 6, bar_col or M.GREEN, 6)
	gui.set_visible(fill, ratio > 0)
	local sh_bar = nil
	if (shield or 0) > 0 then
		local sr = math.max(0, math.min(1, shield / math.max(1, max)))
		sh_bar = M.slice(bg, "bar_fill", -w / 2 + 3 + (w - 6) * sr / 2, -h * 0.3, math.max(4, (w - 6) * sr), math.max(5, h * 0.32), M.BLUE, 4)
	end
	local txt = cur .. "/" .. max .. ((shield or 0) > 0 and (" (+" .. shield .. ")") or "")
	local lbl = M.text(bg, txt, 0, 0, math.max(14, h - 8), M.WHITE)
	M.fit(lbl, w - 12, math.max(14, h - 8))
	return bg, fill, lbl, sh_bar
end

-- ---------------------------------------------------------------- transforms

function M.world(n)
	local p = gui.get_position(n)
	local s = gui.get_scale(n).x
	local parent = gui.get_parent(n)
	while parent do
		local ps = gui.get_scale(parent).x
		p = gui.get_position(parent) + p * ps
		s = s * ps
		parent = gui.get_parent(parent)
	end
	return p, s
end

-- ---------------------------------------------------------------- buttons

function M.button(node, w, h, fn, opts)
	local b = { node = node, w = w, h = h, fn = fn, layer = M.layer, silent = opts and opts.silent, disabled = opts and opts.disabled }
	M.buttons[#M.buttons + 1] = b
	return b
end

function M.remove_buttons(layer)
	for i = #M.buttons, 1, -1 do
		if M.buttons[i].layer == layer then table.remove(M.buttons, i) end
	end
end

local function hit(b, x, y)
	if b.disabled or not gui.is_enabled(b.node, true) then return false end
	local p, s = M.world(b.node)
	return math.abs(x - p.x) <= b.w * s / 2 and math.abs(y - p.y) <= b.h * s / 2
end

function M.find_button(x, y, layer)
	for i = #M.buttons, 1, -1 do
		local b = M.buttons[i]
		if b.layer == layer and hit(b, x, y) then return b end
	end
end

function M.press(b)
	b.base_scale = b.base_scale or gui.get_scale(b.node).x
	local s = b.base_scale * 0.92
	gui.animate(b.node, "scale", V3(s, s, 1), gui.EASING_OUTQUAD, 0.06)
end

function M.release(b, fire)
	if b.base_scale then
		local s = b.base_scale
		gui.animate(b.node, "scale", V3(s, s, 1), gui.EASING_OUTBACK, 0.16)
	end
	if fire then
		if not b.silent then audio.play("button") end
		b.fn(b)
	end
end

-- ---------------------------------------------------------------- tweens & fx

function M.after(delay, fn)
	local g = M.gen
	local pg = M.layer == "popup" and M.popup_gen
	timer.delay(delay, false, function()
		if g == M.gen and (not pg or pg == M.popup_gen) then fn() end
	end)
end

function M.pop(n, from, to, dur, delay)
	gui.set_scale(n, V3(from, from, 1))
	gui.animate(n, "scale", V3(to, to, 1), gui.EASING_OUTBACK, dur or 0.28, delay or 0)
end

function M.pulse(n, k, period)
	local s = gui.get_scale(n).x
	gui.animate(n, "scale", V3(s * k, s * k, 1), gui.EASING_INOUTSINE, period or 0.65, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
end

function M.shake(n, amount)
	gui.cancel_animations(n, "euler.z")
	gui.set_euler(n, V3(0, 0, amount or 10))
	gui.animate(n, "euler.z", 0, gui.EASING_OUTELASTIC, 0.45)
end

function M.glow(n)
	gui.set_blend_mode(n, gui.BLEND_ADD)
	return n
end

function M.burst(parent, x, y, count, color, spread, size)
	for _ = 1, (count or 6) do
		local s = (size or 26) * (0.7 + math.random() * 0.6)
		local n = M.glow(M.box(parent, "spark", x, y, s, s, color or M.GOLD))
		local a = math.random() * math.pi * 2
		local d = (spread or 65) * (0.4 + math.random() * 0.6)
		local dur = 0.28 + math.random() * 0.22
		gui.set_euler(n, V3(0, 0, math.random(0, 90)))
		gui.animate(n, "position", V3(x + math.cos(a) * d, y + math.sin(a) * d, 0), gui.EASING_OUTCUBIC, dur)
		gui.animate(n, "euler.z", math.random(-120, 120), gui.EASING_OUTQUAD, dur)
		gui.animate(n, "color.w", 0, gui.EASING_INQUAD, dur, 0, function() gui.delete_node(n) end)
	end
end

function M.ring(parent, x, y, size, color, dur)
	local n = M.glow(M.box(parent, "ring", x, y, size * 0.3, size * 0.3, color or M.WHITE))
	gui.animate(n, "size", V3(size, size, 0), gui.EASING_OUTCUBIC, dur or 0.35)
	gui.animate(n, "color.w", 0, gui.EASING_INQUAD, dur or 0.35, 0, function() gui.delete_node(n) end)
end

function M.float_text(parent, str, x, y, size, color, rise)
	local n = M.text(parent, str, x, y, size or 28, color or M.WHITE)
	M.pop(n, 0.4, 1, 0.22)
	gui.animate(n, "position.y", y + (rise or 64), gui.EASING_OUTQUAD, 0.75, 0.12)
	gui.animate(n, "color.w", 0, gui.EASING_INQUAD, 0.3, 0.55, function() gui.delete_node(n) end)
	return n
end

function M.fly(n, to_x, to_y, dur, delay, done)
	delay = delay or 0
	gui.animate(n, "position.x", to_x, gui.EASING_INOUTSINE, dur, delay)
	gui.animate(n, "position.y", to_y, gui.EASING_OUTQUAD, dur, delay, done and function() done() end or nil)
end

return M
