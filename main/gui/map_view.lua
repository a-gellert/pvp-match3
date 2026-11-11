-- Campaign map tab: Druid scroll with a winding path of 30 stage medallions across 5 biomes,
-- stars per stage, boss portraits, current-stage pulse and a star-chest progress header.
local ui = require "main.gui.ui"
local campaign = require "main.modules.campaign"
local progress = require "main.modules.progress"
local config = require "main.modules.config"
local i18n = require "main.modules.i18n"
local audio = require "main.modules.audio"

local M = {}
local V3 = vmath.vector3
local V4 = vmath.vector4

local GAP = 150
local BIOME_GAP = 150

local function star_header(app, parent, cx, y, w)
	local have, need = progress.star_chest_progress()
	local ready = progress.star_chest_ready()
	-- Show progress toward the current chest only (e.g. 4 / 6)
	local base = need - config.STAR_CHEST_EVERY
	have, need = math.min(config.STAR_CHEST_EVERY, have - base), config.STAR_CHEST_EVERY
	local box = ui.slice(parent, "panel_stone", cx, y, w, 96, ui.WHITE, 22)
	ui.box(box, "icon_star", -w / 2 + 46, 4, 58, 58)
	ui.label(box, i18n.t("STAR_CHEST"), -w / 2 + 86, 22, 20, ui.GOLD, w * 0.45, { pivot = gui.PIVOT_W })
	local bw = w - 300
	ui.bar(box, -w / 2 + 86 + bw / 2, -16, bw, 24, math.min(1, have / need), ui.YELLOW, { text = have .. " / " .. need, text_size = 16 })
	local rarity = ((progress.data.star_chests or 0) + 1) % 3 == 0 and "royal" or "silver"
	local _, b = ui.btn(box, ready and "btn_gold" or "btn_dark", w / 2 - 82, 0, 140, 76, ready and i18n.t("OPEN") or "", 20, function()
		local res = progress.claim_star_chest()
		if res then
			audio.play("chest")
			app.open_popup("chest", res)
		else
			ui.float_text(app.hub_fx, i18n.t("STARS_NEED", { n = need - have }), cx + w / 2 - 82, y + 50, 20, ui.DIM, 30)
		end
	end, { icon = config.CHESTS[rarity].sprite, icon_size = ready and 50 or 64, pulse = ready })
	if ready then ui.badge(b.node, 62, 30, 1, 28) end
end

