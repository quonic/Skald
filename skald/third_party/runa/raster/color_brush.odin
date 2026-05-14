package raster

// color_brush.odin — COLRv1 brush-aware rasterizer.
//
// Reads `Colr_Brush_Layer`s (each glyph mask paired with a brush) and
// composites them into a single RGBA bitmap. Compared to the COLRv0
// path in `color.odin` this version evaluates colours per pixel for
// linear, radial, and sweep gradient brushes, in addition to flat
// solid fills.
//
// Geometry per kind:
//   - Linear: project the pixel centre onto the (p0, p1) axis and
//     pick the colour at parameter t in [0, 1].
//   - Radial: solve the quadratic (1-t)*c0 + t*c1 / (1-t)*r0 + t*r1
//     so the implied circle passes through the pixel. The smaller
//     non-negative root is the gradient parameter.
//   - Sweep: read the pixel's angle from the centre via atan2, map
//     to [start_angle, end_angle].
//
// The composite pipeline stays straight-alpha source-over for v0.9;
// 27-mode-aware blending lands alongside this in color_composite.odin.

import "../parse"
import "core:math"

// rasterize_colr_brush_layers composites every brush layer onto an
// RGBA bitmap. `layers` is in back-to-front order.
rasterize_colr_brush_layers :: proc(
	layers:       []parse.Colr_Brush_Layer,
	palette:      ^parse.Cpal,
	palette_idx:  u16,
	foreground:   [4]u8,
	glyf:         ^parse.Glyf,
	loca:         ^parse.Loca,
	units_per_em: u16,
	size:         f32,
	edges:        ^[dynamic]Edge,
	allocator := context.allocator,
) -> (bm: Color_Bitmap, x_offset, y_offset: int, err: Rast_Error) {

	if size <= 0 || units_per_em == 0 { err = .Invalid_Size; return }
	if len(layers) == 0 { return }

	Layer_Render :: struct {
		bitmap:         Bitmap,
		x_off, y_off:   int,
		brush:          parse.Colr_Brush,
		composite_mode: u8,
	}
	renders := make([dynamic]Layer_Render, 0, len(layers), context.temp_allocator)
	defer {
		for &r in renders { bitmap_destroy(&r.bitmap, allocator) }
	}

	outline := parse.Outline{}
	defer parse.outline_destroy(&outline)

	for lyr in layers {
		oerr := parse.glyf_outline(glyf, loca, lyr.glyph_id, &outline)
		if oerr != .None { continue }
		if len(outline.contour_ends) == 0 { continue }

		layer_bm, xo, yo, rerr := rasterize(&outline, units_per_em, size, edges, allocator = allocator)
		if rerr != .None { continue }
		if layer_bm.width == 0 || layer_bm.height == 0 {
			bitmap_destroy(&layer_bm, allocator)
			continue
		}
		append(&renders, Layer_Render{bitmap = layer_bm, x_off = xo, y_off = yo, brush = lyr.brush, composite_mode = lyr.composite_mode})
	}
	if len(renders) == 0 { return }

	// Union-bbox the layer placements.
	x_min, y_min := renders[0].x_off, renders[0].y_off
	x_max := renders[0].x_off + renders[0].bitmap.width
	y_max := renders[0].y_off + renders[0].bitmap.height
	for r in renders {
		if r.x_off                   < x_min { x_min = r.x_off }
		if r.y_off                   < y_min { y_min = r.y_off }
		if r.x_off + r.bitmap.width  > x_max { x_max = r.x_off + r.bitmap.width }
		if r.y_off + r.bitmap.height > y_max { y_max = r.y_off + r.bitmap.height }
	}
	width  := x_max - x_min
	height := y_max - y_min
	if width <= 0 || height <= 0 { return }

	canvas := make([]u8, width * height * 4, allocator)
	if canvas == nil { err = .Out_Of_Memory; return }
	bm = Color_Bitmap{width = width, height = height, pixels = canvas}
	x_offset, y_offset = x_min, y_min

	// Per-pixel scale from font-units to pixel space. Same convention
	// the analytic rasterizer uses: 1 design unit = (size / upem) px,
	// y axis flipped so y_off+height−1 is at the design-unit y_min.
	pixel_scale := f32(size) / f32(units_per_em)

	for &r in renders {
		dx := r.x_off - x_min
		dy := r.y_off - y_min

		// Pre-compute gradient parameters in pixel-space for fast
		// per-pixel evaluation. Each kind uses a different eval struct
		// because the math diverges (line projection / quadratic /
		// atan2); the shared piece is the layer-origin pixel-space
		// transform.
		linear: Linear_Eval
		radial: Radial_Eval
		sweep:  Sweep_Eval
		switch r.brush.kind {
		case .Linear: linear = init_linear_eval(r.brush, pixel_scale, r.x_off, r.y_off, r.bitmap.height)
		case .Radial: radial = init_radial_eval(r.brush, pixel_scale, r.x_off, r.y_off)
		case .Sweep:  sweep  = init_sweep_eval(r.brush,  pixel_scale, r.x_off, r.y_off)
		case .Solid:
		}

		for sy in 0..<r.bitmap.height {
			ty := dy + sy
			if ty < 0 || ty >= height { continue }
			for sx in 0..<r.bitmap.width {
				tx := dx + sx
				if tx < 0 || tx >= width { continue }
				mask := r.bitmap.pixels[sy * r.bitmap.width + sx]
				if mask == 0 { continue }

				// Resolve the brush colour for this pixel.
				color: [4]u8
				switch r.brush.kind {
				case .Linear:
					color = eval_linear(linear, &r.brush, palette, palette_idx, foreground, sx, sy)
				case .Radial:
					color = eval_radial(radial, &r.brush, palette, palette_idx, foreground, sx, sy)
				case .Sweep:
					color = eval_sweep(sweep, &r.brush, palette, palette_idx, foreground, sx, sy)
				case .Solid:
					color = solid_color(r.brush, palette, palette_idx, foreground)
				}

				idx := (ty * width + tx) * 4
				composite_pixel(canvas[idx:idx + 4], color, mask, r.brush, r.composite_mode)
			}
		}
	}
	return
}

