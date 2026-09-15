# Turn gate — Phase 1b state flow

State machine phases: `AIM`, `IN_FLIGHT`, `SETTLED`, `FORFEIT`, `GAME_OVER`, `ROUND_OVER`.

```
                    begin_turn() / continue_to_next_round()
                  +----------------------------------------------+
                  v                                              |
  +--------+   on_flick    +------------+   both settled   +------------+
  |   AIM  | ------------->| IN_FLIGHT  |----------------->|  SETTLED   |-> begin_turn() (next player)
  +--------+               +------------+                  +------------+
     ^  ^                     |        |
     |  |   forfeit_tick()    |        |  on_out_of_bounds(pen)
     |  |  (timeout reached)  v        v
     |  +-----------+  +------------------+   winner/loser decided
     |              |  |   ROUND_OVER      |   GEOMETRICALLY here (docs 3.2),
     |              +->|  (parked — gate)  |   before any ceremony
     |                 +------------------+
     |                          |
     |  continue_to_next_round()|  (tap / F key in Main; feel.reset() skips ceremony)
     +--------------------------+

SETTLED (both pens stayed on table) auto-advances to the next player with no
winner — no gate, no ceremony.

ROUND_OVER is the ONLY place a decided round (OOB winner or forfeit) rests:
- nothing auto-advances; Main locks aim input (AimInput.input_locked = true)
  and shows the centered "TAP TO CONTINUE" prompt.
- `continue_to_next_round()` -> begin_turn(): the next round starts with the
  player who did NOT flick last (strict alternation in `begin_turn()`; that is
  the round winner when the flicker lost, and the loser on a knockout).
- state() exposes winner / loser / round_winner / round_over.
- on_flick / forfeit_tick are no-ops while parked.

Owned by Agent A per phase1b-contract.md.

## Prompt layout (presentation rule)

`show_prompt()` renders the prompt at `FONT_SIZE` (44) and steps the size down
in 2 px increments (floor `FONT_SIZE_MIN` 18) until the widest explicit line
fits the viewport inset by `SIDE_MARGIN` (32 px each side). Autowrap is
`AUTOWRAP_WORD_SMART` as the safety net, and multi-part prompts separate their
parts with an explicit `\n` (the match-over gate puts the series on its own
line).

Why: the match-over prompt ("… wins the match N-M — tap for a rematch (series
…)") measured **1276 px wide on a 1280 px viewport** — glyphs flush to both
edges with both ends clipped. Round prompts measured 931–943 px, so they keep
44 px untouched; only an overlong prompt shrinks. This also protects narrower
logical viewports: `window/stretch/aspect=keep_height` means a tall phone's
logical width is well below 1280.

Regression evidence: `game/tests/state_shots.gd` prints a per-shot
`FIT OK` / `FIT FAIL` line comparing the widest rendered line against the inset
width (`root.get_visible_rect().size.x - 2 × 32`); the pre-fix run printed a
1276 px bbox on `match_over.png`, the post-fix run prints `FIT OK`.
