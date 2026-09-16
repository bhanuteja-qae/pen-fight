# Session lifecycle and mode-aware handoff — frozen decision for issue #11

**Status:** Frozen decision. This document defines the target session lifecycle and must be honored by the implementation; it does not claim the wiring has been implemented.

**Decision base:** repository commit `b4c496e`, issue #11 ("Choose session lifecycle and mode-aware handoff behavior") and its two grilling rounds with Bhanu (2026-09-16 — Q1–Q5 settled in round 1, Q6–Q10 in round 2; every recommendation accepted as put), `docs/adr/0001-separate-application-flow-from-game-sessions.md`, the app-flow prototype (`docs/prototypes/app-flow/`), the match contract (`docs/architecture/MATCH-CONTRACT.md`), and the FTUE beat module (`game/prototypes/ftue/ftue_flow.gd`) at its turn/rematch boundary.

## Purpose and boundaries

One session lifecycle serves both Game Modes. A **Game Session** becomes a real object that owns a Match: constructed on `start_match`, torn down on `end_match`/`confirm_leave`. `Main` becomes the app shell (app entry + screens), no longer the match owner. Solo and Hot Seat differ only in slot controllers and gate policy; suspend, leave, teardown, forfeit, and result recording are mode-independent.

This decision deliberately does **not** cover:

- Match rules, pen behavior, or the shot pipeline — frozen in `docs/architecture/MATCH-CONTRACT.md`.
- Persistence schema or save data — issue #7.
- Rival selection, personas, or progression — issue #10.
- Entry/exit copy and the FTUE-to-session seam — these settle with the FTUE integration work.
- Menu/mock content beyond the behaviors pinned here.

## The lifecycle (Q1, Q5)

- **The Game Session is a real object.** Created on `start_match`, torn down on `end_match`/`confirm_leave`. `Main` becomes the shell (app entry + screens), no longer the match owner. Rationale: every hazard named in the ticket — duplicate signal connections, stale bot timers, wrong-owner shots after a rematch — is a teardown problem, and one `_teardown()` on a session object is the only shape that makes them testable.
- **The session owns its teardown.** It disconnects exactly what it connected, cancels its own timers, and drops the snapshot.
- **Re-entry constructs fresh; it never reuses state.** A rematch begins a fresh Match within the same Game Session visit (fresh `MatchConfig` snapshot, fresh round state, no reused handlers or timers); any new match from HOME begins a fresh Game Session. Acceptance gate: a test that plays two matches back-to-back and asserts each transition fires exactly once.

## One suspend rule (Q4, Q9)

- **Every match clock freezes whenever `PLAYING` is not active** — sheet up, gate up, or app not foregrounded — and resumes with no elapsed penalty. In scope: idle forfeit, the in-flight physics-resolution backstop, bot think delay, hit-stop.
- **Suspending mid-flight is legal.** The board is preserved; the flick continues on resume.
- **Leaving is not suspending.** Leaving abandons the match; an unfinished flight is discarded rather than resolved.
- **Forfeit:** 15 s, in both modes, charged to the acting participant, only for a stalled AIM. The in-flight backstop is a separate valve (it resolves/expires a launched flick) and is suspended when not in play.

## Mode policy (Q6, Q7, Q8)

- **One lifecycle, two policies.** Solo and Hot Seat differ only in slot controllers and gate policy; suspend/leave/teardown/forfeit/result stay mode-independent.
- **Gate policy.** A gate appears when a *different human receives the phone*; round-over and match-over always prompt; bot turns never gate; the opening turn stays un-gated. The gate is a handoff acknowledgment, not a tap-to-continue on every turn.
- **Bot ownership.** The bot acts only when the session says it is the bot's slot and `PLAYING` is active; its think timer is session-scoped and cancelled on suspend and teardown; a human gate never blocks the bot; the bot never gates. Enforced at the one `_submit_shot` boundary that already rejects wrong-owner shots.

## Back and settings (Q2, Q3)

- **Hardware Back** adopts the app-flow prototype exactly: `quit_on_go_back = false`; `NOTIFICATION_WM_GO_BACK_REQUEST` routes into `AppFlow.handle_back()`; quitting the app is possible only outside a live match (`BOOT`/`HOME` do not consume Back — the host quits); `PLAYING` never exits directly — it routes to `CONFIRM_LEAVE` first. No silent forfeit, no app exit mid-match.
- **Settings is never reachable during a live match.** Settings lives in `HOME`; entry from `PLAYING` is a guarded no-op. No mid-match audio exception. The win target joins the frozen `MatchConfig` snapshot so no store read can retarget a live match.

## Result boundary (Q10)

- The session ends by producing an **immutable result** — winner, score, mode/ruleset, rival. The app/circuit layer is the only writer of anything durable.
- **Leaving records nothing** — no win, no loss, no mastery. An abandoned Solo match does not count as a loss against the rival.

## Hazards this decision must prevent (from the ticket)

| Hazard | Prevented by |
|---|---|
| Hidden-menu forfeits | Settings unreachable in `PLAYING`; every clock freezes when `PLAYING` is not active |
| Stale bot timers | Think timer is session-scoped and cancelled on suspend/teardown |
| Duplicate signal connections | Session owns teardown; re-entry constructs fresh (back-to-back test) |
| Wrong-owner shots | Bot ownership enforced at the one `_submit_shot` boundary |
| Bot deadlock on human handoff gates | A human gate never blocks the bot |
| Settings mutating an active match | Win target joins the frozen `MatchConfig` snapshot |

## Implementation notes

- `game/docs/turn_gate.md` still lists deleted `FORFEIT`/`GAME_OVER` phases — fold its cleanup into the commit that implements this decision.
- Today the win target is read live (`settings_store.rounds_to_win()`, `main.gd:578`) while `config.best_of()` stays frozen — this decision closes that divergence; the snapshot must carry the effective target.
- Re-entry acceptance gate: the two-match back-to-back test asserting each transition fires exactly once.
