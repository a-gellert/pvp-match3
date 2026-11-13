-- Daily meta-loop (pure Lua): day clock, 3 daily quests, 7-day login calendar, shop daily deals.
-- Works on the progress data table passed in, so it has no dependency on progress.lua.
local config = require "main.modules.config"
local squads = require "main.modules.squads"
local rng = require "main.modules.rng"

local M = {}

M.time_offset = 0 -- debug: shift the clock (seconds)

function M.now()
	return os.time() + M.time_offset
end

-- Local calendar day id (changes at local midnight).
function M.today()
	local t = os.date("*t", M.now())
	return t.year * 1000 + t.yday
end

-- Day id of the previous calendar day (handles the year boundary).
function M.yesterday()
	local t = os.date("*t", M.now())
	t.day = t.day - 1
	t.hour = 12
	local y = os.date("*t", os.time(t))
	return y.year * 1000 + y.yday
end

function M.seconds_to_reset()
	local t = os.date("*t", M.now())
	return math.max(1, 86400 - (t.hour * 3600 + t.min * 60 + t.sec))
end

-- Quest pool: stat key -> targets by tier, reward per tier.
M.POOL = {
	{ id = "win",         stat = "wins",        targets = { 2, 3, 5 },       gold = { 70, 110, 170 } },
	{ id = "win_pvp",     stat = "pvp_wins",    targets = { 1, 2, 3 },       diamonds = { 4, 6, 9 } },
	{ id = "gems_red",    stat = "gems_red",    targets = { 30, 55, 90 },    gold = { 50, 80, 130 } },
	{ id = "gems_yellow", stat = "gems_yellow", targets = { 30, 55, 90 },    gold = { 50, 80, 130 } },
	{ id = "gems_purple", stat = "gems_purple", targets = { 30, 55, 90 },    gold = { 50, 80, 130 } },
	{ id = "gems_green",  stat = "gems_green",  targets = { 30, 55, 90 },    gold = { 50, 80, 130 } },
	{ id = "gems_blue",   stat = "gems_blue",   targets = { 30, 55, 90 },    gold = { 50, 80, 130 } },
	{ id = "combos",      stat = "combos",      targets = { 4, 8, 12 },      gold = { 60, 100, 150 } },
	{ id = "skills",      stat = "skills",      targets = { 3, 6, 10 },      diamonds = { 3, 5, 8 } },
	{ id = "specials",    stat = "specials",    targets = { 3, 6, 10 },      gold = { 60, 100, 150 } },
	{ id = "damage",      stat = "damage",      targets = { 250, 600, 1400 }, gold = { 70, 120, 180 } },
	{ id = "chests",      stat = "chests",      targets = { 1, 2, 3 },       diamonds = { 3, 5, 7 } },
	{ id = "upgrade",     stat = "upgrades",    targets = { 1, 2, 3 },       gold = { 60, 100, 150 } },
	{ id = "boosters",    stat = "boosters",    targets = { 1, 2, 3 },       gold = { 50, 80, 120 } },
	{ id = "stars",       stat = "stars",       targets = { 2, 4, 6 },       diamonds = { 3, 5, 7 } },
}
M.BY_ID = {}
for _, q in ipairs(M.POOL) do M.BY_ID[q.id] = q end

M.QUESTS_PER_DAY = 3
M.BONUS_CHEST = "silver"

local DEAL_PRICE = { common = 9, rare = 32, epic = 160, legendary = 700 }
local DEAL_COUNT = { common = { 8, 14 }, rare = { 3, 6 }, epic = { 1, 2 }, legendary = { 1, 1 } }

local function tier_for(data)
	local p = (data.max_prestige or 0) + (data.max_stage_unlocked or 1) * 20
	if p >= 900 then return 3 elseif p >= 250 then return 2 end
	return 1
end

