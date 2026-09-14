# Pen-Fight — Design Pillars

`game-design:design-pillars-extractor` applied to the shipped Phase-1 vertical slice of
`~/pen-fight` (Godot 4.7.2 / GDScript, Android, local hot-seat). Method: extract the priorities
the design *actually* lives by — from the loop, the reward/punishment structure, the pacing, the
agency model and the anti-features the code refuses to have — then state what the design gives up
to hold each of them. Every pillar ends in a rule that can kill a feature. Geometry comes from
code, never from `docs/ART_AND_FEEL_SPEC.md`, which is three phases stale (see *Assumptions*).

## Extraction Target

- **Analysed:** the whole shipped game — the Phase-1 vertical slice on `main` (HEAD `666b94e`):
  `game/scenes/main.tscn`, `game/scripts/*.gd`, `game/tests/`.
- **Scope and state:** the product, not a sub-system; meta layers (settings sheet, skin picker)
  appear only where they carry a stance. These are *current* pillars — what the build rewards
  today. Where a stated intent is not reinforced by a system it goes under *Missing or Weak
  Pillars*, not into the pillar set.
- **In one line:** two people at one screen taking one committing, self-endangering flick per turn
  and watching it resolve — with the game refusing to help either of them.

## Extracted Design Pillars

### 1. Risk-Symmetric Flicks — every shot is a bet on your own pen

- **Meaning:** the attack and the exposure are the same gesture, and the exposure is not optional.
  Out-of-bounds is evaluated for **both** pens every physics tick regardless of who flicked, so a
  defender's pen rammed off the table loses too (`pen_body.gd:244-249` `_update_oob`, called every
  tick from `pen_body.gd:214-216`); when both leave in the same tick the **flicker loses**
  (`turn_state.gd:200-206`). Nothing contains a hard flick: no `StaticBody2D` exists in
  `game/scenes` (grep), gravity is off (`project.godot:33`), the only collision is pen-vs-pen.
- **Prioritizes:** tension on every shot, not only attacking ones; overlap as the reward for
  precision; the opponent's placement as a live hazard.
- **Sacrifices:** any safe attack. A shot that can only help you is a design failure here, so this
  rules out aim assistance that rescues a misjudged full-power flick, wall or cushion geometry that
  turns a bad flick into a harmless bounce, "defend-only" or "wait" actions, and any turn spendable
  without exposing your own pen.
- **Supporting systems:** `TABLE_RECT` as the single boundary (`main.gd:92`); `MAX_IMPULSE 1600`
  calibrated so full power crosses ~70% of the table and over-power is a real ejection risk
  (`pen_body.gd:38-42`, `:125-134`); the buffered frame-boundary tie rule (`turn_state.gd:174-209`,
  drained at `main.gd:284`); geometric any-part-off verdict with jitter tolerance
  (`pen_body.gd:269-282`, `OOB_TOLERANCE_PX 8.0` at `:54`).
- **Tiebreaker:** if a feature lets you win without risking your own pen, it is out.

### 2. Unassisted Geometry — the aim is estimated, never solved

- **Meaning:** the game gives a direction and a power and refuses to say where the pen will go
  (`aim_input.gd:8-12`: "NO trajectory prediction … the skill ceiling depends on not solving the
  aim for the player"). The overlay holds the line — the launch cone's far end is deliberately open
  ("reads as direction, not predicted path", `aim_overlay.gd:290-306`). Rationale: no bank shots and
  no rails, so the physics to predict is a straight line, and a drawn path would delete the skill
  expression (`docs/research/05-feel-polish.md:76`).
- **Prioritizes:** in-head estimation plus precise execution; the mastery curve as the product's
  substance; the human beside you as the only viable teaching channel.
- **Sacrifices:** accessibility and onboarding — the category's calibration affordances (the drawn
  guideline, the previous-shot ghost trail, explicitly the rejected reference at
  `docs/research/05-feel-polish.md:76`), any angle or outcome readout, and bank geometry that would
  make prediction worth assisting.
