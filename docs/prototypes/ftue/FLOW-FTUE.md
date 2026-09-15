# FLOW-FTUE.md — first-minute FTUE prototype (Wave 1, wayfinder ticket #12)

Companion to `mock/index.html` (single-file click-through) and to
`game/prototypes/ftue/ftue_flow.gd` + `ftue_flow_test.gd` (the pure-logic module and its headless
test). Everything in this document is either measured by a gate that ran, or is a decision this
document is asking Wave 2 / the orchestrator to confirm — the two are labelled differently.

Scope: **the first minute of a match**, not the app flow. The hop from `BOOT` to a live desk belongs
to `app-flow` (ticket #5, closed) and is *cited* here, never re-decided. This prototype owns only the
beats that play **on top of a live AIM turn**.

---

## 1. The first minute in one line

Two people, one phone, one committing flick each — and the game still refuses to help either of them
(`docs/design/design-pillars.md:18-19`). The FTUE adds a **teaching layer over a live AIM turn**: it
explains the slingshot gesture, cues the first flick, states the Pen Powers tradeoff in words, and
otherwise stays out of the way. It is a layer, not a gate: **no beat may ever be required before the
player can grab the pen.**

## 2. Beat sequence

`enum Beat { TEACH, FIRST_SHOT, RIVAL_CHOICE, TRADEOFF, PLAY }` — pinned order, asserted against
`Beat.keys()` in the test (`_test_beat_enum_matches_pinned_order`). `beat` is read-only for
consumers; only `start_first_minute()` and the beat's own exit method assign it.

| Beat | Entered when | On screen | How it leaves | Can it block a flick? |
|---|---|---|---|---|
| `TEACH` | Hot Seat + Classic starts; or the pre-flick card path falls through to it | Cue `GRAB THE PEN - PULL BACK - LET GO`; 3-step diagram (grab / pull back / let go); the desk's own hint strip stays under it | `on_drag_started()` → `PLAY`; `skip()` → **cancels the rest of the first minute**, straight to `PLAY`; 4 s idle → `FIRST_SHOT` | No. `on_drag_started()` clears it from any beat |
| `FIRST_SHOT` | 4 s of no input in `TEACH` | Cue `FIRST FLICK - PULL BACK, LET GO`; the same desk, same live turn | `on_first_shot_committed()` → `PLAY`; `on_drag_started()` / `skip()` → `PLAY` (minute cancelled). **Sticky**: idle never moves it | No. It is the beat that *waits* for the real flick |
| `RIVAL_CHOICE` | Solo only, on `start_first_minute("solo", …)` | Ordered list of three rivals; lock state **injected**, never hardcoded (ticket #10 undecided) | `skip()` / 4 s idle → next beat (`TRADEOFF` under `pen_powers`, else `TEACH`); `on_drag_started()` → `PLAY` | No |
| `TRADEOFF` | `start_first_minute(…, "pen_powers")` — never under `classic` | The pen's strength **and** its cost, in words, for both profiles, before the first flick (`docs/prototypes/pen-profiles/DECISION.md:31`) | `on_tradeoff_acknowledged()` / `skip()` → `TEACH`; `on_drag_started()` → `PLAY`. **Sticky**: idle never moves it, by design — a disclosure the player has not acknowledged must not scroll past on its own | No |
| `PLAY` | any drag, any commit, `skip()` out of `TEACH`/`FIRST_SHOT` | nothing — the host's own idle cue (`"YOUR FLICK"`, `aim_overlay.gd:217`) runs the desk | — | by definition not |

Two different kinds of exit, and the difference is the contract's: `skip()` on a **teach** beat is the
escape ("stop teaching me", cancel the minute); `skip()` on a **pre-flick card** is a dismiss
("seen it", advance one beat). A card that a tap could not dismiss would be exactly the gate the
contract forbids (`ftue_flow.gd:175-181`).

`tick(delta)` advances **at most one beat per call**, and only `TEACH` and `RIVAL_CHOICE` relax on
idle — so a stalled host frame can never fast-forward the whole first minute (measured:
`_test_tick_advance_without_input`). `_grabbed` stops the clock for good: once the player has taken
the pen, idle can never move a beat again in this turn (`ftue_flow.gd:205-206`). The module owns no
timer: the host feeds `tick(delta)` and owns every rendering decision.

## 3. Mode × Ruleset matrix

Game Mode and Ruleset are different axes (`CONTEXT.md`) and the FTUE keeps them separate — mode
changes *which card opens the minute*, ruleset changes *whether the tradeoff card exists at all*:

| Mode (`mode`) | Ruleset (`ruleset`) | Opening beat | Pre-flick beat order (idle relaxes `TEACH`/`RIVAL_CHOICE` only; `FIRST_SHOT` and `TRADEOFF` are sticky) |
|---|---|---|---|
| `hot_seat` | `classic` | `TEACH` | `TEACH → FIRST_SHOT → PLAY` |
| `hot_seat` | `pen_powers` | `TRADEOFF` | `TRADEOFF → TEACH → FIRST_SHOT → PLAY` |
| `solo` | `classic` | `RIVAL_CHOICE` | `RIVAL_CHOICE → TEACH → FIRST_SHOT → PLAY` |
| `solo` | `pen_powers` | `RIVAL_CHOICE` | `RIVAL_CHOICE → TRADEOFF → TEACH → FIRST_SHOT → PLAY` |

Unknown or near-miss tokens resolve to the **safe defaults** (`hot_seat`, `classic`) rather than
erroring — `"solo "` resolves, `"pen powers"` (with a space) does not. That fallback is what makes
the two "only when" invariants strict rather than aspirational, so the fallback itself is pinned by
tests (`_test_resolution_defaults_are_strict`). Rival choice is presented **only** in Solo; in Hot
Seat the two players are already at the table and there is nobody to choose.

## 4. Tap budget

Launch to a live AIM turn costs **≤ 3 taps**, and the FTUE's own required cost is **0**
(`TAPS_REQUIRED_BEFORE_FIRST_FLICK` in the module, asserted in the test).

| Host tap | Consumes | App-flow method | FTUE call |
|---|---|---|---|
| 1 | `BOOT` cover | `boot_complete()` | — |
| 2 | `HOME` hub | `open_mode_select()` | — |
| 3 | `MODE` → live desk | `start_match(mode)` | `start_first_minute(mode, ruleset)` |
| *(0 more)* | a beat may be **showing** | — | a drag is honoured immediately, from every beat |

The FTUE adds no tap: `on_drag_started()`, `skip()` and `on_tradeoff_acknowledged()` are all
*optional escapes*, and no path through any beat requires one to have fired. Measured both sides:
`_test_tap_budget_boot_to_live_aim` (GDScript) and the mock's own selftest agree that the host
ledger is 3 and the FTUE's required contribution is 0. The mock's debug panel prints the same
ledger (`host taps: 3 / 3 budget | FTUE taps required: 0`) so a reviewer can see it without reading
code.

Cue strings are capped at `MAX_CUE_CHARS = 48` characters, uppercase, ASCII-only, no leading or
trailing space (`_test_cue_text_fits_the_viewport`). That cap is the pure-logic *proxy* for the
prompt-fit rule from commit `4573676` (text fits a computed viewport width; never a hardcoded 44 px,
never an assumption of 1280 — `window/stretch/aspect = keep_height`, so a tall phone's logical width
is far under 1280). The real fit measurement is Wave 2's `VISUAL.md` rule (`prompt width ≤ viewport −
2×32`); the logic layer's job is only to never hand the layout a string that cannot fit.

## 5. What is on screen at t=0, t=5 s, t=15 s

Clock assumption: the host has consumed all three taps and called `start_first_minute()` at t=0, and
the player does **nothing at all** (no grab, no tap). `IDLE_ADVANCE_SECONDS = 4.0`.

**t=0 — the desk is live, the teach is up.** Screen `PLAYING`: score bar, turn cue, both pens on the
desk, the persistent hint strip `GRAB ANYWHERE ON THE PEN -> PULL BACK -> LET GO | drag past 30 px
or the flick cancels · power caps at 160 px`, and the `TEACH` card over it with the 3-step diagram.
The turn is already an AIM turn: pointer-down on the pen is accepted in this exact frame. Node: the
numbers in that hint strip are not invented; they are `min_drag_pixels = 30.0` (`aim_input.gd:46`),
`max_drag_pixels = 160.0` (`aim_input.gd:48`) and the capsule grab zone with its finger margin
(`aim_input.gd:53`, `:163-174`).

The teach card is **pointer-transparent** (`.beat-layer .card-shell{ pointer-events: none }`, only
its own buttons go back to `auto`) and this is not a style choice: measured, at the pinned 1280x720
window the card spans the entire arena (`#beat-shell=348x234@459,188`, arena inside a `368x503`
device), so a card that swallowed pointer events would silently gate the very drag it is teaching —
the one thing this contract forbids. Grabbing through the card is also *visible*: the card's own
exit condition fires on that same pointer-down, so the teach card is gone by the time the pen moves.
Moved for the same reason: the pen's rest position is `top: 46%` of the arena so that at the true
phone aspect it sits *above* the card and a reviewer can see what they are grabbing.

**t=5 s — teach relaxed, first-shot cue up.** 4 s of no input moved the beat to `FIRST_SHOT`, so the
card now reads `FIRST FLICK - PULL BACK, LET GO`; the desk is unchanged and the hint strip is still
there (it is *not* a beat — the beat relaxes, the reference hint does not). This is the state a
player who read the teach and hesitated lands in: nothing has been taken away from them.

**t=15 s — the turn itself is over, and that is the game's clock, not the FTUE's.** The no-input
idle forfeit is 15.0 s (`FORFEIT_TIMEOUT: float = 15.0`, `main.gd:87`; rule restated at
`turn_state.gd:52`). With no input the turn forfeits at t=15 s and the host shows its own gate.
Three honesty notes, since this is exactly where a bad FTUE design hides:

- The FTUE **cannot** interfere with that clock: `tick(delta)` only ever moves a card, never a turn,
  and it holds no timer of its own. If the host stops feeding `tick()`, the FTUE simply stops
  advancing.
- The FTUE has **no forfeit API on purpose** — the beat stays `FIRST_SHOT` into the next turn. That
  is the correct outcome: the player never flicked, so they are still being taught the first flick.
  Adding a `on_turn_forfeited()` method now would be inventing a hook nothing has needed yet.
- The 4 s dwell is deliberately shorter than the 15 s forfeit: the card must relax well before the
  clock can end the turn, so the player is never looking at a teach card at the moment the host takes
  their turn away.

If the player *does* flick at any point: the drag kills the beat in the same frame
(`on_drag_started()`), the release commits (`on_first_shot_committed()`), and `PLAY` is the only beat
that can remain — measured for every beat, every mode and every ruleset by
`_test_only_play_after_first_shot_committed` and by the mock's 2500-sequence selftest walk.

## 6. The loading-feedback call: real work feedback only, no fake delay

The `app-flow` prototype already answered this question for the flow, and the FTUE inherits the
answer instead of re-litigating it:

> **Verdict: a manufactured loading delay is not justified anywhere in this flow.**
> — `docs/prototypes/app-flow/FLOW.md:87`

The FTUE's version of that call, by construction rather than by fiat:

1. **No spinner, no progress bar, no percentage, no fake delay.** The mock's only `setTimeout` calls
   are cosmetic: the toast auto-hide and the post-flick pen-reset animation
   (`mock/index.html:1129`, `:1187`). Nothing in the flow or beat path is gated on a clock, and the
   module has no timer at all. Its `#viewport-probe`, `#layout-probe` and selftest all run
   synchronously in the load handler; the only `requestAnimationFrame` in the file drives the
   **opt-in** `?live=1` host clock.
2. **The FTUE never holds a screen open.** `start_first_minute()` is synchronous, like
   `boot_complete()` (`game/prototypes/app_flow/app_flow.gd:60-63`): the beat is set in the same
   frame the host calls it, and the desk is already draggable in that frame.
3. **A loading view, if a build ever needs one, backs real work.** Per the app-flow finding, any
   perceived duration has to be backed by genuine asynchronous work upstream of the transition
   (asset streaming, save read) — and the FTUE's first beat must *not* be repurposed as that
   loading view: a beat is a teaching layer over a live turn, and using it to hide a wait would
   make it a gate, which is the one thing the contract forbids.
4. The mock's own clock is **paused by default** so a screenshot is deterministic; `?live=1` (or the
   `L` key) lets the host feed `tick(delta)` for real. That is the honest way to demo a time-based
   beat: the reviewer chooses to start the clock.