function M.build(app, parent, R)
	local d = progress.data
	local land = app.orient == "landscape"
	local w = math.min(R.w, land and 1100 or 720)
	local cx = R.cx
	star_header(app, parent, cx, R.y1 - 50, w)

	local view_h = R.y1 - 104 - R.y0
	local sc = ui.scroll(parent, cx, R.y0 + view_h / 2, R.w, view_h)
	local content = sc.content
	local amp = math.min(w * 0.3, 260)
	local unlocked_max = d.max_stage_unlocked or 1

	local y = -40
	local positions = {}
	local cur_y = 0
	for n = 1, campaign.COUNT do
		local stg = campaign.get_stage(n)
		local biome = campaign.BIOMES[stg.zone]
		if (n - 1) % campaign.STAGES_PER_BIOME == 0 then
			-- Biome banner
			y = y - 60
			local locked_biome = n > unlocked_max
			local ban = ui.slice(content, "panel_stone", 0, y, math.min(w - 20, 640), 86, locked_biome and V4(0.6, 0.6, 0.7, 1) or ui.WHITE, 22)
			local strip = ui.box(ban, "arena_bg", 0, 0, math.min(w - 20, 640) - 18, 68, ui.hex(biome.tint))
			gui.set_alpha(strip, locked_biome and 0.25 or 0.55)
			ui.label(ban, i18n.t(biome.name_key), 0, 10, 28, locked_biome and ui.DIM or ui.hex(biome.tint), 520)
			ui.label(ban, i18n.t("STAGES_RANGE", { a = n, b = n + campaign.STAGES_PER_BIOME - 1 }), 0, -22, 16, ui.BONE, 400)
			y = y - BIOME_GAP + 20
		end
		local x = math.sin(n * 0.95) * amp
		positions[n] = { x = x, y = y }
		if n == math.min(unlocked_max, campaign.COUNT) then cur_y = y end
		y = y - GAP
	end

	-- Path dots between nodes
	for n = 1, campaign.COUNT - 1 do
		local a, b = positions[n], positions[n + 1]
		local reached = n + 1 <= unlocked_max
		local col = reached and ui.hex(campaign.BIOMES[campaign.get_stage(n + 1).zone].path) or V4(0.3, 0.33, 0.42, 0.8)
		for k = 1, 5 do
			local t = k / 6
			ui.box(content, "path_dot", a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, reached and 16 or 12, reached and 16 or 12, col)
		end
	end

	-- Stage medallions
	for n = 1, campaign.COUNT do
		local stg = campaign.get_stage(n)
		local p = positions[n]
		local unlocked = n <= unlocked_max
		local current = n == unlocked_max
		local size = stg.boss and 128 or 104
		local tint = unlocked and ui.hex(campaign.BIOMES[stg.zone].path) or V4(0.4, 0.42, 0.5, 1)
		if current then
			local gl = ui.glow(ui.box(content, "glow", p.x, p.y, size * 2.1, size * 2.1, V4(1, 0.8, 0.35, 0.55)))
			ui.pulse(gl, 1.15, 0.6)
			local rays = ui.glow(ui.box(content, "rays", p.x, p.y, size * 2.4, size * 2.4, V4(1, 0.85, 0.5, 0.3)))
			ui.spin(rays, 9)
		end
		local node = ui.box(content, "node_stage", p.x, p.y, size, size, unlocked and ui.WHITE or V4(0.55, 0.55, 0.62, 1))
		local inner = ui.box(node, "glow", 0, 4, size * 0.7, size * 0.7, V4(tint.x, tint.y, tint.z, unlocked and 0.45 or 0.15))
		ui.glow(inner)
		if stg.boss then
			ui.box(node, stg.face, 0, 4, size * 0.6, size * 0.6, unlocked and ui.WHITE or V4(0.3, 0.3, 0.35, 1))
			local tag = ui.slice(node, "btn_crimson", 0, size / 2 + 4, 84, 28, ui.WHITE, 10)
			ui.text(tag, i18n.t("BOSS"), 0, 2, 15, ui.WHITE)
		else
			ui.text(node, tostring(n), 0, 6, 34, unlocked and ui.BONE or ui.DIM)
		end
		if not unlocked then
			ui.box(node, "icon_lock", size * 0.3, -size * 0.28, 30, 30)
		else
			local stars = progress.stage_stars(n)
			for k = 1, 3 do
				local sx = (k - 2) * 30
				local sy = -size / 2 - 6 + (k == 2 and -6 or 0)
				ui.box(node, k <= stars and "icon_star" or "icon_star_empty", sx, sy, 32, 32)
			end
		end
		if current then
			ui.bob(node, 6, 0.6)
			local hand = ui.box(content, "icon_play", p.x + size * 0.72, p.y, 44, 44, ui.GOLD)
			gui.set_euler(hand, V3(0, 0, 180))
			gui.animate(hand, "position.x", p.x + size * 0.62, gui.EASING_INOUTSINE, 0.45, 0, nil, gui.PLAYBACK_LOOP_PINGPONG)
		end
		if unlocked then
			ui.button(node, function() app.open_popup("stage", { id = n }) end)
		else
			ui.button(node, function()
				audio.play("blocked")
				ui.float_text(app.hub_fx, i18n.t("STAGE_LOCKED"), R.cx, R.cy, 24, ui.DIM, 30)
			end, { silent = true })
		end
	end

	local total_h = -y + 60
	sc.set_height(total_h)
	-- Focus the current stage
	-- content.y = -cur_y puts the current medallion in the middle of the view (Druid clamps it)
	sc.scroll:scroll_to(V3(0, cur_y, 0), true)
end

return M
