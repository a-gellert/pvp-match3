-- Modal Popups: Win/Lose (Poki compliant), Chest Open, Card Details, PvP Search, Settings/Pause.
local ui = require "main.gui.ui"
local config = require "main.modules.config"
local squads = require "main.modules.squads"
local progress = require "main.modules.progress"
local i18n = require "main.modules.i18n"
local audio = require "main.modules.audio"

local M = {}

local function backdrop(app)
	local root = ui.pane(app.popup_layer, 0, 0)
	app.popup_root = root
	local bg = ui.box(root, "square", app.vw / 2, app.vh / 2, app.vw, app.vh, vmath.vector4(0.03, 0.04, 0.08, 0.78))
	ui.button(bg, app.vw, app.vh, function() end, { silent = true })
	return root
end

local function panel(root, app, w, h, title)
	local p = ui.slice(root, "panel_stone", app.vw / 2, app.vh / 2, w, h, ui.WHITE, 24)
	ui.pop(p, 0.85, 1, 0.22)
	if title then
		local t = ui.text(p, title, 0, h / 2 - 44, 30, ui.GOLD)
		ui.fit(t, w - 70, 30)
	end
	return p
end

local function close_btn(p, w, h, fn)
	ui.btn(p, "btn_round", w / 2 - 22, h / 2 - 22, 48, 48, "", 16, fn)
	ui.box(p, "icon_close", w / 2 - 22, h / 2 - 22, 24, 24)
end

