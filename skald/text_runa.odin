package skald

import "core:fmt"
import "core:math"
import "runa:runa"

// Text_Runa carries the runa-backed text state. Allocated once per
// Renderer when the `SKALD_RUNA` build define is true *and*
// `text_init_runa` succeeds; otherwise `Text.runa_state` stays nil
// and the renderer transparently falls back to fontstash.
//
// Phase 1a: mono (alpha) glyph path. The runa atlas is sized 1024×1024
// to match Skald's existing GPU image; alpha-page dirty rects flow into
// the same R8_UNORM texture fontstash used, so the rest of the
// renderer is untouched. Colour-emoji (RGBA) glyphs are detected but
// skipped — they render as nothing until Phase 1b lights up the second
// atlas + shader variant.
@(private)
Text_Runa :: struct {
	cache: runa.Cache,
	atlas: runa.Atlas,
	// Heap-allocated runa.Font values, indexed by skald.Font (cast to
	// int). Order is locked at init: 0 = default (Inter), 1 = bold,
	// 2 = italic, 3 = bold-italic. App-loaded fonts append from index 4.
	fonts: [dynamic]^runa.Font,

	// Skald font IDs that have been registered as fallbacks to any
	// base font. v0.1 simplification: a single global chain rather
	// than a per-base map. Every shaping call picks from
	// [primary] ++ fallback_chain.
	fallback_chain: [dynamic]int,

	// (font, glyph_id, size, subpx) → packed slot. raster_glyph
	// re-packs the atlas every call, so without this cache every
	// draw_text would fill the atlas with duplicates and overflow.
	glyph_cache: map[Glyph_Key]runa.Atlas_Slot,

	// Lazy flag: true once `COLOR_ATLAS_KEY` has been registered in
	// the image cache. Registration is deferred until the first
	// colour-glyph dirty rect because `text_init` runs before
	// `image_cache_init`, so we can't seed the entry at init time.
	color_atlas_registered: bool,

	// Reusable Font_Stack buffer. Built once per `font_add_fallback`
	// and re-pointed each call so `measure_text_runa` / `draw_text_runa`
	// don't allocate a fresh slice every time. Gallery-style UIs hit
	// this path dozens of times per frame; the savings show up as ~3 %
	// in p50 frame time.
	stack_buf: [dynamic]^runa.Font,
}

// Glyph_Key keys the raster-slot cache. `size_q` is `size * 4` rounded
// (1/4-pixel quantisation — enough granularity for fractional DPI scale
// without exploding the cache).
@(private)
Glyph_Key :: struct {
	font:   ^runa.Font,
	gid:    u16,
	size_q: u32,
	subpx:  u8,
}

// Synthetic image-cache key for runa's RGBA glyph atlas. COLR-base
// glyphs are composited into runa's pages_color[0] (RGBA), then the
// dirty region is mirrored into this Skald-side image-cache entry so
// `batch_push_image` can sample it like any other RGBA texture.
@(private)
COLOR_ATLAS_KEY :: "skald://runa-color-atlas"

// RUNA_BACKEND_DEFAULT is true when the build was passed
// `-define:SKALD_RUNA=true`. text_init reads this to decide whether
// to even attempt the runa init path.
@(private)
RUNA_BACKEND_DEFAULT :: #config(SKALD_RUNA, false)

