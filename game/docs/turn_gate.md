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
