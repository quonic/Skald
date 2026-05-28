package skald

import "core:testing"

@(test)
outside_press_blurs_focused_widget :: proc(t: ^testing.T) {
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)

	id := Widget_ID(1)
	ws.focused_id = id
	ws.states[id] = Widget_State {
		kind       = .Button,
		last_rect  = {x = 10, y = 10, w = 80, h = 24},
		last_frame = ws.frame,
	}

	input := Input{mouse_pos = {200, 200}}
	input.mouse_pressed[.Left] = true

	widget_store_frame_reset(&ws)
	widget_store_blur_on_outside_press(&ws, input)

	testing.expect_value(t, ws.focused_id, Widget_ID(0))
}

@(test)
press_inside_overlay_keeps_focus :: proc(t: ^testing.T) {
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)

	id := Widget_ID(1)
	ws.focused_id = id
	ws.states[id] = Widget_State {
		kind       = .Select,
		last_rect  = {x = 10, y = 10, w = 120, h = 28},
		last_frame = ws.frame,
	}
	append(&ws.overlay_rects, Rect{x = 10, y = 42, w = 120, h = 90})

	input := Input{mouse_pos = {20, 60}}
	input.mouse_pressed[.Left] = true

	widget_store_frame_reset(&ws)
	widget_store_blur_on_outside_press(&ws, input)

	testing.expect_value(t, ws.focused_id, id)
}

@(test)
explicit_id_never_collides_with_auto_id :: proc(t: ^testing.T) {
	Msg :: distinct int
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)
	input: Input
	ctx := Ctx(Msg){widgets = &ws, input = &input}

	// A raw small-int explicit id (Widget_ID(1)) must NOT resolve to the same
	// value as the first positional auto-id (also internally 1) — otherwise a
	// widget with id=1 and an auto-id widget would alias and corrupt state
	// (the bug behind the spell-check menu failing to dismiss).
	raw_explicit := widget_resolve_id(&ctx, Widget_ID(1))
	auto_first   := widget_resolve_id(&ctx, 0) // explicit==0 -> first auto-id

	testing.expect(t, raw_explicit != auto_first,
		"raw explicit id must not collide with an auto-id")
	testing.expect(t, raw_explicit & WIDGET_ID_EXPLICIT_BIT != 0,
		"explicit id must live in the high (explicit) namespace")
	testing.expect(t, auto_first & WIDGET_ID_EXPLICIT_BIT == 0,
		"unscoped auto-id must stay in the low namespace")

	// hash_id already carries the bit, so resolving it is idempotent — the
	// documented path is byte-for-byte unchanged.
	h := hash_id("editor")
	testing.expect_value(t, widget_resolve_id(&ctx, h), h)
}
