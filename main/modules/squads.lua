-- Squad card catalog (18 squads across 4 rarities), Clash Royale scaling, and 2-crystal Rune Skills (pure Lua).
local config = require "main.modules.config"

local M = {}

M.LIST = {
	-- RED (Damage tier 1 — 6 squads: 2C, 2R, 1E, 1L)
	{
		id = "red_militia",
		color = "red",
		rarity = "common",
		units = 4,
		base_atk = 6,
		sprite = "squad_red_militia",
		style = "melee",
		fx = "fx_slash",
		trait = "none",
		runes = { "red", "red" },
		skill = { id = "shield_bash", mult = 1.55, effect = "shield", val = 6, fx = "fx_slash" },
		starter = true,
	},
	{
		id = "red_spearmen",
		color = "red",
		rarity = "common",
		units = 3,
		base_atk = 7,
		sprite = "squad_red_spearmen",
		style = "melee",
		fx = "fx_slash",
		trait = "pierce",
		runes = { "red", "blue" },
		skill = { id = "phalanx", mult = 1.65, effect = "pierce_shield", val = 6, pierce = 1.0, fx = "fx_slash" },
	},
	{
		id = "red_wolves",
		color = "red",
		rarity = "rare",
		units = 3,
		base_atk = 8,
		sprite = "squad_red_wolves",
		style = "melee",
		fx = "fx_slash",
		trait = "crit",
		runes = { "red", "red" },
		skill = { id = "pack_frenzy", mult = 1.60, effect = "burn", val = 6, dur = 2, fx = "fx_slash" },
	},
	{
		id = "red_pyromancer",
		color = "red",
		rarity = "rare",
		units = 2,
		base_atk = 9,
		sprite = "squad_red_pyromancer",
		style = "magic",
		fx = "proj_fire",
		trait = "none",
		runes = { "red", "yellow" },
		skill = { id = "molten_bomb", mult = 1.75, effect = "burn", val = 8, dur = 2, fx = "proj_fire" },
	},
	{
		id = "red_berserk",
		color = "red",
		rarity = "epic",
		units = 4,
		base_atk = 10,
		sprite = "squad_red_berserk",
		style = "melee",
		fx = "fx_slash",
		trait = "fury",
		runes = { "red", "green" },
		skill = { id = "whirlwind", mult = 1.85, effect = "fury_heal", val = 0.25, fx = "fx_slash" },
	},
	{
		id = "red_drake",
		color = "red",
		rarity = "legendary",
		units = 1,
		base_atk = 13,
		sprite = "squad_red_drake",
		style = "magic",
		fx = "proj_fire",
		trait = "crit",
		runes = { "red", "purple" },
		skill = { id = "inferno", mult = 2.25, effect = "burn", val = 11, dur = 2, fx = "proj_fire" },
	},

	-- YELLOW (Damage tier 2 — 6 squads: 2C, 2R, 1E, 1L)
	{
		id = "yellow_archers",
		color = "yellow",
		rarity = "common",
		units = 4,
		base_atk = 11,
		sprite = "squad_yellow_archers",
		style = "ranged",
		fx = "proj_arrow",
		trait = "none",
		runes = { "yellow", "yellow" },
		skill = { id = "arrow_hail", mult = 1.65, effect = "pierce", pierce = 0.4, fx = "proj_arrow" },
		starter = true,
	},
	{
		id = "yellow_falconer",
		color = "yellow",
		rarity = "common",
		units = 3,
		base_atk = 11,
		sprite = "squad_yellow_falconer",
		style = "ranged",
		fx = "proj_arrow",
		trait = "none",
		runes = { "yellow", "green" },
		skill = { id = "falcon_hunt", mult = 1.55, effect = "heal", val = 8, fx = "proj_arrow" },
	},
	{
		id = "yellow_crossbow",
		color = "yellow",
		rarity = "rare",
		units = 3,
		base_atk = 13,
		sprite = "squad_yellow_crossbow",
		style = "ranged",
		fx = "proj_bolt",
		trait = "pierce",
		runes = { "yellow", "red" },
		skill = { id = "snipe", mult = 1.85, effect = "pierce", pierce = 1.0, fx = "proj_bolt" },
	},
	{
		id = "yellow_assassins",
		color = "yellow",
		rarity = "rare",
		units = 2,
		base_atk = 13,
		sprite = "squad_yellow_assassins",
		style = "ranged",
		fx = "proj_venom",
		trait = "crit",
		runes = { "yellow", "green" },
		skill = { id = "venom_darts", mult = 1.60, effect = "poison", val = 7, dur = 3, fx = "proj_venom" },
	},
	{
		id = "yellow_paladin",
		color = "yellow",
		rarity = "epic",
		units = 2,
		base_atk = 15,
		sprite = "squad_yellow_paladin",
		style = "melee",
		fx = "fx_slash",
		trait = "bastion",
		runes = { "yellow", "blue" },
		skill = { id = "judgment", mult = 1.55, effect = "shield_slam", val = 0.6, fx = "fx_slash" },
	},
	{
		id = "yellow_thunder",
		color = "yellow",
		rarity = "legendary",
		units = 1,
		base_atk = 18,
		sprite = "squad_yellow_thunder",
		style = "magic",
		fx = "proj_lightning",
		trait = "pierce",
		runes = { "yellow", "blue" },
		skill = { id = "tempest", mult = 2.15, effect = "shatter", val = 0.6, fx = "proj_lightning" },
	},

	-- PURPLE (Damage tier 3 — 6 squads: 2C, 2R, 1E, 1L)
	{
		id = "purple_cultists",
		color = "purple",
		rarity = "common",
		units = 3,
		base_atk = 17,
		sprite = "squad_purple_cultists",
		style = "magic",
		fx = "proj_spell",
		trait = "none",
		runes = { "purple", "purple" },
		skill = { id = "void_bolts", mult = 1.70, effect = "none", fx = "proj_spell" },
		starter = true,
	},
	{
		id = "purple_imps",
		color = "purple",
		rarity = "common",
		units = 4,
		base_atk = 16,
		sprite = "squad_purple_imps",
		style = "melee",
		fx = "fx_slash",
		trait = "crit",
		runes = { "purple", "red" },
		skill = { id = "imp_ambush", mult = 1.65, effect = "burn", val = 6, dur = 2, fx = "fx_slash" },
	},
	{
		id = "purple_necro",
		color = "purple",
		rarity = "rare",
		units = 2,
		base_atk = 19,
		sprite = "squad_purple_necro",
		style = "magic",
		fx = "proj_spell",
		trait = "drain",
		runes = { "purple", "green" },
		skill = { id = "siphon", mult = 1.70, effect = "lifesteal", val = 0.45, fx = "proj_spell" },
	},
	{
		id = "purple_banshee",
		color = "purple",
		rarity = "rare",
		units = 2,
		base_atk = 18,
		sprite = "squad_purple_banshee",
		style = "magic",
		fx = "proj_spell",
		trait = "none",
		runes = { "purple", "blue" },
		skill = { id = "frost_wail", mult = 1.55, effect = "freeze", val = 1, fx = "proj_spell" },
	},
	{
		id = "purple_golem",
		color = "purple",
		rarity = "epic",
		units = 1,
		base_atk = 23,
		sprite = "squad_purple_golem",
		style = "melee",
		fx = "fx_slash",
		trait = "crush",
		runes = { "purple", "blue" },
		skill = { id = "quake", mult = 1.75, effect = "crush", val = 1.5, fx = "fx_slash" },
	},
	{
		id = "purple_reaper",
		color = "purple",
		rarity = "legendary",
		units = 1,
		base_atk = 25,
		sprite = "squad_purple_reaper",
		style = "melee",
		fx = "fx_reap",
		trait = "fury",
		runes = { "purple", "red" },
		skill = { id = "execution", mult = 2.05, effect = "execute", val = 1.65, fx = "fx_reap" },
	},
	{
		id = "red_templar",
		color = "red",
		rarity = "epic",
		units = 2,
		base_atk = 22,
		sprite = "squad_red_templar",
		style = "melee",
		fx = "fx_slash",
		trait = "bastion",
		runes = { "red", "yellow" },
		skill = { id = "cleanse_smite", mult = 1.80, effect = "cleanse_burn", val = 7, dur = 2, fx = "fx_slash" },
	},
	{
		id = "yellow_valkyrie",
		color = "yellow",
		rarity = "epic",
		units = 2,
		base_atk = 23,
		sprite = "squad_yellow_valkyrie",
		style = "melee",
		fx = "proj_lightning",
		trait = "fury",
		runes = { "yellow", "purple" },
		skill = { id = "radiant_rally", mult = 1.75, effect = "rally_charge", val = 9, fx = "proj_lightning" },
	},
	{
		id = "purple_witch",
		color = "purple",
		rarity = "rare",
		units = 2,
		base_atk = 19,
		sprite = "squad_purple_witch",
		style = "magic",
		fx = "proj_spell",
		trait = "drain",
		runes = { "purple", "green" },
		skill = { id = "curse_hex", mult = 1.75, effect = "hex", val = 6, dur = 3, fx = "proj_spell" },
	},
}

