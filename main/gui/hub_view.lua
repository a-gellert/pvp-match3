-- Hub Screen: Currencies, 3 Active Slots, Moves (1..7), Color-Filtered 18-Squad Collection, 4 Chests.
local ui = require "main.gui.ui"
local config = require "main.modules.config"
local squads = require "main.modules.squads"
local progress = require "main.modules.progress"
local i18n = require "main.modules.i18n"
local audio = require "main.modules.audio"

local M = { filter = "red" }
local st = {}

local GEM_SPRITE = {
	red = "gem_red",
	yellow = "gem_yellow",
	purple = "gem_purple",
	green = "gem_green",
	blue = "gem_blue",
}

local function draw_card_tile(parent, sq, x, y, w, h, is_active, highlight_tut)
	local d = progress.data
	local c = d.cards[sq.id]
	local unlocked = c.unlocked
	local req = squads.upgrade_req(sq.id, c.level)
	local can_up = progress.can_upgrade_card(sq.id)

	local frame_sp = ui.RARITY_FRAME[sq.rarity] or "card_common"
	local card_btn = ui.slice(parent, frame_sp, x, y, w, h, unlocked and ui.WHITE or vmath.vector4(0.65, 0.65, 0.72, 0.9), 20)
	ui.button(card_btn, w, h, function()
		st.app.open_popup("card", { id = sq.id })
	end)

	-- Color gem indicator in top-left & 2 Rune crystal icons along top center
	ui.box(card_btn, GEM_SPRITE[sq.color], -w / 2 + 22, h / 2 - 22, 24, 24)
	if sq.runes then
		ui.box(card_btn, GEM_SPRITE[sq.runes[1]], -9, h / 2 - 20, 16, 16)
		ui.box(card_btn, GEM_SPRITE[sq.runes[2]], 9, h / 2 - 20, 16, 16)
	end
	if is_active then
		ui.box(card_btn, "icon_check", w / 2 - 20, h / 2 - 20, 22, 22)
	elseif not unlocked then
		ui.box(card_btn, "icon_lock", w / 2 - 20, h / 2 - 20, 20, 20)
	end

	-- Squad sprite (1-4 warriors)
	ui.icon(card_btn, sq.sprite, 0, 8, math.min(w - 26, 82), unlocked and ui.WHITE or vmath.vector4(0.4, 0.4, 0.5, 0.9))

	-- Name & level / bar
	local title = ui.text(card_btn, i18n.t("SQ_" .. sq.id), 0, -h / 2 + 44, 15, ui.BONE)
	ui.fit(title, w - 16, 15)

	if unlocked then
		ui.text(card_btn, i18n.t("LVL_FMT", { n = c.level }), -w / 2 + 28, h / 2 - 44, 14, ui.GOLD)
		if req then
			local col = can_up and ui.GREEN or ui.BLUE
			ui.hp_bar(card_btn, 0, -h / 2 + 20, w - 20, 18, c.count, req, 0, col)
		else
			ui.text(card_btn, i18n.t("MAX"), 0, -h / 2 + 20, 15, ui.GOLD)
		end
	else
		local d_cost = squads.unlock_diamonds(sq.id)
		ui.box(card_btn, "icon_diamond", -18, -h / 2 + 20, 20, 20)
		ui.text(card_btn, tostring(d_cost), 12, -h / 2 + 20, 17, ui.DIAMOND)
	end

	if highlight_tut then
		local hand = ui.box(card_btn, "icon_hand", 26, -12, 48, 48)
		ui.pulse(hand, 1.18, 0.45)
	end
end

