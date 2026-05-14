package example_emoji_picker

import "core:strings"
import "gui:skald"

MAX_RECENTS :: 8

State :: struct {
	picked:  string,
	recents: [dynamic]string,   // most-recent-first
}

Msg :: union {
	Pick_Emoji,
}

Pick_Emoji :: struct { emoji: string }

@(private) fonts_ready: bool

init :: proc() -> State { return {} }

update :: proc(s: State, m: Msg) -> (State, skald.Command(Msg)) {
	s := s
	switch v in m {
	case Pick_Emoji:
		emoji := strings.clone(v.emoji)
		if len(s.picked) > 0 { delete(s.picked) }
		s.picked = strings.clone(emoji)
		// De-duplicate then push to the front. Cap to MAX_RECENTS so the
		// slice doesn't grow without bound.
		for r, i in s.recents {
			if r == emoji { delete(s.recents[i]); ordered_remove(&s.recents, i); break }
		}
		inject_at(&s.recents, 0, emoji)
		for len(s.recents) > MAX_RECENTS {
			delete(s.recents[len(s.recents)-1])
			pop(&s.recents)
		}
	}
	return s, {}
}

on_pick :: proc(e: string) -> Msg { return Pick_Emoji{emoji = e} }

view :: proc(s: State, ctx: ^skald.Ctx(Msg)) -> skald.View {
	th := ctx.theme

	if !fonts_ready && ctx.renderer != nil {
		skald.font_use_default_emoji(ctx.renderer)
		fonts_ready = true
	}

	display := s.picked
	if display == "" { display = "—" }

	return skald.col(
		skald.text("Emoji picker", th.color.fg, th.font.size_xl),
		skald.spacer(th.spacing.md),
		skald.text("Click the 😀 button. Search by name, switch categories, pick a skin tone.",
			th.color.fg_muted, th.font.size_sm, max_width = 560),
		skald.spacer(th.spacing.lg),
		skald.row(
			skald.emoji_picker(ctx, on_pick, recents = s.recents[:]),
			skald.spacer(th.spacing.lg),
			skald.text(display, th.color.fg, th.font.size_display),
			cross_align = .Center,
		),
		padding = th.spacing.xl,
		spacing = th.spacing.sm,
		cross_align = .Start,
	)
}

main :: proc() {
	skald.run(skald.App(State, Msg){
		title  = "Skald — Emoji Picker",
		size   = {720, 560},
		theme  = skald.theme_dark(),
		init   = init,
		update = update,
		view   = view,
	})
}
