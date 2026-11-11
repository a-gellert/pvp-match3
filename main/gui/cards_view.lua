-- Squads tab: commander (HP / moves upgrade), active slots, colour filter and a Druid scroll grid.
local ui = require "main.gui.ui"
local widgets = require "main.gui.widgets"
local config = require "main.modules.config"
local squads = require "main.modules.squads"
local progress = require "main.modules.progress"
local i18n = require "main.modules.i18n"
local audio = require "main.modules.audio"

local M = { filter = "all" }
local V4 = vmath.vector4

local FILTERS = { "all", "red", "yellow", "purple" }

local function sorted_list()
	local d = progress.data
	local out = {}
	for _, sq in ipairs(squads.LIST) do
		if M.filter == "all" or sq.color == M.filter then out[#out + 1] = sq end
	end
	local RANK = { common = 1, rare = 2, epic = 3, legendary = 4 }
	table.sort(out, function(a, b)
		local ca, cb = d.cards[a.id], d.cards[b.id]
		local ua, ub = progress.can_upgrade_card(a.id), progress.can_upgrade_card(b.id)
		if ua ~= ub then return ua end
		if ca.unlocked ~= cb.unlocked then return ca.unlocked end
		if a.color ~= b.color then return config.COLOR_INDEX[a.color] < config.COLOR_INDEX[b.color] end
		return RANK[a.rarity] < RANK[b.rarity]
	end)
	return out
end

local function commander_panel(app, parent, cx, y, w)
	local d = progress.data
	local box = ui.slice(parent, "panel_stone", cx, y, w, 130, ui.WHITE, 22)
	ui.box(box, "face_hero", -w / 2 + 64, 0, 96, 96)
	ui.label(box, i18n.t("COMMANDER_LVL", { n = d.commander_lvl }), -w / 2 + 124, 34, 24, ui.GOLD, w * 0.45, { pivot = gui.PIVOT_W })
	ui.box(box, "icon_heart", -w / 2 + 138, 0, 28, 28)
	ui.label(box, tostring(progress.hero_hp()), -w / 2 + 160, 1, 21, ui.BONE, 90, { pivot = gui.PIVOT_W })
	ui.box(box, "icon_shield", -w / 2 + 250, 0, 28, 28)
	ui.label(box, tostring(progress.shield_power()), -w / 2 + 272, 1, 21, ui.BONE, 70, { pivot = gui.PIVOT_W })
	local ox = -w / 2 + 138
	for i = 1, config.MAX_MOVES do
		local o = ui.box(box, "icon_move_orb", ox + (i - 1) * 28, -36, 24, 24, i <= d.max_moves and ui.WHITE or V4(0.3, 0.35, 0.45, 0.45))
		if i == d.max_moves then ui.pulse(o, 1.12, 0.6) end
	end
	local cost = progress.move_upgrade_cost()
	local bw = math.min(230, w * 0.34)
	if cost then
		local can = d.gold >= cost
		ui.btn(box, can and "btn_gold" or "btn_dark", w / 2 - bw / 2 - 16, 0, bw, 84, i18n.t("UPGRADE_MOVES", { g = cost }), 20, function()
			if progress.upgrade_moves() then
				audio.play("levelup")
				app.open_popup("levelup", { kind = "moves" })
				app.rebuild()
			else
				audio.play("blocked")
				ui.float_text(app.hub_fx, i18n.t("NEED_GOLD"), cx + w / 2 - bw / 2 - 16, y + 50, 22, ui.RED, 40)
			end
		end, { icon = "icon_move_orb", icon_size = 40, badge = can and 1 or 0 })
	else
		ui.label(box, i18n.t("MAX_MOVES"), w / 2 - bw / 2 - 16, 0, 22, ui.GOLD, bw)
	end
end

function M.build(app, parent, R)
	local d = progress.data
	local land = app.orient == "landscape"
	local w = land and R.w or math.min(R.w, 720)
	local cx = R.cx

	local top = R.y1
	if land then
		-- Left column: commander + active slots; right: collection
		local lw = math.min(560, R.w * 0.36)
		local lcx = R.x0 + lw / 2
		commander_panel(app, parent, lcx, top - 70, lw)
		widgets.section(parent, i18n.t("SQUAD_SLOTS"), lcx, top - 168, lw, "icon_sword")
		local sh = math.min(230, (top - 200 - R.y0) / 3 - 10)
		for i, col in ipairs(config.ATTACK_COLORS) do
			local sq = squads.get(d.slots[col])
			local y = top - 204 - sh / 2 - (i - 1) * (sh + 10)
			widgets.card_tile(parent, sq, lcx, y, lw - 40, sh, { active = true, on_tap = function() app.open_popup("card", { id = sq.id }) end })
		end
		cx = R.x0 + lw + 20 + (R.w - lw - 20) / 2
		w = R.w - lw - 20
	else
		commander_panel(app, parent, cx, top - 70, w)
		top = top - 148
		widgets.section(parent, i18n.t("SQUAD_SLOTS"), cx, top - 22, w, "icon_sword")
		local sw = (w - 24) / 3
		for i, col in ipairs(config.ATTACK_COLORS) do
			local sq = squads.get(d.slots[col])
			widgets.card_tile(parent, sq, cx + (i - 2) * (sw + 12), top - 140, sw, 196,
				{ active = true, on_tap = function() app.open_popup("card", { id = sq.id }) end })
		end
		top = top - 248
	end

	-- Filter tabs
	local ft_y = land and (R.y1 - 30) or (top - 34)
	local fw = (w - 30) / #FILTERS
	for i, f in ipairs(FILTERS) do
		local active = M.filter == f
		local fx = cx + (i - (#FILTERS + 1) / 2) * (fw + 10)
		local _, b = ui.btn(parent, active and "btn_gold" or "btn_dark", fx, ft_y, fw, 50, i18n.t("FILTER_" .. f), 18, function()
			if M.filter ~= f then M.filter = f; app.rebuild() end
		end, { icon = f ~= "all" and ui.GEM_SPRITE[f] or "icon_cards", icon_size = 30, text_color = active and ui.INK or ui.BONE })
		local cnt = 0
		for _, sq in ipairs(squads.LIST) do
			if (f == "all" or sq.color == f) and progress.can_upgrade_card(sq.id) then cnt = cnt + 1 end
		end
		if cnt > 0 then ui.badge(b.node, fw / 2 - 8, 18, cnt, 26) end
	end

	-- Scroll grid
	local view_top = ft_y - 34
	local view_h = view_top - R.y0
	local sc = ui.scroll(parent, cx, R.y0 + view_h / 2, w, view_h)
	local list = sorted_list()
	local cols = math.max(3, math.floor(w / 200))
	local cw = (w - 16 - (cols - 1) * 12) / cols
	local ch = math.min(250, cw * 1.25)
	for idx, sq in ipairs(list) do
		local r = math.floor((idx - 1) / cols)
		local c = (idx - 1) % cols
		local x = -w / 2 + 8 + cw / 2 + c * (cw + 12)
		local y = -14 - ch / 2 - r * (ch + 12)
		local tut = d.onboarding_step == 1 and sq.id == "red_militia"
		widgets.card_tile(sc.content, sq, x, y, cw, ch, {
			active = d.slots[sq.color] == sq.id,
			tut = tut,
			on_tap = function() app.open_popup("card", { id = sq.id }) end,
		})
	end
	local rows = math.ceil(#list / cols)
	sc.set_height(rows * (ch + 12) + 30)

	if d.onboarding_step == 1 then
		local hint = ui.slice(parent, "btn_gold", cx, R.y0 + 34, math.min(w - 20, 560), 52, ui.WHITE, 16)
		ui.label(hint, i18n.t("TUT_UPGRADE"), 0, 2, 21, ui.INK, math.min(w - 20, 560) - 30)
		ui.pulse(hint, 1.04, 0.5)
	end
end

return M
