# FLOW.md — app-flow prototype (Wave 2, wayfinder ticket #5)

Companion to `mock/index.html`, a single-file clickable prototype of the boot → home → mode →
match → leave-confirm flow. The mock's JS `AppFlow` class is a line-for-line port of
`game/prototypes/app_flow/app_flow.gd` (Wave 1): same `Screen` enum, same method names, same
guard conditions, same signal-emission points. This document maps that graph, states the Back
table, states the reachability rules the mock is built to satisfy, and answers the ticket's
loading-view question. See `docs/prototypes/CONTRACTS-app-flow.md` and
`docs/adr/0001-separate-application-flow-from-game-sessions.md` for the pinned ground truth this
document cites.

## Screens

| Screen | Purpose | Mock representation |
|---|---|---|
| `BOOT` | Initial resting state before the app has anything to show | Closed notebook cover; tap opens it |
| `HOME` | Hub: START / PENS / SETTINGS | Open notebook page, ruled lines, red margin |
| `MODE` | Choose Pass & Play (`hot_seat`) or Solo (`solo`) | Notebook page, two mode cards |
| `PENS` | Cosmetic pen picker | Notebook page, pen-color swatch grid |
| `SETTINGS` | Sound / Haptics / Screen shake / read-only match length & pen | Notebook page, toggle rows, filled `BACK` button |
| `PLAYING` | Live match (placeholder — no gameplay rendered) | Desk-laminate screen, score bar, turn cue, `Leave match` button |
| `CONFIRM_LEAVE` | Leave-confirm modal | Paper modal card **overlaid on top of** the still-mounted `PLAYING` screen |

## Transition table

Pinned 1:1 from `app_flow.gd` (`game/prototypes/app_flow/app_flow.gd:43-141`):

| Method | Valid from | Goes to | Signals emitted | Guard if called elsewhere |
|---|---|---|---|---|
| `boot_complete()` | `BOOT` | `HOME` | — | no-op (idempotent) |
| `open_mode_select()` | `HOME` | `MODE` | — | no-op |
| `open_pens()` | `HOME` | `PENS` | — | no-op |
| `open_settings()` | `HOME` | `SETTINGS` | — | no-op, **including from `PLAYING`** (suspend semantics are host-owned, not app-flow navigation) |
| `start_match(mode)` | `MODE` | `PLAYING` | `gameplay_start_requested(mode)` | no-op |
| `end_match()` | `PLAYING` | `HOME` | `gameplay_stop_requested()` | no-op |
| `confirm_leave()` | `CONFIRM_LEAVE` | `HOME` | `gameplay_stop_requested()` | no-op |
| `cancel_leave()` | `CONFIRM_LEAVE` | `PLAYING` | — (pure resume, nothing was torn down) | no-op |
| `handle_back()` | any | see Back table below | see Back table | never a no-op except at `BOOT`/`HOME` (returns `false`, not consumed) |

`gameplay_start_requested` fires **only** inside `start_match()`. `gameplay_stop_requested` fires
**only** inside `end_match()` and `confirm_leave()` — never on the `PLAYING → CONFIRM_LEAVE` Back
edge and never on `cancel_leave()`, because the match is not torn down until the player actually
confirms leaving. The mock's `Leave match` button on the `PLAYING` screen calls `handle_back()`
rather than a separate "leave" method — there is no such method in the pinned API; leaving a live
match always routes through `CONFIRM_LEAVE`.

## Back table

| From screen | `handle_back()` result | Consumed? | Lands on |
|---|---|---|---|
| `BOOT` | `false` | No — host would quit/exit | (stays at `BOOT`) |
| `HOME` | `false` | No — host would quit/exit | (stays at `HOME`) |
| `MODE` | `true` | Yes | `HOME` |
| `PENS` | `true` | Yes | `HOME` |
| `SETTINGS` | `true` | Yes | `HOME` |
| `PLAYING` | `true` | Yes | `CONFIRM_LEAVE` — **never straight out of a live match** |
| `CONFIRM_LEAVE` | `true` | Yes | `PLAYING` — Back here is a cancel, identical to pressing "Keep playing" |

