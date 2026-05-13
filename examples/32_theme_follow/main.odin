package example_theme_follow

import "core:fmt"
import "gui:skald"

// Follows the OS dark/light preference. Seeds from `system_theme()`
// in main, then swaps on `on_system_theme_change` so flipping the
// setting in System Settings / GNOME Tweaks / Windows Personalization
// updates the running window.
//
// On Linux, detection depends on the desktop environment publishing
// the preference — GNOME (via XDG portal) works; some WMs return
// `.Unknown`, in which case the app stays on whatever it started with.

State :: struct {
	sys_theme: skald.System_Theme,
}

Msg :: union {
	Theme_Changed,
}

Theme_Changed :: distinct skald.System_Theme

on_theme_change :: proc(new_theme: skald.System_Theme) -> Msg {
	return Theme_Changed(new_theme)
}

theme_for :: proc(sys: skald.System_Theme) -> skald.Theme {
	return skald.theme_light() if sys == .Light else skald.theme_dark()
}

init :: proc() -> State {
	return State{sys_theme = skald.system_theme()}
}

update :: proc(s: State, m: Msg) -> (State, skald.Command(Msg)) {
	out := s
	switch v in m {
	case Theme_Changed:
		out.sys_theme = skald.System_Theme(v)
		// Tell the runtime to swap the active theme on the next
		// frame. Cleaner than mutating `ctx.theme^` from view —
		// state changes belong in update.
		return out, skald.cmd_set_theme(Msg, theme_for(out.sys_theme))
	}
	return out, {}
}

view :: proc(s: State, ctx: ^skald.Ctx(Msg)) -> skald.View {
	th := ctx.theme
	label := fmt.tprintf("OS theme: %v", s.sys_theme)

	return skald.col(
		skald.text("Skald — System Theme Follow", th.color.fg, th.font.size_xl),
		skald.spacer(th.spacing.sm),
		skald.text(label, th.color.fg_muted, th.font.size_md),
		skald.spacer(th.spacing.md),
		skald.text(
			"Flip your OS dark/light setting — this window updates live.",
			th.color.fg_muted, th.font.size_sm,
			max_width = 480,
		),
		padding     = th.spacing.xl,
		cross_align = .Start,
	)
}

main :: proc() {
	sys := skald.system_theme()
	skald.run(skald.App(State, Msg){
		title  = "Skald — Theme Follow",
		size   = {560, 320},
		theme  = theme_for(sys),
		init   = init,
		update = update,
		view   = view,
		on_system_theme_change = on_theme_change,
	})
}
