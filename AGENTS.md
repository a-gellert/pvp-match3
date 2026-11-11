# Project Architecture & Guidelines — Gem Vanguard (Poki Match-3 Battler)

## Mandatory Workflow Rule
- **После каждого завершения работы агент обязан сделать коммит в ветку `main`.**

## Core Principles
1. **Target platform**: Poki (`wasm-web`). Fast startup, compact release bundle, portrait (mobile) and landscape (desktop).
2. **Visual Style**: Casual Dark Fantasy — deep indigo/slate stone (`#111521`, `#1c2233`, `#262e45`), aged gold/bronze accents (`#e8b84b`), saturated elemental gems (`red`, `yellow`, `purple`, `green`, `blue`), expressive commander face portraits, and squad sprites of **1–5 warriors**.
3. **GUI only & Zero Heavy Physics**: Everything is rendered via `main/gui/game.gui` with code-built nodes and lightweight GUI tweens (`ui.lua`). `main/game.appmanifest` strips Box2D/Bullet/models/particles.
4. **Virtual canvas**: `main/modules/layout.lua` maps the window to `720x1280` (portrait, aspect < 0.9) or `1600x900` (landscape).
   - Portrait Battle: Top arena (Player squads left, Enemy squads right, Commander face icons at bottom corners of arena) -> Match-3 board -> Bottom Boosters bar.
   - Landscape Battle: Left arena + commanders + boosters, Right Match-3 board.
5. **Modular Architecture**: Keep code split into small single-purpose modules:
   - Logic (`main/modules/`): `config`, `squads`, `campaign`, `board`, `ai`, `battle`, `progress`, `i18n`, `layout`, `rng`, `poki`, `audio`. Core combat/board logic has zero Defold API calls so it can run headlessly in simulations.
   - Views (`main/gui/`): `ui`, `battle_view`, `hub_view`, `map_view`, `shop_view`, `popups`, `game.gui_script`.
6. **Determinism**: Gameplay RNG uses `rng.lua` (Park-Miller); `math.random` is only for visual FX.
7. **Rebuildable views**: Resize/orientation rebuilds screens via `app.rebuild()`. Delayed callbacks use `ui.after(...)`.
8. **Poki SDK & Button Rules**: `gameplay_start` on active play, `gameplay_stop` on pause/popups/hub; `commercial_break` from level 4; `rewarded_break` buttons always have a non-rewarded alternative at least as prominent and are never green.
9. **Localization & Assets**: Visible strings live in `main/modules/i18n.lua` (`ru`, `en`). Always regenerate `main/assets/fonts/main.font` (`node tools/gen_font.js`), `main/assets/game.atlas` + `main/gui/sprite_sizes.lua` (`node tools/gen_sprites.js`), and `main/sounds.go` (`node tools/gen_sounds.js`) instead of hand-editing generated files.
