-- Quests tab (Druid scroll): 7-day login calendar, 3 daily quests, all-done bonus chest,
-- reset timer and the next trophy-road milestone.
local ui = require "main.gui.ui"
local widgets = require "main.gui.widgets"
local config = require "main.modules.config"
local progress = require "main.modules.progress"
local quests = require "main.modules.quests"
local i18n = require "main.modules.i18n"
local audio = require "main.modules.audio"

local M = {}
local V4 = vmath.vector4

local QUEST_ICON = {
	wins = "icon_pvp", pvp_wins = "icon_trophy", combos = "icon_fire", skills = "icon_star",
	specials = "spec_bomb", damage = "icon_sword", chests = "chest_wood", upgrades = "icon_cards",
	boosters = "boost_hammer", stars = "icon_star",
	gems_red = "gem_red", gems_yellow = "gem_yellow", gems_purple = "gem_purple", gems_green = "gem_green", gems_blue = "gem_blue",
}

local function reward_of(day)
	return config.DAILY_REWARDS[day]
end

local function calendar(app, C, y, w)
	local d = progress.data
	local pending = quests.login_pending(d)
	local today = quests.login_index(d) -- next day to claim
	local count = (d.login and d.login.count) or 0
	local cycle_done = count % #config.DAILY_REWARDS -- days already claimed in this cycle
	local cols = 7
	local tw = (w - 20 - (cols - 1) * 8) / cols
	local th = 150
	for i = 1, 7 do
		local x = -w / 2 + 10 + tw / 2 + (i - 1) * (tw + 8)
		local claimed = i <= cycle_done
		local is_today = pending and i == today
		local frame = is_today and "card_legendary" or (claimed and "panel_dark" or (i == 7 and "card_epic" or "card_common"))
		local box = ui.slice(C, frame, x, y, tw, th, claimed and V4(0.6, 0.62, 0.7, 1) or ui.WHITE, 16)
		ui.label(box, i18n.t("DAY_FMT", { n = i }), 0, th / 2 - 20, 15, is_today and ui.GOLD or ui.DIM, tw - 8)
		local rw = reward_of(i)
		local icon, amount
		if rw.gold then icon, amount = "icon_gold", "+" .. rw.gold
		elseif rw.diamonds then icon, amount = "icon_diamond", "+" .. rw.diamonds
		elseif rw.booster then icon, amount = config.BOOSTERS[rw.booster].sprite, "x" .. (rw.count or 1)
		else icon, amount = config.CHESTS[rw.chest].sprite, "" end
		ui.icon(box, icon, 0, 4, math.min(tw - 16, rw.chest and 64 or 50))
		if amount ~= "" then ui.label(box, amount, 0, -th / 2 + 22, 17, ui.BONE, tw - 8) end
		if claimed then
			ui.box(box, "icon_check", 0, 4, 46, 46)
		elseif is_today then
			ui.pulse(box, 1.05, 0.5)
			ui.badge(box, tw / 2 - 6, th / 2 - 6, 1, 26)
			ui.button(box, function() app.open_popup("daily") end)
		end
	end
	return th
end

local function quest_row(app, C, idx, q, y, w)
	local def = quests.BY_ID[q.id]
	local done = quests.is_done(q)
	local h = 128
	local box = ui.slice(C, q.claimed and "panel_dark" or (done and "card_rare" or "panel_stone"), 0, y, w, h, q.claimed and V4(0.7, 0.72, 0.8, 1) or ui.WHITE, 20)
	ui.icon(box, QUEST_ICON[def.stat] or "icon_quest", -w / 2 + 54, 6, 64)
	local tx = -w / 2 + 104
	local tw = w - 104 - 200
	ui.label(box, i18n.t("Q_" .. q.id, { n = q.target }), tx, 22, 20, ui.BONE, tw, { pivot = gui.PIVOT_W })
	ui.bar(box, tx + tw / 2, -18, tw, 28, math.min(1, q.prog / q.target), done and ui.GREEN or ui.BLUE,
		{ text = math.min(q.prog, q.target) .. " / " .. q.target, text_size = 17 })
	local rw = { gold = q.gold, diamonds = q.diamonds }
	local bx = w / 2 - 94
	if q.claimed then
		ui.box(box, "icon_check", bx, 0, 56, 56)
	elseif done then
		widgets.reward_row(box, rw, bx, 38, 24)
		ui.btn(box, "btn_gold", bx, -14, 160, 64, i18n.t("CLAIM"), 22, function()
			local reward = progress.claim_quest(idx)
			if reward then
				audio.play("quest")
				app.open_popup("reward", { reward = reward, title = i18n.t("QUEST_DONE") })
			end
		end, { pulse = true })
	else
		widgets.reward_row(box, rw, bx, 0, 34)
	end
	return h
