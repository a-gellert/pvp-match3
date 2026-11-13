-- GUI toolkit on top of Druid: palette, node factories, Druid buttons/texts/progress/scrolls,
-- layers (screen / popup, one Druid instance each), tweens and juicy FX.
local druid = require "druid.druid"
local druid_drag = require "druid.base.drag"
local druid_const = require "druid.const"
local druid_helper = require "druid.helper"
local druid_style = require "main.gui.druid_style"
local audio = require "main.modules.audio"
local loader = require "main.modules.loader"
local sizes = require "main.gui.sprite_sizes"

-- Defold dispatches TOUCH_MULTI (action.touch) for touch swipes on both native Android/iOS
-- and HTML5 mobile browsers, while mouse emulation only sends tap start/end without move
-- deltas. Druid's built-in drag checks helper.is_mobile() (false in HTML5), so mobile web
-- dropped touch_multi; handle native mobile, mobile web, and touch/mouse switching cleanly.
local function is_coarse_web()
	return html5 and html5.run("window.matchMedia && window.matchMedia('(pointer: coarse)').matches") == "true" or false
end

local IS_COARSE_WEB = is_coarse_web()
druid_drag._find_touch = function(self, action_id, action, touch_id)
	if not self._allowed_drag_actions[action_id] then
		return
	end
	if action_id == druid_const.ACTION_MULTITOUCH then
		self._prefer_multi = true
		if action.touch then
			local all_released = true
			for i = 1, #action.touch do
				if not action.touch[i].released then
					all_released = false
					break
				end
			end
			if all_released then
				self._skip_touch_until_press = true
			end
		end
	elseif action_id == druid_const.ACTION_TOUCH then
		if druid_helper.is_mobile() or druid_helper.is_web_mobile() or IS_COARSE_WEB then
			return
		end
		if self._prefer_multi or self._skip_touch_until_press then
			if action.pressed and not self.is_touch then
				self._prefer_multi = false
				self._skip_touch_until_press = false
			else
				return
			end
		end
	end
	if action.touch then
		local touch = action.touch
		for i = 1, #touch do
			if touch[i].id == touch_id then
				return touch[i]
			end
		end
		return touch[1]
	else
		return action
	end
end

local M = {}
local V3 = vmath.vector3
local V4 = vmath.vector4

M.TEX = "game"
M.FONT = "main"
M.FONT_SIZE = 44

function M.hex(s, a)
	local v = tonumber(string.sub(s, 2), 16)
	return V4(math.floor(v / 65536) / 255, math.floor(v / 256) % 256 / 255, v % 256 / 255, a or 1)
end

-- Casual Dark Fantasy palette (Royal Slate & Cobalt / Clash Royale style)
M.WHITE    = V4(1, 1, 1, 1)
M.CLEAR    = V4(1, 1, 1, 0)
M.INK      = M.hex("#090d16")
M.BG_DARK  = M.hex("#162032")
M.BG_PANEL = M.hex("#22314a")
M.BG_CARD  = M.hex("#2b3e5e")
M.BONE     = M.hex("#f8f5ee")
M.DIM      = M.hex("#a5b5d4")
M.GOLD     = M.hex("#ffc72c")
M.DIAMOND  = M.hex("#5be4ff")
M.PRESTIGE = M.hex("#d977ff")
M.RED      = M.hex("#ff4d66")
M.YELLOW   = M.hex("#ffd738")
M.PURPLE   = M.hex("#bf5eff")
M.GREEN    = M.hex("#44ea8a")
M.BLUE     = M.hex("#4db8ff")
M.CRIMSON  = M.hex("#e63946")
M.SHADOW   = V4(0, 0, 0, 0.45)

M.GEM_COLOR = { red = M.RED, yellow = M.YELLOW, purple = M.PURPLE, green = M.GREEN, blue = M.BLUE, prism = M.WHITE }
M.GEM_SPRITE = { red = "gem_red", yellow = "gem_yellow", purple = "gem_purple", green = "gem_green", blue = "gem_blue", prism = "gem_prism" }
M.RARITY_FRAME = { common = "card_common", rare = "card_rare", epic = "card_epic", legendary = "card_legendary" }
M.RARITY_COLOR = { common = M.hex("#cbd5e1"), rare = M.hex("#f59e0b"), epic = M.hex("#c084fc"), legendary = M.hex("#38bdf8") }

