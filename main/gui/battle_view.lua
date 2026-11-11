-- Battle Screen: Casual Dark Fantasy arena (melee dashes, arrow volleys, magic fireballs) + 7x7 Match-3 board.
local ui = require "main.gui.ui"
local config = require "main.modules.config"
local battle = require "main.modules.battle"
local i18n = require "main.modules.i18n"
local audio = require "main.modules.audio"

local M = {}
local V3 = vmath.vector3

local GEM_SPRITE = {
	red = "gem_red",
	yellow = "gem_yellow",
	purple = "gem_purple",
	green = "gem_green",
	blue = "gem_blue",
	prism = "gem_prism",
}

local SPEC_SPRITE = {
	line_h = "spec_line_h",
	line_v = "spec_line_v",
	bomb = "spec_bomb",
}

local st = {}

local function cell_pos(r, c)
	return st.board_x0 + (c - 0.5) * st.cell, st.board_y0 + (r - 0.5) * st.cell
end

local function screen_to_cell(x, y)
	local c = math.floor((x - st.board_x0) / st.cell) + 1
	local r = math.floor((y - st.board_y0) / st.cell) + 1
	if r >= 1 and r <= config.GRID and c >= 1 and c <= config.GRID then
		return r, c
	end
end

local function make_gem_node(r, c, gem, drop_dy)
	if not gem then return nil end
	local x, y = cell_pos(r, c)
	local gs = st.cell * 0.86
	local start_y = drop_dy and (y + drop_dy) or y
	local n = ui.box(st.gem_layer, GEM_SPRITE[gem.color] or "gem_red", x, start_y, gs, gs)
	if gem.special and SPEC_SPRITE[gem.special] then
		local sp = ui.box(n, SPEC_SPRITE[gem.special], 0, 0, gs * 0.88, gs * 0.88)
		ui.pulse(sp, 1.12, 0.6)
	end
	if drop_dy and drop_dy > 0 then
		gui.animate(n, "position.y", y, gui.EASING_OUTBOUNCE, 0.24, (r - 1) * 0.015)
	end
	return n
end

local function rebuild_gems(drop_dy)
	if st.gem_layer then gui.delete_node(st.gem_layer) end
	st.gem_layer = ui.pane(st.root, 0, 0)
	st.gem_nodes = {}
	local g = st.session.board.grid
	for r = 1, config.GRID do
		st.gem_nodes[r] = {}
		for c = 1, config.GRID do
			st.gem_nodes[r][c] = make_gem_node(r, c, g[r][c], drop_dy)
		end
	end
end

local function refresh_fighters()
	local s = st.session
	if not (s and st.hud_layer) then return end
	gui.delete_node(st.hud_layer)
	st.hud_layer = ui.pane(st.root, 0, 0)

	local is_p = s.turn == "player"
	ui.slice(st.hud_layer, is_p and "btn_gold" or "btn_crimson", st.turn_x, st.turn_y, 200, 44, ui.WHITE, 16)
	local t_lbl = ui.text(st.hud_layer, i18n.t(is_p and "YOUR_TURN" or "ENEMY_TURN"), st.turn_x, st.turn_y + 1, 20, ui.WHITE)
	ui.fit(t_lbl, 180, 20)

	ui.hp_bar(st.hud_layer, st.p_bar_x, st.p_bar_y, st.bar_w, 28, s.player.hp, s.player.max_hp, s.player.shield, ui.GREEN)
	for i = 1, s.player.max_moves do
		local active = is_p and i <= s.player.moves_left
		local ox = st.p_orbs_x + (i - 1) * 26
		ui.box(st.hud_layer, "icon_move_orb", ox, st.p_orbs_y, 22, 22, active and ui.WHITE or vmath.vector4(0.3, 0.35, 0.45, 0.45))
	end

	ui.hp_bar(st.hud_layer, st.e_bar_x, st.e_bar_y, st.bar_w, 28, s.enemy.hp, s.enemy.max_hp, s.enemy.shield, ui.RED)
	for i = 1, s.enemy.max_moves do
		local active = (not is_p) and i <= s.enemy.moves_left
		local ox = st.e_orbs_x - (i - 1) * 26
		ui.box(st.hud_layer, "icon_move_orb", ox, st.e_orbs_y, 22, 22, active and ui.RED or vmath.vector4(0.35, 0.25, 0.3, 0.45))
	end

	for _, kind in ipairs({ "shuffle", "hammer", "extra_move" }) do
		local cnt = s.boosters[kind] or 0
		local bx, by = st.boost_pos[kind].x, st.boost_pos[kind].y
		if cnt > 0 then
			ui.text(st.hud_layer, "x" .. cnt, bx + 54, by + 16, 17, ui.GOLD)
		else
			ui.box(st.hud_layer, "icon_ad", bx + 54, by + 16, 24, 18)
		end
	end

	-- 2-Crystal Rune Gauges below each Squad + Active Status Icons (Burn / Poison)
	local ry_off = (st.sq_size or 96) * 0.44
	for _, side in ipairs({
		{ sqs = s.player.squads, homes = st.p_home },
		{ sqs = s.enemy.squads,  homes = st.e_home },
	}) do
		for _, col in ipairs(config.ATTACK_COLORS) do
			local sq, hm = side.sqs[col], side.homes[col]
			if sq and hm and sq.runes then
				for slot = 1, 2 do
					local rcol = sq.runes[slot]
					local filled = sq.rune_filled and sq.rune_filled[slot]
					local rx = hm.x + (slot == 1 and -12 or 12)
					local ry = hm.y - ry_off
					ui.box(st.hud_layer, "rune_bg", rx, ry, 20, 20, ui.WHITE)
					if filled then
						ui.glow(ui.box(st.hud_layer, "glow", rx, ry, 26, 26, ui.GEM_COLOR[rcol] or ui.WHITE))
					end
					local gc = ui.box(st.hud_layer, GEM_SPRITE[rcol] or "gem_red", rx, ry, filled and 15 or 12, filled and 15 or 12)
					if not filled then gui.set_alpha(gc, 0.42) end
				end
			end
		end
	end

	local function draw_statuses(statuses, bx, by, dir)
		if not statuses then return end
		local sx = bx
		if statuses.burn then
			ui.box(st.hud_layer, "icon_burn", sx, by, 22, 22)
			ui.text(st.hud_layer, tostring(statuses.burn.dmg), sx + dir * 16, by, 14, ui.RED)
			sx = sx + dir * 42
		end
		if statuses.poison then
			ui.box(st.hud_layer, "icon_poison", sx, by, 22, 22)
			ui.text(st.hud_layer, tostring(statuses.poison.dmg), sx + dir * 16, by, 14, ui.GREEN)
		end
	end
	draw_statuses(s.player.statuses, st.p_bar_x - st.bar_w / 2 + 12, st.p_bar_y + 24, 1)
	draw_statuses(s.enemy.statuses, st.e_bar_x + st.bar_w / 2 - 12, st.e_bar_y - 24, -1)
