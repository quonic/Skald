package example_selectable_text

import "core:fmt"
import "core:strings"
import "gui:skald"

// Demonstrates the three selectable-text widgets:
//
//   - text_selectable               — plain text that supports
//                                     click-drag selection, double-click
//                                     word, triple-click select-all,
//                                     Ctrl-A / Ctrl-C.
//   - rich_text_selectable          — same input behaviour, but content
//                                     is a span list (bold / italic /
//                                     colour / size). Selection ranges
//                                     are byte offsets into the
//                                     spans-concatenation.
//   - rich_text_selectable_links    — adds clickable link spans on top.
//                                     A quick press-and-release on a
//                                     link fires its callback; a
//                                     press-then-drag past a small
//                                     threshold starts selection
//                                     instead. Multi-click (double /
//                                     triple) cancels the pending link
//                                     fire so word / select-all wins.
//
// Use this as a reference when you need copyable chat-bubble bodies,
// log entries the user wants to grab a substring of, or any prose
// region whose text needs to leave the app via the clipboard.

State :: struct {
	last_link: string,
}

Msg :: union {
	Link_Clicked,
}

Link_Clicked :: distinct string

init :: proc() -> State { return {} }

update :: proc(s: State, m: Msg) -> (State, skald.Command(Msg)) {
	out := s
	switch v in m {
	case Link_Clicked:
		delete(out.last_link)
		out.last_link = strings.clone(string(v))
	}
	return out, {}
}

on_link :: proc(target: string) -> Msg { return Link_Clicked(target) }

view :: proc(s: State, ctx: ^skald.Ctx(Msg)) -> skald.View {
	th := ctx.theme
	fg      := th.color.fg
	muted   := th.color.fg_muted
	primary := th.color.primary
	sz      := th.font.size_md

	// --- text_selectable ------------------------------------------------
	plain_label := skald.text("text_selectable — plain string, copyable",
		muted, th.font.size_sm)
	plain := skald.text_selectable(ctx,
		"Click and drag to select any part of this sentence. Ctrl+C copies the selection to the clipboard; paste it into a terminal to confirm.",
		fg, sz, max_width = 540)

	plain_multiline_label := skald.text("text_selectable — wrapped paragraph",
		muted, th.font.size_sm)
	plain_multiline := skald.text_selectable(ctx,
		"Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Selection follows the wrap; double-click selects the word under the cursor; triple-click selects everything.",
		fg, sz, max_width = 540)

	// --- rich_text_selectable ------------------------------------------
	rich_label := skald.text("rich_text_selectable — mixed-format spans, copy strips styling",
		muted, th.font.size_sm)
	rich := skald.rich_text_selectable(ctx,
		[]skald.Text_Span{
			{str = "Drag across these ",      color = fg, size = sz},
			{str = "bold",                    color = fg, size = sz, weight = .Bold},
			{str = " and ",                   color = fg, size = sz},
			{str = "italic",                  color = primary, size = sz, italic = true},
			{str = " spans — selection ",     color = fg, size = sz},
			{str = "spans the boundaries",    color = fg, size = sz, underline = true},
			{str = " cleanly, and copy returns plain text.", color = fg, size = sz},
		},
		base = fg, size = sz, max_width = 540)

	// --- rich_text_selectable_links ------------------------------------
	link_label := skald.text("rich_text_selectable_links — clickable links inside selectable prose",
		muted, th.font.size_sm)
	link_block := skald.rich_text_selectable_links(ctx,
		[]skald.Text_Span{
			{str = "Read ",                            color = fg, size = sz},
			{str = "the announcement",                 color = primary, size = sz, underline = true, link = "https://example.com/announcement"},
			{str = " or skim ",                        color = fg, size = sz},
			{str = "the docs",                         color = primary, size = sz, underline = true, link = "https://example.com/docs"},
			{str = ". Quick tap on a link fires its callback; press-and-drag starts a selection instead. Double-click selects the word, triple-click selects all — multi-click on a link cancels the link fire.",
				color = fg, size = sz},
		},
		base = fg, on_link_click = on_link, size = sz, max_width = 540)

	feedback := skald.text(
		fmt.tprintf("Last link clicked: %q", s.last_link),
		muted, th.font.size_sm)

	return skald.col(
		skald.text("Selectable text widgets", fg, th.font.size_lg),
		skald.spacer(8),
		skald.text(
			"Three opt-in variants of static text that the user can select and copy. Plain text and rich text rendering otherwise stays the same.",
			muted, th.font.size_sm, max_width = 540),
		skald.spacer(16),

		plain_label,
		plain,
		skald.spacer(12),

		plain_multiline_label,
		plain_multiline,
		skald.spacer(12),

		rich_label,
		rich,
		skald.spacer(12),

		link_label,
		link_block,
		skald.spacer(4),
		feedback,

		padding     = th.spacing.lg,
		spacing     = th.spacing.md,
		cross_align = .Start,
	)
}

main :: proc() {
	skald.run(skald.App(State, Msg){
		title  = "Skald — selectable text",
		size   = {700, 740},
		theme  = skald.theme_dark(),
		init   = init,
		update = update,
		view   = view,
	})
}
