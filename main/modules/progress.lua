-- Player persistence & economy: currencies, prestige/leagues, cards, chests, stars, trophy road,
-- free chest, rewards and notification badges. Pure Lua except sys.save/sys.load.
local config = require "main.modules.config"
local squads = require "main.modules.squads"
local campaign = require "main.modules.campaign"
local quests = require "main.modules.quests"
local rng = require "main.modules.rng"

local M = {}

local SAVE_FILE = "gem_vanguard_save_v1"
M.VERSION = 2

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
		version = M.VERSION,
		gold = 60,
		diamonds = 30,
		prestige = 0,
		max_prestige = 0,
		max_moves = 1,
		commander_lvl = 1,
		max_stage_unlocked = 1,
		onboarding_done = false,
		onboarding_step = 0, -- 0: battle 1, 1: upgrade a card in the hub, 2: done
		lang = "",
		sound = true,
		music = true,
		slots = {
			red = "red_militia",
			yellow = "yellow_archers",
			purple = "purple_cultists",
		},
		cards = cards,
		chests = {}, -- [1..4] = { rarity, unlocking, end_time }
		boosters = { shuffle = 2, hammer = 2, extra_move = 1 },
		stars = {},          -- [stage_id] = 1..3
		star_chests = 0,     -- star chests claimed
		road_claimed = 0,    -- trophy road milestones claimed
		free_chest_at = 0,   -- os.time when the free chest is ready
		streak = 0,          -- current PvP win streak
		best_streak = 0,
		stats = { battles = 0, wins = 0, pvp_wins = 0, chests = 0, upgrades = 0 },
		login = { last_day = 0, count = 0 },
		daily = nil,
	}
end

M.data = default_data()

function M.save()
	local path = sys.get_save_file("GemVanguard", SAVE_FILE)
	sys.save(path, M.data)
end

local function merge_defaults(dst, def)
	for k, v in pairs(def) do
		if dst[k] == nil then
			dst[k] = v
		elseif type(v) == "table" and type(dst[k]) == "table" and k ~= "chests" and k ~= "stars" then
			merge_defaults(dst[k], v)
		end
	end
end

function M.load(fresh)
	if fresh then
		M.data = default_data()
	else
		local path = sys.get_save_file("GemVanguard", SAVE_FILE)
		local loaded = sys.load(path)
		if loaded and loaded.cards and loaded.slots then
			merge_defaults(loaded, default_data())
			loaded.max_prestige = math.max(loaded.max_prestige or 0, loaded.prestige or 0)
			loaded.max_stage_unlocked = math.min(campaign.COUNT, loaded.max_stage_unlocked or 1)
			loaded.version = M.VERSION
			M.data = loaded
		else
			M.data = default_data()
		end
	end
	quests.refresh(M.data)
end

-- Called every hub visit: rolls the daily block over at midnight.
function M.tick_day()
	if quests.refresh(M.data) then
		M.save()
		return true
	end
	return false
end

-- ---------------------------------------------------------------- commander
function M.hero_hp()
	return config.commander_hp(M.data.commander_lvl, M.data.max_moves, M.data.prestige)
end

function M.heal_power()
	return math.floor(M.hero_hp() * config.HEAL_RATIO + 0.5)
end

function M.shield_power()
	return math.floor(M.hero_hp() * config.SHIELD_RATIO + 0.5)
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

-- Rough build strength used by PvP matchmaking.
function M.player_power()
	local sum = 0
	for _, col in ipairs(config.ATTACK_COLORS) do
		local c = M.data.cards[M.data.slots[col]]
		sum = sum + (c and c.level or 1)
	end
	return { hp = M.hero_hp(), moves = M.data.max_moves or 1, avg_lvl = math.floor(sum / 3 + 0.5) }
end

-- ---------------------------------------------------------------- cards
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
	M.data.stats.upgrades = (M.data.stats.upgrades or 0) + 1
	quests.on_event(M.data, "upgrades", 1)
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
	c.new = true
	c.level = 1
	c.count = 0
	M.save()
	return true
end

function M.mark_seen(id)
	local c = M.data.cards[id]
	if c and c.new then
		c.new = nil
		M.save()
	end
