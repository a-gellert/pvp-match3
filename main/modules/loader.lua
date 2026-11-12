-- Priority background loader for non-critical textures (arenas, late portraits, unlockable squads).
-- Critical frame-1 assets stay in main/assets/game.atlas; lazy PNGs live in bundle_res/common/lazy/img/
-- and for web bundles they are copied next to index.html (bundle_resources -> lazy/img/...).
-- They load after startup via http.request -> image.load -> gui.new_texture.
-- Outside a web bundle (editor, native) there is no HTTP origin for these files, so we keep the
-- atlas fallbacks instead of firing requests that can only fail.
local manifest = require "main.modules.lazy_manifest"

local M = {}

local PRIORITY = {
	"chest_royal",
	"arena_bg_lava",
	"arena_bg_void",
	"face_orc",
	"face_skeleton",
	"face_necromancer",
	"face_dragon",
	"proj_bolt",
	"proj_lightning",
	"proj_venom",
	"fx_reap",
}

local MAX_INFLIGHT = 2
local state = {}
local watchers = {}
local queue = {}
local queued = {}
local inflight = 0
local started = false
local base_url = nil
local on_idle_cb = nil
local idle_fired = false
local warned = false
-- Set when the first response proves the bundle has no lazy/ folder (or the request layer is
-- unavailable): the remaining assets are marked unavailable instead of spamming one error each.
local unreachable = false
local verbose = sys.get_config_int("pvp.lazy_debug", 0) == 1

local function log(fmt, ...)
	if verbose then print("[lazy] " .. string.format(fmt, ...)) end
end

local function get_base_url()
	if base_url and base_url ~= "" then return base_url end
	if html5 then
		local ok, res = pcall(html5.run, "(function(){var u=window.location.href.split('#')[0].split('?')[0];return u.replace(/[^/]*$/,'');})()")
		if ok and type(res) == "string" and res:match("^https?://") then
			base_url = res
			return base_url
		end
	end
	return ""
end

local function mark_unavailable(id)
	state[id] = "unavailable"
	watchers[id] = nil
	log("%s -> unavailable (atlas fallback)", id)
end

function M.base_url()
	return get_base_url()
end

function M.is_lazy(id)
	return manifest[id] ~= nil
end

function M.is_ready(id)
	return not manifest[id] or state[id] == "ready"
end

function M.reset_watchers()
	watchers = {}
end

local function enqueue(id, front)
	if not manifest[id] then return end
	if state[id] == "ready" or state[id] == "loading" or state[id] == "unavailable" then return end
	if queued[id] then
		if front then
			for i, v in ipairs(queue) do
				if v == id then
					table.remove(queue, i)
					table.insert(queue, 1, id)
					break
				end
			end
		end
		return
	end
	queued[id] = true
	if front then
		table.insert(queue, 1, id)
	else
		queue[#queue + 1] = id
	end
end

local pump

local function flush_watchers(id)
	local list = watchers[id]
	watchers[id] = nil
	if not list then return end
	for _, node in ipairs(list) do
		pcall(gui.set_texture, node, id)
	end
end

pump = function()
	if not started then return end
	while inflight < MAX_INFLIGHT and #queue > 0 do
		local id = table.remove(queue, 1)
		queued[id] = nil
		local def = manifest[id]
		if def and not state[id] then
			local base = get_base_url()
			if base == "" or unreachable then
				-- No web origin: this build only has the atlas (editor / native / stale bundle).
				mark_unavailable(id)
			else
				state[id] = "loading"
				inflight = inflight + 1
				local url = base .. def.path
				log("GET %s", url)
				http.request(url, "GET", function(_, _, res)
					inflight = math.max(0, inflight - 1)
					local ok_status = res and (res.status == 200 or res.status == 304)
					log("%s status=%s bytes=%s", id, tostring(res and res.status),
						tostring(res and res.response and #res.response))
					if ok_status and res.response and image and image.load then
						local ok_img, img = pcall(image.load, res.response, true)
						if ok_img and img and img.buffer then
							-- gui.TYPE_* is not exposed in every engine version; gui.new_texture also takes "rgb"/"rgba".
							local ttype = (img.type == image.TYPE_RGBA) and "rgba" or "rgb"
							local ok_tex, tex_err = pcall(gui.new_texture, id, img.width, img.height, ttype, img.buffer)
							if ok_tex then
								state[id] = "ready"
								log("%s ready %dx%d", id, img.width, img.height)
								flush_watchers(id)
							else
								log("%s new_texture failed: %s", id, tostring(tex_err))
								mark_unavailable(id)
							end
						else
							log("%s image.load failed (%s)", id, tostring(img))
							mark_unavailable(id)
						end
					else
						-- Missing lazy/ folder next to index.html: stop after the first failure.
						unreachable = true
						if not warned then
							warned = true
							print(string.format("[lazy] assets not found at %s (status %s) - using atlas fallbacks",
								tostring(url), tostring(res and res.status)))
						end
						mark_unavailable(id)
					end
					pump()
				end)
			end
		end
	end
	if inflight == 0 and #queue == 0 and not idle_fired then
		idle_fired = true
		if on_idle_cb then on_idle_cb() end
	end
end

function M.prioritize(id)
	if not manifest[id] or state[id] == "ready" then return end
	enqueue(id, true)
	if started then pump() end
end

function M.apply(node, id)
	local def = manifest[id]
	if not def then
		gui.set_texture(node, "game")
		gui.play_flipbook(node, id)
		return
	end
	if state[id] == "ready" then
		local ok = pcall(gui.set_texture, node, id)
		if ok then return end
	end
	gui.set_texture(node, "game")
	gui.play_flipbook(node, def.fallback or "square")
	if state[id] ~= "unavailable" then
		watchers[id] = watchers[id] or {}
		local w = watchers[id]
		w[#w + 1] = node
		M.prioritize(id)
	end
end

function M.start(on_idle)
	if started then return end
	started = true
	on_idle_cb = on_idle
	for _, id in ipairs(PRIORITY) do enqueue(id, false) end
	local rest = {}
	for id in pairs(manifest) do
		if not queued[id] then rest[#rest + 1] = id end
	end
	table.sort(rest)
	for _, id in ipairs(rest) do enqueue(id, false) end
	if timer and timer.delay then
		timer.delay(0.18, false, pump)
	end
end

return M