M.gen = 0
M.popup_gen = 0
M.layer = "screen"
M.layers = {}
M.druid = nil

-- ---------------------------------------------------------------- Druid layers
function M.init(context)
	M.context = context
	druid.set_default_style(druid_style)
	druid.set_sound_function(function(id) audio.play(id) end)
end

function M.set_layer(layer)
	M.layer = layer
	M.druid = M.layers[layer]
end

-- Fresh Druid instance for a layer (old one must be finalized before its nodes are deleted).
function M.open_layer(layer)
	M.close_layer(layer)
	M.layers[layer] = druid.new(M.context)
	M.set_layer(layer)
	return M.layers[layer]
end

function M.close_layer(layer)
	local d = M.layers[layer]
	if d then
		-- Druid schedules late_init (button stencil lookup) with timer.delay(0) and final() does not
		-- cancel it: a layer opened and closed within one frame would hit its deleted nodes.
		if d._late_init_timer_id then
			timer.cancel(d._late_init_timer_id)
			d._late_init_timer_id = nil
		end
		d:final()
		M.layers[layer] = nil
	end
	if M.layer == layer then M.druid = nil end
end

function M.update(dt)
	for _, key in ipairs({ "screen", "popup" }) do
		local d = M.layers[key]
		if d then d:update(dt) end
	end
end

-- Run fn on the next frame (button callbacks may rebuild the screen safely).
function M.defer(fn)
	local layer = M.layer
	timer.delay(0, false, function()
		local prev = M.layer
		M.set_layer(layer)
		fn()
		M.set_layer(prev)
	end)
end

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
		loader.apply(n, sprite)
	end
	gui.set_color(n, color or M.WHITE)
	gui.set_inherit_alpha(n, true)
	if parent then gui.set_parent(n, parent) end
	return n
end

function M.slice(parent, sprite, x, y, w, h, color, border)
	local n = M.box(parent, sprite, x, y, w, h, color)
	gui.set_slice9(n, V4(border, border, border, border))
	return n
end

function M.text(parent, str, x, y, size, color, outline)
	local n = gui.new_text_node(V3(x, y, 0), str)
	gui.set_font(n, M.FONT)
	gui.set_line_break(n, false)
	gui.set_size(n, V3(3000, 220, 0))
	local s = size / M.FONT_SIZE
	gui.set_scale(n, V3(s, s, 1))
	gui.set_color(n, color or M.BONE)
	gui.set_outline(n, outline or M.INK)
	gui.set_shadow(n, V4(0, 0, 0, 0.45))
	gui.set_inherit_alpha(n, true)
	if parent then gui.set_parent(n, parent) end
	return n
end

-- Druid text that auto-downscales into max_w (and optional multi-line area).
-- opts: lines (multi-line count), adjust ("downscale"|"trim"...), pivot, outline, plain
function M.label(parent, str, x, y, size, color, max_w, opts)
	opts = opts or {}
	local n = M.text(parent, str, x, y, size, color, opts.outline)
	if opts.pivot then gui.set_pivot(n, opts.pivot) end
	if not max_w then return n end
	local s = size / M.FONT_SIZE
	local lines = opts.lines or 1
	gui.set_line_break(n, lines > 1)
	gui.set_size(n, V3(max_w / s, M.FONT_SIZE * (lines > 1 and (1.25 * lines + 0.2) or 1.6), 0))
	-- plain: no Druid component (nodes that get deleted outside of a layer close)
	if opts.plain then return n end
	local t = M.druid and M.druid:new_text(n, str, opts.adjust or "downscale") or nil
	return n, t
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

function M.icon(parent, sprite, x, y, size, color)
	local wh = sizes[sprite] or { 1, 1 }
	local k = size / math.max(wh[1], wh[2])
	return M.box(parent, sprite, x, y, wh[1] * k, wh[2] * k, color)