The mock exposes exactly one Back input path for hardware/gesture Back (the pill fixed to the
bottom of the phone frame, plus Escape as a desktop-reviewer stand-in) and, on screens that also
carry an in-page Back affordance in the source mockups (`MODE`, `PENS`, `SETTINGS`'s `BACK`
button), those wire to the identical `handle_back()` call — there is no second, divergent
navigation path.

## Reachability rules

- Every value in the pinned `Screen` enum is reachable from `BOOT` by at least one path, and the
  mock adds no edge and removes none relative to `app_flow.gd`.
- `CONFIRM_LEAVE` is reachable **only** from `PLAYING` (via hardware Back or the `Leave match`
  button, both calling `handle_back()`). There is no shortcut from any menu screen into
  `CONFIRM_LEAVE`, and no direct edge from `PLAYING` to `HOME` via Back — that edge does not exist
  in the pinned module, so the mock does not render one.
- `SETTINGS` is reachable only from `HOME`. Calling `open_settings()` while `PLAYING` is a no-op in
  both `app_flow.gd` and the mock (matching Wave-1's `_test_open_settings_guarded_from_playing`):
  pausing a live match for settings is host-owned suspend behavior, not application-flow
  navigation, so this prototype does not offer a settings entry point from the match screen at
  all.
- The `CONFIRM_LEAVE` overlay renders on top of the `PLAYING` screen's own DOM node rather than
  replacing it (`render()` in `mock/index.html` keeps `PLAYING` mounted whenever `screen` is either
  `PLAYING` or `CONFIRM_LEAVE`), so the match is visibly still there underneath the dialog — this
  is the concrete, visual form of "nothing is torn down until `confirm_leave()` fires."
- Double-Back from `PLAYING` toggles `PLAYING ⇄ CONFIRM_LEAVE` indefinitely without ever escaping
  to `HOME` on its own, matching Wave-1's `_test_double_back_toggle_between_playing_and_confirm_leave`.

## The loading-view finding

**Verdict: a manufactured loading delay is not justified anywhere in this flow.** `boot_complete()`
in `app_flow.gd` is synchronous — no timer, no frame counter, no simulated wait
(`game/prototypes/app_flow/app_flow.gd:60-63`, and restated at length in Wave-1's own doc comment
at the top of the file). The state machine transitions the instant the host calls it; any
perceived "boot screen" duration is entirely a property of what the host does *before* calling
`boot_complete()`, not of this module.

The mock honors that finding by construction rather than by fiat: `BOOT` is a closed notebook
cover, and the only way out of it is a tap — there is no spinner, no progress bar, no percentage,
and no `setTimeout`. `boot_complete()` fires directly inside the tap's click handler. This is
deliberately *not* the same thing as a fake-delay loading screen that a real build might be
tempted to add for "feel": a tap-gated screen is input-driven (zero elapsed time is guaranteed
once the input arrives), while a manufactured delay is time-driven regardless of whether any real
work is happening.

The generalizable rule this leaves for later waves: if a real Android build ever wants `BOOT` to
be visible for longer than a single frame, that time has to be backed by genuine asynchronous work
happening *upstream* of the `boot_complete()` call — asset streaming, save-file reads, or similar —
and `boot_complete()` should be invoked the moment that work resolves. Nothing in application flow
should ever hold `BOOT` open by waiting on a clock; app-flow's only pinned contract is that the
transition is synchronous with the call, not that the call itself must arrive quickly.

## What Wave 2 deliberately does not do

- No production files were touched; `mock/index.html` and this document are new files under
  `docs/prototypes/app-flow/` only.
- The `PLAYING` screen is a placeholder — no gameplay is simulated or rendered, consistent with
  ADR-0001 (`docs/adr/0001-separate-application-flow-from-game-sessions.md`): application flow
  only ever requests that a Game Session be created/torn down, it never owns match rules or
  presentation itself.
- Settings toggles and the pen picker are local, decorative UI state in the mock. `app_flow.gd` has
  no opinion on them; only screen *navigation* is wired to the ported state machine.
