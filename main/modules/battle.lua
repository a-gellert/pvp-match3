-- Turn-based Match-3 combat session (pure Lua, zero Defold API).
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
		out[col] = {
			id = def.id,
			level = def.level or 1,
			power = squads.power(def.id, def.level or 1),
			trait = info and info.trait or "none",
			sprite = info and info.sprite or "squad_red_militia",
			style = info and info.style or "melee",
			fx = info and info.fx or "fx_slash",
			units = info and info.units or 1,
		}
	end
	return out
end

function M.new(opts)
	local r = rng.new(opts.seed or 42)
	local b = board.new(r)
	local p_hp = opts.player_hp or config.BASE_HP
	local e_hp = opts.enemy_hp or 60
	local s = {
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
		},
	}
	return s
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

local function apply_cascade_effects(s, actor, target, who, steps)
	local fm = fury_mult(s)
	for _, step in ipairs(steps) do
		local c_mult = (1 + 0.25 * (step.cascade - 1)) * fm
		-- Attack colors
		for _, col in ipairs(config.ATTACK_COLORS) do
			local cnt = step.counts[col] or 0
			if cnt > 0 then
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
		-- Green = Heal
		local g_cnt = step.counts.green or 0
		if g_cnt > 0 then
			local amt = math.max(1, math.floor(actor.heal_power * (g_cnt / 3) * (1 + 0.2 * (step.cascade - 1)) + 0.5))
			local gained = math.min(actor.max_hp - actor.hp, amt)
			actor.hp = actor.hp + gained
			push(s, { kind = "heal", who = who, amount = amt, gained = gained })
		end
		-- Blue = Shield
		local b_cnt = step.counts.blue or 0
		if b_cnt > 0 then
			local amt = math.max(1, math.floor(actor.shield_power * (b_cnt / 3) * (1 + 0.2 * (step.cascade - 1)) + 0.5))
			local gained = math.min(actor.max_shield - actor.shield, amt)
			actor.shield = actor.shield + gained
			push(s, { kind = "shield", who = who, amount = amt, gained = gained })
		end
	end
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
		s.turn = "enemy"
		s.enemy.moves_left = s.enemy.max_moves
		push(s, { kind = "turn", turn = "enemy" })
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
		s.turn = "player"
		s.turn_num = s.turn_num + 1
		s.player.moves_left = s.player.max_moves
		push(s, { kind = "turn", turn = "player", turn_num = s.turn_num })
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
	push(s, { kind = "revive" })
	return true
end

function M.suggest_move(s)
	local moves = board.valid_moves(s.board.grid)
	return moves[1]
end

return M
