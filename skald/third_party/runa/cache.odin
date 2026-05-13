package runa

// cache.odin — memoised shaping.
//
// The Cache is the caller-owned mutable state for fast re-layout. It
// stores `[]Shaped_Glyph` keyed by `(font, size, text)`. On a hit,
// shape / measure / layout calls return without re-running GSUB / GPOS
// and without allocating — PROPOSAL §6a rule 7 and the v0.1 DoD's
// zero-allocation guarantee land here.
//
// The text key is *interned* — every distinct cache key holds its own
// string copy, so the caller may free the original buffer. Cache
// lifetime stays the caller's: `cache_destroy` releases every
// interned string and every cached glyph slice.

import "core:mem"

import "parse"
import "shape"

// Cache holds the caller-owned shape memoisation table. It's an
// opaque struct — callers don't reach into the field set, just pass
// `^Cache` to the shaping entry points.
Cache :: struct {
	allocator: mem.Allocator,
	entries:   map[Shape_Key]Cache_Entry,
}

// Shape_Key uniquely identifies a shaped run.
//
// `font` is compared by pointer — the caller's Font struct must live
// for the lifetime of the Cache. `text` is the caller's UTF-8 slice;
// the cache clones it on insert so the original buffer can vary.
@(private)
Shape_Key :: struct {
	font_ptr: rawptr,
	size:     f32,
	text:     string,                // interned by the cache on insert
}

@(private)
Cache_Entry :: struct {
	glyphs: []Shaped_Glyph,
	width:  f32,                     // sum of x_advance — measure-text shortcut
}

cache_make :: proc(allocator := context.allocator) -> Cache {
	return Cache{allocator = allocator, entries = make(map[Shape_Key]Cache_Entry, 64, allocator)}
}

cache_destroy :: proc(c: ^Cache) {
	for key, entry in c.entries {
		delete(entry.glyphs, c.allocator)
		delete(key.text, c.allocator)
	}
	delete(c.entries)
	c^ = {}
}

// shape_text_cached returns a slice of Shaped_Glyph for the given
// (font, text, size), reusing a cached buffer if one exists. Cache
// hits make zero heap allocations.
//
// The returned slice is owned by the Cache; do not modify it, and do
// not retain it past `cache_destroy`.
shape_text_cached :: proc(font: ^Font, text: string, size: f32, c: ^Cache, script_tag: parse.Tag = parse.LATN_SCRIPT, language_tag: parse.Tag = parse.DFLT_LANG) -> []Shaped_Glyph {
	key := Shape_Key{font_ptr = font, size = size, text = text}
	if existing, ok := c.entries[key]; ok {
		return existing.glyphs
	}

	// Miss — clone the text key, shape, store.
	owned_text := strings_clone(text, c.allocator)
	stored_key := Shape_Key{font_ptr = font, size = size, text = owned_text}

	buf := make([dynamic]Shaped_Glyph, 0, max(8, len(text)), c.allocator)
	shape_into(font, owned_text, size, &buf, script_tag, language_tag)
	glyphs := buf[:]

	w: f32 = 0
	for g in glyphs { w += g.x_advance }

	c.entries[stored_key] = Cache_Entry{glyphs = glyphs, width = w}
	return glyphs
}

// measure_text_cached is the same shape-and-sum-advances cycle as
// `measure_text`, but reuses the Cache's per-run shape buffer. Cache
// hits do not allocate.
measure_text_cached :: proc(text: string, opts: Paragraph_Opts, c: ^Cache) -> (width, height: f32) {
	if len(opts.fonts) == 0 || opts.size <= 0 { return 0, 0 }
	// For multi-font runs, walk codepoints once to find the picks.
	byte_off := 0
	cur_font: ^Font
	run_start := 0
	for r in text {
		picked := pick_font_for_rune(opts.fonts, r)
		if picked != cur_font && cur_font != nil {
			gs := shape_text_cached(cur_font, text[run_start:byte_off], opts.size, c)
			for sg in gs { width += sg.x_advance }
			run_start = byte_off
		}
		cur_font = picked
		byte_off += utf8_byte_len(r)
	}
	if cur_font != nil {
		gs := shape_text_cached(cur_font, text[run_start:byte_off], opts.size, c)
		for sg in gs { width += sg.x_advance }
	}

	for f in opts.fonts {
		s := opts.size / f32(f.units_per_em)
		h := (f.ascent - f.descent + f.line_gap) * s
		if h > height { height = h }
	}
	return
}

// strings_clone copies `s` into `allocator`. core:strings's clone uses
// context.allocator; we need an explicit one for cache ownership.
@(private)
strings_clone :: proc(s: string, allocator: mem.Allocator) -> string {
	if len(s) == 0 { return "" }
	buf := make([]u8, len(s), allocator)
	copy(buf, transmute([]u8)s)
	return string(buf)
}

// shape_into shapes one run into an existing dynamic buffer. Internal
// helper for the cache; mirrors `shape_text` but doesn't allocate the
// output buffer itself.
@(private)
shape_into :: proc(font: ^Font, text: string, size: f32, out: ^[dynamic]Shaped_Glyph, script_tag, language_tag: parse.Tag) {
	inputs := shape.Shape_Inputs{
		cmap         = &font._cmap,
		hmtx         = &font._hmtx,
		gsub         = &font._gsub if font._has_gsub else nil,
		gpos         = &font._gpos if font._has_gpos else nil,
		units_per_em = font.units_per_em,
	}
	opts := shape.Shape_Run_Opts{script = script_tag, language = language_tag}
	shape.shape_run(&inputs, opts, text, size, out)
}

