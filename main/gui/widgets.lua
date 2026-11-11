-- Shared composite widgets: squad card tile, chest slot, reward chips, section headers.
local ui = require "main.gui.ui"
local config = require "main.modules.config"
local squads = require "main.modules.squads"
local progress = require "main.modules.progress"
local i18n = require "main.modules.i18n"

local M = {}
local V4 = vmath.vector4

-- Squad card. opts: active (equipped check), tut (hand pointer), on_tap, compact
function M.card_tile(parent, sq, x, y, w, h, opts)
	opts = opts or {}
	local d = progress.data
	local c = d.cards[sq.id]
	local unlocked = c.unlocked
	local req = squads.upgrade_req(sq.id, c.level)
	local can_up = progress.can_upgrade_card(sq.id)

	local frame = ui.RARITY_FRAME[sq.rarity] or "card_common"
	local card = ui.slice(parent, frame, x, y, w, h, unlocked and ui.WHITE or V4(0.55, 0.57, 0.66, 1), 20)
	if opts.on_tap then ui.button(card, opts.on_tap) end

	ui.box(card, ui.GEM_SPRITE[sq.color], -w / 2 + 22, h / 2 - 22, 26, 26)
	if sq.runes then
		ui.box(card, ui.GEM_SPRITE[sq.runes[1]], -9, h / 2 - 20, 16, 16)
		ui.box(card, ui.GEM_SPRITE[sq.runes[2]], 9, h / 2 - 20, 16, 16)
	end
	if opts.active then
		ui.box(card, "icon_check", w / 2 - 20, h / 2 - 20, 26, 26)
	elseif not unlocked then
		ui.box(card, "icon_lock", w / 2 - 20, h / 2 - 20, 22, 22)
	end

	local art_size = math.min(w - 30, h - 74, 96)
	local art = ui.icon(card, sq.sprite, 0, 10, art_size, unlocked and ui.WHITE or V4(0.35, 0.36, 0.45, 1))
	if unlocked then ui.bob(art, 3, 1.3, math.random() * 0.6) end

	ui.label(card, i18n.t("SQ_" .. sq.id), 0, -h / 2 + 46, 16, ui.BONE, w - 16)
	if unlocked then
		local lv = ui.slice(card, "panel_dark", -w / 2 + 34, h / 2 - 50, 52, 26, ui.WHITE, 10)
		ui.label(lv, i18n.t("LVL_FMT", { n = c.level }), 0, 1, 15, ui.GOLD, 46)
		if req then
			local bar = ui.bar(card, 0, -h / 2 + 20, w - 22, 20, math.min(1, c.count / req), can_up and ui.GREEN or ui.BLUE,
				{ text = c.count .. "/" .. req, text_size = 15 })
			if can_up then
				local arrow = ui.box(card, "icon_play", w / 2 - 18, -h / 2 + 22, 24, 24, ui.GREEN)
				gui.set_euler(arrow, vmath.vector3(0, 0, 90))
				ui.bob(arrow, 4, 0.4)
			end
		else
			ui.label(card, i18n.t("MAX"), 0, -h / 2 + 20, 16, ui.GOLD, w - 20)
		end
	else
		ui.box(card, "icon_diamond", -20, -h / 2 + 20, 22, 22)
		ui.text(card, tostring(squads.unlock_diamonds(sq.id)), 12, -h / 2 + 20, 18, ui.DIAMOND)
	end
	if c.new then
		local tag = ui.slice(card, "btn_crimson", w / 2 - 30, h / 2 - 52, 58, 26, ui.WHITE, 10)
		ui.text(tag, i18n.t("NEW"), 0, 2, 14, ui.WHITE)
		ui.pulse(tag, 1.1, 0.4)
	end
	if opts.tut then
		local hand = ui.box(card, "icon_hand", 22, -16, 56, 56)
		ui.pulse(hand, 1.18, 0.45)
		local gl = ui.glow(ui.slice(card, "tab_active", 0, 0, w + 14, h + 14, ui.GOLD, 18))
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
		ui.label(b, i18n.fmt_time(def.duration), 0, 2, 15, ui.WHITE, w - 30)
	end
	return timer_node
end

return M
