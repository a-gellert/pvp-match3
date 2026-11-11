-- Balance constants and rules for Gem Vanguard (pure Lua).
local M = {}

M.GRID = 7
M.COLORS = { "red", "yellow", "purple", "green", "blue" }
M.COLOR_INDEX = { red = 1, yellow = 2, purple = 3, green = 4, blue = 5 }
M.ATTACK_COLORS = { "red", "yellow", "purple" }

-- Damage/effect multipliers per matched gem beyond base power:
-- Red = Damage tier 1, Yellow = tier 2, Purple = tier 3
M.GEM_MULT = {
	red = 1.0,
	yellow = 2.0,
	purple = 3.0,
	green = 1.0,
	blue = 1.0,
}

M.BASE_HP = 70
M.HP_PER_PRESTIGE_BRACKET = 12
M.SHIELD_CAP_RATIO = 0.65
M.BASE_HEAL = 10
M.BASE_SHIELD = 10
M.FURY_TURN = 12 -- from turn 12+, damage +20% per turn so battles always end

M.MIN_MOVES = 1
M.MAX_MOVES = 7
-- Gold cost to upgrade max_moves from (n-1) to n
M.MOVE_COSTS = { 0, 80, 200, 450, 900, 1800, 3500 }

M.PRESTIGE_WIN = 25
M.PRESTIGE_LOSE = 12
M.PVP_PRESTIGE_WIN = 32
M.PVP_PRESTIGE_LOSE = 18

M.MAX_CHEST_SLOTS = 4
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
	},
}

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

M.FIRST_AD_LEVEL = 4

return M
