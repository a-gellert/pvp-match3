-- Hub shell (background, top bar, bottom tab bar) + Home tab (league, showcase, battle, chests).
local ui = require "main.gui.ui"
local widgets = require "main.gui.widgets"
local cards_view = require "main.gui.cards_view"
local map_view = require "main.gui.map_view"
local shop_view = require "main.gui.shop_view"
local quests_view = require "main.gui.quests_view"
local config = require "main.modules.config"
local squads = require "main.modules.squads"
local campaign = require "main.modules.campaign"
local progress = require "main.modules.progress"
local quests = require "main.modules.quests"
local i18n = require "main.modules.i18n"
local audio = require "main.modules.audio"

local M = {}
local V3 = vmath.vector3
local V4 = vmath.vector4

local TABS = {
	{ id = "shop",   icon = "icon_shop",  key = "TAB_SHOP" },
	{ id = "cards",  icon = "icon_cards", key = "TAB_CARDS" },
	{ id = "home",   icon = "icon_pvp",   key = "TAB_HOME" },
	{ id = "map",    icon = "icon_map",   key = "TAB_MAP" },
	{ id = "quests", icon = "icon_quest", key = "TAB_QUESTS" },
}
local VIEWS = { cards = cards_view, map = map_view, shop = shop_view, quests = quests_view }

local st = {}