M.BY_ID = {}
for _, s in ipairs(M.LIST) do M.BY_ID[s.id] = s end

function M.get(id)
	return M.BY_ID[id]
end

function M.by_color(color)
	local out = {}
	for _, s in ipairs(M.LIST) do
		if s.color == color then out[#out + 1] = s end
	end
	return out
end

function M.power(id, level)
	local s = M.BY_ID[id]
	if not s then return 6 end
	local lvl = math.max(1, level or 1)
	return math.floor(s.base_atk * (1 + 0.22 * (lvl - 1)) + 0.5)
end

function M.skill_power(id, level)
	local s = M.BY_ID[id]
	if not (s and s.skill) then return M.power(id, level) end
	local base = M.power(id, level)
	local lvl_bonus = 1 + 0.05 * math.max(0, (level or 1) - 1)
	return math.floor(base * s.skill.mult * lvl_bonus + 0.5)
end

function M.upgrade_req(id, level)
	local s = M.BY_ID[id]
	if not s then return nil end
	return config.CARD_REQ[s.rarity][level]
end

function M.upgrade_gold(id, level)
	local s = M.BY_ID[id]
	if not s then return nil end
	return config.CARD_GOLD[s.rarity][level]
end

function M.unlock_diamonds(id)
	local s = M.BY_ID[id]
	if not s then return 50 end
	return config.UNLOCK_DIAMONDS[s.rarity]
end

return M
