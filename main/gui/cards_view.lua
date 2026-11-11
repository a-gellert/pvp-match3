-- Squads tab in Clash Royale style: the battle squad (3 big cards, one per gem colour / lane) with a
-- compact "moves per turn" upgrade, then the collection (found cards) and the cards not found yet.
-- Tapping any card opens its info popup (stats, skill, Use / Upgrade). No filters, no duplicates.
local ui = require "main.gui.ui"
local widgets = require "main.gui.widgets"
local config = require "main.modules.config"
local squads = require "main.modules.squads"
local progress = require "main.modules.progress"
local i18n = require "main.modules.i18n"
local audio = require "main.modules.audio"

local M = {}
local V4 = vmath.vector4

local RANK = { common = 1, rare = 2, epic = 3, legendary = 4 }

local function collection()
	local d = progress.data
	local found, missing = {}, {}
	for _, sq in ipairs(squads.LIST) do
		if d.slots[sq.color] ~= sq.id then
			if d.cards[sq.id].unlocked then found[#found + 1] = sq else missing[#missing + 1] = sq end
		end
	end
	table.sort(found, function(a, b)
		local ua, ub = progress.can_upgrade_card(a.id), progress.can_upgrade_card(b.id)
		if ua ~= ub then return ua end
		if a.color ~= b.color then return config.COLOR_INDEX[a.color] < config.COLOR_INDEX[b.color] end
		return RANK[a.rarity] < RANK[b.rarity]
	end)
	table.sort(missing, function(a, b)
		if a.rarity ~= b.rarity then return RANK[a.rarity] < RANK[b.rarity] end
		return config.COLOR_INDEX[a.color] < config.COLOR_INDEX[b.color]
	end)
	return found, missing
end

local function open_card(app, id)
	app.open_popup("card", { id = id })
end

-- Section band: title on the left, optional right-hand value with an icon.
local function band(parent, x, y, w, title, right, icon)
	local b = ui.slice(parent, "panel_dark", x, y, w, 48, V4(1, 1, 1, 0.95), 14)
	ui.label(b, title, -w / 2 + 18, 2, 22, ui.GOLD, w * 0.58, { pivot = gui.PIVOT_W })
	if right then
		local t = ui.text(b, right, w / 2 - 16, 2, 20, ui.BONE)
		gui.set_pivot(t, gui.PIVOT_E)
		ui.fit(t, w * 0.34, 20)
		if icon then ui.icon(b, icon, w / 2 - 16 - ui.text_width(t) * gui.get_scale(t).x - 22, 1, 30) end
	end
	return b
end

-- Moves per turn: orbs + upgrade button (one compact row).
local function moves_row(app, parent, cx, y, w)
	local d = progress.data
	local row = ui.slice(parent, "panel_dark", cx, y, w, 70, V4(1, 1, 1, 0.9), 16)
	ui.label(row, i18n.t("MOVES_PER_TURN"), -w / 2 + 18, 15, 18, ui.DIM, w * 0.5, { pivot = gui.PIVOT_W })
	local ox = -w / 2 + 30
	for i = 1, config.MAX_MOVES do
		local o = ui.box(row, "icon_move_orb", ox + (i - 1) * 26, -13, 22, 22, i <= d.max_moves and ui.WHITE or V4(0.3, 0.35, 0.45, 0.45))
		if i == d.max_moves then ui.pulse(o, 1.12, 0.6) end
	end
	local cost = progress.move_upgrade_cost()
	local bw = math.min(210, w * 0.36)
	local bx = w / 2 - bw / 2 - 10
	if cost then
		local can = d.gold >= cost
		ui.btn(row, can and "btn_gold" or "btn_dark", bx, 0, bw, 56, "+1  " .. cost, 22, function()
			if progress.upgrade_moves() then
				audio.play("levelup")
				app.refresh_then_popup("levelup", { kind = "moves" })
			else
				audio.play("blocked")
				ui.float_text(app.hub_fx, i18n.t("NEED_GOLD"), app.vw / 2, app.vh / 2, 24, ui.RED, 40)
			end
		end, { icon = "icon_gold", icon_size = 32, badge = can and 1 or 0 })
	else
		ui.label(row, i18n.t("MAX_MOVES"), bx, 0, 20, ui.GOLD, bw)
	end
end

-- The battle squad panel from y = top downward; returns its height.
local function deck(app, parent, cx, top, w, card_w)
	local d = progress.data
	local card_h = math.floor(card_w * 1.5)
	local h = 64 + card_h + 14 + 84
	ui.slice(parent, "panel_stone", cx, top - h / 2, w, h, ui.WHITE, 22)
	band(parent, cx, top - 34, w - 24, i18n.t("DECK"), tostring(progress.hero_hp()), "icon_heart")
	local gap = (w - 24 - card_w * 3) / 2
	for i, col in ipairs(config.ATTACK_COLORS) do
		local sq = squads.get(d.slots[col])
		local x = cx + (i - 2) * (card_w + gap)
		widgets.card_tile(parent, sq, x, top - 66 - card_h / 2, card_w, card_h, {
			deck = true,
			tut = d.onboarding_step == 1 and sq.id == "red_militia",
			on_tap = function() open_card(app, sq.id) end,
		})
	end
	moves_row(app, parent, cx, top - 66 - card_h - 14 - 38, w - 24)
	return h
end

-- Grid of cards from y = top downward; returns its height.
local function grid(app, parent, list, cx, top, w, cols)
	if #list == 0 then return 0 end
	local gap = 12
	local cw = (w - (cols - 1) * gap) / cols
	local ch = math.floor(cw * 1.45)
	for idx, sq in ipairs(list) do
		local r = math.floor((idx - 1) / cols)
		local c = (idx - 1) % cols
		local x = cx - w / 2 + cw / 2 + c * (cw + gap)
		local y = top - ch / 2 - r * (ch + gap)
		widgets.card_tile(parent, sq, x, y, cw, ch, {
			hide_bar = not progress.data.cards[sq.id].unlocked,
			on_tap = function() open_card(app, sq.id) end,
		})
	end
	local rows = math.ceil(#list / cols)
	return rows * (ch + gap) - gap
end

local function collection_block(app, parent, cx, top, w, cols)
	local found, missing = collection()
	local total = #squads.LIST
	local y = top
	band(parent, cx, y - 24, w, i18n.t("COLLECTION_FMT", { a = total - #missing, b = total }))
	y = y - 62
	y = y - grid(app, parent, found, cx, y, w, cols) - 22
	if #missing > 0 then
		band(parent, cx, y - 24, w, i18n.t("NOT_FOUND"), i18n.t("IN_CHESTS"), "chest_wood")
		y = y - 62
		y = y - grid(app, parent, missing, cx, y, w, cols) - 22
	end
	return top - y
end

function M.build(app, parent, R)
	local d = progress.data
	local land = app.orient == "landscape"
	if land then
		-- Left: battle squad (fixed). Right: collection (scroll).
		local lw = math.min(620, R.w * 0.42)
		local lcx = R.x0 + lw / 2
		local card_w = math.floor(math.min(180, (lw - 60) / 3, (R.h - 180) / 1.5))
		deck(app, parent, lcx, R.y1 - 4, lw, card_w)
		local rw = R.w - lw - 24
		local rcx = R.x1 - rw / 2
		local sc = ui.scroll(parent, rcx, R.cy, rw, R.h)
		local cols = math.max(4, math.floor(rw / 170))
		local h = collection_block(app, sc.content, 0, -10, rw - 20, cols)
		sc.set_height(h + 30)
	else
		local w = math.min(R.w, 720)
		local sc = ui.scroll(parent, R.cx, R.cy, w, R.h)
		local card_w = math.floor((w - 24 - 2 * 16) / 3)
		local top = -6
		local h = deck(app, sc.content, 0, top, w, card_w)
		top = top - h - 18
		local ch = collection_block(app, sc.content, 0, top, w - 16, 4)
		sc.set_height(h + ch + 60)
	end

	if d.onboarding_step == 1 then
		local hw = math.min(R.w - 40, 560)
		local hint = ui.slice(parent, "btn_gold", R.cx, R.y0 + 34, hw, 52, ui.WHITE, 16)
		ui.label(hint, i18n.t("TUT_UPGRADE"), 0, 2, 21, ui.INK, hw - 30)
		ui.pulse(hint, 1.04, 0.5)
	end
end

return M
