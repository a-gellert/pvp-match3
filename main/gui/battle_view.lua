-- Battle screen: dark-fantasy arena (squads, commanders, HP bars) + 7x7 Match-3 board.
-- Board input goes through a Druid drag component; every cascade step is animated
-- (clear -> specials -> gravity -> refill) and combat FX are synced to the step that caused them.
local ui = require "main.gui.ui"
local config = require "main.modules.config"
local battle = require "main.modules.battle"
local campaign = require "main.modules.campaign"
local i18n = require "main.modules.i18n"
local audio = require "main.modules.audio"
local poki = require "main.modules.poki"

local M = {}
local V3 = vmath.vector3
local V4 = vmath.vector4
local N = config.GRID

local SPEC_SPRITE = { line_h = "spec_line_h", line_v = "spec_line_v", bomb = "spec_bomb" }
local STEP_DUR = 0.36
local HINT_DELAY = 5.5

local st = {}

-- ---------------------------------------------------------------- helpers
local function cell_pos(r, c)
	return st.board_x0 + (c - 0.5) * st.cell, st.board_y0 + (r - 0.5) * st.cell
end

local function screen_to_cell(x, y)
	local c = math.floor((x - st.board_x0) / st.cell) + 1
	local r = math.floor((y - st.board_y0) / st.cell) + 1
	if r >= 1 and r <= N and c >= 1 and c <= N then return r, c end
end

local function side_of(who) return who == "player" and "player" or "enemy" end
local function other(who) return who == "player" and "enemy" or "player" end

local function face_pos(who)
	if who == "player" then return st.p_face_x, st.p_face_y end
	return st.e_face_x, st.e_face_y
end

local function at(t, fn)
	if t <= 0.001 then fn() else ui.after(t, fn) end
end

-- ---------------------------------------------------------------- gems
local function make_gem(r, c, gem, start_y)
	if not gem then return nil end
	local x, y = cell_pos(r, c)
	local gs = st.cell * 0.88
	local n = ui.box(st.gem_layer, ui.GEM_SPRITE[gem.color] or "gem_red", x, start_y or y, gs, gs)
	if gem.special and SPEC_SPRITE[gem.special] then
		local sp = ui.glow(ui.box(n, SPEC_SPRITE[gem.special], 0, 0, gs * 0.9, gs * 0.9, V4(1, 1, 1, 0.95)))
		ui.pulse(sp, 1.12, 0.55)
	elseif gem.special == "prism" then
		ui.spin(n, 6)
		local gl = ui.glow(ui.box(n, "glow", 0, 0, gs * 1.4, gs * 1.4, V4(1, 1, 1, 0.35)))
		ui.pulse(gl, 1.15, 0.6)
	end
	return { node = n, color = gem.color, special = gem.special }
end

local function kill_gem(g, delay)
	if not g then return end
	local n = g.node
	gui.animate(n, "scale", V3(1.35, 1.35, 1), gui.EASING_OUTQUAD, 0.1, delay or 0)
	gui.animate(n, "color.w", 0, gui.EASING_INQUAD, 0.12, delay or 0, function() gui.delete_node(n) end)
end

local function rebuild_gems(pop)
	if st.gem_layer then gui.delete_node(st.gem_layer) end
	st.gem_layer = ui.pane(st.clip, -st.board_cx, -st.board_cy)
	st.gems = {}
	local g = st.session.board.grid
	for r = 1, N do
		st.gems[r] = {}
		for c = 1, N do
			st.gems[r][c] = make_gem(r, c, g[r][c])
			if pop and st.gems[r][c] then ui.pop(st.gems[r][c].node, 0.1, 1, 0.3, (r + c) * 0.018) end
		end
	end
end

-- Make the displayed gems match the logic board exactly (after cascades / shuffles).
local function sync_board()
	local g = st.session.board.grid
	for r = 1, N do
		for c = 1, N do
			local want = g[r][c]
			local have = st.gems[r][c]
			local x, y = cell_pos(r, c)
			if not want then
				if have then gui.delete_node(have.node); st.gems[r][c] = nil end
			elseif not have or have.color ~= want.color or have.special ~= want.special then
				if have then gui.delete_node(have.node) end
				st.gems[r][c] = make_gem(r, c, want)
			else
				gui.cancel_animations(have.node, "position")
				gui.set_position(have.node, V3(x, y, 0))
				gui.set_scale(have.node, V3(1, 1, 1))
			end
		end
	end
end

local function clear_hint()
	st.idle = 0
	if st.hint_nodes then
		for _, g in ipairs(st.hint_nodes) do
			if g.node then
				gui.cancel_animations(g.node, "scale")
				gui.set_scale(g.node, V3(1, 1, 1))
			end
		end
		st.hint_nodes = nil
	end
	if st.hint_hand then gui.delete_node(st.hint_hand); st.hint_hand = nil end
end

