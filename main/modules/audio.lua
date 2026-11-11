-- Sound effects (components live on main:/sounds).
local M = {}

local URL = "main:/sounds#"
local sound_on = true
local music_on = true
local last_played = {}
local clock = 0

function M.update(dt)
	clock = clock + dt
end

function M.play(name, gain, speed)
	if not sound_on then return end
	if last_played[name] and clock - last_played[name] < 0.04 then return end
	last_played[name] = clock
	pcall(sound.play, URL .. name, { gain = gain or 1, speed = speed or 1 })
end

function M.set(sound_enabled, music_enabled)
	sound_on = sound_enabled
	music_on = music_enabled
end

function M.is_music()
	return music_on
end

return M
