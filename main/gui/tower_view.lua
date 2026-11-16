-- Endless Gauntlet tab: 5 fights, carried HP, one of three run relics after every win.
local ui = require "main.gui.ui"
local widgets = require "main.gui.widgets"
local config = require "main.modules.config"
local progress = require "main.modules.progress"
local i18n = require "main.modules.i18n"

local M = {}
local V4 = vmath.vector4

local function step_pips(parent, cx, y, step, total)
	local gap = 58
	local x0 = cx - (total - 1) * gap / 2
	for i = 1, total do
		local cleared = i < step or (step > total)
		local current = i == step
		local node = ui.box(parent, "badge_dot", x0 + (i - 1) * gap, y, 42, 42,
			cleared and ui.GOLD or (current and ui.PURPLE or V4(0.3, 0.34, 0.45, 0.9)))
		if current then ui.pulse(node, 1.16, 0.45) end
		ui.text(node, tostring(i), 0, 1, 20, cleared and ui.INK or ui.WHITE)
	end
end

function M.build(app, parent, R)
	local d = progress.data
	local land = app.orient == "landscape"
	local w = math.min(R.w, land and 1100 or 720)
	local cx = R.cx
	local top = R.y1 - 12
	local active = progress.survival_active()
	local step = active and progress.survival_step() or 1
	local total = config.SURVIVAL.battles

	-- Hero banner: gauntlet identity + run progress
	local hh = land and 224 or 286
	local card = ui.slice(parent, "panel_stone", cx, top - hh / 2, w, hh, ui.WHITE, 24)
	local arena = ui.box(card, "arena_bg_void", 0, 18, w - 16, hh - 44, V4(0.72, 0.6, 1, 0.7))
	gui.set_alpha(arena, 0.55)
	ui.box(card, "vignette", 0, 18, w - 16, hh - 44, V4(1, 1, 1, 0.8))
	local rays = ui.glow(ui.box(card, "rays", 0, 54, 300, 300, V4(0.8, 0.5, 1, 0.32)))
	ui.spin(rays, 11)
	local fl = ui.icon(card, "icon_fire", 0, 58, 92)
	ui.pulse(fl, 1.12, 0.45)
	ui.label(card, i18n.t("SURVIVAL_TITLE"), 0, 4, 32, ui.GOLD, w - 80)
	ui.label(card, i18n.t("SURVIVAL_SUB"), 0, -32, 17, ui.BONE, w - 100, { lines = 2 })
	step_pips(card, 0, -78, step, total)
	local mx = progress.hero_hp()
	local hp = active and math.max(1, d.survival.hp or mx) or mx
	local bar = ui.bar(card, 0, -118, w - 120, 28, hp / math.max(1, mx), ui.GREEN, { text = hp .. " / " .. mx, text_size = 17 })
	ui.box(bar.bg, "icon_heart", -(w - 120) / 2 - 6, 0, 34, 34)
	local best = i18n.t("SURVIVAL_BEST", { n = (d.survival and d.survival.best) or 0 })

	-- Primary CTA
	local btn_y = top - hh - 62
	if active then
		ui.label(parent, i18n.t("SURVIVAL_RUN_FMT", { a = step, b = total }), cx, btn_y + 58, 18, ui.DIM, w - 100)
	end
	ui.btn(parent, "btn_gold", cx, btn_y, w - 140, 86, i18n.t(active and "SURVIVAL_CONTINUE" or "SURVIVAL_START"), 28, function()
		app.start_survival()
	end, { icon = "icon_fire", icon_size = 46, pulse = true })

	-- Rules + rewards
	local ry = btn_y - 78
	ui.label(parent, i18n.t("SURVIVAL_RULES"), cx, ry, 17, ui.DIM, w - 80, { lines = 2 })
	local reward_y = ry - 62
	widgets.section(parent, i18n.t("SURVIVAL_REWARD"), cx, reward_y, w, "chest_royal")
	widgets.reward_row(parent, {
		gold = config.SURVIVAL.gold,
		diamonds = config.SURVIVAL.diamonds,
		chest = config.SURVIVAL.chest,
	}, cx, reward_y - 56, 38)
	ui.label(parent, best, cx, reward_y - 104, 16, ui.PRESTIGE, w - 80)

	-- Run relics: owned ones light up
	local rel_y = reward_y - 148
	widgets.section(parent, i18n.t("SURVIVAL_RELICS"), cx, rel_y, w, "icon_star")
	local owned = progress.survival_relic_ids()
	local n = #config.RELICS
	local tw = math.min(92, (w - 40) / n)
	local x0 = cx - (n - 1) * (tw + 6) / 2
	for i, r in ipairs(config.RELICS) do
		local has = progress.survival_has_relic(r.id)
		local x = x0 + (i - 1) * (tw + 6)
		local box = ui.slice(parent, has and "card_epic" or "panel_dark", x, rel_y - 66, tw, tw + 8, ui.WHITE, 14)
		ui.icon(box, r.sprite, 0, 8, tw * 0.55, has and ui.WHITE or V4(0.4, 0.42, 0.5, 0.9))
		if has then
			ui.box(box, "icon_check", tw / 2 - 10, tw / 2 - 2, 20, 20)
		else
			ui.box(box, "icon_lock", tw / 2 - 12, tw / 2 - 4, 20, 20)
		end
	end
	ui.label(parent, i18n.t("SURVIVAL_RELIC_HINT", { n = #owned }), cx, rel_y - 112, 15, ui.DIM, w - 60)
end

return M