// text_init_runa allocates the Text_Runa state, opens the four bundled
// Inter faces against runa's parser, sizes the atlas to match Skald's
// 1024² GPU image, and parks the state on t.runa_state so every
// public API dispatches to the runa path from this frame onwards.
// Returns true on success; caller falls back to fontstash on false.
@(private)
text_init_runa :: proc(t: ^Text, r: ^Renderer) -> bool {
	rs := new(Text_Runa)
	rs.atlas = runa.atlas_make(u16(t.atlas_w), u16(t.atlas_h))
	rs.cache = runa.cache_make()
	rs.fonts          = make([dynamic]^runa.Font, 0, 4)
	rs.fallback_chain = make([dynamic]int, 0, 4)
	rs.glyph_cache    = make(map[Glyph_Key]runa.Atlas_Slot, 256)
	rs.stack_buf      = make([dynamic]^runa.Font, 1, 5)

	// Lock the embedded-Inter font indices to the same values fontstash
	// would have assigned (0..3), so app code that called font_default /
	// font_bold under fontstash keeps working.
	ok := text_runa_add_font(rs, INTER_VARIABLE) &&
	      text_runa_add_font(rs, INTER_BOLD) &&
	      text_runa_add_font(rs, INTER_ITALIC) &&
	      text_runa_add_font(rs, INTER_BOLD_ITALIC)
	if !ok {
		fmt.eprintln("skald: runa font load failed; falling back to fontstash")
		text_runa_free(rs)
		return false
	}

	t.default_font     = Font(0)
	t.bold_font        = Font(1)
	t.italic_font      = Font(2)
	t.bold_italic_font = Font(3)

	t.runa_state = rs
	return true
}

@(private)
text_destroy_runa :: proc(t: ^Text, r: ^Renderer) {
	if t.runa_state == nil { return }
	text_runa_free(t.runa_state)
	t.runa_state = nil
}

@(private)
text_runa_free :: proc(rs: ^Text_Runa) {
	delete(rs.glyph_cache)
	delete(rs.fallback_chain)
	delete(rs.stack_buf)
	for f in rs.fonts {
		runa.font_destroy(f)
		free(f)
	}
	delete(rs.fonts)
	runa.cache_destroy(&rs.cache)
	runa.atlas_destroy(&rs.atlas)
	free(rs)
}

@(private)
text_runa_add_font :: proc(rs: ^Text_Runa, data: []u8) -> bool {
	f := new(runa.Font)
	loaded, err := runa.font_load(data)
	if err != .None {
		free(f)
		return false
	}
	f^ = loaded
	append(&rs.fonts, f)
	return true
}

// text_runa_stack returns the per-call Font_Stack: [primary] ++ every
// fallback that has been registered via font_add_fallback. Reuses a
// persistent buffer on Text_Runa rather than allocating a fresh slice
// per call — gallery-style UIs hit this dozens of times per frame.
@(private)
text_runa_stack :: proc(rs: ^Text_Runa, primary: Font) -> runa.Font_Stack {
	idx := int(primary)
	if idx < 0 || idx >= len(rs.fonts) { idx = 0 }
	n := 1 + len(rs.fallback_chain)
	resize(&rs.stack_buf, n)
	rs.stack_buf[0] = rs.fonts[idx]
	for fi, i in rs.fallback_chain {
		rs.stack_buf[i+1] = rs.fonts[fi]
	}
	return runa.Font_Stack(rs.stack_buf[:n])
}

// text_upload_dirty_runa drains both the alpha page (→ Skald's R8 atlas
// image) and the colour page (→ the registered `skald://runa-color-atlas`
// image cache entry). Page 0 of each shares dimensions with its GPU
// counterpart so coordinates are 1:1. Returns false for `rebuilt` —
// Phase 1 never resizes the GPU images.
@(private)
text_upload_dirty_runa :: proc(t: ^Text, r: ^Renderer) -> (rebuilt: bool) {
	rs := t.runa_state
	if rs == nil { return }

	// Alpha (mono) glyphs → the existing R8 atlas image.
	if len(rs.atlas.pages_alpha) > 0 {
		page := &rs.atlas.pages_alpha[0]
		if page.is_dirty {
			x0 := int(page.dirty_min.x)
			y0 := int(page.dirty_min.y)
			x1 := int(page.dirty_max.x)
			y1 := int(page.dirty_max.y)
			w := x1 - x0
			h := y1 - y0
			if w > 0 && h > 0 {
				text_upload_region_from(t, r, x0, y0, w, h, page.pixels, int(page.width))
			}
			page.is_dirty  = false
			page.dirty_min = {}
			page.dirty_max = {}
		}
	}

	// Colour glyphs → the image-cache RGBA entry. Registration is lazy
	// (image_cache_init runs after text_init, so we can't seed at init
	// time); the first dirty colour rect triggers `image_load_pixels`,
	// subsequent ones use `image_update_pixels`. The whole page uploads
	// each time — no sub-region API yet — which is cheap enough at
	// 4 MB-per-update because frames introducing new emoji are rare.
	if len(rs.atlas.pages_color) > 0 {
		page := &rs.atlas.pages_color[0]
		if page.is_dirty {
			w, h := u32(page.width), u32(page.height)
			if !rs.color_atlas_registered {
				if image_load_pixels(r, COLOR_ATLAS_KEY, w, h, page.pixels) {
					rs.color_atlas_registered = true
				}
			} else {
				image_update_pixels(r, COLOR_ATLAS_KEY, w, h, page.pixels)
			}
			page.is_dirty  = false
			page.dirty_min = {}
			page.dirty_max = {}
		}
	}
	return
}

