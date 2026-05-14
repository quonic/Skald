# runa

A pure-Odin modern text engine — parsing, itemization, shaping,
line-breaking, rasterization. Built first to replace fontstash +
stb_truetype in [Skald](https://github.com/BuLEEto/Skald), designed
to be useful for any Odin project that needs production-quality text.

**Status:** v0.9-rc1 — *"Everything except complex-script shapers."*
UAX #9 bidi at 100 %, UAX #29 grapheme clusters at 100 %, CFF2
variable instances, COLRv1 emoji with true linear / radial / sweep
gradients + composite blend modes, GPOS mark-to-ligature, and a
frozen public API ([`API.md`](API.md)). v1.0 final lands the Indic
+ SEA shapers. DoD scoreboards per milestone live in
[`CHANGELOG.md`](CHANGELOG.md); the design contract is in
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
| **v0.5** | RTL support — UAX #9 bidi at 100 %, Arabic shaper, Hebrew. COLRv1 linear-gradient emoji. CFF2 default instance. |
| **v0.9-rc1** | API freeze. CFF2 non-default-instance (Item Variation Store), UAX #29 grapheme clusters at 100 %, radial + sweep gradients, COLR composite modes, GPOS mark-to-ligature. |
| **v1.0** | Indic family + Thai / Lao / Khmer / Myanmar shapers. |

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

v0.9-rc1 is shipping — API frozen ([`API.md`](API.md)), bidi at
100 %, graphemes at 100 %, COLRv1 gradients + composite modes
real, CFF2 variations real. v1.0 final work picks up the Indic
family (Devanagari, Bengali, Tamil, Telugu, Kannada, Malayalam,
Gurmukhi, Gujarati, Odia) and SEA scripts (Thai, Lao, Myanmar,
Khmer) — each shaper is its own module sharing a state-core, so
the work parallelises. Open an issue if you spot a scope problem,
a spec inaccuracy, or have a strong opinion on the API in
`API.md` / `PROPOSAL.md` §6.