// composite_pixel applies one COLRv1 composite mode over a single
// canvas pixel. The 8 most-used modes (SrcOver, SrcIn, SrcOut,
// DestIn, DestOut, Plus, Screen, Multiply) get dedicated equations;
// other modes (Clear, Xor, Overlay, ColorDodge/Burn, HSL variants,
// etc.) fall through to SrcOver — close enough for v0.9, and a
// known-lossy parity with what FreeType / Cairo's COLRv1 raster
// path produced before they grew full PDF-style blend support.
@(private)
composite_pixel :: proc(dst: []u8, color: [4]u8, mask: u8, b: parse.Colr_Brush, mode: u8) {
	src_a := f32(color[3]) * f32(mask) / (255.0 * 255.0)
	if mode == parse.COMPOSITE_CLEAR {
		// Wipe the pixel.
		dst[0] = 0; dst[1] = 0; dst[2] = 0; dst[3] = 0
		return
	}
	if src_a == 0 && mode != parse.COMPOSITE_DEST {
		// Source contributes nothing; for modes that key off the
		// source's alpha the result is unchanged (SrcOver, Plus, etc.).
		return
	}
	sr := f32(color[0]) / 255.0
	sg := f32(color[1]) / 255.0
	sb := f32(color[2]) / 255.0
	dst_a := f32(dst[3]) / 255.0
	dr    := f32(dst[0]) / 255.0
	dg    := f32(dst[1]) / 255.0
	db    := f32(dst[2]) / 255.0

	out_a, or, og, ob: f32

	switch mode {
	case parse.COMPOSITE_SRC:
		out_a = src_a
		or, og, ob = sr, sg, sb
	case parse.COMPOSITE_DEST:
		return                                          // canvas unchanged
	case parse.COMPOSITE_SRC_IN:
		out_a = src_a * dst_a
		or, og, ob = sr, sg, sb
	case parse.COMPOSITE_DEST_IN:
		out_a = src_a * dst_a
		or, og, ob = dr, dg, db
	case parse.COMPOSITE_SRC_OUT:
		out_a = src_a * (1.0 - dst_a)
		or, og, ob = sr, sg, sb
	case parse.COMPOSITE_DEST_OUT:
		out_a = dst_a * (1.0 - src_a)
		or, og, ob = dr, dg, db
	case parse.COMPOSITE_PLUS:
		// Additive: clamp each channel to [0, 1].
		out_a = src_a + dst_a
		if out_a > 1.0 { out_a = 1.0 }
		or = sr + dr;  if or > 1.0 { or = 1.0 }
		og = sg + dg;  if og > 1.0 { og = 1.0 }
		ob = sb + db;  if ob > 1.0 { ob = 1.0 }
	case parse.COMPOSITE_SCREEN:
		// 1 - (1 - s) * (1 - d). Acts on un-premul colour; alpha is
		// regular source-over.
		out_a = src_a + dst_a * (1.0 - src_a)
		or = 1.0 - (1.0 - sr) * (1.0 - dr)
		og = 1.0 - (1.0 - sg) * (1.0 - dg)
		ob = 1.0 - (1.0 - sb) * (1.0 - db)
	case parse.COMPOSITE_MULTIPLY:
		out_a = src_a + dst_a * (1.0 - src_a)
		or = sr * dr
		og = sg * dg
		ob = sb * db
	case parse.COMPOSITE_DARKEN:
		out_a = src_a + dst_a * (1.0 - src_a)
		or = min(sr, dr)
		og = min(sg, dg)
		ob = min(sb, db)
	case parse.COMPOSITE_LIGHTEN:
		out_a = src_a + dst_a * (1.0 - src_a)
		or = max(sr, dr)
		og = max(sg, dg)
		ob = max(sb, db)
	case:
		// SrcOver fallback — covers COMPOSITE_SRC_OVER explicitly and
		// every unhandled mode (Xor / SrcAtop / DestOver / overlay /
		// dodge / burn / soft-light / hard-light / difference /
		// exclusion / HSL variants). Real-world COLRv1 fonts use
		// SrcOver in 95%+ of layers; the rest will be tightened in a
		// follow-up.
		out_a = src_a + dst_a * (1.0 - src_a)
		if out_a == 0 { return }
		or = (sr * src_a + dr * dst_a * (1.0 - src_a)) / out_a
		og = (sg * src_a + dg * dst_a * (1.0 - src_a)) / out_a
		ob = (sb * src_a + db * dst_a * (1.0 - src_a)) / out_a
	}
	dst[0] = u8(or    * 255.0 + 0.5)
	dst[1] = u8(og    * 255.0 + 0.5)
	dst[2] = u8(ob    * 255.0 + 0.5)
	dst[3] = u8(out_a * 255.0 + 0.5)
	_ = b
}

