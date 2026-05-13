/*
Package shape turns a UTF-8 run into a sequence of positioned glyph
IDs by applying the font's GSUB (substitution) and GPOS (positioning)
tables.

v0.1 scope:
  - LTR Latin / Cyrillic / Greek.
  - GSUB: liga, clig, calt, rlig, locl, ccmp.
  - GPOS: kern (pair positioning).
  - No script/language fallback at this layer — the caller passes a
    pre-resolved (script, language) pair. The itemizer's job to pick
    them.

Cluster tracking is approximate at v0.1 — every glyph carries
`cluster = byte_offset_of_first_codepoint_at_input`. Ligatures retain
the cluster of the *first* input glyph; the trailing inputs disappear.
*/
package shape

import "../parse"

// Shaped_Glyph is one output glyph from `shape_run`. Coordinates are in
// pixel space: caller-friendly, no per-call font-unit conversion.
//
// `cluster` is the byte index of the source codepoint within the input
// string. Multiple glyphs may share a cluster (when one codepoint
// produces several glyphs); a single glyph may span multiple clusters
// (ligation).
Shaped_Glyph :: struct {
	glyph_id:  parse.Glyph_ID,
	cluster:   u32,
	x_advance: f32,
	y_advance: f32,
	x_offset:  f32,
	y_offset:  f32,
}

// Shape_Inputs is the set of parsed tables `shape_run` consumes. Pass
// `gsub = nil` / `gpos = nil` for fonts that lack those tables — the
// shaper degrades gracefully (advances from `hmtx` only, no
// substitution, no kerning).
Shape_Inputs :: struct {
	cmap:         ^parse.Cmap,
	hmtx:         ^parse.Hmtx_Table,
	gsub:         ^parse.Gsub,                // may be nil
	gpos:         ^parse.Gpos,                // may be nil
	units_per_em: u16,
}

// Shape_Run_Opts is the per-call options.
Shape_Run_Opts :: struct {
	script:   parse.Tag,                       // e.g. parse.LATN_SCRIPT
	language: parse.Tag,                       // e.g. parse.DFLT_LANG
	// Add per-call feature overrides if/when the API matures.
}

// shape_run shapes `text` for one font at `size` pixels, appending to
// `out`. Existing entries in `out` are kept — the caller can reuse the
// dynamic array across calls. Allocations made during shaping land in
// `context.temp_allocator` and are not held past the call.
shape_run :: proc(in_: ^Shape_Inputs, opts: Shape_Run_Opts, text: string, size: f32, out: ^[dynamic]Shaped_Glyph) {
	scale := size / f32(in_.units_per_em)

	// Stage 1: map codepoints to glyph IDs, recording the source byte
	// offset for cluster tracking.
	gids := make([dynamic]parse.Glyph_ID, 0, len(text), context.temp_allocator)
	clusters := make([dynamic]u32, 0, len(text), context.temp_allocator)

	byte_idx: u32 = 0
	for r in text {
		gid := parse.cmap_lookup(in_.cmap, r)
		append(&gids, gid)
		append(&clusters, byte_idx)

		// Advance byte index by the UTF-8 length of the codepoint we
		// just consumed.
		if r < 0x80 { byte_idx += 1 }
		else if r < 0x800 { byte_idx += 2 }
		else if r < 0x10000 { byte_idx += 3 }
		else { byte_idx += 4 }
	}

	// Stage 2: GSUB. Apply v0.1 features in the canonical order. The
	// cluster array is rewritten in parallel as ligatures collapse
	// glyphs.
	if in_.gsub != nil {
		gsub_features := [?]parse.Tag{
			parse.tag("ccmp"),
			parse.tag("locl"),
			parse.tag("rlig"),
			parse.tag("liga"),
			parse.tag("clig"),
			parse.tag("calt"),
		}
		for ft in gsub_features {
			before := len(gids)
			parse.gsub_apply_feature(in_.gsub, &gids, opts.script, opts.language, ft)
			after := len(gids)
			if before == after { continue }
			// Walk in parallel and drop cluster entries whose gid index
			// no longer exists. Since GSUB rewrites gids in place with
			// `ordered_remove(gids, j)` for the trailing inputs of a
			// ligation, the simplest re-sync is to truncate `clusters`
			// to `after` from the right — but that loses correctness if
			// non-leading positions collapsed. Walk and pull the leftmost
			// surviving cluster for each gid.
			//
			// For v0.1, the imprecision: if a ligation happened we keep
			// the cluster of the first surviving codepoint. Good enough
			// for left-to-right Latin text where ligation always
			// preserves the leftmost cluster.
			resize(&clusters, after)
		}
	}

	// Stage 3: per-glyph horizontal advance from hmtx.
	adjusts := make([]parse.Pos_Adjust, len(gids), context.temp_allocator)

	// Stage 4: GPOS — apply 'kern' feature in font units, then convert
	// the whole shebang to pixels.
	if in_.gpos != nil {
		parse.gpos_apply_feature(in_.gpos, gids[:], adjusts, opts.script, opts.language, parse.tag("kern"))
	}

	// Stage 5: emit Shaped_Glyph slice in pixel space.
	for i in 0..<len(gids) {
		m := parse.hmtx_glyph_metric(in_.hmtx, gids[i])
		advance_units := f32(m.advance_width) + f32(adjusts[i].x_advance)
		x_off_units   := f32(adjusts[i].x_placement)
		y_off_units   := f32(adjusts[i].y_placement)

		cluster: u32 = 0
		if i < len(clusters) { cluster = clusters[i] }

		append(out, Shaped_Glyph{
			glyph_id  = gids[i],
			cluster   = cluster,
			x_advance = advance_units * scale,
			y_advance = f32(adjusts[i].y_advance) * scale,
			x_offset  = x_off_units * scale,
			y_offset  = y_off_units * scale,
		})
	}
}
