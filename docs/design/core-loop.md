# Pen-Fight — Core Loop Extraction

`game-design:core-loop-extractor` applied to the shipped Phase-1 vertical slice.
Every claim below cites a file I read in this repo. Where a claim is an
inference about what a player would *feel*, it is marked **inference** — no human
has playtested this build yet (`docs/handoff-2026-09-14.md` §5).

---

## Extraction Target

- **What is analysed:** the whole game as currently shipped — the Phase-1
  vertical slice on `main`: `game/scenes/main.tscn`, `game/scripts/*.gd`,
  `game/tests/`.
- **Loop scope:** the **top-level game loop** (the minute-to-minute cycle and the
  round/match cycle that wraps it). Not a sub-loop; the settings screen and the
  pen-skin picker are treated as meta layers, not the engine.
- **Claimed loop in the docs:** there isn't one stated. What the docs supply is
  (a) a turn **state machine** — `AIM → IN_FLIGHT → SETTLED → ROUND_OVER |
  hand-over` (`docs/ART_AND_FEEL_SPEC.md` §7; implemented in
  `game/scripts/turn_state.gd`) — and (b) a pass/fail **gate**, not a loop
  definition: *"you and one other person play 20 rounds and want a 21st"*
  (`docs/RESEARCH.md` §5, `docs/ART_AND_FEEL_SPEC.md` §10 step 11). The repo has
  a machine, not an articulation of why anyone re-enters it. That gap is the
  first thing this extraction fixes.

---

## Extracted Core Loop

**One breath:** grab your own pen, drag back, release, watch two pens collide
until they stop, tap through the verdict, do it again.

**Form:** `Aim → Flick → Resolve → Judge → Tap → (hand over) → Aim`

Amplified by the adversarial variant of the same cycle:

`Aim → Flick → Risk your own pen → Resolve → Knock theirs off (or lose yours) →
Tap → Score → Aim again`

The loop has exactly one beat of player agency — a **≤160 px drag**
(`game/scripts/aim_input.gd` `max_drag_pixels`) — wrapped in two beats of
mandatory non-agency (the gate tap) and one variable-length beat of watching
(`IN_FLIGHT`, up to the 8 s backstop at `game/scripts/turn_state.gd`
`RESOLVE_TIMEOUT`). That ratio is the whole loop's character: it is a
**gambit loop** — commit a shot, surrender control, absorb the result.

---

## Loop Step Breakdown

| # | Stage | What happens | Where |
|---|---|---|---|
| 1 | **Handoff gate** | Full-screen tap-to-continue overlay; all flick routing is dead while it is up | `main.gd` `_show_gate` / `_on_gate_tapped`, `turn_gate.gd` |
| 2 | **AIM** | Active pen gets a "YOUR FLICK" cue; press must land on that pen's capsule + 26 px finger margin; drag back; release | `main.gd` `_feed_aim_overlay`, `aim_input.gd` `_press_on_pen` |
| 3 | **Flick** | `direction = −drag`, `power = dist/160` clamped, `contact_offset = grab point along barrel (−1…+1)`; impulse = `power × 1600`, applied as an offset impulse so an off-centre skew grab **spins** the pen (torque) | `aim_input.gd` `_release`/`_contact_offset`, `main.gd` `_on_flick_ready`, `pen_body.gd` `apply_flick` + `_integrate_forces` |
| 4 | **IN_FLIGHT** | Pen slides/spins; the **only collision in the scene is pen-vs-pen** (no walls); impacts ≥60 px/s fire sound, haptics and trauma shake; hit-stop on the decisive contact | `pen_body.gd` `_update_impact`, `main.gd` `_on_pen_impact`, `feel.gd` |
| 5 | **Settle** | Both bodies below (6 px/s, 0.4 rad/s) for 0.25 s → `settled`; hard 8 s in-flight backstop makes it safe | `pen_body.gd` `_update_settle`, `turn_state.gd` `resolve_tick` |
| 6 | **Judge** (geometric, *before* any ceremony) | A capsule endpoint leaves the table rect (8 px jitter tolerance) → that pen's player loses. Same-tick double-OOB → **the flicker loses**. Both settled and nothing moved → stalemate forfeit. 15 s with no flick → idle forfeit, the other player wins | `turn_state.gd` `resolve_pending_oob` / `on_settled` / `forfeit_tick`, `pen_body.gd` `_any_part_outside`, `main.gd` `FORFEIT_TIMEOUT` |
| 7 | **Ceremony + verdict** | Hit-stop (3–6 frames) + shake, haptics, then a gate prompt carrying the running score; tap starts the next round (or a rematch) | `main.gd` `_check_game_over`/`_trigger_ceremony`/`_update_gate`, `feel.gd` |
| 8 | **Match** | A round win is counted on resolution; first to `ceil(N/2)` wins a best-of-`{1,3,5,7}` match; the match-over tap resets the score to 0–0 | `main.gd` `_round_wins`, `settings_store.gd` `rounds_to_win` |
| 9 | **Meta** (not the loop) | Pen skins (4 designs), match length, sound/haptics/shake — persisted to `user://settings.cfg` | `settings_store.gd`, `settings_screen.gd`, `main.gd` `_apply_settings` |