-- State signature: when it changes (a timer finished, etc.) the hub is rebuilt.
local function signature()
	local d = progress.data
	local parts = { tostring(progress.free_chest_remaining() <= 0), tostring(quests.login_pending(d)), tostring(d.daily and d.daily.day) }
	for i = 1, config.MAX_CHEST_SLOTS do
		local ch = d.chests[i]
		parts[#parts + 1] = ch and (ch.rarity .. tostring(ch.unlocking) .. tostring(progress.chest_remaining(i) <= 0)) or "-"
	end
	return table.concat(parts, ",")
end

-- ---------------------------------------------------------------- top bar & nav
local function top_bar(app, y, cx0, cx1)
	local d = progress.data
	local w = cx1 - cx0
	local h = 70
	ui.slice(st.root, "panel_dark", (cx0 + cx1) / 2, y, w, h + 10, V4(1, 1, 1, 0.92), 18)
	local x = cx0 + 46
	-- Commander avatar + level
	local av = ui.box(st.root, "face_hero", x, y, 66, 66)
	ui.button(av, function() app.open_popup("profile") end)
	local lv = ui.box(av, "badge_dot", 24, -22, 30, 30, ui.hex("#2b6bd6"))
	ui.text(lv, tostring(d.commander_lvl), 0, 1, 16, ui.WHITE)
	local pills_w = w - 92 - 64
	local pw = math.min(app.orient == "landscape" and 250 or 196, (pills_w - 24) / 3)
	-- Centre the pill group between the avatar and the settings button
	local group_w = pw * 3 + 24
	local px = cx0 + 92 + math.max(0, (pills_w - group_w) / 2) + pw / 2
	-- League / prestige
	local _, lg = progress.league()
	local lp = ui.slice(st.root, "panel_dark", px, y, pw, 50, ui.WHITE, 16)
	ui.box(lp, "league_badge", -pw / 2 + 22, 1, 44, 44, ui.hex(lg.color))
	st.prestige_lbl = ui.label(lp, tostring(d.prestige), 14, 2, 22, ui.PRESTIGE, pw - 58)
	ui.button(lp, function() app.open_popup("road") end)
	if progress.road_claimable() then ui.badge(lp, pw / 2 - 6, 18, 1, 26) end
	-- Gold & diamonds
	local gp = ui.currency_pill(st.root, "icon_gold", d.gold, px + pw + 12, y, pw, 50)
	st.gold_pos = { x = px + pw + 12 - pw / 2 + 20, y = y }
	local dp = ui.currency_pill(st.root, "icon_diamond", d.diamonds, px + (pw + 12) * 2, y, pw, 50)
	st.diamond_pos = { x = px + (pw + 12) * 2 - pw / 2 + 20, y = y }
	ui.button(dp, function() app.set_tab("shop") end)
	ui.button(gp, function() app.set_tab("shop") end)
	ui.btn(st.root, "btn_round", cx1 - 36, y, 58, 58, "", 20, function() app.open_popup("settings") end, { icon = "icon_gear", icon_size = 30 })
end

local function nav_bar(app, cx0, cx1, h)
	local badges = progress.badges()
	local w = cx1 - cx0
	ui.slice(st.root, "panel_stone", (cx0 + cx1) / 2, h / 2 - 6, w + 20, h + 14, ui.WHITE, 22)
	local tw = w / #TABS
	for i, tab in ipairs(TABS) do
		local x = cx0 + (i - 0.5) * tw
		local active = app.tab == tab.id
		local holder = ui.pane(st.root, x, h / 2)
		if active then
			local glow = ui.glow(ui.box(holder, "glow", 0, 14, tw * 1.3, h * 1.3, V4(1, 0.8, 0.35, 0.3)))
			ui.pulse(glow, 1.06, 0.9)
		end
		-- Tap zone (Druid button) with an opaque sprite only for the active tab
		local hit = active and ui.slice(holder, "tab_active", 0, 10, tw - 8, h, ui.WHITE, 18)
			or ui.box(holder, nil, 0, 0, tw - 8, h - 16, V4(1, 1, 1, 0))
		local isz = active and 64 or 50
		local ic = ui.icon(hit, tab.icon, 0, active and 14 or 10, isz, active and ui.WHITE or V4(0.78, 0.8, 0.88, 1))
		gui.set_inherit_alpha(ic, false)
		if active then ui.bob(ic, 4, 0.9) end
		local lbl = ui.label(hit, i18n.t(tab.key), 0, -h / 2 + (active and 22 or 26), active and 19 or 16, active and ui.GOLD or ui.DIM, tw - 14)
		gui.set_inherit_alpha(lbl, false)
		ui.button(hit, function() app.set_tab(tab.id) end, { silent = true })
		local cnt = badges[tab.id] or 0
		local tut_hand = tab.id == "cards" and not active and progress.data.onboarding_step == 2
		if cnt > 0 and not active and not tut_hand then
			local bd = ui.badge(hit, isz / 2 + 4, isz / 2, cnt, 30)
			gui.set_inherit_alpha(bd, false)
		end
		if tut_hand then
			local hand = ui.box(holder, "icon_hand", 22, 30, 52, 52)
			ui.pulse(hand, 1.18, 0.45)
		end
	end
end

-- ---------------------------------------------------------------- home tab
local function free_gift_tile(app, parent, x, y, w, h)
	local rem = progress.free_chest_remaining()
	local ready = rem <= 0
	local box = ui.slice(parent, ready and "card_epic" or "panel_dark", x, y, w, h, ui.WHITE, 18)
	local ic = ui.icon(box, "icon_gift", 0, 12, math.min(h - 44, 74))
	if ready then
		ui.bob(ic, 6, 0.45)
		ui.badge(box, w / 2 - 6, h / 2 - 6, 1, 30)
		local rays = ui.glow(ui.box(box, "rays", 0, 12, h * 1.4, h * 1.4, V4(0.85, 0.6, 1, 0.35)))
		ui.spin(rays, 8)
	end
	local lbl = ui.label(box, ready and i18n.t("FREE_GIFT") or i18n.fmt_time(rem), 0, -h / 2 + 20, 16, ready and ui.GOLD or ui.BONE, w - 12)
	if not ready then st.timers[#st.timers + 1] = { node = lbl, fn = function() return i18n.fmt_time(progress.free_chest_remaining()) end } end
	ui.button(box, function()
		local res = progress.claim_free_chest()
		if res then app.open_popup("chest", res)
		else ui.float_text(st.fx, i18n.t("FREE_GIFT_WAIT"), x, y + h / 2, 20, ui.DIM, 30) end
	end)
end

local function daily_tile(app, parent, x, y, w, h)
	local pending = quests.login_pending(progress.data)
	local box = ui.slice(parent, pending and "card_rare" or "panel_dark", x, y, w, h, ui.WHITE, 18)
	local ic = ui.icon(box, "icon_calendar", 0, 12, math.min(h - 44, 70))
	if pending then ui.bob(ic, 5, 0.5); ui.badge(box, w / 2 - 6, h / 2 - 6, 1, 30) end
	ui.label(box, i18n.t("DAILY_SHORT"), 0, -h / 2 + 20, 16, pending and ui.GOLD or ui.BONE, w - 12)
	ui.button(box, function() app.open_popup("daily") end)
end

-- Daily Trial tile: today's boss face, "fight" state with a badge or a "done" check + streak.
local function trial_tile(app, parent, x, y, w, h)
	local avail = progress.trial_available()
	local boss = progress.trial_boss()
	local box = ui.slice(parent, avail and "card_legendary" or "panel_dark", x, y, w, h, ui.WHITE, 18)
	local face = ui.icon(box, boss.face, 0, 14, math.min(h - 50, 70), avail and ui.WHITE or V4(0.6, 0.62, 0.7, 1))
	if avail then
		ui.bob(face, 4, 0.6)
		ui.badge(box, w / 2 - 6, h / 2 - 6, 1, 30)
	else
		ui.box(box, "icon_check", w / 2 - 26, h / 2 - 26, 36, 36)
	end
	local streak = progress.trial_streak()
	if streak >= 2 then
		local fl = ui.box(box, "icon_fire", -w / 2 + 22, h / 2 - 24, 34, 34)
		ui.text(fl, "x" .. streak, 0, -12, 16, ui.WHITE)
	end
	local lbl = ui.label(box, avail and i18n.t("TRIAL_SHORT") or i18n.fmt_time(quests.seconds_to_reset()), 0, -h / 2 + 20, 16,
		avail and ui.GOLD or ui.BONE, w - 12)
	if not avail then st.timers[#st.timers + 1] = { node = lbl, fn = function() return i18n.fmt_time(quests.seconds_to_reset()) end } end
	ui.button(box, function()
		if not progress.trial_unlocked() then return end
		if avail then
			app.open_popup("trial")
		else
			ui.float_text(st.fx, i18n.t("TRIAL_TOMORROW"), x, y + h / 2, 20, ui.DIM, 30)
		end
	end)
end

local function league_banner(app, parent, cx, y, w)
	local d = progress.data
	local idx, lg, nxt = progress.league()
	local box = ui.slice(parent, "panel_stone", cx, y, w, 104, ui.WHITE, 22)
	local badge = ui.box(box, "league_badge", -w / 2 + 56, 0, 84, 84, ui.hex(lg.color))
	ui.text(badge, tostring(idx), 0, 2, 26, ui.INK, ui.WHITE)
	ui.label(box, i18n.t("LEAGUE_" .. lg.id), -w / 2 + 110, 24, 26, ui.hex(lg.color), w - 260, { pivot = gui.PIVOT_W })
	local bar_w = w - 270
	local lo = lg.min
	local hi = nxt and nxt.min or (lg.min + 1000)
	local ratio = math.min(1, (d.prestige - lo) / math.max(1, hi - lo))
	local bar = ui.bar(box, -w / 2 + 110 + bar_w / 2, -16, bar_w, 24, ratio, ui.PRESTIGE,
		{ text = d.prestige .. " / " .. hi, text_size = 16 })
	ui.box(bar.bg, "icon_prestige", -bar_w / 2 - 2, 0, 30, 30)
	-- Trophy road button
	local rb_node = ui.btn(box, "btn_purple", w / 2 - 72, 0, 120, 78, "", 18, function() app.open_popup("road") end,
		{ icon = "icon_trophy", icon_size = 50, badge = progress.road_claimable() and 1 or 0 })
	ui.text(rb_node, i18n.t("ROAD_SHORT"), 0, -30, 14, ui.WHITE)
end

local function showcase(app, parent, cx, cy, w, h)
	local d = progress.data
	ui.slice(parent, "panel_dark", cx, cy, w, h, ui.WHITE, 20)
	ui.box(parent, "arena_bg", cx, cy, w - 14, h - 14, V4(0.8, 0.82, 0.95, 1))
	ui.box(parent, "vignette", cx, cy, w - 14, h - 14, V4(1, 1, 1, 0.8))
	local sz = math.min(150, h * 0.5, w * 0.24)
	local xs = { -0.28, 0, 0.28 }
	for i, col in ipairs(config.ATTACK_COLORS) do
		local sq = squads.get(d.slots[col])
		local sx, sy = cx + w * xs[i], cy - h * 0.06 + (i == 2 and -h * 0.06 or h * 0.04)
		ui.box(parent, "glow", sx, sy - sz * 0.36, sz * 0.9, sz * 0.26, V4(0, 0, 0, 0.55))
		local gl = ui.glow(ui.box(parent, "glow", sx, sy, sz * 1.4, sz * 1.4, V4(ui.GEM_COLOR[col].x, ui.GEM_COLOR[col].y, ui.GEM_COLOR[col].z, 0.25)))
		ui.pulse(gl, 1.1, 1.2 + i * 0.2)
		local art = ui.icon(parent, sq.sprite, sx, sy, sz)
		ui.bob(art, 5, 1.1 + i * 0.15, i * 0.2)
		ui.button(art, function() app.open_popup("card", { id = sq.id }) end)
		local c = d.cards[sq.id]
		local lv = ui.slice(parent, "panel_dark", sx, sy - sz * 0.56, 72, 26, ui.WHITE, 10)
		ui.label(lv, i18n.t("LVL_FMT", { n = c.level }), 0, 1, 15, ui.GOLD, 66)
	end
	-- Commander stats strip
	local strip = ui.slice(parent, "panel_dark", cx, cy + h / 2 - 28, math.min(w - 40, 420), 40, V4(1, 1, 1, 0.9), 14)
	ui.box(strip, "icon_heart", -110, 1, 26, 26)
	ui.text(strip, tostring(progress.hero_hp()), -66, 2, 19, ui.BONE)
	ui.box(strip, "icon_move_orb", 20, 1, 24, 24)
	ui.text(strip, i18n.t("MOVES_FMT", { n = d.max_moves }), 90, 2, 19, ui.BONE)
end

local function chapter_bar(app, parent, cx, y, w, h)
	local d = progress.data
	local stage_n = math.min(campaign.COUNT, d.max_stage_unlocked or 1)
	local biome_idx = math.min(#campaign.BIOMES, math.floor((stage_n - 1) / campaign.STAGES_PER_BIOME) + 1)
	local bm = campaign.BIOMES[biome_idx]
	local boss_stage_n = biome_idx * campaign.STAGES_PER_BIOME
	local boss_stg = campaign.get_stage(boss_stage_n)
	local to_boss = boss_stage_n - stage_n
	local is_boss = to_boss <= 0

	local box = ui.slice(parent, is_boss and "card_epic" or "panel_stone", cx, y, w, h, ui.WHITE, 16)
	local ic = ui.icon(box, is_boss and boss_stg.face or "icon_map", -w / 2 + 36, 0, 48)
	if is_boss then ui.pulse(ic, 1.12, 0.4) end

	local tx = -w / 2 + 68
	local tw = w - 80
	local title = i18n.t("CHAPTER_FMT", { n = biome_idx, name = i18n.t(bm.name_key) })
	ui.label(box, title, tx, 12, 17, is_boss and ui.RED or ui.GOLD, tw, { pivot = gui.PIVOT_W })

	local sub = is_boss and i18n.t("BOSS_READY") or i18n.t("TO_BOSS_FMT", { n = to_boss })
	ui.label(box, sub, tx, -12, 15, is_boss and ui.GOLD or ui.BONE, tw, { pivot = gui.PIVOT_W })

	ui.button(box, function()
		if not d.onboarding_done then return end
		app.open_popup("stage", { id = stage_n })
	end)
end

local function star_chest_bar(app, parent, cx, y, w, h)
	local have, need = progress.star_chest_progress()
	local ready = progress.star_chest_ready()
	local base = need - config.STAR_CHEST_EVERY
	local cur_have = math.min(config.STAR_CHEST_EVERY, math.max(0, have - base))
	local cur_need = config.STAR_CHEST_EVERY
	local rarity = ((progress.data.star_chests or 0) + 1) % 3 == 0 and "royal" or "silver"

	local box = ui.slice(parent, ready and "card_rare" or "panel_stone", cx, y, w, h, ui.WHITE, 16)
	if ready then
		local rays = ui.glow(ui.box(box, "rays", w / 2 - 32, 0, h * 1.3, h * 1.3, V4(1, 0.85, 0.4, 0.3)))
		ui.spin(rays, 8)
	end

	local sic = ui.box(box, "icon_star", -w / 2 + 28, 0, 38, 38)
	if ready then ui.bob(sic, 4, 0.4) end

	local bar_w = w - 124
	local bar_x = -w / 2 + 52 + bar_w / 2
	local txt = ready and i18n.t("STAR_CHEST_READY") or (cur_have .. " / " .. cur_need)
	ui.bar(box, bar_x, 0, bar_w, 28, math.min(1, cur_have / cur_need), ui.YELLOW, { text = txt, text_size = 15, text_color = ui.WHITE })

	local cic = ui.icon(box, config.CHESTS[rarity].sprite, w / 2 - 32, 0, 48)
	if ready then ui.pulse(cic, 1.15, 0.38) end

	ui.button(box, function()
		if ready then
			local res = progress.claim_star_chest()
			if res then app.open_popup("chest", res) end
		else
			ui.float_text(st.fx, i18n.t("STARS_NEED", { n = cur_need - cur_have }), cx, y + h / 2, 20, ui.DIM, 30)
		end
	end)
end

local function build_home(app, parent, R)
	local d = progress.data
	local land = app.orient == "landscape"
	local stage_n = math.min(campaign.COUNT, d.max_stage_unlocked or 1)
	local function battle_buttons(cx, y, w)
		local bw = (w - 14) / 2
		local pvp_x = cx - bw / 2 - 7
		local camp_x = cx + bw / 2 + 7
		ui.btn(parent, "btn_gold", pvp_x, y, bw, 108, i18n.t("BATTLE"), 34, function() app.start_pvp_search() end,
			{ icon = "icon_pvp", icon_size = 64, pulse = true })
		if (d.streak or 0) >= 2 then
			local fl = ui.box(parent, "icon_fire", pvp_x + bw / 2 - 28, y + 42, 48, 48)
			ui.pulse(fl, 1.15, 0.35)
			ui.text(parent, "x" .. d.streak, pvp_x + bw / 2 - 28, y + 28, 18, ui.WHITE)
		end
		local stg = campaign.get_stage(stage_n)
		local cn = ui.btn(parent, stg.boss and "btn_crimson" or "btn_purple", camp_x, y, bw, 108,
			i18n.t("CAMPAIGN_NEXT", { n = stage_n }), 26, function()
				app.open_popup("stage", { id = stage_n })
			end, { icon = stg.face, icon_size = 64 })
		if not d.onboarding_done then gui.set_enabled(cn, false) end
		if (d.streak or 0) >= 2 then
			local fl2 = ui.box(parent, "icon_fire", camp_x + bw / 2 - 28, y + 42, 48, 48)
			ui.pulse(fl2, 1.15, 0.35)
			ui.text(parent, "x" .. d.streak, camp_x + bw / 2 - 28, y + 28, 18, ui.WHITE)
		end
	end

	if land then
		local split = R.x0 + R.w * 0.58
		local lcx, lw = (R.x0 + split) / 2, split - R.x0 - 12
		local rcx, rw = (split + R.x1) / 2, R.x1 - split - 12
		league_banner(app, parent, lcx, R.y1 - 56, lw)
		local btn_y = R.y0 + 64
		local bar_y = btn_y + 54 + 44
		local hw = (lw - 14) / 2
		chapter_bar(app, parent, lcx - hw / 2 - 7, bar_y, hw, 72)
		star_chest_bar(app, parent, lcx + hw / 2 + 7, bar_y, hw, 72)
		battle_buttons(lcx, btn_y, lw)
		local sc_top = R.y1 - 118
		local sc_bot = bar_y + 44
		showcase(app, parent, lcx, (sc_top + sc_bot) / 2, lw, sc_top - sc_bot)
		-- Right column: gift + daily (+ trial), then chests 2x2
		local tile_h = 150
		local ty = R.y1 - tile_h / 2 - 4
		if d.onboarding_done then
			local tw3 = (rw - 16) / 3
			free_gift_tile(app, parent, rcx - tw3 - 8, ty, tw3, tile_h)
			daily_tile(app, parent, rcx, ty, tw3, tile_h)
			trial_tile(app, parent, rcx + tw3 + 8, ty, tw3, tile_h)
		else
			free_gift_tile(app, parent, rcx - rw / 4 - 4, ty, rw / 2 - 8, tile_h)
			daily_tile(app, parent, rcx + rw / 4 + 4, ty, rw / 2 - 8, tile_h)
		end
		widgets.section(parent, i18n.t("CHESTS"), rcx, ty - tile_h / 2 - 34, rw, "chest_wood")
		local ch_top = ty - tile_h / 2 - 62
		local ch_h = math.min(240, (ch_top - R.y0 - 12) / 2)
		for i = 1, 4 do
			local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
			local x = rcx + (col - 0.5) * (rw / 2 + 4)
			local y = ch_top - ch_h / 2 - row * (ch_h + 10)
			local tn = widgets.chest_slot(parent, app, i, x, y, rw / 2 - 8, ch_h)
			if tn then st.timers[#st.timers + 1] = { node = tn, fn = function() return i18n.fmt_time(progress.chest_remaining(i)) end } end
		end
	else
		local cx, w = R.cx, math.min(R.w, 720)
		league_banner(app, parent, cx, R.y1 - 58, w)
		local chest_h = 176
		local chest_y = R.y0 + chest_h / 2 + 2
		local btns_y = chest_y + chest_h / 2 + 70
		local bar_y = btns_y + 54 + 44
		local hw = (w - 14) / 2
		chapter_bar(app, parent, cx - hw / 2 - 7, bar_y, hw, 74)
		star_chest_bar(app, parent, cx + hw / 2 + 7, bar_y, hw, 74)
		battle_buttons(cx, btns_y, w)
		local sc_top = R.y1 - 122
		local sc_bot = bar_y + 44
		local sc_h = math.max(200, sc_top - sc_bot)
		local tile_w = 112
		showcase(app, parent, cx, sc_bot + sc_h / 2, w - (tile_w * 2 + 20), sc_h)
		free_gift_tile(app, parent, cx - w / 2 + tile_w / 2, sc_bot + sc_h - 80, tile_w, 150)
		daily_tile(app, parent, cx + w / 2 - tile_w / 2, sc_bot + sc_h - 80, tile_w, 150)
		if d.onboarding_done and sc_h >= 320 then
			trial_tile(app, parent, cx + w / 2 - tile_w / 2, sc_bot + sc_h - 240, tile_w, 150)
		end
		local cw = (w - 30) / 4
		for i = 1, 4 do
			local tn = widgets.chest_slot(parent, app, i, cx - w / 2 + cw / 2 + 6 + (i - 1) * (cw + 6), chest_y, cw, chest_h)
			if tn then st.timers[#st.timers + 1] = { node = tn, fn = function() return i18n.fmt_time(progress.chest_remaining(i)) end } end
		end
	end
end

-- ---------------------------------------------------------------- build
function M.build(app, parent)
	local vw, vh = app.vw, app.vh
	local land = app.orient == "landscape"
	st = { app = app, root = ui.pane(parent, 0, 0), timers = {}, tick = 0, sig = signature() }
	ui.background(st.root, vw, vh, ui.hex(app.tab == "map" and "#6a4ab0" or "#3a4a8a"), true)

	local comp_w = math.min(vw - (land and 40 or 16), land and 1760 or 900)
	local cx0 = (vw - comp_w) / 2
	local cx1 = cx0 + comp_w
	local top_h = 84
	local nav_h = land and 100 or 124
	local R = { x0 = cx0, x1 = cx1, y0 = nav_h + 6, y1 = vh - top_h - 12 }
	R.w, R.h = R.x1 - R.x0, R.y1 - R.y0
	R.cx, R.cy = (R.x0 + R.x1) / 2, (R.y0 + R.y1) / 2

	local content = ui.pane(st.root, 0, 0)
	if app.tab == "home" then
		build_home(app, content, R)
	elseif VIEWS[app.tab] then
		VIEWS[app.tab].build(app, content, R, st)
	end
	ui.fade_in(content, 0.2)

	top_bar(app, vh - top_h / 2 - 4, cx0, cx1)
	nav_bar(app, land and math.max(cx0, vw / 2 - 560) or cx0, land and math.min(cx1, vw / 2 + 560) or cx1, nav_h)
	st.fx = ui.pane(st.root, 0, 0)
	app.hub_fx = st.fx
	app.hub_st = st
end

-- Reward juice from anywhere in the hub: icons fly into the currency pills.
function M.collect_fx(kind, x, y, count)
	if not (st.fx and st.gold_pos) then return end
	local target = kind == "diamond" and st.diamond_pos or st.gold_pos
	ui.collect(st.fx, kind == "diamond" and "icon_diamond" or "icon_gold", x, y, target.x, target.y, count or 6, 40)
end

function M.update(dt)
	if not st.root then return end
	st.tick = st.tick + dt
	if st.tick < 0.5 then return end
	st.tick = 0
	for _, t in ipairs(st.timers) do gui.set_text(t.node, t.fn()) end
	local v = VIEWS[st.app.tab]
	if v and v.tick then v.tick() end
	local sig = signature()
	if sig ~= st.sig and not st.app.popup then
		st.sig = sig
		progress.tick_day()
		st.app.rebuild()
	end
end

return M
