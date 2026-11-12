-- Campaign (30 stages in 5 biomes, bosses, stars) and PvP bot matchmaking (pure Lua).
local rng = require "main.modules.rng"
local config = require "main.modules.config"
local squads_db = require "main.modules.squads"

local M = {}

-- Biomes: arena tint + palette for the world map.
M.BIOMES = {
	{ id = "woods",  name_key = "BIOME_1", tint = "#9fe0a0", path = "#5fbf6a" },
	{ id = "crypt",  name_key = "BIOME_2", tint = "#a9c4ff", path = "#7f9bd9" },
	{ id = "ash",    name_key = "BIOME_3", tint = "#ffb38a", path = "#e0743f" },
	{ id = "void",   name_key = "BIOME_4", tint = "#d2a6ff", path = "#a865f0" },
	{ id = "throne", name_key = "BIOME_5", tint = "#ff9a9a", path = "#e0445a" },
}
M.STAGES_PER_BIOME = 6

local POOLS = {
	red = { "red_militia", "red_spearmen", "red_wolves", "red_pyromancer", "red_berserk", "red_drake" },
	yellow = { "yellow_archers", "yellow_falconer", "yellow_crossbow", "yellow_assassins", "yellow_paladin", "yellow_thunder" },
	purple = { "purple_cultists", "purple_imps", "purple_necro", "purple_banshee", "purple_golem", "purple_reaper" },
}

local BIOME_FACES = {
	{ "face_goblin", "face_goblin", "face_orc" },
	{ "face_skeleton", "face_necromancer", "face_skeleton" },
	{ "face_orc", "face_dragon", "face_orc" },
	{ "face_necromancer", "face_skeleton", "face_necromancer" },
	{ "face_dragon", "face_orc", "face_dragon" },
}

-- Hand-made onboarding stages (biome 1). HP / moves / levels come from the scaling model below
-- unless set explicitly.
local HAND = {
	{ name_key = "ENEMY_SCOUT", face = "face_goblin", hp = 135, moves = 1, tutorial = true,
	  squads = { red = "red_militia", yellow = "yellow_archers", purple = "purple_cultists" } },
	{ name_key = "ENEMY_RAIDER", face = "face_goblin", moves = 1,
	  squads = { red = "red_spearmen", yellow = "yellow_falconer", purple = "purple_imps" } },
	{ name_key = "ENEMY_SHAMAN", face = "face_goblin", moves = 2,
	  squads = { red = "red_pyromancer", yellow = "yellow_archers", purple = "purple_cultists" } },
	{ name_key = "ENEMY_WARCHIEF", face = "face_orc",
	  squads = { red = "red_berserk", yellow = "yellow_assassins", purple = "purple_imps" } },
	{ name_key = "ENEMY_BONE", face = "face_skeleton",
	  squads = { red = "red_spearmen", yellow = "yellow_crossbow", purple = "purple_banshee" } },
	{ name_key = "ENEMY_HUNTER", face = "face_orc",
	  squads = { red = "red_wolves", yellow = "yellow_assassins", purple = "purple_cultists" } },
}

local ENEMY_KEYS = {
	"ENEMY_SCOUT", "ENEMY_RAIDER", "ENEMY_SHAMAN", "ENEMY_WARCHIEF", "ENEMY_BONE", "ENEMY_HUNTER",
	"ENEMY_WARLOCK", "ENEMY_LICH", "ENEMY_KNIGHT", "ENEMY_DARK", "ENEMY_DRAKE", "ENEMY_OVERLORD",
}
local BOSS_KEYS = { "ENEMY_HUNTER", "ENEMY_LICH", "ENEMY_DRAKE", "ENEMY_DARK", "ENEMY_OVERLORD" }

-- Expected player build when first reaching stage n (avg card level, moves, commander HP).
-- Enemies are scaled against it; the simulation calibrates HP_K / BOSS_K.
function M.expected_build(n)
	local lvl = 1 + math.floor((n - 1) / 4)
	local moves = math.min(config.MAX_MOVES, config.START_MOVES + math.floor((n - 1) / 5))
	local cmd = 1 + 3 * (lvl - 1) + math.floor(n / 2)
	return lvl, moves, config.commander_hp(cmd, moves, 0)
end

M.HP_K = 0.66
M.BOSS_K = 1.12
-- Gentle onboarding ramp: early enemies get less HP
local function hp_ramp(n)
	if n <= 6 then return 0.62 + n * 0.02 end
	if n <= 12 then return 0.9 end
	return 1
end

-- Rarer squads hit much harder (legendary ~2x a common). Pick the level that gives roughly the
-- power of a reference common/rare squad at `lvl`, so variety does not spike difficulty.
local POWER_REF = { red = 7, yellow = 12, purple = 18 }
-- Traits and stronger skills of rare squads are worth extra power
local RARITY_K = { common = 1, rare = 1.08, epic = 1.25, legendary = 1.35 }
function M.level_for_power(id, col, lvl)
	local info = squads_db.get(id)
	local target = POWER_REF[col] * (1 + 0.22 * (lvl - 1))
	local eff = info.base_atk * (RARITY_K[info.rarity] or 1)
	return math.max(1, math.min(10, math.floor(1 + (target / eff - 1) / 0.22 + 0.5)))
