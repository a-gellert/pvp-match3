# Gem Vanguard

Casual dark-fantasy **Match-3 battler** for [Poki](https://poki.com/), made with [Defold](https://defold.com/) and the [Druid](https://github.com/Insality/druid) UI library. Portrait (mobile) and landscape (desktop) layouts adapt to any aspect ratio.

- 7×7 board shared with the enemy, 1–7 moves per turn, special gems, cascades and squad rune skills.
- 18 squads (Clash Royale–style cards and upgrades), 30-stage campaign in 5 biomes with stars and bosses, PvP ladder with 6 leagues and a 40-step prestige road.
- Daily quests, 7-day login calendar, free gift every 4 hours, daily shop deals, chest slots with timers.
- Russian and English localization.

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
node tools/gen_font.js           # main/assets/fonts/main.font (glyphs used in i18n.lua)
node tools/gen_sounds.js         # SFX + music loop WAVs and main/sounds.go
```

## Smoke test

```sh
node tools/web_smoke.js "bundle/web/Gem Vanguard" out --screen=home --size=405x720
node tools/web_smoke.js "bundle/web/Gem Vanguard" out --size=405x720 --steps="wait:6;click:200,400;wait:2;shot:after"
```

`--screen` jumps to a debug state (`home`, `cards`, `map`, `shop`, `quests`, `battle`, `pvp`, `chest`, `win`, `road`, `stage`); the script prints the number of Lua/JS errors seen in the console.
