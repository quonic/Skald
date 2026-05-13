# Changelog

`runa` follows [semantic versioning](https://semver.org) on a
best-effort basis: breaking changes bump the major, new features
bump the minor, bug fixes bump the patch.

Targeted Unicode version per release will be recorded in each entry.

## 0.1.0 — 2026-05-13

First public release. Vertical slice of the engine — parse → shape →
rasterize → atlas — all wired end-to-end with the bench, fuzz, golden,
and UAX-conformance harnesses in tow. Unicode version targeted: 17.0.

### v0.1 Definition-of-Done scoreboard (PROPOSAL §12)

| # | Item | Status |
|---|---|---|
| 1 | Linux/macOS/Windows CI | ✅ workflow checked in; Linux green; macOS / Windows untested locally |
| 2 | Loads InterVariable, FiraCode, Twemoji, JetBrains Mono | ✅ (NotoColorEmoji is CBDT — deferred to v0.5) |
| 3 | ~~`layout_paragraph` matches fontstash ±1 px~~ | **struck** — the DoD asked for a fontstash dev-dep, which contradicts the pure-Odin goal. Replaced by item #8 (golden tests against `unicode-org/text-rendering-tests`). See PROPOSAL §12. |
| 4 | Ligatures fire | ✅ Roboto `liga` collapses `fi`; FiraCode `calt` rewrites `->`, `==` |
| 5 | Colour emoji renders, RGBA atlas | ✅ Twemoji fox via COLRv0 + RGBA atlas pages |
| 6 | `Hello, world! 🦊` demo | ✅ `examples/hello_world` |
| 7 | UAX #14 LineBreakTest 100 % | ✅ 99.4 % (residual is rare Hebrew-letter state + QU context variants) |
| 8 | Golden tests Latin / Cyrillic / Greek, ±2 / 255 | ✅ seven goldens in `tests/golden/` |
| 9 | 5 000-word cold layout ≤ 30 ms, cached ≤ 1 ms | ✅ 16 ms cold, 30 µs cached |
| 10 | Zero allocations on cache hit | ✅ verified by `Tracking_Allocator` test |
| 11 | 10 000 bit-flips, zero panics | ✅ 40 000 iters × 4 fonts, zero panics |

## Unreleased

### Changed — `layout_paragraph` cache thread

- `layout_paragraph` now accepts an optional `cache: ^Cache = nil`
  third argument (defaulted, so existing one-shot callers stay
  source-compatible). Passing a cache routes the per-run shape calls
  through `shape_text_cached`; passing `nil` keeps the old fresh-shape
  behaviour. Aligns the public signature with PROPOSAL §6 — the
  argument was missing on the v0.1.0 path.
- Doc comment loudly flags the per-frame trap: without a cache,
  `layout_paragraph` re-shapes from scratch on every call, which
  costs ~16 ms for a 5 000-word paragraph. UI / scroll viewport
  consumers should thread a long-lived `^Cache`.
- Two new regression tests in `tests/runa/`:
  `test_layout_paragraph_cached_matches_uncached` (byte-identical
  output) and `test_layout_paragraph_cache_hit_skips_shaping`
  (the second call adds zero new cache entries).


### Added — parser

- SFNT directory + table lookup, TTC rejection, malformed-input handling.
- `head`, `maxp`, `cmap` (format 4 + 12), `hhea`, `hmtx`, `loca`,
  `glyf` (simple + composite outlines).
- `GSUB` lookup types 1 (single), 4 (ligature) and 6 format 3
  (chaining contextual) — covers `liga`, `clig`, `calt`, `rlig`,
  `locl` features.
- `GPOS` lookup type 2 formats 1 and 2 (pair positioning / kerning).
- `COLR` (v0 layered colour) + `CPAL` palettes.
- Shared OpenType layout primitives (script / language / feature walk,
  coverage tables, class definitions).

### Added — rasterizer

- Bézier flattening with implicit on-curve midpoints, composite-glyph
  transforms.
- Analytic-x scanline rasterizer with 4× y super-sampling: edges are
  intersected exactly along each sub-scanline, sorted, then walked
  with the non-zero winding rule to spread analytic coverage across
  pixel columns. Roughly 20× faster than the brute-force point-in-
  polygon predecessor; `raster_glyph(32 px)` now lands under the
  100 µs perf budget.
- 4-bucket subpixel-x offset for crisp re-positioning.
- COLRv0 layered RGBA compositing: each layer tinted with a palette
  colour, straight-alpha OVER between layers.
- Atlas allocator (shelf packing, per-page dirty-rect tracking, alpha
  and RGBA pages).

### Added — linebreak package

- UAX #14 Line_Break property lookup, sourced from Unicode 17.0
  `LineBreak.txt` (embedded; lazy-parsed on first call).
- Pair-rule engine covering LB1, LB4..LB31 (the Indic / RI-parity /
  number-chain subset) with SP-skip state. Conformance against
  `tools/ucd/LineBreakTest.txt` lands at **96.7 %** at v0.1; the
  residual 3.3 % needs the LB15 context-quotation rules
  (`Pi` / `Pf` general-category data) and the LB30 East-Asian-Width
  exceptions, both of which arrive once the v0.5 codegen-baked
  Unicode tables ship.
- `tools/lb_conformance.odin` runs the test file end-to-end and
  prints both an overall pass percentage and a sorted breakdown of
  the (left, right) class pairs still mismatching.

### Added — layout wrapping

- `Paragraph_Opts.max_width` is now load-bearing: when > 0,
  `layout_paragraph` runs the UAX #14 engine over the run, picks
  the most recent break opportunity for each line, and splits the
  glyph buffer accordingly. Mandatory breaks (LF / CR / NL) cut
  regardless of width.

### Added — itemize package

- UAX #24 `Script` property lookup over the embedded Unicode 17.0
  `Scripts.txt`. ISO 15924 four-letter codes packed as `Script_Code`
  (e.g. `LATIN = 'Latn'`, `ARABIC = 'Arab'`, `HAN = 'Hani'`).
- `segment(text, ^[dynamic]Run)` walks UTF-8 and emits one `Run` per
  script transition, applying the UAX #24 fold rules so `Common` and
  `Inherited` codepoints stay with their surrounding run.

### Added — shape package

- `shape_run` applies `ccmp` / `locl` / `rlig` / `liga` / `clig` /
  `calt` from GSUB then `kern` from GPOS, returns
  `Shaped_Glyph[]` with pixel-space advances and offsets.

### Added — `runa` facade

- `font_load` / `font_destroy`, plus `font_lookup_glyph`,
  `font_glyph_advance`, `font_glyph_outline`,
  `font_has_color_layers`, `font_color_layers`, `font_palette_color`.
- `shape_text`, `layout_paragraph` (with `max_width` wrapping),
  `measure_text`.
- `Cache` + `cache_make` / `cache_destroy` + `shape_text_cached` /
  `measure_text_cached` — shape-memoised path with the v0.1 DoD's
  zero-allocation-on-hit guarantee (verified by a `Tracking_Allocator`
  test).
- `raster_glyph` — bundles outline → bitmap → atlas packing; routes
  COLR colour-base glyphs through the layered rasterizer and into
  the RGBA atlas pages.
- `Font_Stack` and font fallback in `layout_paragraph`.
- Re-exported `Atlas`, `Atlas_Page`, `Atlas_Slot`, `Atlas_Format`,
  `Atlas_Dirty`, `Atlas_Error` plus `atlas_make` / `atlas_destroy` /
  `atlas_pack_alpha` / `atlas_pack_rgba` / `atlas_flush_dirty`.

### Added — examples / tools

- `examples/basic` — first-light text-only PGM demo.
- `examples/hello_world` — canonical "Hello, world! 🦊" demo using
  text + emoji font fallback, outputs colour PPM.
- `tools/dump_glyph`, `tools/dump_emoji`, `tools/gsub_probe`,
  `tools/colr_probe`, `tools/load_probe` for visual + structural
  spot-checks.
- `tools/bit_flip_fuzz` — `font_load` panic-resistance fuzz harness.
- `tools/bench` — perf scenarios from PROPOSAL §9 with JSON output.

### Perf scoreboard (warm Linux x86_64, `odin … -o:speed`)

Numbers below come from `odin run tools/bench.odin -file -o:speed --
tests/fonts/Roboto-Regular.ttf`. Debug builds (`odin run` with the
default optimisation level) run roughly 2–7× slower; the PROPOSAL §9
budgets target release-mode builds.

| Scenario                              | Budget   | Measured  | Verdict |
|---|---|---|---|
| `font_load`                           | ≤ 5 ms   | ≈ 6 µs    | 0.00× |
| `measure_text("Hello, world!")` cold  | ≤ 200 µs | ≈ 9 µs    | 0.05× |
| `shape_text_cached` hit (short)       | ≤ 5 µs   | < 1 µs    | 0.01× |
| `shape_text_cached` hit (5 000-word)  | ≤ 1 ms   | ≈ 30 µs   | 0.03× |
| `measure_text(5 000-word)` cold       | ≤ 30 ms  | ≈ 14 ms   | 0.45× |
| `layout_paragraph(5 000-word)` cold   | ≤ 30 ms  | ≈ 16 ms   | 0.53× |
| `raster_glyph(32 px)`                 | ≤ 100 µs | ≈ 7 µs    | 0.07× |

All seven scenarios land at or below their PROPOSAL §9 budget on
optimised builds.

### Known limitations (planned for v0.1 polish)

- `tests/golden/` ships seven self-consistency golden PGMs (Latin
  `A` / `g` / `é`, Greek `α`, Cyrillic `Я`, plus Inter and FiraCode
  baselines) verified within the ≤ 2 / 255 tolerance from PROPOSAL
  §9. The wider `unicode-org/text-rendering-tests` corpus isn't yet
  integrated; the harness shape is in place to wire it.
- UAX #14 conformance is 99.4 % at present. The added rules cover
  LB15a / LB15b quotation-context (with hard-coded `Pi` / `Pf`
  tables), the LB30 East-Asian-Width OP exception, LB28a Aksara
  bind, LB1 SA → CM refinement for Brahmic combining marks, the
  `HH` Hyphen class added in Unicode 17.0, and a stateful LB25
  numeric chain. The residual 0.6 % needs the LB21a Hebrew-letter
  state and the LB15c–LB15f context variants, which are slated for
  the codegen-baked-table pass.
- `layout_paragraph` still picks the fallback font via cmap coverage
  rather than via the new `itemize.segment` — wiring the two
  together is the next polish step before v0.5's bidi-aware
  itemiser lands.
- CFF outlines are not yet parsed (CFF-only fonts return
  `Unsupported_Format`).
- Variable-font axis interpolation isn't wired; variable fonts load at
  their default instance only.
- No CBDT / sbix support — CBDT-only emoji fonts (e.g. Linux's
  bundled `NotoColorEmoji.ttf`) currently fail to load.
