-- Player persistence: currencies, prestige, Clash Royale cards, 4 chest slots, 1..7 moves.
local config = require "main.modules.config"
local squads = require "main.modules.squads"
local rng = require "main.modules.rng"

local M = {}

local SAVE_FILE = "gem_vanguard_save_v1"

local function default_data()
	local cards = {}
	for _, s in ipairs(squads.LIST) do
		cards[s.id] = {
			unlocked = s.starter == true,
			level = 1,
			count = 0,
		}
	end
	return {
		gold = 55,
		diamonds = 25,
		prestige = 0,
		max_moves = 1,
		commander_lvl = 1,
		campaign_stage = 1,
		max_stage_unlocked = 1,
		onboarding_done = false,
		onboarding_step = 0, -- 0: start battle1, 1: chest/card upgrade in hub, 2: done
		lang = "",
		sound = true,
		music = true,
		slots = {
			red = "red_militia",
			yellow = "yellow_archers",
			purple = "purple_cultists",
		},
		cards = cards,
		chests = { nil, nil, nil, nil }, -- { rarity = "wood"|"silver"|"royal", unlocking = bool, end_time = os.time }
		boosters = { shuffle = 2, hammer = 2, extra_move = 1 },
	}
end

M.data = default_data()

function M.save()
	local path = sys.get_save_file("GemVanguard", SAVE_FILE)
	sys.save(path, M.data)
end

function M.load(fresh)
	if fresh then
		M.data = default_data()
		return
	end
	local path = sys.get_save_file("GemVanguard", SAVE_FILE)
	local loaded = sys.load(path)
	if loaded and loaded.cards and loaded.slots then
		local def = default_data()
		for k, v in pairs(def) do
			if loaded[k] == nil then loaded[k] = v end
		end
		for id, cdef in pairs(def.cards) do
			if not loaded.cards[id] then loaded.cards[id] = cdef end
		end
		M.data = loaded
	else
		M.data = default_data()
	end
end

function M.hero_hp()
	local lvl = M.data.commander_lvl or 1
	return config.BASE_HP + (lvl - 1) * 16 + math.floor((M.data.prestige or 0) / 40) * 4
end

function M.heal_power()
	return config.BASE_HEAL + ((M.data.commander_lvl or 1) - 1) * 2
end

function M.shield_power()
	return config.BASE_SHIELD + ((M.data.commander_lvl or 1) - 1) * 2
end

function M.player_slots_for_battle()
	local out = {}
	for _, col in ipairs(config.ATTACK_COLORS) do
		local id = M.data.slots[col]
		local c = M.data.cards[id]
		out[col] = { id = id, level = c and c.level or 1 }
	end
	return out
end

function M.assign_slot(id)
	local s = squads.get(id)
	local c = M.data.cards[id]
	if not (s and c and c.unlocked) then return false end
	M.data.slots[s.color] = id
	M.save()
	return true
end

function M.can_upgrade_card(id)
	local c = M.data.cards[id]
	if not (c and c.unlocked) then return false end
	local req = squads.upgrade_req(id, c.level)
	local gold = squads.upgrade_gold(id, c.level)
	if not req or not gold then return false end
	return c.count >= req and M.data.gold >= gold
end

function M.upgrade_card(id)
	if not M.can_upgrade_card(id) then return false end
	local c = M.data.cards[id]
	local req = squads.upgrade_req(id, c.level)
	local gold = squads.upgrade_gold(id, c.level)
	c.count = c.count - req
	c.level = c.level + 1
	M.data.gold = M.data.gold - gold
	M.data.commander_lvl = M.data.commander_lvl + 1
	if M.data.onboarding_step == 1 then
		M.data.onboarding_step = 2
		M.data.onboarding_done = true
	end
	M.save()
	return true
end

function M.buy_locked_card(id)
	local c = M.data.cards[id]
	if not c or c.unlocked then return false end
	local cost = squads.unlock_diamonds(id)
	if M.data.diamonds < cost then return false end
	M.data.diamonds = M.data.diamonds - cost
	c.unlocked = true
	c.level = 1
	c.count = 0
	M.save()
	return true
end

function M.move_upgrade_cost()
	local cur = M.data.max_moves or 1
	if cur >= config.MAX_MOVES then return nil end
	return config.MOVE_COSTS[cur + 1]
end

function M.upgrade_moves()
	local cost = M.move_upgrade_cost()
	if not cost or M.data.gold < cost then return false end
	M.data.gold = M.data.gold - cost
	M.data.max_moves = M.data.max_moves + 1
	M.save()
	return true
end

function M.buy_booster(kind)
	local b = config.BOOSTERS[kind]
	if not b or M.data.gold < b.gold_cost then return false end
	M.data.gold = M.data.gold - b.gold_cost
	M.data.boosters[kind] = (M.data.boosters[kind] or 0) + 1
	M.save()
	return true