- **Supporting systems:** cancelling short drag and capped power (`min_drag_pixels 30`,
  `max_drag_pixels 160`, `aim_input.gd:46-48`, `:199-208`); capsule-wide grab zone with a 26 px
  finger margin (`aim_input.gd:54`, `:165-178`); open-ended launch cone and power fill
  (`aim_overlay.gd:290-330`); no path-prediction code (grep: the only "trajectory prediction"
  string is the comment forbidding it, `aim_overlay.gd:17`, `:293`).
- **Nuance — checked against source.** The overlay *does* predict one thing: a spin arc reading out
  the pen's own predicted angular velocity from the grab offset (`aim_overlay.gd:341-358`). Not a
  contradiction — spin is a property of your grip, the path is the opponent's geometry — but it is
  an **unstated line**. Write it down or the next overlay change crosses it unnoticed.
- **Tiebreaker:** if a feature says where the pen will end up, it is out; if it says what your own
  grip is doing, it is allowed.

### 3. One Grab Point, One Outcome — the contact point is a real input axis

- **Meaning:** where on the barrel you grabbed is preserved through the flick as torque. The grab
  offset is computed in `[-1, 1]` along the barrel (`aim_input.gd:186-192`), passed unchanged
  through `main.gd:365-368` into `pen_body.gd:125-134`, and applied at `:210` as an offset impulse
  with a rotation-only arm (`pen_body.gd:175-194`, `APPLY_IMPULSE_WORLD_TRANSLATION = false`). An
  off-centre grab with a drag skewed to the barrel spins the pen as it slides; a centred grab is a
  clean slide (`pen_body.gd:121-124`). The corner flick — the real playground trick — as a
  mechanical axis, not a flourish.
- **Prioritizes:** plausibility of the real pen-fight; a second, non-numeric skill axis beside
  power; expression as a personal signature.
- **Sacrifices:** input forgiveness and uniform output. Two identical drags from different grip
  points do not produce the same shot, so the game cannot be balanced as if power + direction were
  the whole input, and nothing may normalise the axis: no auto-centring the grab, no click-to-flick,
  no spin-free reticle that ignores `contact_offset`, no per-skin mass/spin modifier that flattens
  it. (The friction / per-skin mass lever proposed in `docs/handoff-2026-09-14.md:191` is exactly
  the change this pillar adjudicates — it may ship only if it preserves the axis for both pens.)
- **Supporting systems:** `aim_input._contact_offset` → `main._on_flick_ready` →
  `pen_body.apply_flick` → `_to_world()`. The arm offset is **probe-measured, not assumed** —
  `pen_body.gd:175-184` records an 8.6x spin error from the pre-fix transform, locked by
  `tests/torque_arm_probe.gd`; the spin arc is its readout (`aim_overlay.gd:341-358`).
- **Tiebreaker:** if a change makes grip position stop mattering, it is out.

### 4. Verdict Before Ceremony — the world reacts, but it never decides

- **Meaning:** the outcome is decided geometrically and completely before any presentation runs.
  The state machine resolves OOB and forfeits itself and parks in `PHASE_ROUND_OVER`
  (`turn_state.gd:9-19`, `:174-209`, `:239-247`); the OOB handler that fires the ceremony is
  connected **after** the resolver so it always runs on a decided result (`main.gd:184-192`); the
  ceremony refuses to run unless the phase is already `ROUND_OVER` (`main.gd:464-469`); hit-stop
  near-freezes at `time_scale 0.02` and never `0.0`, because `0.0` reportedly produces spurious
  collisions on resume (`feel.gd:10-14`, `:25`).
- **Prioritizes:** one unambiguous author of truth; juice as pure reaction; and, in a
  two-people-one-screen game, the loser never being able to blame the presentation.
- **Sacrifices:** suspense mechanics of every kind — no slow-motion build-up before an outcome, no
  last-chance input during the ceremony, no presentation effect that can change who won, no
  photo-finish rule. It also forbids a second judge: the scene's `ExitZone` `Area2D`
  (`main.tscn:93-96`) is read by no script, because the geometric capsule test is the only verdict.
