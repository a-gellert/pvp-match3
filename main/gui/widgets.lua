-- Shared composite widgets: squad card (Clash Royale style), chest slot, reward chips, section headers.
local ui = require "main.gui.ui"
local config = require "main.modules.config"
local squads = require "main.modules.squads"
local progress = require "main.modules.progress"
local i18n = require "main.modules.i18n"

local M = {}
local V4 = vmath.vector4

-- Squad card in Clash Royale style: rarity frame, big art, colour gem (its lane), level ribbon and
-- the card-count bar under it (green + arrow when an upgrade is ready).
-- opts: tut (hand pointer), on_tap, deck (bigger fonts), hide_bar
function M.card_tile(parent, sq, x, y, w, h, opts)
	opts = opts or {}
	local d = progress.data
	local c = d.cards[sq.id]
	local unlocked = c.unlocked
	local req = squads.upgrade_req(sq.id, c.level)
	local can_up = progress.can_upgrade_card(sq.id)
	local bar_h = opts.hide_bar and 0 or math.max(22, math.floor(h * 0.1))
	local ch = h - bar_h - (bar_h > 0 and 6 or 0)
	local cy = y + (h - ch) / 2

	local holder = ui.pane(parent, x, cy)
	if can_up then
		local gl = ui.glow(ui.box(holder, "glow", 0, 0, w * 1.5, ch * 1.3, V4(0.3, 1, 0.5, 0.28)))
		ui.pulse(gl, 1.06, 0.6)
	end
	local frame = ui.RARITY_FRAME[sq.rarity] or "card_common"
	local card = ui.slice(holder, frame, 0, 0, w, ch, unlocked and ui.WHITE or V4(0.45, 0.47, 0.56, 1), 20)
	if opts.on_tap then ui.button(card, opts.on_tap) end

	local art_size = math.min(w - 22, ch - 44)
	if unlocked then
		local col = ui.GEM_COLOR[sq.color] or ui.WHITE
		ui.box(card, "glow", 0, 8, art_size * 1.15, art_size * 1.15, V4(col.x, col.y, col.z, 0.2))
	end
	local art = ui.icon(card, sq.sprite, 0, 8, art_size, unlocked and ui.WHITE or V4(0.08, 0.09, 0.14, 0.9))
	if unlocked then ui.bob(art, 3, 1.3, math.random() * 0.6) end
	ui.box(card, ui.GEM_SPRITE[sq.color], -w / 2 + 20, ch / 2 - 20, 28, 28)

	if unlocked then
		local rw = math.min(w - 20, opts.deck and 120 or 96)
		local rib = ui.slice(card, "panel_dark", 0, -ch / 2 + 16, rw, opts.deck and 32 or 28, ui.WHITE, 12)
		ui.label(rib, i18n.t("LVL_FMT", { n = c.level }), 0, 2, opts.deck and 20 or 17, ui.RARITY_COLOR[sq.rarity] or ui.BONE, rw - 12)
	else
		ui.text(card, "?", 0, 8, art_size * 0.5, ui.DIM)
		ui.box(card, "icon_lock", w / 2 - 20, ch / 2 - 20, 24, 24)
	end
	if c.new then
		local tag = ui.slice(card, "btn_crimson", w / 2 - 30, ch / 2 - 16, 60, 26, ui.WHITE, 10)
		ui.text(tag, i18n.t("NEW"), 0, 2, 14, ui.WHITE)
		ui.pulse(tag, 1.1, 0.4)
	end

	if bar_h > 0 and unlocked then
		local by = y - h / 2 + bar_h / 2
		if req then
			local bar = ui.bar(parent, x, by, w - 4, bar_h, math.min(1, c.count / req), can_up and ui.GREEN or ui.BLUE,
				{ text = c.count .. "/" .. req, text_size = math.max(14, bar_h - 7) })
			if can_up then
				local arrow = ui.box(bar.bg, "icon_play", -(w - 4) / 2 + 2, 0, bar_h + 8, bar_h + 8, ui.GREEN)
				gui.set_euler(arrow, vmath.vector3(0, 0, 90))
				ui.bob(arrow, 3, 0.4)
			end
		else
			local mx = ui.slice(parent, "panel_dark", x, by, w - 4, bar_h, ui.WHITE, 8)
			ui.text(mx, i18n.t("MAX"), 0, 1, math.max(14, bar_h - 7), ui.GOLD)
		end
	end
	if opts.tut then
		local hand = ui.box(card, "icon_hand", 22, -16, 64, 64)
		ui.pulse(hand, 1.18, 0.45)
		local gl = ui.glow(ui.slice(card, "tab_active", 0, 0, w + 14, ch + 14, ui.GOLD, 18))
		ui.pulse(gl, 1.03, 0.4)
	end
	return card
