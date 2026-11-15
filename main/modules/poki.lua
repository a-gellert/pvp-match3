-- Poki SDK wrapper: gameplay events, commercial breaks, rewarded breaks and analytics.
-- All audio is muted while an ad is on screen (Poki requirement).
local audio = require "main.modules.audio"

local M = {}

local gameplay = false
local ad_active = false

-- Commercial breaks start after the 3 onboarding battles (Poki rate-limits them on its side too).
M.FIRST_BREAK_LEVEL = 4

local function set_ad(active)
	ad_active = active
	audio.ad_mute(active)
end

local function sdk()
	return rawget(_G, "poki_sdk")
end

function M.available()
	return sdk() ~= nil
end

function M.is_ad_active()
	return ad_active
end

function M.is_gameplay()
	return gameplay
end

function M.gameplay_start()
	if gameplay or ad_active then return end
	gameplay = true
	local s = sdk()
	if s and s.gameplay_start then s.gameplay_start() end
end

function M.gameplay_stop()
	if not gameplay then return end
	gameplay = false
	local s = sdk()
	if s and s.gameplay_stop then s.gameplay_stop() end
end

-- PokiSDK.getLanguage(): the player's language as a lowercase base code ("en", "pt"
-- for pt-BR). The Defold binding does not expose it yet, so ask the JS SDK directly.
-- Returns nil outside HTML5 (or before the SDK is loaded) so callers can fall back.
function M.language()
	local s = sdk()
	if s and s.get_language then
		local ok, res = pcall(s.get_language)
		if ok and type(res) == "string" and res ~= "" then return res end
	end
	if html5 and html5.run then
		local ok, res = pcall(html5.run, "window.PokiSDK&&PokiSDK.getLanguage?PokiSDK.getLanguage():''")
		if ok and type(res) == "string" and res ~= "" then return res end
	end
	return nil
end

function M.measure(category, what, action)
	local s = sdk()
	if s and s.measure then pcall(s.measure, category, tostring(what), action) end
end

function M.commercial_break(level, on_done)
	local s = sdk()
	if not (s and s.commercial_break) or (level or 1) < M.FIRST_BREAK_LEVEL then
		if on_done then on_done() end
		return
	end
	M.gameplay_stop()
	set_ad(true)
	local done = false
	s.commercial_break(function(_, status)
		if status == s.COMMERCIAL_BREAK_START then
			set_ad(true)
		elseif not done then
			done = true
			set_ad(false)
			if on_done then on_done() end
		end
	end)
end

function M.rewarded(size, on_done)
	local s = sdk()
	if not (s and s.rewarded_break) then
		if on_done then on_done(true) end
		return
	end
	M.gameplay_stop()
	set_ad(true)
	local done = false
	s.rewarded_break(size or "small", function(_, status)
		if status == s.REWARDED_BREAK_START then
			set_ad(true)
		elseif not done then
			done = true
			set_ad(false)
			if on_done then on_done(status == s.REWARDED_BREAK_SUCCESS) end
		end
	end)
end

return M
