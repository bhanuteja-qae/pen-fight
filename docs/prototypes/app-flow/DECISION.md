# DECISION.md — app-flow prototype (Wave 3, wayfinder ticket #5)

Ticket resolution for *"Prototype the home, mode, pens, settings, and Back flow"* (issue #5),
written after independently re-verifying Waves 1–2's own reports rather than trusting them.

## Ticket question (verbatim)

> Prototype the home, mode, pens, settings, and Back flow

as pinned in `docs/prototypes/CONTRACTS-app-flow.md` ("Wayfinder ticket... (issue #5)"), with the
Wave-3 resolution criteria also pinned there: *"the smallest flow that satisfies START/PENS/SETTINGS
clarity, Pass & Play + Solo without restructuring, correct Back ownership, no live match behind a
menu."* I could not independently fetch the raw GitHub issue #5 body — `gh` is not installed in this
offline sandbox and the contract is explicitly offline-only — so this quotes the contract's pinned
wording rather than the live issue. Flagged under Open risks.

## Answer

The smallest flow that satisfies the ticket is the 7-screen graph already built and tested in
`game/prototypes/app_flow/app_flow.gd`:

**Screens:** `BOOT, HOME, MODE, PENS, SETTINGS, CONFIRM_LEAVE, PLAYING`.

**Back ownership:** a single pure-logic module (`AppFlow`) owns 100% of Back semantics via
`handle_back()` — there is no second navigation path. `BOOT`/`HOME` don't consume Back (host quits
the app). `MODE`/`PENS`/`SETTINGS` all return to `HOME` on Back — they are HOME's children, not a
tab bar between siblings, so nothing else is reachable from them. `PLAYING` never exits directly on
Back; it always routes to `CONFIRM_LEAVE` first. Back inside `CONFIRM_LEAVE` cancels back to
`PLAYING` (identical to pressing "Keep playing") — this is what makes double-Back from a live match
safe: it toggles `PLAYING ⇄ CONFIRM_LEAVE` forever rather than ever leaking out to `HOME`.

**Gameplay lifecycle:** a Game Session is requested exactly once, on the `MODE → PLAYING` edge
(`start_match(mode)`, emitting `gameplay_start_requested(mode)`), and torn down at exactly two
points: `end_match()` (the match concluded on its own) and `confirm_leave()` (the player confirmed
leaving) — both emit `gameplay_stop_requested()`. The Back-press that lands on `CONFIRM_LEAVE` and
`cancel_leave()` both emit nothing, because the match is not torn down until the player actually
confirms — that's the entire point of a leave-confirmation screen. `AppFlow` itself never
instantiates a scene or node anywhere (source-scan enforced); it only ever requests that the host
create/destroy a Game Session, matching ADR-0001. Settings is reachable only from `HOME` — entry
from `PLAYING` is a guarded no-op, because pausing a live match for settings is host-owned suspend
behavior, not application-flow navigation.

