-- Squad card catalog and Clash Royale style level scaling (pure Lua).
local config = require "main.modules.config"

local M = {}

M.LIST = {
	-- RED (Damage tier 1)
	{
		id = "red_militia",
		color = "red",
		rarity = "common",
		units = 5,
		base_atk = 6,
		sprite = "squad_red_militia",
		style = "melee",
		fx = "fx_slash",
		trait = "none",
		starter = true,
	},
	{
		id = "red_wolves",
		color = "red",
		rarity = "rare",
		units = 4,
		base_atk = 8,
		sprite = "squad_red_wolves",
		style = "melee",
		fx = "fx_slash",
		trait = "crit", -- 25% chance for x1.5 damage
	},
	{
		id = "red_berserk",
		color = "red",
		rarity = "epic",
		units = 2,
		base_atk = 10,
		sprite = "squad_red_berserk",
		style = "melee",
		fx = "fx_slash",
		trait = "fury", -- +35% damage when hero HP < 50%
	},

	-- YELLOW (Damage tier 2)
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
		starter = true,
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
		trait = "pierce", -- ignores 50% of enemy shield
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
		trait = "bastion", -- grants +4 shield on attack
	},

	-- PURPLE (Damage tier 3)
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
		starter = true,
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
		trait = "drain", -- heals hero for 25% of damage dealt
	},
	{
		id = "purple_golem",
		color = "purple",
		rarity = "epic",
		units = 1,
		base_atk = 24,
		sprite = "squad_purple_golem",
		style = "melee",
		fx = "fx_slash",
		trait = "crush", -- +30% bonus damage vs enemy shield
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
