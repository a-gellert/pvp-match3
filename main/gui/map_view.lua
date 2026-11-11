-- Campaign World Map: 12 stages across 3 zones, replayable for farming.
local ui = require "main.gui.ui"
local campaign = require "main.modules.campaign"
local progress = require "main.modules.progress"
local config = require "main.modules.config"
local i18n = require "main.modules.i18n"

local M = {}

function M.build(app, parent)
	local root = ui.pane(parent, 0, 0)
	local vw, vh = app.vw, app.vh
	local is_land = app.orient == "landscape"
	local d = progress.data

	ui.box(root, "square", vw / 2, vh / 2, vw, vh, ui.BG_DARK)

	-- Header
	ui.btn(root, "btn_dark", 96, vh - 46, 150, 56, i18n.t("HUB"), 22, function() app.show_hub() end)
	ui.text(root, i18n.t("CAMPAIGN"), vw / 2, vh - 46, 30, ui.GOLD)
	ui.currency_pill(root, "icon_prestige", d.prestige, vw - 100, vh - 46, 160, 48)

	local cols = is_land and 4 or 3
	local cw = is_land and 340 or 212
	local ch = is_land and 205 or 218
	local gap_x = is_land and 366 or 228
	local gap_y = is_land and 225 or 244

	for idx, stg in ipairs(campaign.STAGES) do
		local r = math.floor((idx - 1) / cols)
		local c = (idx - 1) % cols
		local cx = vw / 2 + (c - (cols - 1) / 2) * gap_x
		local cy = vh - 190 - r * gap_y
		local unlocked = stg.id <= (d.max_stage_unlocked or 1)
		local cleared = stg.id < (d.max_stage_unlocked or 1)

		local frame = stg.boss and "card_epic" or (unlocked and "card_rare" or "card_common")
		local card = ui.slice(root, frame, cx, cy, cw, ch, unlocked and ui.WHITE or vmath.vector4(0.55, 0.55, 0.65, 0.85), 20)

		ui.text(card, i18n.t("STAGE_FMT", { n = stg.id }), -cw / 2 + 54, ch / 2 - 24, 16, ui.GOLD)
		if stg.boss then
			ui.text(card, i18n.t("BOSS"), cw / 2 - 42, ch / 2 - 24, 15, ui.RED)
		elseif cleared then
			ui.box(card, "icon_check", cw / 2 - 24, ch / 2 - 24, 24, 24)
		elseif not unlocked then
			ui.box(card, "icon_lock", cw / 2 - 24, ch / 2 - 24, 24, 24)
		end

		local face_sz = is_land and 72 or 56
		local face_x = -cw / 2 + (is_land and 52 or 38)
		local tx = is_land and 36 or 32
		local tw = cw - (is_land and 130 or 94)
		ui.box(card, stg.face, face_x, 12, face_sz, face_sz)
		local e_lbl = ui.text(card, i18n.t(stg.name_key), tx, 30, 17, ui.BONE)
		ui.fit(e_lbl, tw, 17)
		local hp_lbl = ui.text(card, "HP " .. stg.hp .. " | " .. i18n.t("MOVES_FMT", { n = stg.moves }), tx, 2, 15, ui.DIM)
		ui.fit(hp_lbl, tw, 15)
		ui.box(card, config.CHESTS[stg.chest].sprite, 0, -26, 34, 34)
		ui.text(card, "+" .. stg.gold, 42, -26, 16, ui.GOLD)

		if unlocked then
			ui.btn(card, stg.boss and "btn_crimson" or "btn_gold", 0, -ch / 2 + 30, cw - 24, 42, i18n.t("FIGHT"), 18, function()
				app.start_campaign(stg.id)
			end)
		end
	end
end

return M
