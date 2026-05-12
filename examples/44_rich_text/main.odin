package example_rich_text

import "core:fmt"
import "core:strings"
import "gui:skald"

// rich_text skeleton smoke test. v1 of the widget: spans flow on a
// single line, per-span colour / weight / italic apply, no wrap yet.
// Subsequent commits on the feature/rich-text branch will add:
//
//   - word-wrap across span seams (max_width > 0)
//   - inline-code background fills + underline rendering
//   - per-span hit-test + clickable link spans + hover cursor
//   - an `examples/45` or similar that exercises everything together
//
// This file deliberately starts minimal — confirm the API shape and
// the per-span font + colour selection before the bigger pieces land.

State :: struct {
	last_link_clicked: string,
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
		out.last_link_clicked = strings.clone(string(v))
	}
	return out, {}
}

view :: proc(s: State, ctx: ^skald.Ctx(Msg)) -> skald.View {
	th := ctx.theme

	one_liner := skald.rich_text(ctx,
		[]skald.Text_Span{
			skald.span("The "),
			skald.span_bold("--sshkey"),
			skald.span(" flag tells syncoid to use a "),
			skald.span_bold("dedicated"),
			skald.span(" key for the "),
			skald.span_italic("automation job"),
			skald.span("."),
		},
		base = th.color.fg,
		size = th.font.size_md,
	)

	mix_sizes := skald.rich_text(ctx,
		[]skald.Text_Span{
			skald.span("Mixing "),
			skald.Text_Span{str = "sizes", size = th.font.size_xl, color = th.color.primary},
			skald.span(" and "),
			skald.Text_Span{str = "colours", color = th.color.danger, weight = .Bold},
			skald.span(" inline."),
		},
		base = th.color.fg,
		size = th.font.size_md,
	)

	// Wrapped paragraph: max_width = 420 forces word-wrap across
	// span seams. Bold / italic / regular runs must flow into one
	// another and break only on word boundaries, never inside a run.
	wrapped := skald.rich_text(ctx,
		[]skald.Text_Span{
			skald.span("Markdown rendering in chat needs "),
			skald.span_bold("bold"),
			skald.span(", "),
			skald.span_italic("italic"),
			skald.span(", and "),
			skald.Text_Span{str = "inline code", weight = .Bold, color = th.color.primary},
			skald.span(" all flowing through one wrapped paragraph. Long sentences word-wrap at spaces; runs split across visual lines if a break opportunity lands inside them, but never inside a word itself."),
		},
		base      = th.color.fg,
		size      = th.font.size_md,
		max_width = 420,
	)

	// Inline-code chips (bg fill) + clickable link spans. Using
	// rich_text_links here so the `on_link_click` callback fires when
	// the user releases a click on a link span; the mouse cursor also
	// switches to the hand pointer on hover.
	chips := skald.rich_text_links(ctx,
		[]skald.Text_Span{
			skald.span("Pass "),
			skald.Text_Span{
				str = "--sshkey",
				bg  = th.color.surface,
				color = th.color.primary,
			},
			skald.span(" to use a dedicated key, then visit "),
			skald.span_link("the docs", "https://example.com/docs", th.color.primary),
			skald.span(" or "),
			skald.span_link("the readme", "internal:readme", th.color.primary),
			skald.span(" for details."),
		},
		base          = th.color.fg,
		size          = th.font.size_md,
		max_width     = 460,
		on_link_click = proc(link: string) -> Msg { return Link_Clicked(link) },
	)

	last_clicked := s.last_link_clicked if len(s.last_link_clicked) > 0 else "(none yet)"
	clicked_line := skald.text(
		fmt.tprintf("Last link clicked: %s", last_clicked),
		th.color.fg_muted, th.font.size_sm,
	)

	return skald.col(
		skald.text("rich_text wrap + chrome (step 6)", th.color.fg, th.font.size_xl),
		skald.spacer(th.spacing.md),
		one_liner,
		skald.spacer(th.spacing.md),
		mix_sizes,
		skald.spacer(th.spacing.md),
		wrapped,
		skald.spacer(th.spacing.md),
		chips,
		skald.spacer(th.spacing.md),
		clicked_line,
		padding     = th.spacing.xl,
		spacing     = 0,
		cross_align = .Start,
	)
}

main :: proc() {
	skald.run(skald.App(State, Msg){
		title  = "Skald — rich_text",
		size   = {720, 480},
		theme  = skald.theme_dark(),
		init   = init,
		update = update,
		view   = view,
	})
}
