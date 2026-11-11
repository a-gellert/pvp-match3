-- Shop Screen: Buy locked Squad Cards with Diamonds, buy Boosters with Gold.
local ui = require "main.gui.ui"
local config = require "main.modules.config"
local squads = require "main.modules.squads"
local progress = require "main.modules.progress"
local i18n = require "main.modules.i18n"
local audio = require "main.modules.audio"

local M = {}

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

	-- Locked Cards for Diamonds
	local locked = {}
	for _, sq in ipairs(squads.LIST) do
		if not d.cards[sq.id].unlocked then locked[#locked + 1] = sq end
	end

	local y_cards = vh - 265
	ui.text(root, i18n.t("COLLECTION"), vw / 2, y_cards + 106, 22, ui.DIAMOND)
	local shown = math.min(3, #locked)
	if shown == 0 then
		ui.text(root, i18n.t("MAX"), vw / 2, y_cards, 22, ui.GREEN)
	else
		for i = 1, shown do
			local sq = locked[i]
			local cx = vw / 2 + (i - (shown + 1) / 2) * 224
			local card = ui.slice(root, ui.RARITY_FRAME[sq.rarity], cx, y_cards - 30, 206, 220, ui.WHITE, 20)
			ui.icon(card, sq.sprite, 0, 32, 92)
			local nm = ui.text(card, i18n.t("SQ_" .. sq.id), 0, -28, 17, ui.BONE)
			ui.fit(nm, 184, 17)
			local d_cost = squads.unlock_diamonds(sq.id)
			ui.btn(card, "btn_purple", 0, -74, 176, 46, i18n.t("BUY_CARD", { d = d_cost }), 17, function()
				if progress.buy_locked_card(sq.id) then
					audio.play("upgrade")
					app.rebuild()
				else
					ui.float_text(root, i18n.t("MISS_RES"), cx, y_cards + 40, 20, ui.RED, 40)
				end
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