end

-- Reward chips ({gold, diamonds, booster+count, chest}) laid out horizontally around x.
function M.reward_row(parent, reward, x, y, size, color)
	local items = {}
	if reward.gold then items[#items + 1] = { "icon_gold", "+" .. reward.gold, ui.GOLD } end
	if reward.diamonds then items[#items + 1] = { "icon_diamond", "+" .. reward.diamonds, ui.DIAMOND } end
	if reward.booster then items[#items + 1] = { config.BOOSTERS[reward.booster].sprite, "x" .. (reward.count or 1), ui.BONE } end
	if reward.chest then items[#items + 1] = { config.CHESTS[reward.chest].sprite, "", ui.BONE } end
	size = size or 40
	local step = size * 2.4
	for i, it in ipairs(items) do
		local ix = x + (i - (#items + 1) / 2) * step
		local icon_x = it[2] ~= "" and (ix - size * 0.45) or ix
		ui.icon(parent, it[1], icon_x, y, size * (it[2] == "" and 1.3 or 1))
		if it[2] ~= "" then ui.text(parent, it[2], ix + size * 0.55, y, size * 0.55, color or it[3]) end
	end
end

function M.section(parent, title, x, y, w, icon)
	local bar = ui.slice(parent, "panel_dark", x, y, w, 46, V4(1, 1, 1, 0.9), 14)
	if icon then ui.icon(bar, icon, -w / 2 + 30, 0, 34) end
	ui.label(bar, title, icon and 14 or 0, 2, 22, ui.GOLD, w - 90)
	return bar
end

-- Chest slot. Returns the timer text node (or nil) so the caller can refresh it.
function M.chest_slot(parent, app, i, x, y, w, h)
	local d = progress.data
	local slot = d.chests[i]
	local box = ui.slice(parent, "panel_dark", x, y, w, h, ui.WHITE, 18)
	if not slot then
		gui.set_alpha(box, 0.7)
		ui.box(box, "chest_wood", 0, 10, math.min(w - 30, 70), math.min(w - 30, 70), V4(0.2, 0.22, 0.3, 0.6))
		ui.label(box, i18n.t("EMPTY_SLOT"), 0, -h / 2 + 22, 15, ui.DIM, w - 14)
		return nil
	end
	local def = config.CHESTS[slot.rarity]
	local rem = progress.chest_remaining(i)
	local size = math.min(w - 20, h - 64, 92)
	local ready = slot.unlocking and rem <= 0
	if ready then
		local rays = ui.glow(ui.box(box, "rays", 0, 14, size * 2, size * 2, V4(1, 0.85, 0.4, 0.45)))
		ui.spin(rays, 7)
	end
	local ic = ui.icon(box, def.sprite, 0, 16, size)
	ui.button(box, function()
		if ready then
			local res = progress.open_chest(i, false)
			if res then app.open_popup("chest", res) end
		else
			app.open_popup("chest_info", { slot = i })
		end
	end)
	local timer_node
	if ready then
		ui.bob(ic, 6, 0.45)
		local b = ui.slice(box, "btn_gold", 0, -h / 2 + 24, w - 16, 38, ui.WHITE, 14)
		ui.label(b, i18n.t("READY"), 0, 3, 17, ui.WHITE, w - 30)
		ui.pulse(b, 1.06, 0.4)
	elseif slot.unlocking then
		timer_node = ui.text(box, i18n.fmt_time(rem), 0, -h / 2 + 46, 17, ui.GOLD)
		local cost = progress.chest_rush_cost(i)
		local pill = ui.slice(box, "btn_purple", 0, -h / 2 + 20, w - 16, 32, ui.WHITE, 12)
		ui.box(pill, "icon_diamond", -18, 1, 20, 20)
		ui.text(pill, tostring(cost), 10, 2, 16, ui.WHITE)
	else
		ui.label(box, i18n.t("CHEST_" .. slot.rarity), 0, -h / 2 + 46, 14, ui.BONE, w - 14)
		local b = ui.slice(box, progress.any_chest_unlocking() and "btn_dark" or "btn_gold", 0, -h / 2 + 20, w - 16, 32, ui.WHITE, 12)
		ui.label(b, i18n.fmt_time(progress.chest_duration(i)), 0, 2, 15, ui.WHITE, w - 30)
	end
	return timer_node
end

return M
