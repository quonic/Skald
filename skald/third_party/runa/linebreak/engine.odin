/*
UAX #14 line-break opportunity engine.

Implements LB1 (class resolution) plus LB4..LB31 in pair form, with
SP-skip state so the "OP SP* ×", "CL SP* × NS" and similar rules
work without sprinkling lookaheads into every caller.

Rules left out at v0.1:
  - LB1's AI / SA / SG / CJ aren't tailored — they get the simple
    AL / NS / NS fallbacks. LineBreakTest expects the same default.
  - LB15a / LB15b / LB15c / LB15d / LB15e / LB15f (quotation-context):
    the LB19 simple form is used instead — × QU / QU ×.
  - LB21a (HL HY/BA × …): needs Hebrew-letter state we don't track.
  - LB30a / LB30b's regional-indicator parity counting: simplified.

References: UAX #14 §6, https://www.unicode.org/reports/tr14/
*/
package linebreak

// Opportunity classifies a break position between two codepoints.
Opportunity :: enum u8 {
	None,       // × — must NOT break here
	Allow,      // ÷ — may break here
	Mandatory,  // ÷! — MUST break here (LB4/LB5)
}

// next_break walks `text` forward from `start` and returns the
// codepoint index at the next allowed break opportunity, plus a
// flag for whether the rules made the break *mandatory* (e.g. CR
// LF in the input). When no internal break opportunity exists the
// procedure returns `(len(text), true)` per LB3 (always break at
// eot).
next_break :: proc(text: []rune, start: int) -> (idx: int, mandatory: bool) {
	if start >= len(text) { return len(text), true }

	// LB1 resolution. AI / SG / XX collapse to AL — they're "weak"
	// classes that fall back to alphabetic. SA needs more care: per
	// LB1, SA codepoints that are combining marks resolve to CM (so
	// they attach via LB9); other SA codepoints resolve to AL. CJ
	// resolves to NS (strict).
	resolve :: proc(c: Line_Break_Class, r: rune) -> Line_Break_Class {
		#partial switch c {
		case .AI, .SG, .XX:
			return .AL
		case .SA:
			return .CM if sa_resolves_to_cm(r) else .AL
		case .CJ:
			return .NS
		}
		return c
	}

	prev := resolve(line_break_class(text[start]), text[start])
	// LB10: a CM / ZWJ at start-of-text has no base to attach to.
	// Treat it as AL for rule-matching purposes.
	if prev == .CM || prev == .ZWJ { prev = .AL }
	// `non_sp` tracks the most recent non-SP, post-CM class — the
	// "effective predecessor" for SP-skip rules (LB14, LB16, LB17,
	// LB19, LB25 chains).
	non_sp := prev
	// LB30a regional-indicator parity counter — pairs of RI bind.
	ri_run := prev == .RI ? 1 : 0

	// LB15a tracking: non_sp_was_pi_qu_after_opener is true when
	// non_sp came from an opener-preceded Pi-QU. At sot the "before"
	// position is one of LB15a's openers, so a leading Pi-QU
	// qualifies.
	non_sp_is_pi_after_opener := prev == .QU && is_pi_punctuation(text[start])
	// "What was non_sp before the current non_sp" — needed when a
	// Pi-QU lands and we check what preceded it.
	prev_non_sp_before_cur_non_sp: Line_Break_Class = .BK  // pretend sot
	prev_rune := text[start]
	// LB25 numeric-chain state. Once a NU starts the chain, it stays
	// open through NU / SY / IS / CL / CP and lets `(CL|CP) × (PO|PR)`
	// fire. Anything outside that set breaks the chain.
	in_num_chain := prev == .NU

	for i := start + 1; i < len(text); i += 1 {
		cur_raw := line_break_class(text[i])
		cur := resolve(cur_raw, text[i])

		// LB9 / LB10: CM and ZWJ attach to a base. If `prev` is one of
		// the break-causing classes (BK, CR, LF, NL, SP, ZW), the CM /
		// ZWJ has nothing to attach to — LB10 says treat it as AL and
		// apply rules normally. Otherwise (LB9) the CM / ZWJ inherits
		// `prev`'s class for rule-matching, which we approximate by
		// not advancing state.
		if cur == .CM || cur == .ZWJ {
			lb10_applies := prev == .BK || prev == .CR || prev == .LF ||
			                prev == .NL || prev == .SP || prev == .ZW
			if !lb10_applies {
				continue
			}
			cur = .AL
		}

		op := classify(prev, non_sp, cur, ri_run, text[i], prev_rune, in_num_chain)

		// LB15a override: × (anything) when the most-recent non-SP is
		// a Pi-QU and that Pi-QU was preceded by sot or an LB15a
		// "opener" class.
		if op == .Allow && non_sp_is_pi_after_opener {
			op = .None
		}

		// LB15b override: × Pf-QU when Pf-QU is followed by SP / ZW /
		// CL / CP / EX / IS / SY / BK / CR / LF / NL or eot. The
		// lookahead skips SPs that follow Pf-QU.
		if op == .Allow && cur == .QU && is_pf_punctuation(text[i]) {
			next_cls := next_nonsp_class(text, i + 1)
			if lb15b_closer(next_cls) {
				op = .None
			}
		}

		switch op {
		case .Mandatory: return i, true
		case .Allow:     return i, false
		case .None:      // fall through
		}

		// State updates for the next iteration.
		prev_rune = text[i]
		// LB25 numeric chain: open on NU, extend through NU/SY/IS/CL/CP,
		// close on anything else.
		if cur == .NU {
			in_num_chain = true
		} else if in_num_chain && (cur == .SY || cur == .IS || cur == .CL || cur == .CP) {
			// still in chain
		} else {
			in_num_chain = false
		}
		if cur == .RI {
			if prev == .RI && ri_run > 0 { ri_run = 0 } else { ri_run += 1 }
		} else {
			ri_run = 0
		}
		if cur != .SP {
			// LB15a tracking: did this new non_sp become a Pi-QU that
			// was preceded by an LB15a opener?
			//   Openers: sot (handled by initialisation), BK, CR, LF,
			//            NL, OP, QU, GL, SP, ZW.
			if cur == .QU && is_pi_punctuation(text[i]) && lb15a_opener(non_sp) {
				non_sp_is_pi_after_opener = true
			} else {
				non_sp_is_pi_after_opener = false
			}
			prev_non_sp_before_cur_non_sp = non_sp
			non_sp = cur
		}
		prev = cur
	}
	return len(text), true
}