**Loop drivers — why anyone takes another cycle:**

- **Risk on every shot.** Your own pen can leave the table, and OOB is checked for
  *both* pens every physics tick (`pen_body.gd` `_update_oob`), so a hard flick is
  a real gamble, not a free attack. This is the tension source.
- **Unsolved geometry.** No trajectory prediction by explicit design
  (`docs/ART_AND_FEEL_SPEC.md` §8) — estimating the bounce is the skill, and the
  corner-flick spin (grab offset × skew) is the expression lever.
- **Impact feedback.** Trauma² shake, hit-stop, layered pitch-randomised sound,
  haptics — the "the world reacted" beat lands on every collision.
- **Legibility.** Idle turn cue plus a gate prompt that carries the score
  (`main.gd` `_update_gate`).
- **The opponent.** In hot-seat, the reason to re-enter is the human on the other
  side of the phone. This is a real driver — and it is **external to the game**.

---

## Loop Breaks and Dead Steps

Five findings, ordered by damage. The first two are trust/motivation-breaking;
the last three are structural hygiene.

### 1. Weak motivational closure — the "re-enter" leg is not in the game

- **Issue:** nothing the player does outlives the round. The only durable state
  in the entire build is six settings keys — `sound_on`, `haptics_on`,
  `screen_shake_on`, `match_length`, `pen_red`, `pen_blue`
  (`settings_store.gd` `save_to_disk`). No win record, no streak, no unlock, no
  score that survives the match-over tap (`main.gd` `_on_gate_tapped` resets
  `_round_wins` to `{"red": 0, "blue": 0}`). The only feedback that outlives a
  round is an integer rendered on a modal overlay.
- **Cause:** the loop was built as a mechanics + feel slice. That is a defensible
  Phase-1 scope call (`docs/RESEARCH.md` §5), but it means the loop's own
  re-entry leg was never designed — and the two candidate drivers the research
  identified are both blocked: friend-challenge must be async turn-relay, and an
  AI opponent is an architectural dead end on non-deterministic Godot 2D physics
  (`docs/RESEARCH.md` §4.1).
- **Consequence:** the loop cannot self-sustain. Solo re-entry has no in-game
  pull at all; the entire retention argument rests on a second human being
  physically present, plus the 20-round gate. **Inference:** a player with nobody
  to hand the phone to has no reason to open it twice.
- **Change:** see *Minimal Loop Fix*.

### 2. Dead phases and an inert rule path — the state machine advertises more loop than it runs

- **Issue:** `PHASE_FORFEIT` and `PHASE_GAME_OVER` are declared
  (`turn_state.gd:25-26`) and **asserted against in two test suites**
  (`tests/auto_flick_test.gd:82`, `tests/rounds_gate_test.gd:88`) but are never
  assigned anywhere in the codebase. `PHASE_SETTLED` (`turn_state.gd:163`) is
  assigned and overwritten inside the same function, so no observer can ever see
  it. Separately, the documented **stalemate rule is unreachable through human
  input** — `turn_state.gd:42-48` states it outright, and the weakest legal drag
  got *further* from the 25 px/s `MOVED_LINEAR_VEL` threshold when
  `min_drag_pixels` was raised 15 → 30 (`aim_input.gd:46`).
- **Cause:** the phase enum is a spec artifact carried over from
  `docs/phase05-contract.md` (which names a different phase set: `AIM, IN_FLIGHT,
  SETTLED, FORFEIT, GAME_OVER`), and the anti-stall design listed three
  mechanisms (`docs/ART_AND_FEEL_SPEC.md` §7) without checking that all three were
  reachable through the shipped input.
