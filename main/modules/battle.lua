-- Turn-based Match-3 combat session with 2-crystal Rune Skills & DoT/Freeze statuses (pure Lua).
local config = require "main.modules.config"
local squads = require "main.modules.squads"
local board = require "main.modules.board"
local ai = require "main.modules.ai"
local rng = require "main.modules.rng"

local M = {}

local function build_fighter_squads(slot_defs)
	local out = {}
	for _, col in ipairs(config.ATTACK_COLORS) do
		local def = slot_defs[col]
		local info = squads.get(def.id)
		local lvl = def.level or def.lvl or 1
		out[col] = {
			id = def.id,
			color = col,
			level = lvl,
			power = squads.power(def.id, lvl),
			skill_power = squads.skill_power(def.id, lvl),
			trait = info and info.trait or "none",
			sprite = info and info.sprite or "squad_red_militia",
			style = info and info.style or "melee",
			fx = info and info.fx or "fx_slash",
			units = info and info.units or 1,
			runes = info and info.runes or { col, col },
			rune_filled = { false, false },
			skill = info and info.skill,
		}
	end
	return out
end

function M.new(opts)
	local r = rng.new(opts.seed or 42)
	local b = board.new(r, opts.board_cfg)
	local relics = opts.relics or {}
	b.cross_rocket = relics.cross_rocket == true
	if relics.start_bomb then
		local placed = false
		for _, p in ipairs({ { 4, 4 }, { 3, 4 }, { 4, 3 }, { 5, 4 }, { 4, 5 } }) do
			if not placed and board.place_special(b, p[1], p[2], "bomb") then placed = true end
		end
	end
	local p_hp = opts.player_hp or config.BASE_HP
	local waves = opts.waves
	local first = waves and waves[1] or nil
	local e_hp = first and first.hp or opts.enemy_hp or 60
	local e_moves = first and first.moves or opts.enemy_moves or 1
	local e_squads = (first and first.squads) or opts.enemy_squads
	local s = {
		rng = r,
		board = b,
		board_cfg = opts.board_cfg,
		arena = opts.arena or "arena_bg",
		mode = opts.mode or "campaign",
		stage_id = opts.stage_id or 1,
		waves = waves,
		wave_index = first and 1 or nil,
		survival_step = opts.survival_step,
		survival_total = opts.survival_total,
		tutorial = opts.tutorial or false,
		tutorial_step = opts.tutorial and 1 or 0,
		turn = "player",
		turn_num = 1,
		status = "play",
		events = {},
		-- Player-side stats for quests / results screen
		stats = {
			gems = { red = 0, yellow = 0, purple = 0, green = 0, blue = 0 },
			max_combo = 0,
			combos = 0,
			skills = 0,
			specials = 0,
			damage = 0,
			boosters = 0,
			moves = 0,
		},
		boosters = {
			shuffle = opts.boosters and opts.boosters.shuffle or 0,
			hammer = opts.boosters and opts.boosters.hammer or 0,
			extra_move = opts.boosters and opts.boosters.extra_move or 0,
		},
		ult = {
			charge = math.max(0, math.min(config.ULT.max, (opts.ult_charge or 0) + (relics.fury_start and 50 or 0))),
			max = config.ULT.max,
		},
		relics = relics,
		player = {
			face = "face_hero",
			hp = p_hp,
			max_hp = p_hp,
			shield = 0,
			max_shield = math.floor(p_hp * config.SHIELD_CAP_RATIO * (relics.iron_skin and 1.25 or 1)),
			moves_left = opts.player_moves or config.START_MOVES,
			max_moves = opts.player_moves or config.START_MOVES,
			heal_power = opts.heal_power or math.floor(p_hp * config.HEAL_RATIO + 0.5),
			shield_power = opts.shield_power or math.floor(p_hp * config.SHIELD_RATIO + 0.5),
			squads = build_fighter_squads(opts.player_squads),
			statuses = { burn = nil, poison = nil, freeze = 0 },
		},
		enemy = {
			name = opts.enemy_name or "",
			name_key = (first and first.name_key) or opts.enemy_name_key,
			face = (first and first.face) or opts.enemy_face or "face_goblin",
			hp = e_hp,
			max_hp = e_hp,
			shield = 0,
			max_shield = math.floor(e_hp * config.SHIELD_CAP_RATIO),
			moves_left = e_moves,
			max_moves = e_moves,
			difficulty = opts.enemy_diff or 1,
			boss = opts.enemy_boss == true,
			elite = opts.enemy_elite == true,
			heal_power = math.max(6, math.floor(e_hp * config.HEAL_RATIO + 0.5)),
			shield_power = math.max(6, math.floor(e_hp * config.SHIELD_RATIO + 0.5)),
			squads = build_fighter_squads(e_squads),
			statuses = { burn = nil, poison = nil, freeze = 0 },
		},
	}
	-- Boss/elite bombs hit hard (25% / 15% of the commander's max HP); regular curses 7%.
	s.curse_ratio = s.enemy.boss and 0.25 or (s.enemy.elite and 0.15 or 0.07)
	return s
end

local function push(s, ev)
	if s.cur_step and not ev.step then ev.step = s.cur_step end
	s.events[#s.events + 1] = ev
	if ev.who == "player" and s.stats then
		if (ev.kind == "attack" or ev.kind == "skill") and ev.dealt then
			s.stats.damage = s.stats.damage + ev.dealt
		end
		if ev.kind == "skill" then s.stats.skills = s.stats.skills + 1 end
	end
end

-- Campaign boss hook: grant one relic for the rest of this battle only.
function M.grant_relic(s, id)
	if not (s and config.RELIC_BY_ID[id]) then return false end
	s.relics = s.relics or {}
	s.relics[id] = true
	if id == "iron_skin" then
		s.player.max_shield = math.floor(s.player.max_shield * 1.25)
	elseif id == "fury_start" then
		s.ult.charge = math.min(s.ult.max, s.ult.charge + 50)
	elseif id == "cross_rocket" then
		s.board.cross_rocket = true
	elseif id == "start_bomb" then
		for _, p in ipairs({ { 4, 4 }, { 3, 4 }, { 4, 3 }, { 5, 4 }, { 4, 5 } }) do
			if board.place_special(s.board, p[1], p[2], "bomb") then break end
		end
	end
	return true
end

local function track_steps(s, who, steps)
	if who ~= "player" then return end
	local st = s.stats
	st.moves = st.moves + 1
	for _, step in ipairs(steps) do
		for col, cnt in pairs(step.counts) do
			if st.gems[col] then st.gems[col] = st.gems[col] + cnt end
		end
		st.specials = st.specials + #(step.specials or {})
		if step.cascade > st.max_combo then st.max_combo = step.cascade end
	end
	if #steps >= 2 then st.combos = st.combos + 1 end
end

local function fury_mult(s)
	if s.turn_num < config.FURY_TURN then return 1 end
	return 1 + 0.2 * (s.turn_num - config.FURY_TURN + 1)
end

local function apply_damage(target, dmg, pierce_ratio)
	local to_shield = math.floor(dmg * (1 - (pierce_ratio or 0)) + 0.5)
	local blocked = math.min(target.shield, to_shield)
	target.shield = target.shield - blocked
	local rest = math.max(0, dmg - blocked)
	local dealt = math.min(target.hp, rest)
	target.hp = target.hp - dealt
	return dealt, blocked
end

local function next_wave(s)
	if not (s.waves and s.wave_index and s.wave_index < #s.waves) then return false end
	s.wave_index = s.wave_index + 1
	local w = s.waves[s.wave_index]
	s.enemy.hp = w.hp
	s.enemy.max_hp = w.hp
	s.enemy.max_shield = math.floor(w.hp * config.SHIELD_CAP_RATIO)
	s.enemy.shield = 0
	s.enemy.moves_left = w.moves
	s.enemy.max_moves = w.moves
	if w.squads then s.enemy.squads = build_fighter_squads(w.squads) end
	s.enemy.statuses = { burn = nil, poison = nil, freeze = 0 }
	-- Reinforcements arrive; the board (and every prepared special) stays untouched.
	local heal = math.min(s.player.max_hp - s.player.hp, math.floor(s.player.max_hp * 0.05))
	s.player.hp = s.player.hp + heal
	local sh = math.min(math.max(0, s.player.max_shield - s.player.shield), math.floor(s.player.max_shield * 0.15))
	s.player.shield = s.player.shield + sh
	s.player.moves_left = s.player.max_moves
	s.turn = "player"
	push(s, { kind = "wave", wave = s.wave_index, total = #s.waves, heal = heal, shield = sh })
	return true
end

local function check_end(s)
	if s.enemy.hp <= 0 then
		if next_wave(s) then return true end
		s.enemy.hp = 0
		s.status = "win"
		push(s, { kind = "win" })
		return true
	elseif s.player.hp <= 0 then
		s.player.hp = 0
		s.status = "lose"
		push(s, { kind = "lose" })
		return true
	end
	return false
end

local function trigger_skill(s, actor, target, who, col, sq)
	local sk = sq.skill
	if not sk then return end
	local fm = fury_mult(s)
	local dmg = math.max(1, math.floor(sq.skill_power * fm + 0.5))
	if actor.statuses.weak and actor.statuses.weak.turns > 0 then
		dmg = math.max(1, math.floor(dmg * (actor.statuses.weak.ratio or 0.75) + 0.5))
	end
	local pierce = sk.pierce or 0
	local eff = sk.effect

	if eff == "fury_heal" and actor.hp < actor.max_hp * 0.6 then
		dmg = math.floor(dmg * 1.45 + 0.5)
	elseif eff == "shield_slam" then
		dmg = dmg + math.min(dmg, math.floor(actor.shield * (sk.val or 0.5) + 0.5))
	elseif eff == "crush" and target.shield > 0 then
		dmg = math.floor(dmg * (sk.val or 1.6) + 0.5)
	elseif eff == "execute" and target.hp < target.max_hp * 0.5 then
		dmg = math.floor(dmg * (sk.val or 1.65) + 0.5)
	elseif eff == "shatter" and target.shield > 0 then
		local broken = math.max(1, math.floor(target.shield * (sk.val or 0.5)))
		target.shield = math.max(0, target.shield - broken)
	end

	if who == "player" and s.relics and s.relics.bloodlust then
		dmg = math.max(1, math.floor(dmg * 1.12 + 0.5))
	end
	local dealt, blocked = apply_damage(target, dmg, pierce)
	push(s, {
		kind = "skill",
		who = who,
		color = col,
		level = sq.level,
		skill_id = sk.id,
		style = sq.style,
		fx = sk.fx or sq.fx,
		units = math.max(2, sq.units or 2),
		dmg = dmg,
		dealt = dealt,
		blocked = blocked,
		effect = eff,
	})

	if eff == "shield" or eff == "pierce_shield" then
		local g = math.min(actor.max_shield - actor.shield, sk.val or 6)
		if g > 0 then
			actor.shield = actor.shield + g
			push(s, { kind = "shield", who = who, amount = g, gained = g })
		end
	elseif eff == "shield_slam" then
		local g = math.min(actor.max_shield - actor.shield, 5)
		if g > 0 then
			actor.shield = actor.shield + g
			push(s, { kind = "shield", who = who, amount = g, gained = g })
		end
	elseif eff == "heal" then
		local g = math.min(actor.max_hp - actor.hp, sk.val or 8)
		if g > 0 then
			actor.hp = actor.hp + g
			push(s, { kind = "heal", who = who, amount = g, gained = g })
		end
	elseif (eff == "lifesteal" or eff == "fury_heal") and dealt > 0 then
		local h = math.max(1, math.floor(dealt * (sk.val or 0.35)))
		local g = math.min(actor.max_hp - actor.hp, h)
		if g > 0 then
			actor.hp = actor.hp + g
			push(s, { kind = "heal", who = who, amount = g, gained = g })
		end
	elseif eff == "burn" then
		target.statuses.burn = { dmg = sk.val or 6, turns = sk.dur or 2 }
		push(s, { kind = "status", who = who == "player" and "enemy" or "player", stype = "burn", val = target.statuses.burn.dmg })
	elseif eff == "poison" then
		target.statuses.poison = { dmg = sk.val or 7, turns = sk.dur or 3 }
		push(s, { kind = "status", who = who == "player" and "enemy" or "player", stype = "poison", val = target.statuses.poison.dmg })
	elseif eff == "cleanse_burn" then
		local cleared = actor.statuses.burn ~= nil or actor.statuses.poison ~= nil or actor.statuses.weak ~= nil or (actor.statuses.freeze or 0) > 0
		actor.statuses.burn = nil
		actor.statuses.poison = nil
		actor.statuses.weak = nil
		actor.statuses.freeze = 0
		if cleared then
			push(s, { kind = "status", who = who, stype = "cleanse", val = 1 })
		end
		target.statuses.burn = { dmg = sk.val or 7, turns = sk.dur or 2 }
		push(s, { kind = "status", who = who == "player" and "enemy" or "player", stype = "burn", val = target.statuses.burn.dmg })
	elseif eff == "rally_charge" then
		local g = math.min(actor.max_hp - actor.hp, sk.val or 9)
		if g > 0 then
			actor.hp = actor.hp + g
			push(s, { kind = "heal", who = who, amount = g, gained = g })
		end
		for _, oc in ipairs(config.ATTACK_COLORS) do
			if oc ~= col then
				local osq = actor.squads[oc]
				if osq and osq.rune_filled then
					for slot = 1, 2 do
						if not osq.rune_filled[slot] then
							osq.rune_filled[slot] = true
							push(s, { kind = "rune", who = who, color = oc, slot = slot, rune_color = osq.runes and osq.runes[slot] or oc })
							break
						end
					end
				end
			end
		end
	elseif eff == "hex" then
		target.statuses.poison = { dmg = sk.val or 6, turns = sk.dur or 3 }
		target.statuses.weak = { ratio = 0.75, turns = 2 }
		local tw = who == "player" and "enemy" or "player"
		push(s, { kind = "status", who = tw, stype = "poison", val = target.statuses.poison.dmg })
		push(s, { kind = "status", who = tw, stype = "weak", val = 25 })
	elseif eff == "freeze" then
		target.statuses.freeze = math.min(1, (target.statuses.freeze or 0) + (sk.val or 1))
		push(s, { kind = "status", who = who == "player" and "enemy" or "player", stype = "freeze", val = target.statuses.freeze })
		local frozen = board.freeze_random(s.board, s.rng, 1)
		if #frozen > 0 then
			push(s, { kind = "board_freeze", cells = frozen })
		end
	end
end

local function charge_runes(s, actor, target, who, col_counts)
	for _, sq_col in ipairs(config.ATTACK_COLORS) do
		local sq = actor.squads[sq_col]
		if sq and sq.runes and sq.skill and target.hp > 0 then
			for gem_col, cnt in pairs(col_counts) do
				if cnt > 0 then
					local fills = cnt >= 5 and 2 or 1
					for _ = 1, fills do
						for slot = 1, 2 do
							if not sq.rune_filled[slot] and sq.runes[slot] == gem_col then
								sq.rune_filled[slot] = true
								push(s, { kind = "rune", who = who, color = sq_col, slot = slot, rune_color = gem_col })
								break
							end
						end
						if sq.rune_filled[1] and sq.rune_filled[2] then
							sq.rune_filled[1] = false
							sq.rune_filled[2] = false
							trigger_skill(s, actor, target, who, sq_col, sq)
							if target.hp <= 0 then return end
						end
					end
				end
			end
		end
	end
end

local function apply_cascade_effects(s, actor, target, who, steps)
	local fm = fury_mult(s)
	track_steps(s, who, steps)
	for step_idx, step in ipairs(steps) do
		s.cur_step = step_idx
		local c_mult = (1 + 0.25 * (step.cascade - 1)) * fm
		for _, col in ipairs(config.ATTACK_COLORS) do
			local cnt = step.counts[col] or 0
			if cnt > 0 and target.hp > 0 then
				local sq = actor.squads[col]
				local gem_scale = cnt / 3
				local dmg = math.max(1, math.floor(sq.power * gem_scale * c_mult + 0.5))
				if actor.statuses.weak and actor.statuses.weak.turns > 0 then
					dmg = math.max(1, math.floor(dmg * (actor.statuses.weak.ratio or 0.75) + 0.5))
				end
				local pierce = 0
				local crit = false
				if sq.trait == "crit" and s.rng:float() < 0.25 then
					dmg = math.floor(dmg * 1.5 + 0.5)
					crit = true
				elseif sq.trait == "fury" and actor.hp < actor.max_hp * 0.5 then
					dmg = math.floor(dmg * 1.35 + 0.5)
				elseif sq.trait == "pierce" then
					pierce = 0.5
				elseif sq.trait == "crush" and target.shield > 0 then
					dmg = math.floor(dmg * 1.25 + 0.5)
				end
				if who == "player" and s.relics and s.relics.bloodlust then
					dmg = math.max(1, math.floor(dmg * 1.12 + 0.5))
				end
				local dealt, blocked = apply_damage(target, dmg, pierce)
				push(s, {
					kind = "attack",
					who = who,
					color = col,
					level = sq.level,
					dmg = dmg,
					dealt = dealt,
					blocked = blocked,
					crit = crit,
					cascade = step.cascade,
					style = sq.style,
					fx = sq.fx,
					units = sq.units,
					gems = cnt,
				})
				if sq.trait == "bastion" then
					local gain = math.min(actor.max_shield - actor.shield, 4)
					if gain > 0 then
						actor.shield = actor.shield + gain
						push(s, { kind = "shield", who = who, amount = gain })
					end
				elseif sq.trait == "drain" and dealt > 0 then
					local heal = math.max(1, math.floor(dealt * 0.25))
					local gained = math.min(actor.max_hp - actor.hp, heal)
					if gained > 0 then
						actor.hp = actor.hp + gained
						push(s, { kind = "heal", who = who, amount = gained })
					end
				end
			end
		end

		local g_cnt = step.counts.green or 0
		if g_cnt > 0 then
			local amt = math.max(1, math.floor(actor.heal_power * (g_cnt / 3) * (1 + 0.2 * (step.cascade - 1)) + 0.5))
			local gained = math.min(actor.max_hp - actor.hp, amt)
			actor.hp = actor.hp + gained
			push(s, { kind = "heal", who = who, amount = amt, gained = gained })
			if who == "player" and s.relics and s.relics.green_shield then
				local sg = math.min(actor.max_shield - actor.shield, math.floor(amt * 0.5 + 0.5))
				if sg > 0 then
					actor.shield = actor.shield + sg
					push(s, { kind = "shield", who = who, amount = sg, gained = sg })
				end
			end
		end

		local b_cnt = step.counts.blue or 0
		if b_cnt > 0 then
			local amt = math.max(1, math.floor(actor.shield_power * (b_cnt / 3) * (1 + 0.2 * (step.cascade - 1)) + 0.5))
			local gained = math.min(actor.max_shield - actor.shield, amt)
			actor.shield = actor.shield + gained
			push(s, { kind = "shield", who = who, amount = amt, gained = gained })
		end

	-- Commander rage: large clusters and prisms charge the ultimate.
		if who == "player" and s.ult then
			local total = 0
			for _, col in ipairs(config.COLORS) do total = total + (step.counts[col] or 0) end
			if total >= 6 then
				s.ult.charge = math.min(s.ult.max, s.ult.charge + config.ULT.cluster_charge + math.max(0, total - 6) * 2)
			end
			for _, sp in ipairs(step.specials or {}) do
				if sp.special == "prism" then
					s.ult.charge = math.min(s.ult.max, s.ult.charge + config.ULT.prism_charge)
				end
			end
		end

		-- Feed crystal runes across all 3 squads & trigger Special Skills when 2/2 ready
		charge_runes(s, actor, target, who, step.counts)
		if step.stones_broken and #step.stones_broken > 0 then
			local g = math.min(actor.max_shield - actor.shield, 4 * #step.stones_broken)
			if g > 0 then
				actor.shield = actor.shield + g
				push(s, { kind = "shield", who = who, amount = g, gained = g })
			end
		end
		if (step.curses_cleared or 0) > 0 and target.hp > 0 then
			local cdmg = math.max(6, math.floor(target.max_hp * 0.06 + 0.5)) * step.curses_cleared
			local dealt, blocked = apply_damage(target, cdmg, 0.5)
			push(s, { kind = "curse_clear", who = who, count = step.curses_cleared, dmg = cdmg, dealt = dealt, blocked = blocked, cells = step.curse_cells })
		end
		if target.hp <= 0 then return end
	end
end

local function apply_effects(s, actor, target, who, steps)
	apply_cascade_effects(s, actor, target, who, steps)
	s.cur_step = nil
end

local function begin_turn(s, next_who)
	if next_who == "player" then s.turn_num = s.turn_num + 1 end
	s.turn = next_who
	local actor = next_who == "player" and s.player or s.enemy
	local st_map = actor.statuses

	-- Tick Burn & Poison at start of turn
	for _, key in ipairs({ "burn", "poison" }) do
		local st = st_map[key]
		if st and st.turns > 0 then
			local pierce = key == "poison" and 1.0 or 0.0
			local dealt, blocked = apply_damage(actor, st.dmg, pierce)
			push(s, { kind = "dot", who = next_who, dtype = key, dmg = st.dmg, dealt = dealt, blocked = blocked })
			st.turns = st.turns - 1
			if st.turns <= 0 then st_map[key] = nil end
			if check_end(s) then return end
		end
	end

	local freeze = st_map.freeze or 0
	st_map.freeze = 0
	-- Freeze removes moves but always leaves at least one (no skipped turns).
	actor.moves_left = math.max(1, actor.max_moves - freeze)
	-- Relic: +1 move on every odd round.
	if next_who == "player" and s.relics and s.relics.odd_move and s.turn_num % 2 == 1 then
		actor.moves_left = math.min(config.MAX_MOVES, actor.moves_left + 1)
	end
	push(s, { kind = "turn", turn = next_who, turn_num = s.turn_num, freeze = freeze })
	if freeze > 0 then
		push(s, { kind = "frozen", who = next_who, lost = actor.max_moves - actor.moves_left })
	end
end

function M.player_tap(s, r, c)
	if s.status ~= "play" or s.turn ~= "player" then return false end
	local steps, shuffled = board.resolve_tap(s.board, r, c)
	if not steps then return false end

	if s.tutorial and s.tutorial_step > 0 then
		s.tutorial_step = s.tutorial_step + 1
	end
	push(s, { kind = "blast", who = "player", r = r, c = c, steps = steps, shuffled = shuffled })
	apply_effects(s, s.player, s.enemy, "player", steps)

	s.player.moves_left = math.max(0, s.player.moves_left - 1)
	if check_end(s) then return true end

	if s.player.moves_left == 0 then
		if s.player.statuses.weak then
			s.player.statuses.weak.turns = s.player.statuses.weak.turns - 1
			if s.player.statuses.weak.turns <= 0 then s.player.statuses.weak = nil end
		end
		local ct = board.tick_curses(s.board)
		if #ct.exploded > 0 then
			local bdmg = math.max(5, math.floor(s.player.max_hp * (s.curse_ratio or 0.07) + 0.5)) * #ct.exploded
			local dealt, blocked = apply_damage(s.player, bdmg, 0)
			push(s, { kind = "curse_blast", cells = ct.exploded, dmg = bdmg, dealt = dealt, blocked = blocked })
			if check_end(s) then return true end
		end
		if #ct.remaining > 0 then
			push(s, { kind = "curse_tick", cells = ct.remaining })
		end
		begin_turn(s, "enemy")
	end
	return true
end

function M.player_swap(s, r1, c1, r2, c2)
	if config.is_blast_mode() then
		return M.player_tap(s, r1, c1)
	end
	if s.status ~= "play" or s.turn ~= "player" then return false end
	local steps, shuffled = board.resolve_swap(s.board, r1, c1, r2, c2)
	if not steps then return false end

	if s.tutorial and s.tutorial_step > 0 then
		s.tutorial_step = s.tutorial_step + 1
	end
	push(s, { kind = "swap", who = "player", r1 = r1, c1 = c1, r2 = r2, c2 = c2, steps = steps, shuffled = shuffled })
	apply_effects(s, s.player, s.enemy, "player", steps)

	s.player.moves_left = math.max(0, s.player.moves_left - 1)
	if check_end(s) then return true end

	if s.player.moves_left == 0 then
		if s.player.statuses.weak then
			s.player.statuses.weak.turns = s.player.statuses.weak.turns - 1
			if s.player.statuses.weak.turns <= 0 then s.player.statuses.weak = nil end
		end
		local ct = board.tick_curses(s.board)
		if #ct.exploded > 0 then
			local bdmg = math.max(5, math.floor(s.player.max_hp * (s.curse_ratio or 0.07) + 0.5)) * #ct.exploded
			local dealt, blocked = apply_damage(s.player, bdmg, 0)
			push(s, { kind = "curse_blast", cells = ct.exploded, dmg = bdmg, dealt = dealt, blocked = blocked })
			if check_end(s) then return true end
		end
		if #ct.remaining > 0 then
			push(s, { kind = "curse_tick", cells = ct.remaining })
		end
		begin_turn(s, "enemy")
	end
	return true
end

function M.step_enemy(s)
	if s.status ~= "play" or s.turn ~= "enemy" then return false end
	-- "Wrath of the Vanguard" stuns the enemy for a full turn.
	if s.enemy.statuses.stun then
		s.enemy.statuses.stun = nil
		s.enemy.moves_left = 0
		push(s, { kind = "stunned", who = "enemy" })
		begin_turn(s, "player")
		return true
	end
	local m = ai.pick_move(s.board, s.enemy, s.enemy.difficulty, s.rng)
	if not m then
		board.shuffle(s.board)
		push(s, { kind = "shuffle" })
		m = ai.pick_move(s.board, s.enemy, s.enemy.difficulty, s.rng)
	end
	if m then
		if config.is_blast_mode() then
			local tr, tc = m.r or m.r1, m.c or m.c1
			local steps, shuffled = board.resolve_tap(s.board, tr, tc)
			if steps then
				push(s, { kind = "blast", who = "enemy", r = tr, c = tc, steps = steps, shuffled = shuffled })
				apply_effects(s, s.enemy, s.player, "enemy", steps)
			end
		else
			local steps, shuffled = board.resolve_swap(s.board, m.r1, m.c1, m.r2, m.c2)
			if steps then
				push(s, { kind = "swap", who = "enemy", r1 = m.r1, c1 = m.c1, r2 = m.r2, c2 = m.c2, steps = steps, shuffled = shuffled })
				apply_effects(s, s.enemy, s.player, "enemy", steps)
			end
		end
	end
	s.enemy.moves_left = math.max(0, s.enemy.moves_left - 1)
	if check_end(s) then return true end

	if s.enemy.moves_left == 0 then
		if s.enemy.statuses.weak then
			s.enemy.statuses.weak.turns = s.enemy.statuses.weak.turns - 1
			if s.enemy.statuses.weak.turns <= 0 then s.enemy.statuses.weak = nil end
		end
		begin_turn(s, "player")
		if s.status == "play" and s.board_cfg then
			if s.board_cfg.freeze_chance and s.rng:float() < s.board_cfg.freeze_chance then
				local fr = board.freeze_random(s.board, s.rng, 1)
				if #fr > 0 then push(s, { kind = "board_freeze", cells = fr }) end
			end
			if s.board_cfg.curse_chance and s.rng:float() < s.board_cfg.curse_chance then
				local cu = board.spawn_curse(s.board, s.rng)
				if cu then push(s, { kind = "board_curse", cells = { cu } }) end
			end
		end
		-- Bosses and elites actively plant 1-2 three-move bombs on their turn.
		if s.status == "play" and (s.enemy.boss or s.enemy.elite) then
			local planted = {}
			local n = s.enemy.boss and 2 or 1
			for _ = 1, n do
				local cu = board.spawn_curse(s.board, s.rng)
				if cu then planted[#planted + 1] = cu end
			end
			if #planted > 0 then push(s, { kind = "board_curse", cells = planted, boss = true }) end
		end
	end
	return true
end

function M.use_ult(s)
	if s.status ~= "play" or s.turn ~= "player" then return false end
	if not s.ult or s.ult.charge < s.ult.max then return false end
	local total = 0
	for _, col in ipairs(config.ATTACK_COLORS) do
		local sq = s.player.squads[col]
		if sq then total = total + sq.power end
	end
	local dmg = math.max(1, math.floor(total * config.ULT.damage_mult + 0.5))
	local dealt, blocked = apply_damage(s.enemy, dmg, 0)
	s.enemy.statuses.stun = true
	s.ult.charge = 0
	push(s, { kind = "ult", who = "player", dmg = dmg, dealt = dealt, blocked = blocked })
	check_end(s)
	return true
end

function M.use_booster(s, kind, r, c)
	if s.status ~= "play" or s.turn ~= "player" then return false end
	if (s.boosters[kind] or 0) <= 0 then return false end
	if kind == "shuffle" then
		s.boosters.shuffle = s.boosters.shuffle - 1
		s.stats.boosters = s.stats.boosters + 1
		board.shuffle(s.board)
		push(s, { kind = "shuffle", booster = true })
		return true
	elseif kind == "extra_move" then
		if s.player.moves_left >= config.MAX_MOVES then return false end
		s.boosters.extra_move = s.boosters.extra_move - 1
		s.stats.boosters = s.stats.boosters + 1
		s.player.moves_left = s.player.moves_left + 1
		push(s, { kind = "extra_move" })
		return true
	elseif kind == "hammer" and r and c then
		local steps, shuffled = board.use_hammer(s.board, r, c)
		if not steps then return false end
		s.boosters.hammer = s.boosters.hammer - 1
		s.stats.boosters = s.stats.boosters + 1
		push(s, { kind = "hammer", r = r, c = c, steps = steps, shuffled = shuffled })
		apply_effects(s, s.player, s.enemy, "player", steps)
		check_end(s)
		return true
	end
	return false
end

function M.revive_player(s)
	if s.status ~= "lose" or s.revived then return false end
	s.revived = true
	s.status = "play"
	s.turn = "player"
	s.player.hp = math.max(1, math.floor(s.player.max_hp * 0.5))
	s.player.shield = math.floor(s.player.max_shield * 0.5)
	s.player.moves_left = s.player.max_moves
	s.player.statuses = { burn = nil, poison = nil, freeze = 0 }
	push(s, { kind = "revive" })
	return true
end

-- Hint: best move to play (clears most gems / creates specials, breaks ties toward attack gems).
local ATK_HINT = { red = true, yellow = true, purple = true }
function M.suggest_move(s)
	local moves = board.valid_moves(s.board.grid)
	if #moves == 0 then return nil end

	if config.is_blast_mode() then
		-- Onboarding: the first hint points at the deterministic starter cluster.
		if s.tutorial and s.board.cfg and s.board.cfg.force_cluster then
			local fc = s.board.cfg.force_cluster
			local cells = {}
			for _, p in ipairs(fc.cells or {}) do cells[#cells + 1] = { r = p[1], c = p[2] } end
			if #cells >= 2 then
				return {
					r = cells[1].r, c = cells[1].c,
					r1 = cells[1].r, c1 = cells[1].c,
					r2 = cells[1].r, c2 = cells[1].c,
					size = #cells, color = fc.color, cells = cells, match_cells = cells,
				}
			end
		end
		local best, best_n = moves[1], -1
		for _, m in ipairs(moves) do
			local n = m.size or (m.cells and #m.cells) or 1
			if m.special then n = 12 end
			if m.color and ATK_HINT[m.color] then n = n + 0.1 end
			if n > best_n then
				best, best_n = m, n
			end
		end
		if best then
			best.match_cells = best.cells or { { r = best.r, c = best.c } }
		end
		return best
	end

	local best, best_n = moves[1], -1
	local best_cells = nil
	local g = s.board.grid
	for _, m in ipairs(moves) do
		local a, b = g[m.r1][m.c1], g[m.r2][m.c2]
		local n = 0
		local m_cells = {}
		if a.special == "prism" or b.special == "prism" then
			n = 12
		else
			g[m.r1][m.c1], g[m.r2][m.c2] = b, a
			for _, grp in ipairs(board.find_matches(g)) do
				n = n + #grp.cells + (grp.spawn and 3 or 0) + (ATK_HINT[grp.color] and 0.1 or 0)
				for _, c in ipairs(grp.cells) do
					m_cells[#m_cells + 1] = { r = c.r, c = c.c }
				end
			end
			g[m.r1][m.c1], g[m.r2][m.c2] = a, b
		end
		if n > best_n then
			best, best_n = m, n
			best_cells = m_cells
		end
	end
	if best then
		best.match_cells = best_cells
	end
	return best
end

-- Estimated damage of tapping a cluster / special (no RNG: previews never touch the real board).
function M.preview(s, r, c)
	if not (s and s.board and s.status == "play" and s.turn == "player") then return nil end
	if not config.is_blast_mode() then return nil end
	local sim = board.clone_grid_only(s.board)
	sim.rng = rng.new(24601)
	local steps = board.resolve_tap(sim, r, c)
	if not steps or #steps == 0 then return nil end

	local fm = fury_mult(s)
	local dmg, heal, shield, cleared = 0, 0, 0, 0
	for _, step in ipairs(steps) do
		local c_mult = (1 + 0.25 * (step.cascade - 1)) * fm
		for _, col in ipairs(config.ATTACK_COLORS) do
			local cnt = step.counts[col] or 0
			if cnt > 0 then
				local sq = s.player.squads[col]
				local d = math.max(1, math.floor(sq.power * (cnt / 3) * c_mult + 0.5))
				if s.player.statuses.weak and s.player.statuses.weak.turns > 0 then
					d = math.max(1, math.floor(d * (s.player.statuses.weak.ratio or 0.75) + 0.5))
				end
				if sq.trait == "fury" and s.player.hp < s.player.max_hp * 0.5 then
					d = math.floor(d * 1.35 + 0.5)
				elseif sq.trait == "crush" and s.enemy.shield > 0 then
					d = math.floor(d * 1.25 + 0.5)
				end
				dmg = dmg + d
			end
		end
		local g = step.counts.green or 0
		if g > 0 then
			heal = heal + math.max(1, math.floor(s.player.heal_power * (g / 3) * (1 + 0.2 * (step.cascade - 1)) + 0.5))
		end
		local b = step.counts.blue or 0
		if b > 0 then
			shield = shield + math.max(1, math.floor(s.player.shield_power * (b / 3) * (1 + 0.2 * (step.cascade - 1)) + 0.5))
		end
		if (step.curses_cleared or 0) > 0 then
			dmg = dmg + math.max(6, math.floor(s.enemy.max_hp * 0.06 + 0.5)) * step.curses_cleared
		end
		cleared = cleared + #(step.cleared or {})
	end

	local hp_dmg = math.max(0, math.min(s.enemy.hp, dmg - math.max(0, s.enemy.shield)))
	return {
		dmg = dmg,
		hp_dmg = hp_dmg,
		heal = heal,
		shield = shield,
		cleared = cleared,
		lethal = dmg >= s.enemy.hp + math.max(0, s.enemy.shield),
	}
end

-- Remaining-HP ratio of the player (stars / results).
function M.hp_ratio(s)
	return s.player.hp / math.max(1, s.player.max_hp)
end

return M
