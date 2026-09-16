# Solo Rival — frozen decision for issue #10

**Status:** Frozen decision. This document defines the target Solo (Rival) product behavior for V1 and must be honored by the implementation; it does not claim the wiring has been implemented.

**Decision base:** repository commit `1b0ee5d`; issue #10 ("Choose the Rival Circuit progression and mastery goals") and its two grilling rounds with Bhanu (2026-09-16); the policy-bot prototype (`docs/prototypes/policy-bot/`) and its attributed re-measurement (`game/prototypes/policy_bot/rival_matrix.gd`, `game/prototypes/policy_bot/results/rival_matrix.json`, `docs/prototypes/policy-bot/RIVAL-MATRIX.md`); the pen-profile prototype (`docs/prototypes/pen-profiles/`); the match contract (`docs/architecture/MATCH-CONTRACT.md`); the session lifecycle decision (`docs/architecture/SESSION-LIFECYCLE.md`); `CONTEXT.md`; `docs/design/core-loop.md`; `docs/design/design-pillars.md`; `docs/research/05-feel-polish.md`.

## The decision in one paragraph

Solo V1 is a **single Rival match**, not a circuit: one authored opponent, one optional Mastery Stamp, no currency, XP, energy, upgrades, or grind quota. The Rival is the **direct hitter**, playing **Graphite / Anchor**; the player picks their own pen freely. A Rival match is **best-of-3** (first to 2 rounds) and ignores the saved Match Length setting. Beating the Rival once completes the Circuit and records Solo Progress; the Rival stays freely selectable and immediately retryable, and leaving a match records nothing.

## Scope amendment (this changes the map)

The map and `CONTEXT.md` described Solo V1 as an **ordered three-Rival circuit** (direct hitter → spin specialist → edge finisher) with one Mastery Stamp per Rival. Bhanu, 2026-09-16: *"no need of 3 rivals just 1v1"* and *"just 1 persona"*. **V1 ships one Rival.** Consequences recorded here so no downstream ticket has to guess:

- Rival order, per-Rival unlock progression, and the "free-select state" are **void for V1** — with one Rival there is no list to unlock. They return only if a second Rival is added.
- The other two personas and their stamps are **not discarded**; they are specified under *Deferred* below, with the predicates already designed and evidenced.
- The `solo` persistence shape is **per-Rival keyed** so adding Rivals later is additive, not a migration.
- The FTUE visual direction (closed ticket) renders a three-row Rival list with injected lock state (`docs/prototypes/ftue/VISUAL.md:367`, `FLOW-FTUE.md:32`). Those artifacts stay as the dated prototype record; the **FTUE integration ticket reduces the list to one row** and drops "three rivals in order" from the Solo card copy. Nothing in those artifacts is rewritten here.

## The Rival

- **Persona:** the direct hitter — strong, near-centred direct shots (`docs/prototypes/policy-bot/DECISION.md:20`). Authored score weights `alignment 0.70 / impulse 0.20 / reach 0.10 / safety 0.05`, independent seeded score noise in `[-0.035, +0.035]` per candidate, and a visible fixed **250 ms** think delay before committing (`docs/prototypes/policy-bot/DECISION.md:12-16`). No forward simulation, no retry, no post-launch physics change.
- **Readable signature (measured):** spin usage `0.0000`, mean absolute contact offset `0.2200`, mean impulse `0.8900` (`docs/prototypes/policy-bot/METRICS.md:18`) — the most legible of the three authored personas, which is what a lone opponent has to be.
- **Pen model:** Graphite / Anchor (`mass 1.4–1.8`, measured travel −123…−200 px, launch peak −319…−496 px/s; `docs/prototypes/pen-profiles/DECISION.md:23`). It is the hardest pen to shove off the table, so a lone Rival cannot beat itself and the player must actually outplay it.
- **Player pen:** free choice, **mirror allowed** (`docs/prototypes/pen-profiles/DECISION.md:30-32`). Under Pen Powers both profiles are revealed simultaneously before the first flick and locked for the whole match, including rematches (`DECISION.md:30-31`).
- **Why not the other two** (evidence, not taste): the spin specialist resolved **0 of 4** shots against the stand-in opponent — as a lone opponent it is the weakest possible first impression; the edge finisher is measured the strongest (4–0) but its pairing with the direct hitter produced **0 resolved rounds in 4 shots**, and a lone Rival that can stall into unresolved rounds has no fallback opponent.
- **Lesson copy (V1, behaviour-only, true in both rulesets):** *"Straight and committed: it flicks down the middle as hard as it can. Answer force with force."*

