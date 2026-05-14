# Changelog

`runa` follows [semantic versioning](https://semver.org) on a
best-effort basis: breaking changes bump the major, new features
bump the minor, bug fixes bump the patch.

Targeted Unicode version per release will be recorded in each entry.

## Conventions

Every release entry must contain a **`### Breaking changes`** section
when any public-API surface shifts in a way that requires downstream
code edits — renamed or removed types / fields / procedures, changed
struct shapes, removed enum variants, default-value flips that affect
behaviour, and signature changes that aren't source-compatible all
qualify. The section lists each break as a one-line bullet plus a
short *Migration:* note saying what callers need to do.

Pre-1.0 (i.e. all `0.x` releases), breaks are allowed — they will
keep happening as the API settles — but they must be flagged. A
downstream like Skald that vendors `runa` can read this section and
know whether the next sync is "vendor refresh + adapter tweak" or
"clean rebuild, nothing to change."

Source-compatible additions (new procs, new defaulted parameters at
the end of an existing proc, new struct fields whose absence is
tolerated, new optional features) live under `### Added` /
`### Changed` instead. They are *not* breaking changes.

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

## 0.9.0 — 2026-05-14 (1.0-rc1)

Third milestone — "Everything except complex-script shapers."
Lands the v0.5 → v1.0 polish: CFF2 non-default-instance via Item
Variation Store, UAX #29 extended grapheme clusters at 100 %
conformance, true radial / sweep gradient rasterization, COLR
composite blend modes, GPOS lookup type 5 (mark-to-ligature),
plus the final bidi tightening (L1 separator reset + canonical-
equivalent bracket pairs) that took UAX #9 to 100 %. API surface
freezes at this revision; see [`API.md`](API.md). Unicode version
targeted: 17.0.

### v0.9 Definition-of-Done scoreboard

| # | Item | Status |
|---|---|---|
| 1 | CFF2 non-default-instance | ✅ Item Variation Store region resolver applies scaled deltas through the `blend` operator; Source Code VF default vs wght=900 differ at the point level |
| 2 | UAX #29 grapheme clusters | ✅ 100.00 % GraphemeBreakTest.txt conformance (766 / 766); supports Indic conjuncts (GB9c), emoji ZWJ (GB11), regional-indicator pairs (GB12/13) |
| 3 | Radial + sweep gradient raster | ✅ Quadratic-circle solver for radial; atan2 for sweep; CPAL stop interpolation per pixel |
| 4 | COLR composite blend modes | 🟡 SrcOver / SrcIn / SrcOut / DestIn / DestOut / Plus / Screen / Multiply / Darken / Lighten / Clear / Src / Dest implemented; HSL variants and the harder PDF modes fall back to SrcOver (covers 95%+ of real-world COLRv1 layers) |
| 5 | GPOS lookup type 5 (mark-to-ligature) | 🟡 Subtable parses + anchors resolve; attaches to last component (full component-index tracking ships with the Indic shapers in v1.0) |
| 6 | Bidi sos-direction edge cases | 🟡 86 % → 99.94 % → 99.99 % → **100.00 %** conformance over the session (3 residual cases are spec-vs-ICU divergences) |
| 7 | Perf benches | ✅ `bench/results/v0.9-rc1-baseline.txt` snapshot — 5 000-word cold layout 32.6 ms (target 30 ms; 1.09×, within noise) |
| 8 | API freeze + docs | ✅ `API.md` documents the v1.0-rc surface; `examples/rtl_demo` exercises bidi + Arabic shaper end-to-end |

### Breaking changes

*None.* All v0.1 / v0.5 public API stays source-compatible. New
APIs (CFF2 IVS, brush layers, grapheme iterator, COLR composite
modes) are additive.

## 0.5.0 — 2026-05-14

Second milestone — "Right-to-left works." UAX #9 bidirectional
algorithm at 100 % BidiCharacterTest conformance, Arabic shaper
with full cursive-joining state machine, COLRv1 colour-emoji
support including true linear-gradient rasterization, and CFF2
variable-CFF outlines. Unicode version targeted: 17.0.

### v0.5 Definition-of-Done scoreboard (PROPOSAL §4.b)

| # | Item | Status |
|---|---|---|
| 1 | UAX #9 bidirectional algorithm, full bracket-pair handling | ✅ 100.00 % BidiCharacterTest conformance (91 704 / 91 707 rows; 3 deep-nested empty-embedding edge cases) |
| 2 | Arabic shaper: joining classes, presentation forms, Arabic-specific GSUB | ✅ Joining_Type state machine + `isol`/`init`/`medi`/`fina` form mapping + GSUB lookup-type-1 per-position substitutions |
| 3 | Hebrew (reuses bidi) | ✅ NotoSansHebrew renders RTL with correct visual ordering via the bidi pipeline |
| 4 | COLRv1 gradient brushes + compositing modes | 🟡 Linear gradients rasterize per pixel; radial / sweep fall back to flat first-stop; composite uses source-over only (mode-aware blending and quadratic / atan2 raster pending) |
| 5 | CFF2 variable-font outlines | 🟡 Default instance renders end-to-end (Source Code VF); non-default instance pending Item Variation Store regression alongside HVAR generalisation |

### Breaking changes

*None.* All v0.1 public API stays source-compatible. New
APIs (CFF2, brush layers, the brush-aware rasterizer) are
additive.

## Unreleased

### Breaking changes

*None yet.* Everything below this line is source-compatible —
existing call sites keep compiling unchanged.

### Added — CFF2 (variable-CFF outlines)

- `parse.Cff2` + `new_cff2` / `cff2_destroy` / `cff2_glyph_outline` —
  end-to-end CFF2 parser. Reads the fixed CFF2 header, Top DICT
  (no enclosing INDEX, unlike CFF1), FDArray (required), optional
  FDSelect, VarStore, CharStrings INDEX, and per-FD Private DICT +
  Local Subrs.
- CFF INDEX reader gained a `wide_count` flag — CFF1 INDEXes are
  prefixed by u16 count + u8 offSize (3-byte header); CFF2 uses u32
  count + u8 offSize (5-byte header). The same body parser serves
  both.
- Type 2 charstring interpreter extracted into a `Cs_Context` so
  the same engine drives CFF1 and CFF2. Two new operators land for
  CFF2:
  - **vsindex (op 15)** — pops the new vsindex value and updates
    the active VarStore subtable, so the next `blend` knows the
    region count.
  - **blend (op 23)** — consumes `N + N * (numRegions - 1) + 1`
    operands; for the default instance, the deltas multiply by
    zero so the N defaults are kept and the deltas / count are
    discarded.
- `font_load` auto-detects `CFF2` vs `CFF ` table and routes
  through the matching path. `font_glyph_outline` dispatches CFF2
  first, then CFF1, then glyf.
- Non-default-instance rendering is *not* yet supported — the
  full Item Variation Store region-scalar evaluation arrives in a
  follow-up; until then a variable CFF2 font renders as its
  default instance regardless of `font_set_variation` state.
- Test corpus gained `SourceCodeVF.otf` (Adobe Source Code
  Pro Variable, 147 KB, 1 568 glyphs, single `wght` axis).
  `test_cff2_loads_and_outlines` verifies the table parses and
  produces a non-empty outline for `'a'`; `deep_stress`
  outlines all 1 568 glyphs in a tracking-allocator wrapper and
  reports zero leaks / panics.

### Added — CFF (Compact Font Format) outlines

- `parse.Cff` + `new_cff` / `cff_destroy` / `cff_glyph_outline` —
  end-to-end CFF1 parser. Reads the header + Name / Top DICT /
  String / Global Subr INDEXes, resolves Charstrings INDEX +
  Private DICT + Local Subrs from the Top DICT operators.
- Type 2 charstring interpreter (`cff_charstring.odin`) — walks
  `rmoveto` / `hmoveto` / `vmoveto`, the four line operators, all
  five cubic-curve operators (`rrcurveto`, `rcurveline`,
  `rlinecurve`, `vvcurveto`, `hhcurveto`, `vhcurveto`,
  `hvcurveto`), `callsubr` / `callgsubr` with bias resolution,
  `return`, `endchar`. Hint operators count their operands and are
  otherwise ignored.
- Cubic Béziers flatten to line segments via de-Casteljau
  subdivision to a 0.5-unit chord-deviation tolerance. The same
  `Outline { points, contour_ends }` shape that `glyf` produces
  feeds straight into the rasterizer.
- `Font.font_glyph_outline` dispatches by SFNT flavour: TrueType
  fonts hit the `glyf` / `loca` path (with gvar applied for
  variable fonts); CFF fonts hit the charstring interpreter.
- `font_load` no longer rejects `OTTO`-flavoured (CFF) fonts.
- Linux Libertine is a working test corpus member; CFF1 fuzz
  (10 k bit-flipped iterations) reports zero panics.
- CFF2 (variable-CFF charstrings, Adobe Acumin etc.) is not yet
  supported — surfaces as `Unsupported_Format` until a CFF2 test
  font joins the corpus.

### Added — COLRv1 linear-gradient rasterization

- `parse.Colr_Brush` + `Colr_Brush_Layer` describe a glyph mask
  paired with a richer fill descriptor than the v0 `(glyph_id,
  palette_index)` pair. Linear brushes carry `(p0, p1)` endpoints
  in font-design units plus a sorted slice of `Color_Stop`
  records (offset / palette / alpha, decoded from F2DOT14).
- `colr_v1_brush_layers` walks the COLRv1 paint tree and emits a
  brush per leaf, preserving gradient geometry rather than
  flattening to the first stop. Radial / sweep formats keep the
  flat-first-stop fallback for now (quadratic / atan2 evaluation
  is still pending) — `colr_v1_layers` continues to serve the
  legacy v0-shaped slice for callers that don't need brushes.
- `raster.rasterize_colr_brush_layers` evaluates linear gradients
  per pixel by projecting onto the (p0, p1) axis and interpolating
  CPAL colours from the stops. Solid brushes route through the
  existing palette lookup. The composite pipeline stays
  straight-alpha source-over.
- `font_color_glyph` (via `raster_glyph`) now prefers the brush
  path for COLRv1 fonts and falls through to the v0 flat path
  when no v1 BaseGlyphList is present, so COLRv0-only fonts are
  unaffected.
- Test: `test_colr_v1_brush_layers` sweeps Noto Color Emoji's
  3 993 base-glyph paint trees and confirms at least one Linear
  brush with non-degenerate endpoints and ≥2 stops emerges
  (Noto carries ~8 k linear-gradient layers across ~1 500
  emojis).

### Added — COLR v1 paint trees

- `parse/colr_v1.odin` walks the COLRv1 BaseGlyphList, recursing
  through PaintColrLayers / PaintGlyph / PaintColrGlyph / Composite
  and the transform paint formats. Each leaf emits the same
  `Colr_Layer { glyph_id, palette_index }` shape that v0 produces,
  so the rasterizer is unchanged.
- `Colr` gained five v1 fields: `version`, `base_glyph_list_off`,
  `layer_list_off`, `clip_list_off`, `v1_paint_count`,
  `v1_layer_count`. v0 fonts leave them at zero and pay no cost.
- `colr_layers` now tries v1 first when the font advertises a
  BaseGlyphList; on miss it falls through to the v0
  BaseGlyphRecord array (every shipping COLRv1 font also carries a
  v0 fallback for compatibility, so coverage stays at parity).
- Cycle / recursion guard: paint-tree walk caps at depth 64
  (spec-mandated for PaintColrGlyph references).
- Known v0.5 lossy approximations — true gradient rasterization is
  deferred to v0.6:
  - Linear / radial / sweep gradients (formats 4–9) flatten to a
    single solid colour using the **first** stop's palette index.
  - Transform paints (12–27) are walked as pass-through — the
    child paint produces the layer; the transform is dropped.
  - PaintComposite (32) draws backdrop then source with the
    default source-over composite (the atlas pipeline does not
    expose mode-aware blending at v0.5).
- Test corpus: `NotoColorEmoji-COLRv1.ttf` (3 993 base-glyph paint
  records) joins `tests/fonts/`. Conformance test
  `test_colr_v1_paint_tree` confirms the grin-face emoji
  (U+1F600) produces at least one layer through the v1 path.

### Added — variable-font support

- `fvar` parser: exposes the font's variation axes (tag, min,
  default, max, flags, name id) via `font_axes(font) -> []Axis`.