## 7. Invariants and where each one is enforced

| Contract invariant | Enforced by (module test) | Also enforced by |
|---|---|---|
| `"hot_seat"` never enters `RIVAL_CHOICE` | `_test_exhaustive_interaction_walk` (4 combos × 5⁴ sequences) + `_test_mode_ruleset_matrix_chains` | mock selftest, same walk |
| A teach beat can never block a legal flick | `_test_teach_dies_on_drag_from_every_beat` | mock: pointer-down handler never reads `beat`; beat card is pointer-transparent (measured) |
| … and never re-arms in the same player turn | `_test_teach_never_rearms_after_drag` (300 s of ticks after the grab) | mock selftest |
| Only `PLAY` may remain after `on_first_shot_committed()` | `_test_only_play_after_first_shot_committed` (a second commit is a strict no-op in the same test) | mock selftest |
| `TRADEOFF` only when `ruleset == "pen_powers"` | `_test_resolution_defaults_are_strict`, `_test_exhaustive_interaction_walk` | mock selftest |
| ≤ 3 taps `BOOT` → live AIM; no beat required first | `_test_tap_budget_boot_to_live_aim` | mock: host-tap ledger shown in the debug panel |
| No beat may be *required* to complete before a drag | `_test_teach_dies_on_drag_from_every_beat` (drag from **every** beat, including `PLAY`) | mock selftest |
| Beat changes only ever go where the matrix allows | `_test_beat_changed_edges_are_legal` | — |
| Pure logic: no nodes, no scenes, no own timers | `_test_no_nodes_or_timers_in_source` (source scan + first `extends` line must be `extends MainLoop`) | gate 2 runs the file itself |
| Cue text can always fit a computed viewport width | `_test_cue_text_fits` (≤ `MAX_CUE_CHARS`, uppercase, ASCII, trimmed) | brute force: no string the layout can receive is over the cap |

