-- Shop tab (Druid scroll): free diamonds (rewarded ad), daily card deals, chests for diamonds,
-- boosters for gold and locked squads for diamonds.
local ui = require "main.gui.ui"
local widgets = require "main.gui.widgets"
local config = require "main.modules.config"
local squads = require "main.modules.squads"
local progress = require "main.modules.progress"
local quests = require "main.modules.quests"
local poki = require "main.modules.poki"
local i18n = require "main.modules.i18n"
local audio = require "main.modules.audio"

local M = {}
local V4 = vmath.vector4
local st = {}

local function fail(app, x, y, key)
	audio.play("blocked")
	ui.float_text(app.hub_fx, i18n.t(key or "MISS_RES"), x, y, 22, ui.RED, 40)
end

local function price_btn(parent, x, y, w, sprite, icon, amount, fn, opts)
	return ui.btn(parent, sprite, x, y, w, 52, tostring(amount), 22, fn, { icon = icon, icon_size = 32, disabled = opts and opts.disabled })
end

function M.build(app, parent, R, hub_st)
	local d = progress.data
	local land = app.orient == "landscape"
	local w = math.min(R.w, land and 1240 or 720)
	local sc = ui.scroll(parent, R.cx, R.cy, R.w, R.h)
	local C = sc.content
	local cols = math.max(3, math.min(5, math.floor(w / 230)))
	local tw = (w - 20 - (cols - 1) * 14) / cols
	local function col_x(i) return -w / 2 + 10 + tw / 2 + (i - 1) * (tw + 14) end
	local y = -10
	st = { timer = nil }

	-- 1. Free stuff
	y = y - 26
	widgets.section(C, i18n.t("SHOP_FREE"), 0, y, w, "icon_gift")
	y = y - 36 - 110
	do
		local left = progress.ad_diamonds_left()
		local box = ui.slice(C, left > 0 and "card_legendary" or "panel_dark", col_x(1), y, tw, 220, ui.WHITE, 20)
		local ic = ui.icon(box, "icon_diamond", 0, 40, 84)
		if left > 0 then ui.bob(ic, 5, 0.6) end
		ui.text(box, "+" .. config.AD_DIAMONDS, 0, -18, 28, ui.DIAMOND)
		ui.label(box, i18n.t("ADS_LEFT", { n = left }), 0, -48, 15, ui.DIM, tw - 16)
		ui.btn(box, "btn_purple", 0, -84, tw - 20, 46, i18n.t("WATCH"), 19, function()
			if progress.ad_diamonds_left() <= 0 then return fail(app, R.cx, R.cy, "ADS_DONE") end
			poki.rewarded("small", function(ok)
				if ok and progress.claim_ad_diamonds() then
					audio.play("coin")
					app.rebuild()
				end
			end)
		end, { icon = "icon_ad", icon_size = 28, disabled = left <= 0 })

		local rem = progress.free_chest_remaining()
		local gb = ui.slice(C, rem <= 0 and "card_epic" or "panel_dark", col_x(2), y, tw, 220, ui.WHITE, 20)
		local gi = ui.icon(gb, "icon_gift", 0, 40, 84)
		if rem <= 0 then ui.bob(gi, 5, 0.5) end
		ui.label(gb, i18n.t("FREE_GIFT"), 0, -24, 18, ui.GOLD, tw - 16)
		local lbl = ui.label(gb, rem <= 0 and i18n.t("READY") or i18n.fmt_time(rem), 0, -84, 18, ui.BONE, tw - 16)
		if rem > 0 then hub_st.timers[#hub_st.timers + 1] = { node = lbl, fn = function() return i18n.fmt_time(progress.free_chest_remaining()) end } end
		ui.button(gb, function()
			local res = progress.claim_free_chest()
			if res then app.open_popup("chest", res) else fail(app, R.cx, R.cy, "FREE_GIFT_WAIT") end
		end)

		local sb = ui.slice(C, "panel_dark", col_x(3), y, tw, 220, ui.WHITE, 20)
		ui.icon(sb, "icon_quest", 0, 40, 80)
		ui.label(sb, i18n.t("TAB_QUESTS"), 0, -24, 18, ui.GOLD, tw - 16)
		ui.label(sb, i18n.t("QUESTS_HINT"), 0, -70, 14, ui.DIM, tw - 20, { lines = 2 })
		ui.button(sb, function() app.set_tab("quests") end)
	end
	y = y - 110 - 24

	-- 2. Daily deals
	y = y - 26
	local hdr = widgets.section(C, i18n.t("SHOP_DEALS"), 0, y, w, "icon_cards")
	local tl = ui.text(hdr, i18n.fmt_time(quests.seconds_to_reset()), w / 2 - 90, 2, 18, ui.DIM)
	hub_st.timers[#hub_st.timers + 1] = { node = tl, fn = function() return i18n.fmt_time(quests.seconds_to_reset()) end }
	y = y - 36 - 140
	for i, deal in ipairs(d.daily and d.daily.deals or {}) do
		local sq = squads.get(deal.id)
		local x = col_x(((i - 1) % cols) + 1)
		local box = ui.slice(C, ui.RARITY_FRAME[sq.rarity], x, y, tw, 270, deal.bought and V4(0.5, 0.5, 0.55, 1) or ui.WHITE, 20)
		ui.icon(box, sq.sprite, 0, 48, math.min(tw - 40, 110), deal.bought and V4(0.4, 0.4, 0.45, 1) or ui.WHITE)
		ui.label(box, i18n.t("SQ_" .. sq.id), 0, -26, 17, ui.BONE, tw - 16)
		ui.text(box, "x" .. deal.count, 0, -56, 26, ui.RARITY_COLOR[sq.rarity])
		if deal.bought then
			ui.box(box, "icon_check", 0, -100, 40, 40)
		else
			price_btn(box, 0, -100, tw - 20, d.gold >= deal.price and "btn_gold" or "btn_dark", "icon_gold", deal.price, function()
				if progress.buy_deal(i) then
					audio.play("upgrade")
					app.rebuild()
				else
					fail(app, R.cx, R.cy, "NEED_GOLD")
				end
			end)
		end
	end
	y = y - 140 - 24

	-- 3. Chests for diamonds
	y = y - 26
	widgets.section(C, i18n.t("SHOP_CHESTS"), 0, y, w, "chest_royal")
	y = y - 36 - 125
	for i, rar in ipairs(config.CHEST_ORDER) do
		local def = config.CHESTS[rar]
		local box = ui.slice(C, i == 3 and "card_legendary" or (i == 2 and "card_rare" or "card_common"), col_x(i), y, tw, 250, ui.WHITE, 20)
		if i == 3 then
			local rays = ui.glow(ui.box(box, "rays", 0, 40, 200, 200, V4(0.5, 0.9, 1, 0.3)))
			ui.spin(rays, 10)
		end
		ui.icon(box, def.sprite, 0, 44, math.min(tw - 30, 110))
		ui.label(box, i18n.t("CHEST_" .. rar), 0, -30, 17, ui.BONE, tw - 16)
		ui.label(box, i18n.t("CARDS_RANGE", { a = def.cards_min, b = def.cards_max }), 0, -56, 15, ui.DIM, tw - 16)
		price_btn(box, 0, -96, tw - 20, d.diamonds >= def.diamonds and "btn_purple" or "btn_dark", "icon_diamond", def.diamonds, function()
			local res = progress.buy_chest(rar)
			if res then app.open_popup("chest", res) else fail(app, R.cx, R.cy, "NEED_DIAMONDS") end
		end)
	end
	y = y - 125 - 24

	-- 4. Boosters for gold
	y = y - 26
	widgets.section(C, i18n.t("SHOP_BOOSTERS"), 0, y, w, "boost_hammer")
	y = y - 36 - 110
	for i, kind in ipairs(config.BOOSTER_ORDER) do
		local b = config.BOOSTERS[kind]
		local box = ui.slice(C, "panel_stone", col_x(i), y, tw, 220, ui.WHITE, 20)
		ui.icon(box, b.sprite, 0, 44, 84)
		ui.label(box, i18n.t("BOOST_" .. kind), 0, -14, 18, ui.BONE, tw - 16)
		ui.label(box, i18n.t("OWNED_FMT", { n = d.boosters[kind] or 0 }), 0, -40, 15, ui.DIM, tw - 16)
		price_btn(box, 0, -82, tw - 20, d.gold >= b.gold_cost and "btn_gold" or "btn_dark", "icon_gold", b.gold_cost, function()
			if progress.buy_booster(kind) then
				audio.play("coin")
				app.rebuild()
			else
				fail(app, R.cx, R.cy, "NEED_GOLD")
			end
		end)
	end
	y = y - 110 - 24

	-- 5. Locked squads
	local locked = {}
	for _, sq in ipairs(squads.LIST) do
		if not d.cards[sq.id].unlocked then locked[#locked + 1] = sq end
	end
	if #locked > 0 then
		y = y - 26
		widgets.section(C, i18n.t("SHOP_SQUADS"), 0, y, w, "icon_lock")
		y = y - 36
		local ch = 250
		for idx, sq in ipairs(locked) do
			local r = math.floor((idx - 1) / cols)
			local c = (idx - 1) % cols
			local cy = y - ch / 2 - r * (ch + 14)
			widgets.card_tile(C, sq, col_x(c + 1), cy, tw, ch, { on_tap = function() app.open_popup("card", { id = sq.id }) end })
		end
		y = y - math.ceil(#locked / cols) * (ch + 14)
	end
	sc.set_height(-y + 30)
end

return M