end

-- ---- Chests (4 slots, 1m / 1h / 24h)
function M.add_chest(rarity)
	for i = 1, config.MAX_CHEST_SLOTS do
		if not M.data.chests[i] then
			M.data.chests[i] = { rarity = rarity or "wood", unlocking = false, end_time = 0 }
			M.save()
			return i
		end
	end
	return nil
end

function M.any_chest_unlocking()
	for i = 1, config.MAX_CHEST_SLOTS do
		local ch = M.data.chests[i]
		if ch and ch.unlocking then return i end
	end
	return nil
end

function M.chest_remaining(slot)
	local ch = M.data.chests[slot]
	if not ch then return 0 end
	if not ch.unlocking then return config.CHESTS[ch.rarity].duration end
	return math.max(0, (ch.end_time or 0) - os.time())
end

function M.chest_rush_cost(slot)
	local rem = M.chest_remaining(slot)
	if rem <= 0 then return 0 end
	return math.max(1, math.min(60, math.ceil(rem / 180)))
end

function M.start_chest(slot)
	local ch = M.data.chests[slot]
	if not ch or ch.unlocking then return false end
	if M.any_chest_unlocking() then return false end
	ch.unlocking = true
	ch.end_time = os.time() + config.CHESTS[ch.rarity].duration
	M.save()
	return true
end

function M.open_chest(slot, rush_diamonds)
	local ch = M.data.chests[slot]
	if not ch then return nil end
	local rem = M.chest_remaining(slot)
	if rem > 0 then
		if not rush_diamonds then return nil end
		local cost = M.chest_rush_cost(slot)
		if M.data.diamonds < cost then return nil end
		M.data.diamonds = M.data.diamonds - cost
	end
	local def = config.CHESTS[ch.rarity]
	local r = rng.new(os.time() + slot * 97 + (M.data.gold or 0))
	local gold = r:int(def.gold_min, def.gold_max)
	local total_cards = r:int(def.cards_min, def.cards_max)
	local drops = {}
	for _ = 1, total_cards do
		local roll = r:float()
		local rar = roll < def.epic_chance and "epic" or (roll < def.epic_chance + def.rare_chance and "rare" or "common")
		local pool = {}
		for _, sq in ipairs(squads.LIST) do
			if sq.rarity == rar then pool[#pool + 1] = sq.id end
		end
		local id = r:pick(pool)
		drops[id] = (drops[id] or 0) + 1
	end
	M.data.gold = M.data.gold + gold
	local drop_list = {}
	for id, cnt in pairs(drops) do
		local c = M.data.cards[id]
		local newly_unlocked = not c.unlocked
		if not c.unlocked then
			c.unlocked = true
			c.level = 1
			c.count = c.count + math.max(0, cnt - 1)
		else
			c.count = c.count + cnt
		end
		drop_list[#drop_list + 1] = { id = id, count = cnt, unlocked_now = newly_unlocked }
	end
	M.data.chests[slot] = nil
	M.save()
	return { rarity = ch.rarity, gold = gold, drops = drop_list }
end

function M.apply_battle_result(opts)
	local won = opts.won
	local is_pvp = opts.is_pvp
	local gold = won and (opts.gold or 40) or math.floor((opts.gold or 40) * 0.25)
	local d_pres = 0
	if won then
		d_pres = is_pvp and config.PVP_PRESTIGE_WIN or config.PRESTIGE_WIN
	else
		d_pres = -(is_pvp and config.PVP_PRESTIGE_LOSE or config.PRESTIGE_LOSE)
	end
	M.data.gold = M.data.gold + gold
	M.data.prestige = math.max(0, (M.data.prestige or 0) + d_pres)

	local chest_slot = nil
	local chest_rarity = nil
	local bonus_cards = nil
	if won then
		if opts.tutorial then
			-- Onboarding gives instant cards for militia + wood chest so user sees Clash Royale upgrade immediately!
			M.data.cards.red_militia.count = M.data.cards.red_militia.count + 2
			bonus_cards = { { id = "red_militia", count = 2 } }
			if M.data.onboarding_step == 0 then M.data.onboarding_step = 1 end
		end
		chest_rarity = opts.chest or "wood"
		chest_slot = M.add_chest(chest_rarity)
		if not is_pvp and opts.stage_id and opts.stage_id >= (M.data.max_stage_unlocked or 1) then
			M.data.max_stage_unlocked = math.min(12, opts.stage_id + 1)
		end
	end
	M.save()
	return {
		won = won,
		gold = gold,
		prestige_delta = d_pres,
		chest_rarity = chest_rarity,
		chest_slot = chest_slot,
		bonus_cards = bonus_cards,
	}
end

return M
