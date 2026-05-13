# Pure-Odin Modern Text Engine — Project Proposal

**Status:** proposal / RFC. No code yet.
**Audience:** the engineer (or coding agent) who picks this up cold and starts designing/building.
**Sponsor:** Lee (`lee@focus-sb.co.uk`) — author of [Skald](https://github.com/BuLEEto/Skald), the Elm-architecture GUI framework for Odin.
**Date:** 2026-05-13

---

## 1. One-liner

A modern, pure-Odin text engine — text **parsing → itemization → shaping →
line-breaking → rasterization** — useful as a standalone library across the
Odin community, designed first to replace Skald's `vendor:fontstash` +
`stb_truetype` path.

Think "cosmic-text for Odin", but written from scratch in idiomatic Odin
with zero C dependencies in the v1.0 target.

---

## 2. Why this exists

Skald currently uses Odin's `vendor:fontstash` (a port of fontstash) layered
on top of `stb_truetype` for glyph outlines. That stack is a *glyph atlas
+ basic horizontal kerning*, nothing more. It cannot:

- **Shape complex scripts** — Arabic joining/cursive forms, Devanagari
  conjuncts, Thai/Khmer cluster reordering, Hebrew/Arabic bidirectional
  layout.
- **Break lines per the Unicode standard** — UAX #14 line-breaking with
  proper handling of Chinese/Japanese/Korean breakpoints, hard breaks,
  combining marks, regional indicators.
- **Render colour emoji** — modern fonts use COLRv1 (gradient + layer +
  compositing), CBDT (bitmap), or sbix; fontstash only knows monochrome
  alpha glyphs. Skald shows tofu for `🦊`.
- **Apply OpenType features** — ligatures (`fi`, `fl`, `→`), kerning via
  GPOS pairs, contextual alternates, stylistic sets.
- **Subpixel-position glyphs** — fontstash quantises to integer pixels;
  long passages of text drift visibly at small sizes.

These gaps are real for shipped Skald apps:
- The Limn showcase app needs `Ctrl+,` to mean *preferences* — that works
  now, but a Limn-style note-taking app would need Arabic/Devanagari
  rendering for international users.
- Lee's `boc-next` agent UI is a chat app — every chat app needs emoji.
- A code editor built on Skald would need ligatures (`!=`, `=>`, `->`)
  to look right with fonts like Fira Code / JetBrains Mono.

These items already sit on Skald's *post-1.0 backlog* as tasks #193 (bidi
+ shaping) and #202 / #203 (colour emoji, emoji picker). The framework
ships 1.0 without them. **This proposal is the long-term fix.**

---

## 3. Vision

A standalone Odin library — call it **`runa`** for now (see §13 for name
options) — that any Odin project can drop in to get production-quality
text rendering.

**Out of scope** for *the library*: GUI widgets, text input/editing
cursors, IME (input method editor) handling, clipboard, focus. Those are
the consuming application's job. The library produces *positioned,
rasterized glyphs against an atlas*. The consumer composites them into
their UI.

**In scope:**
- Read OpenType / TrueType / variable fonts from `[]u8`.
- Itemize a UTF-8 paragraph into runs by script + direction + font.
- Shape each run with GSUB/GPOS lookups (ligatures, kerning, mark positioning).
- Apply UAX #9 bidirectional algorithm (paragraph → visual order).
- Break paragraphs into lines per UAX #14.
- Rasterize glyph outlines (`glyf`, `CFF` at v0.1; `CFF2` at v0.5)
  into a CPU-side atlas.
- Composite COLRv0 layered colour glyphs into the atlas at v0.1
  (gradients + compositing modes from COLRv1 land in v0.5).
- Cache by `(font, glyph_id, size, subpixel_offset)`.
- Hand back: per-glyph atlas-rect + position + RGBA hint (mono vs colour).

**Explicit non-goals:**
- *Font hinting* (TrueType bytecode interpreter — `prep`/`fpgm`/`cvt`).
  Grayscale anti-aliasing + stem-darkening is good enough for 2026
  high-DPI displays. Skald already does this in its WGSL shader.
- *Font subsetting / generation*. Read-only.
- *System font enumeration* (Windows DirectWrite / macOS Core Text /
  fontconfig). At v1.0 the app hands the library a `[]u8` of the font.
  A `fontdb`-equivalent companion library can come later as `runa-system`.
- *Hyphenation* (Knuth-Liang). Line breaks happen at UAX #14 boundaries
  only at v1.0.
- *Knuth-Plass paragraph justification.* Left-align + center + right +
  ragged-right at v1.0; "justify with stretch" is post-1.0.
- *SVG-in-OpenType* and Apple's `morx`/`kerx` AAT tables. Most Apple-only
  fonts have OpenType fallback tables that work.
- *Pre-2010 font formats*: Type 1, bitmap-only `EBDT`, etc.

---

## 4. Phased roadmap

### v0.1 — "It renders English / Cyrillic / Greek and beats fontstash"

The MVP. Skald can switch off fontstash at this milestone and lose nothing
for Latin-script apps.

- OpenType parser: `cmap`, `head`, `hhea`, `hmtx`, `maxp`, `name`, `OS/2`,
  `post`, `glyf` (TrueType outlines), `CFF` (PostScript outlines — CFF2
  punted to v0.5), `GDEF`, `GSUB`, `GPOS`, `kern`, `COLR` (v0 layered),
  `CPAL`, `fvar`, `avar`, `gvar`, `HVAR`, `MVAR`, `STAT` for variable-
  font axes. `avar` is mandatory: without it user→normalized axis
  coords for non-linear axes are wrong.
- Shaper: GSUB (`liga`, `clig`, `calt`, `locl`, `rlig`), GPOS pair kerning,
  GPOS mark-to-base. **LTR only.** No Arabic state machine yet.
