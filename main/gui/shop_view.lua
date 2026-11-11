-- Shop Screen: Browse & Unlock any of the 18 Squad Cards with Diamonds, buy Boosters with Gold.
local ui = require "main.gui.ui"
local config = require "main.modules.config"
local squads = require "main.modules.squads"
local progress = require "main.modules.progress"
local i18n = require "main.modules.i18n"
local audio = require "main.modules.audio"

local M = { page = 1 }

local GEM_SPRITE = {
	red = "gem_red", yellow = "gem_yellow", purple = "gem_purple", green = "gem_green", blue = "gem_blue",
}

function M.build(app, parent)
	local root = ui.pane(parent, 0, 0)
	local vw, vh = app.vw, app.vh
	local d = progress.data

	ui.box(root, "square", vw / 2, vh / 2, vw, vh, ui.BG_DARK)

	-- Header
	local is_land = app.orient == "landscape"
	ui.btn(root, "btn_dark", 96, vh - 46, 150, 56, i18n.t("HUB"), 22, function() app.show_hub() end)
	ui.text(root, i18n.t("SHOP"), vw / 2, is_land and (vh - 46) or (vh - 102), 30, ui.GOLD)
	ui.currency_pill(root, "icon_gold", d.gold, vw - 270, vh - 46, 154, 48)
	ui.currency_pill(root, "icon_diamond", d.diamonds, vw - 102, vh - 46, 154, 48)

	-- Locked Cards for Diamonds (paged cleanly by 3 across all 18 squads)
	local locked = {}
	for _, sq in ipairs(squads.LIST) do
		if not d.cards[sq.id].unlocked then locked[#locked + 1] = sq end
	end

	local pages = math.max(1, math.ceil(#locked / 3))
	if M.page > pages then M.page = pages end

	local y_cards = vh - 265
	ui.text(root, i18n.t("COLLECTION"), vw / 2, y_cards + 106, 22, ui.DIAMOND)
	if #locked == 0 then
		ui.text(root, i18n.t("MAX"), vw / 2, y_cards, 22, ui.GREEN)
	else
		local first = (M.page - 1) * 3 + 1
		local last = math.min(#locked, first + 2)
		local shown = last - first + 1
		for idx = first, last do
			local i = idx - first + 1
			local sq = locked[idx]
			local cx = vw / 2 + (i - (shown + 1) / 2) * 224
			local card = ui.slice(root, ui.RARITY_FRAME[sq.rarity], cx, y_cards - 30, 206, 224, ui.WHITE, 20)
			ui.box(card, GEM_SPRITE[sq.color], -80, 88, 22, 22)
			if sq.runes then
				ui.box(card, GEM_SPRITE[sq.runes[1]], 56, 88, 16, 16)
				ui.box(card, GEM_SPRITE[sq.runes[2]], 74, 88, 16, 16)
			end
			ui.icon(card, sq.sprite, 0, 30, 88)
			local nm = ui.text(card, i18n.t("SQ_" .. sq.id), 0, -28, 17, ui.BONE)
			ui.fit(nm, 184, 17)
			local d_cost = squads.unlock_diamonds(sq.id)
			ui.btn(card, "btn_purple", 0, -76, 176, 46, i18n.t("BUY_CARD", { d = d_cost }), 17, function()
				if progress.buy_locked_card(sq.id) then
					audio.play("upgrade")
					app.rebuild()
				else
					ui.float_text(root, i18n.t("MISS_RES"), cx, y_cards + 40, 20, ui.RED, 40)
				end
			end)
		end
		if pages > 1 then
			ui.btn(root, "btn_dark", vw / 2 - 140, y_cards + 106, 44, 34, "<", 20, function()
				M.page = M.page > 1 and (M.page - 1) or pages
				app.rebuild()
			end)
			ui.btn(root, "btn_dark", vw / 2 + 140, y_cards + 106, 44, 34, ">", 20, function()
				M.page = M.page < pages and (M.page + 1) or 1
				app.rebuild()
			end)
		end
	end

	-- Boosters for Gold
	local by = vh - 560
	ui.text(root, i18n.t("GOLD"), vw / 2, by + 98, 22, ui.GOLD)
	local b_keys = { "shuffle", "hammer", "extra_move" }
	for i, kind in ipairs(b_keys) do
		local b = config.BOOSTERS[kind]
		local bx = vw / 2 + (i - 2) * 224
		local card = ui.slice(root, "panel_stone", bx, by - 24, 206, 198, ui.WHITE, 20)
		ui.box(card, b.sprite, 0, 34, 72, 72)
		local b_lbl = ui.text(card, i18n.t("BOOST_" .. kind) .. " (x" .. (d.boosters[kind] or 0) .. ")", 0, -20, 17, ui.BONE)
		ui.fit(b_lbl, 188, 17)
		ui.btn(card, "btn_gold", 0, -64, 176, 44, i18n.t("BUY_GOLD", { g = b.gold_cost }), 17, function()
			if progress.buy_booster(kind) then
				audio.play("button")
				app.rebuild()
			else
				ui.float_text(root, i18n.t("MISS_RES"), bx, by + 30, 20, ui.RED, 40)
			end
		end)
	end
end

return M