end

local function gen_stage(n, hand)
	local r = rng.new(n * 7919 + 17)
	local biome = math.floor((n - 1) / M.STAGES_PER_BIOME) + 1
	local in_biome = (n - 1) % M.STAGES_PER_BIOME + 1
	local boss = in_biome == M.STAGES_PER_BIOME
	local lvl, moves, hp = M.expected_build(n)
	local tier = math.min(6, 1 + math.floor((n + 2) / 5))
	local squads = {}
	for _, col in ipairs(config.ATTACK_COLORS) do
		local pool = POOLS[col]
		local pick = (hand and hand.squads[col]) or (boss and pool[tier]) or pool[r:int(math.max(1, tier - 2), tier)]
		squads[col] = { id = pick, lvl = M.level_for_power(pick, col, lvl + (boss and 1 or 0)) }
	end
	local faces = BIOME_FACES[biome]
	local chest = boss and "royal" or ((in_biome % 3 == 0) and "silver" or "wood")
	if boss and n == M.STAGES_PER_BIOME then chest = "silver" end
	local st = {
		name_key = boss and BOSS_KEYS[biome] or ENEMY_KEYS[r:int(5, 12)],
		face = boss and faces[3] or faces[r:int(1, 2)],
		hp = math.floor(hp * M.HP_K * hp_ramp(n) * (boss and M.BOSS_K or 1) + 0.5),
		moves = math.max(1, math.min(6, moves)),
		diff = n <= 6 and 1 or (n < 14 and 2 or 3),
		chest = chest,
		gold = 40 + n * 12,
		squads = squads,
		boss = boss,
	}
	if hand then
		for k, v in pairs(hand) do
			if k ~= "squads" then st[k] = v end
		end
	end
	return st
end

function M.build()
	M.STAGES = {}
	for n = 1, M.STAGES_PER_BIOME * #M.BIOMES do
		local st = gen_stage(n, HAND[n])
		st.id = n
		st.zone = math.floor((n - 1) / M.STAGES_PER_BIOME) + 1
		M.STAGES[n] = st
	end
	M.COUNT = #M.STAGES
end
M.build()

function M.get_stage(id)
	return M.STAGES[math.max(1, math.min(#M.STAGES, id or 1))]
end

function M.biome(stage_id)
	local st = M.get_stage(stage_id)
	return M.BIOMES[st.zone] or M.BIOMES[1]
end

-- 1..3 stars from remaining HP ratio (only for wins).
function M.stars_for(hp, max_hp)
	local ratio = (hp or 0) / math.max(1, max_hp or 1)
	local stars = 1
	for i = 2, 3 do
		if ratio >= config.STAR_HP[i] then stars = i end
	end
	return stars
end

local PVP_NAMES = {
	"ShadowFang", "Valkor", "GrimHelm", "AshBorn", "Kragor", "NightVeil", "IronCrow", "Morwen",
	"DreadSpark", "Zarek", "Brannoc", "Ysolde", "Kaelthar", "Vexis", "Thorn", "Mirelle",
	"Oskar_77", "RuneLord", "Gemsmith", "Hexa", "Darkwind", "Pyrra", "Stormjaw", "Lunaria",
}
local PVP_FACES = { "face_orc", "face_skeleton", "face_necromancer", "face_goblin", "face_dragon" }

function M.pvp_opponent(prestige, seed, player_power)
	local r = rng.new(seed or 1337)
	prestige = prestige or 0
	local tier = math.floor(prestige / 75)
	-- Prestige maps to an "equivalent campaign stage"; then blend toward the player's own build
	-- so the bot is a fair mirror (losing streaks lower prestige -> easier bots).
	local eq = math.max(2, math.min(M.COUNT, 2 + math.floor(prestige / 60)))
	local lvl, moves, hp = M.expected_build(eq)
	hp = hp * M.HP_K
	if player_power then
		hp = (hp + player_power.hp) / 2
		moves = (moves + player_power.moves) / 2
		lvl = (lvl + player_power.avg_lvl) / 2
	end
	hp = math.floor(hp * (0.82 + r:float() * 0.16) + 0.5)
	moves = math.max(1, math.min(6, math.floor(moves + 0.5)))
	lvl = math.max(1, math.min(9, math.floor(lvl + 0.5)))
	local diff = tier >= 4 and 3 or (tier >= 2 and 2 or 1)
	local roll = r:float()
	local chest = roll < 0.10 and "royal" or (roll < 0.42 and "silver" or "wood")
	local pool_top = math.max(2, math.min(6, 2 + math.floor(tier / 2)))
	local sq = {}
	for _, col in ipairs(config.ATTACK_COLORS) do
		local id = POOLS[col][r:int(1, pool_top)]
		sq[col] = { id = id, lvl = M.level_for_power(id, col, lvl) }
	end
	return {
		is_pvp = true,
		name = r:pick(PVP_NAMES),
		face = r:pick(PVP_FACES),
		prestige = math.max(0, prestige + r:int(-20, 25)),
		hp = hp,
		moves = moves,
		diff = diff,
		chest = chest,
		gold = 45 + tier * 18,
		squads = sq,
	}
end

return M
