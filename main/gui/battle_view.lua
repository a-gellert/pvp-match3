-- Battle Screen: Portrait (Arena top, Commanders corners, Board middle, Boosters bottom)
-- and Landscape (Arena+Commanders+Boosters left, Board right).
local ui = require "main.gui.ui"
local config = require "main.modules.config"
local battle = require "main.modules.battle"
local board = require "main.modules.board"
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
	local x = st.board_x0 + (c - 0.5) * st.cell
	local y = st.board_y0 + (r - 0.5) * st.cell
	return x, y
end

local function screen_to_cell(x, y)
	local c = math.floor((x - st.board_x0) / st.cell) + 1
	local r = math.floor((y - st.board_y0) / st.cell) + 1
	if r >= 1 and r <= config.GRID and c >= 1 and c <= config.GRID then
		return r, c
	end
end

local function make_gem_node(r, c, gem)
	if not gem then return nil end
	local x, y = cell_pos(r, c)
	local gs = st.cell * 0.84
	local n = ui.box(st.gem_layer, GEM_SPRITE[gem.color] or "gem_red", x, y, gs, gs)
	if gem.special and SPEC_SPRITE[gem.special] then
		ui.box(n, SPEC_SPRITE[gem.special], 0, 0, gs * 0.92, gs * 0.92)
	end
	return n
end

local function rebuild_gems()
	if st.gem_layer then gui.delete_node(st.gem_layer) end
	st.gem_layer = ui.pane(st.root, 0, 0)
	st.gem_nodes = {}
	local g = st.session.board.grid
	for r = 1, config.GRID do
		st.gem_nodes[r] = {}
		for c = 1, config.GRID do
			st.gem_nodes[r][c] = make_gem_node(r, c, g[r][c])
		end
	end
end

local function refresh_fighters()
	local s = st.session
	if not (s and st.hud_layer) then return end
	gui.delete_node(st.hud_layer)
	st.hud_layer = ui.pane(st.root, 0, 0)

	-- Turn banner
	local is_p = s.turn == "player"
	ui.slice(st.hud_layer, is_p and "btn_gold" or "btn_crimson", st.turn_x, st.turn_y, 200, 44, ui.WHITE, 16)
	local t_lbl = ui.text(st.hud_layer, i18n.t(is_p and "YOUR_TURN" or "ENEMY_TURN"), st.turn_x, st.turn_y + 1, 20, ui.WHITE)
	ui.fit(t_lbl, 180, 20)

	-- Player HP + Shield + Move Orbs (1..7)
	ui.hp_bar(st.hud_layer, st.p_bar_x, st.p_bar_y, st.bar_w, 28, s.player.hp, s.player.max_hp, s.player.shield, ui.GREEN)
	for i = 1, s.player.max_moves do
		local active = is_p and i <= s.player.moves_left
		local ox = st.p_orbs_x + (i - 1) * 26
		ui.box(st.hud_layer, "icon_move_orb", ox, st.p_orbs_y, 22, 22, active and ui.WHITE or vmath.vector4(0.3, 0.35, 0.45, 0.45))
	end

	-- Enemy HP + Shield + Move Orbs
	ui.hp_bar(st.hud_layer, st.e_bar_x, st.e_bar_y, st.bar_w, 28, s.enemy.hp, s.enemy.max_hp, s.enemy.shield, ui.RED)
	for i = 1, s.enemy.max_moves do
		local active = (not is_p) and i <= s.enemy.moves_left
		local ox = st.e_orbs_x - (i - 1) * 26
		ui.box(st.hud_layer, "icon_move_orb", ox, st.e_orbs_y, 22, 22, active and ui.RED or vmath.vector4(0.35, 0.25, 0.3, 0.45))
	end

	-- Booster counts
	for _, kind in ipairs({ "shuffle", "hammer", "extra_move" }) do
		local cnt = s.boosters[kind] or 0
		local bx, by = st.boost_pos[kind].x, st.boost_pos[kind].y
		if cnt > 0 then
			ui.text(st.hud_layer, "x" .. cnt, bx + 54, by + 16, 17, ui.GOLD)
		else
			ui.box(st.hud_layer, "icon_ad", bx + 54, by + 16, 24, 18)
		end
	end
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
		p_squad_nodes = {},
		e_squad_nodes = {},
		boost_pos = {},
	}
	local vw, vh = app.vw, app.vh
	local is_land = app.orient == "landscape"

	-- Background ambient slate frame
	ui.box(st.root, "square", vw / 2, vh / 2, vw, vh, ui.BG_DARK)

	local s = st.session
	local arena_cx, arena_cy, arena_w, arena_h

	if is_land then
		-- Landscape: Field RIGHT, Arena & Enemy/Player LEFT
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
		-- Portrait (matches user sketch): Boosters bottom, Field middle, Commanders at corners above field, Squads top!
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

	-- Top HUD: Pause + Stage label
	ui.btn(st.root, "btn_round", 46, vh - 46, 62, 62, "", 20, function() app.pause() end)
	ui.box(st.root, "icon_pause", 46, vh - 46, 30, 30)
	local stage_str = s.mode == "pvp" and (s.enemy.name ~= "" and s.enemy.name or i18n.t("PVP"))
		or i18n.t("STAGE_FMT", { n = s.stage_id })
	local stg_lbl = ui.text(st.root, stage_str, is_land and (arena_cx - 80) or (vw / 2 - 40), vh - 46, 26, ui.BONE)
	ui.fit(stg_lbl, 260, 26)

	-- Arena backdrop + Player 3 Squads (left) vs Enemy 3 Squads (right)
	ui.slice(st.root, "panel_dark", arena_cx, arena_cy, arena_w, arena_h, ui.WHITE, 20)
	local p_offsets = {
		red    = { x = -arena_w * 0.24, y = arena_h * 0.16 },
		yellow = { x = -arena_w * 0.36, y = -arena_h * 0.14 },
		purple = { x = -arena_w * 0.18, y = -arena_h * 0.18 },
	}
	local e_offsets = {
		red    = { x = arena_w * 0.24, y = arena_h * 0.16 },
		yellow = { x = arena_w * 0.36, y = -arena_h * 0.14 },
		purple = { x = arena_w * 0.18, y = -arena_h * 0.18 },
	}
	local sq_size = math.min(120, arena_h * 0.48)
	for _, col in ipairs(config.ATTACK_COLORS) do
		local po, eo = p_offsets[col], e_offsets[col]
		local pn = ui.icon(st.root, s.player.squads[col].sprite, arena_cx + po.x, arena_cy + po.y, sq_size)
		st.p_squad_nodes[col] = pn
		local en = ui.icon(st.root, s.enemy.squads[col].sprite, arena_cx + eo.x, arena_cy + eo.y, sq_size)
		gui.set_scale(en, V3(-1, 1, 1))
		st.e_squad_nodes[col] = en
	end

	-- Commander Face Icons at left/right corners just above the board
	st.p_face_node = ui.box(st.root, s.player.face, st.p_face_x, st.p_face_y, 88, 88)
	st.e_face_node = ui.box(st.root, s.enemy.face, st.e_face_x, st.e_face_y, 88, 88)
	local e_name = s.enemy.name_key and i18n.t(s.enemy.name_key) or s.enemy.name
	local e_lbl = ui.text(st.root, e_name, st.e_bar_x, st.e_face_y + 38, 18, ui.DIM)
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

	-- Boosters bar (bottom)
	local b_list = { "shuffle", "hammer", "extra_move" }
	local b_w = 175
	local b_gap = 192
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
	st.fx_layer = ui.pane(st.root, 0, 0)
	rebuild_gems()
	refresh_fighters()
	show_tutorial_hand()