**"No live match behind a menu":** the only screen that can be showing while a match is live is
`CONFIRM_LEAVE`, and that is not a menu — it's a modal rendered *on top of* the still-mounted
`PLAYING` view (verified in the mock's `render()`), so the match is visibly present underneath the
dialog rather than hidden behind a disconnected screen. Every actual menu (`MODE`/`PENS`/`SETTINGS`)
is reachable only from `HOME`, which is only reachable after a Game Session has already been torn
down via `end_match()`/`confirm_leave()`. There is no path from any menu into a live match's screen
graph.

**Loading-view verdict: real work feedback, not a fake delay.** `boot_complete()`
(`game/prototypes/app_flow/app_flow.gd:60-63`) is synchronous — no timer, no frame counter, no
simulated wait — and the idempotency test (`_test_boot_complete_is_idempotent`) confirms a second
call is a true no-op, not a debounced timer. The mock demonstrates the same finding by construction:
`BOOT` is a tap-gated cover with no spinner or progress bar; `boot_complete()` fires directly inside
the tap handler. Evidence for the verdict: a state machine that never models a delay cannot be made
to fake one later without an explicit, separate change — the generalizable rule for later waves is
that any future BOOT-screen duration must be backed by genuine upstream async work (asset streaming,
save-file reads) completing, never by application flow waiting on a clock.

## Evidence

| Claim | Artifact | How verified | Result |
|---|---|---|---|
| Full transition table matches the pinned contract | `game/prototypes/app_flow/app_flow.gd:43-141` | Read source; re-ran `app_flow_test.gd` clean via the two contract-pinned Godot gate commands | `app_flow_test: ALL PASS` (raw output below) |
| `gameplay_start_requested` fires only inside `start_match()`, never from a menu state | `app_flow.gd:106-110`; `app_flow_test.gd:330-349` | Gate test + independent adversarial driver (`.scratch/adversarial_probe.gd`) calling `start_match()` from `BOOT`/`HOME`/`PENS`/`SETTINGS`/`CONFIRM_LEAVE` | 0 failures — signal never escapes |
| `handle_back()` never exits `PLAYING` directly | `app_flow.gd:136-139` | Adversarial probe: Back at every one of the 7 screens, plus 6 repeated Back presses from `PLAYING` | Toggles `PLAYING ⇄ CONFIRM_LEAVE` indefinitely (`[CONFIRM_LEAVE, PLAYING, CONFIRM_LEAVE, PLAYING, CONFIRM_LEAVE, PLAYING]`), never reaches `HOME` |
| Settings entry blocked from `PLAYING` (and `CONFIRM_LEAVE`) | `app_flow.gd:81-84`; `app_flow_test.gd:190-201` | Gate test + adversarial probe (also checked the untested `CONFIRM_LEAVE` case) | No-op confirmed in both states |
| `end_match()`/`confirm_leave()` are the only two stop-signal emitters | `app_flow.gd:90-121`; `app_flow_test.gd:355-369` | Gate test + adversarial probe: `end_match()` called while in `CONFIRM_LEAVE` | No-op, no stray signal |
| No scene/node instantiation anywhere in `app_flow.gd` (ADR-0001) | `app_flow.gd` (whole file); `app_flow_test.gd:377-383` source-scan | Re-ran gate test (source-scan passes); manual read for the forbidden-API list | Confirmed, zero matches |
| Mock JS is a faithful 1:1 port, adds/removes no edge | `mock/index.html:628-700` vs `app_flow.gd:43-148` | Side-by-side read: same enum, same guards, same emit points | Line-for-line match |
| `CONFIRM_LEAVE` overlays the still-mounted `PLAYING` DOM node | `mock/index.html:712-720` (`render()`) | Read render logic | Confirmed: `visible` resolves to `PLAYING` for both `PLAYING` and `CONFIRM_LEAVE` |
| Double-Back, repeat `start_match`/`end_match` misuse are safe no-ops | Every public method's guard clause in `app_flow.gd` | Adversarial probe, 8 scenario groups | 29/29 checks pass (one probe-authoring bug found and fixed mid-review, see below) |
| Ticket wording | `docs/prototypes/CONTRACTS-app-flow.md` | Could **not** verify against the live GitHub issue (`gh` unavailable, offline sandbox) | Used the contract's pinned quote instead |

Raw gate output (re-run this session, clean, from `~/pen-fight/game`):

```
$ flock /tmp/pf-godot.lock -c '... --headless --editor --quit --import .'
[...]
[ DONE ] loading_editor_layout

$ flock /tmp/pf-godot.lock -c '... --headless --path . --script res://prototypes/app_flow/app_flow_test.gd'
Godot Engine v4.7.2.stable.official.ed1daf0bf
app_flow_test: ALL PASS
```

Adversarial probe (throwaway, `game/prototypes/app_flow/.scratch/adversarial_probe.gd` — not a
deliverable, kept only as verification evidence, safe to delete):

```
=== adversarial probe: start ===
-- Back at every screen --                       (7/7 ok)
-- double-Back everywhere --                      (3/3 ok, incl. 6x Back from PLAYING)
-- Back from CONFIRM_LEAVE emits no stop signal --(2/2 ok)
-- settings entry from PLAYING --                 (3/3 ok, incl. CONFIRM_LEAVE)
-- mode switch while PLAYING --                   (2/2 ok)
-- end_match() from CONFIRM_LEAVE --               (2/2 ok)
-- starting a match twice in a row --              (4/4 ok)
-- negative: no start signal escapes any menu/CONFIRM_LEAVE state -- (6/6 ok)
=== adversarial probe: 29 checks, 0 failures ===
```

One honest note on process: the probe's first run reported 1 failure (`start_match()` from `MODE`
"leaking" a signal). That was a bug in the probe itself — `MODE → PLAYING` is the one *intended*
success path, not a state the negative check should have covered — not a defect in `app_flow.gd`.
Fixed the probe and re-ran clean; included here rather than silently editing it out, since the
ticket asked for every case tried, including ones that initially failed.

