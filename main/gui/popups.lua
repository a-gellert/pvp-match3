-- Modal popups (Druid popup layer: blocker + back handler): win / lose (Poki compliant), chest opening
-- sequence, chest info, card details, PvP search, stage info, trophy road, daily calendar, rewards,
-- league up, level up, profile, settings / pause.
local ui = require "main.gui.ui"
local widgets = require "main.gui.widgets"
local config = require "main.modules.config"
local squads = require "main.modules.squads"
local campaign = require "main.modules.campaign"
local progress = require "main.modules.progress"
local quests = require "main.modules.quests"
local poki = require "main.modules.poki"
local i18n = require "main.modules.i18n"
local audio = require "main.modules.audio"

local M = {}
local V3 = vmath.vector3
local V4 = vmath.vector4

local B = {} -- builders by kind

-- ---------------------------------------------------------------- frame helpers
local function backdrop(app, alpha)
	local root = ui.pane(app.popup_layer, 0, 0)
	app.popup_root = root
	local bg = ui.box(root, "square", app.vw / 2, app.vh / 2, app.vw, app.vh, V4(0.02, 0.03, 0.06, alpha or 0.8))
	ui.fade_in(bg, 0.18)
	ui.druid:new_blocker(bg)
	ui.druid:new_back_handler(function() ui.defer(function() M.on_back(app) end) end)
	return root
end

local function panel_size(app, w, h)
	return math.min(w, app.vw - 24), math.min(h, app.vh - 40)
end

local function panel(root, app, w, h, title, sprite)
	w, h = panel_size(app, w, h)
	local holder = ui.pane(root, app.vw / 2, app.vh / 2)
	local p = ui.slice(holder, sprite or "panel_stone", 0, 0, w, h, ui.WHITE, 24)
	ui.pop(holder, 0.8, 1, 0.26)
	if title then
		local rib = ui.slice(p, "btn_crimson", 0, h / 2 - 2, math.min(w - 60, 420), 62, ui.WHITE, 18)
		ui.label(rib, title, 0, 4, 30, ui.WHITE, math.min(w - 60, 420) - 36)
	end
	return p, w, h
end

local function close_btn(app, p, w, h, fn)
	ui.btn(p, "btn_round", w / 2 - 20, h / 2 - 20, 56, 56, "", 16, fn or function() app.close_popup() end, { icon = "icon_close", icon_size = 26 })
end

local function hub_collect(app, kind, x, y, n)
	local hub = package.loaded["main.gui.hub_view"]
	if app.screen == "hub" and hub and hub.collect_fx then hub.collect_fx(kind, x, y, n) end
end

-- Open a chest result popup or a plain reward popup depending on what was granted.
local function show_reward(app, reward, chest_res, title)
	if chest_res then
		app.open_popup("chest", chest_res)
	else
		app.open_popup("reward", { reward = reward, title = title })
	end
end

-- ---------------------------------------------------------------- win / lose
B.win = function(app, root, data)
	local s = app.session
	local p, w, h = panel(root, app, 600, 760, i18n.t("VICTORY"))
	local rays = ui.glow(ui.box(p, "rays", 0, h / 2 - 150, 520, 520, V4(1, 0.85, 0.45, 0.35)))
	ui.spin(rays, 12)
	ui.confetti(app.popup_root, app.vw / 2, app.vh + 40, app.vw, 50)
	audio.play("win")
	local y = h / 2 - 120

	if data.stars then
		for k = 1, 3 do
			local sx = (k - 2) * 120
			local sy = y - (k == 2 and 20 or 0)
			ui.box(p, "icon_star_empty", sx, sy, 100, 100)
			if k <= data.stars then
				ui.after(0.35 + k * 0.32, function()
					local star = ui.box(p, "icon_star", sx, sy, 100, 100)
					ui.pop(star, 2.2, 1, 0.3)
					ui.burst(p, sx, sy, 10, ui.GOLD, 90, 24)
					audio.play("star", 0.9, 0.9 + k * 0.12)
				end)
			end
		end
		y = y - 130
	else
		local face = ui.box(p, "face_hero", 0, y - 20, 140, 140)
		ui.bob(face, 6, 0.8)
		y = y - 130
	end

	-- Rewards row
	local gold_lbl = ui.text(p, "+0", -80, y, 34, ui.GOLD)
	ui.box(p, "icon_gold", -160, y, 54, 54)
	ui.count_up(gold_lbl, 0, data.gold or 0, 0.8, function(v) return "+" .. v end)
	ui.box(p, "icon_prestige", 80, y, 54, 54)
	local dp = data.prestige_delta or 0
	ui.text(p, (dp >= 0 and "+" or "") .. dp, 150, y, 34, ui.PRESTIGE)
	y = y - 66
	if (data.streak_bonus or 0) > 0 then
		ui.box(p, "icon_fire", -140, y, 40, 40)
		ui.label(p, i18n.t("STREAK_BONUS", { n = data.streak, g = data.streak_bonus }), 20, y, 20, ui.GOLD, w - 200)
		y = y - 46
	end
	if data.chest_rarity then
		local cb = ui.slice(p, "panel_dark", 0, y - 34, w - 80, 96, ui.WHITE, 16)
		local ci = ui.icon(cb, config.CHESTS[data.chest_rarity].sprite, -(w - 80) / 2 + 60, 0, 80)
		ui.bob(ci, 5, 0.6)
		ui.label(cb, data.chest_slot and i18n.t("CHEST_GOT", { name = i18n.t("CHEST_" .. data.chest_rarity) }) or i18n.t("CHEST_FULL"),
			30, 0, 20, data.chest_slot and ui.BONE or ui.RED, w - 240, { lines = 2 })
		y = y - 110
	end
	if data.stats then
		local st = data.stats
		ui.label(p, i18n.t("STATS_LINE", { d = st.damage or 0, c = st.max_combo or 0, s = st.skills or 0 }), 0, y - 4, 18, ui.DIM, w - 60)
		y = y - 40
	end
	if not data.followups_queued then
		data.followups_queued = true
		if data.league_up then app.queue_popup("league") end
		if data.first_clear and data.stage_id and campaign.get_stage(data.stage_id).boss then
			app.queue_popup("reward", { reward = { diamonds = 10 }, title = i18n.t("BOSS_BONUS") })
		end
	end

	-- Buttons (Poki: plain buttons at least as prominent as the rewarded one, never green)
	local by = -h / 2 + 150
	local can_next = s and s.mode == "campaign" and (progress.data.max_stage_unlocked or 1) > (data.stage_id or 0)
		and (data.stage_id or 0) < campaign.COUNT
	if can_next and progress.data.onboarding_done then
		ui.btn(p, "btn_gold", 0, by, w - 120, 76, i18n.t("NEXT_STAGE"), 28, function() app.next_stage() end, { icon = "icon_play", icon_size = 40 })
	else
		ui.btn(p, "btn_gold", 0, by, w - 120, 76, i18n.t("CONTINUE"), 28, function()
			app.close_popup(true)
			app.show_hub(progress.data.onboarding_step == 1 and "cards" or "home")
		end)
	end
	local half = (w - 140) / 2
	ui.btn(p, "btn_dark", -half / 2 - 10, by - 88, half, 66, i18n.t("TO_HUB"), 22, function()
		app.close_popup(true)
		app.show_hub(progress.data.onboarding_step == 1 and "cards" or "home")
	end)
	if not data.doubled and (data.gold or 0) > 0 and progress.data.onboarding_done then
		ui.btn(p, "btn_purple", half / 2 + 10, by - 88, half, 66, i18n.t("DOUBLE_GOLD"), 22, function()
			app.reward_double_gold(data)
		end, { icon = "icon_ad", icon_size = 30 })
	end