## 8. What we deliberately did not build

- **No production behavior, no production files.** `game/scripts/*`, `game/scenes/*`,
  `game/tests/*`, `project.godot` and the sibling prototypes are untouched — Wave 1 writes four new
  files and nothing else.
- **No Rival Circuit progression rules.** The rival list is rendered with lock state from an
  *injected* callback (`window.__ftueHost.rivalCircuit`); the file's default is a labelled stand-in,
  not a rule. Ticket #10 owns this.
- **No numeric stat page, no hidden stats.** The `PEN PROFILES` / tradeoff surface states each pen's
  strength *and* its cost in words, per `CONTEXT.md`.
- **No aim assist, no trajectory line, no ghost trail, no power reticle.** Pillar 2 rules out exactly
  this class of affordance (`docs/design/design-pillars.md:54-57`); the teach explains the gesture,
  it never previews the shot.
- **No grip-centred teach.** The teach says *grab anywhere on the pen* on purpose: the grab offset is
  preserved through the flick as torque (`aim_input.gd:186-192`), so "hold the middle" would be
  teaching a lie that flattens the corner flick.
- **No new art, fonts, images, network, autoloads or exports.** HTML/CSS/markdown/GDScript only; the
  mock has zero external dependencies (no `src=`, no `@font-face`, no CDN).