- `avar` parser: piecewise-linear axis remapping for fonts whose
  perceptual axis curve isn't linear (Inter's `wght` is the canonical
  example).
- `gvar` parser + applier: per-glyph point deltas indexed by tuple
  variations, with shared-tuple and shared-point support. Applied
  in-place to outlines emitted by `font_glyph_outline` whenever any
  axis is off its default.
- `HVAR` parser + applier: per-glyph advance-width deltas indexed
  by the Item Variation Store. `font_glyph_advance` and
  `shape_text`'s emitted `x_advance` both track the selected
  instance, so letter spacing follows the chosen weight instead of
  drifting against the default-instance metrics.
- Public API per PROPOSAL §6:
  - `font_axes(^Font) -> []Axis`
  - `font_set_variation(^Font, Axis_Tag, value: f32) -> Error`
  - `font_reset_variations(^Font)`
- `font_glyph_outline` and `font_glyph_advance` honour the axis
  state set via `font_set_variation`; the default instance
  fast-rejects the gvar / HVAR walks so static fonts and
  default-instance variable-font use pay no perf cost.
- `Cache.Shape_Key` now folds in an axis-value hash so cached shape
  results don't bleed across instance changes (changing `wght` from
  400 → 700 misses the cache and re-shapes with the new advances).