end

B.lose = function(app, root, data)
	local p, w, h = panel(root, app, 580, 640, i18n.t("DEFEAT"))
	audio.play("lose")
	local face = ui.box(p, "face_hero", 0, h / 2 - 150, 130, 130, V4(0.7, 0.6, 0.65, 1))
	ui.shake(face, 12)
	local y = h / 2 - 250
	ui.box(p, "icon_gold", -150, y, 48, 48)
	ui.text(p, "+" .. (data.gold or 0), -90, y, 30, ui.GOLD)
	ui.box(p, "icon_prestige", 60, y, 48, 48)
	ui.text(p, tostring(data.prestige_delta or 0), 130, y, 30, ui.RED)
	local tips = { "TIP_1", "TIP_2", "TIP_3", "TIP_4", "TIP_5" }
	ui.label(p, i18n.t(tips[math.random(1, #tips)]), 0, y - 70, 19, ui.DIM, w - 70, { lines = 2 })
	local by = -h / 2 + 170
	local half = (w - 140) / 2
	ui.btn(p, "btn_gold", -half / 2 - 10, by, half, 76, i18n.t("RETRY"), 26, function() app.retry_battle() end)
	ui.btn(p, "btn_dark", half / 2 + 10, by, half, 76, i18n.t("TO_HUB"), 24, function() app.leave_battle("cards") end)
	if data.can_revive then
		-- Poki: the rewarded button is never bigger than the plain alternatives above it
		ui.btn(p, "btn_purple", 0, by - 90, half, 66, i18n.t("SECOND_CHANCE"), 22, function()
			app.reward_second_chance()
		end, { icon = "icon_ad", icon_size = 32 })
	end
end

-- ---------------------------------------------------------------- chests
B.chest = function(app, root, data)
	local vw, vh = app.vw, app.vh
	local cx, cy = vw / 2, vh / 2 + math.min(160, vh * 0.15)
	local rays = ui.glow(ui.box(root, "rays", cx, cy, 620, 620, V4(1, 0.85, 0.45, 0)))
	ui.spin(rays, 10)
	local def = config.CHESTS[data.rarity or "wood"]
	local chest = ui.icon(root, def.sprite, cx, cy, 220)
	ui.pop(chest, 0.2, 1, 0.35)
	local title = ui.label(root, i18n.t("CHEST_" .. (data.rarity or "wood")), cx, cy + 160, 34, ui.GOLD, vw - 60)
	local shakes = { 6, 10, 16 }
	for k, amp in ipairs(shakes) do
		ui.after(0.35 + (k - 1) * 0.28, function()
			audio.play("flip", 0.8, 0.8 + k * 0.1)
			ui.shake(chest, (k % 2 == 0) and amp or -amp)
			ui.burst(root, cx, cy, 4 + k * 2, ui.GOLD, 120, 20)
		end)
	end
	local t_open = 0.35 + #shakes * 0.28 + 0.1
	ui.after(t_open, function()
		audio.play("chest")
		ui.flash(root, vw, vh, V4(1, 0.9, 0.6, 0.6), 0.4)
		ui.ring(root, cx, cy, 500, ui.GOLD, 0.5)
		ui.burst(root, cx, cy, 24, ui.GOLD, 260, 30)
		ui.confetti(root, cx, vh + 40, vw, 40)
		gui.animate(rays, "color.w", 0.4, gui.EASING_OUTQUAD, 0.4)
		gui.animate(rays, "position.y", vh / 2, gui.EASING_OUTQUAD, 0.4)
		gui.animate(chest, "scale", V3(1.5, 1.5, 1), gui.EASING_OUTQUAD, 0.25)
		gui.animate(chest, "color.w", 0, gui.EASING_INQUAD, 0.3, 0.05)
		gui.animate(title, "color.w", 0, gui.EASING_INQUAD, 0.2)
	end)

	-- Gold + cards reveal (grid centred on screen, gold above, claim below)
	ui.after(t_open + 0.3, function()
		local drops = data.drops or {}
		local land = app.orient == "landscape"
		local cols = math.max(1, math.min(#drops, land and 6 or 4))
		local cw, ch = land and 170 or 150, land and 210 or 196
		local rows = math.ceil(#drops / cols)
		local grid_h = rows * ch + (rows - 1) * 14
		local top = vh / 2 + grid_h / 2 - ch / 2 + 20
		local gy = top + ch / 2 + 64
		ui.box(root, "icon_gold", cx - 70, gy, 64, 64)
		local gl = ui.text(root, "+0", cx + 30, gy, 44, ui.GOLD)
		ui.count_up(gl, 0, data.gold or 0, 0.6, function(v) return "+" .. v end)
		audio.play("coin")
		for i, dr in ipairs(drops) do
			local r = math.floor((i - 1) / cols)
			local c = (i - 1) % cols
			local in_row = math.min(cols, #drops - r * cols)
			local x = cx + (c - (in_row - 1) / 2) * (cw + 14)
			local y = top - r * (ch + 14)
			ui.after(0.25 + (i - 1) * 0.22, function()
				local sq = squads.get(dr.id)
				local holder = ui.pane(root, x, y)
				local glow = ui.glow(ui.box(holder, "glow", 0, 0, cw * 1.6, ch * 1.4, ui.RARITY_COLOR[sq.rarity]))
				gui.set_alpha(glow, sq.rarity == "common" and 0.15 or 0.45)
				local card = ui.slice(holder, ui.RARITY_FRAME[sq.rarity], 0, 0, cw, ch, ui.WHITE, 18)
				ui.icon(card, sq.sprite, 0, 18, math.min(cw - 30, 110))
				ui.label(card, i18n.t("SQ_" .. sq.id), 0, -ch / 2 + 46, 15, ui.BONE, cw - 12)
				ui.text(card, "+" .. dr.count, 0, -ch / 2 + 20, 24, ui.GREEN)
				if dr.unlocked_now then
					local tag = ui.slice(card, "btn_crimson", 0, ch / 2 - 4, 90, 30, ui.WHITE, 10)
					ui.text(tag, i18n.t("NEW"), 0, 2, 16, ui.WHITE)
					ui.pulse(tag, 1.12, 0.35)
				end
				gui.set_scale(holder, V3(0.05, 1.1, 1))
				gui.animate(holder, "scale", V3(1, 1, 1), gui.EASING_OUTBACK, 0.3)
				audio.play("flip", 0.8, 1 + math.min(4, (sq.rarity == "legendary" and 4 or (sq.rarity == "epic" and 2 or 0))) * 0.1)
				if sq.rarity == "epic" or sq.rarity == "legendary" then
					ui.burst(root, x, y, 14, ui.RARITY_COLOR[sq.rarity], 140, 26)
					audio.play("star")
				end
			end)
		end
		local t_end = 0.25 + #drops * 0.22 + 0.3
		ui.after(t_end, function()
			local by = math.max(64, top - (rows - 1) * (ch + 14) - ch / 2 - 64)
			ui.btn(root, "btn_gold", cx, by, 320, 82, i18n.t("CLAIM"), 30, function()
				app.close_popup()
				app.rebuild()
				hub_collect(app, "gold", cx, gy, 8)
			end, { pulse = true })
		end)
	end)
end

B.chest_info = function(app, root, data)
	local i = data.slot
	local slot = progress.data.chests[i]
	if not slot then app.close_popup(); return end
	local def = config.CHESTS[slot.rarity]
	local p, w, h = panel(root, app, 560, 600, i18n.t("CHEST_" .. slot.rarity))
	close_btn(app, p, w, h)
	local ci = ui.icon(p, def.sprite, 0, h / 2 - 170, 170)
	ui.bob(ci, 6, 0.8)
	ui.label(p, i18n.t("CHEST_CONTENTS", { a = def.cards_min, b = def.cards_max, g1 = def.gold_min, g2 = def.gold_max }), 0, h / 2 - 290, 20, ui.BONE, w - 60, { lines = 2 })
	local rem = progress.chest_remaining(i)
	local by = -h / 2 + 200
	if not slot.unlocking then
		if not progress.any_chest_unlocking() then
			ui.btn(p, "btn_gold", 0, by, w - 120, 76, i18n.t("START_UNLOCK", { t = i18n.fmt_time(def.duration) }), 24, function()
				progress.start_chest(i)
				audio.play("upgrade")
				app.close_popup()
				app.rebuild()
			end)
		else
			ui.label(p, i18n.t("ONE_AT_A_TIME"), 0, by, 19, ui.DIM, w - 60, { lines = 2 })
		end
	else
		local tl = ui.text(p, i18n.fmt_time(rem), 0, by + 4, 34, ui.GOLD)
		ui.after(1, function() gui.set_text(tl, i18n.fmt_time(progress.chest_remaining(i))) end)
		ui.btn(p, "btn_purple", 0, by - 90, w - 120, 70, i18n.t("SPEEDUP_AD"), 22, function()
			poki.rewarded("small", function(ok)
				if ok and progress.speedup_chest(i) then
					audio.play("upgrade")
					app.close_popup()
					app.rebuild()
				end
			end)
		end, { icon = "icon_ad", icon_size = 30 })
	end
	local cost = progress.chest_rush_cost(i)
	ui.btn(p, "btn_dark", 0, -h / 2 + 52, w - 120, 70, i18n.t("OPEN_NOW", { d = cost }), 22, function()
		local res = progress.open_chest(i, true)
		if res then app.open_popup("chest", res)
		else
			audio.play("blocked")
			ui.float_text(p, i18n.t("NEED_DIAMONDS"), 0, -h / 2 + 100, 20, ui.RED, 30)
		end
	end, { icon = "icon_diamond", icon_size = 32 })
end

-- ---------------------------------------------------------------- card details (Clash Royale style)
local STYLE_ICON = { melee = "icon_pvp", ranged = "proj_arrow", magic = "proj_spell" }

-- 2-column grid of stat boxes: { icon, label, value, next_value } from y downward; returns height.
local function stat_grid(p, stats, cx, y, w)
	local cw = (w - 12) / 2
	local chh = 66
	for i, sd in ipairs(stats) do
		local col = (i - 1) % 2
		local row = math.floor((i - 1) / 2)
		local sx = cx + (col - 0.5) * (cw + 12)
		local sy = y - chh / 2 - row * (chh + 10)
		local box = ui.slice(p, "panel_dark", sx, sy, cw, chh, ui.WHITE, 14)
		ui.icon(box, sd[1], -cw / 2 + 30, 0, 38)
		ui.label(box, sd[2], -cw / 2 + 58, 15, 16, ui.DIM, cw - 70, { pivot = gui.PIVOT_W })
		ui.label(box, tostring(sd[3]), -cw / 2 + 58, -12, 23, ui.BONE, cw - 130, { pivot = gui.PIVOT_W })
		if sd[4] and sd[4] ~= sd[3] then
			ui.label(box, "+" .. (sd[4] - sd[3]), cw / 2 - 12, -12, 21, ui.GREEN, 72, { pivot = gui.PIVOT_E })
		end
	end
	local rows = math.ceil(#stats / 2)
	return rows * (chh + 10) - 10
end

B.card = function(app, root, data)
	local sq = squads.get(data.id)
	local d = progress.data
	local c = d.cards[sq.id]
	progress.mark_seen(sq.id)
	local land = app.orient == "landscape"
	-- Portrait panel height follows the content (trait line / skill box are optional)
	local ph = 96 + 250 + 22 + 142 + 12 + ((sq.trait and sq.trait ~= "none") and 34 or 0) + ((sq.skill and sq.runes) and 98 or 0) + 210
	local p, w, h = panel(root, app, land and 980 or 620, land and 660 or ph, i18n.t("SQ_" .. sq.id))
	close_btn(app, p, w, h)
	local rar = ui.RARITY_COLOR[sq.rarity] or ui.BONE
	local lvl = c.level
	local req = squads.upgrade_req(sq.id, lvl)
	local gcost = squads.upgrade_gold(sq.id, lvl)
	local has_next = c.unlocked and req ~= nil

	-- Column geometry: portrait = one column; landscape = card on the left, details on the right
	local card_w, card_h = land and 240 or 200, land and 300 or 250
	local card_x, card_y, col_cx, col_w, y
	if land then
		card_x, card_y = -w / 2 + 40 + card_w / 2, 30
		col_w = w - card_w - 120
		col_cx = w / 2 - 40 - col_w / 2
		y = h / 2 - 70
	else
		card_x, card_y = 0, h / 2 - 96 - card_h / 2
		col_w = w - 60
		col_cx = 0
		y = card_y - card_h / 2 - 22
	end
	local rays = ui.glow(ui.box(p, "rays", card_x, card_y, card_w * 1.9, card_w * 1.9, V4(rar.x, rar.y, rar.z, 0.22)))
	ui.spin(rays, 14)
	local card = ui.slice(p, ui.RARITY_FRAME[sq.rarity], card_x, card_y, card_w, card_h, ui.WHITE, 20)
	local art = ui.icon(card, sq.sprite, 0, 8, card_w * 0.82, c.unlocked and ui.WHITE or V4(0.08, 0.09, 0.14, 0.92))
	ui.bob(art, 5, 1)
	ui.box(card, ui.GEM_SPRITE[sq.color], -card_w / 2 + 24, card_h / 2 - 24, 34, 34)
	local tag = i18n.t("RARITY_" .. sq.rarity) .. (c.unlocked and ("  |  " .. i18n.t("LVL_FMT", { n = lvl })) or "")
	if land then
		ui.label(p, tag, card_x, card_y - card_h / 2 - 26, 22, rar, card_w + 40)
		ui.label(p, i18n.t("SLOT_" .. sq.color), card_x, card_y - card_h / 2 - 58, 17, ui.DIM, card_w + 40)
	else
		ui.label(p, tag, 0, h / 2 - 76, 22, rar, w - 120)
	end

	-- Stats (green +N = what the next level gives)
	-- Every card upgrade also raises the commander level (+HP for the whole team)
	local cmd_next = config.commander_hp((d.commander_lvl or 1) + 1, d.max_moves, d.prestige)
	local stats = {
		{ "icon_sword", i18n.t("STAT_DMG"), squads.power(sq.id, lvl), has_next and squads.power(sq.id, lvl + 1) or nil },
		{ "icon_star", i18n.t("STAT_SKILL"), squads.skill_power(sq.id, lvl), has_next and squads.skill_power(sq.id, lvl + 1) or nil },
		{ STYLE_ICON[sq.style] or "icon_sword", i18n.t("STAT_TYPE"), i18n.t("STYLE_" .. sq.style) },
		{ "icon_heart", i18n.t("STAT_CMD_HP"), progress.hero_hp(), has_next and cmd_next or nil },
	}
	y = y - stat_grid(p, stats, col_cx, y, col_w) - 12
	if sq.trait and sq.trait ~= "none" then
		ui.label(p, i18n.t("TRAIT_" .. sq.trait), col_cx, y - 12, 18, ui.GREEN, col_w)
		y = y - 34
	end
	if sq.skill and sq.runes then
		local sk = ui.slice(p, "panel_dark", col_cx, y - 44, col_w, 86, ui.WHITE, 16)
		local rx = -col_w / 2 + 34
		for k = 1, 2 do
			ui.box(sk, "rune_bg", rx + (k - 1) * 40, 0, 38, 38)
			ui.box(sk, ui.GEM_SPRITE[sq.runes[k]], rx + (k - 1) * 40, 0, 28, 28)
		end
		ui.label(sk, i18n.t("SK_" .. sq.skill.id), -col_w / 2 + 92, 14, 19, ui.DIAMOND, col_w - 110, { pivot = gui.PIVOT_W })
		ui.label(sk, i18n.t("RUNE_HINT"), -col_w / 2 + 92, -16, 15, ui.DIM, col_w - 110, { pivot = gui.PIVOT_W })
		y = y - 98
	end

	-- Card count bar + buttons
	local by = -h / 2 + 60
	local half = (col_w - 16) / 2
	if c.unlocked then
		if req then
			local can = progress.can_upgrade_card(sq.id)
			local bar = ui.bar(p, col_cx, by + 84, col_w - 40, 32, math.min(1, c.count / req), can and ui.GREEN or ui.BLUE,
				{ text = c.count .. " / " .. req, text_size = 20 })
			ui.icon(bar.bg, "icon_cards", -(col_w - 40) / 2 - 4, 0, 40)
		end
		local is_eq = d.slots[sq.color] == sq.id
		ui.btn(p, is_eq and "btn_dark" or "btn_purple", col_cx - half / 2 - 8, by, half, 78, i18n.t(is_eq and "EQUIPPED" or "EQUIP"), 24, function()
			if not is_eq and progress.assign_slot(sq.id) then
				audio.play("shield")
				app.close_popup()
				app.rebuild()
			end
		end, { icon = is_eq and "icon_check" or ui.GEM_SPRITE[sq.color], icon_size = 34 })
		if req and gcost then
			local can = progress.can_upgrade_card(sq.id)
			local nb = ui.btn(p, can and "btn_gold" or "btn_dark", col_cx + half / 2 + 8, by, half, 78, i18n.t("UPGRADE", { g = gcost }), 22, function()
				if progress.upgrade_card(sq.id) then
					audio.play("levelup")
					app.refresh_then_popup("levelup", { kind = "card", id = sq.id })
				else
					audio.play("blocked")
					ui.float_text(p, i18n.t(c.count < req and "NEED_CARDS" or "NEED_GOLD"), col_cx + half / 2 + 8, by + 60, 20, ui.RED, 30)
				end
			end, { icon = "icon_gold", icon_size = 32 })
			if can then
				ui.pulse(nb, 1.05, 0.45)
				if d.onboarding_step == 1 then
					local hand = ui.box(p, "icon_hand", col_cx + half / 2 + 40, by - 30, 64, 64)
					ui.pulse(hand, 1.2, 0.4)
				end
			end
		else
			ui.label(p, i18n.t("MAX"), col_cx + half / 2 + 8, by, 28, ui.GOLD, half)
		end
	else
		ui.label(p, i18n.t("FIND_IN_CHESTS"), col_cx, by + 76, 18, ui.DIM, col_w)
		ui.btn(p, "btn_purple", col_cx, by, col_w - 60, 78, i18n.t("BUY_CARD", { d = squads.unlock_diamonds(sq.id) }), 24, function()
			if progress.buy_locked_card(sq.id) then
				audio.play("levelup")
				app.close_popup()
				app.rebuild()
			else
				audio.play("blocked")
				ui.float_text(p, i18n.t("NEED_DIAMONDS"), col_cx, by + 60, 20, ui.RED, 30)
			end
		end, { icon = "icon_diamond", icon_size = 34 })
	end
end

-- ---------------------------------------------------------------- PvP search
B.pvp_search = function(app, root, data)
	local p, w, h = panel(root, app, 560, 520, i18n.t("PVP"))
	local opp = data.opp
	local rays = ui.glow(ui.box(p, "rays", 0, 40, 380, 380, V4(0.85, 0.4, 0.5, 0.3)))
	ui.spin(rays, 4)
	local face = ui.box(p, "face_hero", 0, 50, 150, 150, V4(0.3, 0.3, 0.4, 1))
	local name = ui.text(p, i18n.t("PVP_SEARCH"), 0, -80, 26, ui.BONE)
	local NAMES = { "...", "ShadowFang", "Valkor", "Morwen", "IronCrow", "Zarek", "Hexa" }
	for k = 1, 6 do
		ui.after(k * 0.14, function()
			gui.set_text(name, NAMES[(k % #NAMES) + 1])
			audio.play("tap", 0.5, 1 + k * 0.05)
		end)
	end
	ui.after(1.0, function()
		gui.play_flipbook(face, opp.face)
		gui.set_color(face, ui.WHITE)
		ui.pop(face, 1.4, 1, 0.3)
		ui.burst(p, 0, 50, 14, ui.RED, 120, 24)
		audio.play("hit")
		gui.set_text(name, opp.name)
		ui.fit(name, w - 60, 30)
		ui.text(p, i18n.t("PVP_FOUND"), 0, h / 2 - 100, 22, ui.GOLD)
		ui.box(p, "icon_prestige", -70, -122, 36, 36)
		ui.text(p, tostring(opp.prestige), -20, -122, 22, ui.PRESTIGE)
		ui.box(p, "icon_heart", 70, -122, 32, 32)
		ui.text(p, tostring(opp.hp), 120, -122, 22, ui.BONE)
		ui.btn(p, "btn_crimson", 0, -h / 2 + 64, w - 160, 76, i18n.t("FIGHT"), 30, function()
			app.close_popup(true)
			app.launch_pvp(opp)
		end, { icon = "icon_pvp", icon_size = 46, pulse = true })
	end)
end

-- ---------------------------------------------------------------- stage info
B.stage = function(app, root, data)
	local stg = campaign.get_stage(data.id)
	local biome = campaign.BIOMES[stg.zone]
	local p, w, h = panel(root, app, 600, 800, i18n.t("STAGE_FMT", { n = stg.id }))
	close_btn(app, p, w, h)
	local top = h / 2 - 70
	ui.label(p, i18n.t(biome.name_key), 0, top - 10, 20, ui.hex(biome.tint), w - 80)
	local arena = ui.box(p, "arena_bg", 0, top - 140, w - 60, 200, ui.hex(biome.tint))
	gui.set_alpha(arena, 0.7)
	ui.box(p, "vignette", 0, top - 140, w - 60, 200, V4(1, 1, 1, 0.8))
	local face = ui.box(p, stg.face, -w / 2 + 110, top - 140, 140, 140)
	ui.bob(face, 4, 0.9)
	if stg.boss then
		local tag = ui.slice(p, "btn_crimson", -w / 2 + 110, top - 52, 100, 32, ui.WHITE, 12)
		ui.text(tag, i18n.t("BOSS"), 0, 2, 17, ui.WHITE)
	end
	for i, col in ipairs(config.ATTACK_COLORS) do
		local sq = squads.get(stg.squads[col].id)
		local x = -10 + (i - 1) * 110
		local a = ui.icon(p, sq.sprite, x, top - 140, 96)
		gui.set_scale(a, V3(-1, 1, 1))
	end
	local y = top - 270
	ui.label(p, i18n.t(stg.name_key), 0, y, 28, ui.BONE, w - 60)
	y = y - 46
	ui.box(p, "icon_heart", -150, y, 34, 34)
	ui.text(p, tostring(stg.hp), -96, y, 24, ui.BONE)
	ui.box(p, "icon_move_orb", 40, y, 30, 30)
	ui.text(p, i18n.t("MOVES_FMT", { n = stg.moves }), 120, y, 22, ui.BONE)
	y = y - 46
	local lvl = campaign.expected_build(stg.id)
	ui.label(p, i18n.t("RECOMMENDED", { n = lvl }), 0, y, 18, ui.DIM, w - 60)
	y = y - 56
	-- Rewards
	local rb = ui.slice(p, "panel_dark", 0, y, w - 60, 76, ui.WHITE, 16)
	widgets.reward_row(rb, { gold = stg.gold, chest = stg.chest }, -40, 0, 40)
	if stg.boss and stg.id >= (progress.data.max_stage_unlocked or 1) then
		ui.box(rb, "icon_diamond", (w - 60) / 2 - 90, 0, 36, 36)
		ui.text(rb, "+10", (w - 60) / 2 - 44, 0, 22, ui.DIAMOND)
	end
	y = y - 80
	local stars = progress.stage_stars(stg.id)
	for k = 1, 3 do
		ui.box(p, k <= stars and "icon_star" or "icon_star_empty", (k - 2) * 64, y, 56, 56)
	end
	ui.label(p, i18n.t("STARS_HINT"), 0, y - 44, 15, ui.DIM, w - 60)
	ui.btn(p, stg.boss and "btn_crimson" or "btn_gold", 0, -h / 2 + 60, w - 140, 84, i18n.t("FIGHT"), 32, function()
		app.close_popup(true)
		app.start_campaign(stg.id)
	end, { icon = "icon_pvp", icon_size = 48, pulse = true })
end

-- ---------------------------------------------------------------- trophy road
B.road = function(app, root)
	local d = progress.data
	local p, w, h = panel(root, app, 640, app.vh - 80, i18n.t("ROAD_TITLE"))
	close_btn(app, p, w, h)
	local _, lg = progress.league()
	ui.label(p, i18n.t("ROAD_SUB", { n = d.max_prestige or 0 }), 0, h / 2 - 80, 20, ui.PRESTIGE, w - 80)
	local view_h = h - 140
	local sc = ui.scroll(p, 0, -50, w - 40, view_h)
	local C = sc.content
	local row_h = 104
	local claimed = d.road_claimed or 0
	local focus_y = 0
	for i, m in ipairs(config.TROPHY_ROAD) do
		local y = -row_h / 2 - 10 - (i - 1) * (row_h + 10)
		local reached = (d.max_prestige or 0) >= m.at
		local is_claimed = i <= claimed
		local claimable = i == claimed + 1 and reached
		if i == claimed + 1 then focus_y = y end
		local box = ui.slice(C, claimable and "card_legendary" or (reached and "panel_stone" or "panel_dark"), 0, y, w - 60, row_h,
			is_claimed and V4(0.6, 0.62, 0.7, 1) or ui.WHITE, 18)
		ui.box(box, "league_badge", -(w - 60) / 2 + 50, 0, 64, 64, ui.hex(config.LEAGUES[config.league_index(m.at)].color))
		ui.text(box, tostring(m.at), -(w - 60) / 2 + 50, 0, 18, ui.INK, ui.WHITE)
		widgets.reward_row(box, m.reward, -20, 0, 34)
		local bx = (w - 60) / 2 - 80
		if is_claimed then
			ui.box(box, "icon_check", bx, 0, 46, 46)
		elseif claimable then
			ui.btn(box, "btn_gold", bx, 0, 130, 62, i18n.t("CLAIM"), 20, function()
				local reward, res = progress.claim_road()
				if reward then
					audio.play("quest")
					show_reward(app, reward, res, i18n.t("ROAD_TITLE"))
				end
			end, { pulse = true })
		elseif reached then
			-- Reached, claimable after the previous ones (claims go in order)
			local g = ui.box(box, "icon_gift", bx, 0, 46, 46)
			ui.pulse(g, 1.12, 0.5)
		else
			ui.box(box, "icon_lock", bx, 0, 36, 36)
		end
	end
	sc.set_height(#config.TROPHY_ROAD * (row_h + 10) + 20)
	sc.scroll:scroll_to(V3(0, focus_y, 0), true)
	local _ = lg
end

-- ---------------------------------------------------------------- daily calendar
B.daily = function(app, root)
	local d = progress.data
	local pending = quests.login_pending(d)
	local p, w, h = panel(root, app, 680, 640, i18n.t("DAILY_TITLE"))
	close_btn(app, p, w, h)
	local idx = quests.login_index(d)
	local cycle_done = ((d.login and d.login.count) or 0) % #config.DAILY_REWARDS
	local tw = (w - 60 - 3 * 12) / 4
	for i = 1, 7 do
		local row = i <= 4 and 0 or 1
		local col = i <= 4 and (i - 1) or (i - 5)
		local in_row = row == 0 and 4 or 3
		local x = (col - (in_row - 1) / 2) * (tw + 12)
		local y = h / 2 - 170 - row * 170
		local today = pending and i == idx
		local claimed = i <= cycle_done
		local box = ui.slice(p, today and "card_legendary" or (i == 7 and "card_epic" or "panel_dark"), x, y, tw, 156, claimed and V4(0.55, 0.57, 0.65, 1) or ui.WHITE, 16)
		ui.label(box, i18n.t("DAY_FMT", { n = i }), 0, 58, 17, today and ui.GOLD or ui.DIM, tw - 10)
		widgets.reward_row(box, config.DAILY_REWARDS[i], 0, -4, 34)
		if claimed then ui.box(box, "icon_check", 0, -4, 54, 54) end
		if today then
			ui.pulse(box, 1.05, 0.45)
			local gl = ui.glow(ui.box(box, "glow", 0, 0, tw * 1.6, 220, V4(0.4, 0.9, 1, 0.3)))
			ui.pulse(gl, 1.1, 0.5)
		end
	end
	if pending then
		ui.btn(p, "btn_gold", 0, -h / 2 + 64, w - 160, 80, i18n.t("CLAIM"), 30, function()
			local reward, _, chest_res = progress.claim_login()
			if reward then
				audio.play("quest")
				show_reward(app, reward, chest_res, i18n.t("DAY_FMT", { n = idx }))
			end
		end, { pulse = true })
	else
		ui.label(p, i18n.t("COME_BACK", { t = i18n.fmt_time(quests.seconds_to_reset()) }), 0, -h / 2 + 64, 21, ui.DIM, w - 60)
	end
end

-- ---------------------------------------------------------------- generic reward / level up / league / profile
B.reward = function(app, root, data)
	local p, w, h = panel(root, app, 560, 460, data.title or i18n.t("REWARD"))
	local rays = ui.glow(ui.box(p, "rays", 0, 30, 420, 420, V4(1, 0.85, 0.45, 0.35)))
	ui.spin(rays, 10)
	widgets.reward_row(p, data.reward or {}, 0, 40, 70)
	ui.burst(p, 0, 40, 14, ui.GOLD, 160, 26)
	audio.play("coin")
	ui.btn(p, "btn_gold", 0, -h / 2 + 64, w - 180, 78, i18n.t("CLAIM"), 28, function()
		app.close_popup()
		app.rebuild()
		local r = data.reward or {}
		if r.gold then hub_collect(app, "gold", app.vw / 2, app.vh / 2, 8) end
		if r.diamonds then hub_collect(app, "diamond", app.vw / 2, app.vh / 2, 6) end
	end, { pulse = true })
end

B.levelup = function(app, root, data)
	local p, w, h = panel(root, app, 580, 620, i18n.t(data.kind == "moves" and "MOVES_UP" or "LEVEL_UP"))
	local rays = ui.glow(ui.box(p, "rays", 0, 80, 480, 480, V4(0.5, 1, 0.6, 0.35)))
	ui.spin(rays, 9)
	ui.confetti(app.popup_root, app.vw / 2, app.vh + 40, app.vw, 34)
	local d = progress.data
	if data.kind == "moves" then
		for i = 1, d.max_moves do
			local ox = (i - (d.max_moves + 1) / 2) * 56
			local o = ui.box(p, "icon_move_orb", ox, 110, 50, 50)
			ui.pop(o, 0.1, 1, 0.3, i * 0.06)
			if i == d.max_moves then ui.after(0.5, function() ui.burst(p, ox, 110, 12, ui.BLUE, 90, 24) end) end
		end
		ui.label(p, i18n.t("MOVES_FMT", { n = d.max_moves }), 0, 30, 30, ui.BONE, w - 60)
		local row = ui.slice(p, "panel_dark", 0, -40, w - 80, 60, ui.WHITE, 14)
		ui.icon(row, "icon_heart", -(w - 80) / 2 + 34, 0, 36)
		ui.label(row, i18n.t("CMD_HP", { n = progress.hero_hp() }), 20, 0, 22, ui.GREEN, w - 180)
	else
		local sq = squads.get(data.id)
		local c = d.cards[sq.id]
		local old = math.max(1, c.level - 1)
		local card = ui.slice(p, ui.RARITY_FRAME[sq.rarity], 0, 110, 170, 210, ui.WHITE, 18)
		ui.icon(card, sq.sprite, 0, 10, 140)
		ui.pop(card, 0.3, 1, 0.45)
		local rib = ui.slice(card, "panel_dark", 0, -105, 120, 36, ui.WHITE, 12)
		local lv = ui.text(rib, i18n.t("LVL_FMT", { n = old }), 0, 2, 22, ui.GOLD)
		ui.after(0.55, function()
			gui.set_text(lv, i18n.t("LVL_FMT", { n = c.level }))
			ui.pop(rib, 1.6, 1, 0.3)
			ui.burst(p, 0, 5, 16, ui.GOLD, 110, 26)
			audio.play("star", 0.9, 1.1)
		end)
		local rows = {
			{ "icon_sword", i18n.t("STAT_DMG"), squads.power(sq.id, old), squads.power(sq.id, c.level), ui.GOLD },
			{ "icon_heart", i18n.t("STAT_CMD_HP"), config.commander_hp(math.max(1, (d.commander_lvl or 1) - 1), d.max_moves, d.prestige), progress.hero_hp(), ui.GREEN },
		}
		for i, r in ipairs(rows) do
			local ry = -50 - (i - 1) * 66
			local rw = w - 80
			local row = ui.slice(p, "panel_dark", 0, ry, rw, 58, ui.WHITE, 14)
			ui.icon(row, r[1], -rw / 2 + 34, 0, 36)
			ui.label(row, r[2], -rw / 2 + 64, 0, 19, ui.DIM, 170, { pivot = gui.PIVOT_W })
			local val = ui.text(row, tostring(r[3]), rw / 2 - 60, 0, 26, ui.BONE)
			ui.count_up(val, r[3], r[4], 0.6)
			ui.after(0.7, function() gui.set_color(val, r[5]); ui.pop(val, 1.4, 1, 0.25) end)
			ui.text(row, "+" .. (r[4] - r[3]), rw / 2 - 140, 0, 20, ui.GREEN)
		end
	end
	ui.btn(p, "btn_gold", 0, -h / 2 + 62, w - 180, 76, i18n.t("CONTINUE"), 26, function()
		app.close_popup()
		if d.onboarding_done and d.onboarding_step == 2 and not d.tut_finished then
			d.tut_finished = true
			progress.save()
			app.set_tab("home")
		end
	end)
end

B.league = function(app, root)
	local _, lg = progress.league()
	local p, w, h = panel(root, app, 560, 520, i18n.t("LEAGUE_UP"))
	local rays = ui.glow(ui.box(p, "rays", 0, 40, 480, 480, ui.hex(lg.color, 0.4)))
	ui.spin(rays, 8)
	local b = ui.box(p, "league_badge", 0, 50, 200, 200, ui.hex(lg.color))
	ui.pop(b, 0.2, 1, 0.5)
	ui.burst(p, 0, 50, 20, ui.hex(lg.color), 200, 28)
	audio.play("levelup")
	ui.label(p, i18n.t("LEAGUE_" .. lg.id), 0, -100, 34, ui.hex(lg.color), w - 60)
	ui.btn(p, "btn_gold", 0, -h / 2 + 60, w - 200, 74, i18n.t("CONTINUE"), 26, function() app.close_popup() end)
end

B.profile = function(app, root)
	local d = progress.data
	local s = d.stats
	local p, w, h = panel(root, app, 560, 660, i18n.t("PROFILE"))
	close_btn(app, p, w, h)
	ui.box(p, "face_hero", 0, h / 2 - 140, 130, 130)
	ui.label(p, i18n.t("COMMANDER_LVL", { n = d.commander_lvl }), 0, h / 2 - 230, 26, ui.GOLD, w - 60)
	local rows = {
		{ "icon_heart", i18n.t("STAT_HP"), progress.hero_hp() },
		{ "icon_pvp", i18n.t("STAT_BATTLES"), s.battles or 0 },
		{ "icon_trophy", i18n.t("STAT_WINS"), (s.wins or 0) .. ((s.battles or 0) > 0 and ("  (" .. math.floor((s.wins or 0) / s.battles * 100) .. "%)") or "") },
		{ "icon_fire", i18n.t("STAT_STREAK"), d.best_streak or 0 },
		{ "icon_star", i18n.t("STAT_STARS"), progress.total_stars() .. " / " .. campaign.COUNT * 3 },
		{ "icon_prestige", i18n.t("STAT_PRESTIGE"), d.max_prestige or 0 },
		{ "chest_wood", i18n.t("STAT_CHESTS"), s.chests or 0 },
	}
	for i, r in ipairs(rows) do
		local y = h / 2 - 290 - (i - 1) * 52
		ui.icon(p, r[1], -w / 2 + 70, y, 36)
		ui.label(p, r[2], -w / 2 + 100, y, 20, ui.DIM, w * 0.5, { pivot = gui.PIVOT_W })
		ui.label(p, tostring(r[3]), w / 2 - 50, y, 22, ui.BONE, w * 0.35, { pivot = gui.PIVOT_E })
	end
end

-- ---------------------------------------------------------------- settings / pause
local function settings_body(app, p, w, h, kind)
	local d = progress.data
	local y = h / 2 - 130
	local half = (w - 100) / 2
	ui.btn(p, "btn_dark", -half / 2 - 10, y, half, 70, i18n.t("SOUND"), 22, function()
		d.sound = not d.sound
		audio.set(d.sound, d.music)
		progress.save()
		app.open_popup(kind)
	end, { icon = d.sound and "icon_sound" or "icon_sound_off", icon_size = 40 })
	ui.btn(p, "btn_dark", half / 2 + 10, y, half, 70, i18n.t("MUSIC"), 22, function()
		d.music = not d.music
		audio.set(d.sound, d.music)
		progress.save()
		app.open_popup(kind)
	end, { icon = d.music and "icon_music" or "icon_music_off", icon_size = 40 })
	ui.btn(p, "btn_dark", 0, y - 90, w - 80, 70, i18n.t("LANGUAGE") .. ": " .. i18n.NAMES[i18n.lang], 22, function()
		local nxt = i18n.lang == "ru" and "en" or "ru"
		d.lang = nxt
		i18n.set(nxt)
		progress.save()
		app.rebuild()
		app.open_popup(kind)
	end, { icon = "icon_globe", icon_size = 40 })
	return y - 180
end

B.settings = function(app, root)
	local p, w, h = panel(root, app, 560, 460, i18n.t("SETTINGS"))
	close_btn(app, p, w, h)
	settings_body(app, p, w, h, "settings")
	ui.label(p, "Gem Vanguard v" .. sys.get_config_string("project.version", "1.0"), 0, -h / 2 + 40, 15, ui.DIM, w - 60)
end

B.pause = function(app, root)
	local p, w, h = panel(root, app, 560, 600, i18n.t("PAUSED"))
	close_btn(app, p, w, h, function() app.resume_battle() end)
	local y = settings_body(app, p, w, h, "pause")
	ui.btn(p, "btn_gold", 0, y - 10, w - 80, 80, i18n.t("RESUME"), 28, function()
		app.resume_battle()
	end, { icon = "icon_play", icon_size = 40 })
	ui.btn(p, "btn_crimson", 0, y - 110, w - 80, 64, i18n.t("SURRENDER"), 22, function()
		app.close_popup(true)
		if app.session then app.session.status = "lose"; app.session.revived = true end
		app.on_battle_end(false)
	end)
end

-- ---------------------------------------------------------------- entry points
function M.build(app, popup)
	local kind, data = popup.kind, popup.data or {}
	local root = backdrop(app, kind == "chest" and 0.9 or 0.8)
	if B[kind] then B[kind](app, root, data) else app.close_popup() end
end

-- ESC / Android back inside a popup
function M.on_back(app)
	local kind = app.popup and app.popup.kind
	if kind == "win" then
		app.close_popup(true)
		app.show_hub()
	elseif kind == "lose" then
		app.leave_battle()
	elseif kind == "pause" then
		app.resume_battle()
	elseif kind == "pvp_search" or kind == "chest" then
		return
	else
		app.close_popup()
	end
end

return M
