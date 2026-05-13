package example_color_emoji

import "core:fmt"
import "core:os"
import "gui:skald"

// Colour-emoji smoke test for the runa text backend (Phase 1b).
//
// Loads Twemoji-Mozilla (COLRv0 layered colour font) from the
// sibling runa repo at first-frame time and registers it as a
// fallback to the bundled Inter face. Runa's per-codepoint fallback
// picker then routes emoji codepoints (🦊, 🚀, 🎉, etc.) to Twemoji
// while Latin / Cyrillic / Greek text stays in Inter.
//
// Run with `SKALD_RUNA=1 ./build.sh 45_color_emoji run`. Under
// fontstash (the default) emoji render as `.notdef` boxes — there's
// no equivalent fallback path. Under runa the emoji render as full
// COLRv0 colour glyphs sampled from the RGBA atlas via the existing
// `image_cache` → `batch_push_image` plumbing.

State :: struct {}
Msg   :: struct {}

EMOJI_PATH :: "../runa/tests/fonts/Twemoji-Mozilla.ttf"

@(private)
fonts_ready: bool

init :: proc() -> State { return {} }
update :: proc(s: State, m: Msg) -> (State, skald.Command(Msg)) { return s, {} }

view :: proc(s: State, ctx: ^skald.Ctx(Msg)) -> skald.View {
	th := ctx.theme

	// Lazy one-shot fallback registration. Mirrors examples/39_icons.
	if !fonts_ready && ctx.renderer != nil {
		data, err := os.read_entire_file_from_path(EMOJI_PATH, context.allocator)
		if err != nil {
			fmt.eprintln("45_color_emoji: failed to read", EMOJI_PATH, "—", err)
		} else {
			fnt := skald.font_load(ctx.renderer, "twemoji", data)
			if int(fnt) >= 0 {
				skald.font_add_fallback(ctx.renderer, skald.font_default(ctx.renderer), fnt)
			}
		}
		fonts_ready = true
	}

	return skald.col(
		skald.text("Skald — Colour Emoji (runa)", th.color.fg, th.font.size_xl),
		skald.spacer(th.spacing.md),
		skald.text("Latin text mixes with Twemoji glyphs via the runa fallback chain.",
			th.color.fg_muted, th.font.size_md, max_width = 560),
		skald.spacer(th.spacing.lg),
		skald.text("Hello, world! 🦊", th.color.fg, th.font.size_display),
		skald.spacer(th.spacing.md),
		skald.text("Status: 🚀 shipped · 🐛 fixed · 🎉 celebrated", th.color.fg, th.font.size_lg),
		skald.spacer(th.spacing.md),
		skald.text("Stars: ★ ★ ★ ☆ ☆", th.color.fg, th.font.size_md),
		padding     = th.spacing.xl,
		cross_align = .Start,
	)
}

main :: proc() {
	skald.run(skald.App(State, Msg){
		title  = "Skald — Colour Emoji",
		size   = {640, 360},
		theme  = skald.theme_dark(),
		init   = init,
		update = update,
		view   = view,
	})
}