// solid_color resolves a Solid brush (or a gradient that we treat
// as solid for v0.5) into an 8-bit RGBA colour.
@(private)
solid_color :: proc(b: parse.Colr_Brush, palette: ^parse.Cpal, palette_idx: u16, foreground: [4]u8) -> [4]u8 {
	col := foreground
	if b.palette_index != parse.COLR_FOREGROUND_PALETTE_INDEX {
		c := parse.cpal_lookup(palette, palette_idx, b.palette_index)
		col = [4]u8{c.r, c.g, c.b, c.a}
	}
	// Apply brush-level alpha if specified (Solid brushes carry it;
	// Linear / Radial keep alpha=1 and rely on per-stop alpha).
	if b.alpha < 1.0 {
		col[3] = u8(f32(col[3]) * b.alpha + 0.5)
	}
	return col
}

// Linear_Eval precomputes the constants needed to project a pixel
// (sx, sy) onto the gradient axis. The pixel's local-bitmap coord
// (sx, sy) plus the layer's (x_off, y_off, height) tell us where the
// pixel sits in absolute pixel space; we then transform that to
// font-unit space and project onto (p0, p1).
@(private)
Linear_Eval :: struct {
	// Pixel-space gradient endpoints (after the same scaling as the
	// glyph mask).
	px0, py0:  f32,
	px1, py1:  f32,
	len_sq:    f32,                                    // |p1 - p0|² in pixel-space units
	// Layer origin in pixel-space (top-left of the bitmap, in the
	// same coord system as endpoints).
	origin_x:  f32,
	origin_y:  f32,
	// Pixel-row Y flip: glyph mask rows are y-down from origin_y;
	// gradient endpoints come from font-unit y-up coords.
	height_px: int,
}