- Itemizer: split by script (UAX #24) + per-codepoint font fallback chain.
- Rasterizer: scanline rasterizer for `glyf` / CFF outlines → 8-bit alpha
  atlas slots. Subpixel offsets (4 quantisation steps).
- Colour glyphs: COLRv0 layered glyphs (flat-colour layer compositing
  via `CPAL`) rasterized to RGBA atlas slots. Falls back to mono if
  `COLR` absent. COLRv1 (gradients, compositing modes) deferred to v0.5
  — v0 is the prerequisite layered-glyph table that v1 extends, and
  every COLRv1 font also ships a v0 fallback, so v0-only renders all
  emoji correctly minus gradients.
- Public API: see §6.
- Atlas: dynamic 8-bit + 32-bit atlases, growth + eviction policy. Returns
  GPU-friendly UV rects; consumer owns the GPU upload.

**Skald migration trigger:** at v0.1 the Skald team can swap `text.odin`'s
fontstash calls for `runa` calls behind an internal facade, ship as
`Skald 1.1`, and immediately get COLRv0 layered emoji + ligatures +
subpixel positioning. Everything else stays the same for app authors.
COLRv1 gradient emoji land in Skald 1.2 when runa v0.5 ships.

### v0.5 — "Right-to-left works"

- UAX #9 bidirectional algorithm, full bracket-pair handling.
- Arabic shaper: joining classes, presentation forms (`init`/`medi`/`fina`/`isol`),
  Arabic-specific GSUB lookups (`ccmp`, `isol`, `fina`, `medi`, `init`,
  `rlig`, `calt`).
- Hebrew (mostly LTR-mirrored; reuses bidi).
- COLRv1 gradient brushes + compositing modes (extends v0.1's COLRv0
  layered path; affects gradient-heavy emoji sets like the current
  Noto Color Emoji).
- CFF2 (variable-font CFF outlines — needed for some Adobe variable
  fonts).

### v1.0 — "Complex scripts ship"

- Indic shapers: one module per family, all sharing a shaper-state core —
  Devanagari, Bengali, Tamil, Telugu, Kannada, Malayalam, Gurmukhi,
  Gujarati, Odia.
- Thai / Lao / Myanmar / Khmer: cluster + line-break support. (Thai needs
  a dictionary for word breaks; ship a small one.)
- UAX #29 grapheme-cluster iteration (caret movement, click hit-testing).
- API freeze, semver, docs site.

### Post-v1.0 (separate releases)

- `runa-system`: OS font enumeration (Windows DirectWrite, macOS CTFont,
  Linux fontconfig).
- `runa-edit`: cursor, selection, IME helpers — for editor/text-input
  authors who want a higher-level building block.
- Knuth-Plass justification.
- Hyphenation (Liang patterns).
- TrueType hinting interpreter (only if real demand emerges; modern
  displays don't need it).

---

## 5. Architecture

Six top-level modules, mirroring the cosmic-text split. Each is a
single Odin package; they can live in one repo as sibling directories.

```
runa/
├── parse/     # OpenType table parser. Reads []u8, returns lazy views.
├── shape/     # Per-run GSUB/GPOS shaper. Output: positioned glyph IDs.
├── itemize/   # UTF-8 → runs by script (UAX #24) + bidi level + font.
├── bidi/      # UAX #9 algorithm. v0.5+; stub at v0.1.
├── linebreak/ # UAX #14 break opportunities + width-fit line splitter.
├── raster/    # Outline + COLR → atlas slots. Atlas allocator.
└── runa.odin  # Public facade: `layout_paragraph`, `measure_text`, etc.
```

### Layering rules

- `parse` depends on nothing.
- `shape` depends on `parse`.
- `itemize` depends on `parse` (font lookup) + Unicode data only.
- `bidi` depends on Unicode data only.
- `linebreak` depends on Unicode data only.
- `raster` depends on `parse` (glyph outline data, COLR layers).
- The facade in `runa.odin` orchestrates the others.

Modules talk via simple value types (slices, structs). No interior
mutability hacks; no global state. Every entry-point takes an explicit
allocator.

### Caching strategy

- Per-run shaping is the slow path. Cache keyed by `(font_id, run_text,
  size, script, direction, features_hash)` → `[]Shaped_Glyph`.
- Glyph atlas is keyed by `(font_id, glyph_id, size, subpixel_x_bucket)`.
- Both caches are app-owned: `runa.Cache` is a struct the consumer
  threads through. Library never reaches for a global. This matches
  Skald's "no global state outside the Renderer" convention.

---

## 6. Public API sketch (Odin)

Names are illustrative; final API may differ. The shape is what matters.

```odin
package runa

// Error is the single error type all fallible procs return. `(T, Error)`
// is the convention — `Maybe(T)` is NOT used in the public surface.
// `Error.None` (zero value) means success.
Error :: enum u8 {
    None,
    Out_Of_Memory,
    Invalid_Table,         // malformed OpenType table
    Unsupported_Format,    // e.g. AAT-only font, no GSUB/GPOS
    Glyph_Not_Found,
    Axis_Out_Of_Range,
}

// Identifier types. All are `distinct` so they don't accidentally cross
// boundaries with raw integers.
Font_ID    :: distinct u32     // assigned by Cache on first use
Glyph_ID   :: u16              // OpenType glyph index, native size
Axis_Tag   :: distinct u32     // 4-byte OT tag, big-endian-packed
OT_Feature :: distinct u32     // 4-byte OT feature tag (e.g. 'liga')

Direction :: enum u8 { Auto, LTR, RTL }
Align     :: enum u8 { Start, Center, End }

// Language is a BCP-47 tag held by value — short tags fit inline.
Language :: distinct [12]u8

// A loaded font — parsed once, referenced by many calls. The struct
// owns its parsed table views into the original `[]u8` data; the data
// slice must outlive the Font.
Font :: struct {
    // Public-readable fields (don't write):
    units_per_em: u16,
    num_glyphs:   u16,
    ascent:       f32,  // in font units; multiply by size/upem
    descent:      f32,
    line_gap:     f32,
    // ... opaque parser state below
    _allocator:   runtime.Allocator,  // captured at load; reused by destroy
    _tables:      Table_Index,
}

font_load :: proc(data: []u8, allocator := context.allocator) -> (Font, Error)

// Frees parser state. Uses the allocator captured at `font_load` time;
// caller does NOT pass it again. The source `data` slice is NOT freed
// — caller owns it.
font_destroy :: proc(f: ^Font)

// Variable-font axis lookup. Returns the font-defined axes (wght, wdth,
// opsz, slnt, ital, plus any custom axes).
font_axes :: proc(f: ^Font) -> []Axis

// Sets a variation axis. Out-of-range values return Axis_Out_Of_Range
// (no silent clamping — surprise clamping is a well-known footgun).
font_set_variation :: proc(f: ^Font, axis: Axis_Tag, value: f32) -> Error

// Font fallback chain. Caller-owned slice — runa never mutates this and
// never frees it. Use `[]^Font` (not `[dynamic]^Font`) so the lifetime
// is obviously the caller's: build it once on the stack, hand it to
// `Paragraph_Opts`, forget it.
Font_Stack :: distinct []^Font

// One shaped, positioned glyph ready to draw.
Shaped_Glyph :: struct {
    font_id:    Font_ID,
    glyph_id:   Glyph_ID,
    cluster:    u32,    // byte index back into source UTF-8
    x_advance:  f32,
    y_advance:  f32,    // 0 for horizontal scripts
    x_offset:   f32,
    y_offset:   f32,
    is_color:   bool,   // true → atlas slot is RGBA, not alpha
}

// One laid-out line of a paragraph.
Line :: struct {
    glyphs:   []Shaped_Glyph,
    baseline: f32,
    width:    f32,
    height:   f32,
}

// Layout opts. All fields have sensible zero-value defaults; the
// minimum useful call is `Paragraph_Opts{ fonts = my_fonts, size = 14 }`.
Paragraph_Opts :: struct {
    fonts:       Font_Stack,
    size:        f32,
    line_height: f32,           // 0 → metrics-derived (ascent + descent + line_gap)
    max_width:   f32,           // 0 → no wrapping
    align:       Align,         // .Start / .Center / .End
    direction:   Direction,     // .Auto detects via bidi
    features:    []OT_Feature,  // app overrides; nil → default OT features for the script
    language:    Language,      // for `locl` feature; zero → no locl substitution
}

// The atlas holds rasterised glyph bitmaps. Caller owns the GPU-side
// texture and copies from `pages` after `dirty_rects` go non-empty.
Atlas :: struct {
    pages_alpha: []Atlas_Page,  // 8-bit-alpha pages (mono glyphs)
    pages_color: []Atlas_Page,  // RGBA pages (COLRv0/v1 layered emoji)
    dirty_rects: [dynamic]Atlas_Dirty,  // since last `atlas_flush`
}

Atlas_Page :: struct {
    width, height: u16,
    format:        Atlas_Format,  // .Alpha8 / .RGBA8
    pixels:        []u8,
}

// One slot inside an atlas page, returned by `raster_glyph`.
Atlas_Slot :: struct {
    page_index: u16,
    uv_rect:    [4]f32,  // {u0, v0, u1, v1} — normalised
    px_size:    [2]u16,  // glyph bitmap size in pixels
    bearing:    [2]f32,  // offset from pen position to top-left
    is_color:   bool,
}

// The one-call API for "paragraph in, lines out". `(lines, err)` —
// caller checks err before reading lines.
layout_paragraph :: proc(
    text:  string,
    opts:  Paragraph_Opts,
    cache: ^Cache,
    allocator := context.allocator,
) -> (lines: []Line, err: Error)

raster_glyph :: proc(
    font:     ^Font,
    glyph_id: Glyph_ID,
    size:     f32,
    subpx_x:  u8,        // 0..3
    atlas:    ^Atlas,
) -> (slot: Atlas_Slot, err: Error)

// Quick measurement without full layout (single line, no wrapping).
measure_text :: proc(
    text:  string,
    opts:  Paragraph_Opts,
    cache: ^Cache,
) -> (width, height: f32)
```

The shape of `Paragraph_Opts` matters: it's the contract Skald (and
other consumers) will fill in once per `text()` call. Keep it small,
keep field names short.

---

## 6a. API quality bar — non-negotiable

The point of writing this library in Odin is to *fix* the things that
make text engines miserable to integrate. The agent picking this up
has to internalise these rules before the first line of code:

1. **One string type: `string` (UTF-8).** No `[]rune`, no `cstring`,
   no `wchar_t`. Cluster indices are byte offsets back into the
   caller's UTF-8 buffer. Iteration helpers (graphemes, codepoints)
   live in `runa/iter` and return spans, never copies.
2. **No global state, ever.** No package-level `var cache`, no
   thread-local atlas, no init() function with side effects.
   `Font`, `Cache`, `Atlas` are all explicit value types the caller
   owns. This is Skald's convention and it's the right one.
3. **Explicit allocator on every entry point** that may allocate.
   `proc(..., allocator := context.allocator)`. The caller controls
   memory; the library never reaches for the global heap.
4. **Errors are values.** `(T, Error)` returns everywhere, never
   panic. Malformed font input returns `Error.Invalid_Table`, not a
   crash. The parser is hardened against the OpenType attack surface.
5. **Public types are structs, not opaque handles.** `Font` is a real
   struct the caller can inspect. No `Font_Handle :: distinct rawptr`
   FFI-style indirection. The library is in-process Odin; act like it.
6. **No callbacks-from-library.** The library never calls back into
   user code. Output is values returned from procs, not "register a
   handler." This eliminates the entire class of "what allocator am
   I in" bugs.
7. **Measurement is independent of rasterization.** You can call
   `measure_text` without ever touching an atlas. Layout returns
   positioned glyph IDs; rasterization is a separate later call. The
   consumer decides when to actually pay for glyph bitmaps.
8. **One way to do each thing.** No `layout_paragraph_v2`. No deprecated
   helpers kept "for compat." If a thing turns out to need two shapes,
   pick the better one, version-bump, document the change in CHANGELOG.
9. **Per-call options are structs, not 14-argument procs.**
   `Paragraph_Opts` is a struct with sensible zero-value defaults. A
   caller who wants "left-aligned, no wrap" passes `{}`.
10. **Public API procedures get full doc comments.** Every public proc
    has a multi-line doc block that says (a) what it does, (b) when
    the caller would want it, (c) what the failure modes are. Match
    Skald's doc-comment style.
11. **Public types get full doc comments.** Same rule. A struct field
    that needs explanation gets a `// inline comment` after the field.
12. **Thread safety is documented.** Each public proc states whether
    it's safe to call concurrently. Default: safe iff the `Cache` it
    touches isn't shared without synchronisation. Document explicitly,
    don't make the caller guess.

A consumer who has never read the source should be able to write a
working integration from reading the `runa.odin` facade alone.

## 7. Rendering quality without hinting / AAT / Knuth-Plass / etc.

Reasonable concern: "if you skip hinting and these other features,
won't the text look bad?" Short answer: **no, not for app UIs in
2026.** Each item, honestly:

### Hinting (TrueType bytecode interpreter)

Hinting snaps glyph stems to the pixel grid at small sizes. It was
critical in the era of 96-DPI 1024×768 displays. In 2026:

- **High-DPI displays are the baseline.** macOS retina (2x), Windows
  150% / 200% scaling, GNOME 1.25–2x fractional scaling — Skald's
  whole DPI contract (`project_dpi_scaling`) assumes scale > 1.
  Hinting matters less at every pixel-doubling.
- **Apple has never used TrueType bytecode hinting.** macOS shipped
  grayscale AA + stem-darkening from day one (OS X 10.0, 2001) and
  has stayed there for 25 years. The hinting interpreter was a 2010
  addition to FreeType (post Apple patent expiry), not something
  macOS adopted. Nobody complains macOS text looks bad; the opposite,
  it's the reference for "clean."
- **Firefox / Chrome on macOS disable hinting** even when the font has
  bytecode. They lean on grayscale + stem-darkening.
- **Skald already does stem-darkening in the WGSL shader**
  (`project_text_gamma_stem_darkening` memory). The infrastructure
  for "hinting-quality output without hinting" is already in place.
- **Hinting is a security and complexity nightmare.** TrueType
  bytecode is a Turing-complete stack VM with a long string of
  memory-safety CVEs (CVE-2010-2520 heap overflow in `Ins_SHZ`,
  CVE-2025-27363 OOB write in variable-font TT instruction handling
  — the latter exploited in the wild) and ~10 000 lines of
  interpreter in FreeType. Implementing it in Odin is months of work
  to add a
  feature most users would not notice on a high-DPI display.

The honest concession: at 1× on 1080p with 8pt body text, hinted
TrueType (FreeType `light` hint) reads slightly crisper than pure
grayscale. The gap is small and shrinking; we ship grayscale + stem
darkening and accept the trade.

### Subsetting

Subsetting is the process of *writing* a smaller font file that only
contains the glyphs your document uses (e.g., for web fonts). It is
not a rendering feature. A read-only text engine doesn't need it.
If a user wants subsetted fonts, they pre-process with `pyftsubset`
or similar before bundling. No rendering quality loss.

### System font enumeration

Finding "Arial" on Windows / "Helvetica" on macOS / fontconfig on
Linux. This affects *convenience*, not quality:

- The app has to `#load` or read fonts from a known path instead of
  asking the OS for them.
- Skald already bundles InterVariable and doesn't enumerate.
- Future `runa-system` companion library can add this when there's
  real demand.

Quality at the glyph level is identical either way.

### AAT (Apple Advanced Typography — `morx`, `kerx`)

Apple's pre-OpenType shaper tables. Reality check:

- Every modern Apple font (San Francisco, the entire system font set
  since 2015) ships **OpenType GSUB/GPOS tables in parallel** for
  cross-platform compatibility. AAT-only fonts are a tiny rounding
  error — mostly ancient Apple system fonts from the 1990s that
  nobody bundles in modern apps.
- HarfBuzz supports AAT precisely because Apple's *system* renderer
  picks AAT first when both are present, and HarfBuzz wants to match
  pixel-for-pixel. We don't need that constraint.
- Net effect: with well-built modern fonts, lacking AAT is invisible.

### Knuth-Plass justification

The TeX-style "consider all possible line breaks and minimise total
badness" algorithm. Produces the famous tight-but-not-too-tight
columns in books and LaTeX. Without it, we use first-fit (greedy,
break at first opportunity that fits). Reality:

- **First-fit is what every browser uses for justify-text.** Chrome,
  Firefox, Safari, every WebView. Users have never noticed.
- **App UIs are 99% left-aligned ragged-right.** Skald defaults to
  `.Start` cross-align. Justified text in app UI is rare and usually
  wrong (it makes scanning harder).
- Knuth-Plass adds maybe 1.5× shaping cost per paragraph for a
  visual improvement most users can't articulate.

If a Skald user wanted true typography-grade justification, they'd be
the first to ask, and we'd ship a v1.x add-on. Until then: skip.

### What we *don't* skip

To be clear, the things that *do* affect perceived quality on the
modern web — we cover all of them:

- **Subpixel positioning** (4 buckets) — text drifts smoothly during
  scroll/animation, no jitter.
- **Stem darkening** — text reads thick on light backgrounds.
- **Proper grayscale AA** with sRGB-aware blending.
- **Ligatures and kerning via GPOS** — `fi`, `fl`, programming-font
  arrow ligatures (`->`, `=>`, `!=`).
- **Colour emoji via COLRv0 (v0.1) → COLRv1 (v0.5)** — layer
  compositing for v0; gradient brushes and compositing modes for v1.
  Either way: real coloured emoji, not mono fallback.
- **Variable-font axes** — weight, slant, optical size all live.
- **Unicode-correct line breaks** — UAX #14 with East-Asian-Width.
- **Cluster-aware caret movement** (v1.0) — combining marks travel
  with their base.

The skipped features are the ones the modern web has *also* decided
are not worth their complexity in 2026. We are not lowering the bar;
we are matching it.

## 7a. Unicode data strategy

UAX #9 (bidi) and UAX #14 (linebreak) need real data:

- `Bidi_Class` from `DerivedBidiClass.txt`
- `Bidi_Paired_Bracket` from `BidiBrackets.txt`
- `Line_Break` from `LineBreak.txt`
- `East_Asian_Width` (UAX #11) — affects linebreak
- `Script` (UAX #24)
- `General_Category`
- `Extended_Pictographic` (emoji segmentation)
- `Grapheme_Cluster_Break` (UAX #29) — caret movement at v1.0
- `Word_Break` (UAX #29) — word-by-word caret motion at v1.0
- `Indic_Syllabic_Category` + `Indic_Positional_Category` — required
  by v1.0 Indic shapers
- `Bidi_Mirrored` — for bidi visual order

Strategy:

1. A standalone Odin tool (`tools/gen_unicode.odin`) parses
   pre-downloaded UCD files from `tools/ucd/` and packs the tables
   into compact 2-stage tries (`u8` block index + `u8` block data),
   written out as Odin source: `package unicode_data;
   bidi_class_block_idx :: [...]u8{ ... }`.
2. The tool is run **manually** when adopting a new Unicode version.
   It does NOT run at build time and never touches the network. The
   UCD source `.txt` files are committed to `tools/ucd/` alongside
   the generated output; bumping Unicode is a deliberate PR.
3. Generated files live in `runa/data/` and are committed to the
   repo. Build never downloads, never generates — `odin build` only
   reads what's already on disk.
4. Expected size: ~50–200 KB packed across all tables. Negligible.
5. Pinned Unicode version: **Unicode 17.0** (current as of 2025-09;
   `LineBreakTest.txt` header dated 2025-07-24). Document which
   Unicode version a given `runa` release targets in `CHANGELOG.md`.

Don't hand-write these. Don't `core:strconv` them at boot. Generate,
commit, load via `#load` if `[]u8` or compile-in if Odin source.

---

## 8. Skald integration plan

Skald's font surface area is tiny — one file, `skald/text.odin` (912
lines, 46 fontstash calls). The migration path:

### Step 1 — facade

Introduce `runa` as a build-time dep. Inside `text.odin`, wrap
`measure_text`, `font_add_fallback`, `font_load_*`, and the glyph-atlas
upload path behind a private interface. fontstash stays for a release.

### Step 2 — flip the default

`measure_text` and rasterisation route through `runa`. fontstash code
stays compiled in behind a `when SKALD_FONTSTASH` build flag so apps
in the wild can bisect regressions.

### Step 3 — delete fontstash

After one Skald release with `runa` as the default, remove `vendor:fontstash`
+ `stb_truetype` entirely. `text.odin` shrinks to a thin adapter.

### What apps see

App-level API stays identical for the Latin-script case (`skald.text(...)`,
`skald.font_add_fallback(...)`, `skald.measure_text(...)`). The
*capabilities* expand: ligatures appear, emoji become coloured, RTL text
flows correctly. No app-side migration required.

App authors targeting non-Latin scripts get net-new functionality. The
existing `font_add_fallback` API still works — internally it just builds
a `Font_Stack`.

---

## 9. Testing + perf bar

This library is meant to *raise the floor* of what Odin can do for text,
so it has to be production-quality, not a toy. Testing is not a final
step — it's how the implementer knows each layer is correct before
building the next on top.

### Five test categories, layered by module

1. **Parser tests (`tests/parse/`).** For every OpenType table the
   parser handles, a `parse_<table>_test.odin` file loads a pinned
   font (e.g. `InterVariable.ttf`, version-locked SHA-256 in
   `tests/fonts/MANIFEST`), parses the table, and asserts the known
   structure: glyph count, units-per-em, named glyph indices, kern
   pairs, etc. Numbers come from running `ttx -t cmap InterVariable.ttf`
   or similar — reference is the spec, not another implementation.
2. **Shaper tests (`tests/shape/`).** HarfBuzz's
   [`test/shape/data/in-house/`](https://github.com/harfbuzz/harfbuzz/tree/main/test/shape/data/in-house)
   directory contains thousands of `(font, text, expected_glyph_ids)`
   test vectors covering every GSUB / GPOS feature. Adopt a sane
   subset (Latin ligatures, kerning, GDEF marks for v0.1; expand per
   phase). Each test is: shape a UTF-8 string, compare emitted glyph
   ID + position array to the expected list. Mismatches are bugs.
3. **Layout / linebreak tests (`tests/linebreak/`).** UAX #14 ships
   normative test vectors:
   [`LineBreakTest.txt`](https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/LineBreakTest.txt).
   Each line is a Unicode string with `÷` (must break) / `×` (must not
   break) markers between codepoints. Parse the file, run the
   linebreaker, compare. UAX #9 (bidi) ships
   [`BidiTest.txt`](https://www.unicode.org/Public/UCD/latest/ucd/BidiTest.txt)
   + `BidiCharacterTest.txt` — same pattern. ~50 000 test cases total
   between them; treat them as the conformance gate.
4. **Rasterization tests (`tests/raster/`).** Render a fixed glyph
   (lowercase `g` from InterVariable, 32 px, subpixel offset 0) to an
   8-bit alpha buffer, compare byte-for-byte to a checked-in golden
   PPM/P5 file. Same for COLRv1: render `🦊` from NotoColorEmoji to
   an RGBA buffer, compare to golden PNG. **Tolerance:** absolute
   per-pixel diff ≤ 4 in 8-bit alpha; any glyph-shape difference
   (off-by-one outline pixels) is a failure, not a tolerance.
5. **Layout integration tests (`tests/layout/`).** End-to-end:
   `layout_paragraph` on a paragraph, render to PPM, diff against
   golden. This is the "did the whole stack come together" gate.

### Visual regression workflow

Goldens are checked into `tests/golden/` as PPM (8-bit alpha) or PNG
(RGBA). Two scripts in `tools/`:

- `runa-test` — runs the full suite; on mismatch, dumps actual +
  expected + diff PPM side-by-side into `tests/_failed/` so the
  implementer can eyeball what changed.
- `runa-test --update-goldens` — regenerates goldens when a change
  is *intentional*. Commits diff is then reviewable: "12 goldens
  changed, here's the visual diff atlas" — the reviewer sees one
  image with all changed glyphs side-by-side.

### Cross-platform parity

Goldens are committed once and must reproduce on Linux + macOS +
Windows within a **per-pixel absolute alpha tolerance of ≤ 2/255**.
Bit-identical is unrealistic: libm `cosf` / `sinf` / `sqrtf`
implementations differ in their last ULP across glibc / musl /
Apple's libm / Microsoft's UCRT, so a pure-float scanline rasterizer
will drift by 1–2 alpha levels on edge pixels. Glyph *shape*
(outline pixels position) must match exactly — only the antialias
ramp tolerates the small drift. The CI matrix runs the full test
suite on all three. Any single-platform failure outside tolerance
blocks merge. If consistent per-platform drift becomes a maintenance
burden, fall back to fixed-point math in the rasterizer's inner
loop.

### Continuous test loop during development

Tests are written with Odin's built-in `core:testing` harness —
each module ships `*_test.odin` files containing `@(test)`-tagged
procs. The implementer's normal cycle:

```
$ odin test parse              # ~1s, runs parser tests only
$ odin test shape              # runs shaper tests against HarfBuzz corpus
$ odin test .                  # full suite, ~30s expected
$ odin run tools/bench.odin    # perf-regression check (separate from tests)
```

The Odin test runner is threaded by default, catches panics into
test failures (so a parser panic on a malformed font shows as a
failed test rather than aborting the run), and prints a clean
pass/fail summary. No external test framework needed.

Each module has tests written alongside the implementation, not at
the end. The shaper isn't "done" until its tests pass; layout isn't
"done" until its tests pass. No backlogging "I'll write tests later"
— if a feature ships without tests, the next refactor breaks it
silently and nobody notices for weeks.

### Fuzzing

OpenType is a malicious-input attack surface (countless CVEs in
FreeType / FontConfig over decades). The parser must never panic
on any input. Strategy:

- Stage 1: `tests/fuzz/seeds/` holds the ttf-parser project's public
  fuzz corpus (their MIT-licenced corpus is reusable).
- Stage 2: bit-flip the seeds (`tools/bit-flip-fuzz.odin` — random
  byte mutations) and feed to `font_load`. Track every input that
  panics or hangs.
- Stage 3 (post v1.0): integrate with `cargo fuzz`-equivalent or
  AFL via FFI if Odin gets a fuzz harness. Until then, the
  bit-flip script run nightly is enough.

A panic on malformed input is a release blocker. Return `Error.X`,
never panic.

### Perf budget + tracking

| Operation | Budget (warm cache, modern x86_64) |
|---|---|
| `font_load(InterVariable.ttf)` (5 MB) | ≤ 5 ms |
| `measure_text("Hello, world!", size=16)` cold | ≤ 200 µs |
| `measure_text(…)` cached | ≤ 5 µs |
| `layout_paragraph(5 000 words)` cold | ≤ 30 ms |
| `layout_paragraph(5 000 words)` cached | ≤ 1 ms |
| `raster_glyph` (8-bit alpha, 32 px) | ≤ 100 µs |
| Atlas upload of one glyph slot | ≤ 10 µs |

`tools/bench.odin` runs each scenario, writes JSON to `bench/results/`
keyed by commit hash. CI fails the PR if any number is > 1.2× the
previous main-branch baseline (intentional regressions get
`[bench-ok]` in the commit message to override).

### No allocations in hot paths

Cache hits and measurement must not allocate. Use `core:mem`'s
`Tracking_Allocator` to assert zero allocations in test cases:

```odin
import "core:mem"
import "core:testing"

@(test)
test_cached_measure_no_alloc :: proc(t: ^testing.T) {
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    context.allocator = mem.tracking_allocator(&track)

    cache := make_cache()
    _ = measure_text("warm", opts, &cache)  // populate
    before := track.total_allocation_count
    _ = measure_text("warm", opts, &cache)  // cache hit
    testing.expect_value(t, track.total_allocation_count, before)
}
```

Allocations only happen on first-time shaping of a run; everything
else uses the caller's frame arena.

### Zero unsafe trickery

Slice-cast hacks against `[]u8` font data are wrapped in the `parse`
API and return `(T, Error)`, never panic. The parser tests
specifically include corrupted-table inputs that exercise the error
paths — every `Error.Invalid_X` variant has at least one regression
test that produces it.

---

## 9a. Cross-platform commitment

**Linux + macOS + Windows are first-class targets, equal weight.**
Skald already ships all three; runa has to match — and not via
platform-specific `#when` forks for the core engine, but by being
*genuinely platform-neutral* at the source level.

What that means concretely:

- **The engine has zero OS-specific code paths.** All parsing,
  shaping, layout, rasterization is byte-in / pixel-out pure
  computation. No `core:sys/linux`, no Win32, no CoreText. The same
  `.odin` files compile and run identically on all three platforms.
  This is a hard rule, not a goal.
- **Font input is `[]u8`.** The app provides bytes — `#load`-ed,
  read from disk, downloaded — runa doesn't care where they came
  from. This naturally sidesteps every platform font-API difference.
- **Endianness:** OpenType is big-endian. All three targets are
  little-endian in practice (x86-64, ARM64). Parse helpers byte-swap
  explicitly via `core:encoding/endian` (`endian.get_u16`, `get_u32`,
  `get_i16` etc. with `.Big`) — Odin's idiomatic path for parsing
  big-endian wire formats. No host-byte-order assumptions in the
  parser.
- **File paths:** runa core doesn't open files. Path-handling is the
  caller's problem. (When `runa-system` lands later, *that* library
  has `#when` per-OS code; the core stays clean.)
- **Atlas output is GPU-API-agnostic.** runa returns CPU-side `[]u8`
  / `[]u32` buffers + UV rects. The consumer uploads them — Vulkan,
  Metal-via-MoltenVK, D3D12, OpenGL, whatever. Skald uses Vulkan;
  another consumer might wire to a different backend.
- **CI builds and tests on all three OSes from day one.** GitHub
  Actions matrix (`ubuntu-latest`, `macos-latest`, `windows-latest`).
  No "Linux-only for now, port later" excuses — porting later means
  porting never.

Skald already proved the all-three-platforms model works for pure-
Odin code (Vulkan backend builds clean on all three). runa inherits
the same discipline. Lee can use runa-via-Skald on his Linux dev
machine *and* his macOS laptop *and* the Windows boxes Skald users
target. No "works on my OS" surprises.

## 9b. Git workflow — house rules

These apply across all of Lee's projects (Skald, Limn, runa) and must
be followed by any agent contributing.

1. **Never push to the public remote without explicit user OK.** Local
   commits are fine and encouraged — they're the unit of progress.
   `git push` is a separate, opt-in step. The user reviews the diff,
   says "push," and only then does the agent push. This applies even
   if a previous push was approved minutes ago; approval doesn't carry
   forward.
2. **One-line commit messages by default.** `git commit -m "subject"`
   is the norm. Multi-paragraph bodies are reserved for genuinely
   complex changes that need explanation; they read as AI-authored
   otherwise. Subject line is conventional: `area: what changed`
   (e.g., `parse: handle CFF2 charstrings`, `bidi: bracket-pair fix`).
3. **No `Co-Authored-By` trailer.** Commits are signed by the human
   author only. The `Co-Authored-By: Claude` trailer that some
   templates suggest gets dropped — Lee's open-source projects look
   human-authored.
4. **Never amend or force-push without explicit OK.** Default is to
   create a new commit. The git history is append-only unless the
   user asks otherwise. Force-push to `main` is never done implicitly.
5. **Never skip hooks** (`--no-verify`, `--no-gpg-sign`). If a hook
   fails, the underlying issue gets fixed.
6. **Don't `git add -A` or `git add .`** Stage specific files by name.
   Catches accidental commits of `.env`, scratch files, build outputs.
7. **Test before pushing to public remotes.** "Compiles clean" is not
   "tested." The new behaviour must be exercised interactively (or via
   automated tests if applicable) before the push command runs.

## 9c. Documentation — match Skald's house style

runa's docs target the same bar as Skald's: a human can pick the doc
up cold and write working code in twenty minutes. The Skald docs that
hit that bar are `docs/getting_started.md`, `docs/cookbook.md`,
`docs/guide.md`, and the per-proc doc comments inside the source.
Read them; copy the voice.

What "Skald house style" means in practice:

1. **Voice: direct, low-marketing.** Lee's docs don't say "this
   powerful new API enables blazing-fast text rendering" — they say
   "`layout_paragraph` shapes a paragraph and returns lines you can
   draw." Verbs first. No "blazing," no "powerful," no "seamless,"
   no superlatives.
2. **Lead with the working example.** Every concept doc opens with a
   complete, runnable `main()`-level snippet. The prose comes after
   to explain *why* the snippet looks like that. Don't make readers
   scroll past three paragraphs of motivation to reach code.
3. **Sentences over bullet lists.** Bullets are for genuine
   enumerations. If a paragraph is trying to convey reasoning, it
   should be a paragraph. Skald docs flow as prose; runa's should too.
4. **One doc per audience.** `docs/getting_started.md` is for someone
   who has never used the library. `docs/guide.md` is for someone
   building their first app. `docs/cookbook.md` is for someone who
   knows the library and wants a recipe for a specific need.
   `docs/reference/` is for someone looking up a specific proc. Don't
   merge them — the audiences read differently.
5. **Doc comments on every public proc** with: (a) one-sentence
   summary; (b) when the caller wants this proc vs alternatives; (c)
   failure modes / edge cases; (d) a 3–10 line example if the call is
   non-trivial. See `skald/view.odin`'s `button` / `text_input` /
   `virtual_list` doc comments for the template.
6. **Examples directory mirrors learning order.** `examples/01_load_font/`,
   `examples/02_measure/`, `examples/03_shape/`, etc. Each example is
   self-contained, builds with `./build.sh NN`, runs in under a second.
   Skald's `examples/01_hello` through `examples/44_rich_text` is the
   pattern to copy.
7. **CHANGELOG is the public release-note source.** Every release gets
   a section with the date and a one-paragraph intro plus `### Added`
   / `### Changed` / `### Fixed` blocks. Read like a release announcement,
   not a git log. See Skald's `CHANGELOG.md` for the format.
8. **No emoji in docs unless explicitly requested.** The doc files
   don't use ✅ ⚠️ 🎉 etc. for decoration. Code blocks are code blocks;
   warnings are sentences.
9. **README sets expectations honestly.** State the version, what
   works, what doesn't, what platforms are tested. Don't promise
   features that are post-v1.0.

## 10. References to study

The agent picking this up should read these in roughly this order. None
are reading-of-the-month length; each is hours, not days.

### Architecture & prior art

1. **cosmic-text** — [github.com/pop-os/cosmic-text](https://github.com/pop-os/cosmic-text).
   Read `src/buffer.rs`, `src/shape.rs`, `src/layout.rs`. This is the
   nearest target to what we want.
2. **ttf-parser** — [github.com/RazrFalcon/ttf-parser](https://github.com/RazrFalcon/ttf-parser).
   Best living example of a zero-alloc, panic-free font parser. Mirror
   its module boundaries in `parse/`.
3. **rustybuzz** — [github.com/RazrFalcon/rustybuzz](https://github.com/RazrFalcon/rustybuzz).
   The pure-Rust HarfBuzz port; its layered structure (general shaper +
   per-script complex shapers) is what we copy in `shape/`. Note: it's
   1.5–2× slower than HarfBuzz; that's our perf reality check too.
4. **swash** — [github.com/dfrg/swash](https://github.com/dfrg/swash).
   Combined parser + shaper + rasteriser in one library. Worth reading
   for atlas / colour-emoji integration ideas.
5. **HarfBuzz docs** — [harfbuzz.github.io](https://harfbuzz.github.io/).
   The OpenType shaper spec, written by HarfBuzz authors. Read at
   minimum: "Why do I need a shaper?", "What HarfBuzz doesn't do",
   "Complex script shapers".

### Specs (cite by name in code comments)

6. **OpenType spec** — [docs.microsoft.com/typography/opentype](https://learn.microsoft.com/en-us/typography/opentype/spec/).
   The authoritative reference for every table. Each parser file
   should cite the spec section it implements.
7. **UAX #9 (bidirectional algorithm)** — [unicode.org/reports/tr9](https://www.unicode.org/reports/tr9/).
   Read fully before writing `bidi/`. It has a normative pseudocode.
8. **UAX #14 (line breaking)** — [unicode.org/reports/tr14](https://www.unicode.org/reports/tr14/).
   Same.
9. **UAX #29 (text segmentation)** — [unicode.org/reports/tr29](https://www.unicode.org/reports/tr29/).
   Grapheme clusters for cursor movement (v1.0).
10. **UAX #24 (script property)** — [unicode.org/reports/tr24](https://www.unicode.org/reports/tr24/).
    Itemiser uses this.
11. **OpenType COLRv1 / CPAL** — [learn.microsoft.com/.../colr](https://learn.microsoft.com/en-us/typography/opentype/spec/colr).
    For colour emoji rendering.

### Comparable engines (read READMEs to understand boundaries)

12. **Skia SkParagraph** — `modules/skparagraph/` in Skia.
13. **Pango** — [docs.gtk.org/Pango](https://docs.gtk.org/Pango/).
14. **DirectWrite (high-level overview)** — Microsoft docs. Mostly for
    perspective on how a native OS engine differs from a portable one.

### Odin-specific

15. **Skald source** — [github.com/BuLEEto/Skald](https://github.com/BuLEEto/Skald).
    Read `skald/text.odin` to understand what consumer-side calls look
    like. Read `skald/renderer.odin` for atlas integration. Read
    `skald/shaders/text.wgsl` to see how glyph alpha gets to pixels.
    The integration story has to fit this code.

---

## 11. Open questions for the implementer

These are deliberate forks in the road. The agent picking this up
should pick a lane and document the choice in `runa/DESIGN.md`.

1. **Allocator threading.** Every entry-point takes `allocator: Allocator`
   explicitly, like `core:strings`? Or stash an arena inside `Cache` so
   the caller hands one allocator at construction? Odin idiom is the
   former; cosmic-text uses the latter.
2. **Variable-font axes — eager or lazy?** Bake axis values into the
   font on `font_set_variation` (expensive, one-time) or pass axis vector
   through every shaping/raster call (cheap, but invades every API)?
3. **Subpixel positioning — 4 buckets or N?** cosmic-text uses 4. Skia
   uses 4 or 8. fontstash uses 1 (integer pixels). 4 looks fine.
4. **Atlas growth.** Skald currently uses fontstash's grow-or-evict
   policy; the new library needs a clear contract. Bound growth at
   `(4096, 4096)`? Evict-oldest? Force-flush at the boundary?
5. **Threading.** Is shaping thread-safe (caller can call from
   `cmd_thread` work)? Easiest answer: yes, *Cache* is the only mutable
   state and the caller serializes access. Document explicitly.
6. **Hinting.** Position firmly: no TrueType bytecode interpreter,
   ever, at this scale. Stem-darkening + grayscale AA is good enough.
   Document so a future contributor doesn't open a 50-line PR adding it.
7. **OS font enumeration.** Punt to `runa-system` (separate library)?
   Or keep a fontconfig-style path inside the core? Recommend: punt.

(CFF2, COLRv1 gradients, error-type design, allocator threading,
and license — all resolved in §4, §6, §6a, §17 respectively.)

---

## 12. Definition of done — v0.1

The first deliverable is concrete:

1. `runa` package compiles standalone on Linux/macOS/Windows. CI
   matrix runs the full test suite on all three; all green.
2. Loads InterVariable.ttf, Twemoji-Mozilla.ttf (COLRv0 layered),
   FiraCode.ttf, JetBrainsMono.ttf without errors. NotoColorEmoji.ttf
   loads but layered v0 layers render (gradients arrive at v0.5).
3. ~~`layout_paragraph` on a 100-word English string returns visually
   identical output to fontstash within ±1 px per glyph.~~ **Struck
   2026-05-13.** This DoD asked the agent to install fontstash as a
   dev-time reference, which contradicts the project's "pure-Odin,
   zero-C-deps" goal. The replacement quality bar is item #7 below:
   golden tests against `unicode-org/text-rendering-tests` (an
   industry-standard reference set; a stronger correctness claim
   than "matches one specific renderer").
4. Ligatures fire: rendering "fi" with FiraCode emits one glyph, not two.
5. Colour emoji renders: rendering "🦊" with Twemoji-Mozilla returns
   an `is_color: true` glyph and the atlas slot is RGBA, not alpha.
6. A demo program (`runa/examples/basic/`) draws "Hello, world! 🦊"
   to a PPM/PNG file. No GUI — proves the library is self-contained.
7. Golden tests pass against the `unicode-org/text-rendering-tests`
   subset for Latin/Cyrillic/Greek within the ≤2/255 alpha tolerance.
8. UAX #14 line-break conformance: 100% pass on `LineBreakTest.txt`.
9. A 5 000-word English paragraph lays out in under 30 ms with a
   warm cache; cached re-layouts under 1 ms.
10. `mem.Tracking_Allocator` reports zero allocations on cache-hit
    `measure_text` calls.
11. Fuzzing the parser on 10 000 bit-flipped variants of the test
    fonts produces zero panics (errors are fine; panics are blockers).

---

## 13. Naming

**Project name: `runa`** — Norwegian for "the rune," pairs naturally
with Skald (also Norse-mythology rooted) without conflicting with
Odin's `rune` keyword (which is the lowercase singular). Short,
memorable, evocative of carved letters on stone — fitting for a
glyph-rendering engine.

Alternatives considered:
- `glyph` — most discoverable but generic
- `kern` — typographic, short
- `quill` — writing-implement metaphor
- `vellum` — surface metaphor
- `litera` — Latin for "letter"

---

## 14. Operating instructions for the implementer

If you're an agent / engineer picking this up:

1. **Read §10 references in order.** Block out a day. Don't skim.
2. **Stand up a skeleton.** Empty `parse`, `shape`, `itemize`, `bidi`,
   `linebreak`, `raster` packages. Empty `runa.odin` facade. CI builds
   green.
3. **Implement `parse` first.** Tables in this order: `head`, `maxp`,
   `cmap`, `hhea`, `hmtx`, `glyf` (TT outlines), then `GSUB`/`GPOS`
   structurally (no lookup execution yet), then `CFF`. Each table gets
   a golden test against InterVariable.ttf.
4. **Implement `raster` against TT outlines.** Skip subpixel positioning
   the first pass; integer pixels good enough to prove the path.
5. **Implement `shape` with GSUB ligature substitution only.** Ship
   `fi → fi` working end-to-end. *Then* expand to GPOS pair kerning,
   mark positioning, the rest of GSUB.
6. **Implement `linebreak` from UAX #14 standalone.** Don't wire to the
   layout yet. Tests against UAX #14 reference test vectors.
7. **Wire the facade.** `layout_paragraph` orchestrates itemize → shape
   → linebreak → return. LTR-only.
8. **Add COLR rasterisation.** RGBA atlas. Two-pass: figure out layer
   stack, composite into atlas slot.
9. **Hit v0.1 DoD (§12).** Cut a release.

Then come back for v0.5 (bidi + Arabic).

Don't try to implement v0.5 features before v0.1 ships. The temptation
is real — Arabic looks interesting, COLRv1 gradients look interesting —
but a working Latin-only path is what proves the architecture. Real
shipped users on v0.1 will surface problems you can't predict from a
spec read.

---

## 15. Coordination with Skald

The Skald team will:
- Review the `Paragraph_Opts` / `Shaped_Glyph` API shape before v0.1
  freeze (this is the integration contract).
- Provide the atlas-upload + GPU sampling code as reference — Skald's
  Vulkan backend already does R8_UNORM (alpha) and RGBA atlases, so a
  consumer reference implementation exists.
- Adopt the library behind the facade described in §8 once v0.1 lands.
- Ship `Skald 1.1` with `runa` as the default once a soak period
  passes.

The library author should:
- Open issues against Skald for any integration friction discovered.
- Not feel obliged to match fontstash's API exactly. The right thing
  is the right thing.

---

## 16. Why this is worth doing

Two things become true once this exists.

**For Odin.** The Odin community gets a first-class text-rendering library
that any GUI / game / editor / terminal can adopt. The current options
are: bind to HarfBuzz via C (a real dep + cross-compile pain), use
fontstash (no shaping), or write your own (most projects don't). A
pure-Odin engine moves the floor for the whole ecosystem.

**For Skald.** The roadmap items "Color emoji rendering", "Complex-script
shaping + bidi", "Emoji picker widget", and "SVG rasterization" all
collapse into "wait for `runa`". Skald becomes the first GUI framework
in the post-Electron, pure-native, pure-Odin world that *actually
handles text the way users in 2026 expect*.

Worth the side-project effort.

---

## 17. License + attribution

### License for `runa` itself

**`runa` is zlib-licensed.** Matches Skald's licence so apps
embedding both reason about one attribution story, not two. zlib is
short (three short conditions), unambiguously permissive for
commercial use, GPL-compatible, and the same licence used by Odin's
own standard library — Odin-community-native.

The three zlib conditions:
1. Don't misrepresent the origin (don't claim you wrote it).
2. Altered source versions must be plainly marked.
3. The notice may not be removed from source distributions.

There's no notice-with-binary requirement, so consumer apps shipping
a compiled binary that embeds `runa` don't carry any redistribution
obligation. Source-form redistribution preserves the `LICENSE` file
at the repo root.

The `LICENSE` file at the repository root carries the zlib text with
copyright assigned to `Lee Fry <lee@focus-sb.co.uk>` and contributors.

### Third-party code we draw from

Even though `runa` is pure-Odin and ships no upstream binaries, the
*design* and the *test corpora* are heavily indebted to prior work.
Each owner gets credit in the project's `CREDITS.md` and (where the
licence requires it) a copy of their notice file in `third_party/`:

- **HarfBuzz** ([github.com/harfbuzz/harfbuzz](https://github.com/harfbuzz/harfbuzz),
  Old MIT / "ISC-like"). The shaper-spec authoritative reference and
  the source of the in-house shaping test corpus that `tests/shape/`
  copies. Notice file ships in `third_party/harfbuzz-NOTICE.txt`.
- **cosmic-text** ([github.com/pop-os/cosmic-text](https://github.com/pop-os/cosmic-text),
  MIT or Apache-2.0). Architectural inspiration; module split mirrors
  theirs. No code copied. Credited in `CREDITS.md`.
- **ttf-parser** ([github.com/RazrFalcon/ttf-parser](https://github.com/RazrFalcon/ttf-parser),
  MIT or Apache-2.0). Parser API patterns, error-style conventions,
  and the public fuzz seed corpus that `tests/fuzz/seeds/` adopts.
  Notice file ships in `third_party/ttf-parser-NOTICE.txt`.
- **rustybuzz** ([github.com/RazrFalcon/rustybuzz](https://github.com/RazrFalcon/rustybuzz),
  MIT). Per-script complex-shaper module layout inspired this proposal.
  Credited in `CREDITS.md`.
- **swash** ([github.com/dfrg/swash](https://github.com/dfrg/swash),
  Apache-2.0 or MIT). Influenced the colour-emoji + atlas integration
  thinking. Credited in `CREDITS.md`.
- **Unicode UCD data files** (Unicode-DFS-2016 licence). The `.txt`
  data tables in `tools/ucd/` carry Unicode's own notice. A copy of
  the licence ships at `third_party/UNICODE-LICENSE.txt`. The
  Unicode-DFS terms are permissive but require the notice be
  preserved with any redistribution.
- **unicode-org/text-rendering-tests**
  ([github.com/unicode-org/text-rendering-tests](https://github.com/unicode-org/text-rendering-tests),
  MIT for code, OFL-1.1 for bundled fonts). Subset used in
  `tests/golden/`; both notices ship in `third_party/`.

### Bundled test fonts

`tests/fonts/` holds version-pinned copies of the fonts used by the
test suite. Each carries its own SIL Open Font License (OFL-1.1)
copy alongside the binary:

- **InterVariable** — Inter authors / [github.com/rsms/inter](https://github.com/rsms/inter)
  (OFL-1.1). Latin / Cyrillic / Greek conformance baseline.
- **FiraCode** — Nikita Prokopov / [github.com/tonsky/FiraCode](https://github.com/tonsky/FiraCode)
  (OFL-1.1). Programming-font ligature tests.
- **JetBrains Mono** — JetBrains / [github.com/JetBrains/JetBrainsMono](https://github.com/JetBrains/JetBrainsMono)
  (OFL-1.1). Variable-axis and ligature tests.
- **Twemoji-Mozilla** — Mozilla / [github.com/mozilla/twemoji-colr](https://github.com/mozilla/twemoji-colr)
  (CC-BY-4.0 for artwork, Apache-2.0 for tools). COLRv0 layered emoji
  reference for v0.1.
- **Noto Color Emoji** — Google / [github.com/googlefonts/noto-emoji](https://github.com/googlefonts/noto-emoji)
  (OFL-1.1). COLRv1 gradient emoji reference for v0.5.

The font OFL copies sit next to the `.ttf` / `.otf` in
`tests/fonts/<name>/OFL.txt`. OFL-1.1 requires the notice travel
with the font; redistributing `runa` redistributes the fonts, so
this is non-optional.

### Distributed notice file

Anyone redistributing `runa` in **source form** keeps the `LICENSE`
file (zlib) and the contents of `third_party/`. Anyone embedding
`runa` in a **compiled binary** carries no obligation from zlib
itself — only the upstream notices in `third_party/` that have their
own redistribution clauses (HarfBuzz, Unicode UCD, OFL fonts). This
is one of zlib's nicest properties: ship your app as a binary, no
runa notice needed in your About box.

If `runa` is later split into separate sub-libraries (`runa-system`,
`runa-edit`), each carries the same zlib licence and the same
`third_party/` layout.