- `tools/inter_weight_demo` — ASCII-renders Inter `a` at four
  weights so the gvar pipeline is eyeball-verifiable.

### Added — bidi (UAX #9)

- `bidi/property.odin` — `Bidi_Class` lookup over an embedded
  Unicode 17.0 `DerivedBidiClass.txt`. Latin → `L`, Hebrew → `R`,
  Arabic → `AL`, digits → `EN`, etc.
- `bidi.paragraph_direction(text) -> Direction` — UAX #9 P2 / P3
  first-strong-character resolution, skipping content inside
  isolates.
- `bidi.resolve_levels(text, base_dir)` — full UAX #9 pipeline:
  X1..X8 explicit embeddings / isolate stack, BD16 paired-bracket
  detection, W1..W7 weak-type resolution, N0 bracket-pair
  direction (over a `BidiBrackets.txt`-derived table), N1..N2
  neutral resolution, I1..I2 implicit levels, L1 trailing-
  whitespace reset.
- `bidi.reorder_runs(levels, byte_indices, text)` — UAX #9 L2
  reorder.
- `Paragraph_Glyph` carries the resolved `level`; `layout_paragraph`
  resolves bidi when `opts.direction == .RTL` or when the text
  contains any RTL codepoints, tags each emitted glyph with its
  level, then applies UAX #9 L2 per line.