end

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
				audio.play("blocked")
			end
			return false
		end
		-- Two-tap selection support (desktop/casual click)
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
					audio.play("blocked")
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

local function spawn_projectile(from_x, from_y, to_x, to_y, col)
	local orb = ui.glow(ui.box(st.fx_layer, "glow", from_x, from_y, 38, 38, col))
	ui.fly(orb, to_x, to_y, 0.28, 0, function()
		ui.burst(st.fx_layer, to_x, to_y, 6, col, 48, 20)
		gui.delete_node(orb)
	end)
end

function M.process()
	local evs = st.session.events
	if #evs == 0 then return end
	if st.tut_node then gui.delete_node(st.tut_node); st.tut_node = nil end

	local had_board_change = false
	for _, ev in ipairs(evs) do
		if ev.kind == "swap" or ev.kind == "hammer" or ev.kind == "shuffle" then
			had_board_change = true
		elseif ev.kind == "attack" then
			audio.play("hit")
			local is_p = ev.who == "player"
			local sq_node = is_p and st.p_squad_nodes[ev.color] or st.e_squad_nodes[ev.color]
			local target_face = is_p and st.e_face_node or st.p_face_node
			local fx, fy = st.board_cx, st.board_cy
			if sq_node then
				local sp = gui.get_position(sq_node)
				fx, fy = sp.x, sp.y
				ui.pop(sq_node, 1.22, 1.0, 0.22)
			end
			local tp = gui.get_position(target_face)
			spawn_projectile(fx, fy, tp.x, tp.y, ui.GEM_COLOR[ev.color])
			ui.shake(target_face, is_p and -12 or 12)
			local label = "-" .. ev.dmg .. (ev.crit and "!" or "")
			ui.float_text(st.fx_layer, label, tp.x, tp.y + 30, ev.crit and 32 or 26, ui.GEM_COLOR[ev.color], 56)
		elseif ev.kind == "heal" then
			audio.play("heal")
			local face = ev.who == "player" and st.p_face_node or st.e_face_node
			local tp = gui.get_position(face)
			ui.burst(st.fx_layer, tp.x, tp.y, 7, ui.GREEN, 50, 22)
			ui.float_text(st.fx_layer, "+" .. ev.amount, tp.x, tp.y + 30, 26, ui.GREEN, 52)
		elseif ev.kind == "shield" then
			audio.play("shield")
			local face = ev.who == "player" and st.p_face_node or st.e_face_node
			local tp = gui.get_position(face)
			ui.ring(st.fx_layer, tp.x, tp.y, 110, ui.BLUE, 0.35)
			ui.float_text(st.fx_layer, "+" .. ev.amount, tp.x, tp.y + 24, 24, ui.BLUE, 46)
		elseif ev.kind == "win" then
			audio.play("win")
			ui.after(0.55, function() st.app.on_battle_end(true) end)
		elseif ev.kind == "lose" then
			audio.play("lose")
			ui.after(0.55, function() st.app.on_battle_end(false) end)
		end
	end
	st.session.events = {}

	if had_board_change then
		audio.play("match")
		st.busy = true
		rebuild_gems()
		-- Subtle pop-in for fresh grid feeling snappy without heavy physics
		ui.after(0.22, function()
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