- **No `PLAYING` gameplay.** The desk in the mock reproduces the *input* (grab / pull back / release,
  30 px cancel, 160 px cap), not the physics: it is an interaction prototype, not a match.
- **No settings-persistence work**, no analytics, no mobile build/export path.
- **No second player's FTUE.** Both seats get the same first minute; alternating turns are the host's
  business (`turn_state.gd`).

## 9. Gates (raw output pasted in the handoff)

```bash
cd ~/pen-fight/game
# gate 1 — headless test (must print "ftue_flow_test: ALL PASS", exit 0)
flock /tmp/pf-godot.lock -c 'DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 300 ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://prototypes/ftue/ftue_flow_test.gd'
# gate 2 — the module loads as a script and exits 0 with no script errors
flock /tmp/pf-godot.lock -c 'DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 120 ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://prototypes/ftue/ftue_flow.gd'
# gate 3 — screenshots at both pinned sizes + overflow assertion
chrome --headless --no-sandbox --disable-gpu --window-size=1280,720 \
  --virtual-time-budget=2500 --screenshot=/tmp/ftue-shots/1280x720-PLAYING_TEACH.png \
  "file:///home/ubuntu/pen-fight/docs/prototypes/ftue/mock/index.html#PLAYING@TEACH"
#   ...repeat with --window-size=720,1280; then read #viewport-probe / #layout-probe via --dump-dom
```