@(private)
font_load_runa :: proc(r: ^Renderer, name: string, data: []byte) -> Font {
	rs := r.text.runa_state
	if !text_runa_add_font(rs, data) { return Font(-1) }
	return Font(len(rs.fonts) - 1)
}

@(private)
font_add_fallback_runa :: proc(r: ^Renderer, base, fallback: Font) -> bool {
	rs := r.text.runa_state
	fb := int(fallback)
	if fb < 0 || fb >= len(rs.fonts) { return false }
	// v0.1 simplification: one global chain, ignore `base`. Apps that
	// chain CJK or Arabic to the default Inter end up with the same
	// effective behaviour because the primary is the only font that
	// ever gets shaping pressure to look elsewhere.
	append(&rs.fallback_chain, fb)
	return true
}

@(private)
measure_text_runa :: proc(
	r:    ^Renderer,
	text: string,
	size: f32,
	font: Font,
) -> (width, line_height: f32) {
	rs := r.text.runa_state
	if rs == nil { return }
	f := font == 0 ? r.text.default_font : font
	if int(f) < 0 || int(f) >= len(rs.fonts) { return }

	scale := r.scale
	if scale <= 0 { scale = 1 }

	stack := text_runa_stack(rs, f)
	opts  := runa.Paragraph_Opts{fonts = stack, size = size * scale}
	w, h  := runa.measure_text_cached(text, opts, &rs.cache)
	return w / scale, h / scale
}

@(private)
text_ascent_runa :: proc(r: ^Renderer, size: f32, font: Font) -> f32 {
	rs := r.text.runa_state
	if rs == nil { return 0 }
	f := font == 0 ? r.text.default_font : font
	if int(f) < 0 || int(f) >= len(rs.fonts) { return 0 }

	scale := r.scale
	if scale <= 0 { scale = 1 }
	fnt := rs.fonts[int(f)]
	if fnt.units_per_em == 0 { return 0 }
	s := (size * scale) / f32(fnt.units_per_em)
	return fnt.ascent * s / scale
}

@(private)
draw_text_runa :: proc(
	r:     ^Renderer,
	text:  string,
	x, y:  f32,
	color: Color,
	size:  f32,
	font:  Font,
) {
	rs := r.text.runa_state
	if rs == nil { return }
	f := font == 0 ? r.text.default_font : font
	if int(f) < 0 || int(f) >= len(rs.fonts) { return }

	scale := r.scale
	if scale <= 0 { scale = 1 }
	inv := 1 / scale
	px_size := size * scale

	stack := text_runa_stack(rs, f)
	opts := runa.Paragraph_Opts{fonts = stack, size = px_size}

	// `runa.layout_paragraph` threads the cache through to
	// `shape_text_cached` when a non-nil ^Cache is passed (runa 0.2+),
	// so per-frame redraws of static text hit the shape cache and
	// avoid re-running GSUB / GPOS every call. The earlier custom
	// run-walker is no longer needed — the fix landed in runa proper.
	lines, err := runa.layout_paragraph(text, opts, &rs.cache, context.temp_allocator)
	if err != .None { return }

	pen_x := x * scale
	pen_y := y * scale

	for line in lines {
		for g in line.glyphs {
			text_runa_emit_glyph(rs, r, g.font, u16(g.glyph_id),
				g.x_advance, g.x_offset, g.y_advance, g.y_offset,
				px_size, inv, &pen_x, &pen_y, color)
		}
	}
}

