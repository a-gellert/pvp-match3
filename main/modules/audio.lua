-- Sound effects + looping music (components live on main:/sounds). Groups: sfx, music, master.
local M = {}

local URL = "main:/sounds#"
local SFX = hash("sfx")
local MUSIC = hash("music")
local MASTER = hash("master")
local MUSIC_GAIN = 0.8

local sound_on = true
local music_on = true
local music_started = false
local last_played = {}
local clock = 0

function M.update(dt)
	clock = clock + dt
end

function M.play(name, gain, speed)
	if not sound_on or not name then return end
	if last_played[name] and clock - last_played[name] < 0.04 then return end
	last_played[name] = clock
	pcall(sound.play, URL .. name, { gain = gain or 1, speed = speed or 1 })
end

local function apply()
	pcall(sound.set_group_gain, SFX, sound_on and 1 or 0)
	pcall(sound.set_group_gain, MUSIC, music_on and MUSIC_GAIN or 0)
end

function M.start_music()
	if music_started then return end
	music_started = true
	pcall(sound.play, URL .. "music")
end

function M.set(sound_enabled, music_enabled)
	sound_on = sound_enabled
	music_on = music_enabled
	apply()
	M.start_music()
end

-- Poki: all audio must be silent while an ad is playing.
function M.ad_mute(muted)
	pcall(sound.set_group_gain, MASTER, muted and 0 or 1)
end

function M.is_music()
	return music_on
end

return M
