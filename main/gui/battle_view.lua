-- Battle screen: arena with 3 lanes (your squad faces the enemy squad of the same gem colour), a turn
-- bar (portraits, team HP + shield bars, moves, YOUR TURN / ENEMY TURN pill) and the 7x7 board.
-- HP is one pool per side (commander); visually every attack flies from the striking squad into the
-- enemy squad of its lane. Board input goes through a Druid drag; every cascade step is animated
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
local LANES = config.ATTACK_COLORS
local LANE_OF = { red = true, yellow = true, purple = true }
local SIDES = { "player", "enemy" }

local SPEC_SPRITE = { line_h = "spec_line_h", line_v = "spec_line_v", bomb = "spec_bomb" }
local STEP_DUR = 0.36
local HINT_DELAY = 5.5
local DMG_COLOR = V4(1, 0.93, 0.86, 1)
local DEAD_COLOR = V4(0.36, 0.38, 0.46, 0.6)

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

local function at(t, fn)
	if t <= 0.001 then fn() else ui.after(t, fn) end
end

local function side_of(who) return who == "player" and "player" or "enemy" end
local function foe_of(who) return who == "player" and "enemy" or "player" end
local function unit(side, col) return st.units[side] and st.units[side][col] end
local function tint(c, a) return V4(c.x, c.y, c.z, a) end

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

-- ---------------------------------------------------------------- target preview (who hits whom)
local function clear_target()
	if st.target_fx then gui.delete_node(st.target_fx); st.target_fx = nil end
end

-- Touching a red / yellow / purple gem shows your squad of that colour and the enemy squad it hits.
local function show_target(col)
	clear_target()
	if not LANE_OF[col] then return end
	local A, T = unit("player", col), unit("enemy", col)
	if not (A and T) then return end
	st.target_fx = ui.pane(st.fx_layer, 0, 0)
	local c = ui.GEM_COLOR[col]
	ui.glow(ui.box(st.target_fx, "band", (A.home.x + T.home.x) / 2, A.home.y, math.abs(T.home.x - A.home.x) + st.us, st.us * 0.7, tint(c, 0.35)))
	local ret = ui.glow(ui.box(st.target_fx, "reticle", T.home.x, T.home.y, st.us * 1.05, st.us * 1.05, tint(c, 0.95)))
	ui.spin(ret, 3)
	ui.pulse(ret, 1.1, 0.3)
	local gl = ui.glow(ui.box(st.target_fx, "glow", A.home.x, A.home.y, st.us * 1.6, st.us * 1.6, tint(c, 0.4)))
	ui.pulse(gl, 1.1, 0.35)
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

-- ---------------------------------------------------------------- team HP bars
local function set_bars(instant)
	local s = st.session
	for _, side in ipairs(SIDES) do
		local f, d, b = s[side], st.disp[side], st.bars[side]
		d.hp = math.max(0, math.min(f.max_hp, d.hp))
		d.shield = math.max(0, d.shield)
		b.hp.to(d.hp / f.max_hp, instant)
		-- Shield value lives inside the HP label so nothing spills between the bars
		b.hp.text(math.floor(d.hp + 0.5) .. " / " .. f.max_hp .. (d.shield >= 1 and ("  +" .. math.floor(d.shield + 0.5)) or ""))
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
	for _, side in ipairs(SIDES) do
		st.disp[side].hp = s[side].hp
		st.disp[side].shield = s[side].shield
	end
	set_bars(false)
end

-- ---------------------------------------------------------------- squads: fall (end of fight) / rise
local function fall_unit(side, col, quiet, delay)
	local U = unit(side, col)
	if not U or U.dead then return end
	U.dead = true
	local x, y = U.home.x, U.home.y
	local turn = side == "player" and 1 or -1
	gui.cancel_animations(U.vis, "position.y")
	gui.cancel_animations(U.holder, "position")
	gui.set_position(U.holder, V3(x, y, 0))
	gui.set_alpha(U.ground, 0)
	local fall_pos = V3(0, -st.us * 0.16, 0)
	if quiet then
		gui.set_euler(U.vis, V3(0, 0, 78 * turn))
		gui.set_position(U.vis, fall_pos)
		gui.set_color(U.vis, DEAD_COLOR)
		U.skull = ui.icon(U.holder, "icon_skull", 0, st.us * 0.1, st.us * 0.42)
		return
	end
	ui.after(delay or 0, function()
		gui.cancel_animations(U.vis, "color")
		gui.set_color(U.vis, V4(1, 1, 1, 1))
		gui.animate(U.vis, "scale", V3(U.flip * 1.25, 1.25, 1), gui.EASING_OUTQUAD, 0.1, 0, function()
			gui.animate(U.vis, "scale", V3(U.flip, 1, 1), gui.EASING_INQUAD, 0.22)
		end)
		gui.animate(U.vis, "euler.z", 78 * turn, gui.EASING_OUTBOUNCE, 0.5, 0.08)
		gui.animate(U.vis, "position", fall_pos, gui.EASING_OUTBOUNCE, 0.5, 0.08)
		gui.animate(U.vis, "color", DEAD_COLOR, gui.EASING_INQUAD, 0.45, 0.18)
		audio.play("death", 0.8)
		ui.burst(st.fx_layer, x, y, 14, ui.GEM_COLOR[col] or ui.WHITE, st.us * 1.1, 26)
		ui.puff(st.fx_layer, x, y - st.us * 0.3, nil, st.us * 0.6)
		ui.shake_xy(st.shake, 10)
		U.skull = ui.icon(U.holder, "icon_skull", 0, st.us * 0.1, st.us * 0.42)
		ui.pop(U.skull, 0.2, 1, 0.35, 0.3)
	end)
end