local function draw_filter_tabs(parent, cx, y, tw, gap)
	local d = progress.data
	for i, col in ipairs(config.ATTACK_COLORS) do
		local tx = cx + (i - 2) * gap
		local active = M.filter == col
		local b = ui.btn(parent, active and "btn_gold" or "btn_dark", tx, y, tw, 44, "", 16, function()
			if M.filter ~= col then
				M.filter = col
				st.app.rebuild()
			end
		end)
		ui.box(b, GEM_SPRITE[col], -tw / 2 + 24, 0, 24, 24)
		local lbl = ui.text(b, i18n.t("FILTER_" .. col), 12, 1, 16, active and ui.INK or ui.BONE)
		ui.fit(lbl, tw - 48, 16)
		for _, sq in ipairs(squads.by_color(col)) do
			if progress.can_upgrade_card(sq.id) then
				ui.box(b, "spark", tw / 2 - 14, 12, 18, 18, ui.GREEN)
				break
			end
		end
	end
end

local function refresh_chests()
	if not st.chest_layer then return end
	gui.delete_node(st.chest_layer)
	st.chest_layer = ui.pane(st.root, 0, 0)
	local d = progress.data
	local any_unlocking = progress.any_chest_unlocking()

	for i = 1, config.MAX_CHEST_SLOTS do
		local pos = st.chest_pos[i]
		local cw, ch = pos.w, pos.h
		local slot = d.chests[i]
		local box = ui.slice(st.chest_layer, "panel_dark", pos.x, pos.y, cw, ch, ui.WHITE, 18)
		if not slot then
			local e_lbl = ui.text(box, i18n.t("EMPTY_SLOT"), 0, 0, 16, ui.DIM)
			ui.fit(e_lbl, cw - 14, 16)
		else
			local def = config.CHESTS[slot.rarity]
			local rem = progress.chest_remaining(i)
			ui.icon(box, def.sprite, 0, 18, math.min(cw - 24, 68))
			if rem <= 0 and slot.unlocking then
				ui.btn(box, "btn_gold", 0, -ch / 2 + 28, cw - 14, 42, i18n.t("READY"), 16, function()
					local res = progress.open_chest(i, false)
					if res then
						audio.play("chest")
						st.app.open_popup("chest", res)
					end
				end)
			elseif slot.unlocking then
				local t_lbl = ui.text(box, i18n.fmt_time(rem), 0, -14, 16, ui.GOLD)
				ui.fit(t_lbl, cw - 14, 16)
				local r_cost = progress.chest_rush_cost(i)
				ui.btn(box, "btn_purple", 0, -ch / 2 + 28, cw - 14, 42, i18n.t("RUSH_DIAM", { d = r_cost }), 15, function()
					local res = progress.open_chest(i, true)
					if res then
						audio.play("chest")
						st.app.open_popup("chest", res)
					else
						ui.float_text(st.root, i18n.t("MISS_RES"), pos.x, pos.y + 40, 20, ui.RED, 40)
					end
				end)
			else
				local dur_lbl = ui.text(box, i18n.fmt_time(def.duration), 0, -14, 15, ui.DIM)
				ui.fit(dur_lbl, cw - 14, 15)
				if not any_unlocking then
					ui.btn(box, "btn_gold", 0, -ch / 2 + 28, cw - 14, 42, i18n.t("START_TIMER"), 15, function()
						progress.start_chest(i)
						refresh_chests()
					end)
				else
					local r_cost = progress.chest_rush_cost(i)
					ui.btn(box, "btn_dark", 0, -ch / 2 + 28, cw - 14, 42, i18n.t("RUSH_DIAM", { d = r_cost }), 15, function()
						local res = progress.open_chest(i, true)
						if res then
							audio.play("chest")
							st.app.open_popup("chest", res)
						end
					end)
				end
			end
		end
	end
end

