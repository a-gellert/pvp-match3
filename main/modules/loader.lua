-- Priority background loader for non-critical textures (arenas, late portraits, unlockable squads).
-- Critical frame-1 assets stay in main/assets/game.atlas; lazy PNGs live in bundle_res/common/lazy/img/
-- and load after startup via http.request -> image.load -> gui.new_texture.
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

local function get_base_url()
	if base_url ~= nil then return base_url end
	if html5 then
		local ok, res = pcall(html5.run, "(function(){var u=window.location.href.split('#')[0].split('?')[0];return u.replace(/[^/]*$/,'');})()")
		if ok and type(res) == "string" and #res > 0 then
			base_url = res
			return base_url
		end
	end
	base_url = ""
	return base_url
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
	if not manifest[id] or state[id] == "ready" or state[id] == "loading" then return end
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
			state[id] = "loading"
			inflight = inflight + 1
			local url = get_base_url() .. def.path
			http.request(url, "GET", function(_, _, res)
				inflight = math.max(0, inflight - 1)
				if res and (res.status == 200 or res.status == 304) and res.response and image and image.load then
					local ok_img, img = pcall(image.load, res.response, true)
					if ok_img and img and img.buffer then
						local ttype = (img.type == image.TYPE_RGBA) and gui.TYPE_RGBA or gui.TYPE_RGB
						local ok_tex = pcall(gui.new_texture, id, img.width, img.height, ttype, img.buffer)
						if ok_tex then
							state[id] = "ready"
							flush_watchers(id)
						else
							state[id] = "failed"
						end
					else
						state[id] = "failed"
					end
				else
					state[id] = "failed"
				end
				pump()
			end)
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
	watchers[id] = watchers[id] or {}
	local w = watchers[id]
	w[#w + 1] = node
	M.prioritize(id)
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