end

local function show_tutorial_hand()
	if st.tut_node then gui.delete_node(st.tut_node); st.tut_node = nil end
	local s = st.session
	if not (s and s.tutorial and s.turn == "player" and s.status == "play" and s.tutorial_step <= 2) then return end
	local m = battle.suggest_move(s)
	if not m then return end
	local x1, y1 = cell_pos(m.r1, m.c1)
	local x2, y2 = cell_pos(m.r2, m.c2)
	st.tut_node = ui.pane(st.root, 0, 0)
	local hand = ui.box(st.tut_node, "icon_hand", x1 + 12, y1 - 16, 54, 54)
	gui.animate(hand, "position", V3(x2 + 12, y2 - 16, 0), gui.EASING_INOUTSINE, 0.85, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
	local pill = ui.slice(st.tut_node, "panel_dark", st.board_cx, st.board_y0 + st.board_size + 42, 290, 40, ui.WHITE, 14)
	ui.text(pill, i18n.t("TUT_MATCH"), 0, 1, 20, ui.GOLD)
end

local function spawn_squad(parent, sprite, x, y, size, flip_x, phase)
	local holder = ui.pane(parent, x, y)
	local sh = ui.box(holder, "glow", 0, -size * 0.34, size * 0.86, size * 0.28, vmath.vector4(0, 0, 0, 0.45))
	gui.set_alpha(sh, 0.45)
	local vis = ui.icon(holder, sprite, 0, 0, size)
	if flip_x then gui.set_scale(vis, V3(-1, 1, 1)) end
	-- Subtle idle breathing on child visual so holder coordinates remain clean for dashes
	gui.animate(vis, "position.y", 4, gui.EASING_INOUTSINE, 1.15, phase, nil, gui.PLAYBACK_LOOP_PINGPONG)
	return holder, vis, { x = x, y = y }
end

function M.build(app, parent)
	st = {
		app = app,
		session = app.session,
		root = ui.pane(parent, 0, 0),
		busy = false,
		ai_timer = 0,
		hammer_mode = false,
		sel = nil,
		drag = nil,
		p_squads = {},
		e_squads = {},
		p_vis = {},
		e_vis = {},
		p_home = {},
		e_home = {},
		boost_pos = {},
	}
	local vw, vh = app.vw, app.vh
	local is_land = app.orient == "landscape"

	ui.box(st.root, "square", vw / 2, vh / 2, vw, vh, ui.BG_DARK)
	st.arena_shake = ui.pane(st.root, 0, 0)

	local s = st.session
	local arena_cx, arena_cy, arena_w, arena_h

	if is_land then
		local b_size = math.min(vh - 90, 760)
		st.cell = math.floor((b_size - 28) / config.GRID)
		st.board_size = st.cell * config.GRID
		st.board_cx = vw - st.board_size / 2 - 54
		st.board_cy = vh / 2
		st.board_x0 = st.board_cx - st.board_size / 2
		st.board_y0 = st.board_cy - st.board_size / 2

		local left_w = st.board_x0 - 40
		arena_cx = left_w / 2 + 16
		arena_w = left_w - 24
		arena_h = 320
		arena_cy = vh - 260

		st.turn_x, st.turn_y = arena_cx + 150, vh - 46
		st.p_face_x, st.p_face_y = 92, 330
		st.e_face_x, st.e_face_y = left_w - 64, 330
		st.bar_w = 210
		st.p_bar_x, st.p_bar_y = st.p_face_x + 168, st.p_face_y + 14
		st.e_bar_x, st.e_bar_y = st.e_face_x - 168, st.e_face_y + 14
		st.p_orbs_x, st.p_orbs_y = st.p_face_x + 76, st.p_face_y - 22
		st.e_orbs_x, st.e_orbs_y = st.e_face_x - 76, st.e_face_y - 22
		st.boost_y = 110
		st.boost_cx = arena_cx
	else
		st.cell = math.floor((math.min(vw - 44, 672) - 24) / config.GRID)
		st.board_size = st.cell * config.GRID
		st.board_cx = vw / 2
		st.board_x0 = st.board_cx - st.board_size / 2
		st.board_y0 = 148
		st.board_cy = st.board_y0 + st.board_size / 2

		local board_top = st.board_y0 + st.board_size
		st.p_face_x, st.p_face_y = 74, board_top + 66
		st.e_face_x, st.e_face_y = vw - 74, board_top + 66
		st.bar_w = 188
		st.p_bar_x, st.p_bar_y = st.p_face_x + 152, st.p_face_y + 12
		st.e_bar_x, st.e_bar_y = st.e_face_x - 152, st.e_face_y + 12
		st.p_orbs_x, st.p_orbs_y = st.p_face_x + 72, st.p_face_y - 22
		st.e_orbs_x, st.e_orbs_y = st.e_face_x - 72, st.e_face_y - 22

		local top_hud_y = vh - 44
		local arena_bot = board_top + 120
		local arena_top = top_hud_y - 44
		arena_cx = vw / 2
		arena_w = vw - 28
		arena_h = math.max(170, arena_top - arena_bot)
		arena_cy = (arena_bot + arena_top) / 2
		st.turn_x, st.turn_y = vw - 118, top_hud_y
		st.boost_y = 70
		st.boost_cx = vw / 2
	end
	st.arena_cx, st.arena_cy, st.arena_w, st.arena_h = arena_cx, arena_cy, arena_w, arena_h

	-- Top HUD (locked outside shake layer)
	ui.btn(st.root, "btn_round", 46, vh - 46, 62, 62, "", 20, function() app.pause() end)
	ui.box(st.root, "icon_pause", 46, vh - 46, 30, 30)
	local stage_str = s.mode == "pvp" and (s.enemy.name ~= "" and s.enemy.name or i18n.t("PVP"))
		or i18n.t("STAGE_FMT", { n = s.stage_id })
	local stg_lbl = ui.text(st.root, stage_str, is_land and (arena_cx - 80) or (vw / 2 - 40), vh - 46, 26, ui.BONE)
	ui.fit(stg_lbl, 260, 26)

	-- Casual Dark Fantasy Stone Dungeon Arena
	ui.slice(st.arena_shake, "panel_dark", arena_cx, arena_cy, arena_w, arena_h, ui.WHITE, 20)
	ui.box(st.arena_shake, "arena_bg", arena_cx, arena_cy, arena_w - 14, arena_h - 14)

	local p_offsets = {
		red    = { x = -arena_w * 0.24, y = arena_h * 0.14 },
		yellow = { x = -arena_w * 0.36, y = -arena_h * 0.14 },
		purple = { x = -arena_w * 0.18, y = -arena_h * 0.18 },
	}
	local e_offsets = {
		red    = { x = arena_w * 0.24, y = arena_h * 0.14 },
		yellow = { x = arena_w * 0.36, y = -arena_h * 0.14 },
		purple = { x = arena_w * 0.18, y = -arena_h * 0.18 },
	}
	local sq_size = math.min(122, arena_h * 0.46)
	st.sq_size = sq_size
	for i, col in ipairs(config.ATTACK_COLORS) do
		local po, eo = p_offsets[col], e_offsets[col]
		local ph, pv, phome = spawn_squad(st.arena_shake, s.player.squads[col].sprite, arena_cx + po.x, arena_cy + po.y, sq_size, false, i * 0.25)
		st.p_squads[col], st.p_vis[col], st.p_home[col] = ph, pv, phome
		local eh, ev, ehome = spawn_squad(st.arena_shake, s.enemy.squads[col].sprite, arena_cx + eo.x, arena_cy + eo.y, sq_size, true, i * 0.25 + 0.4)
		st.e_squads[col], st.e_vis[col], st.e_home[col] = eh, ev, ehome
	end

	-- Commanders (Circular Portraits at corners)
	st.p_face_node = ui.box(st.arena_shake, s.player.face, st.p_face_x, st.p_face_y, 88, 88)
	st.e_face_node = ui.box(st.arena_shake, s.enemy.face, st.e_face_x, st.e_face_y, 88, 88)
	local e_name = s.enemy.name_key and i18n.t(s.enemy.name_key) or s.enemy.name
	local e_lbl = ui.text(st.arena_shake, e_name, st.e_bar_x, st.e_face_y + 38, 18, ui.DIM)
	ui.fit(e_lbl, st.bar_w, 18)

	-- 7x7 Board frame & tile grid
	ui.slice(st.root, "panel_stone", st.board_cx, st.board_cy, st.board_size + 26, st.board_size + 26, ui.WHITE, 24)
	for r = 1, config.GRID do
		for c = 1, config.GRID do
			local x, y = cell_pos(r, c)
			ui.box(st.root, "cell_bg", x, y, st.cell - 4, st.cell - 4)
		end
	end
	st.sel_ring = ui.box(st.root, "ring", 0, 0, st.cell * 0.96, st.cell * 0.96, ui.GOLD)
	gui.set_visible(st.sel_ring, false)

	-- Boosters bar
	local b_list = { "shuffle", "hammer", "extra_move" }
	local b_w, b_gap = 175, 192
	for i, kind in ipairs(b_list) do
		local bx = st.boost_cx + (i - 2) * b_gap
		local by = st.boost_y
		st.boost_pos[kind] = { x = bx, y = by }
		local bn = ui.btn(st.root, "btn_dark", bx, by, b_w, 72, "", 20, function()
			M.on_booster_tap(kind)
		end)
		ui.box(bn, config.BOOSTERS[kind].sprite, -b_w / 2 + 34, 0, 52, 52)
		local lbl = ui.text(bn, i18n.t("BOOST_" .. kind), 18, 0, 20, ui.BONE)
		ui.fit(lbl, b_w - 72, 20)
	end

	st.hud_layer = ui.pane(st.root, 0, 0)
	st.gem_layer = ui.pane(st.root, 0, 0)
	st.fx_layer = ui.pane(st.root, 0, 0)
	rebuild_gems(nil)
	refresh_fighters()
	show_tutorial_hand()
end

-- ---------------------------------------------------------------- FX & COMBAT CHOREOGRAPHY

local function impact_on_target(is_p, ev, ix, iy)
	local target_face = is_p and st.e_face_node or st.p_face_node
	local tp_x = is_p and st.e_face_x or st.p_face_x
	local tp_y = is_p and st.e_face_y or st.p_face_y
	local col = ui.GEM_COLOR[ev.color] or ui.RED
	local amp = ev.crit and 10 or (ev.style == "melee" and 7 or 4)

	audio.play("hit", 0.95, ev.crit and 1.15 or 1.0)
	ui.shake(target_face, is_p and -14 or 14)
	ui.flash_hit(target_face, col)
	ui.shake_xy(st.arena_shake, amp)
	ui.burst(st.fx_layer, ix, iy, ev.crit and 12 or 8, col, 62, 26)
	ui.ring(st.fx_layer, ix, iy, ev.crit and 130 or 96, col, 0.30)

	if (ev.blocked or 0) > 0 then
		ui.ring(st.fx_layer, tp_x, tp_y, 108, ui.BLUE, 0.32)
	end

	local label = "-" .. ev.dmg .. (ev.crit and (" " .. i18n.t("CRIT_TAG")) or "")
	ui.float_text(st.fx_layer, label, tp_x, tp_y + 34, ev.crit and 32 or 26, ev.crit and ui.GOLD or col, 60)
	if ix ~= tp_x or math.abs(iy - tp_y) > 45 then
		ui.burst(st.fx_layer, tp_x, tp_y, 5, col, 40, 18)
	end
end

local function animate_melee_dash(ev, is_p, home, holder, vis, delay)
	local hx, hy = home.x, home.y
	local dir = is_p and 1 or -1
	local opp_home = is_p and st.e_home[ev.color] or st.p_home[ev.color]
	local hit_x = st.arena_cx + dir * st.arena_w * 0.22
	local hit_y = (opp_home and (opp_home.y * 0.6 + st.arena_cy * 0.4) or st.arena_cy)

	ui.after(delay, function()
		audio.play("dash")
		gui.cancel_animations(holder, "position")
		gui.cancel_animations(holder, "scale")
		gui.set_position(holder, V3(hx, hy, 0))
		gui.set_scale(holder, V3(1, 1, 1))

		-- Windup & Sprint across arena
		gui.animate(holder, "position", V3(hit_x, hit_y, 0), gui.EASING_INCUBIC, 0.15)
		gui.animate(holder, "scale", V3(1.22, 1.22, 1), gui.EASING_OUTQUAD, 0.15)
		ui.after(0.04, function() ui.puff(st.fx_layer, hx + (hit_x - hx) * 0.3, hy + (hit_y - hy) * 0.3, nil, 30) end)
		ui.after(0.09, function() ui.puff(st.fx_layer, hx + (hit_x - hx) * 0.68, hy + (hit_y - hy) * 0.68, nil, 32) end)

		-- Slash Strike at enemy position
		ui.after(0.15, function()
			audio.play("slash", 0.95, ev.crit and 1.15 or 1.0)
			local sp = ev.fx or "fx_slash"
			local sl = ui.glow(ui.box(st.fx_layer, sp, hit_x + dir * 24, hit_y, 118, 118, (sp == "fx_slash") and (ui.GEM_COLOR[ev.color] or ui.WHITE) or ui.WHITE))
			gui.set_scale(sl, V3(dir * 0.65, 0.65, 1))
			gui.set_euler(sl, V3(0, 0, dir * -22))
			gui.animate(sl, "scale", V3(dir * 1.32, 1.32, 1), gui.EASING_OUTQUAD, 0.18)
			gui.animate(sl, "euler.z", dir * 32, gui.EASING_OUTQUAD, 0.18)
			gui.animate(sl, "color.w", 0, gui.EASING_INQUAD, 0.20, 0.04, function() gui.delete_node(sl) end)

			-- Opposing enemy squad flinches + flash
			local opp_vis = is_p and st.e_vis[ev.color] or st.p_vis[ev.color]
			if opp_vis then
				ui.flash_hit(opp_vis, ui.RED)
				ui.shake(opp_vis, dir * 14)
			end
			impact_on_target(is_p, ev, hit_x + dir * 28, hit_y)
		end)

		-- Dash Back to Home Anchor
		ui.after(0.22, function()
			gui.animate(holder, "position", V3(hx, hy, 0), gui.EASING_OUTQUAD, 0.18)
			gui.animate(holder, "scale", V3(1, 1, 1), gui.EASING_OUTQUAD, 0.18)
			ui.puff(st.fx_layer, hit_x, hit_y, nil, 24)
		end)
	end)
end

local function animate_ranged_volley(ev, is_p, home, holder, delay)
	local hx, hy = home.x, home.y
	local tx = is_p and st.e_face_x or st.p_face_x
	local ty = is_p and st.e_face_y or st.p_face_y
	local dir = is_p and 1 or -1
	local sprite = ev.fx or "proj_arrow"
	local count = math.max(2, math.min(4, ev.units or 3))
	local col = ui.GEM_COLOR[ev.color] or ui.YELLOW

	ui.after(delay, function()
		audio.play("arrow")
		gui.cancel_animations(holder, "position")
		gui.set_position(holder, V3(hx, hy, 0))
		gui.animate(holder, "position.x", hx - dir * 12, gui.EASING_OUTQUAD, 0.06, 0, function()
			gui.animate(holder, "position.x", hx + dir * 8, gui.EASING_OUTBACK, 0.09, 0, function()
				gui.animate(holder, "position.x", hx, gui.EASING_OUTQUAD, 0.10)
			end)
		end)

		for k = 1, count do
			local stagger = (k - 1) * 0.045
			ui.after(stagger, function()
				local sy = hy + (k - (count + 1) / 2) * 14
				local sx = hx + dir * 26
				local ang = math.deg(math.atan2(ty - sy, tx - sx))
				local proj = ui.glow(ui.box(st.fx_layer, sprite, sx, sy, 62, 32, ui.WHITE))
				gui.set_euler(proj, V3(0, 0, ang))
				gui.animate(proj, "position", V3(tx, ty, 0), gui.EASING_LINEAR, 0.19)
				-- Glowing speed sparks along flight path
				ui.after(0.06, function() ui.spark_dot(st.fx_layer, sx + (tx - sx) * 0.35, sy + (ty - sy) * 0.35, col, 14, 0.16) end)
				ui.after(0.12, function() ui.spark_dot(st.fx_layer, sx + (tx - sx) * 0.72, sy + (ty - sy) * 0.72, col, 14, 0.16) end)
				ui.after(0.19, function()
					gui.delete_node(proj)
					if k == 1 then
						impact_on_target(is_p, ev, tx, ty)
					else
						ui.burst(st.fx_layer, tx + math.random(-14, 14), ty + math.random(-14, 14), 3, col, 36, 16)
					end
				end)
			end)
		end
	end)
end

local function animate_magic_cast(ev, is_p, home, holder, delay)
	local hx, hy = home.x, home.y
	local tx = is_p and st.e_face_x or st.p_face_x
	local ty = is_p and st.e_face_y or st.p_face_y
	local dir = is_p and 1 or -1
	local count = math.max(1, math.min(3, ev.units or 2))
	local col = ui.GEM_COLOR[ev.color] or ui.PURPLE

	ui.after(delay, function()
		audio.play("spell")
		-- Levitate + Arcane cast ring around mages
		gui.cancel_animations(holder, "position")
		gui.animate(holder, "position.y", hy + 14, gui.EASING_OUTQUAD, 0.12, 0, function()
			gui.animate(holder, "position.y", hy, gui.EASING_INQUAD, 0.16)
		end)
		ui.ring(st.fx_layer, hx, hy + 10, 108, col, 0.28)
		ui.burst(st.fx_layer, hx, hy + 16, 5, col, 38, 18)

		for k = 1, count do
			local stagger = 0.05 + (k - 1) * 0.065
			ui.after(stagger, function()
				local sy = hy + 10 + (k - (count + 1) / 2) * 16
				local sx = hx + dir * 22
				local ang = math.deg(math.atan2(ty - sy, tx - sx))
				local orb = ui.glow(ui.box(st.fx_layer, ev.fx or "proj_spell", sx, sy, 66, 48, ui.WHITE))
				gui.set_euler(orb, V3(0, 0, ang))
				gui.animate(orb, "position", V3(tx, ty, 0), gui.EASING_INOUTSINE, 0.23)
				gui.animate(orb, "size", V3(82, 58, 0), gui.EASING_OUTQUAD, 0.23)

				ui.after(0.07, function() ui.spark_dot(st.fx_layer, sx + (tx - sx) * 0.30, sy + (ty - sy) * 0.30, col, 22, 0.22) end)
				ui.after(0.15, function() ui.spark_dot(st.fx_layer, sx + (tx - sx) * 0.68, sy + (ty - sy) * 0.68, col, 24, 0.22) end)
				ui.after(0.23, function()
					gui.delete_node(orb)
					if k == 1 then
						impact_on_target(is_p, ev, tx, ty)
					else
						ui.ring(st.fx_layer, tx, ty, 90, col, 0.25)
						ui.burst(st.fx_layer, tx, ty, 4, col, 48, 20)
					end
				end)
			end)
		end
	end)
end

local function animate_board_steps(ev)
	local start_t = 0
	if ev.kind == "swap" and ev.r1 and ev.r2 then
		local n1 = st.gem_nodes[ev.r1] and st.gem_nodes[ev.r1][ev.c1]
		local n2 = st.gem_nodes[ev.r2] and st.gem_nodes[ev.r2][ev.c2]
		local x1, y1 = cell_pos(ev.r1, ev.c1)
		local x2, y2 = cell_pos(ev.r2, ev.c2)
		if n1 then gui.animate(n1, "position", V3(x2, y2, 0), gui.EASING_INOUTQUAD, 0.10) end
		if n2 then gui.animate(n2, "position", V3(x1, y1, 0), gui.EASING_INOUTQUAD, 0.10) end
		start_t = 0.10
	elseif ev.kind == "hammer" and ev.r and ev.c then
		local hx, hy = cell_pos(ev.r, ev.c)
		ui.ring(st.fx_layer, hx, hy, 128, ui.GOLD, 0.32)
		ui.burst(st.fx_layer, hx, hy, 10, ui.GOLD, 64, 24)
		ui.shake_xy(st.arena_shake, 6)
	end

	local steps = ev.steps or {}
	local step_dt = 0.12
	for idx, step in ipairs(steps) do
		local t = start_t + (idx - 1) * step_dt
		ui.after(t, function()
			audio.play("match", 0.9, 1.0 + (step.cascade - 1) * 0.16)
			if step.cascade >= 2 then
				ui.float_text(st.fx_layer, i18n.t("COMBO_FMT", { n = step.cascade }), st.board_cx, st.board_cy + 16, 30, ui.GOLD, 54)
			end
			local rep = {}
			for _, cl in ipairs(step.cleared or {}) do
				local cx, cy = cell_pos(cl.r, cl.c)
				local gcol = ui.GEM_COLOR[cl.color] or ui.WHITE
				if not rep[cl.color] then rep[cl.color] = { x = cx, y = cy } end
				if idx == 1 and st.gem_nodes[cl.r] and st.gem_nodes[cl.r][cl.c] then
					local gn = st.gem_nodes[cl.r][cl.c]
					gui.animate(gn, "scale", V3(1.25, 1.25, 1), gui.EASING_OUTQUAD, 0.08)
					gui.animate(gn, "color.w", 0, gui.EASING_INQUAD, 0.09)
				end
				ui.ring(st.fx_layer, cx, cy, 56, gcol, 0.22)
				ui.burst(st.fx_layer, cx, cy, 3, gcol, 28, 16)
			end
			-- Launch glowing energy orbs from matched gems straight into squads / commanders
			local is_p = (ev.who or "player") == "player"
			for col, pos in pairs(rep) do
				local tx, ty = is_p and st.p_face_x or st.e_face_x, is_p and st.p_face_y or st.e_face_y
				local sq_h = (col == "red" or col == "yellow" or col == "purple") and (is_p and st.p_home[col] or st.e_home[col])
				if sq_h then tx, ty = sq_h.x, sq_h.y end
				local orb = ui.glow(ui.box(st.fx_layer, "glow", pos.x, pos.y, 28, 28, ui.GEM_COLOR[col] or ui.WHITE))
				ui.fly(orb, tx, ty, 0.16, 0, function() gui.delete_node(orb) end)
			end
		end)
	end
	return start_t + math.max(1, #steps) * step_dt
end

-- ---------------------------------------------------------------- INPUT & TURN LOOP

function M.on_booster_tap(kind)
	if st.busy or st.session.status ~= "play" or st.session.turn ~= "player" then return end
	if (st.session.boosters[kind] or 0) <= 0 then
		st.app.buy_booster_ad(kind)
		return
	end
	if kind == "hammer" then
		st.hammer_mode = not st.hammer_mode
		if st.hammer_mode then
			ui.float_text(st.fx_layer, i18n.t("HAMMER_HINT"), st.board_cx, st.board_cy, 28, ui.GOLD, 40)
		end
		return
	end
	if battle.use_booster(st.session, kind) then
		M.process()
	end
end

local function bounce_invalid_swap(r1, c1, r2, c2)
	audio.play("blocked")
	local n1 = st.gem_nodes[r1] and st.gem_nodes[r1][c1]
	local n2 = st.gem_nodes[r2] and st.gem_nodes[r2][c2]
	if not (n1 and n2) then return end
	local x1, y1 = cell_pos(r1, c1)
	local x2, y2 = cell_pos(r2, c2)
	local mx1, my1 = x1 + (x2 - x1) * 0.34, y1 + (y2 - y1) * 0.34
	local mx2, my2 = x2 + (x1 - x2) * 0.34, y2 + (y1 - y2) * 0.34
	gui.animate(n1, "position", V3(mx1, my1, 0), gui.EASING_OUTQUAD, 0.06, 0, function()
		gui.animate(n1, "position", V3(x1, y1, 0), gui.EASING_OUTBACK, 0.10)
	end)
	gui.animate(n2, "position", V3(mx2, my2, 0), gui.EASING_OUTQUAD, 0.06, 0, function()
		gui.animate(n2, "position", V3(x2, y2, 0), gui.EASING_OUTBACK, 0.10)
	end)
end

function M.tap(x, y, pressed, released)
	if st.busy or st.session.status ~= "play" or st.session.turn ~= "player" then return false end
	local r, c = screen_to_cell(x, y)

	if pressed then
		if st.hammer_mode and r then
			st.hammer_mode = false
			if battle.use_booster(st.session, "hammer", r, c) then
				M.process()
				return true
			end
			return false
		end
		if r then
			st.drag = { r = r, c = c, x = x, y = y }
			audio.play("tap")
			return false
		end
	end

	if released and st.drag then
		local d = st.drag
		st.drag = nil
		local dx, dy = x - d.x, y - d.y
		if math.abs(dx) >= 24 or math.abs(dy) >= 24 then
			local nr, nc = d.r, d.c
			if math.abs(dx) > math.abs(dy) then
				nc = nc + (dx > 0 and 1 or -1)
			else
				nr = nr + (dy > 0 and 1 or -1)
			end
			st.sel = nil
			gui.set_visible(st.sel_ring, false)
			if battle.player_swap(st.session, d.r, d.c, nr, nc) then
				M.process()
				return true
			else
				bounce_invalid_swap(d.r, d.c, nr, nc)
			end
			return false
		end
		if r and c then
			if not st.sel then
				st.sel = { r = r, c = c }
				local gx, gy = cell_pos(r, c)
				gui.set_position(st.sel_ring, V3(gx, gy, 0))
				gui.set_visible(st.sel_ring, true)
			elseif st.sel.r == r and st.sel.c == c then
				st.sel = nil
				gui.set_visible(st.sel_ring, false)
			elseif math.abs(st.sel.r - r) + math.abs(st.sel.c - c) == 1 then
				local sr, sc = st.sel.r, st.sel.c
				st.sel = nil
				gui.set_visible(st.sel_ring, false)
				if battle.player_swap(st.session, sr, sc, r, c) then
					M.process()
					return true
				else
					bounce_invalid_swap(sr, sc, r, c)
				end
			else
				st.sel = { r = r, c = c }
				local gx, gy = cell_pos(r, c)
				gui.set_position(st.sel_ring, V3(gx, gy, 0))
			end
		end
	end
	return false
end

function M.process()
	local evs = st.session.events
	if #evs == 0 then return end
	if st.tut_node then gui.delete_node(st.tut_node); st.tut_node = nil end

	local board_dur = 0
	local had_board_change = false
	for _, ev in ipairs(evs) do
		if ev.kind == "swap" or ev.kind == "hammer" or ev.kind == "shuffle" then
			had_board_change = true
			board_dur = math.max(board_dur, animate_board_steps(ev))
		end
	end

	local atk_idx = 0
	local atk_base = had_board_change and 0.18 or 0.02
	local max_fx_end = board_dur

	local function dispatch_strike(ev, delay, extra_banner)
		local is_p = ev.who == "player"
		local holder = is_p and st.p_squads[ev.color] or st.e_squads[ev.color]
		local vis = is_p and st.p_vis[ev.color] or st.e_vis[ev.color]
		local home = is_p and st.p_home[ev.color] or st.e_home[ev.color]
		if extra_banner and home then
			ui.after(delay, function()
				ui.ring(st.fx_layer, home.x, home.y, 116, ui.GEM_COLOR[ev.color] or ui.GOLD, 0.35)
				ui.float_text(st.fx_layer, extra_banner, home.x, home.y + 38, 22, ui.GOLD, 46)
			end)
		end
		if ev.style == "ranged" then
			animate_ranged_volley(ev, is_p, home, holder, delay)
			return delay + 0.34
		elseif ev.style == "magic" then
			animate_magic_cast(ev, is_p, home, holder, delay)
			return delay + 0.38
		else
			animate_melee_dash(ev, is_p, home, holder, vis, delay)
			return delay + 0.40
		end
	end

	for _, ev in ipairs(evs) do
		if ev.kind == "attack" then
			atk_idx = atk_idx + 1
			local delay = atk_base + math.min(3, atk_idx - 1) * 0.14
			max_fx_end = math.max(max_fx_end, dispatch_strike(ev, delay, nil))
		elseif ev.kind == "skill" then
			atk_idx = atk_idx + 1
			local delay = atk_base + 0.08 + math.min(3, atk_idx - 1) * 0.14
			ev.crit = true
			local banner = i18n.t("SKILL_TAG") .. " " .. i18n.t("SK_" .. ev.skill_id)
			max_fx_end = math.max(max_fx_end, dispatch_strike(ev, delay, banner))
		elseif ev.kind == "rune" then
			local is_p = ev.who == "player"
			local hm = is_p and st.p_home[ev.color] or st.e_home[ev.color]
			if hm then
				ui.after(atk_base, function()
					local rx = hm.x + (ev.slot == 1 and -12 or 12)
					local ry = hm.y - (st.sq_size or 96) * 0.44
					ui.burst(st.fx_layer, rx, ry, 4, ui.GEM_COLOR[ev.rune_color] or ui.GOLD, 28, 16)
				end)
			end
		elseif ev.kind == "dot" then
			ui.after(0.08, function()
				local fx = ev.who == "player" and st.p_face_x or st.e_face_x
				local fy = ev.who == "player" and st.p_face_y or st.e_face_y
				local col = ev.dtype == "poison" and ui.GREEN or ui.RED
				local tag = i18n.t(ev.dtype == "poison" and "POISON_TAG" or "BURN_TAG") .. " -" .. ev.dmg
				ui.ring(st.fx_layer, fx, fy, 96, col, 0.30)
				ui.float_text(st.fx_layer, tag, fx, fy + 34, 22, col, 50)
			end)
		elseif ev.kind == "frozen" then
			ui.after(0.12, function()
				local fx = ev.who == "player" and st.p_face_x or st.e_face_x
				local fy = ev.who == "player" and st.p_face_y or st.e_face_y
				ui.ring(st.fx_layer, fx, fy, 128, ui.DIAMOND, 0.45)
				ui.float_text(st.fx_layer, i18n.t("FREEZE_TAG"), fx, fy + 36, 26, ui.DIAMOND, 52)
			end)
		elseif ev.kind == "heal" then
			local delay = atk_base
			max_fx_end = math.max(max_fx_end, delay + 0.25)
			ui.after(delay, function()
				audio.play("heal")
				local face = ev.who == "player" and st.p_face_node or st.e_face_node
				local fx = ev.who == "player" and st.p_face_x or st.e_face_x
				local fy = ev.who == "player" and st.p_face_y or st.e_face_y
				ui.flash_hit(face, ui.GREEN)
				ui.ring(st.fx_layer, fx, fy, 114, ui.GREEN, 0.36)
				ui.burst(st.fx_layer, fx, fy, 8, ui.GREEN, 54, 22)
				ui.float_text(st.fx_layer, "+" .. ev.amount, fx, fy + 34, 26, ui.GREEN, 54)
			end)
		elseif ev.kind == "shield" then
			local delay = atk_base
			max_fx_end = math.max(max_fx_end, delay + 0.25)
			ui.after(delay, function()
				audio.play("shield")
				local fx = ev.who == "player" and st.p_face_x or st.e_face_x
				local fy = ev.who == "player" and st.p_face_y or st.e_face_y
				ui.ring(st.fx_layer, fx, fy, 122, ui.BLUE, 0.38)
				ui.burst(st.fx_layer, fx, fy, 6, ui.BLUE, 44, 18)
				local sh_ic = ui.box(st.fx_layer, "icon_shield", fx, fy + 4, 48, 48, ui.BLUE)
				ui.pop(sh_ic, 0.5, 1.25, 0.22)
				gui.animate(sh_ic, "color.w", 0, gui.EASING_INQUAD, 0.25, 0.16, function() gui.delete_node(sh_ic) end)
				ui.float_text(st.fx_layer, "+" .. ev.amount, fx, fy + 32, 24, ui.BLUE, 48)
			end)
		elseif ev.kind == "win" then
			ui.after(math.max(0.75, max_fx_end + 0.15), function()
				audio.play("win")
				st.app.on_battle_end(true)
			end)
		elseif ev.kind == "lose" then
			ui.after(math.max(0.75, max_fx_end + 0.15), function()
				audio.play("lose")
				st.app.on_battle_end(false)
			end)
		end
	end
	st.session.events = {}

	if had_board_change then
		st.busy = true
		ui.after(math.max(0.16, board_dur), function()
			rebuild_gems(st.cell * 0.48)
			refresh_fighters()
		end)
		ui.after(math.max(0.38, max_fx_end), function()
			st.busy = false
			refresh_fighters()
			show_tutorial_hand()
		end)
	else
		refresh_fighters()
		show_tutorial_hand()
	end
end

function M.update(dt)
	local s = st.session
	if not (s and s.status == "play") then return end
	if st.busy then return end
	if s.turn == "enemy" then
		st.ai_timer = st.ai_timer + dt
		if st.ai_timer >= 0.65 then
			st.ai_timer = 0
			battle.step_enemy(s)
			M.process()
		end
	else
		st.ai_timer = 0
	end
end

return M