function M.build(app, parent)
	st = {
		app = app,
		root = ui.pane(parent, 0, 0),
		chest_pos = {},
		tick = 0,
	}
	local vw, vh = app.vw, app.vh
	local is_land = app.orient == "landscape"
	local d = progress.data

	ui.box(st.root, "square", vw / 2, vh / 2, vw, vh, ui.BG_DARK)

	-- Top Bar
	ui.currency_pill(st.root, "icon_prestige", d.prestige, 96, vh - 42, 160, 48)
	ui.currency_pill(st.root, "icon_gold", d.gold, 274, vh - 42, 160, 48)
	ui.currency_pill(st.root, "icon_diamond", d.diamonds, 452, vh - 42, 160, 48)
	ui.btn(st.root, "btn_round", vw - 44, vh - 42, 56, 56, "", 20, function()
		app.open_popup("settings")
	end)
	ui.box(st.root, "icon_gear", vw - 44, vh - 42, 28, 28)

	local list = squads.by_color(M.filter)

	if is_land then
		local lx = 390
		ui.slice(st.root, "panel_stone", lx, vh - 210, 720, 230, ui.WHITE, 22)
		ui.text(st.root, i18n.t("SQUAD_SLOTS"), lx, vh - 118, 22, ui.GOLD)
		for i, col in ipairs(config.ATTACK_COLORS) do
			local sq = squads.get(d.slots[col])
			draw_card_tile(st.root, sq, lx + (i - 2) * 224, vh - 222, 198, 162, true, false)
		end

		local my = vh - 365
		ui.slice(st.root, "panel_dark", lx, my, 720, 74, ui.WHITE, 18)
		for i = 1, config.MAX_MOVES do
			ui.box(st.root, "icon_move_orb", lx - 310 + (i - 1) * 32, my, 26, 26,
				i <= d.max_moves and ui.WHITE or vmath.vector4(0.3, 0.35, 0.45, 0.4))
		end
		local m_cost = progress.move_upgrade_cost()
		if m_cost then
			local can_m = d.gold >= m_cost
			ui.btn(st.root, can_m and "btn_gold" or "btn_dark", lx + 190, my, 280, 50,
				i18n.t("UPGRADE_MOVES", { g = m_cost }), 20, function()
					if progress.upgrade_moves() then
						audio.play("upgrade")
						app.rebuild()
					else
						ui.float_text(st.root, i18n.t("MISS_RES"), lx + 190, my + 40, 20, ui.RED, 40)
					end
				end)
		else
			ui.text(st.root, i18n.t("MAX_MOVES"), lx + 180, my, 20, ui.GOLD)
		end

		ui.text(st.root, i18n.t("CHESTS"), lx, vh - 436, 20, ui.BONE)
		for i = 1, 4 do
			st.chest_pos[i] = { x = lx - 264 + (i - 1) * 176, y = vh - 548, w = 164, h = 180 }
		end

		-- Right panel: Collection tabs (Red / Yellow / Purple) + 3x2 grid (6 cards of active color)
		local rx = vw - 420
		ui.slice(st.root, "panel_stone", rx, vh / 2 + 24, 790, 680, ui.WHITE, 22)
		ui.text(st.root, i18n.t("COLLECTION"), rx, vh - 114, 22, ui.GOLD)
		draw_filter_tabs(st.root, rx, vh - 166, 228, 242)
		for idx, sq in ipairs(list) do
			local row = math.floor((idx - 1) / 3)
			local col_i = (idx - 1) % 3
			local cx = rx - 245 + col_i * 245
			local cy = vh - 296 - row * 214
			local is_eq = d.slots[sq.color] == sq.id
			local tut_hl = (d.onboarding_step == 1 and sq.id == "red_militia")
			draw_card_tile(st.root, sq, cx, cy, 224, 190, is_eq, tut_hl)
		end

		ui.btn(st.root, "btn_gold", lx - 235, 92, 215, 76, i18n.t("CAMPAIGN"), 22, function() app.show_map() end)
		ui.btn(st.root, "btn_crimson", lx, 92, 225, 76, i18n.t("PVP"), 22, function() app.start_pvp_search() end)
		ui.btn(st.root, "btn_purple", lx + 235, 92, 215, 76, i18n.t("SHOP"), 22, function() app.show_shop() end)
	else
		-- Portrait: Active Slots -> Moves Bar -> Color Tabs -> 3x2 Cards Grid -> Onboarding Banner -> 4 Chests -> Nav
		local top_y = vh - 184
		ui.slice(st.root, "panel_stone", vw / 2, top_y, vw - 28, 196, ui.WHITE, 20)
		ui.text(st.root, i18n.t("SQUAD_SLOTS"), vw / 2, top_y + 76, 19, ui.GOLD)
		for i, col in ipairs(config.ATTACK_COLORS) do
			local sq = squads.get(d.slots[col])
			draw_card_tile(st.root, sq, vw / 2 + (i - 2) * 218, top_y - 10, 202, 138, true, false)
		end

		local my = top_y - 140
		ui.slice(st.root, "panel_dark", vw / 2, my, vw - 28, 66, ui.WHITE, 18)
		for i = 1, config.MAX_MOVES do
			ui.box(st.root, "icon_move_orb", 56 + (i - 1) * 32, my, 24, 24,
				i <= d.max_moves and ui.WHITE or vmath.vector4(0.3, 0.35, 0.45, 0.4))
		end
		local m_cost = progress.move_upgrade_cost()
		if m_cost then
			local can_m = d.gold >= m_cost
			ui.btn(st.root, can_m and "btn_gold" or "btn_dark", vw - 154, my, 248, 48,
				i18n.t("UPGRADE_MOVES", { g = m_cost }), 18, function()
					if progress.upgrade_moves() then
						audio.play("upgrade")
						app.rebuild()
					else
						ui.float_text(st.root, i18n.t("MISS_RES"), vw - 154, my + 38, 18, ui.RED, 40)
					end
				end)
		else
			ui.text(st.root, i18n.t("MAX_MOVES"), vw - 154, my, 18, ui.GOLD)
		end

		local tab_y = my - 66
		draw_filter_tabs(st.root, vw / 2, tab_y, 212, 224)
		for idx, sq in ipairs(list) do
			local row = math.floor((idx - 1) / 3)
			local col_i = (idx - 1) % 3
			local cx = vw / 2 + (col_i - 1) * 224
			local cy = tab_y - 110 - row * 164
			local is_eq = d.slots[sq.color] == sq.id
			local tut_hl = (d.onboarding_step == 1 and sq.id == "red_militia")
			draw_card_tile(st.root, sq, cx, cy, 208, 152, is_eq, tut_hl)
		end

		-- 4 Chests
		local chest_y = 248
		ui.text(st.root, i18n.t("CHESTS"), vw / 2, chest_y + 92, 18, ui.BONE)
		for i = 1, 4 do
			st.chest_pos[i] = { x = 104 + (i - 1) * 170, y = chest_y, w = 158, h = 150 }
		end

		-- Bottom Nav
		ui.btn(st.root, "btn_gold", 128, 66, 212, 74, i18n.t("CAMPAIGN"), 20, function() app.show_map() end)
		ui.btn(st.root, "btn_crimson", vw / 2, 66, 224, 74, i18n.t("PVP"), 22, function() app.start_pvp_search() end)
		ui.btn(st.root, "btn_purple", vw - 128, 66, 212, 74, i18n.t("SHOP"), 20, function() app.show_shop() end)
	end

	if d.onboarding_step == 1 then
		local by = is_land and (vh - 76) or 476
		local bx = is_land and (vw - 420) or (vw / 2)
		local ban = ui.slice(st.root, "btn_gold", bx, by, 440, 42, ui.WHITE, 14)
		ui.text(ban, i18n.t("TUT_UPGRADE"), 0, 1, 20, ui.INK)
	end

	st.chest_layer = ui.pane(st.root, 0, 0)
	refresh_chests()
end

function M.update(dt)
	st.tick = (st.tick or 0) + dt
	if st.tick >= 1.0 then
		st.tick = 0
		refresh_chests()
	end
end

return M