- **Change:** delete the two dead constants and the dead assertions; or wire
  `forfeit_tick` to expose `PHASE_FORFEIT` if the HUD ever wants to read it. Do
  **not** delete the stalemate rule (it still guards scripted flights) but stop
  counting it as one of the loop's stall defences — the idle forfeit is the only
  one that fires in real play.

### 3. The re-entry parameter is alternation wearing a "winner starts" label

- **Issue:** the shorthand **"winner starts the next round"** appears at five
  product sites — `main.gd:516`, `main.gd:537`, `turn_state.gd:19`,
  `turn_state.gd:107` (opening clause) and `game/docs/turn_gate.md:29` — plus five
  test/doc sites — `tests/turn_state_test.gd:267`,
  `tests/rounds_gate_test.gd:11`, `:99`, `:117`, `:225` (the last carries the
  phantom momentum attribution).
  The implementation is strict alternation: `begin_turn()` advances the index by
  one from the last flicker (`turn_state.gd:88-91`). When the flicker *wins* (the
  opponent's pen goes out), **the loser starts the next round.**
- **Nuance — checked against source, and the skill's first read needed
  correcting:** the canonical comment is *not* wrong. `turn_state.gd:105-108`
  spells out the mechanism — "begin_turn() cycles to the next player (the round
  winner when the starter lost, which is the hot-seat convention)" — and
  `turn_gate.md:29` carries the same parenthetical ("the player who started round
  N sits out until round N+1"). So this is **not** a code-versus-doc
  contradiction. It is a labelling problem: the shorthand "winner starts" holds
  in only one of the two outcomes, and the single assertion that carries it
  (`turn_state_test.gd:267`) passes only because its flicker also lost.
- **Consequence — CORRECTED against evidence (20-round gate log, 2026-09-14):** the
  convention is strict alternation, so "winner starts" is a **misnomer, not a myth**.
  The two coincide whenever the *flicker* lost — the common case here, because
  self-OOB ends most rounds — and diverge on a **knockout**, where the next start
  goes to the player who was just knocked out. That divergence is what produces
  streaks: a knockout by X hands the next round to the player X just beat, who then
  tends to lose too, so the same winner repeats. The observed 4–16 split is
  therefore streak-driven, and the 20-round log shows it directly — winners do not
  alternate (`blue, red, red, red`, then twelve blue wins in a row, then red), which
  can only happen through knockouts. So the handoff's attribution
  (`docs/handoff-2026-09-14.md` §5) is right about the *effect* and wrong about the
  *name*; what a human should be asked is whether a long streak reads as
  unfairness — a playtest question, not a code bug.
- **Change:** keep alternation (fairer for hot-seat), make the label true: change
  "winner starts" to "the player who did not flick last starts" in `main.gd:516`
  and `main.gd:537`, `turn_gate.md:29`, and the test message; then add the
  flicker-wins case to `turn_state_test.gd` so the convention is pinned by a test
  that can fail.

### 4. The closing prompt names the default skin, not the pen on the table

- **Issue:** `_display_name()` always maps `red → "Amber"` and `blue → "Cobalt"`
  (`main.gd:643-650`), while the player can render that same slot as **graphite**
  or **ivory** (`main.gd` `PEN_SKINS`, `set_pen_skin`). The gate prompt — the
  single piece of feedback that carries the turn owner, the score and the winner —
  can therefore read *"Amber wins the round 2-1"* while the only pen in that slot
  is drawn as ivory.
- **Nuance:** `red`/`blue` are player-slot ids, not art ids — the pen *is* the
  right player's pen, so this is a naming/legibility defect, not a mislabelled
  identity. The comment at `main.gd:637-642` acknowledges the tradeoff
  ("P1/P2 relabeling is a UI-layer choice, not this constant") and no layer makes
  that choice, so the CVD-safe naming it defends quietly stops matching the art.
- **Change:** derive the display name from `settings_store.pen_for(player)` rather
  than hardcoding Amber/Cobalt. Small, and it protects the CVD-safe naming
  decision the same comment is trying to defend.

### 5. The highest-frequency loop step is a tap, not a decision

- **Issue:** every turn hand-off **and** every round resolution gates on a
  full-screen tap, with the ceremony (hit-stop 3–6 frames + shake) on the same
  overlay (`main.gd` `_update_gate`, `turn_gate.gd`). Per round that is roughly
  two non-game taps per flick. The research already flagged the fatigue point:
  *"a 3-second unskippable ceremony every round adds a full minute of pure waiting
  across 20 rounds"* and asked for it to be skippable after 2–3 rounds
  (`docs/research/05-feel-polish.md` §7).
- **Mitigation already present:** the gate is dismissed by *any* tap and the F
  key (`main.gd` `_unhandled_input`), so the ceremony is skippable — but the tap
  itself is not.
- **Assessment:** for hot-seat this is **correct** — the gate is the fix for the
  single most common failure (flicking on the wrong turn,
  `docs/RESEARCH.md` §3.5 #1) — but it is also the loop's largest fixed per-cycle
  cost, and it argues against match lengths above best-of-3 for repeat sessions.
  Keep it; do not lengthen the ceremony.

---

## Design Implications

Per finding: what to change and what it buys.

1. **Loop step: re-entry / closure.** *(weakest link)* — Cause: no durable
   outcome state. **Change:** persist a match record and surface it on the
   match-over gate. **Expected effect:** the loop acquires an internal re-entry
   leg (a number to defend or beat) with no new systems and no progression design.
2. **Loop step: Judge.** — Cause: dead phases and an unreachable stalemate rule
   make the anti-stall picture unclear. **Change:** prune dead constants, correct
   the docs, and name the idle forfeit as the real stall defence. **Expected
   effect:** no player-facing change; it stops future work from trusting a
   mechanism that cannot fire.
3. **Loop step: Hand-over (round start).** — Cause: a shorthand label
   ("winner starts") across `main.gd`, `turn_gate.md` and one test name that does
   not match the deliberate alternation in `begin_turn()`. **Change:** keep
   alternation, correct the four labels, add the flicker-wins test case, and fix
   the "winner-starts momentum" attribution in `docs/handoff-2026-09-14.md` §5.
   **Expected effect:** round-to-round momentum stops being a phantom variable,
   and the 4–16 imbalance is not carried into a human playtest as a false lead.
4. **Loop step: Verdict feedback.** — Cause: names keyed to default skins.
   **Change:** name the pen the player actually chose. **Expected effect:** the
   feedback leg stays unambiguous once a player has customised.
5. **Loop step: Tension.** *(already strong — protect it)* — No trajectory
   prediction, self-OOB risk, and corner-flick spin are the loop's skill
   expression. **Change:** nothing. Add no aim assistance, no power preview, no
   outcome readout before resolution.

---

## Minimal Loop Fix

**Persist one line of match history and put it on the match-over gate.**

`settings_store.gd` already round-trips a `ConfigFile` for six keys; add two
(`matches_won_red`, `matches_won_blue`) and have `main.gd` `_update_gate` include
them in the match-over prompt: *"Amber wins the match 3-1 — tap for a rematch
(series: Amber 2, Cobalt 1)"*. Roughly 20 lines, no new systems, no art, no
progression design — and it closes the one leg of the circuit the game currently
outsources entirely to the second human. Pair it with the zero-cost fix from
finding 3 (correct the "winner starts" labels and the momentum attribution) so
the loop's re-entry parameter is described as what it is.

**Do not** respond to this by building unlocks or currencies: `docs/RESEARCH.md`
§4 already argues the revenue case does not pay for that work, and the loop's
problem is not a shortage of reward *types* — it is that no outcome survives the
round.

---

## Assumptions and evidence limits

- No human has played this build (`docs/handoff-2026-09-14.md` §5 lists the
  20-round hot-seat playtest as **blocked on the user**). Everything above is read
  off the shipped code, the tests, and the design/research docs — not from
  observed player behaviour.
- Feel and physics are playtest-only by construction; the 20-round CI gate
  (`tests/rounds_gate_test.gd`) proves the loop *resolves* 20 times without
  deadlock, and says explicitly that it cannot measure "want a 21st".
- `docs/ART_AND_FEEL_SPEC.md` is **three phases stale** (360 px pens / 1120×600
  table / centre-of-mass OOB vs the shipped 180 px / 1180×640 / geometric OOB —
  `docs/handoff-2026-09-14.md` §2). Every geometry claim above is taken from the
  code, not from that spec.
- `CONTEXT.md` and `docs/adr/` do not exist in this repo, so no glossary or ADR
  vocabulary constrained the terms used here (`docs/agents/domain.md`).


## Re-check (2026-09-16) — the five findings are closed; the loop has a second, unbuilt leg

This pass was written before `CONTEXT.md` existed and before the Rival Circuit tickets. Everything in it
has since been acted on, and one of its assumptions is now wrong. This section is the delta.

### Status of the five findings and the minimal fix

`docs/design/feature-priorities.md` §Status carries the commits. Finding 1 **closed** by `59c44a1` (series
record, `[SERIES]` log, gate line, `series_record_test.gd`); findings 2 and 3 **closed** by `535af4d` (dead
phase constants and dead test arms deleted, labels corrected to strict alternation with the missing
knockout case pinned by a test); finding 4 **closed** in the same pass (`_display_name()` now names the pen
actually being played); finding 5 **kept as intended** — the two taps per flick are what cap a match at
best-of-3. The minimal loop fix shipped as finding 1's closure.

### What this pass got wrong

- It says `CONTEXT.md` and `docs/adr/` do not exist. `CONTEXT.md` now exists and is authoritative for the
  product language (Round, Match, Hot-seat Series, Solo Progress, Rival Circuit, Mastery Stamp).
- It treats the loop's re-entry leg as one problem with one fix. There are now **two** answers to "why does
  the player come back", and only the weaker one is built: the hot-seat series count (shipped) and the Solo
  Rival with its Mastery Stamp (`docs/design/solo-rival.md` — decided, **not implemented**;
  `game/scripts/match_config.gd:5` declares `solo`, nothing in `game/` constructs it,
  `game/scripts/main.gd:382-386` only ever builds two humans, and there is no mode screen).

### The number this pass did not have

The attributed prototype run resolved 10 of 24 shots: **14 ended by the 8 s in-flight backstop** and only
4 were knockouts (`game/prototypes/policy_bot/results/rival_matrix.json`). The 20-round autoplay log said
the same thing from the other side — self-OOB ends most rounds — and the instrumentation shipped below
confirms it with attribution.

### Shipped in response

Rounds now report **how** they were decided. `TurnState.decided_by()` returns `knockout` / `self_oob` /
`stalemate` / `idle` / `backstop`, `state()` carries it, and `Main` tallies rounds, verdicts and flicks in
`LoopStats` (`game/scripts/loop_stats.gd`), printing one session-cumulative line at every match end.
`decided_by_oob()` is now *derived* from that single field instead of being a second flag — the prototype
harness produced its mis-attributed metric from exactly such a duplicate
(`game/prototypes/policy_bot/match_harness.gd:230-232`).

**First real reading** (headless 20-round gate, `0382e4c`, scripted flicks at 0.5–1.0 power):

```
[LOOP] rounds=18 flicks=49 shots/round=2.72 knockout=1 self_oob=17 stalemate=0 idle=0 backstop=0 contact=18 (100%)
```

18 of the gate's 20 rounds are in that line: the tally prints at match end and the last two gate rounds
were mid-match. Per-round attribution is always present in the `[GAME OVER]` line.

Read it with the right caveat — this is scripted play with no aim, so it overstates self-OOB against a
human who deliberately aims at the opponent's pen. What it does establish is the *shape*: **every** decided
round ended on a pen leaving the table (100% contact, zero stalemates, zero idle forfeits, zero backstops),
and **17 of 18 were the shooter's own pen leaving**. The last three rounds were each decided by a single
shot that sent the shooter's own pen off. That matches the earlier 20-round log and the prototype matrix,
and it makes legibility — not reward — the thing to fix.

### How to read a playtest with it

Play the 20-round gate (`docs/handoff-2026-09-14.md` §5), then read the last `[LOOP]` line:

- `contact` share is the health number: high means the physics decides rounds, low means rounds end by
  themselves.
- `shots/round` is the pacing number: 1.0 means every round is a one-flick self-OOB, 4+ means real
  back-and-forth.
- `knockout` vs `self_oob` splits "I got them" from "I lost it". `self_oob` should dominate early; if
  `knockout` never grows with familiarity, the shove is not learnable.
- `backstop` and `idle` should be rare with human aim. If they are not, the 8 s cap and the 15 s idle
  timeout are cutting rounds short — a playtest finding, not a guess.

### Still open on the loop

1. Solo is unreachable: mode screen, production bot adapter, `solo` persistence.
2. The series count is anonymous and unresettable — E1 initials and a reset row.
3. The 3-cue turn system (B1) remains the legibility fix for the flick itself; test it on the playtest
   above rather than in the abstract.
4. `PHASE_SETTLED` is still assigned and overwritten inside one call, so no observer can read it.
