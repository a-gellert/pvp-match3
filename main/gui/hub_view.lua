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
		if cnt > 0 and not active then
			local bd = ui.badge(hit, isz / 2 + 4, isz / 2, cnt, 30)
			gui.set_inherit_alpha(bd, false)
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

local function build_home(app, parent, R)
	local d = progress.data
	local land = app.orient == "landscape"
	local stage_n = math.min(campaign.COUNT, d.max_stage_unlocked or 1)
	local function battle_buttons(cx, y, w, side_by_side)
		local bw = side_by_side and (w - 16) / 2 or w
		local pvp_x = side_by_side and (cx - bw / 2 - 8) or cx
		local camp_x = side_by_side and (cx + bw / 2 + 8) or cx
		local pvp_y = y
		local camp_y = side_by_side and y or (y - 104)
		ui.btn(parent, "btn_gold", pvp_x, pvp_y, bw, 116, i18n.t("BATTLE"), 40, function() app.start_pvp_search() end,
			{ icon = "icon_pvp", icon_size = 70, pulse = true })
		if (d.streak or 0) >= 2 then
			local fl = ui.box(parent, "icon_fire", pvp_x + bw / 2 - 30, pvp_y + 46, 52, 52)
			ui.pulse(fl, 1.15, 0.35)
			ui.text(parent, "x" .. d.streak, pvp_x + bw / 2 - 30, pvp_y + 30, 20, ui.WHITE)
		end
		local stg = campaign.get_stage(stage_n)
		local cn = ui.btn(parent, stg.boss and "btn_crimson" or "btn_purple", camp_x, camp_y, bw, side_by_side and 116 or 88,
			i18n.t("CAMPAIGN_NEXT", { n = stage_n }), side_by_side and 30 or 26, function()
				app.open_popup("stage", { id = stage_n })
			end, { icon = stg.face, icon_size = side_by_side and 76 or 62 })
		if not d.onboarding_done then gui.set_enabled(cn, false) end
	end

	if land then
		local split = R.x0 + R.w * 0.58
		local lcx, lw = (R.x0 + split) / 2, split - R.x0 - 12
		local rcx, rw = (split + R.x1) / 2, R.x1 - split - 12
		league_banner(app, parent, lcx, R.y1 - 56, lw)
		local btn_y = R.y0 + 64
		local sc_top, sc_bot = R.y1 - 118, btn_y + 74
		showcase(app, parent, lcx, (sc_top + sc_bot) / 2, lw, sc_top - sc_bot)
		battle_buttons(lcx, btn_y, lw, true)
		-- Right column: gift + daily, then chests 2x2
		local tile_h = 150
		local ty = R.y1 - tile_h / 2 - 4
		free_gift_tile(app, parent, rcx - rw / 4 - 4, ty, rw / 2 - 8, tile_h)
		daily_tile(app, parent, rcx + rw / 4 + 4, ty, rw / 2 - 8, tile_h)
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
		local btns_y = chest_y + chest_h / 2 + 40 + 104 + 58
		local sc_top = R.y1 - 122
		local sc_bot = btns_y + 72
		local sc_h = math.max(220, sc_top - sc_bot)
		local tile_w = 112
		showcase(app, parent, cx, sc_bot + sc_h / 2, w - (tile_w * 2 + 20), sc_h)
		free_gift_tile(app, parent, cx - w / 2 + tile_w / 2, sc_bot + sc_h - 80, tile_w, 150)
		daily_tile(app, parent, cx + w / 2 - tile_w / 2, sc_bot + sc_h - 80, tile_w, 150)
		battle_buttons(cx, btns_y, math.min(w - 40, 520), false)
		local cw = (w - 30) / 4
		for i = 1, 4 do
			local tn = widgets.chest_slot(parent, app, i, cx - w / 2 + cw / 2 + 6 + (i - 1) * (cw + 6), chest_y, cw, chest_h)
			if tn then st.timers[#st.timers + 1] = { node = tn, fn = function() return i18n.fmt_time(progress.chest_remaining(i)) end } end
		end
	end

	-- Onboarding hint: go upgrade a card
	if d.onboarding_step == 1 then
		local hint = ui.slice(parent, "btn_gold", R.cx, R.y0 + 30, math.min(R.w - 40, 520), 50, ui.WHITE, 16)
		ui.label(hint, i18n.t("TUT_GO_CARDS"), 0, 2, 21, ui.INK, math.min(R.w - 40, 520) - 30)
		ui.pulse(hint, 1.04, 0.5)
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