## Options considered and why rejected

- **Always-instantiated gameplay scene, hidden/paused behind menus.** Rejected per ADR-0001: the
  current gameplay scene owns idle-forfeit, physics-resolution, input-lock, and bot-automation
  timing; keeping it alive behind menus couples navigation to live match state and risks hidden
  progression, stale callbacks, or bot timers running unseen.
- **`PLAYING → HOME` directly on Back, no confirmation.** Rejected: a single accidental Back press
  (hardware button, mis-tap) would silently end an in-progress match with no recovery. The
  leave-confirm step is one extra transition and buys total safety against that.
- **Settings reachable from `PLAYING` (in-match settings).** Rejected per the ticket's own callout —
  pause/suspend semantics belong to the host layer, not application-flow navigation. Keeping
  `open_settings()` a hard no-op from `PLAYING` keeps the state machine pure and testable.
- **A timed/animated `BOOT` splash.** Rejected — see the loading-view verdict above: there is no
  real async work in this flow to justify one, and manufacturing a delay would contradict the
  ticket's own question rather than answer it.
- **Duplicate Back-handling paths (in-page Back buttons wired separately from hardware Back).**
  Rejected in the mock: every Back affordance (hardware pill, `Escape` key, in-page `Back` buttons
  on `MODE`/`PENS`/`SETTINGS`) calls the identical `handle_back()`, so there is exactly one Back
  stack and no way for the two paths to diverge.

## Open risks / what only a human playtest can judge

- Real device Back-gesture feel (Android predictive-back animation, gesture-nav vs. 3-button nav)
  cannot be judged from a pure-logic module or a static HTML mock.
- Whether players actually read `CONFIRM_LEAVE`'s "match still visible behind the dialog" affordance
  as reassuring (vs. confusing) needs eyes on a real build, not a logic test.
- In-match settings/pause UX is explicitly out of scope for application flow (host-owned) and remains
  entirely undesigned — this decision only confirms that app-flow correctly refuses to own it.
- Whether "Pass & Play" vs. "Solo" ever need more than an opaque `mode: String` (e.g. different
  loading requirements for a bot-driven start) is untested; both modes are only ever exercised as
  interchangeable strings here.
- I could not interactively click through `mock/index.html` in a real browser (headless sandbox, no
  browser tooling available) — it was verified by static reading of the JS against `app_flow.gd`,
  not by visual/interaction testing. A human should still click through it once.
- The verbatim GitHub issue #5 body was not independently fetched (no `gh`, offline sandbox); the
  ticket wording above is the contract's pinned quote, which the contract states was fixed before
  Wave 1 started.

## Artifacts

- `game/prototypes/app_flow/app_flow.gd` — Wave 1, the pinned state machine
- `game/prototypes/app_flow/app_flow_test.gd` — Wave 1, the pinned gate test
- `game/prototypes/app_flow/.scratch/adversarial_probe.gd` — Wave 3, throwaway independent verification (not a deliverable)
- `docs/prototypes/app-flow/mock/index.html` — Wave 2, click-through mock
- `docs/prototypes/app-flow/FLOW.md` — Wave 2, flow map + Back table + loading-view finding
- `docs/prototypes/CONTRACTS-app-flow.md` — pinned ticket contract
- `docs/adr/0001-separate-application-flow-from-game-sessions.md` — ADR-0001
- `docs/prototypes/app-flow/DECISION.md` — this document
- `docs/prototypes/app-flow/RESOLUTION-COMMENT.md` — the issue-comment draft
