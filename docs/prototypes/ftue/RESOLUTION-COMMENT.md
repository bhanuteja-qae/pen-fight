## Resolution: first-minute FTUE + menu visual direction

**Answer:** the first minute is a **non-gating teaching layer over an already-live AIM turn**, and the
menu direction is a **two-family paper/desk system with a measured type scale**. 5 beats —
`TEACH, FIRST_SHOT, RIVAL_CHOICE, TRADEOFF, PLAY` — in one node-free pure-logic module
(`ftue_flow.gd`). No beat can gate a flick: `on_drag_started()` clears the beat from any beat in the
same frame and it never re-arms within the player's turn, and the FTUE's own required-tap cost is 0
(launch to a live AIM turn stays ≤ 3 host taps). Mode and ruleset stay separate axes: Solo opens on
`RIVAL_CHOICE`, Hot Seat never does; `TRADEOFF` exists only under `pen_powers`. The visual sheet is the
gate for the direction — `font-size` floor 11 px, prompt width ≤ viewport − 64, no `overflow:hidden` to
pass a fit check, desk text on a darkened backer (cream on the wood gradient is only 2.45–3.32:1), and
the Pen Powers tradeoff stated in words with no hidden stats.

**Fixed in this wave — the one divergence between the two artifacts:** the rival placeholders disagreed
(`mock/index.html` used `CHALK` / `INK RED` / `VELLUM`, `visual/index.html` used `Nib` / `Blotter` /
`Understudy`). Adopted the mock's set, consistent with the pen models being named for desk materials and
colours (amber, cobalt, graphite, ivory), and renamed three text nodes in the visual sheet —
`3 insertions(+), 3 deletions(-)`, nothing else. Measured, the adopted set is also the narrower one
(widest rival name **100.02 → 74.02 px** at bold 18 px). Placeholder labelling is intact in both files
(`data-placeholder="rival-name"` on the sheet; the mock keeps its injected-callback stub and its
`provenance` string). **These are still stand-ins — ticket #10 owns the real Rival Circuit names and
unlock rules**, and neither artifact encodes a progression rule.

**Loading-view verdict (confirmed):** no manufactured delay. `boot_complete()`-style hand-offs are
synchronous, the mock's only `setTimeout`s are cosmetic, and the beat path is gated on no clock. Any
future loading duration must be backed by real upstream async work — and the first-minute beat must
never be repurposed as a loading view, because that would make a beat a gate.

**Verification:** re-ran every gate on the on-disk files after the rename. `ftue_flow_test` →
`ALL PASS` over 2500 interaction sequences across 4 mode × ruleset combos, exit 0; the module's load
smoke exits 0. The mock's in-page selftest → `PASS (9129 checks, 2500 interaction sequences)`,
`horizontalOverflowPx=0` at 1280x720 and 720x1280, and its hash routes land on the requested **screen
and beat** (`#PLAYING@TEACH`, `#MODE@RIVAL_CHOICE`). The visual sheet's own checker → `ALL CHECKS PASS`
at 1280x720 (widest nowrap prompt 295.4 px vs a 1216 px budget), 720x1280 (vs 656 px) and a true
360x640 (**vs 296 px — 0.6 px of margin**), min rendered font 11 px, zero overflow everywhere. Neither
HTML file references anything outside itself. The rename left the binding fit number untouched: the
widest nowrap prompt is still exactly 295.4 px, and the `t1` census and the rival-list checks are
unchanged.

**Open risks (need a human, a playtest, or a later ticket):**
- **0.6 px of margin at 360 px.** One character added to the 33-char first-shot cue, or a different UI
  font on a target device, breaks the fit gate at that size. And below the 300 px reference surface the
  one-line rule is *not enforced* — 10 of 13 one-line prompts already wrap at 360 px.
- **The mock's JS and the GDScript module are two hand-written ports of one state machine and nothing
  gates them against each other.** They agree today by authorial care, not by a parity test; nothing
  fails when one side gains a transition the other lacks. This is the same defect class as the
  rival-name divergence just fixed.
- **`IDLE_ADVANCE_SECONDS = 4.0` is a judgement call and unmeasured** — the first number a playtest
  should move.
- **The 15 s no-input forfeit already in the game (`main.gd:87`) is not observed by the beat module**
  (no forfeit API, on purpose). How a host forfeit gate reads with a teach card underneath it has never
  been composed.
- **The beat layer has never been composed with a live match.** The mock reproduces the input, not the
  physics; nothing here runs in the real game loop, and no production file is touched.
- **No human has judged the look.** Both artifacts were verified by geometry, computed style and grep in
  a headless browser; the orchestrator's vision pass over three rendered screens confirmed the card text
  is legible at phone size, but readability at a glance, feel, and whether the paper→desk transition
  reads as a state change are unjudged.
- No touch/Android input path and no device Back-gesture feel; the unpaused-clock path (`?live=1`) is
  opt-in, so no time-based beat has ever been watched running. The verbatim issue #12 body was not
  fetched (`gh` unavailable, offline sandbox) — the wording above is the contract's pinned quote.

`VISUAL.md:637` also still named the old placeholder set (`Nib` / `Blotter` / `Understudy`); a frozen
file, corrected by the orchestrator in the same commit as this comment — it was a documentation
inconsistency, not a gate failure.

Full evidence, the rejected alternatives and the named non-answers:
[`docs/prototypes/ftue/DECISION.md`](./DECISION.md). Artifacts:
`game/prototypes/ftue/ftue_flow.gd`, `ftue_flow_test.gd`, `docs/prototypes/ftue/mock/index.html`,
`docs/prototypes/ftue/FLOW-FTUE.md`, `docs/prototypes/ftue/VISUAL.md`,
`docs/prototypes/ftue/visual/index.html`.
