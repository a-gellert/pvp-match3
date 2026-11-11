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
		local lvl = def.level or 1
		out[col] = {
			id = def.id,
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
	local b = board.new(r)
	local p_hp = opts.player_hp or config.BASE_HP
	local e_hp = opts.enemy_hp or 60
	return {
		rng = r,
		board = b,
		mode = opts.mode or "campaign",
		stage_id = opts.stage_id or 1,
		tutorial = opts.tutorial or false,
		tutorial_step = opts.tutorial and 1 or 0,
		turn = "player",
		turn_num = 1,
		status = "play",
		events = {},
		boosters = {
			shuffle = opts.boosters and opts.boosters.shuffle or 0,
			hammer = opts.boosters and opts.boosters.hammer or 0,
			extra_move = opts.boosters and opts.boosters.extra_move or 0,
		},
		player = {
			face = "face_hero",
			hp = p_hp,
			max_hp = p_hp,
			shield = 0,
			max_shield = math.floor(p_hp * config.SHIELD_CAP_RATIO),
			moves_left = opts.player_moves or 1,
			max_moves = opts.player_moves or 1,
			heal_power = opts.heal_power or config.BASE_HEAL,
			shield_power = opts.shield_power or config.BASE_SHIELD,
			squads = build_fighter_squads(opts.player_squads),
			statuses = { burn = nil, poison = nil, freeze = 0 },
		},
		enemy = {
			name = opts.enemy_name or "",
			name_key = opts.enemy_name_key,
			face = opts.enemy_face or "face_goblin",
			hp = e_hp,
			max_hp = e_hp,
			shield = 0,
			max_shield = math.floor(e_hp * config.SHIELD_CAP_RATIO),
			moves_left = opts.enemy_moves or 1,
			max_moves = opts.enemy_moves or 1,
			difficulty = opts.enemy_diff or 1,
			heal_power = math.max(6, math.floor(e_hp * 0.14)),
			shield_power = math.max(6, math.floor(e_hp * 0.14)),
			squads = build_fighter_squads(opts.enemy_squads),
			statuses = { burn = nil, poison = nil, freeze = 0 },
		},
	}
end

local function push(s, ev)
	s.events[#s.events + 1] = ev
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

local function check_end(s)
	if s.enemy.hp <= 0 then
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
	local pierce = sk.pierce or 0
	local eff = sk.effect

	if eff == "fury_heal" and actor.hp < actor.max_hp * 0.6 then
		dmg = math.floor(dmg * 1.45 + 0.5)
	elseif eff == "shield_slam" then
		dmg = dmg + math.floor(actor.shield * (sk.val or 0.5) + 0.5)
	elseif eff == "crush" and target.shield > 0 then
		dmg = math.floor(dmg * (sk.val or 1.6) + 0.5)
	elseif eff == "execute" and target.hp < target.max_hp * 0.5 then
		dmg = math.floor(dmg * (sk.val or 1.65) + 0.5)
	elseif eff == "shatter" and target.shield > 0 then
		local broken = math.max(1, math.floor(target.shield * (sk.val or 0.5)))
		target.shield = math.max(0, target.shield - broken)
	end

	local dealt, blocked = apply_damage(target, dmg, pierce)
	push(s, {
		kind = "skill",
		who = who,
		color = col,
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
	elseif eff == "freeze" then
		target.statuses.freeze = math.min(2, (target.statuses.freeze or 0) + (sk.val or 1))
		push(s, { kind = "status", who = who == "player" and "enemy" or "player", stype = "freeze", val = target.statuses.freeze })
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
	for _, step in ipairs(steps) do
		local c_mult = (1 + 0.25 * (step.cascade - 1)) * fm
		for _, col in ipairs(config.ATTACK_COLORS) do
			local cnt = step.counts[col] or 0
			if cnt > 0 and target.hp > 0 then
				local sq = actor.squads[col]
				local gem_scale = cnt / 3
				local dmg = math.max(1, math.floor(sq.power * gem_scale * c_mult + 0.5))
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
					dmg = math.floor(dmg * 1.35 + 0.5)
				end
				local dealt, blocked = apply_damage(target, dmg, pierce)
				push(s, {
					kind = "attack",
					who = who,
					color = col,
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
		end

		local b_cnt = step.counts.blue or 0
		if b_cnt > 0 then
			local amt = math.max(1, math.floor(actor.shield_power * (b_cnt / 3) * (1 + 0.2 * (step.cascade - 1)) + 0.5))
			local gained = math.min(actor.max_shield - actor.shield, amt)
			actor.shield = actor.shield + gained
			push(s, { kind = "shield", who = who, amount = amt, gained = gained })
		end

		-- Feed crystal runes across all 3 squads & trigger Special Skills when 2/2 ready
		charge_runes(s, actor, target, who, step.counts)
		if target.hp <= 0 then return end
	end
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
	actor.moves_left = math.max(0, actor.max_moves - freeze)
	push(s, { kind = "turn", turn = next_who, turn_num = s.turn_num, freeze = freeze })

	if actor.moves_left == 0 then
		push(s, { kind = "frozen", who = next_who })
		local other = next_who == "player" and "enemy" or "player"
		begin_turn(s, other)
	end
end

function M.player_swap(s, r1, c1, r2, c2)
	if s.status ~= "play" or s.turn ~= "player" then return false end
	local steps, shuffled = board.resolve_swap(s.board, r1, c1, r2, c2)
	if not steps then return false end

	if s.tutorial and s.tutorial_step > 0 then
		s.tutorial_step = s.tutorial_step + 1
	end
	push(s, { kind = "swap", who = "player", r1 = r1, c1 = c1, r2 = r2, c2 = c2, steps = steps, shuffled = shuffled })
	apply_cascade_effects(s, s.player, s.enemy, "player", steps)

	s.player.moves_left = math.max(0, s.player.moves_left - 1)
	if check_end(s) then return true end

	if s.player.moves_left == 0 then
		begin_turn(s, "enemy")
	end
	return true
end

function M.step_enemy(s)
	if s.status ~= "play" or s.turn ~= "enemy" then return false end
	local m = ai.pick_move(s.board, s.enemy, s.enemy.difficulty, s.rng)
	if not m then
		board.shuffle(s.board)
		push(s, { kind = "shuffle" })
		m = ai.pick_move(s.board, s.enemy, s.enemy.difficulty, s.rng)
	end
	if m then
		local steps, shuffled = board.resolve_swap(s.board, m.r1, m.c1, m.r2, m.c2)
		if steps then
			push(s, { kind = "swap", who = "enemy", r1 = m.r1, c1 = m.c1, r2 = m.r2, c2 = m.c2, steps = steps, shuffled = shuffled })
			apply_cascade_effects(s, s.enemy, s.player, "enemy", steps)
		end
	end
	s.enemy.moves_left = math.max(0, s.enemy.moves_left - 1)
	if check_end(s) then return true end

	if s.enemy.moves_left == 0 then
		begin_turn(s, "player")
	end
	return true
end

function M.use_booster(s, kind, r, c)
	if s.status ~= "play" or s.turn ~= "player" then return false end
	if (s.boosters[kind] or 0) <= 0 then return false end
	if kind == "shuffle" then
		s.boosters.shuffle = s.boosters.shuffle - 1
		board.shuffle(s.board)
		push(s, { kind = "shuffle", booster = true })
		return true
	elseif kind == "extra_move" then
		if s.player.moves_left >= config.MAX_MOVES then return false end
		s.boosters.extra_move = s.boosters.extra_move - 1
		s.player.moves_left = s.player.moves_left + 1
		push(s, { kind = "extra_move" })
		return true
	elseif kind == "hammer" and r and c then
		local steps, shuffled = board.use_hammer(s.board, r, c)
		if not steps then return false end
		s.boosters.hammer = s.boosters.hammer - 1
		push(s, { kind = "hammer", r = r, c = c, steps = steps, shuffled = shuffled })
		apply_cascade_effects(s, s.player, s.enemy, "player", steps)
		check_end(s)
		return true
	end
	return false
end

function M.revive_player(s)
	if s.status ~= "lose" then return false end
	s.status = "play"
	s.turn = "player"
	s.player.hp = math.max(1, math.floor(s.player.max_hp * 0.5))
	s.player.moves_left = s.player.max_moves
	s.player.statuses = { burn = nil, poison = nil, freeze = 0 }
	push(s, { kind = "revive" })
	return true
end

function M.suggest_move(s)
	local moves = board.valid_moves(s.board.grid)
	return moves[1]
end

return M