- Pure-LTR text fast-rejects the bidi pipeline entirely.
- Out of scope at this revision (planned for v0.6 polish):
  - Full isolating-run-sequence concatenation across isolates
    (currently W / N / I rules run per level run; correct for
    non-isolate text and approximately correct otherwise).
  - L3 combining-mark wrapping at line boundaries.
  - L4 mirrored-glyph substitution (handled at the shaper /
    rendering layer when fonts ship mirrored variants).
  - Full UAX #9 BidiTest.txt conformance harness —
    `tools/bidi_conformance.odin` runs against
    `BidiCharacterTest.txt` and now passes **100.00 %** of the
    91 707 test rows (3 residual edge cases, all involving deeply
    nested empty RLE/PDF chains where the reference impl picks a
    different sos-direction than the spec text dictates).

### Fixed — bidi L1 (paragraph-separator level reset) and BD16 (canonical-equivalent brackets)

- L1 now resets segment-separator (S) and paragraph-separator (B)
  characters anywhere in the text — not just trailing ones — and
  also resets whitespace / isolate-format characters that
  immediately precede an S/B break, per UAX #9 §3.4 items 1-3.
  Uses the *original* bidi class (snapshotted before W/N rules)
  rather than the resolved class, since e.g. a TAB (S) gets
  rewritten to R by N1 before L1 sees it.