local function show_hint()
	local s = st.session
	local m = battle.suggest_move(s)
	if not m then return end
	local a, b = st.gems[m.r1][m.c1], st.gems[m.r2][m.c2]
	if not (a and b) then return end
	st.hint_nodes = { a, b }
	for _, g in ipairs(st.hint_nodes) do
		gui.animate(g.node, "scale", V3(1.16, 1.16, 1), gui.EASING_INOUTSINE, 0.45, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
	end
	local x1, y1 = cell_pos(m.r1, m.c1)
	local x2, y2 = cell_pos(m.r2, m.c2)
	st.hint_hand = ui.box(st.fx_layer, "icon_hand", x1 + 16, y1 - 22, 58, 58)
	gui.animate(st.hint_hand, "position", V3(x2 + 16, y2 - 22, 0), gui.EASING_INOUTSINE, 0.8, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
end

-- ---------------------------------------------------------------- HUD
local function set_bars(instant)
	local s = st.session
	for _, side in ipairs({ "player", "enemy" }) do
		local f, d, b = s[side], st.disp[side], st.bars[side]
		d.hp = math.max(0, math.min(f.max_hp, d.hp))
		d.shield = math.max(0, d.shield)
		b.hp.to(d.hp / f.max_hp, instant)
		-- Shield value lives inside the HP label so nothing spills between the two bars
		b.hp.text(math.floor(d.hp) .. " / " .. f.max_hp .. (d.shield >= 1 and ("  +" .. math.floor(d.shield)) or ""))
		b.sh.to(math.min(1, d.shield / f.max_hp), instant)
		gui.set_enabled(b.sh_icon, d.shield >= 1)
	end
	-- Low HP warning vignette
	local low = st.disp.player.hp / s.player.max_hp < 0.25 and s.status == "play"
	if low ~= st.low_hp then
		st.low_hp = low
		gui.cancel_animations(st.danger, "color.w")
		if low then
			gui.set_alpha(st.danger, 0.15)
			gui.animate(st.danger, "color.w", 0.55, gui.EASING_INOUTSINE, 0.6, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
		else
			gui.animate(st.danger, "color.w", 0, gui.EASING_OUTQUAD, 0.3)
		end
	end
end

local function sync_disp()
	local s = st.session
	for _, side in ipairs({ "player", "enemy" }) do
		st.disp[side].hp = s[side].hp
		st.disp[side].shield = s[side].shield
	end
	set_bars(false)
end

function M.refresh_hud()
	local s = st.session
	if not (s and st.hud) then return end
	gui.delete_node(st.hud)
	st.hud = ui.pane(st.root, 0, 0)
	local is_p = s.turn == "player"

	-- Turn pill
	gui.play_flipbook(st.turn_pill, is_p and "btn_gold" or "btn_crimson")
	gui.set_text(st.turn_lbl, i18n.t(is_p and "YOUR_TURN" or "ENEMY_TURN"))
	ui.fit(st.turn_lbl, st.turn_w - 24, 22)

	-- Fury indicator
	if s.turn_num >= config.FURY_TURN then
		local pct = math.floor(0.2 * (s.turn_num - config.FURY_TURN + 1) * 100 + 0.5)
		local fl = ui.text(st.hud, i18n.t("FURY_FMT", { n = pct }), st.fury_x, st.fury_y, 18, ui.RED)
		ui.pulse(fl, 1.08, 0.4)
	end

	-- Moves orbs
	for _, side in ipairs({ "player", "enemy" }) do
		local f = s[side]
		local active_side = (side == "player") == is_p
		local total = math.max(f.max_moves, f.moves_left)
		local ox, oy = st.orbs[side].x, st.orbs[side].y
		local dir = side == "player" and 1 or -1
		local step = math.min(26, st.bar_w / math.max(1, total))
		for i = 1, total do
			local on = active_side and i <= f.moves_left
			local col = side == "player" and ui.WHITE or ui.RED
			local o = ui.box(st.hud, "icon_move_orb", ox + dir * (i - 1) * step, oy, 22, 22, on and col or V4(0.3, 0.35, 0.45, 0.45))
			if on and i == f.moves_left then ui.pulse(o, 1.15, 0.4) end
		end
	end

	-- Booster counts
	for _, kind in ipairs(config.BOOSTER_ORDER) do
		local cnt = s.boosters[kind] or 0
		local p = st.boost_pos[kind]
		if cnt > 0 then
			local bg = ui.box(st.hud, "badge_dot", p.x + p.w / 2 - 12, p.y + p.h / 2 - 8, 34, 34, ui.hex("#2b6bd6"))
			ui.text(bg, tostring(cnt), 0, 1, 20, ui.WHITE)
		else
			ui.box(st.hud, "icon_ad", p.x + p.w / 2 - 14, p.y + p.h / 2 - 8, 30, 24)
		end
	end
	if st.hammer_mode then
		local p = st.boost_pos.hammer
		local gl = ui.glow(ui.slice(st.hud, "tab_active", p.x, p.y, p.w + 10, p.h + 10, ui.GOLD, 18))
		ui.pulse(gl, 1.04, 0.35)
	end

	-- Rune gauges under each squad
	local ry_off = st.sq_size * 0.46
	for _, side in ipairs({ { sqs = s.player.squads, homes = st.p_home }, { sqs = s.enemy.squads, homes = st.e_home } }) do
		for _, col in ipairs(config.ATTACK_COLORS) do
			local sq, hm = side.sqs[col], side.homes[col]
			if sq and hm and sq.runes then
				for slot = 1, 2 do
					local rcol = sq.runes[slot]
					local filled = sq.rune_filled and sq.rune_filled[slot]
					local rx, ry = hm.x + (slot == 1 and -13 or 13), hm.y - ry_off
					ui.box(st.hud, "rune_bg", rx, ry, 22, 22)
					if filled then
						local gl = ui.glow(ui.box(st.hud, "glow", rx, ry, 30, 30, ui.GEM_COLOR[rcol] or ui.WHITE))
						ui.pulse(gl, 1.2, 0.5)
					end
					local gc = ui.box(st.hud, ui.GEM_SPRITE[rcol] or "gem_red", rx, ry, filled and 17 or 13, filled and 17 or 13)
					if not filled then gui.set_alpha(gc, 0.4) end
				end
			end
		end
	end

	-- Statuses next to faces
	local function statuses(sts, fx, fy, dir)
		if not sts then return end
		local sx = fx
		for _, key in ipairs({ "burn", "poison" }) do
			if sts[key] then
				local ic = ui.box(st.hud, "icon_" .. key, sx, fy, 26, 26)
				ui.pulse(ic, 1.12, 0.5)
				ui.text(st.hud, sts[key].turns .. "", sx + 14, fy - 10, 14, ui.WHITE)
				sx = sx + dir * 32
			end
		end
		if (sts.freeze or 0) > 0 then ui.box(st.hud, "icon_freeze", sx, fy, 26, 26) end
	end
	statuses(s.player.statuses, st.p_face_x + st.face_size * 0.42, st.p_face_y + st.face_size * 0.42, 1)
	statuses(s.enemy.statuses, st.e_face_x - st.face_size * 0.42, st.e_face_y + st.face_size * 0.42, -1)
end

-- ---------------------------------------------------------------- tutorial
local function show_tutorial()
	if st.tut_node then gui.delete_node(st.tut_node); st.tut_node = nil end
	local s = st.session
	if not (s and s.tutorial and s.turn == "player" and s.status == "play" and s.tutorial_step <= 3) then return end
	st.tut_node = ui.pane(st.root, 0, 0)
	local key = ({ "TUT_MATCH", "TUT_COLORS", "TUT_SUPPORT" })[s.tutorial_step] or "TUT_MATCH"
	local pw = math.min(st.arena_w - 30, 620)
	local pill = ui.slice(st.tut_node, "panel_dark", st.arena_cx, st.arena_cy - st.arena_h / 2 + 36, pw, 52, ui.WHITE, 16)
	ui.label(pill, i18n.t(key), 0, 2, 21, ui.GOLD, pw - 24)
	ui.pop(pill, 0.6, 1, 0.3)
	if s.tutorial_step <= 2 then show_hint() end
end

-- ---------------------------------------------------------------- squads & arena
local function spawn_squad(parent, sprite, x, y, size, flip_x, phase)
	local holder = ui.pane(parent, x, y)
	local sh = ui.box(holder, "glow", 0, -size * 0.36, size * 0.9, size * 0.26, V4(0, 0, 0, 0.5))
	gui.set_alpha(sh, 0.5)
	local vis = ui.icon(holder, sprite, 0, 0, size)
	if flip_x then gui.set_scale(vis, V3(-1, 1, 1)) end
	gui.animate(vis, "position.y", 4, gui.EASING_INOUTSINE, 1.15, phase, nil, gui.PLAYBACK_LOOP_PINGPONG)
	return holder, vis, { x = x, y = y }
end

local function make_bar(side, x, y, w)
	local f = st.session[side]
	local col = side == "player" and ui.GREEN or ui.RED
	local hp = ui.bar(st.root, x, y, w, 30, f.hp / f.max_hp, col, { ghost = true, text = f.hp .. " / " .. f.max_hp, text_size = 19 })
	local sh = ui.bar(st.root, x + 10, y - 21, w - 20, 10, 0, ui.BLUE)
	gui.set_alpha(sh.bg, 0.85)
	-- Small shield icon at the inner-left start of the shield bar (inside the bar's own width)
	local icon = ui.box(st.root, "icon_shield", x - w / 2 + 6, y - 21, 20, 20)
	return { hp = hp, sh = sh, sh_icon = icon }
end

-- ---------------------------------------------------------------- build
function M.build(app, parent)
	local s = app.session
	st = {
		app = app, session = s, root = ui.pane(parent, 0, 0), busy = false, ai_timer = 0, idle = 0,
		hammer_mode = false, sel = nil, drag = nil,
		p_squads = {}, e_squads = {}, p_vis = {}, e_vis = {}, p_home = {}, e_home = {},
		boost_pos = {}, bars = {}, orbs = {},
		disp = { player = { hp = s.player.hp, shield = s.player.shield }, enemy = { hp = s.enemy.hp, shield = s.enemy.shield } },
	}
	local vw, vh = app.vw, app.vh
	local is_land = app.orient == "landscape"

	-- Theme tint: campaign biome or PvP league colour
	local tint_hex = s.mode == "campaign" and campaign.biome(s.stage_id).tint or "#c9d6ee"
	local tint = ui.hex(tint_hex)
	ui.background(st.root, vw, vh, tint, true)

	local arena_cx, arena_cy, arena_w, arena_h
	local cx0, cx1
	if is_land then
		local comp_w = math.min(vw - 60, 1700)
		cx0 = (vw - comp_w) / 2
		cx1 = cx0 + comp_w
		local bs = math.min(vh - 56, 860)
		st.cell = math.floor((bs - 26) / N)
		st.board_size = st.cell * N
		st.board_cx = cx1 - st.board_size / 2 - 13
		st.board_cy = vh / 2
		st.board_x0 = st.board_cx - st.board_size / 2
		st.board_y0 = st.board_cy - st.board_size / 2
		local lx0, lx1 = cx0, st.board_x0 - 52
		local lw = lx1 - lx0
		local lcx = (lx0 + lx1) / 2
		st.top_y = vh - 50
		st.boost_y = 74
		st.hud_y = 196
		arena_cx, arena_w = lcx, lw
		arena_cy = (st.hud_y + 70 + st.top_y - 46) / 2
		arena_h = (st.top_y - 46) - (st.hud_y + 70)
		cx0, cx1 = lx0, lx1
	else
		local comp_w = math.min(vw - 24, 780)
		cx0 = (vw - comp_w) / 2
		cx1 = cx0 + comp_w
		local bs = math.min(comp_w - 10, 700)
		st.cell = math.floor((bs - 26) / N)
		st.board_size = st.cell * N
		st.board_cx = vw / 2
		st.board_y0 = 140
		st.board_x0 = st.board_cx - st.board_size / 2
		st.board_cy = st.board_y0 + st.board_size / 2
		st.top_y = vh - 52
		st.boost_y = 66
		st.hud_y = st.board_y0 + st.board_size + 72
		local arena_bot = st.hud_y + 66
		local arena_top = st.top_y - 44
		arena_cx, arena_w = vw / 2, comp_w
		arena_h = math.max(200, arena_top - arena_bot)
		arena_cy = arena_bot + arena_h / 2
	end
	st.arena_cx, st.arena_cy, st.arena_w, st.arena_h = arena_cx, arena_cy, arena_w, arena_h

	-- Top bar
	ui.btn(st.root, "btn_round", cx0 + 40, st.top_y, 64, 64, "", 20, function() app.pause() end, { icon = "icon_pause", icon_size = 30 })
	local stage_str = s.mode == "pvp" and i18n.t("PVP")
		or (i18n.t("STAGE_FMT", { n = s.stage_id }) .. (campaign.get_stage(s.stage_id).boss and ("  " .. i18n.t("BOSS")) or ""))
	ui.label(st.root, stage_str, (cx0 + cx1) / 2 - 20, st.top_y + 2, 28, ui.BONE, (cx1 - cx0) - 360)
	st.turn_w = 210
	st.turn_pill = ui.slice(st.root, "btn_gold", cx1 - st.turn_w / 2 - 4, st.top_y, st.turn_w, 50, ui.WHITE, 16)
	st.turn_lbl = ui.text(st.turn_pill, "", 0, 3, 22, ui.WHITE)
	st.fury_x, st.fury_y = cx1 - st.turn_w / 2 - 4, st.top_y - 40

	-- Arena
	st.shake = ui.pane(st.root, 0, 0)
	ui.slice(st.shake, "panel_dark", arena_cx, arena_cy, arena_w, arena_h, ui.WHITE, 20)
	ui.box(st.shake, "arena_bg", arena_cx, arena_cy, arena_w - 14, arena_h - 14, V4(0.55 + tint.x * 0.45, 0.55 + tint.y * 0.45, 0.55 + tint.z * 0.45, 1))
	ui.box(st.shake, "vignette", arena_cx, arena_cy, arena_w - 14, arena_h - 14, V4(1, 1, 1, 0.7))

	local sq_size = math.min(144, arena_h * 0.4, arena_w * 0.21)
	st.sq_size = sq_size
	local offs = {
		red    = { x = 0.22, y = 0.15 },
		yellow = { x = 0.37, y = -0.10 },
		purple = { x = 0.17, y = -0.20 },
	}
	for i, col in ipairs(config.ATTACK_COLORS) do
		local o = offs[col]
		local px, py = arena_cx - arena_w * o.x, arena_cy + arena_h * o.y
		local ex = arena_cx + arena_w * o.x
		st.p_squads[col], st.p_vis[col], st.p_home[col] = spawn_squad(st.shake, s.player.squads[col].sprite, px, py, sq_size, false, i * 0.25)
		st.e_squads[col], st.e_vis[col], st.e_home[col] = spawn_squad(st.shake, s.enemy.squads[col].sprite, ex, py, sq_size, true, i * 0.25 + 0.4)
	end

	-- Commanders + HP bars
	st.face_size = 96
	st.p_face_x, st.p_face_y = cx0 + 58, st.hud_y
	st.e_face_x, st.e_face_y = cx1 - 58, st.hud_y
	st.p_face_node = ui.box(st.shake, s.player.face, st.p_face_x, st.p_face_y, st.face_size, st.face_size)
	st.e_face_node = ui.box(st.shake, s.enemy.face, st.e_face_x, st.e_face_y, st.face_size, st.face_size)
	ui.pop(st.e_face_node, 0.3, 1, 0.4, 0.15)
	st.bar_w = math.min(250, ((cx1 - cx0) / 2) - st.face_size - 34)
	local pbx = st.p_face_x + st.face_size / 2 + 12 + st.bar_w / 2
	local ebx = st.e_face_x - st.face_size / 2 - 12 - st.bar_w / 2
	st.bars.player = make_bar("player", pbx, st.hud_y + 14, st.bar_w)
	st.bars.enemy = make_bar("enemy", ebx, st.hud_y + 14, st.bar_w)
	st.orbs.player = { x = pbx - st.bar_w / 2 + 12, y = st.hud_y - 40 }
	st.orbs.enemy = { x = ebx + st.bar_w / 2 - 12, y = st.hud_y - 40 }
	local e_name = s.enemy.name_key and i18n.t(s.enemy.name_key) or s.enemy.name
	ui.label(st.root, e_name, ebx, st.hud_y + 46, 19, ui.DIM, st.bar_w)
	ui.label(st.root, i18n.t("YOU"), pbx, st.hud_y + 46, 19, ui.DIM, st.bar_w)

	-- Board frame, tiles, clipped gem layer
	ui.slice(st.root, "panel_stone", st.board_cx, st.board_cy, st.board_size + 28, st.board_size + 28, ui.WHITE, 24)
	for r = 1, N do
		for c = 1, N do
			local x, y = cell_pos(r, c)
			ui.box(st.root, "cell_bg", x, y, st.cell - 4, st.cell - 4, (r + c) % 2 == 0 and ui.WHITE or V4(0.9, 0.92, 1, 1))
		end
	end
	st.sel_ring = ui.glow(ui.box(st.root, "ring", 0, 0, st.cell * 1.05, st.cell * 1.05, ui.GOLD))
	gui.set_enabled(st.sel_ring, false)
	st.clip = gui.new_box_node(V3(st.board_cx, st.board_cy, 0), V3(st.board_size, st.board_size, 0))
	gui.set_parent(st.clip, st.root)
	gui.set_clipping_mode(st.clip, gui.CLIPPING_MODE_STENCIL)
	gui.set_clipping_visible(st.clip, false)
	rebuild_gems(true)

	-- Board input: Druid drag (swipe swaps mid-gesture, tap-tap selection on release)
	local hit = gui.new_box_node(V3(st.board_cx, st.board_cy, 0), V3(st.board_size, st.board_size, 0))
	gui.set_parent(hit, st.root)
	gui.set_visible(hit, false)
	local drag = ui.druid:new_drag(hit)
	drag.on_touch_start:subscribe(function(_, touch) M.touch_start(touch.x, touch.y) end)
	drag.on_drag:subscribe(function(_, _, _, tx, ty) M.touch_drag(tx, ty) end)
	drag.on_touch_end:subscribe(function(_, touch) M.touch_end(touch and touch.x, touch and touch.y) end)

	-- Boosters bar
	local bw = math.min(196, ((cx1 - cx0) - 40) / 3)
	local gap = bw + 14
	local bcx = (cx0 + cx1) / 2
	for i, kind in ipairs(config.BOOSTER_ORDER) do
		local bx = bcx + (i - 2) * gap
		st.boost_pos[kind] = { x = bx, y = st.boost_y, w = bw, h = 80 }
		ui.btn(st.root, "btn_dark", bx, st.boost_y, bw, 80, i18n.t("BOOST_" .. kind), 20, function()
			M.on_booster_tap(kind)
		end, { icon = config.BOOSTERS[kind].sprite, icon_size = 56 })
	end

	st.hud = ui.pane(st.root, 0, 0)
	st.fx_layer = ui.pane(st.root, 0, 0)
	st.danger = ui.box(st.root, "edge_glow", vw / 2, vh / 2, vw * 1.05, vh * 1.05, V4(1, 0.12, 0.18, 0))
	set_bars(true)
	M.refresh_hud()
	show_tutorial()
	st.shimmer_t = 0
	if s.status == "play" and s.turn == "player" then poki.gameplay_start() end
	-- Rebuilt (resize) after the fight already ended: make sure the result screen still shows
	if s.status ~= "play" and not app.popup then
		ui.after(0.4, function() app.on_battle_end(s.status == "win") end)
	end
end

-- ---------------------------------------------------------------- combat FX
local function apply_hit(target_side, ev)
	local d = st.disp[target_side]
	d.hp = d.hp - (ev.dealt or 0)
	d.shield = d.shield - (ev.blocked or 0)
	set_bars(false)
end

local function impact(is_p, ev, ix, iy)
	local tgt = is_p and "enemy" or "player"
	local face = is_p and st.e_face_node or st.p_face_node
	local tx, ty = face_pos(tgt)
	local col = ui.GEM_COLOR[ev.color] or ui.RED
	local big = ev.crit or ev.kind == "skill"
	audio.play("hit", 0.95, big and 1.15 or 1.0)
	ui.shake(face, is_p and -14 or 14)
	ui.flash_hit(face, col)
	ui.shake_xy(st.shake, big and 11 or (ev.style == "melee" and 7 or 4))
	ui.burst(st.fx_layer, ix, iy, big and 12 or 7, col, 62, 26)
	ui.ring(st.fx_layer, ix, iy, big and 140 or 96, col, 0.3)
	if (ev.blocked or 0) > 0 then ui.ring(st.fx_layer, tx, ty, 112, ui.BLUE, 0.32) end
	local label = "-" .. (ev.dmg or 0) .. (ev.crit and (" " .. i18n.t("CRIT_TAG")) or "")
	ui.float_text(st.fx_layer, label, tx + math.random(-16, 16), ty + 40, big and 36 or 28, big and ui.GOLD or col, 64)
	apply_hit(tgt, ev)
	-- Enemy squad flinch
	local vis = is_p and st.e_vis[ev.color] or st.p_vis[ev.color]
	if vis and ev.style ~= "melee" then ui.flash_hit(vis, ui.RED) end
end

local function strike_melee(ev, is_p, home, holder)
	local hx, hy = home.x, home.y
	local dir = is_p and 1 or -1
	local opp = is_p and st.e_home[ev.color] or st.p_home[ev.color]
	local hit_x = st.arena_cx + dir * st.arena_w * 0.2
	local hit_y = opp and (opp.y * 0.6 + st.arena_cy * 0.4) or st.arena_cy
	audio.play("dash")
	gui.cancel_animations(holder, "position")
	gui.set_position(holder, V3(hx, hy, 0))
	gui.animate(holder, "position", V3(hit_x, hit_y, 0), gui.EASING_INCUBIC, 0.15)
	gui.animate(holder, "scale", V3(1.22, 1.22, 1), gui.EASING_OUTQUAD, 0.15)
	ui.after(0.05, function() ui.puff(st.fx_layer, hx + (hit_x - hx) * 0.35, hy + (hit_y - hy) * 0.35, nil, 30) end)
	ui.after(0.15, function()
		audio.play("slash", 0.95, ev.crit and 1.15 or 1.0)
		local sp = ev.fx or "fx_slash"
		local sl = ui.glow(ui.box(st.fx_layer, sp, hit_x + dir * 24, hit_y, 124, 124, sp == "fx_slash" and (ui.GEM_COLOR[ev.color] or ui.WHITE) or ui.WHITE))
		gui.set_scale(sl, V3(dir * 0.65, 0.65, 1))
		gui.set_euler(sl, V3(0, 0, dir * -22))
		gui.animate(sl, "scale", V3(dir * 1.35, 1.35, 1), gui.EASING_OUTQUAD, 0.18)
		gui.animate(sl, "euler.z", dir * 32, gui.EASING_OUTQUAD, 0.18)
		gui.animate(sl, "color.w", 0, gui.EASING_INQUAD, 0.2, 0.04, function() gui.delete_node(sl) end)
		local ov = is_p and st.e_vis[ev.color] or st.p_vis[ev.color]
		if ov then ui.flash_hit(ov, ui.RED); ui.shake(ov, dir * 14) end
		impact(is_p, ev, hit_x + dir * 28, hit_y)
	end)
	ui.after(0.22, function()
		gui.animate(holder, "position", V3(hx, hy, 0), gui.EASING_OUTQUAD, 0.18)
		gui.animate(holder, "scale", V3(1, 1, 1), gui.EASING_OUTQUAD, 0.18)
	end)
	return 0.4
end

local function strike_ranged(ev, is_p, home, holder)
	local hx, hy = home.x, home.y
	local tgt = is_p and "enemy" or "player"
	local tx, ty = face_pos(tgt)
	local dir = is_p and 1 or -1
	local count = math.max(2, math.min(4, ev.units or 3))
	local col = ui.GEM_COLOR[ev.color] or ui.YELLOW
	audio.play("arrow")
	gui.cancel_animations(holder, "position")
	gui.set_position(holder, V3(hx, hy, 0))
	gui.animate(holder, "position.x", hx - dir * 12, gui.EASING_OUTQUAD, 0.06, 0, function()
		gui.animate(holder, "position.x", hx, gui.EASING_OUTBACK, 0.16)
	end)
	for k = 1, count do
		ui.after((k - 1) * 0.045, function()
			local sy = hy + (k - (count + 1) / 2) * 14
			local sx = hx + dir * 26
			local ang = math.deg(math.atan2(ty - sy, tx - sx))
			local proj = ui.glow(ui.box(st.fx_layer, ev.fx or "proj_arrow", sx, sy, 64, 32, ui.WHITE))
			gui.set_euler(proj, V3(0, 0, ang))
			gui.animate(proj, "position", V3(tx, ty, 0), gui.EASING_LINEAR, 0.19)
			ui.after(0.08, function() ui.spark_dot(st.fx_layer, sx + (tx - sx) * 0.4, sy + (ty - sy) * 0.4, col, 14, 0.16) end)
			ui.after(0.19, function()
				gui.delete_node(proj)
				if k == 1 then impact(is_p, ev, tx, ty)
				else ui.burst(st.fx_layer, tx + math.random(-14, 14), ty + math.random(-14, 14), 3, col, 36, 16) end
			end)
		end)
	end
	return 0.36
end

local function strike_magic(ev, is_p, home, holder)
	local hx, hy = home.x, home.y
	local tgt = is_p and "enemy" or "player"
	local tx, ty = face_pos(tgt)
	local dir = is_p and 1 or -1
	local count = math.max(1, math.min(3, ev.units or 2))
	local col = ui.GEM_COLOR[ev.color] or ui.PURPLE
	audio.play("spell")
	gui.cancel_animations(holder, "position")
	gui.animate(holder, "position.y", hy + 14, gui.EASING_OUTQUAD, 0.12, 0, function()
		gui.animate(holder, "position.y", hy, gui.EASING_INQUAD, 0.16)
	end)
	ui.ring(st.fx_layer, hx, hy + 10, 110, col, 0.28)
	for k = 1, count do
		ui.after(0.05 + (k - 1) * 0.065, function()
			local sy = hy + 10 + (k - (count + 1) / 2) * 16
			local sx = hx + dir * 22
			local ang = math.deg(math.atan2(ty - sy, tx - sx))
			local orb = ui.glow(ui.box(st.fx_layer, ev.fx or "proj_spell", sx, sy, 66, 48, ui.WHITE))
			gui.set_euler(orb, V3(0, 0, ang))
			gui.animate(orb, "position", V3(tx, ty, 0), gui.EASING_INOUTSINE, 0.23)
			gui.animate(orb, "size", V3(84, 60, 0), gui.EASING_OUTQUAD, 0.23)
			ui.after(0.11, function() ui.spark_dot(st.fx_layer, sx + (tx - sx) * 0.5, sy + (ty - sy) * 0.5, col, 22, 0.22) end)
			ui.after(0.23, function()
				gui.delete_node(orb)
				if k == 1 then impact(is_p, ev, tx, ty)
				else ui.ring(st.fx_layer, tx, ty, 90, col, 0.25) end
			end)
		end)
	end
	return 0.42
end

local function strike(ev)
	local is_p = ev.who == "player"
	local holder = is_p and st.p_squads[ev.color] or st.e_squads[ev.color]
	local home = is_p and st.p_home[ev.color] or st.e_home[ev.color]
	if not (holder and home) then
		impact(is_p, ev, face_pos(is_p and "enemy" or "player"))
		return 0.2
	end
	if ev.style == "ranged" then return strike_ranged(ev, is_p, home, holder)
	elseif ev.style == "magic" then return strike_magic(ev, is_p, home, holder) end
	return strike_melee(ev, is_p, home, holder)
end

-- Schedules one combat event at absolute time t; returns the time when it is finished.
local function schedule_effect(ev, t)
	local s = st.session
	local k = ev.kind
	if k == "attack" then
		at(t, function() strike(ev) end)
		return t + 0.42
	elseif k == "skill" then
		local home = ev.who == "player" and st.p_home[ev.color] or st.e_home[ev.color]
		at(t, function()
			audio.play("combo", 0.8, 0.8)
			ui.flash(st.fx_layer, st.app.vw, st.app.vh, V4(ui.GEM_COLOR[ev.color].x, ui.GEM_COLOR[ev.color].y, ui.GEM_COLOR[ev.color].z, 0.22), 0.3)
			if home then
				ui.ring(st.fx_layer, home.x, home.y, 150, ui.GEM_COLOR[ev.color] or ui.GOLD, 0.4)
				local ttl = i18n.t("SK_" .. ev.skill_id)
				local short = string.match(ttl, "^(.-)%s*%(") or ttl
				ui.float_text(st.fx_layer, short, home.x, home.y + 52, 24, ui.GOLD, 50)
			end
		end)
		at(t + 0.12, function() strike(ev) end)
		return t + 0.6
	elseif k == "heal" then
		at(t, function()
			audio.play("heal")
			local fx, fy = face_pos(ev.who)
			ui.flash_hit(ev.who == "player" and st.p_face_node or st.e_face_node, ui.GREEN)
			ui.ring(st.fx_layer, fx, fy, 116, ui.GREEN, 0.36)
			ui.burst(st.fx_layer, fx, fy, 7, ui.GREEN, 54, 22)
			ui.float_text(st.fx_layer, "+" .. (ev.gained or ev.amount), fx, fy + 40, 26, ui.GREEN, 54)
			local d = st.disp[side_of(ev.who)]
			d.hp = d.hp + (ev.gained or ev.amount or 0)
			set_bars(false)
		end)
		return t + 0.3
	elseif k == "shield" then
		at(t, function()
			audio.play("shield")
			local fx, fy = face_pos(ev.who)
			ui.ring(st.fx_layer, fx, fy, 124, ui.BLUE, 0.38)
			local ic = ui.box(st.fx_layer, "icon_shield", fx, fy + 4, 52, 52, ui.BLUE)
			ui.pop(ic, 0.5, 1.25, 0.22)
			gui.animate(ic, "color.w", 0, gui.EASING_INQUAD, 0.25, 0.16, function() gui.delete_node(ic) end)
			ui.float_text(st.fx_layer, "+" .. (ev.gained or ev.amount), fx, fy + 38, 24, ui.BLUE, 48)
			local d = st.disp[side_of(ev.who)]
			d.shield = d.shield + (ev.gained or ev.amount or 0)
			set_bars(false)
		end)
		return t + 0.3
	elseif k == "rune" then
		at(t, function()
			local hm = ev.who == "player" and st.p_home[ev.color] or st.e_home[ev.color]
			if hm then
				local rx, ry = hm.x + (ev.slot == 1 and -13 or 13), hm.y - st.sq_size * 0.46
				ui.burst(st.fx_layer, rx, ry, 4, ui.GEM_COLOR[ev.rune_color] or ui.GOLD, 28, 16)
				ui.ring(st.fx_layer, rx, ry, 44, ui.GEM_COLOR[ev.rune_color] or ui.GOLD, 0.25)
			end
		end)
		return t + 0.1
	elseif k == "status" then
		at(t, function()
			local fx, fy = face_pos(ev.who)
			local key = ev.stype == "burn" and "BURN_TAG" or (ev.stype == "poison" and "POISON_TAG" or "FREEZE_TAG")
			local col = ev.stype == "burn" and ui.RED or (ev.stype == "poison" and ui.GREEN or ui.DIAMOND)
			local ic = ui.box(st.fx_layer, "icon_" .. ev.stype, fx, fy, 64, 64)
			ui.pop(ic, 0.3, 1.2, 0.25)
			gui.animate(ic, "color.w", 0, gui.EASING_INQUAD, 0.3, 0.4, function() gui.delete_node(ic) end)
			ui.float_text(st.fx_layer, i18n.t(key), fx, fy - 30, 22, col, 40)
		end)
		return t + 0.25
	elseif k == "dot" then
		at(t, function()
			local fx, fy = face_pos(ev.who)
			local col = ev.dtype == "poison" and ui.GREEN or ui.RED
			ui.ring(st.fx_layer, fx, fy, 100, col, 0.3)
			ui.burst(st.fx_layer, fx, fy, 5, col, 40, 18)
			ui.float_text(st.fx_layer, i18n.t(ev.dtype == "poison" and "POISON_TAG" or "BURN_TAG") .. " -" .. ev.dmg, fx, fy + 40, 22, col, 50)
			apply_hit(side_of(ev.who), ev)
		end)
		return t + 0.45
	elseif k == "frozen" then
		at(t, function()
			local fx, fy = face_pos(ev.who)
			ui.ring(st.fx_layer, fx, fy, 130, ui.DIAMOND, 0.45)
			ui.float_text(st.fx_layer, i18n.t("FROZEN_FMT", { n = ev.lost or 1 }), fx, fy + 42, 24, ui.DIAMOND, 52)
		end)
		return t + 0.4
	elseif k == "turn" then
		at(t, function()
			audio.play("turn", 0.7)
			local is_p = ev.turn == "player"
			ui.banner(st.fx_layer, i18n.t(is_p and "YOUR_TURN" or "ENEMY_TURN"), st.board_cx, st.board_cy, 54, is_p and ui.GOLD or ui.RED, 0.45)
			M.refresh_hud()
		end)
		return t + 0.6
	elseif k == "extra_move" then
		at(t, function()
			audio.play("upgrade")
			ui.float_text(st.fx_layer, i18n.t("BOOST_extra_move"), st.orbs.player.x + 40, st.orbs.player.y + 10, 26, ui.GOLD, 40)
			M.refresh_hud()
		end)
		return t + 0.2
	elseif k == "revive" then
		at(t, function()
			audio.play("levelup")
			ui.ring(st.fx_layer, st.p_face_x, st.p_face_y, 220, ui.GREEN, 0.6)
			ui.burst(st.fx_layer, st.p_face_x, st.p_face_y, 16, ui.GREEN, 120, 28)
		end)
		return t + 0.5
	elseif k == "win" or k == "lose" then
		local won = k == "win"
		at(t + 0.2, function()
			local fx, fy = face_pos(won and "enemy" or "player")
			local face = won and st.e_face_node or st.p_face_node
			ui.ring(st.fx_layer, fx, fy, 260, won and ui.GOLD or ui.RED, 0.6)
			ui.burst(st.fx_layer, fx, fy, 22, won and ui.GOLD or ui.RED, 160, 30)
			ui.shake_xy(st.shake, 16)
			gui.animate(face, "scale", V3(1.4, 1.4, 1), gui.EASING_OUTQUAD, 0.4)
			gui.animate(face, "color.w", 0.15, gui.EASING_INQUAD, 0.5, 0.2)
			audio.play(won and "win" or "lose")
			if won then
				ui.banner(st.fx_layer, i18n.t("VICTORY"), st.board_cx, st.board_cy, 72, ui.GOLD, 0.9)
				for _, col in ipairs(config.ATTACK_COLORS) do
					local v = st.e_vis[col]
					if v then gui.animate(v, "color.w", 0, gui.EASING_INQUAD, 0.4, 0.1) end
				end
			end
		end)
		at(t + 1.35, function() st.app.on_battle_end(won) end)
		return t + 1.5
	end
	return t
end

-- ---------------------------------------------------------------- board animation
local function anim_swap(ev)
	local a, b = st.gems[ev.r1][ev.c1], st.gems[ev.r2][ev.c2]
	local x1, y1 = cell_pos(ev.r1, ev.c1)
	local x2, y2 = cell_pos(ev.r2, ev.c2)
	if a then gui.animate(a.node, "position", V3(x2, y2, 0), gui.EASING_INOUTQUAD, 0.12) end
	if b then gui.animate(b.node, "position", V3(x1, y1, 0), gui.EASING_INOUTQUAD, 0.12) end
	st.gems[ev.r1][ev.c1], st.gems[ev.r2][ev.c2] = b, a
	audio.play("whoosh", 0.35, 1.4)
end

local function telegraph(ev)
	for _, p in ipairs({ { ev.r1, ev.c1 }, { ev.r2, ev.c2 } }) do
		local x, y = cell_pos(p[1], p[2])
		ui.ring(st.fx_layer, x, y, st.cell * 1.3, ui.RED, 0.3)
		local g = st.gems[p[1]][p[2]]
		if g then
			gui.animate(g.node, "scale", V3(1.15, 1.15, 1), gui.EASING_OUTQUAD, 0.12, 0, function()
				gui.animate(g.node, "scale", V3(1, 1, 1), gui.EASING_INQUAD, 0.12)
			end)
		end
	end
end

local COMBO_KEYS = { [2] = "COMBO_2", [3] = "COMBO_3", [4] = "COMBO_4" }

local function anim_step(ev, step)
	local who = ev.who or "player"
	local is_p = who == "player"
	local cascade = step.cascade or 1
	audio.play("match", 0.9, 1.0 + (cascade - 1) * 0.14)
	if cascade >= 2 then
		local key = COMBO_KEYS[math.min(4, cascade)]
		ui.banner(st.fx_layer, i18n.t(key, { n = cascade }), st.board_cx, st.board_cy + st.cell * 0.6, 40 + math.min(4, cascade) * 6, ui.GOLD, 0.35)
		if cascade >= 3 then audio.play("combo", 0.7, 1 + cascade * 0.05) end
	end
	-- Clear
	local rep = {}
	local many = #step.cleared > 14
	for _, cl in ipairs(step.cleared) do
		local g = st.gems[cl.r][cl.c]
		if g then kill_gem(g); st.gems[cl.r][cl.c] = nil end
		local cx, cy = cell_pos(cl.r, cl.c)
		local col = ui.GEM_COLOR[cl.color] or ui.WHITE
		if not rep[cl.color] then rep[cl.color] = { x = cx, y = cy, n = 0 } end
		rep[cl.color].n = rep[cl.color].n + 1
		ui.ring(st.fx_layer, cx, cy, st.cell * 0.9, col, 0.22)
		if not many then ui.burst(st.fx_layer, cx, cy, 3, col, st.cell * 0.45, 16) end
		if cl.special then
			ui.ring(st.fx_layer, cx, cy, st.cell * 2.6, ui.WHITE, 0.32)
			ui.shake_xy(st.shake, 6)
		end
	end
	-- Energy orbs fly into the squads / commander that will use them
	for col, pos in pairs(rep) do
		local tx, ty = face_pos(who)
		local h = (is_p and st.p_home or st.e_home)[col]
		if h then tx, ty = h.x, h.y end
		for k = 1, math.min(3, math.ceil(pos.n / 3)) do
			local orb = ui.glow(ui.box(st.fx_layer, "glow", pos.x, pos.y, 34, 34, ui.GEM_COLOR[col] or ui.WHITE))
			ui.fly(orb, tx, ty, 0.2 + k * 0.03, (k - 1) * 0.03, function() gui.delete_node(orb) end)
		end
	end
	-- Specials are born where the match was made
	ui.after(0.08, function()
		for _, sp in ipairs(step.specials or {}) do
			local old = st.gems[sp.r][sp.c]
			if old then gui.delete_node(old.node) end
			st.gems[sp.r][sp.c] = make_gem(sp.r, sp.c, sp)
			ui.pop(st.gems[sp.r][sp.c].node, 0.2, 1, 0.3)
			local x, y = cell_pos(sp.r, sp.c)
			ui.ring(st.fx_layer, x, y, st.cell * 1.8, ui.GOLD, 0.35)
			audio.play("star", 0.5, 1.2)
		end
	end)
	-- Gravity + refill
	ui.after(0.13, function()
		for _, f in ipairs(step.falls or {}) do
			local g = st.gems[f.from_r][f.c]
			st.gems[f.from_r][f.c] = nil
			if g then
				local x, y = cell_pos(f.to_r, f.c)
				gui.cancel_animations(g.node, "position")
				gui.animate(g.node, "position", V3(x, y, 0), gui.EASING_OUTBOUNCE, 0.24)
			end
			st.gems[f.to_r][f.c] = g
		end
		local per_col = {}
		for _, sp in ipairs(step.spawns or {}) do per_col[sp.c] = (per_col[sp.c] or 0) + 1 end
		for _, sp in ipairs(step.spawns or {}) do
			local _, top_y = cell_pos(sp.r + per_col[sp.c], sp.c)
			local g = make_gem(sp.r, sp.c, sp, top_y)
			local x, y = cell_pos(sp.r, sp.c)
			gui.animate(g.node, "position", V3(x, y, 0), gui.EASING_OUTBOUNCE, 0.26, (sp.r - 1) * 0.012)
			st.gems[sp.r][sp.c] = g
		end
	end)
end

local function anim_shuffle()
	audio.play("whoosh", 0.8)
	for r = 1, N do
		for c = 1, N do
			local g = st.gems[r][c]
			if g then
				gui.animate(g.node, "scale", V3(0.05, 0.05, 1), gui.EASING_INBACK, 0.2, (r + c) * 0.01)
				gui.animate(g.node, "euler.z", 180, gui.EASING_INQUAD, 0.2, (r + c) * 0.01)
			end
		end
	end
	ui.after(0.3, function()
		rebuild_gems(true)
		ui.float_text(st.fx_layer, i18n.t("SHUFFLED"), st.board_cx, st.board_cy, 36, ui.DIAMOND, 30)
	end)
end

-- ---------------------------------------------------------------- turn loop
function M.process()
	local s = st.session
	local evs = s.events
	if #evs == 0 then return end
	s.events = {}
	clear_hint()
	if st.tut_node then gui.delete_node(st.tut_node); st.tut_node = nil end

	local t = 0
	local i = 1
	while i <= #evs do
		local ev = evs[i]
		if ev.kind == "swap" or ev.kind == "hammer" then
			local t0 = t
			if ev.kind == "swap" then
				if ev.who == "enemy" then
					at(t0, function() telegraph(ev) end)
					t0 = t0 + 0.34
				end
				at(t0, function() anim_swap(ev) end)
				t0 = t0 + 0.14
			else
				at(t0, function()
					local hx, hy = cell_pos(ev.r, ev.c)
					audio.play("hit", 1, 0.8)
					ui.ring(st.fx_layer, hx, hy, 150, ui.GOLD, 0.32)
					ui.burst(st.fx_layer, hx, hy, 10, ui.GOLD, 70, 24)
					ui.shake_xy(st.shake, 8)
				end)
				t0 = t0 + 0.16
			end
			local step_t = {}
			for k, step in ipairs(ev.steps or {}) do
				step_t[k] = t0
				at(t0, function() anim_step(ev, step) end)
				t0 = t0 + STEP_DUR
			end
			local fx_end = t0
			local per_step = {}
			local j = i + 1
			while j <= #evs and evs[j].step do
				local e = evs[j]
				local base = (step_t[e.step] or t0) + 0.2
				local n = per_step[e.step] or 0
				if e.kind == "attack" or e.kind == "skill" then per_step[e.step] = n + 1 end
				fx_end = math.max(fx_end, schedule_effect(e, base + math.min(3, n) * 0.13))
				j = j + 1
			end
			if ev.shuffled then
				at(t0, anim_shuffle)
				t0 = t0 + 0.6
			end
			t = math.max(t0, fx_end)
			i = j
		elseif ev.kind == "shuffle" then
			at(t, anim_shuffle)
			t = t + 0.6
			i = i + 1
		else
			t = math.max(t, schedule_effect(ev, t))
			i = i + 1
		end
	end

	st.busy = true
	at(t + 0.05, function()
		st.busy = false
		sync_board()
		sync_disp()
		M.refresh_hud()
		show_tutorial()
		if s.status == "play" and s.turn == "player" then poki.gameplay_start() end
	end)
end

-- ---------------------------------------------------------------- input
function M.on_booster_tap(kind)
	local s = st.session
	if st.busy or s.status ~= "play" or s.turn ~= "player" then return end
	clear_hint()
	if (s.boosters[kind] or 0) <= 0 then
		st.app.buy_booster_ad(kind)
		return
	end
	if kind == "hammer" then
		st.hammer_mode = not st.hammer_mode
		if st.hammer_mode then
			ui.banner(st.fx_layer, i18n.t("HAMMER_HINT"), st.board_cx, st.board_cy, 34, ui.GOLD, 0.6)
		end
		M.refresh_hud()
		return
	end
	if kind == "extra_move" and s.player.moves_left >= config.MAX_MOVES then
		ui.float_text(st.fx_layer, i18n.t("MAX"), st.boost_pos[kind].x, st.boost_y + 60, 22, ui.RED, 30)
		return
	end
	if battle.use_booster(s, kind) then M.process() end
end

local function bounce_invalid(r1, c1, r2, c2)
	audio.play("blocked")
	local a = st.gems[r1] and st.gems[r1][c1]
	local b = st.gems[r2] and st.gems[r2][c2]
	if not (a and b) then return end
	local x1, y1 = cell_pos(r1, c1)
	local x2, y2 = cell_pos(r2, c2)
	gui.animate(a.node, "position", V3(x1 + (x2 - x1) * 0.34, y1 + (y2 - y1) * 0.34, 0), gui.EASING_OUTQUAD, 0.06, 0, function()
		gui.animate(a.node, "position", V3(x1, y1, 0), gui.EASING_OUTBACK, 0.12)
	end)
	gui.animate(b.node, "position", V3(x2 + (x1 - x2) * 0.34, y2 + (y1 - y2) * 0.34, 0), gui.EASING_OUTQUAD, 0.06, 0, function()
		gui.animate(b.node, "position", V3(x2, y2, 0), gui.EASING_OUTBACK, 0.12)
	end)
end

local function set_selected(r, c)
	if st.sel then
		local g = st.gems[st.sel.r] and st.gems[st.sel.r][st.sel.c]
		if g then gui.cancel_animations(g.node, "scale"); gui.set_scale(g.node, V3(1, 1, 1)) end
	end
	st.sel = r and { r = r, c = c } or nil
	gui.set_enabled(st.sel_ring, r ~= nil)
	if r then
		local x, y = cell_pos(r, c)
		gui.set_position(st.sel_ring, V3(x, y, 0))
		local g = st.gems[r][c]
		if g then gui.animate(g.node, "scale", V3(1.12, 1.12, 1), gui.EASING_INOUTSINE, 0.35, 0, nil, gui.PLAYBACK_LOOP_PINGPONG) end
	end
end

local function try_swap(r1, c1, r2, c2)
	set_selected(nil)
	if r2 < 1 or r2 > N or c2 < 1 or c2 > N then return end
	if battle.player_swap(st.session, r1, c1, r2, c2) then
		M.process()
	else
		bounce_invalid(r1, c1, r2, c2)
	end
end

local function can_act()
	local s = st.session
	return not st.busy and s.status == "play" and s.turn == "player"
end

function M.touch_start(x, y)
	clear_hint()
	if not can_act() then return end
	local r, c = screen_to_cell(x, y)
	if not r then return end
	if st.hammer_mode then
		st.hammer_mode = false
		if battle.use_booster(st.session, "hammer", r, c) then M.process() else M.refresh_hud() end
		return
	end
	st.drag = { r = r, c = c, done = false }
	audio.play("tap")
	local g = st.gems[r][c]
	if g and not (st.sel and st.sel.r == r and st.sel.c == c) then
		gui.animate(g.node, "scale", V3(1.1, 1.1, 1), gui.EASING_OUTQUAD, 0.08)
	end
end

function M.touch_drag(total_x, total_y)
	local d = st.drag
	if not d or d.done or not can_act() then return end
	local th = st.cell * 0.33
	if math.abs(total_x) < th and math.abs(total_y) < th then return end
	d.done = true
	local nr, nc = d.r, d.c
	if math.abs(total_x) > math.abs(total_y) then
		nc = nc + (total_x > 0 and 1 or -1)
	else
		nr = nr + (total_y > 0 and 1 or -1)
	end
	local g = st.gems[d.r][d.c]
	if g then gui.set_scale(g.node, V3(1, 1, 1)) end
	try_swap(d.r, d.c, nr, nc)
end

function M.touch_end()
	local d = st.drag
	st.drag = nil
	if not d or d.done or not can_act() then return end
	local g = st.gems[d.r][d.c]
	if g then gui.animate(g.node, "scale", V3(1, 1, 1), gui.EASING_OUTBACK, 0.12) end
	local r, c = d.r, d.c
	if not st.sel then
		set_selected(r, c)
	elseif st.sel.r == r and st.sel.c == c then
		set_selected(nil)
	elseif math.abs(st.sel.r - r) + math.abs(st.sel.c - c) == 1 then
		try_swap(st.sel.r, st.sel.c, r, c)
	else
		set_selected(r, c)
	end
end

-- ---------------------------------------------------------------- update
function M.update(dt)
	local s = st.session
	if not (s and st.gems) then return end
	-- Idle shimmer on random gems
	st.shimmer_t = (st.shimmer_t or 0) + dt
	if st.shimmer_t > 0.7 then
		st.shimmer_t = 0
		local r, c = math.random(1, N), math.random(1, N)
		if st.gems[r][c] then
			local x, y = cell_pos(r, c)
			ui.spark_dot(st.fx_layer, x + math.random(-12, 12), y + math.random(-12, 12), V4(1, 1, 1, 0.9), st.cell * 0.5, 0.35)
		end
	end
	if s.status ~= "play" or st.busy then return end
	if s.turn == "enemy" then
		st.ai_timer = st.ai_timer + dt
		if st.ai_timer >= 0.45 then
			st.ai_timer = 0
			battle.step_enemy(s)
			M.process()
		end
	else
		st.ai_timer = 0
		st.idle = (st.idle or 0) + dt
		-- Debug autoplay (smoke tests): play the hinted move through the normal input path
		if M.autoplay and st.idle > 0.3 then
			local m = battle.suggest_move(s)
			if m then try_swap(m.r1, m.c1, m.r2, m.c2) end
			return
		end
		if st.idle > HINT_DELAY and not st.hint_nodes and not s.tutorial then
			show_hint()
		end
	end
end

return M
