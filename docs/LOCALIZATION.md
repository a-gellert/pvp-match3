# Localization

Gem Vanguard ships the 10 Poki locales that the bundled `Nunito-Black.ttf` can render
(Latin, Latin Extended, Cyrillic). The list and its order (Poki priority: EFIGS + Turkish,
then pt-BR and Russian, then the remaining Latin-script markets) live in
`main/modules/i18n.lua` (`M.LANGS`) and drive the language picker in Settings.

| Code | Language | Notes |
| --- | --- | --- |
| `en` | English | Reference locale: every other table must contain the same keys |
| `es` | Español | Latin American neutral |
| `pt` | Português | Brazilian Portuguese |
| `ru` | Русский | Cyrillic + `ё`, `—`, `»` |
| `tr` | Türkçe | `ı / İ`, `ş ğ ç ö ü` |
| `pl` | Polski | `ą ć ę ł ń ó ś ź ż` |
| `de` | Deutsch | `ä ö ü ß` |
| `fr` | Français | `à â ç è é ê ë î ô û` |
| `it` | Italiano | `à è é ì ò ù` |
| `nl` | Nederlands | `ë ï é` |

## Where strings live

```
main/modules/i18n.lua            -- LANGS, NAMES, detect/normalize, t(), fmt_time()
main/modules/locales/en.lua      -- one table per language: return { NAME = "...", KEY = "..." }
main/modules/locales/<code>.lua
```

* `i18n.t("KEY", { n = 3 })` replaces `{n}` placeholders; keys missing in the active
  locale fall back to `en`.
* Add a key to **every** locale file (`en.lua` is the reference) and run
  `node tools/check_fonts.js` — it fails on missing/extra keys and on missing glyphs.
* Placeholders (`{n}`, `{g}`, `{d}`, `{t}`, `{a}`, `{b}`, `{g1}`, `{g2}`, `{name}`,
  `{dmg}`, `{h}`, `{m}`, `{c}`, `{s}`) must stay in every translation.
* Keep button labels short: buttons downscale text to fit, but very long labels become
  tiny. `\n` is allowed for two-line labels.

## Language detection

1. `progress.data.lang` — a manual choice from **Settings → Language** (persisted save).
2. `PokiSDK.getLanguage()` on the first run (Poki returns a lowercase base code, so
   `pt-BR` arrives as `pt`). The Defold Poki extension does not wrap this call, so
   `main/modules/poki.lua` evaluates it with `html5.run` and falls back to `nil`.
3. `sys.get_sys_info().language` (native builds, editor).
4. `en`.

`i18n.normalize()` maps full tags and unsupported languages (`zh`, `ja`, `ko`, `vi`,
`th`, `hi`, `ar`, `uk`, ...) to a supported base code or to English.

For QA, `--cfg=pvp.lang=de` (or `web_smoke.js --lang=de`) forces a locale and
`--pokilang=de` changes what the mocked `PokiSDK.getLanguage()` returns
(pass `--lang=` to exercise first-run detection).

## Fonts

`main/assets/fonts/main.font` is generated, never edited by hand:

```sh
node tools/gen_font.js     # collects every glyph used by main/**/*.lua (locales included)
node tools/check_fonts.js  # gate: TTF coverage, atlas contents, cache estimate, key parity
```

* `gen_font.js` emits printable ASCII plus each used non-ASCII glyph and its upper/lower
  case forms, but only if the glyph exists in `Nunito-Black.ttf`.
* `check_fonts.js` reports missing glyphs per locale and warns about case forms the TTF
  lacks. Current atlas: 226 glyphs, estimated 1024x1024 SDF cache (Defold caps dynamic
  fonts at 2048x4096, 1 channel with `shadow_blur: 0`).
* CJK, Vietnamese, Arabic, Thai and Devanagari are **not** supported by this TTF. Adding
  them requires shipping a second font (per-script) and loading it with Live Update;
  until then those players get English.
* The picker names are part of the tables (`NAME`), so a new locale automatically gets
  a native button in Settings.