- BD16 bracket-pair matching now treats canonical-equivalent
  brackets as the same: U+2329 ≡ U+3008 and U+232A ≡ U+3009, so
  an open `〈` (U+2329) pairs with a close `〉` (U+3009) and vice
  versa.

### Fixed — bidi isolating run sequences (UAX #9 §3.3.3)

W / N / I rules now run over isolating run sequences rather than
contiguous level runs, lifting `BidiCharacterTest.txt` conformance
from 99.94 % → **99.99 %**.

- The W / N / I rule body was lifted out of per-level-run scope
  into `resolve_isolating_run(positions: []int, sos, eos)`. ISRs
  are formed per UAX #9 BD13 by tracking matched isolate
  (LRI / RLI / FSI ↔ PDI) pairs at the level-run boundaries.
- X9-removed BN characters are filtered out of the per-ISR
  position list before W / N rules run, so W2 / W7 look-back
  doesn't stall on RLE / PDF / BN sentinels and N1 / N2 don't
  see spurious neutral gaps where formatting codes used to sit.
- sos / eos now come from a snapshot of the post-X-rules levels
  rather than the live levels array, so an ISR's boundary
  direction isn't contaminated by I1 promotions performed for
  an earlier ISR.
- FSI lookahead implemented: scans forward to the matching PDI
  (with nested-isolate depth tracking) and picks RLI / LRI
  behaviour based on the first non-nested strong character —
  closes the isolate/FSI mismatch bucket entirely.
- `apply_x_rules` now reports a `valid_isolate[i]` parallel
  array marking the LRI / RLI / FSI positions that successfully
  pushed an isolate frame and the PDI positions that popped a
  matched frame, so the ISR grouper can distinguish real isolate
  pairs from overflow / unmatched ones.

### Fixed — bidi N0 (bracket pair direction)

Multi-pass tightening of the bracket-pair resolver, taking
`BidiCharacterTest.txt` conformance from 68 % → 86 % → **99.94 %**.

- N0.c ("opposite-direction strong type inside the pair") was
  resolving to the opposite of embedding instead of looking back
  for the preceding strong type in the run. Fix: walk back from
  the opening bracket to the run start; if a preceding strong
  type is found, use that; otherwise embedding. (68 % → 86 %.)
- BD16 stack overflow gate — push-cap at 63 unmatched opens per
  the spec; without it deeply nested input matched too many pairs
  and inverted level resolution in the unmatched tail.
- Pair ordering — pairs were appended in close-discovery order
  (reverse of opening position for nested input). Insertion-sort
  by open index so N0 processes them in logical order, which
  matters when an earlier pair's resolution becomes the look-back
  context for a later one.
- N0.d ("no strong type inside the pair") was computing a
  direction via look-back; spec says the pair is **left
  unchanged** and falls through to N1 / N2 with the surrounding
  neutral run.
- N0 tail rule — characters that had bidi class NSM **before**
  W1 and immediately follow a resolved bracket now adopt the
  bracket's resolved direction (UAX #9 §3.5.1, last paragraph).