end

local function add_cards(id, cnt)
	local c = M.data.cards[id]
	local newly = not c.unlocked
	if newly then
		c.unlocked = true
		c.new = true
		c.level = 1
		c.count = c.count + math.max(0, cnt - 1)
	else
		c.count = c.count + cnt
	end
	return newly
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

-- ---------------------------------------------------------------- chests
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
	return math.max(0, (ch.end_time or 0) - quests.now())
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
	ch.end_time = quests.now() + config.CHESTS[ch.rarity].duration
	M.save()
	return true
end

-- Rewarded ad: cut the remaining unlock time of a chest in half (min 30 min cut).
function M.speedup_chest(slot)
	local ch = M.data.chests[slot]
	if not (ch and ch.unlocking) then return false end
	local rem = M.chest_remaining(slot)
	local cut = math.max(math.floor(rem / 2), math.min(rem, 1800))
	ch.end_time = ch.end_time - cut
	M.save()
	return true
end

-- Roll chest contents and grant them. Returns { rarity, gold, drops = { {id, count, unlocked_now} } }.
function M.roll_chest(rarity, seed)
	local def = config.CHESTS[rarity] or config.CHESTS.wood
	local r = rng.new(seed or (quests.now() + (M.data.gold or 0) * 13 + (M.data.stats.chests or 0) * 97))
	local gold = r:int(def.gold_min, def.gold_max)
	local total_cards = r:int(def.cards_min, def.cards_max)
	local drops = {}
	local order = {}
	for _ = 1, total_cards do
		local roll = r:float()
		local lc = def.legendary_chance or 0
		local rar = roll < lc and "legendary"
			or (roll < lc + def.epic_chance and "epic"
			or (roll < lc + def.epic_chance + def.rare_chance and "rare" or "common"))
		local pool = {}
		for _, sq in ipairs(squads.LIST) do
			if sq.rarity == rar then pool[#pool + 1] = sq.id end
		end
		local id = r:pick(pool)
		if not drops[id] then order[#order + 1] = id end
		drops[id] = (drops[id] or 0) + 1
	end
	M.data.gold = M.data.gold + gold
	local drop_list = {}
	for _, id in ipairs(order) do
		local newly = add_cards(id, drops[id])
		drop_list[#drop_list + 1] = { id = id, count = drops[id], unlocked_now = newly }
	end
	-- Rarest first for the reveal sequence
	local RANK = { legendary = 4, epic = 3, rare = 2, common = 1 }
	table.sort(drop_list, function(a, b)
		local ra, rb = RANK[squads.get(a.id).rarity], RANK[squads.get(b.id).rarity]
		if ra ~= rb then return ra < rb end
		return a.count < b.count
	end)
	M.data.stats.chests = (M.data.stats.chests or 0) + 1
	quests.on_event(M.data, "chests", 1)
	M.save()
	return { rarity = rarity, gold = gold, drops = drop_list }
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
	M.data.chests[slot] = nil
	return M.roll_chest(ch.rarity, quests.now() + slot * 97 + (M.data.gold or 0))
end

function M.buy_chest(rarity)
	local def = config.CHESTS[rarity]
	if not def or M.data.diamonds < def.diamonds then return nil end
	M.data.diamonds = M.data.diamonds - def.diamonds
	return M.roll_chest(rarity)
end

-- ---------------------------------------------------------------- free chest
function M.free_chest_remaining()
	return math.max(0, (M.data.free_chest_at or 0) - quests.now())
end

function M.claim_free_chest()
	if M.free_chest_remaining() > 0 then return nil end
	M.data.free_chest_at = quests.now() + config.FREE_CHEST_INTERVAL
	return M.roll_chest(config.FREE_CHEST_RARITY)
end

-- ---------------------------------------------------------------- rewards
-- Grants a reward table { gold, diamonds, booster+count, chest }. Chests open instantly.
-- Returns the chest result (or nil) so the UI can play the opening sequence.
function M.grant(reward)
	if not reward then return nil end
	local d = M.data
	if reward.gold then d.gold = d.gold + reward.gold end
	if reward.diamonds then d.diamonds = d.diamonds + reward.diamonds end
	if reward.booster then
		d.boosters[reward.booster] = (d.boosters[reward.booster] or 0) + (reward.count or 1)
	end
	local chest_res = nil
	if reward.chest then chest_res = M.roll_chest(reward.chest) end
	M.save()
	return chest_res
end

-- ---------------------------------------------------------------- leagues & trophy road
function M.league()
	local idx = config.league_index(M.data.prestige)
	return idx, config.LEAGUES[idx], config.LEAGUES[idx + 1]
end

function M.road_next()
	local idx = (M.data.road_claimed or 0) + 1
	return idx, config.TROPHY_ROAD[idx]
end

function M.road_claimable()
	local _, m = M.road_next()
	return m ~= nil and (M.data.max_prestige or 0) >= m.at
end

function M.claim_road()
	if not M.road_claimable() then return nil end
	local idx, m = M.road_next()
	M.data.road_claimed = idx
	local res = M.grant(m.reward)
	M.save()
	return m.reward, res
end

-- ---------------------------------------------------------------- campaign stars
function M.stage_stars(id)
	return (M.data.stars and M.data.stars[id]) or 0
end

function M.total_stars()
	local n = 0
	for _, v in pairs(M.data.stars or {}) do n = n + v end
	return n
end

function M.star_chest_progress()
	local need = ((M.data.star_chests or 0) + 1) * config.STAR_CHEST_EVERY
	return M.total_stars(), need
end

function M.star_chest_ready()
	local have, need = M.star_chest_progress()
	return have >= need
end

function M.claim_star_chest()
	if not M.star_chest_ready() then return nil end
	M.data.star_chests = (M.data.star_chests or 0) + 1
	local rarity = (M.data.star_chests % 3 == 0) and "royal" or "silver"
	return M.roll_chest(rarity)
end

-- ---------------------------------------------------------------- daily (quests / login / deals / ads)
function M.claim_quest(idx)
	local reward = quests.claim(M.data, idx)
	if not reward then return nil end
	M.grant(reward)
	return reward
end

function M.claim_quest_bonus()
	local reward = quests.claim_bonus(M.data)
	if not reward then return nil end
	return M.grant(reward), reward
end

function M.claim_login()
	local reward, idx = quests.claim_login(M.data)
	if not reward then return nil end
	local chest_res = M.grant(reward)
	return reward, idx, chest_res
end

function M.buy_deal(i)
	local deal = M.data.daily and M.data.daily.deals and M.data.daily.deals[i]
	if not deal or deal.bought or M.data.gold < deal.price then return false end
	M.data.gold = M.data.gold - deal.price
	deal.bought = true
	add_cards(deal.id, deal.count)
	M.save()
	return true
end

function M.ad_diamonds_left()
	local used = M.data.daily and M.data.daily.ad_diamonds or 0
	return math.max(0, config.AD_DIAMONDS_PER_DAY - used)
end

function M.claim_ad_diamonds()
	if M.ad_diamonds_left() <= 0 then return false end
	M.data.daily.ad_diamonds = (M.data.daily.ad_diamonds or 0) + 1
	M.data.diamonds = M.data.diamonds + config.AD_DIAMONDS
	M.save()
	return true
end

-- ---------------------------------------------------------------- battle results
-- opts: won, is_pvp, stage_id, gold, chest, tutorial, stats (battle.stats), hp_ratio
function M.apply_battle_result(opts)
	local d = M.data
	local won = opts.won
	local is_pvp = opts.is_pvp
	local base_gold = opts.gold or 40
	local gold = won and base_gold or math.floor(base_gold * 0.25)
	local streak_bonus = 0
	local d_pres = 0
	if won then
		d_pres = is_pvp and config.PVP_PRESTIGE_WIN or config.PRESTIGE_WIN
		if is_pvp then
			d.streak = math.min(config.STREAK_MAX, (d.streak or 0) + 1)
			d.best_streak = math.max(d.best_streak or 0, d.streak)
			streak_bonus = math.floor(base_gold * config.STREAK_GOLD_BONUS * (d.streak - 1) + 0.5)
			gold = gold + streak_bonus
		end
	else
		d_pres = -(is_pvp and config.PVP_PRESTIGE_LOSE or config.PRESTIGE_LOSE)
		if is_pvp then d.streak = 0 end
	end
	d.gold = d.gold + gold
	local old_league = config.league_index(d.prestige)
	d.prestige = math.max(0, (d.prestige or 0) + d_pres)
	d.max_prestige = math.max(d.max_prestige or 0, d.prestige)
	local new_league = config.league_index(d.prestige)

	d.stats.battles = (d.stats.battles or 0) + 1
	-- Quest stats from the battle
	local bs = opts.stats
	if bs then
		for col, cnt in pairs(bs.gems or {}) do quests.on_event(d, "gems_" .. col, cnt) end
		quests.on_event(d, "combos", bs.combos or 0)
		quests.on_event(d, "skills", bs.skills or 0)
		quests.on_event(d, "specials", bs.specials or 0)
		quests.on_event(d, "damage", bs.damage or 0)
		quests.on_event(d, "boosters", bs.boosters or 0)
	end

	local chest_slot, chest_rarity, bonus_cards, stars, new_stars, first_clear = nil, nil, nil, nil, 0, false
	if won then
		d.stats.wins = (d.stats.wins or 0) + 1
		quests.on_event(d, "wins", 1)
		if is_pvp then
			d.stats.pvp_wins = (d.stats.pvp_wins or 0) + 1
			quests.on_event(d, "pvp_wins", 1)
		end
		if opts.tutorial then
			-- Onboarding: instant militia cards so the player sees the upgrade loop right away.
			d.cards.red_militia.count = d.cards.red_militia.count + 2
			bonus_cards = { { id = "red_militia", count = 2 } }
			if d.onboarding_step == 0 then d.onboarding_step = 1 end
		end
		chest_rarity = opts.chest or "wood"
		chest_slot = M.add_chest(chest_rarity)
		if not is_pvp and opts.stage_id then
			first_clear = opts.stage_id >= (d.max_stage_unlocked or 1)
			if first_clear then
				d.max_stage_unlocked = math.min(campaign.COUNT, opts.stage_id + 1)
				local st = campaign.get_stage(opts.stage_id)
				if st.boss then d.diamonds = d.diamonds + 10 end
			end
			stars = campaign.stars_for(opts.hp_ratio or 0, 1)
			local old = M.stage_stars(opts.stage_id)
			if stars > old then
				d.stars[opts.stage_id] = stars
				new_stars = stars - old
				quests.on_event(d, "stars", new_stars)
			end
		end
	end
	M.save()
	return {
		won = won,
		gold = gold,
		streak = d.streak,
		streak_bonus = streak_bonus,
		prestige_delta = d_pres,
		prestige = d.prestige,
		league_up = new_league > old_league,
		league_down = new_league < old_league,
		chest_rarity = chest_rarity,
		chest_slot = chest_slot,
		bonus_cards = bonus_cards,
		stars = stars,
		new_stars = new_stars,
		first_clear = first_clear,
		is_pvp = is_pvp,
		stage_id = opts.stage_id,
	}
end

-- ---------------------------------------------------------------- badges (red dots)
function M.badges()
	local d = M.data
	local b = { cards = 0, quests = 0, shop = 0, map = 0, home = 0 }
	for _, s in ipairs(squads.LIST) do
		local c = d.cards[s.id]
		if c.new or M.can_upgrade_card(s.id) then b.cards = b.cards + 1 end
	end
	b.quests = quests.claimable_count(d) + (quests.login_pending(d) and 1 or 0)
	if M.ad_diamonds_left() > 0 then b.shop = 1 end
	if M.star_chest_ready() then b.map = 1 end
	for i = 1, config.MAX_CHEST_SLOTS do
		local ch = d.chests[i]
		if ch and ch.unlocking and M.chest_remaining(i) <= 0 then b.home = b.home + 1 end
	end
	if M.free_chest_remaining() <= 0 then b.home = b.home + 1 end
	if M.road_claimable() then b.home = b.home + 1 end
	return b
end

return M