**Deviation, recorded:** `CONTRACTS-ftue.md:105` names the chromium binary as
`…/chromium-1234/chrome-linux/chrome`. That path does not exist on this box; the real binary is
`…/chromium-1234/chrome-linux64/chrome` (verified by `find`). The gate below uses the real path.

### Gate results (measured on this box, not predicted)

| Gate | Result |
|---|---|
| 1 — headless test | `ftue_flow_test: exhaustive walk cross-checked 2500 interaction sequences over 4 mode x ruleset combos` / `ftue_flow_test: ALL PASS`, exit 0 |
| 2 — module load smoke | `ftue_flow: load smoke OK (beat=PLAY, cue=)`, exit 0 |
| 3a — screenshots | 14 shots, exit 0, `/tmp/ftue-shots/` (10 × 1280x720, 4 × 720x1280) |
| 3b — hash reachability | **35 / 35** routes (7 screens × 5 beats) landed on the requested `screen` **and** `beat` |
| 3c — overflow, 1280x720 | `scrollWidth=1265`, `innerWidth=1280`, **`horizontalOverflowPx=0`**; no `CLIPPED` / `OUTSIDE-DEVICE` element |
| 3c — overflow, 720x1280 | `scrollWidth=720`, `innerWidth=720`, **`horizontalOverflowPx=0`**; no `CLIPPED` / `OUTSIDE-DEVICE` element |
| 3c — mock selftest | `FTUE SELFTEST: PASS (9129 checks, 2500 interaction sequences)` — the same 2500 as gate 1 |

The two layout probes, verbatim:

```
[1280x720] device 368x503 | #beat-shell=348x234@459,188 | #hint-strip=350x57@458,431 | .my-pen=96x13@585,256
[720x1280] device 368x768 | #beat-shell=348x234@186,540 | #hint-strip=350x57@185,784 | .my-pen=96x13@312,466
```

At the true phone aspect the pen (y 466) sits above the card (y 540); at the squashed 1280x720
window the card covers the whole arena and the pen is behind it — which is precisely the case the
pointer-transparency rule in §5 exists for, and why the grab still lands.

## 10. Open questions handed to Wave 2 / the orchestrator

1. **Cue voice.** The cues are currently terse uppercase imperatives (`FIRST FLICK - PULL BACK, LET
   GO`). Wave 2 owns the visual system; if it picks a warmer voice, the 48-char cap and the
   uppercase/ASCII test invariant have to be re-decided *with* the cap, not after it.
2. **Where the beat renders.** The mock renders the beat card over whatever Screen is current (with
   a desk-specific anchor when the desk is up) so every screenshot route is meaningful. A real build
   will want the desk-only anchor as the *only* path, since a beat always implies a live turn.
3. **First-shot cue duration.** `FIRST_SHOT` is sticky until the flick commits. If the forfeit gate
   (15 s) is ever felt to pre-empt it, the fix is a host-side hand-off, not a longer beat.
4. **The 4 s dwell** (`IDLE_ADVANCE_SECONDS`) is a judgement call, not a measurement. It is the one
   number here that a playtest would move first.
5. **Rival-lock copy** is a stand-in; ticket #10 owns the real unlock semantics and the words.

## 11. Files (Wave 1 owns exactly these)

| File | Role |
|---|---|
| `game/prototypes/ftue/ftue_flow.gd` | pure-logic beat sequence (`extends MainLoop` — see its header for why that base class is the only one that satisfies the pinned gate *and* stays node-free) |
| `game/prototypes/ftue/ftue_flow_test.gd` | headless `SceneTree` test; prints `ftue_flow_test: ALL PASS` |
| `docs/prototypes/ftue/mock/index.html` | single-file click-through; hash-routable `#<SCREEN>` / `#<SCREEN>@<beat>` |
| `docs/prototypes/ftue/FLOW-FTUE.md` | this document |

**Not mine, in the same directory:** `docs/prototypes/ftue/VISUAL.md` and
`docs/prototypes/ftue/visual/index.html` are **Wave 2** deliverables ("Ticket #12, wayfinder Wave 2.
Owner: the menu-visual agent") written by a concurrent agent. They are outside this contract's four
files; nothing in Wave 1 reads, edits or gates them, and no gate above touches them.