@(private)
text_runa_emit_glyph :: proc(
	rs:        ^Text_Runa,
	r:         ^Renderer,
	fnt:       ^runa.Font,
	gid:       u16,
	x_advance, x_offset, y_advance, y_offset: f32,
	px_size, inv: f32,
	pen_x, pen_y: ^f32,
	color:     Color,
) {
	// Inlined version of the per-glyph push that used to live in the
	// draw_text_runa loop. Same subpixel-x bucket + pixel-snap fix.
	gx_phys := pen_x^ + x_offset
	frac_x  := gx_phys - math.floor(gx_phys)
	subpx   := u8(frac_x * 4)
	if subpx > 3 { subpx = 0 }

	slot, ok := text_runa_get_slot(rs, fnt, gid, px_size, subpx)
	if ok && slot.px_size.x > 0 && slot.px_size.y > 0 {
		bx := math.floor(pen_x^ + x_offset + slot.bearing.x)
		by := math.floor(pen_y^ + y_offset + slot.bearing.y)
		x0 := bx * inv
		y0 := by * inv
		x1 := (bx + f32(slot.px_size.x)) * inv
		y1 := (by + f32(slot.px_size.y)) * inv
		if slot.is_color {
			entry := text_runa_ensure_color_atlas(rs, r)
			if entry != nil {
				batch_push_image(r, entry.dset,
					Rect{x0, y0, x1 - x0, y1 - y0},
					[4]f32{slot.uv_rect[0], slot.uv_rect[1], slot.uv_rect[2], slot.uv_rect[3]},
					Color{1, 1, 1, 1})
			}
		} else {
			batch_push_glyph(r,
				x0, y0, x1, y1,
				slot.uv_rect[0], slot.uv_rect[1],
				slot.uv_rect[2], slot.uv_rect[3],
				color)
		}
	}
	pen_x^ += x_advance
	pen_y^ += y_advance
}

// text_runa_ensure_color_atlas lazily registers the colour atlas with
// the image cache and returns its entry. Called from `draw_text_runa`
// the first time a colour glyph is pushed — this has to happen during
// view (not at frame_end) so the entry's descriptor set is available
// for the same frame's render pass. Returns nil on registration
// failure (no colour glyphs render that frame).
@(private)
text_runa_ensure_color_atlas :: proc(rs: ^Text_Runa, r: ^Renderer) -> ^Image_Entry {
	if rs.color_atlas_registered {
		return image_cache_get(r, COLOR_ATLAS_KEY)
	}
	if len(rs.atlas.pages_color) == 0 { return nil }
	page := &rs.atlas.pages_color[0]
	if !image_load_pixels(r, COLOR_ATLAS_KEY, u32(page.width), u32(page.height), page.pixels) {
		return nil
	}
	rs.color_atlas_registered = true
	// Initial upload covered the current state; clear the dirty flag
	// so `text_upload_dirty_runa` doesn't re-upload the same bytes at
	// frame_end. Subsequent dirty rects (later frames) flow through
	// `image_update_pixels` normally.
	page.is_dirty  = false
	page.dirty_min = {}
	page.dirty_max = {}
	return image_cache_get(r, COLOR_ATLAS_KEY)
}

// text_runa_get_slot is the raster-cache lookup. On miss it rasterises
// + atlas-packs the glyph (mono path) and stores the result. Colour
// glyphs are rastered too but flagged `is_color`; draw_text_runa
// currently skips them — Phase 1b wires the RGBA atlas + shader.
@(private)
text_runa_get_slot :: proc(
	rs:       ^Text_Runa,
	font:     ^runa.Font,
	gid:      u16,
	px_size:  f32,
	subpx:   u8,
) -> (slot: runa.Atlas_Slot, ok: bool) {
	key := Glyph_Key{font = font, gid = gid, size_q = u32(px_size * 4), subpx = subpx}
	if existing, hit := rs.glyph_cache[key]; hit { return existing, true }

	s, err := runa.raster_glyph(font, gid, px_size, subpx, &rs.atlas)
	if err != .None { return }
	rs.glyph_cache[key] = s
	return s, true
}