## Match format

- **Best-of-3 per match** — first to `ceil(3/2) = 2` round wins (`game/scripts/settings_store.gd:46`).
- The Rival match **ignores the saved Match Length setting** (`[1,3,5,7]`, default `5`; `settings_store.gd:28,33`), which stays meaningful for hot-seat and for any future mode. The Rival screen states the format so a player who set best-of-7 is not surprised.
- Rationale already in-repo: the full-screen gate is the loop's largest fixed per-cycle cost and *"argues against match lengths above best-of-3 for repeat sessions"* (`docs/design/core-loop.md:197-201`).
- A round is decided exactly as the loop already specifies (`docs/design/core-loop.md:59`): a pen leaving the table loses for its player; same-tick double-OOB loses for **the flicker**; both-settled-no-movement is a stalemate forfeit; 15 s with no flick is an idle forfeit. Round resolution is geometric and immediate (`game/scripts/turn_state.gd:188-217` resolves on the first tick with any pending OOB event).
- Rounds are decided **mostly by the opponent's mistake, not by a knockout** — in the attributed measurement 4 of 24 shots were knockouts and 14 ended by the 8 s backstop. The format must therefore never present a round loss as a physics accident.

## Mastery Stamp — one, optional, non-repeatable

- **DECISIVE** — *win a round by knocking the Rival's pen off the table with a centred contact (`|contact_offset| < 0.5`).*
- **Round-scoped.** It is earnable in a match the player goes on to lose; progress never un-earns.
- **Optional and never a gate.** A Mastery Stamp records demonstrated play; it is not currency, an upgrade, or a requirement to continue (`CONTEXT.md:89-90`).
- **Why this predicate:** the Rival's own lever is the centred hit, so the stamp asks the player to answer in the Rival's own language. It is demonstrably achievable — in the attributed measurement the hitter persona won a round by knocking the stand-in's pen off with a centred contact (`offset 0.22`, `impulse 0.89`).
- **Why not "win a round by knockout without your own pen leaving the table":** that predicate **collapses into DECISIVE**. `turn_state.gd:188-217` buffers OOB events and resolves on the first tick with any pending event; a single-pen OOB loses for that pen's player, a same-tick double-OOB loses for the flicker, and the round then parks. So any knockout the player wins already implies their pen stayed on the table at the deciding tick — the extra clause can only exclude a same-tick double-OOB, which is a loss, not a win.
- **What the implementation needs:** per-round observations in the match result — round winner, how it was decided, and the deciding flick's `contact_offset`. **Partly shipped since this decision:** the verdict vocabulary is now first-class in the live loop — `TurnState.decided_by()` reports `knockout` / `self_oob` / `stalemate` / `idle` / `backstop`, `LoopStats` tallies it per session, and the match-over log carries it per round (`docs/design/core-loop.md`, §Re-check). That is finer than the `oob` / `forfeit` pair this bullet assumed, so the stamp predicate can be evaluated from the shipped verdict without a new taxonomy. Still missing: the deciding flick's `contact_offset` on the result boundary, and per-round detail inside #11's immutable result. `contact_offset` is already a first-class physics input (`docs/architecture/MATCH-CONTRACT.md:46,90`), and #11's immutable result already carries winner, score, mode/ruleset and rival — but **not** per-round detail, so the result boundary must be extended by the implementing ticket.

## Completion state, selectability, rematch

