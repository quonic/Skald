package example_audio

// Microphone capture + playback demo using skald/audio.odin.
//
// Pick a mic, hit Record (it captures raw f32 PCM into memory with a
// live input-level meter), hit Stop, then Play to hear it back. No
// codec — this is the raw-PCM platform API; encoding (Opus / AAC /
// etc.) is the app's job and out of scope for the demo.
//
// Polling model: while recording or playing, an Audio_Tick reschedules
// itself every 20 ms (50 Hz) so we drain the mic / watch playback
// without forcing always_redraw. Idle = no ticks = no work.

import "core:fmt"
import "core:math"
import "core:strings"
import "gui:skald"

SAMPLE_RATE :: 48000
CHANNELS    :: 1

State :: struct {
	// Device list, enumerated at startup + on Refresh. Heap-owned;
	// freed before re-enumeration.
	mics:         []skald.Audio_Device,
	mic_names:    []string,
	sel_mic_name: string,
	sel_mic_id:   u32,           // 0 = system default

	// Recording.
	recording: bool,
	capture:   ^skald.Audio_Capture,
	samples:   [dynamic]f32,     // recorded PCM
	level:     f32,              // current input RMS, 0..1, for the meter

	// Playback.
	playing:    bool,
	playback:   ^skald.Audio_Playback,
	play_total: int,             // samples written at play start (for progress)
}

Msg :: union {
	Refresh_Devices,
	Mic_Selected,
	Record_Toggle,
	Play_Toggle,
	Audio_Tick,
}

Refresh_Devices :: struct {}
Mic_Selected    :: distinct string
Record_Toggle   :: struct {}
Play_Toggle     :: struct {}
Audio_Tick      :: struct {}

init :: proc() -> State {
	s := State{}
	_refresh_devices(&s)
	return s
}

@(private)
_refresh_devices :: proc(s: ^State) {
	// Free the previous enumeration (names cloned into context.allocator).
	for d in s.mics do delete(d.name)
	delete(s.mics)
	delete(s.mic_names)

	s.mics = skald.audio_capture_devices(context.allocator)
	s.mic_names = make([]string, len(s.mics) + 1)
	s.mic_names[0] = "System default"
	for d, i in s.mics do s.mic_names[i + 1] = d.name
	if s.sel_mic_name == "" do s.sel_mic_name = "System default"
}

update :: proc(s: State, m: Msg) -> (State, skald.Command(Msg)) {
	out := s
	switch v in m {
	case Refresh_Devices:
		_refresh_devices(&out)

	case Mic_Selected:
		out.sel_mic_name = string(v)
		out.sel_mic_id = 0
		for d in out.mics {
			if d.name == string(v) { out.sel_mic_id = d.id; break }
		}

	case Record_Toggle:
		if out.recording {
			// Stop.
			skald.audio_capture_close(out.capture)
			out.capture = nil
			out.recording = false
			out.level = 0
		} else {
			// Start fresh — drop any prior take.
			clear(&out.samples)
			cap, ok := skald.audio_capture_open(
				device_id = out.sel_mic_id,
				rate      = SAMPLE_RATE,
				channels  = CHANNELS)
			if !ok do return out, {}
			out.capture   = cap
			out.recording = true
			return out, skald.cmd_delay(0.02, Msg(Audio_Tick{}))
		}

	case Play_Toggle:
		if out.playing {
			skald.audio_play_close(out.playback)
			out.playback = nil
			out.playing = false
		} else if len(out.samples) > 0 {
			pb, ok := skald.audio_play_open(rate = SAMPLE_RATE, channels = CHANNELS)
			if !ok do return out, {}
			skald.audio_play_write(pb, out.samples[:])
			out.playback   = pb
			out.playing     = true
			out.play_total = len(out.samples)
			return out, skald.cmd_delay(0.02, Msg(Audio_Tick{}))
		}

	case Audio_Tick:
		keep_ticking := false
		if out.recording && out.capture != nil {
			// Drain whatever the mic has queued.
			avail := skald.audio_capture_available(out.capture)
			if avail > 0 {
				buf := make([]f32, avail, context.temp_allocator)
				n := skald.audio_capture_read(out.capture, buf)
				// Append + compute RMS for the level meter.
				sum_sq: f32 = 0
				for i in 0..<n {
					append(&out.samples, buf[i])
					sum_sq += buf[i] * buf[i]
				}
				if n > 0 {
					rms := math.sqrt(sum_sq / f32(n))
					// Voice is quiet — scale up so the meter is lively.
					out.level = min(rms * 4, 1)
				}
			}
			keep_ticking = true
		}
		if out.playing && out.playback != nil {
			if skald.audio_play_queued(out.playback) <= 0 {
				skald.audio_play_close(out.playback)
				out.playback = nil
				out.playing = false
			} else {
				keep_ticking = true
			}
		}
		if keep_ticking do return out, skald.cmd_delay(0.02, Msg(Audio_Tick{}))
	}
	return out, {}
}