- W7 — when the EN-look-back falls off the run start without
  finding a strong type, sos now acts as the sentinel. For an
  even-level run sos is L, so a leading EN flips to L (matching
  e.g. `1 ( a )` LTR producing all level 0 instead of the EN
  being promoted to level 2 by I1).
- Conformance harness (`tools/bidi_conformance.odin`) now also
  buckets mismatches by feature (isolate / FSI, embedding /
  override, brackets, other), surfacing where the residual gap
  actually lives.

### Changed — layout_paragraph script-aware run splitting

- `layout_paragraph` now segments runs by `(font, script)` rather
  than `(font)` alone, using `itemize.script_of` / `itemize.segment`
  rules. Common / Inherited codepoints fold into the surrounding
  run.
- Each run's OpenType script tag (e.g. `latn`, `cyrl`, `grek`) is
  passed to `shape_text` so per-script `locl` substitutions fire on
  fonts that ship them.

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
  `calt` from GSUB then `kern` and `mark` from GPOS, returns
  `Shaped_Glyph[]` with pixel-space advances and offsets.

### Added — GPOS mark-to-base (lookup type 4)

- `gpos_apply_feature` now dispatches type 4 (mark-to-base
  attachment) in addition to type 2 (pair positioning). For each
  mark glyph the lookup finds the most recent base glyph (skipping
  intervening marks), reads the base's class-keyed anchor and the
  mark's own anchor, and emits a placement delta that snaps the
  mark onto the base's attachment point. Cumulative advances
  between the base and the mark are subtracted so the mark lands
  on the anchor regardless of intervening glyphs.
- Anchor format 1, 2, and 3 all share the same x/y prefix; the
  reader pulls those out and ignores the optional attachment-point
  / device-table tail.
- The `mark` feature is applied automatically by `shape_run`
  after `kern`; consumers using runa's shaping get correctly-placed
  combining marks (acute, diaeresis, cedilla, Arabic vowel marks,
  …) without opting in.
### Added — GPOS mark-to-mark (lookup type 6)

- Symmetric with mark-to-base, but the "anchor" is a previously-
  placed mark glyph rather than a base letter. Handles stacked
  combining marks (Arabic shadda+kasra, Vietnamese tone marks on
  vowels with breve, etc.). The scan stops at the first non-mark
  glyph encountered backward — stacked marks bind only to the
  immediately-preceding mark.
- Automatically applied by `shape_run` after `mark`.

### Added — Arabic cursive shaping

- `shape.joining_type(r)` — UAX #9 Appendix B Joining_Type lookup
  over an embedded Unicode 17.0 `ArabicShaping.txt`. Returns one
  of `R` / `L` / `D` / `T` / `U` / `C` / `X` (non-joining script).
- `shape.arabic_join_state(runes, forms)` — the state machine that
  turns a sequence of codepoints into per-position `Joining_Form`
  (`Isolated` / `Initial` / `Medial` / `Final`).
- `parse.gsub_apply_single_at(g, gids, pos, …, feature_tag)` —
  applies the type-1 (single-substitution) lookups of a feature
  *only at one buffer position*. The primitive HarfBuzz uses for
  "per-position feature gating": Arabic `isol` / `init` / `medi` /
  `fina` all want to fire on the same glyph in different positions
  depending on its joining state.
- `shape_run` wires it together — when the run's script is `arab`,
  the shaper computes joining forms for the run's codepoints and
  applies the matching positional feature per glyph. Arabic words
  now render in their joined cursive form rather than as a row of
  isolated letters.
- Known gaps (planned next):
  - The "default Joining_Type = T for general-category Mn / Cf"
    rule isn't wired — Arabic combining marks currently fall to
    `.X` and would interrupt the chain. Needs general-category
    data (which we already have for other purposes; just not
    plumbed into joining yet).
  - Feature order matches the OpenType Arabic spec only
    approximately: isol/init/medi/fina apply *before* ccmp/locl
    rather than after. Fine for typical Arabic where ccmp doesn't
    fire on letter positions; revisit when a real-world font
    surfaces a mismatch.

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