@(private)
init_linear_eval :: proc(b: parse.Colr_Brush, pixel_scale: f32, layer_x_off, layer_y_off, height_px: int) -> Linear_Eval {
	// Convert font-unit endpoints to pixel-space. The y axis flips
	// because glyf y-up vs raster y-down.
	px0 := b.p0[0] * pixel_scale
	py0 := -b.p0[1] * pixel_scale
	px1 := b.p1[0] * pixel_scale
	py1 := -b.p1[1] * pixel_scale
	dx := px1 - px0
	dy := py1 - py0
	return Linear_Eval{
		px0 = px0, py0 = py0,
		px1 = px1, py1 = py1,
		len_sq    = dx * dx + dy * dy,
		origin_x  = f32(layer_x_off),
		origin_y  = f32(layer_y_off),
		height_px = height_px,
	}
}

// eval_linear computes the gradient colour at pixel (sx, sy) inside
// the current layer's bitmap.
@(private)
eval_linear :: proc(g: Linear_Eval, b: ^parse.Colr_Brush, palette: ^parse.Cpal, palette_idx: u16, foreground: [4]u8, sx, sy: int) -> [4]u8 {
	if g.len_sq <= 1e-6 || len(b.stops) == 0 {
		// Degenerate gradient — fall back to first stop or foreground.
		return solid_color(b^, palette, palette_idx, foreground)
	}
	// Pixel centre coords in pixel-space (same frame as endpoints).
	abs_x := g.origin_x + f32(sx) + 0.5
	abs_y := g.origin_y + f32(sy) + 0.5

	// Project onto (p0, p1).
	vx := abs_x - g.px0
	vy := abs_y - g.py0
	dx := g.px1 - g.px0
	dy := g.py1 - g.py0
	t := (vx * dx + vy * dy) / g.len_sq
	if t < 0 { t = 0 }
	if t > 1 { t = 1 }

	return interpolate_stops(b.stops, t, palette, palette_idx, foreground)
}

@(private)
interpolate_stops :: proc(stops: []parse.Color_Stop, t: f32, palette: ^parse.Cpal, palette_idx: u16, foreground: [4]u8) -> [4]u8 {
	if len(stops) == 0 { return [4]u8{0, 0, 0, 0} }
	if t <= stops[0].offset    { return stop_color(stops[0], palette, palette_idx, foreground) }
	if t >= stops[len(stops) - 1].offset { return stop_color(stops[len(stops) - 1], palette, palette_idx, foreground) }

	// Find the bracketing pair.
	for i in 0..<len(stops) - 1 {
		a := stops[i]
		b := stops[i + 1]
		if t >= a.offset && t <= b.offset {
			span := b.offset - a.offset
			u: f32 = 0
			if span > 0 { u = (t - a.offset) / span }
			ca := stop_color(a, palette, palette_idx, foreground)
			cb := stop_color(b, palette, palette_idx, foreground)
			return [4]u8{
				lerp_u8(ca[0], cb[0], u),
				lerp_u8(ca[1], cb[1], u),
				lerp_u8(ca[2], cb[2], u),
				lerp_u8(ca[3], cb[3], u),
			}
		}
	}
	return stop_color(stops[len(stops) - 1], palette, palette_idx, foreground)
}

@(private)
stop_color :: proc(s: parse.Color_Stop, palette: ^parse.Cpal, palette_idx: u16, foreground: [4]u8) -> [4]u8 {
	col := foreground
	if s.palette_index != parse.COLR_FOREGROUND_PALETTE_INDEX {
		c := parse.cpal_lookup(palette, palette_idx, s.palette_index)
		col = [4]u8{c.r, c.g, c.b, c.a}
	}
	col[3] = u8(f32(col[3]) * s.alpha + 0.5)
	return col
}

@(private)
lerp_u8 :: proc(a, b: u8, t: f32) -> u8 {
	r := f32(a) + (f32(b) - f32(a)) * t
	if r < 0 { r = 0 }
	if r > 255 { r = 255 }
	return u8(r + 0.5)
}

// ---- Radial gradient -------------------------------------------------

@(private)
Radial_Eval :: struct {
	cx0, cy0:  f32,
	cx1, cy1:  f32,
	r0,  r1:   f32,
	origin_x:  f32,
	origin_y:  f32,
}