local function gen_quests(data, day)
	local r = rng.new(day * 31 + 7)
	local pool = {}
	for _, q in ipairs(M.POOL) do
		-- PvP / stars quests only once the modes are relevant
		local ok = true
		if q.id == "win_pvp" and (data.max_stage_unlocked or 1) < 3 then ok = false end
		if q.id == "upgrade" and not data.onboarding_done then ok = false end
		if ok then pool[#pool + 1] = q end
	end
	r:shuffle(pool)
	local tier = tier_for(data)
	local out = {}
	for i = 1, M.QUESTS_PER_DAY do
		local q = pool[i]
		out[i] = {
			id = q.id,
			target = q.targets[tier],
			prog = 0,
			claimed = false,
			gold = q.gold and q.gold[tier] or nil,
			diamonds = q.diamonds and q.diamonds[tier] or nil,
		}
	end
	return out
end

local function gen_deals(data, day)
	local r = rng.new(day * 131 + 3)
	local deals = {}
	local used = {}
	local rarities = { "common", "rare", r:float() < 0.35 and "epic" or "rare" }
	if r:float() < 0.08 then rarities[3] = "legendary" end
	for i, rar in ipairs(rarities) do
		local pool = {}
		for _, s in ipairs(squads.LIST) do
			if s.rarity == rar and not used[s.id] then pool[#pool + 1] = s.id end
		end
		local id = r:pick(pool)
		used[id] = true
		local cnt = r:int(DEAL_COUNT[rar][1], DEAL_COUNT[rar][2])
		deals[i] = { id = id, count = cnt, price = DEAL_PRICE[rar] * cnt, bought = false }
	end
	return deals
end

-- Make sure today's daily block exists; returns true when a new day started.
function M.refresh(data)
	local day = M.today()
	local d = data.daily
	if d and d.day == day then return false end
	data.daily = {
		day = day,
		quests = gen_quests(data, day),
		bonus_claimed = false,
		deals = gen_deals(data, day),
		ad_diamonds = 0,
	}
	return true
end

-- Add progress to every active quest that tracks this stat.
function M.on_event(data, stat, amount)
	local d = data.daily
	if not (d and d.quests) or (amount or 0) <= 0 then return end
	for _, q in ipairs(d.quests) do
		local def = M.BY_ID[q.id]
		if def and def.stat == stat and not q.claimed then
			q.prog = math.min(q.target, q.prog + amount)
		end
	end
end

function M.is_done(q)
	return q.prog >= q.target
end

function M.claimable_count(data)
	local d = data.daily
	if not d then return 0 end
	local n = 0
	for _, q in ipairs(d.quests) do
		if M.is_done(q) and not q.claimed then n = n + 1 end
	end
	if M.bonus_ready(data) then n = n + 1 end
	return n
end

function M.all_claimed(data)
	local d = data.daily
	if not d then return false end
	for _, q in ipairs(d.quests) do
		if not q.claimed then return false end
	end
	return true
end

function M.bonus_ready(data)
	return data.daily and not data.daily.bonus_claimed and M.all_claimed(data)
end

-- Mark a quest claimed and return its reward table (caller grants it).
function M.claim(data, idx)
	local q = data.daily and data.daily.quests[idx]
	if not q or q.claimed or not M.is_done(q) then return nil end
	q.claimed = true
	return { gold = q.gold, diamonds = q.diamonds }
end

function M.claim_bonus(data)
	if not M.bonus_ready(data) then return nil end
	data.daily.bonus_claimed = true
	return { chest = M.BONUS_CHEST }
end

-- ---- 7-day login calendar
function M.login_pending(data)
	local lg = data.login or {}
	return lg.last_day ~= M.today()
end

function M.login_index(data)
	local lg = data.login or {}
	return ((lg.count or 0) % #config.DAILY_REWARDS) + 1
end

function M.claim_login(data)
	if not M.login_pending(data) then return nil end
	data.login = data.login or {}
	local idx = M.login_index(data)
	data.login.last_day = M.today()
	data.login.count = (data.login.count or 0) + 1
	return config.DAILY_REWARDS[idx], idx
end

return M