function M.build(app, popup)
	local kind, data = popup.kind, popup.data or {}
	local root = backdrop(app)

	if kind == "win" or kind == "lose" then
		local won = kind == "win"
		local w, h = 520, 480
		local p = panel(root, app, w, h, i18n.t(won and "VICTORY" or "DEFEAT"))

		-- Gold & Prestige delta
		ui.box(p, "icon_gold", -110, 90, 44, 44)
		ui.text(p, "+" .. (data.gold or 0), -54, 90, 28, ui.GOLD)

		ui.box(p, "icon_prestige", 60, 90, 44, 44)
		local dp = data.prestige_delta or 0
		ui.text(p, (dp >= 0 and "+" or "") .. dp, 120, 90, 28, dp >= 0 and ui.PRESTIGE or ui.RED)

		if won and data.chest_rarity then
			local sp = config.CHESTS[data.chest_rarity].sprite
			ui.icon(p, sp, 0, 8, 88)
			ui.text(p, data.chest_slot and i18n.t("CHEST_" .. data.chest_rarity) or i18n.t("CHEST_FULL"), 0, -48, 19,
				data.chest_slot and ui.BONE or ui.DIM)
		end

		-- Poki button rule: Plain button is equal/larger and placed ABOVE or beside purple rewarded button (never green!)
		if won then
			ui.btn(p, "btn_gold", 0, -112, 340, 62, i18n.t("TO_HUB"), 24, function()
				app.close_popup()
				app.show_hub()
			end)
			if not data.doubled then
				ui.btn(p, "btn_purple", 0, -184, 300, 54, i18n.t("DOUBLE_GOLD"), 20, function()
					app.reward_double_gold(data)
				end)
			end
		else
			ui.btn(p, "btn_dark", -110, -120, 200, 60, i18n.t("TO_HUB"), 22, function()
				app.close_popup()
				app.show_hub()
			end)
			ui.btn(p, "btn_gold", 110, -120, 200, 60, i18n.t("RETRY"), 22, function()
				app.close_popup()
				app.retry_battle()
			end)
			ui.btn(p, "btn_purple", 0, -190, 320, 54, i18n.t("SECOND_CHANCE"), 20, function()
				app.reward_second_chance()
			end)
		end

	elseif kind == "chest" then
		local w, h = 500, 460
		local p = panel(root, app, w, h, i18n.t("CHEST_OPENED"))
		ui.icon(p, config.CHESTS[data.rarity or "wood"].sprite, 0, 108, 94)
		ui.burst(p, 0, 108, 12, ui.GOLD, 90, 24)
		ui.box(p, "icon_gold", -46, 26, 36, 36)
		ui.text(p, "+" .. (data.gold or 0), 22, 26, 26, ui.GOLD)

		local drops = data.drops or {}
		local n = math.min(3, #drops)
		for i = 1, n do
			local dr = drops[i]
			local sq = squads.get(dr.id)
			local dx = (i - (n + 1) / 2) * 145
			ui.slice(p, ui.RARITY_FRAME[sq.rarity], dx, -66, 128, 118, ui.WHITE, 16)
			ui.icon(p, sq.sprite, dx, -56, 76)
			ui.text(p, "+" .. dr.count, dx, -104, 20, ui.GREEN)
		end
		ui.btn(p, "btn_gold", 0, -172, 260, 58, i18n.t("CLAIM"), 24, function()
			app.close_popup()
			app.rebuild()
		end)

	elseif kind == "card" then
		local sq = squads.get(data.id)
		local c = progress.data.cards[sq.id]
		local w, h = 480, 500
		local p = panel(root, app, w, h, i18n.t("SQ_" .. sq.id))
		close_btn(p, w, h, function() app.close_popup() end)

		ui.slice(p, ui.RARITY_FRAME[sq.rarity], 0, 100, 180, 146, ui.WHITE, 20)
		ui.icon(p, sq.sprite, 0, 100, 124)

		local atk = squads.power(sq.id, c.level)
		ui.text(p, i18n.t("RARITY_" .. sq.rarity) .. " | " .. i18n.t("LVL_FMT", { n = c.level }), 0, 4, 20, ui.GOLD)
		ui.text(p, i18n.t("ATK_FMT", { n = atk }) .. "   (" .. i18n.t("SLOT_" .. sq.color) .. ")", 0, -30, 19, ui.BONE)
		local tr = ui.text(p, i18n.t("TRAIT_" .. sq.trait), 0, -68, 18, ui.DIM)
		ui.fit(tr, w - 60, 18)

		if c.unlocked then
			local req = squads.upgrade_req(sq.id, c.level)
			local gcost = squads.upgrade_gold(sq.id, c.level)
			if req then
				ui.hp_bar(p, 0, -110, 320, 26, c.count, req, 0, progress.can_upgrade_card(sq.id) and ui.GREEN or ui.BLUE)
			end
			local is_eq = progress.data.slots[sq.color] == sq.id
			ui.btn(p, is_eq and "btn_dark" or "btn_gold", -105, -178, 190, 58,
				i18n.t(is_eq and "EQUIPPED" or "EQUIP"), 20, function()
					if not is_eq then
						progress.assign_slot(sq.id)
						app.close_popup()
						app.rebuild()
					end
				end)
			if req and gcost then
				local can_u = progress.can_upgrade_card(sq.id)
				ui.btn(p, can_u and "btn_gold" or "btn_dark", 105, -178, 190, 58,
					i18n.t("UPGRADE", { g = gcost }), 18, function()
						if progress.upgrade_card(sq.id) then
							audio.play("upgrade")
							app.open_popup("card", { id = sq.id })
							app.rebuild()
						else
							ui.float_text(p, i18n.t("MISS_RES"), 105, -125, 18, ui.RED, 35)
						end
					end)
			end
		else
			local dc = squads.unlock_diamonds(sq.id)
			ui.btn(p, "btn_purple", 0, -178, 280, 60, i18n.t("BUY_CARD", { d = dc }), 22, function()
				if progress.buy_locked_card(sq.id) then
					audio.play("upgrade")
					app.close_popup()
					app.rebuild()
				else
					ui.float_text(p, i18n.t("MISS_RES"), 0, -120, 18, ui.RED, 35)
				end
			end)
		end

	elseif kind == "pvp_search" then
		local w, h = 440, 300
		local p = panel(root, app, w, h, i18n.t("PVP"))
		ui.box(p, "icon_pvp", 0, 26, 76, 76)
		local st_txt = ui.text(p, i18n.t("PVP_SEARCH"), 0, -52, 22, ui.BONE)
		ui.after(1.0, function()
			ui.set_text(st_txt, i18n.t("PVP_FOUND") .. " " .. (data.opp.name or ""), 380, 22)
			ui.after(0.6, function()
				app.close_popup()
				app.launch_pvp(data.opp)
			end)
		end)

	elseif kind == "pause" or kind == "settings" then
		local d = progress.data
		local is_pause = kind == "pause"
		local w, h = 460, is_pause and 440 or 380
		local p = panel(root, app, w, h, i18n.t(is_pause and "PAUSED" or "SETTINGS"))
		close_btn(p, w, h, function() app.close_popup() end)

		ui.btn(p, "btn_dark", -90, 56, 150, 58, i18n.t("SOUND"), 19, function()
			d.sound = not d.sound
			audio.set(d.sound, d.music)
			progress.save()
			app.open_popup(kind)
		end)
		ui.box(p, d.sound and "icon_sound" or "icon_sound_off", -135, 56, 28, 28)

		ui.btn(p, "btn_dark", 90, 56, 150, 58, i18n.t("MUSIC"), 19, function()
			d.music = not d.music
			audio.set(d.sound, d.music)
			progress.save()
			app.open_popup(kind)
		end)
		ui.box(p, d.music and "icon_music" or "icon_music_off", 45, 56, 28, 28)

		ui.btn(p, "btn_dark", 0, -24, 320, 56, i18n.t("LANGUAGE") .. ": " .. i18n.NAMES[i18n.lang], 20, function()
			local nxt = i18n.lang == "ru" and "en" or "ru"
			d.lang = nxt
			i18n.set(nxt)
			progress.save()
			app.rebuild()
			app.open_popup(kind)
		end)

		if is_pause then
			ui.btn(p, "btn_gold", 0, -104, 320, 58, i18n.t("RESUME"), 22, function() app.close_popup() end)
			ui.btn(p, "btn_crimson", 0, -172, 320, 52, i18n.t("SURRENDER"), 20, function()
				app.close_popup()
				app.on_battle_end(false)
			end)
		end
	end
end

return M
