# Gem Vanguard

Casual dark-fantasy **Match-3 battler** for [Poki](https://poki.com/), made with [Defold](https://defold.com/) and the [Druid](https://github.com/Insality/druid) UI library. Portrait (mobile) and landscape (desktop) layouts adapt to any aspect ratio.

- 7×7 board shared with the enemy in **tap-to-blast** mode (Toon Blast style clusters; classic swap mode is one flag away), 3–7 moves per turn, special gems, cascades and squad rune skills.
- 21 squads (7 per element, Clash Royale–style cards and upgrades), 30-stage campaign in 5 biomes with multi-wave bosses, stars, PvP ladder with 6 leagues and a 40-step prestige road.
- Daily Trial (a new boss every day with a win streak), Endless Gauntlet (5 fights + relics), daily quests, 7-day login calendar, free gift every 4 hours, daily shop deals, chest slots with web-friendly timers (0s / 10s / 2m / 7m; every win cuts 45s off the active chest).
- Progressive-disclosure hub: Battle + Squads after the first 3 onboarding fights, then Tower, Map/Quests and finally Shop + PvP.
- 10 Poki locales: English, Spanish, Portuguese (BR), Russian, Turkish, Polish, German, French, Italian and Dutch. The language is taken from `PokiSDK.getLanguage()` on the first run and can be changed in Settings.

Design and architecture: [docs/DESIGN_DOC.md](docs/DESIGN_DOC.md). Rules for contributors and agents: [AGENTS.md](AGENTS.md).

## Dependencies (`game.project`)

| Library | Version |
| --- | --- |
| [extension-poki-sdk](https://github.com/defold/extension-poki-sdk) | locked to commit `3e0c329` |
| [defold-event](https://github.com/Insality/defold-event) | 21 |
| [Druid](https://github.com/Insality/druid) | 1.3.0 |

## Build

```sh
sh tools/build_web.sh            # debug web bundle -> bundle/web
sh tools/build_poki.sh           # release bundle + poki.zip for upload
```

Both scripts use the Defold install in `C:/Program Files (x86)/Defold` (override with `DEFOLD=...`).

## Generated assets

Do not edit these by hand — regenerate them:

```sh
node tools/gen_sprites.js        # main/assets/images, game.atlas, main/gui/sprite_sizes.lua
node tools/gen_font.js           # main/assets/fonts/main.font (glyphs used by every .lua under main/)
node tools/check_fonts.js        # fails when a string needs a glyph the TTF or main.font lacks
node tools/gen_sounds.js         # SFX + music loop WAVs and main/sounds.go
```

## Smoke test

```sh
node tools/web_smoke.js "bundle/web/GemVanguard" out --screen=home --size=405x720
node tools/web_smoke.js "bundle/web/GemVanguard" out --size=405x720 --steps="wait:6;click:200,400;wait:2;shot:after"
node tools/web_smoke.js "bundle/web/GemVanguard" out --screen=language --lang=de --size=540x960
```

`--screen` jumps to a debug state (`home`, `hub_early`, `cards`, `map`, `shop`, `quests`, `tower`, `battle`, `wave`, `boss_relic`, `pvp`, `chest`, `win`, `road`, `stage`, `trial`, `trial_battle`, `trial_win`, `relic`, `relics_ult`, `survival`, `settings`, `language`, `sim`); `--lang` forces a locale. The script prints the number of Lua/JS errors seen in the console; `--cfg=pvp.poki_debug=1` traces the Poki lifecycle and `--cfg=pvp.autoplay=1` plays the board through the normal input path.