@(private)
lb15a_opener :: proc(c: Line_Break_Class) -> bool {
	#partial switch c {
	case .BK, .CR, .LF, .NL, .OP, .QU, .GL, .SP, .ZW: return true
	}
	return false
}

@(private)
lb15b_closer :: proc(c: Line_Break_Class) -> bool {
	#partial switch c {
	case .BK, .CR, .LF, .NL, .SP, .ZW, .CL, .CP, .EX, .IS, .SY: return true
	}
	return false
}

// next_nonsp_class scans `text` from `start` forward, skipping SP
// codepoints, and returns the resolved Line_Break_Class of the next
// non-SP codepoint, or `.BK` as a sentinel for end-of-text (which
// behaves like an LB15b closer per the rule).
@(private)
next_nonsp_class :: proc(text: []rune, start: int) -> Line_Break_Class {
	for i := start; i < len(text); i += 1 {
		c := line_break_class(text[i])
		if c != .SP { return c }
	}
	return .BK
}

@(private)
classify :: proc(prev, non_sp_prev, cur: Line_Break_Class, ri_run: int, cur_rune, prev_rune: rune, in_num_chain: bool) -> Opportunity {
	// Helpers for LB28a Aksara cluster rules (Indic / Brahmic).
	// `25CC` (DOTTED CIRCLE, class AL) acts as an Aksara base for
	// these rules.
	is_ak_base :: proc(c: Line_Break_Class, r: rune) -> bool {
		return c == .AK || c == .AS || r == 0x25CC
	}
	// ---- LB4 / LB5: hard breaks --------------------------------------
	if prev == .BK { return .Mandatory }
	if prev == .CR && cur != .LF { return .Mandatory }
	if prev == .LF || prev == .NL { return .Mandatory }

	// ---- LB6: never break before mandatory-break characters ----------
	if cur == .BK || cur == .CR || cur == .LF || cur == .NL { return .None }

	// ---- LB7: never break before SP / ZW -----------------------------
	if cur == .SP || cur == .ZW { return .None }

	// ---- LB8: break after ZW ----------------------------------------
	// (LB8a: × ZWJ — handled by the CM/ZWJ shortcut in the walker.)
	if prev == .ZW { return .Allow }

	// ---- LB11: WJ × and × WJ ----------------------------------------
	if cur == .WJ || prev == .WJ { return .None }

	// ---- LB12 / LB12a: GL --------------------------------------------
	if prev == .GL { return .None }
	if cur == .GL {
		// LB12a: × GL except when prev is SP / BA / HY. (CB is *not*
		// an exception — LB12a fires first, before LB20 can break.)
		#partial switch prev {
		case .SP, .BA, .HY: // natural break — let later rules decide
		case:               return .None
		}
	}

	// ---- LB13: × CL / CP / EX / IS / SY ------------------------------
	if cur == .CL || cur == .CP || cur == .EX || cur == .IS || cur == .SY {
		return .None
	}

	// ---- LB14: OP SP* × ---------------------------------------------
	if non_sp_prev == .OP { return .None }

	// ---- LB15a / 15b / 15c / 15d / 15e / 15f: QU context-quotation ---
	// v0.1 falls back to LB19's simple × QU / QU ×.

	// ---- LB16: CL/CP SP* × NS ---------------------------------------
	if cur == .NS && (non_sp_prev == .CL || non_sp_prev == .CP) {
		return .None
	}

	// ---- LB17: B2 SP* × B2 ------------------------------------------
	if cur == .B2 && non_sp_prev == .B2 { return .None }

	// ---- LB18: SP ÷ --------------------------------------------------
	if prev == .SP { return .Allow }

	// ---- LB19: × QU and QU × -----------------------------------------
	if cur == .QU || prev == .QU { return .None }

	// ---- LB20: ÷ CB and CB ÷ -----------------------------------------
	if cur == .CB || prev == .CB { return .Allow }

	// ---- LB21: × BA / HY / HH / NS; BB × ------------------------------
	if cur == .BA || cur == .HY || cur == .HH || cur == .NS { return .None }
	if prev == .BB { return .None }
	// (`× BB` and `× HH` are NOT rules — break opportunities are
	// allowed AFTER HH except in specific contexts.)

	// ---- LB22: × IN --------------------------------------------------
	if cur == .IN { return .None }

	// ---- LB23: (AL|HL) × NU; NU × (AL|HL) ----------------------------
	if (prev == .AL || prev == .HL) && cur == .NU { return .None }
	if prev == .NU && (cur == .AL || cur == .HL) { return .None }

	// ---- LB23a: PR × (ID|EB|EM); (ID|EB|EM) × PO ----------------------
	if prev == .PR && (cur == .ID || cur == .EB || cur == .EM) { return .None }
	if (prev == .ID || prev == .EB || prev == .EM) && cur == .PO { return .None }

	// ---- LB24: (PR|PO) × (AL|HL); (AL|HL) × (PR|PO) -------------------
	if (prev == .PR || prev == .PO) && (cur == .AL || cur == .HL) { return .None }
	if (prev == .AL || prev == .HL) && (cur == .PR || cur == .PO) { return .None }

	// ---- LB25: numeric expressions (simplified subset) ---------------
	// NU × (NU | SY | IS); (PR | PO) × NU; NU × (CL | CP);
	// (CL | CP) × (PO | PR); etc.
	if prev == .NU && (cur == .NU || cur == .SY || cur == .IS) { return .None }
	if (prev == .PR || prev == .PO) && cur == .NU { return .None }
	if prev == .NU && (cur == .CL || cur == .CP) { return .None }
	// LB25: (NU)(CL|CP) × (PO|PR) — only inside an open numeric chain.
	if in_num_chain && (prev == .CL || prev == .CP) && (cur == .PO || cur == .PR) {
		return .None
	}
	if prev == .NU && cur == .NU { return .None }
	// LB25 extension: SY/IS chains feeding into a numeric.
	if (prev == .SY || prev == .IS) && cur == .NU { return .None }

	// ---- LB26 / LB27: Hangul -----------------------------------------
	if prev == .JL && (cur == .JL || cur == .JV || cur == .H2 || cur == .H3) {
		return .None
	}
	if (prev == .JV || prev == .H2) && (cur == .JV || cur == .JT) { return .None }
	if (prev == .JT || prev == .H3) && cur == .JT { return .None }
	if (prev == .JL || prev == .JV || prev == .JT || prev == .H2 || prev == .H3) && cur == .PO {
		return .None
	}
	if prev == .PR && (cur == .JL || cur == .JV || cur == .JT || cur == .H2 || cur == .H3) {
		return .None
	}

	// ---- LB28: (AL|HL) × (AL|HL) -------------------------------------
	if (prev == .AL || prev == .HL) && (cur == .AL || cur == .HL) { return .None }

	// ---- LB28a: Aksara cluster (Brahmic-script bind) -----------------
	// (AK | 25CC | AS) × (VF | VI)
	// AP × (AK | 25CC | AS)
	// Subset of LB28a; the lookahead variants ("(AK|…) × (AK|…) VF"
	// and "(AK|…) VI × (AK|…)") need state we don't yet track.
	if is_ak_base(prev, prev_rune) && (cur == .VF || cur == .VI) { return .None }
	if prev == .AP && is_ak_base(cur, cur_rune) { return .None }

	// ---- LB29: IS × (AL|HL) ------------------------------------------
	if prev == .IS && (cur == .AL || cur == .HL) { return .None }

	// ---- LB30: (AL|HL|NU) × OP; CP × (AL|HL|NU) ----------------------
	// Spec-defined EAW exception: wide-form OPs (e.g. U+2329, CJK
	// brackets, fullwidth parens) keep the default break — they're
	// visually their own column rather than glued to the preceding
	// letter. `is_eaw_wide_op` is a 29-entry hard-coded table from
	// EastAsianWidth.txt.
	if (prev == .AL || prev == .HL || prev == .NU) && cur == .OP && !is_eaw_wide_op(cur_rune) {
		return .None
	}
	if prev == .CP && (cur == .AL || cur == .HL || cur == .NU) { return .None }

	// ---- LB30a: RI × RI but only for odd-count runs -------------------
	if prev == .RI && cur == .RI && ri_run % 2 == 1 { return .None }

	// ---- LB30b: EB × EM, ID × EM -------------------------------------
	if (prev == .EB || prev == .ID) && cur == .EM { return .None }

	// ---- LB31: default ÷ ALL -----------------------------------------
	return .Allow
}