end

function M.delete(n)
	if n then gui.delete_node(n) end
end

-- ---------------------------------------------------------------- Druid widgets
-- Generic tap target on any node (cards, tiles). Callback is deferred one frame.
function M.button(node, fn, opts)
	opts = opts or {}
	local b
	b = M.druid:new_button(node, function()
		M.defer(function() fn(b) end)
	end)
	b.base_color = gui.get_color(node)
	b.silent = opts.silent
	if opts.disabled then b:set_enabled(false) end
	return b
end

-- Sprite button with label and optional icon.
-- opts: color, text_color, icon, icon_size, disabled, silent, pulse, badge
function M.btn(parent, sprite, x, y, w, h, label, tsize, fn, opts)
	opts = opts or {}
	local br = math.min(20, math.floor(math.min(w, h) * 0.42))
	if opts.pulse then
		-- Breathe a holder so Druid's own press/hover scale on the button stays intact
		local holder = M.pane(parent, x, y)
		gui.animate(holder, "scale", V3(1.05, 1.05, 1), gui.EASING_INOUTSINE, 0.7, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
		local glow = M.glow(M.box(holder, "glow", 0, 0, w * 1.3, h * 1.9, V4(1, 0.8, 0.35, 0.22)))
		gui.animate(glow, "color.w", 0.08, gui.EASING_INOUTSINE, 0.7, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
		parent, x, y = holder, 0, 0
	end
	local node = M.slice(parent, sprite, x, y, w, h, opts.color or M.WHITE, br)
	local has_label = label and label ~= ""
	local icon_w = 0
	if opts.icon then
		local isz = opts.icon_size or math.min(h - 18, 46)
		local ix = has_label and (-w / 2 + 14 + isz / 2) or 0
		M.icon(node, opts.icon, ix, 2, isz)
		icon_w = has_label and (isz + 10) or 0
	end
	local txt
	if has_label then
		txt = M.label(node, label, icon_w / 2, 3, tsize or 24, opts.text_color or M.BONE, w - 26 - icon_w)
	end
	local b = M.button(node, fn, opts)
	b.text_node = txt
	if opts.badge and opts.badge > 0 then M.badge(node, w / 2 - 6, h / 2 - 6, opts.badge) end
	return node, b
end

-- Red notification dot with a count.
function M.badge(parent, x, y, count, size)
	size = size or 34
	local n = M.box(parent, "badge_dot", x, y, size, size)
	if count and count > 1 then
		M.text(n, tostring(math.min(count, 9)), 0, 1, size * 0.62, M.WHITE)
	end
	gui.animate(n, "scale", V3(1.15, 1.15, 1), gui.EASING_INOUTSINE, 0.55, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
	return n
end

-- Progress bar (Druid progress) with optional "ghost" trail that catches up later.
-- Returns table { bg, fill, prog, ghost, label, set(cur, max, extra) }
function M.bar(parent, x, y, w, h, ratio, color, opts)
	opts = opts or {}
	local bg = M.slice(parent, "bar_bg", x, y, w, h, M.WHITE, 8)
	local inner_w, inner_h = w - 6, math.max(6, h - 6)
	local r = { bg = bg }
	if opts.ghost then
		local g = M.slice(bg, "bar_fill", -inner_w / 2, 0, inner_w, inner_h, opts.ghost_color or V4(1, 0.95, 0.85, 0.85), 6)
		gui.set_pivot(g, gui.PIVOT_W)
		r.ghost = M.druid:new_progress(g, "x", ratio)
		r.ghost_node = g
	end
	local f = M.slice(bg, "bar_fill", -inner_w / 2, 0, inner_w, inner_h, color or M.GREEN, 6)
	gui.set_pivot(f, gui.PIVOT_W)
	r.fill = f
	r.prog = M.druid:new_progress(f, "x", ratio)
	if opts.text then
		local ts = opts.text_size or math.max(14, h - 6)
		r.label = M.text(bg, opts.text, 0, 1, ts, M.WHITE)
		M.fit(r.label, w - 10, ts)
	end
	function r.to(value, instant)
		value = math.max(0, math.min(1, value))
		if instant then r.prog:set_value(value) else r.prog:to(value) end
		if r.ghost then
			if value >= r.ghost:get() or instant then
				r.ghost:set_value(value)
			else
				M.after(0.35, function() r.ghost:to(value) end)
			end
		end
	end
	function r.text(str)
		if r.label then gui.set_text(r.label, str); M.fit(r.label, w - 10, opts.text_size or math.max(14, h - 6)) end
	end
	return r
end

-- Vertical Druid scroll inside a stencil-clipped view. Children go into `content`,
-- placed from y = 0 (top) downward (negative y). Call set_height(h) after filling.
function M.scroll(parent, cx, cy, w, h)
	local view = gui.new_box_node(V3(cx, cy, 0), V3(w, h, 0))
	gui.set_parent(view, parent)
	gui.set_clipping_mode(view, gui.CLIPPING_MODE_STENCIL)
	gui.set_clipping_visible(view, false)
	gui.set_color(view, V4(1, 1, 1, 1))
	local content = gui.new_box_node(V3(0, h / 2, 0), V3(w, h, 0))
	gui.set_pivot(content, gui.PIVOT_N)
	gui.set_visible(content, false)
	gui.set_parent(content, view)
	local sc = M.druid:new_scroll(view, content)
	sc:set_horizontal_scroll(false)
	local r = { view = view, content = content, scroll = sc, w = w, h = h }
	function r.set_height(ch)
		sc:set_size(V3(w, math.max(h, ch), 0))
	end
	return r
end

function M.currency_pill(parent, sprite, val, x, y, w, h, on_plus)
	local bg = M.slice(parent, "panel_dark", x, y, w, h, M.WHITE, 18)
	M.icon(bg, sprite, -w / 2 + 20, 1, h + 4)
	local lbl = M.label(bg, M.short_num(val), on_plus and 4 or 10, 2, 22, M.BONE, w - (on_plus and 80 or 54))
	return bg, lbl
end

function M.short_num(v)
	v = math.floor(v or 0)
	if v >= 1000000 then return string.format("%.1fM", v / 1000000) end
	if v >= 10000 then return string.format("%.1fK", v / 1000) end
	return tostring(v)
end

-- Animated number counter on a text node.
function M.count_up(n, from, to, dur, fmt)
	local steps = 14
	for i = 1, steps do
		M.after(dur * i / steps, function()
			local v = math.floor(from + (to - from) * i / steps + 0.5)
			gui.set_text(n, fmt and fmt(v) or tostring(v))
		end)
	end
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

-- ---------------------------------------------------------------- tweens & fx
function M.after(delay, fn)
	local g = M.gen
	local layer = M.layer
	local pg = M.popup_gen
	timer.delay(delay, false, function()
		if g ~= M.gen then return end
		if layer == "popup" and pg ~= M.popup_gen then return end
		local prev = M.layer
		M.set_layer(layer)
		fn()
		M.set_layer(prev)
	end)
end

function M.pop(n, from, to, dur, delay)
	gui.set_scale(n, V3(from, from, 1))
	gui.animate(n, "scale", V3(to, to, 1), gui.EASING_OUTBACK, dur or 0.28, delay or 0)
end

function M.fade_in(n, dur, delay)
	local c = gui.get_color(n)
	gui.set_color(n, V4(c.x, c.y, c.z, 0))
	gui.animate(n, "color.w", c.w, gui.EASING_OUTQUAD, dur or 0.25, delay or 0)
end

function M.slide_in(n, dx, dy, dur, delay)
	local p = gui.get_position(n)
	gui.set_position(n, V3(p.x + (dx or 0), p.y + (dy or 0), 0))
	gui.animate(n, "position", p, gui.EASING_OUTBACK, dur or 0.35, delay or 0)
end

function M.pulse(n, k, period)
	local s = gui.get_scale(n).x
	gui.animate(n, "scale", V3(s * k, s * k, 1), gui.EASING_INOUTSINE, period or 0.65, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
end

function M.spin(n, period)
	gui.animate(n, "euler.z", -360, gui.EASING_LINEAR, period or 8, 0, nil, gui.PLAYBACK_LOOP_FORWARD)
end

function M.bob(n, amp, period, phase)
	local p = gui.get_position(n)
	gui.animate(n, "position.y", p.y + (amp or 6), gui.EASING_INOUTSINE, period or 1.2, phase or 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
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

-- Confetti rain for big wins
function M.confetti(parent, cx, top, width, count)
	local cols = { M.GOLD, M.RED, M.BLUE, M.GREEN, M.PURPLE, M.YELLOW }
	for i = 1, (count or 40) do
		local x = cx + (math.random() - 0.5) * width
		local n = M.box(parent, "square", x, top + math.random(0, 120), math.random(8, 16), math.random(12, 22), cols[(i % #cols) + 1])
		local dur = 1.4 + math.random() * 1.2
		gui.set_euler(n, V3(0, 0, math.random(0, 360)))
		gui.animate(n, "position.y", top - 700 - math.random(0, 400), gui.EASING_INQUAD, dur, math.random() * 0.4)
		gui.animate(n, "position.x", x + (math.random() - 0.5) * 220, gui.EASING_INOUTSINE, dur, 0)
		gui.animate(n, "euler.z", math.random(-720, 720), gui.EASING_LINEAR, dur)
		gui.animate(n, "color.w", 0, gui.EASING_INQUAD, dur * 0.4, dur * 0.6, function() gui.delete_node(n) end)
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

-- Big centered banner text that punches in and fades (combos, turn changes).
function M.banner(parent, str, x, y, size, color, hold)
	local n = M.text(parent, str, x, y, size or 48, color or M.GOLD)
	gui.set_scale(n, V3(0.1, 0.1, 1))
	local s = (size or 48) / M.FONT_SIZE
	gui.animate(n, "scale", V3(s * 1.15, s * 1.15, 1), gui.EASING_OUTBACK, 0.22, 0, function()
		gui.animate(n, "scale", V3(s, s, 1), gui.EASING_OUTQUAD, 0.1)
	end)
	gui.animate(n, "color.w", 0, gui.EASING_INQUAD, 0.25, hold or 0.7, function() gui.delete_node(n) end)
	return n
end

function M.fly(n, to_x, to_y, dur, delay, done)
	delay = delay or 0
	gui.animate(n, "position.x", to_x, gui.EASING_INOUTSINE, dur, delay)
	gui.animate(n, "position.y", to_y, gui.EASING_OUTQUAD, dur, delay, done and function() done() end or nil)
end

-- Reward icons flying from (x1,y1) to (x2,y2) with a coin sound per icon.
function M.collect(parent, sprite, x1, y1, x2, y2, count, size)
	for i = 1, (count or 6) do
		local n = M.icon(parent, sprite, x1 + math.random(-30, 30), y1 + math.random(-30, 30), size or 40)
		M.pop(n, 0.2, 1, 0.18, (i - 1) * 0.04)
		M.fly(n, x2, y2, 0.45 + math.random() * 0.15, 0.2 + (i - 1) * 0.05, function()
			gui.delete_node(n)
			audio.play("coin", 0.6, 0.95 + math.random() * 0.2)
		end)
	end
end

function M.flash_hit(n, col)
	if not n then return end
	gui.cancel_animations(n, "color")
	gui.set_color(n, col or M.RED)
	gui.animate(n, "color", M.WHITE, gui.EASING_OUTQUAD, 0.22)
end

function M.puff(parent, x, y, color, size)
	local s = size or 28
	local n = M.box(parent, "puff", x, y, s, s, color or V4(0.85, 0.85, 0.92, 0.55))
	gui.animate(n, "size", V3(s * 1.9, s * 1.9, 0), gui.EASING_OUTQUAD, 0.26)
	gui.animate(n, "color.w", 0, gui.EASING_INQUAD, 0.26, 0, function() gui.delete_node(n) end)
end

function M.spark_dot(parent, x, y, color, size, dur)
	local s = size or 16
	local n = M.glow(M.box(parent, "glow", x, y, s, s, color or M.GOLD))
	gui.animate(n, "size", V3(4, 4, 0), gui.EASING_INQUAD, dur or 0.22)
	gui.animate(n, "color.w", 0, gui.EASING_INQUAD, dur or 0.22, 0, function() gui.delete_node(n) end)
end

function M.shake_xy(n, amp)
	if not n then return end
	amp = amp or 7
	gui.cancel_animations(n, "position")
	gui.set_position(n, V3(math.random(-amp, amp), math.random(-amp, amp), 0))
	M.after(0.04, function()
		local a = math.floor(amp * 0.6)
		gui.set_position(n, V3(math.random(-a, a), math.random(-a, a), 0))
		gui.animate(n, "position", V3(0, 0, 0), gui.EASING_OUTQUAD, 0.12)
	end)
end

-- Full-screen flash (skills, big hits)
function M.flash(parent, vw, vh, color, dur)
	local n = M.glow(M.box(parent, "square", vw / 2, vh / 2, vw, vh, color or V4(1, 1, 1, 0.35)))
	gui.animate(n, "color.w", 0, gui.EASING_OUTQUAD, dur or 0.25, 0, function() gui.delete_node(n) end)
end

-- ---------------------------------------------------------------- backgrounds
-- Layered background: base colour, soft light blobs, drifting embers, vignette.
function M.background(parent, vw, vh, tint, embers)
	local root = M.pane(parent, 0, 0)
	M.box(root, "square", vw / 2, vh / 2, vw, vh, M.BG_DARK)
	local t = tint or M.hex("#41588a")
	-- Soft center spotlight: illuminates the table/arena like in Clash Royale
	M.glow(M.box(root, "glow", vw / 2, vh * 0.52, vw * 1.05, vh * 0.72, V4(0.25, 0.38, 0.6, 0.22)))
	local g1 = M.glow(M.box(root, "bg_glow", vw * 0.2, vh * 0.78, vw * 0.9, vh * 0.75, V4(t.x, t.y, t.z, 0.2)))
	local g2 = M.glow(M.box(root, "bg_glow", vw * 0.85, vh * 0.3, vw * 0.8, vh * 0.7, V4(0.48, 0.35, 0.85, 0.16)))
	gui.animate(g1, "position.x", vw * 0.3, gui.EASING_INOUTSINE, 7, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
	gui.animate(g2, "position.y", vh * 0.4, gui.EASING_INOUTSINE, 9, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
	if embers ~= false then
		local layer = M.pane(root, 0, 0)
		local function spawn()
			local x = math.random() * vw
			local s = math.random(6, 14)
			local col = (math.random() < 0.6) and V4(1, 0.72, 0.35, 0.55) or V4(0.7, 0.55, 1, 0.45)
			local n = M.glow(M.box(layer, "glow", x, -20, s, s, col))
			local dur = 7 + math.random() * 6
			gui.animate(n, "position.y", vh + 40, gui.EASING_LINEAR, dur)
			gui.animate(n, "position.x", x + math.random(-80, 80), gui.EASING_INOUTSINE, dur)
			gui.animate(n, "color.w", 0, gui.EASING_INQUAD, dur, 0, function() gui.delete_node(n) end)
		end
		for _ = 1, 6 do
			local n0 = M.glow(M.box(layer, "glow", math.random() * vw, math.random() * vh, 8, 8, V4(1, 0.72, 0.35, 0.4)))
			gui.animate(n0, "position.y", vh + 40, gui.EASING_LINEAR, 6 + math.random() * 5)
			gui.animate(n0, "color.w", 0, gui.EASING_INQUAD, 6, 0, function() gui.delete_node(n0) end)
		end
		local function loop()
			spawn()
			M.after(0.6 + math.random() * 0.5, loop)
		end
		loop()
	end
	M.box(root, "vignette", vw / 2, vh / 2, vw * 1.04, vh * 1.04, V4(1, 1, 1, 0.85))
	return root
end

return M
