-- Balance constants and rules for Gem Vanguard (pure Lua).
local M = {}

M.GRID = 7
M.COLORS = { "red", "yellow", "purple", "green", "blue" }
M.COLOR_INDEX = { red = 1, yellow = 2, purple = 3, green = 4, blue = 5 }
M.ATTACK_COLORS = { "red", "yellow", "purple" }

M.BASE_HP = 160
M.HP_PER_COMMANDER_LVL = 24
M.MOVE_HP_BONUS = 0.22  -- every extra move per turn also gives +22% commander HP
M.SHIELD_CAP_RATIO = 0.65
M.HEAL_RATIO = 0.10     -- green 3-match heals 10% of max HP
M.SHIELD_RATIO = 0.10   -- blue 3-match gives 10% of max HP as shield
M.FURY_TURN = 8 -- from turn 8+, damage +20% per turn so battles always end

-- Commander max HP from commander level (card upgrades), moves per turn and prestige.
function M.commander_hp(cmd_lvl, moves, prestige)
	local base = M.BASE_HP + ((cmd_lvl or 1) - 1) * M.HP_PER_COMMANDER_LVL + math.floor((prestige or 0) / 40) * 6
	return math.floor(base * (1 + M.MOVE_HP_BONUS * ((moves or 1) - 1)) + 0.5)
end

M.MIN_MOVES = 1
M.MAX_MOVES = 7
-- Gold cost to upgrade max_moves from (n-1) to n
M.MOVE_COSTS = { 0, 80, 200, 450, 900, 1800, 3500 }

M.PRESTIGE_WIN = 25
M.PRESTIGE_LOSE = 12
M.PVP_PRESTIGE_WIN = 32
M.PVP_PRESTIGE_LOSE = 18
M.STREAK_GOLD_BONUS = 0.15 -- +15% gold per PvP win in a row
M.STREAK_MAX = 5

M.MAX_CHEST_SLOTS = 4
M.CHEST_ORDER = { "wood", "silver", "royal" }
M.CHESTS = {
	wood = {
		id = "wood",
		duration = 60,        -- 1 minute
		gold_min = 35,
		gold_max = 55,
		cards_min = 2,
		cards_max = 4,
		rare_chance = 0.22,
		epic_chance = 0.04,
		legendary_chance = 0.005,
		sprite = "chest_wood",
		diamonds = 30,         -- shop price
	},
	silver = {
		id = "silver",
		duration = 3600,      -- 1 hour
		gold_min = 95,
		gold_max = 145,
		cards_min = 6,
		cards_max = 9,
		rare_chance = 0.50,
		epic_chance = 0.16,
		legendary_chance = 0.03,
		sprite = "chest_silver",
		diamonds = 60,
	},
	royal = {
		id = "royal",
		duration = 86400,     -- 24 hours
		gold_min = 280,
		gold_max = 420,
		cards_min = 14,
		cards_max = 20,
		rare_chance = 0.50,
		epic_chance = 0.36,
		legendary_chance = 0.14,
		sprite = "chest_royal",
		diamonds = 150,
	},
}

-- Free gift chest in the Hub (does not use a slot, opens instantly).
M.FREE_CHEST_INTERVAL = 4 * 3600
M.FREE_CHEST_RARITY = "wood"

-- Rewarded-ad diamonds in the shop.
M.AD_DIAMONDS = 5
M.AD_DIAMONDS_PER_DAY = 3

-- Clash Royale style upgrade requirements by level (level -> next)
M.CARD_REQ = {
	common    = { 2, 4, 10, 20, 40, 80, 150, 300, 500 },
	rare      = { 2, 4, 8, 16, 30, 60, 120, 200, 350 },
	epic      = { 1, 2, 4, 8, 15, 30, 60, 100, 200 },
	legendary = { 1, 2, 4, 8, 12, 20, 35, 50 },
}
M.CARD_GOLD = {
	common    = { 25, 60, 130, 260, 500, 900, 1600, 2800, 4500 },
	rare      = { 45, 110, 230, 450, 850, 1500, 2600, 4200, 6500 },
	epic      = { 90, 200, 420, 800, 1500, 2600, 4400, 7000, 10000 },
	legendary = { 150, 350, 750, 1400, 2600, 4500, 7500, 12000 },
}

M.UNLOCK_DIAMONDS = {
	common = 15,
	rare = 35,
	epic = 80,
	legendary = 150,
}

M.BOOSTERS = {
	shuffle = { id = "shuffle", sprite = "boost_shuffle", gold_cost = 60 },
	hammer = { id = "hammer", sprite = "boost_hammer", gold_cost = 80 },
	extra_move = { id = "extra_move", sprite = "boost_moves", gold_cost = 100 },
}
M.BOOSTER_ORDER = { "shuffle", "hammer", "extra_move" }

M.FIRST_AD_LEVEL = 4

-- Campaign stars: remaining HP ratio needed for 2 and 3 stars (1 star = any win).
M.STAR_HP = { 0.0, 0.45, 0.75 }
M.STAR_CHEST_EVERY = 6 -- every 6 campaign stars -> a bonus chest

-- 7-day login calendar (loops). A missed day does not reset the streak.
M.DAILY_REWARDS = {
	{ gold = 120 },
	{ diamonds = 10 },
	{ booster = "hammer", count = 2 },
	{ gold = 300 },
	{ chest = "silver" },
	{ diamonds = 25 },
	{ chest = "royal" },
}

-- Prestige leagues (PvP ladder).
M.LEAGUES = {
	{ id = "bronze",   min = 0,    color = "#d08a52" },
	{ id = "silver",   min = 300,  color = "#c9d6ee" },
	{ id = "gold",     min = 700,  color = "#ffd644" },
	{ id = "crystal",  min = 1200, color = "#59d8ff" },
	{ id = "master",   min = 2000, color = "#d26eff" },
	{ id = "champion", min = 3000, color = "#ff4a64" },
}

function M.league_index(prestige)
	local idx = 1
	for i, lg in ipairs(M.LEAGUES) do
		if (prestige or 0) >= lg.min then idx = i end
	end
	return idx
end

-- Trophy road: milestone list generated once (prestige -> reward).
M.TROPHY_ROAD = {}
do
	local at = 0
	for i = 1, 40 do
		at = at + (i <= 10 and 50 or (i <= 25 and 100 or 150))
		local reward
		if i % 10 == 0 then
			reward = { chest = "royal" }
		elseif i % 5 == 0 then
			reward = { diamonds = 20 + i }
		elseif i % 3 == 0 then
			reward = { chest = "silver" }
		elseif i % 2 == 0 then
			reward = { booster = M.BOOSTER_ORDER[(i / 2) % 3 + 1], count = 2 }
		else
			reward = { gold = 80 + i * 30 }
		end
		M.TROPHY_ROAD[i] = { at = at, reward = reward }
	end
end

return M
