# runa

A pure-Odin modern text engine — parsing, itemization, shaping,
line-breaking, rasterization. Built first to replace fontstash +
stb_truetype in [Skald](https://github.com/BuLEEto/Skald), designed
to be useful for any Odin project that needs production-quality text.

**Status:** v0.1 — first public release. Parse → shape → rasterize →
atlas is wired end-to-end, with bench / fuzz / golden / UAX-conformance
harnesses in place. The DoD scoreboard from PROPOSAL §12 lives in
[`CHANGELOG.md`](CHANGELOG.md); the full design contract is in
[`PROPOSAL.md`](PROPOSAL.md).

## What this is

The current Odin text-rendering story is `vendor:fontstash` plus
`stb_truetype` — a glyph atlas and basic kerning. That covers Latin
text at small scales but cannot:

- Shape complex scripts (Arabic joining, Devanagari conjuncts, Thai
  clusters, bidi).
- Break lines per Unicode UAX #14.
- Render colour emoji (COLRv0 / COLRv1 / CBDT / sbix tables).
- Apply OpenType features (ligatures, GPOS kerning, contextual
  alternates, stylistic sets).
- Subpixel-position glyphs.

`runa` is the long-term fix. Think "cosmic-text for Odin," written
from scratch in idiomatic Odin with zero C dependencies at v1.0.

## What's planned

| Milestone | Scope |
|-----------|-------|
| **v0.1** | Latin / Cyrillic / Greek production quality. Ligatures, GPOS kerning, COLRv0 emoji, variable fonts, subpixel positioning. Skald can switch off fontstash here. |
| **v0.5** | RTL support — UAX #9 bidi, Arabic shaper, Hebrew. COLRv1 gradient emoji. CFF2. |
| **v1.0** | Complex scripts ship — Indic family, Thai / Lao / Khmer / Myanmar. API freeze. |

Details, rationale, and per-phase deliverables: see [`PROPOSAL.md`](PROPOSAL.md).

## Building

The library is a set of plain Odin packages — no build script needed.

```
odin check . -no-entry-point          # type-check the library
odin test  tests/parse                # parser tests
odin test  tests/raster               # rasterizer smoke tests
odin test  tests/runa                 # facade integration tests
```

The runnable demo:

```
odin run examples/hello_world -- \
    tests/fonts/Roboto-Regular.ttf \
    tests/fonts/Twemoji-Mozilla.ttf \
    /tmp/hello.ppm
```

`tests/fonts/` holds local symlinks during development;
proper version-pinned copies of InterVariable, FiraCode, JetBrains
Mono, and Twemoji-Mozilla arrive once the OFL sidecars are landed.

## License

`runa` is licensed under the **zlib license** — see
[`LICENSE`](LICENSE). Permissive, GPL-compatible, the same licence
Odin's own standard library uses.

Third-party data files and bundled test fonts carry their own
licences alongside them in `third_party/` and `tests/fonts/` once
those land. See `PROPOSAL.md` §17 for the full attribution plan.

## Contributing

The v0.1 milestone is being built out — the vertical slice is in,
the polish (analytic-coverage rasterizer, cache, UAX #14, atlas,
variable-axis interpolation, cross-platform CI) is the active work.
Open an issue if you spot a scope problem, a spec inaccuracy, or
have a strong opinion on the API sketch in `PROPOSAL.md` §6.