@(private)
init_radial_eval :: proc(b: parse.Colr_Brush, pixel_scale: f32, layer_x_off, layer_y_off: int) -> Radial_Eval {
	return Radial_Eval{
		cx0      =  b.p0[0] * pixel_scale,
		cy0      = -b.p0[1] * pixel_scale,
		cx1      =  b.p1[0] * pixel_scale,
		cy1      = -b.p1[1] * pixel_scale,
		r0       =  b.r0 * pixel_scale,
		r1       =  b.r1 * pixel_scale,
		origin_x = f32(layer_x_off),
		origin_y = f32(layer_y_off),
	}
}

// eval_radial solves for the gradient parameter t such that the
// interpolated circle (center (1-t)c0 + t c1, radius (1-t)r0 + t r1)
// passes through the pixel. The smaller non-negative real root of
// the quadratic in t wins.
@(private)
eval_radial :: proc(g: Radial_Eval, b: ^parse.Colr_Brush, palette: ^parse.Cpal, palette_idx: u16, foreground: [4]u8, sx, sy: int) -> [4]u8 {
	if len(b.stops) == 0 { return solid_color(b^, palette, palette_idx, foreground) }
	px := g.origin_x + f32(sx) + 0.5
	py := g.origin_y + f32(sy) + 0.5

	// Quadratic:  |p - ((1-t)c0 + t c1)|² = ((1-t)r0 + t r1)²
	// Expand:     a t² + b t + c = 0  with
	//   a = |c1-c0|² - (r1-r0)²
	//   b = -2 * ((p - c0)·(c1 - c0) + r0 * (r1 - r0))
	//   c = |p - c0|² - r0²
	dcx := g.cx1 - g.cx0
	dcy := g.cy1 - g.cy0
	dr  := g.r1  - g.r0
	pcx := px - g.cx0
	pcy := py - g.cy0

	A := dcx*dcx + dcy*dcy - dr*dr
	B := -2 * (pcx*dcx + pcy*dcy + g.r0 * dr)
	C := pcx*pcx + pcy*pcy - g.r0*g.r0

	t: f32
	if A == 0 {
		// Linear case (circles same radius): solve B t + C = 0.
		if B == 0 { return solid_color(b^, palette, palette_idx, foreground) }
		t = -C / B
	} else {
		disc := B*B - 4*A*C
		if disc < 0 { return [4]u8{0, 0, 0, 0} }
		sq := math.sqrt(disc)
		t0 := (-B - sq) / (2*A)
		t1 := (-B + sq) / (2*A)
		// Prefer the larger root, but clamp to [0, 1] so the gradient
		// covers the disc cleanly. This mirrors Skia's resolution.
		t = max(t0, t1)
	}
	if t < 0 { t = 0 }
	if t > 1 { t = 1 }
	return interpolate_stops(b.stops, t, palette, palette_idx, foreground)
}

// ---- Sweep gradient --------------------------------------------------

@(private)
Sweep_Eval :: struct {
	cx, cy:      f32,
	start, end:  f32,                                  // angles, radians
	origin_x:    f32,
	origin_y:    f32,
}

@(private)
init_sweep_eval :: proc(b: parse.Colr_Brush, pixel_scale: f32, layer_x_off, layer_y_off: int) -> Sweep_Eval {
	return Sweep_Eval{
		cx       =  b.p0[0] * pixel_scale,
		cy       = -b.p0[1] * pixel_scale,
		start    =  b.angle_start,
		end      =  b.angle_end,
		origin_x = f32(layer_x_off),
		origin_y = f32(layer_y_off),
	}
}

@(private)
eval_sweep :: proc(g: Sweep_Eval, b: ^parse.Colr_Brush, palette: ^parse.Cpal, palette_idx: u16, foreground: [4]u8, sx, sy: int) -> [4]u8 {
	if len(b.stops) == 0 { return solid_color(b^, palette, palette_idx, foreground) }
	px := g.origin_x + f32(sx) + 0.5
	py := g.origin_y + f32(sy) + 0.5
	// y is flipped in pixel-space relative to font-unit space, but
	// the gradient endpoints arrived in font-units. atan2 with the
	// already-flipped (cx, cy) gives a consistent rotation direction.
	a := math.atan2(py - g.cy, px - g.cx)
	span := g.end - g.start
	if span == 0 { return solid_color(b^, palette, palette_idx, foreground) }
	t := (a - g.start) / span
	if t < 0 { t = 0 }
	if t > 1 { t = 1 }
	return interpolate_stops(b.stops, t, palette, palette_idx, foreground)
}