view :: proc(s: State, ctx: ^skald.Ctx(Msg)) -> skald.View {
	th := ctx.theme
	fg := th.color.fg

	secs := f32(len(s.samples)) / f32(SAMPLE_RATE * CHANNELS)

	rec_label := s.recording ? "■ Stop" : "● Record"
	rec_bg    := s.recording ? th.color.danger : th.color.primary

	play_disabled := s.recording || len(s.samples) == 0
	play_label := s.playing ? "■ Stop" : "▶ Play"

	// Level meter geometry: a coloured fill rect + a track-coloured
	// remainder rect, laid out in a row.
	meter_w :: f32(360)
	fill_w  := meter_w * s.level

	return skald.col(
		skald.text("Audio capture + playback", fg, th.font.size_lg),
		skald.spacer(8),
		skald.text(
			"Pick a mic, Record, Stop, then Play it back. Raw PCM — no codec.",
			th.color.fg_muted, th.font.size_sm),
		skald.spacer(16),

		// Device picker.
		skald.text("Microphone:", th.color.fg_muted, th.font.size_sm),
		skald.row(
			skald.select(ctx, s.sel_mic_name, s.mic_names,
				proc(v: string) -> Msg { return Mic_Selected(v) },
				width = 320),
			skald.spacer(8),
			skald.button(ctx, "Refresh", Refresh_Devices{},
				bg = th.color.surface, fg = fg),
			cross_align = .Center,
		),
		skald.spacer(16),

		// Transport.
		skald.row(
			skald.button(ctx, rec_label, Record_Toggle{}, bg = rec_bg),
			skald.spacer(8),
			skald.button(ctx, play_label, Play_Toggle{},
				bg = th.color.primary, disabled = play_disabled),
			cross_align = .Center,
		),
		skald.spacer(16),

		// Input level meter (only meaningful while recording).
		skald.text("Input level:", th.color.fg_muted, th.font.size_sm),
		skald.row(
			skald.rect({fill_w, 14}, th.color.primary, th.radius.sm),
			skald.rect({meter_w - fill_w, 14}, th.color.surface, th.radius.sm),
			spacing = 0,
		),
		skald.spacer(16),

		// Status.
		skald.text(
			fmt.tprintf("Recorded: %.1f s  (%d samples)", secs, len(s.samples)),
			fg, th.font.size_md),
		skald.text(
			s.recording ? "● recording…" : (s.playing ? "▶ playing…" : "idle"),
			th.color.fg_muted, th.font.size_sm),

		padding     = th.spacing.lg,
		spacing     = th.spacing.sm,
		cross_align = .Start,
	)
}

main :: proc() {
	skald.run(skald.App(State, Msg){
		title  = "Skald — audio capture + playback",
		size   = {560, 420},
		theme  = skald.theme_dark(),
		init   = init,
		update = update,
		view   = view,
	})
}