local function rise_unit(side, col)
	local U = unit(side, col)
	if not U then return end
	ui.ring(st.fx_layer, U.home.x, U.home.y, st.us * 2.2, ui.GREEN, 0.5)
	ui.burst(st.fx_layer, U.home.x, U.home.y, 12, ui.GREEN, st.us, 24)
	if not U.dead then return end
	U.dead = false
	if U.skull then gui.delete_node(U.skull); U.skull = nil end
	gui.cancel_animations(U.vis, "euler.z")
	gui.cancel_animations(U.vis, "position")
	gui.cancel_animations(U.vis, "color")
	gui.set_euler(U.vis, V3(0, 0, 0))
	gui.set_position(U.vis, V3(0, 0, 0))
	gui.set_color(U.vis, ui.WHITE)
	gui.animate(U.vis, "position.y", 4, gui.EASING_INOUTSINE, 1.15, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
	ui.pop(U.vis, 0.3, 1, 0.4)
end

-- ---------------------------------------------------------------- HUD (rebuilt on every change)
local function turn_visuals(is_p)
	local s = st.session
	local playing = s.status == "play"
	-- Active side: glowing ground under its squads
	for _, side in ipairs(SIDES) do
		local active = playing and ((side == "player") == is_p)
		for _, col in ipairs(LANES) do
			local U = unit(side, col)
			gui.cancel_animations(U.ground, "color.w")
			if active and not U.dead then
				gui.set_alpha(U.ground, 0.22)
				gui.animate(U.ground, "color.w", 0.45, gui.EASING_INOUTSINE, 0.7, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
			else
				gui.animate(U.ground, "color.w", 0, gui.EASING_OUTQUAD, 0.25)
			end
		end
	end
	-- Board: red veil while the enemy plays, golden halo while it's your move
	gui.cancel_animations(st.veil, "color.w")
	gui.animate(st.veil, "color.w", (playing and not is_p) and 0.32 or 0, gui.EASING_OUTQUAD, 0.3)
	gui.cancel_animations(st.halo, "color.w")
	if playing and is_p then
		gui.set_alpha(st.halo, 0.12)
		gui.animate(st.halo, "color.w", 0.3, gui.EASING_INOUTSINE, 0.8, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
	else
		gui.animate(st.halo, "color.w", 0, gui.EASING_OUTQUAD, 0.25)
	end
	-- Turn pill + active portrait
	gui.play_flipbook(st.turn_pill, is_p and "btn_gold" or "btn_crimson")
	gui.set_text(st.turn_lbl, i18n.t(is_p and "YOUR_TURN" or "ENEMY_TURN"))
	ui.fit(st.turn_lbl, st.turn_w - 64, 22)
	gui.play_flipbook(st.turn_face, is_p and s.player.face or s.enemy.face)
	for _, side in ipairs(SIDES) do
		local fr = st.faces[side]
		local active = playing and ((side == "player") == is_p)
		gui.cancel_animations(fr.ring, "color.w")
		gui.set_alpha(fr.ring, active and 0.9 or 0)
		gui.set_color(fr.face, active and ui.WHITE or V4(0.55, 0.58, 0.68, 1))
		if active then gui.animate(fr.ring, "color.w", 0.35, gui.EASING_INOUTSINE, 0.5, 0, nil, gui.PLAYBACK_LOOP_PINGPONG) end
	end
end

function M.refresh_hud()
	local s = st.session
	if not (s and st.hud) then return end
	gui.delete_node(st.hud)
	st.hud = ui.pane(st.root, 0, 0)
	local is_p = s.turn == "player"
	turn_visuals(is_p)

	-- Round + fury
	gui.set_text(st.round_lbl, i18n.t("ROUND_FMT", { n = s.turn_num }))
	ui.fit(st.round_lbl, st.round_w - 20, 20)
	if s.turn_num >= config.FURY_TURN then
		local pct = math.floor(0.2 * (s.turn_num - config.FURY_TURN + 1) * 100 + 0.5)
		local fl = ui.text(st.hud, i18n.t("FURY_FMT", { n = pct }), st.round_x, st.top_y - 40, 18, ui.RED)
		ui.pulse(fl, 1.08, 0.4)
	end

	-- Move orbs under each team bar
	for _, side in ipairs(SIDES) do
		local f = s[side]
		local active_side = (side == "player") == is_p
		local total = math.max(f.max_moves, f.moves_left)
		local o = st.orbs[side]
		for i = 1, total do
			local on = active_side and i <= f.moves_left
			local col = side == "player" and ui.WHITE or V4(1, 0.55, 0.55, 1)
			local orb = ui.box(st.hud, "icon_move_orb", o.x + o.dir * (i - 1) * o.step, o.y, o.size, o.size, on and col or V4(0.3, 0.35, 0.45, 0.45))
			if on and i == f.moves_left then ui.pulse(orb, 1.18, 0.4) end
		end
		if active_side and s.status == "play" and side == "player" and f.moves_left == 1 and f.max_moves > 1 then
			local lm = ui.text(st.hud, i18n.t("LAST_MOVE"), o.x + o.dir * (total * o.step + 50), o.y, 15, ui.GOLD)
			ui.pulse(lm, 1.1, 0.35)
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

	-- Rune crystals next to each squad (2 filled -> special skill)
	for _, side in ipairs(SIDES) do
		for _, col in ipairs(LANES) do
			local sq = s[side].squads[col]
			local U = unit(side, col)
			if sq and sq.runes and U and not U.dead then
				for slot = 1, 2 do
					local rcol = sq.runes[slot]
					local filled = sq.rune_filled and sq.rune_filled[slot]
					local rx, ry = U.rune_x + U.rune_dir * (slot - 1) * st.rune_step, U.rune_y
					ui.box(st.hud, "rune_bg", rx, ry, st.rune_size, st.rune_size)
					if filled then
						local gl = ui.glow(ui.box(st.hud, "glow", rx, ry, st.rune_size * 1.5, st.rune_size * 1.5, ui.GEM_COLOR[rcol] or ui.WHITE))
						ui.pulse(gl, 1.2, 0.5)
					end
					local gs = st.rune_size * (filled and 0.8 or 0.6)
					local gc = ui.box(st.hud, ui.GEM_SPRITE[rcol] or "gem_red", rx, ry, gs, gs)
					if not filled then gui.set_alpha(gc, 0.4) end
				end
			end
		end
	end

	-- Burn / poison / freeze badges on the portraits
	for _, side in ipairs(SIDES) do
		local sts = s[side].statuses
		local fr = st.faces[side]
		local icons = {}
		for _, key in ipairs({ "burn", "poison" }) do
			if sts and sts[key] then icons[#icons + 1] = { "icon_" .. key, sts[key].turns } end
		end
		if sts and (sts.freeze or 0) > 0 then icons[#icons + 1] = { "icon_freeze" } end
		local dir = side == "player" and 1 or -1
		for k, ic in ipairs(icons) do
			local ix = fr.x + dir * (st.face_size * 0.3 + (k - 1) * 24)
			local iy = st.strip_y + st.face_size * 0.36
			local n = ui.box(st.hud, ic[1], ix, iy, 26, 26)
			ui.pulse(n, 1.12, 0.5)
			if ic[2] then ui.text(st.hud, tostring(ic[2]), ix + 11, iy - 9, 13, ui.WHITE) end
		end
	end
end

-- ---------------------------------------------------------------- tutorial
local function show_tutorial()
	if st.tut_node then gui.delete_node(st.tut_node); st.tut_node = nil end
	local s = st.session
	if not (s and s.tutorial and s.turn == "player" and s.status == "play" and s.tutorial_step <= 3) then return end
	st.tut_node = ui.pane(st.root, 0, 0)
	local key = ({ "TUT_MATCH", "TUT_COLORS", "TUT_SUPPORT" })[s.tutorial_step] or "TUT_MATCH"
	-- Over the stage title in the top bar: never covers squads, bars or gems
	local pw = math.min(st.arena_w - 250, 640)
	local pill = ui.slice(st.tut_node, "btn_gold", st.arena_cx, st.top_y - 2, pw, 80, ui.WHITE, 18)
	ui.label(pill, i18n.t(key), 0, 3, 21, ui.INK, pw - 26, { lines = 2, plain = true, outline = V4(1, 0.9, 0.6, 0) })
	ui.pulse(pill, 1.03, 0.55)
	if s.tutorial_step <= 2 then show_hint() end
end

-- ---------------------------------------------------------------- arena
local function spawn_unit(parent, side, sq, x, y, size, phase)
	local holder = ui.pane(parent, x, y)
	local ground = ui.glow(ui.box(holder, "glow", 0, -size * 0.3, size * 1.5, size * 0.75, tint(side == "player" and ui.GOLD or ui.RED, 0)))
	ui.box(holder, "glow", 0, -size * 0.38, size * 0.9, size * 0.24, V4(0, 0, 0, 0.5))
	local vis = ui.icon(holder, sq.sprite, 0, 0, size)
	local flip = side == "enemy" and -1 or 1
	gui.set_scale(vis, V3(flip, 1, 1))
	gui.animate(vis, "position.y", 4, gui.EASING_INOUTSINE, 1.15, phase, nil, gui.PLAYBACK_LOOP_PINGPONG)
	return { holder = holder, vis = vis, ground = ground, home = { x = x, y = y }, flip = flip, dead = false }
end

-- Team HP bar (+ thin shield bar) inside the turn bar, between the portrait and the turn pill.
local function make_team_bar(side, bx, by, bw)
	local f = st.session[side]
	local col = side == "player" and ui.GREEN or ui.RED
	local hp = ui.bar(st.root, bx, by, bw, 28, f.hp / f.max_hp, col, { ghost = true, text = f.hp .. " / " .. f.max_hp, text_size = 18 })
	local sh = ui.bar(st.root, bx, by - 21, bw - 12, 9, 0, ui.BLUE)
	gui.set_alpha(sh.bg, 0.85)
	local outer = side == "player" and -1 or 1
	local icon = ui.box(st.root, "icon_shield", bx + outer * (bw / 2 - 4), by - 21, 22, 22)
	return { hp = hp, sh = sh, sh_icon = icon, x = bx, y = by, w = bw }
end

-- ---------------------------------------------------------------- build
function M.build(app, parent)
	local s = app.session
	st = {
		app = app, session = s, root = ui.pane(parent, 0, 0), busy = false, ai_timer = 0, idle = 0,
		hammer_mode = false, sel = nil, drag = nil,
		units = { player = {}, enemy = {} }, boost_pos = {}, orbs = {}, faces = {}, bars = {},
		disp = { player = { hp = s.player.hp, shield = s.player.shield }, enemy = { hp = s.enemy.hp, shield = s.enemy.shield } },
	}
	local vw, vh = app.vw, app.vh
	local is_land = app.orient == "landscape"

	-- Theme tint: campaign biome or PvP league colour
	local tint_hex = s.mode == "campaign" and campaign.biome(s.stage_id).tint or "#c9d6ee"
	local th = ui.hex(tint_hex)
	ui.background(st.root, vw, vh, th, true)

	-- ---- layout
	local cx0, cx1
	local strip_h = 92
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
		cx1 = st.board_x0 - 52
		st.top_y = vh - 46
		st.boost_y = 60
		st.strip_y = st.boost_y + 38 + 14 + strip_h / 2
		st.arena_y0 = st.strip_y + strip_h / 2 + 8
		st.arena_y1 = st.top_y - 40
	else
		local comp_w = math.min(vw - 24, 780)
		cx0 = (vw - comp_w) / 2
		cx1 = cx0 + comp_w
		local bs = math.min(comp_w - 10, 640)
		st.cell = math.floor((bs - 26) / N)
		st.board_size = st.cell * N
		st.board_cx = vw / 2
		st.board_y0 = 122
		st.board_x0 = st.board_cx - st.board_size / 2
		st.board_cy = st.board_y0 + st.board_size / 2
		st.top_y = vh - 44
		st.boost_y = 56
		st.strip_y = st.board_y0 + st.board_size + 14 + 6 + strip_h / 2
		st.arena_y0 = st.strip_y + strip_h / 2 + 8
		st.arena_y1 = st.top_y - 36
	end
	st.arena_cx, st.arena_w = (cx0 + cx1) / 2, cx1 - cx0
	st.arena_h = math.max(220, st.arena_y1 - st.arena_y0)
	st.arena_cy = st.arena_y0 + st.arena_h / 2
	local acx, acy, aw, ah = st.arena_cx, st.arena_cy, st.arena_w, st.arena_h

	-- ---- top bar: pause | stage + enemy name | round
	ui.btn(st.root, "btn_round", cx0 + 38, st.top_y, 62, 62, "", 20, function() app.pause() end, { icon = "icon_pause", icon_size = 30 })
	local stage_str = s.mode == "pvp" and i18n.t("PVP")
		or (i18n.t("STAGE_FMT", { n = s.stage_id }) .. (campaign.get_stage(s.stage_id).boss and ("  " .. i18n.t("BOSS")) or ""))
	local title_w = (cx1 - cx0) - 300
	ui.label(st.root, stage_str, acx, st.top_y + 12, 26, ui.BONE, title_w)
	local e_name = s.enemy.name_key and i18n.t(s.enemy.name_key) or s.enemy.name
	ui.label(st.root, i18n.t("VS_FMT", { name = e_name }), acx, st.top_y - 16, 18, ui.DIM, title_w)
	st.round_w = 150
	st.round_x = cx1 - st.round_w / 2 - 4
	local rp = ui.slice(st.root, "panel_dark", st.round_x, st.top_y, st.round_w, 46, ui.WHITE, 14)
	st.round_lbl = ui.text(rp, "", 0, 2, 20, ui.GOLD)

	-- ---- arena: zoom pivot -> shake pane -> lanes and squads
	st.zoom = ui.pane(st.root, acx, acy)
	local inner = ui.pane(st.zoom, -acx, -acy)
	st.shake = ui.pane(inner, 0, 0)
	ui.slice(st.shake, "panel_dark", acx, acy, aw, ah, ui.WHITE, 20)
	ui.box(st.shake, "arena_bg", acx, acy, aw - 14, ah - 14, V4(0.55 + th.x * 0.45, 0.55 + th.y * 0.45, 0.55 + th.z * 0.45, 1))
	ui.box(st.shake, "vignette", acx, acy, aw - 14, ah - 14, V4(1, 1, 1, 0.75))

	-- Lane row: [squad] -- (gem) -- [squad]; matched gems of a colour make that squad strike across
	local pad = 8
	st.lane_h = (ah - pad * 2) / 3
	st.us = math.max(48, math.min(st.lane_h - 10, aw * (is_land and 0.2 or 0.24), 170))
	st.rune_size = is_land and 24 or 20
	st.rune_step = st.rune_size + 3
	local ms = math.min(46, st.lane_h * 0.36)
	local ux = aw / 2 - st.us * 0.55 - 10
	for i, col in ipairs(LANES) do
		local ly = st.arena_y1 - pad - (i - 0.5) * st.lane_h
		local c = ui.GEM_COLOR[col]
		local band = ui.box(st.shake, "band", acx, ly, aw - 24, st.lane_h - 8, tint(c, 0.12))
		gui.set_blend_mode(band, gui.BLEND_ADD)
		ui.box(st.shake, "rune_bg", acx, ly, ms * 1.3, ms * 1.3, V4(1, 1, 1, 0.85))
		local mark = ui.box(st.shake, ui.GEM_SPRITE[col], acx, ly, ms, ms)
		ui.pulse(mark, 1.06, 0.9 + i * 0.1)
		for _, side in ipairs(SIDES) do
			local dir = side == "player" and -1 or 1
			local sx = acx + dir * ux
			local U = spawn_unit(st.shake, side, s[side].squads[col], sx, ly, st.us, i * 0.25 + (side == "enemy" and 0.4 or 0))
			-- Runes on the inner side of the squad, below its centre
			U.rune_dir = -dir
			U.rune_x = sx - dir * (st.us * 0.5 + st.rune_size * 0.5 + 6)
			U.rune_y = ly - st.us * 0.28
			st.units[side][col] = U
		end
	end

	-- ---- turn bar: [face | HP + shield + moves]  [ YOUR TURN ]  [HP + shield + moves | face]
	local sw = cx1 - cx0
	local sy = st.strip_y
	ui.slice(st.root, "panel_dark", (cx0 + cx1) / 2, sy, sw, strip_h, V4(1, 1, 1, 0.92), 18)
	st.face_size = 62
	st.turn_w = math.min(200, sw * 0.28)
	local bar_w = (sw - st.turn_w) / 2 - st.face_size - 34
	for _, side in ipairs(SIDES) do
		local is_pl = side == "player"
		local dir = is_pl and 1 or -1
		local fx = is_pl and (cx0 + 8 + st.face_size / 2 + 4) or (cx1 - 8 - st.face_size / 2 - 4)
		local ring = ui.glow(ui.box(st.root, "glow", fx, sy, st.face_size * 1.7, st.face_size * 1.7, is_pl and ui.GOLD or ui.RED))
		gui.set_alpha(ring, 0)
		local face = ui.box(st.root, is_pl and s.player.face or s.enemy.face, fx, sy, st.face_size, st.face_size)
		st.faces[side] = { ring = ring, face = face, x = fx }
		local bx = fx + dir * (st.face_size / 2 + 10 + bar_w / 2)
		st.bars[side] = make_team_bar(side, bx, sy + 18, bar_w)
		st.orbs[side] = { x = bx - dir * (bar_w / 2 - 10), y = sy - 26, dir = dir, step = 22, size = 18 }
	end
	st.turn_pill = ui.slice(st.root, "btn_gold", (cx0 + cx1) / 2, sy, st.turn_w, 62, ui.WHITE, 18)
	st.turn_face = ui.box(st.turn_pill, s.player.face, -st.turn_w / 2 + 28, 2, 40, 40)
	st.turn_lbl = ui.text(st.turn_pill, "", 20, 3, 22, ui.WHITE)

	-- ---- board: halo, frame, tiles, clipped gems, veil
	st.halo = ui.glow(ui.box(st.root, "glow", st.board_cx, st.board_cy, st.board_size * 1.45, st.board_size * 1.45, tint(ui.GOLD, 0)))
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
	st.veil = ui.box(st.root, "square", st.board_cx, st.board_cy, st.board_size + 6, st.board_size + 6, V4(0.28, 0.02, 0.06, 0))

	-- Board input: Druid drag (swipe swaps mid-gesture, tap-tap selection on release)
	local hit = gui.new_box_node(V3(st.board_cx, st.board_cy, 0), V3(st.board_size, st.board_size, 0))
	gui.set_parent(hit, st.root)
	gui.set_visible(hit, false)
	local drag = ui.druid:new_drag(hit)
	drag.on_touch_start:subscribe(function(_, touch) M.touch_start(touch.x, touch.y) end)
	drag.on_drag:subscribe(function(_, _, _, tx, ty) M.touch_drag(tx, ty) end)
	drag.on_touch_end:subscribe(function(_, touch) M.touch_end(touch and touch.x, touch and touch.y) end)

	-- ---- boosters
	local bcx = is_land and (cx0 + cx1) / 2 or vw / 2
	local bwid = math.min(196, ((cx1 - cx0) - 40) / 3)
	local gap = bwid + 14
	for i, kind in ipairs(config.BOOSTER_ORDER) do
		local bx = bcx + (i - 2) * gap
		st.boost_pos[kind] = { x = bx, y = st.boost_y, w = bwid, h = 74 }
		ui.btn(st.root, "btn_dark", bx, st.boost_y, bwid, 74, i18n.t("BOOST_" .. kind), 20, function()
			M.on_booster_tap(kind)
		end, { icon = config.BOOSTERS[kind].sprite, icon_size = 52 })
	end

	st.hud = ui.pane(st.root, 0, 0)
	st.fx_layer = ui.pane(st.root, 0, 0)
	st.danger = ui.box(st.root, "edge_glow", vw / 2, vh / 2, vw * 1.05, vh * 1.05, V4(1, 0.12, 0.18, 0))

	-- Rebuilt after the fight ended: the losing army lies on the ground
	if s.status ~= "play" then
		local loser = s.status == "win" and "enemy" or "player"
		for _, col in ipairs(LANES) do fall_unit(loser, col, true) end
	end
	set_bars(true)
	M.refresh_hud()
	st.shimmer_t = 0

	if s.status == "play" and not s.intro_done and s.turn == "player" and s.stats.moves == 0 then
		s.intro_done = true
		M.intro()
	elseif #s.events > 0 then
		M.process() -- e.g. the revive event after a second chance
	else
		show_tutorial()
		if s.status == "play" and s.turn == "player" then poki.gameplay_start() end
	end
	-- Rebuilt (resize) after the fight already ended: make sure the result screen still shows
	if s.status ~= "play" and not app.popup then
		ui.after(0.4, function() app.on_battle_end(s.status == "win") end)
	end
end

-- ---------------------------------------------------------------- turn banner & intro
-- Full-width ribbon sweeping across the board: whose turn it is, with the portrait.
local function turn_banner(is_p, sub)
	local s = st.session
	local bw = math.min(st.app.vw, st.board_size + 220)
	local root = ui.pane(st.fx_layer, st.board_cx, st.board_cy)
	local col = is_p and V4(0.93, 0.68, 0.18, 0.95) or V4(0.72, 0.1, 0.18, 0.95)
	local band = ui.box(root, "band", 0, 0, bw, 150, col)
	gui.set_scale(band, V3(1, 0.05, 1))
	gui.animate(band, "scale", V3(1, 1, 1), gui.EASING_OUTBACK, 0.2)
	local dark = ui.box(root, "band", 0, 0, bw * 0.92, 112, V4(0.05, 0.05, 0.1, 0.55))
	gui.set_scale(dark, V3(1, 0.05, 1))
	gui.animate(dark, "scale", V3(1, 1, 1), gui.EASING_OUTBACK, 0.2)
	local grp = ui.pane(root, (is_p and -1 or 1) * bw * 0.7, 0)
	local face = ui.box(grp, is_p and s.player.face or s.enemy.face, -st.board_size * 0.3, 0, 96, 96)
	ui.text(grp, i18n.t(is_p and "YOUR_TURN" or "ENEMY_TURN"), 50, sub and 12 or 2, 58, is_p and ui.GOLD or ui.WHITE)
	if sub then ui.text(grp, sub, 50, -32, 22, ui.BONE) end
	gui.animate(grp, "position.x", 0, gui.EASING_OUTBACK, 0.3)
	ui.pop(face, 0.4, 1, 0.35, 0.1)
	ui.after(0.85, function()
		gui.animate(grp, "position.x", (is_p and 1 or -1) * bw * 0.8, gui.EASING_INQUAD, 0.2)
		gui.animate(band, "scale", V3(1, 0.02, 1), gui.EASING_INQUAD, 0.2)
		gui.animate(dark, "scale", V3(1, 0.02, 1), gui.EASING_INQUAD, 0.2, 0, function() gui.delete_node(root) end)
	end)
	audio.play(is_p and "turn_you" or "turn_enemy", 0.9)
	audio.play("whoosh", 0.45, is_p and 1.2 or 0.85)
end

local function moves_sub(who)
	return i18n.t("MOVES_FMT", { n = st.session[who].moves_left })
end

-- Fight intro: squads march in, "FIGHT!" + goal, then the first turn banner.
function M.intro()
	st.busy = true
	for _, side in ipairs(SIDES) do
		for i, col in ipairs(LANES) do
			local U = unit(side, col)
			local off = (side == "player" and -1 or 1) * (st.arena_w * 0.45)
			gui.set_position(U.holder, V3(U.home.x + off, U.home.y, 0))
			gui.animate(U.holder, "position", V3(U.home.x, U.home.y, 0), gui.EASING_OUTBACK, 0.45, 0.08 * i + (side == "enemy" and 0.12 or 0))
			ui.after(0.3 + 0.08 * i, function() ui.puff(st.fx_layer, U.home.x, U.home.y - st.us * 0.35, nil, st.us * 0.5) end)
		end
	end
	audio.play("whoosh", 0.7)
	ui.after(0.55, function()
		audio.play("hit", 0.8, 0.7)
		ui.shake_xy(st.shake, 8)
		ui.banner(st.fx_layer, i18n.t("FIGHT"), st.arena_cx, st.arena_cy + 18, 64, ui.GOLD, 0.55)
		local goal = ui.text(st.fx_layer, i18n.t("GOAL_HP"), st.arena_cx, st.arena_cy - 36, 22, ui.BONE)
		ui.fit(goal, st.arena_w - 40, 22)
		ui.fade_in(goal, 0.2)
		gui.animate(goal, "color.w", 0, gui.EASING_INQUAD, 0.3, 1.2, function() gui.delete_node(goal) end)
	end)
	ui.after(1.35, function()
		turn_banner(true, moves_sub("player"))
	end)
	ui.after(2.25, function()
		st.busy = false
		show_tutorial()
		if st.session.status == "play" then poki.gameplay_start() end
	end)
end

-- ---------------------------------------------------------------- combat FX
-- A hit lands on the enemy squad of the attacker's lane; damage goes to that side's shared HP.
local function hit_squad(side, col, ev, big, color)
	local U = unit(side, col)
	local d = st.disp[side]
	d.hp = d.hp - (ev.dealt or 0)
	d.shield = d.shield - (ev.blocked or 0)
	set_bars(false)
	if not U then return end
	local x, y = U.home.x, U.home.y
	local away = side == "enemy" and 1 or -1
	if not U.dead then
		gui.cancel_animations(U.holder, "position")
		gui.set_position(U.holder, V3(x + away * (big and 20 or 11), y, 0))
		gui.animate(U.holder, "position", V3(x, y, 0), gui.EASING_OUTBACK, 0.28)
		gui.cancel_animations(U.vis, "scale")
		gui.set_scale(U.vis, V3(U.flip * 1.16, 0.84, 1))
		gui.animate(U.vis, "scale", V3(U.flip, 1, 1), gui.EASING_OUTELASTIC, 0.5)
		ui.flash_hit(U.vis, V4(1, 0.3, 0.3, 1))
	end
	ui.burst(st.fx_layer, x, y, big and 12 or 7, color, st.us * 0.75, 24)
	ui.ring(st.fx_layer, x, y, st.us * (big and 1.9 or 1.35), color, 0.3)
	if (ev.blocked or 0) > 0 then
		ui.ring(st.fx_layer, x, y, st.us * 1.55, ui.BLUE, 0.32)
		ui.float_text(st.fx_layer, "-" .. ev.blocked, x - away * st.us * 0.55, y + st.us * 0.15, 20, ui.BLUE, 40)
	end
	if (ev.dealt or 0) > 0 or (ev.blocked or 0) == 0 then
		ui.float_text(st.fx_layer, "-" .. (ev.dealt or ev.dmg or 0), x - away * st.us * 0.2 + math.random(-8, 8), y + st.us * 0.45,
			big and 42 or 32, big and ui.GOLD or DMG_COLOR, 72)
	end
	if ev.crit then
		audio.play("crit")
		ui.float_text(st.fx_layer, i18n.t("CRIT_TAG"), x - away * st.us * 0.3, y + st.us * 0.9, 24, ui.GOLD, 40)
	end
	audio.play("hit", 0.9, big and 1.15 or 1.0)
end

local function strike_melee(ev, A, T, foe, big, col)
	local hx, hy = A.home.x, A.home.y
	local dir = ev.who == "player" and 1 or -1
	local tx, ty = T.home.x - dir * st.us * 0.62, T.home.y
	audio.play("dash")
	gui.cancel_animations(A.holder, "position")
	gui.set_position(A.holder, V3(hx, hy, 0))
	gui.animate(A.holder, "position", V3(tx, ty, 0), gui.EASING_INCUBIC, 0.16)
	gui.animate(A.holder, "scale", V3(1.18, 1.18, 1), gui.EASING_OUTQUAD, 0.16)
	ui.after(0.05, function() ui.puff(st.fx_layer, hx + (tx - hx) * 0.3, hy + (ty - hy) * 0.3, nil, 30) end)
	ui.after(0.16, function()
		audio.play("slash", 0.95, ev.crit and 1.15 or 1.0)
		local sp = ev.fx or "fx_slash"
		local sz = st.us * 1.25
		local sl = ui.glow(ui.box(st.fx_layer, sp, T.home.x - dir * 8, T.home.y, sz, sz, sp == "fx_slash" and col or ui.WHITE))
		gui.set_scale(sl, V3(dir * 0.65, 0.65, 1))
		gui.set_euler(sl, V3(0, 0, dir * -22))
		gui.animate(sl, "scale", V3(dir * 1.35, 1.35, 1), gui.EASING_OUTQUAD, 0.18)
		gui.animate(sl, "euler.z", dir * 32, gui.EASING_OUTQUAD, 0.18)
		gui.animate(sl, "color.w", 0, gui.EASING_INQUAD, 0.2, 0.04, function() gui.delete_node(sl) end)
		hit_squad(foe, ev.color, ev, big, col)
		ui.shake_xy(st.shake, big and 10 or 6)
	end)
	ui.after(0.24, function()
		gui.animate(A.holder, "position", V3(hx, hy, 0), gui.EASING_OUTQUAD, 0.18)
		gui.animate(A.holder, "scale", V3(1, 1, 1), gui.EASING_OUTQUAD, 0.18)
	end)
end

-- Arrows / bolts / spells fly from the squad into the enemy squad of the same lane.
local function strike_missile(ev, A, T, foe, big, col, magic)
	local hx, hy = A.home.x, A.home.y
	local tx, ty = T.home.x, T.home.y
	local dir = ev.who == "player" and 1 or -1
	audio.play(magic and "spell" or "arrow")
	gui.cancel_animations(A.holder, "position")
	gui.set_position(A.holder, V3(hx, hy, 0))
	if magic then
		gui.animate(A.holder, "position.y", hy + 14, gui.EASING_OUTQUAD, 0.12, 0, function()
			gui.animate(A.holder, "position.y", hy, gui.EASING_INQUAD, 0.16)
		end)
		ui.ring(st.fx_layer, hx, hy + 10, st.us * 1.2, col, 0.28)
	else
		gui.animate(A.holder, "position.x", hx - dir * 12, gui.EASING_OUTQUAD, 0.06, 0, function()
			gui.animate(A.holder, "position.x", hx, gui.EASING_OUTBACK, 0.16)
		end)
	end
	local per = magic and math.max(1, math.min(3, ev.units or 2)) or math.max(2, math.min(4, ev.units or 3))
	local fly = magic and 0.23 or 0.19
	for k = 1, per do
		ui.after((k - 1) * (magic and 0.065 or 0.045), function()
			local sy = hy + (k - (per + 1) / 2) * 14
			local sx = hx + dir * st.us * 0.3
			local ey = ty + (k - (per + 1) / 2) * 10
			local ang = math.deg(math.atan2(ey - sy, tx - sx))
			local w, h = magic and 66 or 64, magic and 48 or 32
			local proj = ui.glow(ui.box(st.fx_layer, ev.fx or (magic and "proj_spell" or "proj_arrow"), sx, sy, w, h, ui.WHITE))
			gui.set_euler(proj, V3(0, 0, ang))
			gui.animate(proj, "position", V3(tx, ey, 0), magic and gui.EASING_INOUTSINE or gui.EASING_LINEAR, fly)
			ui.after(fly * 0.45, function() ui.spark_dot(st.fx_layer, sx + (tx - sx) * 0.45, sy + (ey - sy) * 0.45, col, magic and 22 or 14, 0.2) end)
			ui.after(fly, function()
				gui.delete_node(proj)
				if k == 1 then hit_squad(foe, ev.color, ev, big, col)
				elseif magic then ui.ring(st.fx_layer, tx, ey, st.us * 1.1, col, 0.25)
				else ui.burst(st.fx_layer, tx + math.random(-14, 14), ey + math.random(-14, 14), 3, col, 36, 16) end
			end)
		end)
	end
	if big then ui.after(fly, function() ui.shake_xy(st.shake, 8) end) end
end

local function strike(ev)
	local side, foe = side_of(ev.who), foe_of(ev.who)
	local A, T = unit(side, ev.color), unit(foe, ev.color)
	local col = ui.GEM_COLOR[ev.color] or ui.RED
	local big = ev.crit or ev.kind == "skill"
	if not (A and T) then
		hit_squad(foe, ev.color, ev, big, col)
		return
	end
	if ev.style == "ranged" then strike_missile(ev, A, T, foe, big, col, false)
	elseif ev.style == "magic" then strike_missile(ev, A, T, foe, big, col, true)
	else strike_melee(ev, A, T, foe, big, col) end
end

-- Brief zoom punch on the arena (skills, victory).
local function zoom_punch(k)
	gui.cancel_animations(st.zoom, "scale")
	gui.set_scale(st.zoom, V3(k, k, 1))
	gui.animate(st.zoom, "scale", V3(1, 1, 1), gui.EASING_OUTBACK, 0.35)
end

-- Heal / shield: a glow on each own squad and the amount over the team bar.
local function support_fx(ev, color, sprite, field)
	local side = side_of(ev.who)
	for _, col in ipairs(LANES) do
		local U = unit(side, col)
		if U and not U.dead then
			ui.ring(st.fx_layer, U.home.x, U.home.y, st.us * 1.35, color, 0.36)
			if sprite then
				local ic = ui.box(st.fx_layer, sprite, U.home.x, U.home.y + 4, st.us * 0.5, st.us * 0.5, color)
				ui.pop(ic, 0.5, 1.2, 0.22)
				gui.animate(ic, "color.w", 0, gui.EASING_INQUAD, 0.25, 0.16, function() gui.delete_node(ic) end)
			else
				ui.burst(st.fx_layer, U.home.x, U.home.y, 5, color, st.us * 0.6, 20)
			end
		end
	end
	local b = st.bars[side]
	local v = ev.gained or ev.amount or 0 -- trait shields carry only `amount` (= the real gain)
	if v > 0 then ui.float_text(st.fx_layer, "+" .. v, b.x, b.y + 30, 26, color, 46) end
	ui.ring(st.fx_layer, st.faces[side].x, st.strip_y, 110, color, 0.36)
	local d = st.disp[side]
	d[field] = d[field] + (ev.gained or ev.amount or 0)
	set_bars(false)
end

-- Schedules one combat event at absolute time t; returns the time when it is finished.
local function schedule_effect(ev, t)
	local k = ev.kind
	if k == "attack" then
		at(t, function() strike(ev) end)
		return t + 0.42
	elseif k == "skill" then
		at(t, function()
			local c = ui.GEM_COLOR[ev.color] or ui.GOLD
			audio.play("combo", 0.8, 0.8)
			ui.flash(st.fx_layer, st.app.vw, st.app.vh, tint(c, 0.22), 0.3)
			zoom_punch(1.04)
			local A = unit(side_of(ev.who), ev.color)
			if A then
				ui.ring(st.fx_layer, A.home.x, A.home.y, st.us * 2.4, c, 0.45)
				local gl = ui.glow(ui.box(st.fx_layer, "glow", A.home.x, A.home.y, st.us * 2, st.us * 2, tint(c, 0.6)))
				gui.animate(gl, "color.w", 0, gui.EASING_INQUAD, 0.5, 0, function() gui.delete_node(gl) end)
				local ttl = i18n.t("SK_" .. ev.skill_id)
				local short = string.match(ttl, "^(.-)%s*%(") or ttl
				ui.banner(st.fx_layer, short, st.arena_cx, A.home.y + st.us * 0.55, 28, ui.GOLD, 0.5)
			end
		end)
		at(t + 0.15, function() strike(ev) end)
		return t + 0.7
	elseif k == "heal" then
		at(t, function()
			audio.play("heal")
			support_fx(ev, ui.GREEN, nil, "hp")
		end)
		return t + 0.3
	elseif k == "shield" then
		at(t, function()
			audio.play("shield")
			support_fx(ev, ui.BLUE, "icon_shield", "shield")
		end)
		return t + 0.3
	elseif k == "rune" then
		at(t, function()
			local U = unit(side_of(ev.who), ev.color)
			if U then
				local rx = U.rune_x + U.rune_dir * (ev.slot - 1) * st.rune_step
				ui.burst(st.fx_layer, rx, U.rune_y, 4, ui.GEM_COLOR[ev.rune_color] or ui.GOLD, 28, 16)
				ui.ring(st.fx_layer, rx, U.rune_y, 46, ui.GEM_COLOR[ev.rune_color] or ui.GOLD, 0.25)
			end
		end)
		return t + 0.1
	elseif k == "status" then
		at(t, function()
			local side = side_of(ev.who)
			local key = ev.stype == "burn" and "BURN_TAG" or (ev.stype == "poison" and "POISON_TAG" or "FREEZE_TAG")
			local col = ev.stype == "burn" and ui.RED or (ev.stype == "poison" and ui.GREEN or ui.DIAMOND)
			local fx = st.faces[side].x
			local ic = ui.box(st.fx_layer, "icon_" .. ev.stype, fx, st.strip_y, 70, 70)
			ui.pop(ic, 0.3, 1.2, 0.25)
			gui.animate(ic, "color.w", 0, gui.EASING_INQUAD, 0.3, 0.4, function() gui.delete_node(ic) end)
			ui.float_text(st.fx_layer, i18n.t(key), st.bars[side].x, st.strip_y + 40, 22, col, 40)
			for _, c2 in ipairs(LANES) do
				local U = unit(side, c2)
				if U then ui.ring(st.fx_layer, U.home.x, U.home.y, st.us * 1.2, col, 0.3) end
			end
		end)
		return t + 0.25
	elseif k == "dot" then
		at(t, function()
			local side = side_of(ev.who)
			local col = ev.dtype == "poison" and ui.GREEN or ui.RED
			local b = st.bars[side]
			ui.ring(st.fx_layer, st.faces[side].x, st.strip_y, 100, col, 0.3)
			ui.burst(st.fx_layer, b.x, b.y, 6, col, 50, 18)
			ui.float_text(st.fx_layer, i18n.t(ev.dtype == "poison" and "POISON_TAG" or "BURN_TAG") .. " -" .. ev.dmg, b.x, b.y + 30, 22, col, 46)
			for _, c2 in ipairs(LANES) do
				local U = unit(side, c2)
				if U then ui.flash_hit(U.vis, tint(col, 1)) end
			end
			local d = st.disp[side]
			d.hp = d.hp - (ev.dealt or 0)
			d.shield = d.shield - (ev.blocked or 0)
			set_bars(false)
		end)
		return t + 0.45
	elseif k == "frozen" then
		at(t, function()
			local side = side_of(ev.who)
			local o = st.orbs[side]
			audio.play("shield", 0.6, 1.4)
			ui.ring(st.fx_layer, st.faces[side].x, st.strip_y, 130, ui.DIAMOND, 0.45)
			ui.ring(st.fx_layer, o.x + o.dir * 30, o.y, 90, ui.DIAMOND, 0.4)
			ui.float_text(st.fx_layer, i18n.t("FROZEN_FMT", { n = ev.lost or 1 }), st.bars[side].x, st.strip_y + 40, 24, ui.DIAMOND, 52)
		end)
		return t + 0.4
	elseif k == "turn" then
		at(t, function()
			local is_p = ev.turn == "player"
			turn_banner(is_p, moves_sub(is_p and "player" or "enemy"))
			M.refresh_hud()
		end)
		return t + 1.1
	elseif k == "extra_move" then
		at(t, function()
			audio.play("upgrade")
			local o = st.orbs.player
			ui.float_text(st.fx_layer, i18n.t("BOOST_extra_move"), o.x + 60, o.y + 20, 24, ui.GOLD, 40)
			ui.ring(st.fx_layer, o.x + 30, o.y, 120, ui.GOLD, 0.35)
			M.refresh_hud()
		end)
		return t + 0.2
	elseif k == "revive" then
		at(t, function()
			audio.play("levelup")
			for _, col in ipairs(LANES) do rise_unit("player", col) end
			ui.ring(st.fx_layer, st.faces.player.x, st.strip_y, 220, ui.GREEN, 0.6)
			sync_disp()
		end)
		return t + 0.5
	elseif k == "win" or k == "lose" then
		local won = k == "win"
		at(t + 0.2, function()
			local loser = won and "enemy" or "player"
			for i, col in ipairs(LANES) do fall_unit(loser, col, false, (i - 1) * 0.16) end
			gui.animate(st.faces[loser].face, "color.w", 0.25, gui.EASING_INQUAD, 0.5, 0.2)
			ui.ring(st.fx_layer, st.faces[loser].x, st.strip_y, 220, won and ui.GOLD or ui.RED, 0.6)
		end)
		at(t + 0.75, function()
			audio.play(won and "win" or "lose")
			ui.shake_xy(st.shake, 16)
			zoom_punch(1.06)
			if won then
				ui.banner(st.fx_layer, i18n.t("VICTORY"), st.arena_cx, st.arena_cy, 72, ui.GOLD, 0.9)
				ui.confetti(st.fx_layer, st.arena_cx, st.app.vh + 40, st.app.vw, 40)
			else
				ui.banner(st.fx_layer, i18n.t("DEFEAT"), st.arena_cx, st.arena_cy, 64, ui.RED, 0.9)
			end
		end)
		at(t + 1.9, function() st.app.on_battle_end(won) end)
		return t + 2.0
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

-- Enemy move preview: a red claw slides from one gem to the other.
local function telegraph(ev)
	local x1, y1 = cell_pos(ev.r1, ev.c1)
	local x2, y2 = cell_pos(ev.r2, ev.c2)
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
	local hand = ui.box(st.fx_layer, "icon_hand", x1 + 14, y1 - 20, 58, 58, V4(1, 0.45, 0.45, 1))
	gui.animate(hand, "position", V3(x2 + 14, y2 - 20, 0), gui.EASING_INOUTQUAD, 0.26)
	gui.animate(hand, "color.w", 0, gui.EASING_INQUAD, 0.12, 0.3, function() gui.delete_node(hand) end)
end

local COMBO_KEYS = { [2] = "COMBO_2", [3] = "COMBO_3", [4] = "COMBO_4" }

local function anim_step(ev, step)
	local who = ev.who or "player"
	local side = side_of(who)
	local cascade = step.cascade or 1
	audio.play("match", 0.9, 1.0 + (cascade - 1) * 0.14)
	if cascade >= 2 then
		local key = COMBO_KEYS[math.min(4, cascade)]
		ui.banner(st.fx_layer, i18n.t(key, { n = cascade }), st.board_cx, st.board_cy + st.cell * 0.6, 40 + math.min(4, cascade) * 6, ui.GOLD, 0.35)
		ui.shake_xy(st.shake, 3 + cascade * 2)
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
	-- Energy orbs fly into the squads that will use them (green / blue: into the team HP bar)
	for col, pos in pairs(rep) do
		local tx, ty
		local U = LANE_OF[col] and unit(side, col)
		if U then
			tx, ty = U.home.x, U.home.y
		else
			tx, ty = st.bars[side].x, st.bars[side].y
		end
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
	clear_target()
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
					t0 = t0 + 0.36
				end
				at(t0, function()
					anim_swap(ev)
					-- the spent move orb flashes
					local o = st.orbs[ev.who]
					local f = s[ev.who]
					if o and f then
						ui.ring(st.fx_layer, o.x + o.dir * f.moves_left * o.step, o.y, 54, ev.who == "player" and ui.GOLD or ui.RED, 0.3)
					end
				end)
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
	else
		clear_target()
	end
end

local function try_swap(r1, c1, r2, c2)
	set_selected(nil)
	clear_target()
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
	if g then show_target(g.color) end
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
	if not d or d.done or not can_act() then clear_target(); return end
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
		if g then show_target(g.color) end
	end
	if not st.sel then clear_target() end
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