- **Completion = beating the Rival once** in a best-of-3, at any score. Stamps are optional and do not affect it.
- On completion the Solo Progress record shows the Rival as **defeated** with a completion marker, plus a separate stamp marker once DECISIVE is earned. No new art or ceremony asset in V1; the match-over gate states it in words.
- **Selectability:** the Rival is selectable from HOME → Solo **at all times** — there is no lock, because there is no list. (The tri-state LOCKED / NOW / DEFEATED row design from round 1 is retained only as the shape to reuse if a second Rival is added.)
- **Loss:** immediate retry from the match-over gate. No penalty, no streak requirement, no resource.
- **Rematch:** same Rival, same pens (match-locked), new seed. Progress never un-earns.
- **Leaving mid-match records nothing** — no win, no loss, no stamp (`docs/architecture/SESSION-LIFECYCLE.md`, "Result boundary"; issue #11).

## Ruleset coverage

One Rival, **both rulesets**, shared Solo Progress. The Rival's bot profile is identical under Classic and Pen Powers; only the pens' profiles differ. In Classic the profiles are equal physics, so the Rival's identity is cosmetic; under Pen Powers its profile and lever are disclosed before the first flick (`docs/prototypes/pen-profiles/DECISION.md:31`). DECISIVE is outcome-based and therefore ruleset-independent. The record notes which ruleset a stamp was earned in — display only, never a separate unlock.

## Difficulty budget

**Uniform across the whole Rival match.** Identical authored candidate sets, identical seeded noise `±0.035`, identical visible 250 ms think delay. The Rival's difficulty comes only from its readable style; there are no hidden physical advantages and no disclosed per-Rival ramp in V1. This follows the map's own rule ("Rivals differ through readable strategy and judgment/noise, never hidden physical advantages") and the pillar tiebreaker that rejects anything letting a player win without risking their own pen (`docs/design/design-pillars.md:23,42`).

## Persistence (shape only — #7 owns the schema)

Two booleans per Rival in a new `solo` section of `user://settings.cfg`, keyed by Rival id:

| Key | Meaning |
|---|---|
| `<rival_id>.defeated` | the Rival has been beaten once in a best-of-3 |
| `<rival_id>.stamp` | DECISIVE has been earned |

Everything else is **derived**: completion = `defeated`; nothing stored can disagree with what is displayed. New Rivals are additive keys, not a migration.

Plus one SETTINGS row, **Reset Solo Progress**, behind a confirm, which clears **only** the `solo` keys — never the hot-seat series (`matches_won_red/blue`), pen choices (`pen_red/pen_blue`), match length, sound/haptics/shake (`game/scripts/settings_store.gd:24,28,33,34,40`). Rationale: the Rival is the first-run solo experience, and without the row the only reset is clearing app data, which would wrongly wipe the hot-seat series too. SETTINGS is unreachable during a live match (#11), so the row is safe by construction.

## Evidence

Attributed re-measurement, 6 fixed seeds × 4 shots = 24 shots (14 ended by the 8 s backstop, 10 resolved); harness `game/prototypes/policy_bot/rival_matrix.gd`, raw results `game/prototypes/policy_bot/results/rival_matrix.json`, note `docs/prototypes/policy-bot/RIVAL-MATRIX.md`:

| Pairing | Rounds | Persona-caused knockouts | OOB caused by the persona | OOB caused by the opponent |
|---|---|---|---|---|
| hitter vs stand-in | 2–0 | 1 (centred 0.22, impulse 0.89) | 0 | 2 |
| spin vs stand-in | 0–0 | 0 | 0 | 0 |
| edge vs stand-in | 2–0 | 0 | 0 | 2 |
| hitter vs spin | 1–1 | 1 (spin, offset 0.88) | 0 | 2 |
| hitter vs edge | 0–0 | 0 | 0 | 0 |
| spin vs edge | 0–2 | 2 (both edge, centred 0.00, impulse 0.94) | 0 | 2 |

- Resolved-round record: **edge 4–0, hitter 3–1, spin 1–3.** Resolve rate against the same stand-in: hitter 2/4, edge 2/4, spin 0/4.
- **Correction to `METRICS.md`:** its `oob_rate` could not attribute an OOB to a pen. With attribution, the edge persona caused **zero** OOBs of its own; every OOB in its pairings was the opponent's pen. The "edge is self-destructive" reading that the old number invited is unsupported.
- **Both stamp levers are physically demonstrated:** a centred contact knocked a pen off (hitter) *and* an off-centre contact knocked a pen off (spin, `offset 0.88`) — relevant to the deferred SIDESWIND.
- **Stall risk is real:** hitter vs edge produced 0 resolved rounds in 4 shots. Two committed centred opponents can trade shots without resolution, which is why the format and the retry path matter more than any difficulty knob.

## Deferred (not in V1 — do not build)

- **Rival 2, spin specialist** on Amber / Spin: authored set `alignment 0.48 / impulse 0.38 / reach 0.14 / safety 0.05` (`policy-bot/DECISION.md:12-16`), signature `spin_usage 1.0`, mean offset `0.88`. Stamp **SIDESWIND** — win a round by knocking the Rival's pen off with an off-centre contact (`|contact_offset| ≥ 0.5`). Caveat for whoever revives it: measured weakest converter (0/4 resolved vs the stand-in).
- **Rival 3, edge finisher** on Ivory / Glide: authored set `alignment 0.57 / impulse 0.18 / reach 0.18 / safety 0.07`, signature centred (`0.00`), impulse `0.94`, fastest settle. Stamp **STAY OFF THE LIP** — win a round without your pen entering the outer band. This is the only stamp needing new telemetry (the player's minimum distance to the OOB line over the round, ~5 lines where pen positions are already live), and it is the only one with a `[TUNE]` constant: **band = half a pen length = 90 px**, measured against the shipping verdict geometry, not the art rect. Why that value: the shipping collision capsule is 180 px long with radius 5 (`game/scripts/pen_body.gd:45-48`), pens start 240 px clear of the nearest edge (`game/scenes/main.tscn:40`, `game/scripts/main.gd:97`), and measured solo travel is 100–200 px (Graphite `pen-profiles/DECISION.md:23`, Ivory `:24`) — so normal exchanges survive it and a big shove does not. The band is stated in the capsule's own units and must be re-derived if the sprite-vs-capsule divergence below is resolved. Validate on device.

## Handoffs and open risks (not #10's to fix)

1. **The docs and the shipping code disagree about the out-of-bounds rule.** `docs/ART_AND_FEEL_SPEC.md:280-303` states the verdict is **centre of mass** (`not PLAYFIELD.has_point(pen.global_position)`; capsule extents "for presentation, not the verdict"), while `game/scripts/pen_body.gd:271-284` ships the opposite and says so explicitly ("the verdict stays geometric capsule-extent — **never centre-of-mass**"), testing both capsule centreline endpoints against the table rect inset by `pen_radius + OOB_TOLERANCE_PX`. `docs/design/core-loop.md:59` agrees with the code. Two documents against one — the code is authoritative for what ships, and the spec needs correcting.
2. **The spec's pen geometry does not match the shipped capsule.** `docs/ART_AND_FEEL_SPEC.md:92-95` describes a 360 px pen at radius 10; `game/scripts/pen_body.gd:45-48` ships radius 5 / height 180 and its own comment claims the spec says so. Any distance-in-pen-lengths constant (including the deferred band above) must be derived from the runtime capsule until this is reconciled.
3. **There is no production bot.** `docs/architecture/MATCH-CONTRACT.md:147,159` — promoting the hitter policy means a production adapter that converts the chosen candidate into a `ShotCommand` with `source = "bot"` and submits it through `_submit_shot`, with no direct physics API and no source-based bypass. The prototype `PolicyBot` stays prototype evidence until then.
4. **The result boundary needs extending** with the per-round observation record described under Mastery Stamp.
5. **FTUE copy** — see the scope amendment.

## Acceptance for the implementing ticket

1. A Solo Rival match is best-of-3 regardless of the Match Length setting, and the Rival screen says so.
2. Beating the Rival once sets `<rival_id>.defeated`; earning DECISIVE sets `<rival_id>.stamp`; both survive app restart and neither is required to keep playing.
3. A stamp is earnable in a match that is subsequently lost, and is never re-awarded or revoked.
4. Leaving a live match records nothing.
5. Reset Solo Progress clears only the `solo` keys.
6. The Rival is reachable from HOME → Solo with no lock at any point.