- **Supporting systems:** `turn_state.gd` as pure logic with no scene-tree or physics dependency
  (`:1-14`), so the verdict is unit-testable; `pen_body.gd:_any_part_outside` (`:269-282`);
  `main.gd:_check_game_over` / `_trigger_ceremony` / `_on_out_of_bounds` (`:456-501`) with ceremony
  strength keyed to how the round was decided (`main.gd:500-501`); `feel.gd` and `haptics.gd` as
  reaction-only consumers (double pulse on knockout, `haptics.gd:53-55`).
- **Tiebreaker:** if a feature can change who won after resolution, it is out, however good it feels.

### 5. The Gate Outranks the Flow — turn ownership beats pace

- **Meaning:** every handoff and every round resolution gates on a full-screen tap-to-continue
  overlay, and flick routing is hard-locked outside `AIM` (`aim_input.gd:35-39`, `main.gd:59`,
  `:288-290`, `:528-531`; `turn_gate.gd:64-82` dismisses on any press and marks it handled). It
  exists for one reason: the commonest hot-seat failure is a player flicking on someone else's turn
  (`main.gd:13-21`; `docs/RESEARCH.md:190-192` ranks this fix #1 by effect per hour).
- **Prioritizes:** legibility of whose turn it is — the gate plus the idle "YOUR FLICK" cue
  (`main.gd:417-437`) — over pace and over flow.
- **Sacrifices:** momentum and session length. The gate is the loop's largest fixed per-cycle cost
  (~2 non-game taps per flick) and the loop's own analysis concludes it argues against match
  lengths above best-of-3 for repeat sessions (`docs/design/core-loop.md:176-192`). Rules out
  removing or softening the input lock, auto-advancing rounds, a non-blocking gate, lengthening the
  ceremony, and putting the confirm target outside the incoming player's reach.
- **Supporting systems:** `turn_gate.gd` (self-contained presentation, no game state);
  `main.gd:_show_gate` / `_on_gate_tapped` / `_update_gate` (`:504-567`); `PHASE_ROUND_OVER` parks
  with no auto-advance (`turn_state.gd:105-113`); and the correctness rule falling out of the same
  stance — the forfeit clock is suspended under the gate **and** under the settings sheet
  (`main.gd:272-279`), because being asked to tap, or reading settings, must never cost you a round.
- **Tiebreaker:** if a change trades turn-ownership legibility for pace, it is out; a harder lock
  needs a real wrong-turn failure to justify it.

## Conflicts and Contradictions

1. **Pillars 1 and 2 make the first minutes hostile, and that is the price of both.** Self-risk on
   every shot with no assistance means a new player can lose a round before understanding the
   input; the only onboarding channel left is the human beside them, which is why the 20-round
   hot-seat test is the real gate (`docs/ART_AND_FEEL_SPEC.md:529-532`).
2. **Pillars 5 and 2 tax the same resource.** The gate buys correctness with pace; the aim model
   asks for care and estimation. Both ask a burst-play audience
   (`docs/design/multiplayer-audit.md:137-138`) for time it has least. Best-of-1/-3 as the
   repeat-session band is the honest consequence.
3. **Pillar 2's stated line vs the shipped spin arc** (`aim_overlay.gd:341-358` vs `:290-306`) is
   defensible as written above but dangerous while unstated: a later "helpful" overlay change can
   cross it without anyone noticing there was a line.
4. **Pillar 4 is clean; its labels are not.** `begin_turn()` is strict alternation
   (`turn_state.gd:88-91`) while five label sites say "winner starts / winner first"
   (`turn_state.gd:19`, `:107-108`, `main.gd:516`, `:537`, `game/docs/turn_gate.md:29`). The
   behaviour is the deliberate hot-seat convention; the shorthand is true in only one of two
   outcomes (when the flicker wins, the loser starts). Nothing in the pillar set depends on the
   label — do not let a pillar inherit it.
5. **The stalemate rule is scaffolding, not an anti-stall pillar.** It cannot fire through human
   input (`turn_state.gd:42-48`; the weakest legal flick clears `MOVED_LINEAR_VEL 25` —
   `aim_input.gd:46`, `pen_body.gd:36`). What fires is the 15 s idle forfeit (`main.gd:81-87`,
   `turn_state.gd:239-247`). Keep the rule (it guards scripted flights); stop calling it an
   anti-stall defence.
6. **All five pillars describe a two-person, one-sitting product.** The re-entry leg is external to
   the game (`docs/design/core-loop.md:86-105`) and an AI opponent is architecturally blocked by
   Godot 2D non-determinism (`docs/RESEARCH.md:241-259`). A solo feature must be justified *against*
   these pillars, not added for them.

## Missing or Weak Pillars

- **Co-presence — load-bearing, never written down.** The strongest priority in the build is that
  the second human *is* the content: the codebase is built around it (the gate; per-player pen rows,
  `game/scripts/settings_screen.gd:21-23`; exactly two pens, `main.gd:179`), yet no system carries it
  past the session. Durability was given up by omission rather than decision — the core loop's #1
  break (`docs/design/core-loop.md:86-105`) and the substrate every social option needs
  (`docs/design/multiplayer-audit.md:183-189`; that audit is unverified by me). Recommend promoting
  it to a written sixth priority whose stated sacrifice is *progression*: cut unlocks, currencies
  and rank on purpose, and keep exactly the minimum durable record.
- **Legible identity — present but self-contradicting.** Four selectable skins exist and persist
  (`main.gd:106-123`, `settings_store.gd:79-80`), yet the one feedback that names a player hardcodes
  Amber/Cobalt (`main.gd:643-650`) while graphite/ivory are selectable. As a pillar candidate — *the
  game names the pen that is on the table* — it is testable in one line. Labelling defect, not
  behaviour defect: the pen in the slot is the right player's pen (`docs/design/core-loop.md:159-174`).
- **Haptic promise — not verifiable yet.** These pillars lean on "the world reacted" and haptics are
  part of that, but `Input.vibrate_handheld()`'s amplitude parameter is unconfirmed and the OS-level
  setting cannot be queried (`docs/RESEARCH.md:208-210`; `docs/ART_AND_FEEL_SPEC.md:499-508`). No
  pillar may promise a channel that has not run on hardware.
- **Production stance — real, but a constraint rather than a player pillar.** 2D only, no `Light2D`,
  baked shadows, assets produced at capsule scale, CC0-only sourcing (`docs/RESEARCH.md:164-184`;
  `docs/handoff-2026-09-14.md:108-133`). It has a sharp no — "no feature may require a purchased
  asset, dynamic lighting, or a 3D physics rewrite" — so name it a production rule and stop it
  competing with the player-facing five.

## Decision Guidance

Ordered, so a tie is decided rather than debated.

1. **Pillar 4 dominates all.** Any feature that can alter a resolved outcome is rejected regardless
   of feel. The code already enforces this by connection order (`main.gd:184-192`) — keep it
   structural.
2. **Pillar 1 outranks Pillar 2 when they collide.** Protect self-exposure before difficulty: a
   change that helps a new player by removing *their own* risk is worse than one that helps by
   clarifying input state.
3. **Pillar 2 outranks Pillar 5.** Refuse aim assistance even where it costs onboarding;
   onboarding's answer is the human in the room, not a line on the screen.
4. **Pillar 5 never overrides Pillars 1-3.** Do not lengthen, entrench or add ceremony to guard
   against a real risk; the input lock is the guard.
5. **Pillar 3 is the one to protect while tuning.** Damping, mass and friction may be A/B'd;
   grip-position sensitivity may not be normalised away.
6. **Cut test for any new feature.** Reject if it (a) adds a way to win without risking your own pen;
   (b) tells the player where the pen will go; (c) makes grip position stop mattering; (d) changes
   who won after resolution; (e) adds durable state the seated match does not read — defer (e) until
   the durable record exists, then re-ask; (f) requires a purchased asset, dynamic lighting, or a 3D
   physics rewrite.
7. **Challenge these artifacts** — none is supported by the pillar set: `PHASE_FORFEIT` and
   `PHASE_GAME_OVER`, declared at `turn_state.gd:25-26` and assigned nowhere (referenced only in
   test conditions, `tests/auto_flick_test.gd:82`, `tests/rounds_gate_test.gd:88`); `PHASE_SETTLED`,
   assigned at `turn_state.gd:163` and overwritten inside the same function; the `ExitZone` `Area2D`
   (`main.tscn:93-96`, read by no script); and the "anti-stall stalemate rule" framing
   (`turn_state.gd:42-48`).

## Minimal Fix

**Correct the labels; change no mechanic, because the mechanics already are the pillars.**

1. Make the five "winner starts / winner first" sites describe alternation (`turn_state.gd:19`,
   `:107-108`; `main.gd:516`, `:537`; `game/docs/turn_gate.md:29`), and add the flicker-wins case to
   `tests/turn_state_test.gd` so the convention is pinned by a test that can fail.
2. Derive the verdict name from `settings_store.pen_for(player)` (`settings_store.gd:48-49`) instead
   of the hardcoded map at `main.gd:643-650`.
3. Decide explicitly whether **Co-presence** is promoted to a written sixth priority — and if it is,
   pair it with the one durable-record change the loop and the social audit both converge on
   (`docs/design/core-loop.md:226-242`). A sacrifice made by omission is not a pillar, it is a bug.

## Assumptions and evidence limits

- **Docs are not all current; where they disagree with code, the code wins.** `README.md:6-9` still
  says the skeleton is not committed while HEAD `666b94e` has many commits of game code.
  `docs/ART_AND_FEEL_SPEC.md` is stale on geometry, physics and settings, verified: table
  `Rect2(80,60,1120,600)` (`:43`) vs `Rect2(-590,-320,1180,640)` (`main.gd:92`); pen `360 x 20`
  (`:44-45`) vs capsule radius 5 / height 180 (`main.tscn:12-14`) drawn at 180x10 (`main.gd:94-100`);
  centre-of-mass OOB (`:270-293`) vs geometric any-part OOB (`pen_body.gd:269-282`); `MAX_DRAG 220` /
  `CANCEL_RADIUS 34` (`:393-395`) vs `max_drag_pixels 160` / `min_drag_pixels 30`
  (`aim_input.gd:46-48`); `angular_damp 4.0` (`:185`) vs `1.5` (`main.tscn:44`); stretch `expand` and
  renderer `mobile` (`:124-127`) vs `keep_height` / `gl_compatibility` (`project.godot:26-27`). No
  number above comes from that spec.
- **No human has played this build, and the research is snippet-sourced.** The 20-round hot-seat
  playtest is blocked on the user (`docs/handoff-2026-09-14.md:186`), so feel statements above are
  inferences from code; no external page was ever opened during the research pass
  (`docs/RESEARCH.md:27-47`), so Pillar 5's effect-per-hour ranking and Pillar 2's no-bank-shots
  rationale (`docs/research/05-feel-polish.md:76`) inherit that weakness.
- **`docs/design/multiplayer-audit.md` is a prior audit, not one I verified.** Cited only where it
  agrees with code I opened myself.
- **Absence claims are grep-backed, not assumed.** Case-insensitive grep for
  `ENetMultiplayer|MultiplayerAPI|MultiplayerPeer|WebSocket|HTTPRequest|HTTPClient|PacketPeer|rpc|matchmak|leaderboard|profile|account|guild|club|friend`
  over `game/scripts`, `game/scenes`, `game/tests`, `game/project.godot` returns nothing; no
  `StaticBody2D` in `game/scenes`; no progression/durability construct
  (`unlock|streak|xp|level_up|coins|currency|badge|reward|matches_won`) in `game/scripts` or
  `game/tests` — the only persisted state is six settings keys (`settings_store.gd:73-80`) plus
  `_round_wins` zeroed on the match-over tap (`main.gd:556-559`); no script reads `ExitZone` /
  `Area2D` / `body_exited`.
- **Behaviour fact vs labelling fact, kept separate.** Behaviour: strict alternation
  (`turn_state.gd:88-91`), the two dead phase constants, the unreachable-by-hand stalemate rule, no
  durable outcome. Labelling only: the five "winner starts/first" sites, the Amber/Cobalt verdict
  name, and the `PHASE_SETTLED` write no observer can see. The labelling defects are the cheap ones
  and the Minimal Fix above addresses exactly those.