end

function M.build(app, parent, R, hub_st)
	local d = progress.data
	local land = app.orient == "landscape"
	local w = math.min(R.w, land and 1100 or 720)
	local sc = ui.scroll(parent, R.cx, R.cy, R.w, R.h)
	local C = sc.content
	local y = -10

	y = y - 26
	widgets.section(C, i18n.t("DAILY_TITLE"), 0, y, w, "icon_calendar")
	y = y - 30
	local ch = 150
	calendar(app, C, y - ch / 2 - 6, w)
	y = y - ch - 30

	y = y - 26
	local hdr = widgets.section(C, i18n.t("QUESTS_TITLE"), 0, y, w, "icon_quest")
	local tl = ui.text(hdr, i18n.fmt_time(quests.seconds_to_reset()), w / 2 - 90, 2, 18, ui.DIM)
	hub_st.timers[#hub_st.timers + 1] = { node = tl, fn = function() return i18n.fmt_time(quests.seconds_to_reset()) end }
	y = y - 34
	for i, q in ipairs(d.daily and d.daily.quests or {}) do
		local h = 128
		quest_row(app, C, i, q, y - h / 2, w)
		y = y - h - 12
	end

	-- All-done bonus
	local all = quests.all_claimed(d)
	local bonus_ready = quests.bonus_ready(d)
	local claimed = d.daily and d.daily.bonus_claimed
	local bh = 120
	local box = ui.slice(C, bonus_ready and "card_epic" or "panel_dark", 0, y - bh / 2, w, bh, ui.WHITE, 20)
	local chest = ui.icon(box, config.CHESTS[quests.BONUS_CHEST].sprite, -w / 2 + 70, 0, 92)
	if bonus_ready then ui.bob(chest, 6, 0.5) end
	ui.label(box, i18n.t("QUESTS_BONUS"), -w / 2 + 130, 16, 21, ui.GOLD, w - 340, { pivot = gui.PIVOT_W })
	local done_n = 0
	for _, q in ipairs(d.daily and d.daily.quests or {}) do if q.claimed then done_n = done_n + 1 end end
	ui.label(box, done_n .. " / " .. quests.QUESTS_PER_DAY, -w / 2 + 130, -18, 18, ui.DIM, 200, { pivot = gui.PIVOT_W })
	if claimed then
		ui.box(box, "icon_check", w / 2 - 94, 0, 56, 56)
	elseif bonus_ready then
		ui.btn(box, "btn_gold", w / 2 - 94, 0, 160, 70, i18n.t("OPEN"), 22, function()
			local res = progress.claim_quest_bonus()
			if res then app.open_popup("chest", res) end
		end, { pulse = true })
	else
		ui.box(box, "icon_lock", w / 2 - 94, 0, 44, 44)
	end
	y = y - bh - 30
	if all then y = y end

	-- Trophy road teaser
	y = y - 26
	widgets.section(C, i18n.t("ROAD_TITLE"), 0, y, w, "icon_trophy")
	y = y - 30
	local idx, m = progress.road_next()
	local rh = 120
	local rb = ui.slice(C, progress.road_claimable() and "card_legendary" or "panel_stone", 0, y - rh / 2, w, rh, ui.WHITE, 20)
	if m then
		ui.box(rb, "icon_prestige", -w / 2 + 60, 0, 70, 70)
		ui.label(rb, i18n.t("ROAD_NEXT", { n = m.at }), -w / 2 + 110, 18, 21, ui.PRESTIGE, w - 360, { pivot = gui.PIVOT_W })
		local prev = idx > 1 and config.TROPHY_ROAD[idx - 1].at or 0
		local ratio = math.min(1, ((d.max_prestige or 0) - prev) / math.max(1, m.at - prev))
		ui.bar(rb, -w / 2 + 110 + (w - 360) / 2, -20, w - 360, 22, ratio, ui.PRESTIGE)
		widgets.reward_row(rb, m.reward, w / 2 - 170, 0, 34)
	else
		ui.label(rb, i18n.t("ROAD_DONE"), 0, 0, 22, ui.GOLD, w - 40)
	end
	ui.button(rb, function() app.open_popup("road") end)
	y = y - rh - 30
	sc.set_height(-y + 20)
end

return M
