/*
Package bidi implements the UAX #9 bidirectional algorithm — paragraph
text in logical order in, embedding levels and visual reorder map out.

v0.1: stub. Returns LTR levels for every codepoint. The facade calls
through to here so the API shape doesn't change when v0.5 lands the
real algorithm.

v0.5: full UAX #9 with bracket pairs (BD16).

See PROPOSAL.md §4 (v0.5) and reference UAX #9.
*/
package bidi
