-- Sound effects + deferred WebAudio loader for music and secondary meta SFX.
-- Critical battle/UI SFX live in main:/sounds; music + non-critical meta SFX load post-boot.
local M = {}

local URL = "main:/sounds#"
-- Only the "sfx" group exists in main/sounds.go; music/master live in WebAudio (window._gvAudio).
-- Calling sound.set_group_gain on a missing group logs "Failed to set group gain (-13)".
local SFX = hash("sfx")
local MUSIC_GAIN = 0.55

local LAZY_FALLBACK = {
	levelup = "star",
	chest = "star",
	quest = "coin",
	upgrade = "coin",
	flip = "tap",
	turn = "turn_you",
	notify = "tap",
}

local sound_on = true
local music_on = true
local ad_muted = false
local music_started = false
local music_mode = "hub"
local deferred_started = false
local last_played = {}
local clock = 0

local function sync_web_gains()
	if not html5 then return end
	pcall(html5.run, string.format(
		"window._gvAudio && window._gvAudio.gains(%s,%s,%s)",
		ad_muted and "0" or "1",
		sound_on and "1" or "0",
		music_on and tostring(MUSIC_GAIN) or "0"
	))
end

function M.update(dt)
	clock = clock + dt
end

function M.play(name, gain, speed)
	if not sound_on or ad_muted or not name then return end
	if last_played[name] and clock - last_played[name] < 0.04 then return end
	last_played[name] = clock
	if LAZY_FALLBACK[name] then
		if html5 then
			local ok, played = pcall(html5.run, string.format(
				"window._gvAudio ? window._gvAudio.play('%s',%s,%s) : false",
				name, tostring(gain or 1), tostring(speed or 1)
			))
			if ok and played == "true" or played == true then return end
		end
		name = LAZY_FALLBACK[name]
	end
	pcall(sound.play, URL .. name, { gain = gain or 1, speed = speed or 1 })
end

local function apply()
	pcall(sound.set_group_gain, SFX, sound_on and 1 or 0)
	sync_web_gains()
end

function M.load_deferred(base_url)
	if deferred_started or not html5 then return end
	deferred_started = true
	local b = (base_url or ""):gsub("'", "")
	local js = [[
	(function(base){
		if(window._gvAudio)return;
		var AC=window.AudioContext||window.webkitAudioContext;
		if(!AC)return;
		var ctx=new AC();
		var master=ctx.createGain(), sfxG=ctx.createGain(), musG=ctx.createGain();
		var hubG=ctx.createGain(), batG=ctx.createGain();
		hubG.gain.value=1; batG.gain.value=0;
		hubG.connect(musG); batG.connect(musG);
		sfxG.connect(master); musG.connect(master); master.connect(ctx.destination);
		var bufs={}, hubStarted=false, batStarted=false;
		var musWant=]] .. (music_on and "true" or "false") .. [[, wantMode=']] .. music_mode .. [[';
		var unlock=function(){if(ctx.state==='suspended')ctx.resume().catch(function(){});};
		['pointerdown','touchstart','keydown'].forEach(function(e){window.addEventListener(e,unlock,{passive:true});});
		var syncMus=function(){
			if(!musWant)return;
			var useBat=(wantMode==='battle' && !!bufs.music_battle);
			if(!useBat && bufs.music && !hubStarted){
				hubStarted=true;
				var s1=ctx.createBufferSource();
				s1.buffer=bufs.music; s1.loop=true; s1.connect(hubG); s1.start(0);
			}
			if(useBat && bufs.music_battle && !batStarted){
				batStarted=true;
				var s2=ctx.createBufferSource();
				s2.buffer=bufs.music_battle; s2.loop=true; s2.connect(batG); s2.start(0);
			}
			var t=ctx.currentTime;
			try{
				hubG.gain.cancelScheduledValues(t); hubG.gain.setValueAtTime(hubG.gain.value,t);
				hubG.gain.linearRampToValueAtTime(useBat?0:1, t+0.6);
				batG.gain.cancelScheduledValues(t); batG.gain.setValueAtTime(batG.gain.value,t);
				batG.gain.linearRampToValueAtTime(useBat?1:0, t+0.6);
			}catch(e){hubG.gain.value=useBat?0:1; batG.gain.value=useBat?1:0;}
		};
		var loadOne=function(name){
			return fetch(base+'lazy/sfx/'+name+'.wav').then(function(r){return r.ok?r.arrayBuffer():null;}).then(function(ab){
				return ab?ctx.decodeAudioData(ab):null;
			}).then(function(b){if(b){bufs[name]=b;if(name==='music'||name==='music_battle')syncMus();}}).catch(function(){});
		};
		window._gvAudio={
			gains:function(m,s,mu){
				master.gain.value=m; sfxG.gain.value=s; musG.gain.value=mu;
				musWant=mu>0; if(musWant)syncMus();
			},
			play:function(name,g,sp){
				var b=bufs[name]; if(!b)return false;
				unlock();
				var src=ctx.createBufferSource(), gn=ctx.createGain();
				src.buffer=b; src.playbackRate.value=sp||1; gn.gain.value=g||1;
				src.connect(gn); gn.connect(sfxG); src.start(0);
				return true;
			},
			startMusic:function(){musWant=true;unlock();syncMus();},
			setMode:function(m){wantMode=m||'hub';syncMus();}
		};
		window._gvAudio.gains(]] .. (ad_muted and "0" or "1") .. [[,]] .. (sound_on and "1" or "0") .. [[,]] .. (music_on and tostring(MUSIC_GAIN) or "0") .. [[);
		['music','music_battle','chest','levelup','quest','upgrade','flip','turn','notify'].reduce(function(p,n){
			return p.then(function(){return loadOne(n);});
		}, Promise.resolve());
	})(']] .. b .. [[');
	]]
	pcall(html5.run, js)
end

function M.start_music()
	if music_started or not music_on then return end
	music_started = true
	if html5 then
		pcall(html5.run, "window._gvAudio && window._gvAudio.startMusic()")
	end
end

function M.set_music(mode)
	music_mode = (mode == "battle") and "battle" or "hub"
	if html5 then
		pcall(html5.run, "window._gvAudio && window._gvAudio.setMode('" .. music_mode .. "')")
	end
end

function M.set(sound_enabled, music_enabled)
	sound_on = sound_enabled
	music_on = music_enabled
	apply()
	M.start_music()
end

-- Poki: all audio must be silent while an ad is playing.
function M.ad_mute(muted)
	ad_muted = muted
	pcall(sound.set_group_gain, SFX, (sound_on and not muted) and 1 or 0)
	sync_web_gains()
end

function M.is_music()
	return music_on
end

return M
