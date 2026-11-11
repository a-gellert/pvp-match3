-- Campaign levels (including Onboarding Level 1) and PvP bot matchmaking (pure Lua).
local rng = require "main.modules.rng"

local M = {}

M.STAGES = {
	{ id = 1, zone = 1, name_key = "ENEMY_SCOUT",  face = "face_goblin",      hp = 42,  moves = 1, diff = 1, chest = "wood",   gold = 40,  tutorial = true,
	  squads = { red = { id = "red_militia", lvl = 1 }, yellow = { id = "yellow_archers", lvl = 1 }, purple = { id = "purple_cultists", lvl = 1 } } },
	{ id = 2, zone = 1, name_key = "ENEMY_RAIDER", face = "face_goblin",      hp = 58,  moves = 1, diff = 1, chest = "wood",   gold = 50,
	  squads = { red = { id = "red_spearmen", lvl = 1 }, yellow = { id = "yellow_falconer", lvl = 1 }, purple = { id = "purple_imps", lvl = 1 } } },
	{ id = 3, zone = 1, name_key = "ENEMY_SHAMAN", face = "face_goblin",      hp = 72,  moves = 2, diff = 1, chest = "wood",   gold = 60,
	  squads = { red = { id = "red_pyromancer", lvl = 1 }, yellow = { id = "yellow_archers", lvl = 1 }, purple = { id = "purple_cultists", lvl = 2 } } },
	{ id = 4, zone = 1, name_key = "ENEMY_WARCHIEF", face = "face_orc",       hp = 95,  moves = 2, diff = 2, chest = "silver", gold = 85,  boss = true,
	  squads = { red = { id = "red_berserk", lvl = 1 }, yellow = { id = "yellow_assassins", lvl = 1 }, purple = { id = "purple_imps", lvl = 2 } } },

	{ id = 5, zone = 2, name_key = "ENEMY_BONE",   face = "face_skeleton",    hp = 115, moves = 2, diff = 2, chest = "wood",   gold = 95,
	  squads = { red = { id = "red_spearmen", lvl = 2 }, yellow = { id = "yellow_crossbow", lvl = 2 }, purple = { id = "purple_banshee", lvl = 1 } } },
	{ id = 6, zone = 2, name_key = "ENEMY_HUNTER", face = "face_orc",         hp = 135, moves = 3, diff = 2, chest = "silver", gold = 110,
	  squads = { red = { id = "red_wolves", lvl = 2 },  yellow = { id = "yellow_assassins", lvl = 2 }, purple = { id = "purple_cultists", lvl = 3 } } },
	{ id = 7, zone = 2, name_key = "ENEMY_WARLOCK",face = "face_necromancer", hp = 160, moves = 3, diff = 2, chest = "wood",   gold = 125,
	  squads = { red = { id = "red_pyromancer", lvl = 2 }, yellow = { id = "yellow_paladin", lvl = 1 },  purple = { id = "purple_necro", lvl = 2 } } },
	{ id = 8, zone = 2, name_key = "ENEMY_LICH",   face = "face_skeleton",    hp = 200, moves = 3, diff = 3, chest = "royal",  gold = 175, boss = true,
	  squads = { red = { id = "red_berserk", lvl = 2 }, yellow = { id = "yellow_paladin", lvl = 2 },  purple = { id = "purple_banshee", lvl = 2 } } },

	{ id = 9, zone = 3, name_key = "ENEMY_KNIGHT", face = "face_orc",         hp = 235, moves = 4, diff = 3, chest = "silver", gold = 190,
	  squads = { red = { id = "red_wolves", lvl = 4 },  yellow = { id = "yellow_paladin", lvl = 3 },  purple = { id = "purple_necro", lvl = 3 } } },
	{ id = 10, zone = 3, name_key = "ENEMY_DARK",  face = "face_necromancer", hp = 275, moves = 4, diff = 3, chest = "silver", gold = 220,
	  squads = { red = { id = "red_pyromancer", lvl = 4 }, yellow = { id = "yellow_thunder", lvl = 2 }, purple = { id = "purple_golem", lvl = 2 } } },
	{ id = 11, zone = 3, name_key = "ENEMY_DRAKE", face = "face_dragon",      hp = 330, moves = 5, diff = 3, chest = "royal",  gold = 280, boss = true,
	  squads = { red = { id = "red_drake", lvl = 3 }, yellow = { id = "yellow_thunder", lvl = 3 },  purple = { id = "purple_reaper", lvl = 2 } } },
	{ id = 12, zone = 3, name_key = "ENEMY_OVERLORD", face = "face_dragon",   hp = 400, moves = 6, diff = 3, chest = "royal",  gold = 350, boss = true,
	  squads = { red = { id = "red_drake", lvl = 4 }, yellow = { id = "yellow_thunder", lvl = 4 },  purple = { id = "purple_reaper", lvl = 4 } } },
}

function M.get_stage(id)
	return M.STAGES[math.max(1, math.min(#M.STAGES, id or 1))]
end

local PVP_NAMES = {
	"ShadowFang", "Valkor", "GrimHelm", "AshBorn", "Kragor",
	"NightVeil", "IronCrow", "Morwen", "DreadSpark", "Zarek",
}
local PVP_FACES = { "face_orc", "face_skeleton", "face_necromancer", "face_goblin", "face_dragon" }
local RED_POOL = { "red_militia", "red_spearmen", "red_wolves", "red_pyromancer", "red_berserk", "red_drake" }
local YEL_POOL = { "yellow_archers", "yellow_falconer", "yellow_crossbow", "yellow_assassins", "yellow_paladin", "yellow_thunder" }
local PUR_POOL = { "purple_cultists", "purple_imps", "purple_necro", "purple_banshee", "purple_golem", "purple_reaper" }

function M.pvp_opponent(prestige, seed)
	local r = rng.new(seed or 1337)
	local tier = math.floor((prestige or 0) / 75)
	local lvl = math.max(1, math.min(6, 1 + math.floor(tier / 2)))
	local moves = math.max(1, math.min(6, 1 + math.floor((tier + 1) / 2)))
	local hp = 68 + tier * 24 + r:int(-8, 12)
	local diff = tier >= 4 and 3 or (tier >= 2 and 2 or 1)
	local chest = r:float() < 0.12 and "royal" or (r:float() < 0.42 and "silver" or "wood")
	return {
		is_pvp = true,
		name = r:pick(PVP_NAMES),
		face = r:pick(PVP_FACES),
		prestige = math.max(0, (prestige or 0) + r:int(-20, 25)),
		hp = hp,
		moves = moves,
		diff = diff,
		chest = chest,
		gold = 45 + tier * 18,
		squads = {
			red = { id = r:pick(RED_POOL), lvl = lvl },
			yellow = { id = r:pick(YEL_POOL), lvl = lvl },
			purple = { id = r:pick(PUR_POOL), lvl = lvl },
		},
	}
end

return M
