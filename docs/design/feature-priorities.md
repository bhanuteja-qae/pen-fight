# Pen-Fight — Feature Prioritization and Build Order

`game-design:feature-prioritization` applied to the Pen-Fight Phase-1 vertical slice
(`~/pen-fight`, Godot 4.7.2 / GDScript, Android, local hot-seat, `main` @ HEAD `666b94e`).

Inputs, all read in full and treated as verified evidence:

- `docs/design/core-loop.md` — the loop, its dead steps, the missing re-entry leg, the persistence fix.
- `docs/design/multiplayer-audit.md` — co-presence is the product; async friend-challenge is the only
  evidence-backed differentiator and must be trajectory-relay, not lockstep.
- `docs/design/design-pillars.md` — the five pillars, used here as the FIT / tiebreaker dimension.

Every claim below about the repo was checked against a file I opened. Absence claims are grep-backed.
Anything I could not verify is in *Assumptions and evidence limits*.

**Citation convention.** A bare `:NNN` inside a paragraph about a named doc refers to that doc
(`docs/handoff-2026-09-14.md` §5, cited as `:186`, means line 186 of the handoff). Code and scene
claims always carry the full repo-relative path.

---

## Candidates

The candidate set is the task's (a)-(d) plus four additions the evidence justifies, marked **(added)**.

### (a) Verified code fixes carried by the audits

- **A1 — Persist a durable match/series record and surface it on the match-over gate.** The re-entry
  leg every audit converges on (`docs/design/core-loop.md` §Minimal Loop Fix, `:228-242`;
  `docs/design/multiplayer-audit.md` §Recommendations item 1, `:305-311`). Today the only persisted
  state is six settings keys (`game/scripts/settings_store.gd:73-80`) and `_round_wins` is zeroed on the
  match-over tap (`game/scripts/main.gd:556-559`).
- **A2 — Make the gate/verdict label match the chosen pen skin.** `_display_name()` hardcodes
  `red -> "Amber"` / `blue -> "Cobalt"` (`game/scripts/main.gd:643-650`) while `PEN_SKINS` offers
  `graphite` and `ivory` (`game/scripts/main.gd:106-123`) and `set_pen_skin` swaps the art
  (`game/scripts/main.gd:131-144`). Derive from `settings_store.pen_for(player)`
  (`game/scripts/settings_store.gd:48-49`). Labelling defect, not a behaviour defect.
- **A3 — Correct the "winner starts" labels to the strict alternation `begin_turn()` implements.**
  Alternation: `_current_index = (_current_index + 1) % _pens.size()` (`game/scripts/turn_state.gd:88-91`).
  Grep found the shorthand at five product sites (A3 sites listed in Evidence limits) plus test/comment
  sites (`game/tests/turn_state_test.gd:267`, `game/tests/rounds_gate_test.gd:11`,
  `game/tests/rounds_gate_test.gd:99`, `game/tests/rounds_gate_test.gd:117`).
  Add the flicker-wins case so the convention is pinned by a test that can fail, and fix the
  "winner-starts momentum" attribution (`game/tests/rounds_gate_test.gd:225`;
  `docs/handoff-2026-09-14.md:186`).
- **A4 — Delete the never-assigned phase constants and the dead test clauses.** `PHASE_FORFEIT` and
  `PHASE_GAME_OVER` are declared (`game/scripts/turn_state.gd:25-26`); grep shows `PHASE_FORFEIT` is
  referenced nowhere else and `PHASE_GAME_OVER` only in two test conditions
  (`game/tests/auto_flick_test.gd:82`, `game/tests/rounds_gate_test.gd:88`). `PHASE_SETTLED` is assigned
  at `game/scripts/turn_state.gd:163` and overwritten inside the same function, so no observer can read it.
- **A5 — Document the aim overlay's spin-prediction line.** The overlay predicts the pen's own angular
  velocity from the grab offset (`game/scripts/aim_overlay.gd:341-358`) while the launch cone is
  deliberately open-ended (`:290-306`). Pillar 2 permits "what your own grip is doing" and forbids
  "where the pen will end up" — write the line down before a later overlay change crosses it.

### (b) The repo's own approved queue (`docs/handoff-2026-09-14.md:188-192`)

- **B1 — Full 3-cue turn system** (mockup parity; the `show_turn` slice is proven live).
- **B2 — Coulomb friction behind a flag + per-skin mass lever** (review item 9; small, A/B-able).
- **B3 — Refresh `docs/ART_AND_FEEL_SPEC.md` to shipped geometry.** Verified stale: the spec's playfield
  is `Rect2(80, 60, 1120, 600)` (`docs/ART_AND_FEEL_SPEC.md:43`, `:296`) against the shipped
  `Rect2(-590, -320, 1180, 640)` (`game/scripts/main.gd:92`); `MAX_DRAG 220` / `CANCEL_RADIUS 34`
  (`:393`, `:395`) against shipped 160 / 30 (`game/scripts/aim_input.gd:46-48`); `angular_damp 4.0`
  (`:185`) against shipped 1.5 (`game/scenes/main.tscn:44`). Three phases stale
  (`docs/handoff-2026-09-14.md:74`).

### (c) The research's strategic bets (`docs/RESEARCH.md`)

- **C1 — Async "challenge a friend remotely" mode.** The only evidence-backed differentiator
  (`docs/RESEARCH.md:237-239`); hard-constrained to trajectory relay, never lockstep
  (`:241-261`), and hard-sequenced after A1 (`docs/design/multiplayer-audit.md:328-338`, `:183-189`).
- **C2 — Play Console registration + 12-tester recruitment.** Uncompressible 14-day calendar clock
  (`docs/RESEARCH.md:99-102`, `:147-156`), scheduled to run in parallel from Phase 1.5.
- **C3 — AI opponent.** Architecturally blocked by non-deterministic Godot 2D physics
  (`docs/RESEARCH.md:255-259`) — an impulse search cannot be reproduced. Discard.
- **C4 — Realtime online PvP / lockstep.** Blocked by the same non-determinism, and wrong for the
  audience's time model (`docs/RESEARCH.md:246-254`; `docs/design/multiplayer-audit.md:342-343`). Discard.
- **C5 — Clubs, guilds, chat, global leaderboards.** Guild-shell and wallpaper risk: no durable
  outcome, no shared goal, exactly two participants (`docs/design/multiplayer-audit.md:344-350`). Discard.

### (d) The human gate

- **G1 — Human 20-round hot-seat playtest of the current APK.** The real Phase-1 gate, blocked on the
  user, not on code (`docs/handoff-2026-09-14.md:186`; `docs/RESEARCH.md:273` "Gate: 20 rounds, want a
  21st"). The headless 20-round gate proves the loop *resolves* and says explicitly it cannot measure
  "want a 21st" (`game/tests/rounds_gate_test.gd:3`, `game/tests/rounds_gate_test.gd:13`).

### (added) Candidates the evidence justifies

- **E1 — Name the two players in the session (initials).** `docs/design/multiplayer-audit.md`
  §Recommendations item 3 (`:316-321`): the settings sheet already uses per-player rows
  (`game/scripts/settings_screen.gd:21-23`, labels at `:340-341`) but still renders "Amber's pen" /
  "Cobalt's pen" from `_display_name()` (`game/scripts/main.gd:247`). Added because a durable record of
  "Amber 2, Cobalt 1" is worth less than "Sam 2, Alex 1" — E1 is what makes A1 land as a series between
  two people rather than two pen slots. Small, zero network, and the first real identity in the build.
- **E2 — Promote Co-presence to a written sixth pillar.** `docs/design/design-pillars.md` §Minimal Fix
  item 3 (`:228-230`). Added because it is a cheap governance decision that stops durability being
  sacrificed "by omission rather than decision", which is exactly how A1 went unbuilt.
- **E3 — GitHub Actions release pipeline.** Added with a verified absence: there is **no `.github/`
  directory and no workflow YAML anywhere in the repo** (see Evidence limits). The handoff's workflow is
  the manual local gate set (`docs/handoff-2026-09-14.md:76-87`); CI is planned for Phase 4
  (`docs/RESEARCH.md:277`; `docs/research/06-workflows.md:83-89`), not present. Cost estimates below use
  the real manual workflow, not a CI that does not exist.
- **E4 — Secrets hardening.** `export_presets.cfg` exists and holds plaintext keystore material
  (`docs/RESEARCH.md:158-162`); the deferred council items are keystore env-var injection, `.claude/` +
  `.mcp.json` gitignore, and float guards (`docs/handoff-2026-09-14.md:194`, explicitly "no secrets risk").
  Added as an explicitly low-priority hygiene row so it is ranked rather than forgotten.

---

## Evaluation Matrix

Scored 1-5: impact and fit are better-high; cost and risk are better-low. Rough structured judgment,
not precision. "Fit" is alignment with the five verified pillars (`docs/design/design-pillars.md`),
with the unwritten co-presence priority (`:166-175`) counted where the item serves it.

| Option | Impact | Cost | Fit | Risk | Timing | Notes |
|---|---:|---:|---:|---:|---|---|
| A1 persistence | 5 | 1 | 5 | 1 | now | Convergence of both audits; ~20 lines on existing `ConfigFile` + gate string |
| A2 skin name | 3 | 1 | 5 | 1 | now | Labelling; makes the playtest instrument honest |
| A3 alternation labels | 3 | 1 | 5 | 1 | now | Labelling + one missing test case; pins the convention and corrects a misnamed (not phantom) momentum effect |
| A4 dead constants | 1 | 1 | 3 | 1 | now | Hygiene; no player-facing change |
| A5 spin-arc line | 2 | 1 | 4 | 1 | now | Docs only; protects Pillar 2's boundary |
| B1 3-cue turn system | 2 | 3 | 4 | 3 | next | Feel claim unvalidated; risks adding ceremony against Pillar 5 |
| B2 friction + mass lever | 3 | 3 | 3 | 3 | next | Pillar 3 adjudicates it: may ship only if grip axis survives |
| B3 ART spec refresh | 2 | 1 | 4 | 1 | next | Stops future work trusting 1120x600 / MAX_DRAG 220 |
| C1 async friend-challenge | 4 | 5 | 4 | 4 | later | Only evidence-backed differentiator; biggest job; scope undecided |
| C2 Play Console + testers | 4 | 2 | 4 | 2 | now | Calendar, not engineering; account-type policy unverified |
| C3 AI opponent | 2 | 5 | 1 | 5 | never | Architectural block, not scope |
| C4 realtime online PvP | 2 | 5 | 1 | 5 | never | Same block; wrong time model; destroys co-presence |
| C5 clubs / leaderboards | 1 | 4 | 1 | 4 | never | Wallpaper over zero durable outcomes |
| G1 20-round playtest | 5 | 1 | 5 | 3 | now | Real Phase-1 gate; blocked on user; measurement noise |
| E1 player initials | 3 | 2 | 4 | 1 | next | Converts a pen slot into a person; hooks A1 |
| E2 co-presence pillar | 3 | 1 | 5 | 1 | next | Doc decision; prevents the omission recurring |
| E3 GitHub Actions CI | 3 | 4 | 3 | 2 | later | Verified absent; not needed to start C2 or G1 |
| E4 secrets hardening | 2 | 2 | 3 | 1 | later | Keystore env injection + gitignore; low urgency |

---

## Priority Ranking

### Do now

1. **A1** — the one build item every audit converges on, and the prerequisite for C1.
2. **A2 + A3 + A5** — a single "make the gate tell the truth" pass. Tiny, and it must land *before* G1
   so the tester is not told "Amber wins 2-1" while the pen is drawn as ivory
   (`docs/design/core-loop.md:159-174`) and the 4-16 split is not carried into the playtest as
   "winner-starts momentum" (`docs/design/core-loop.md:146-152`).
3. **G1** — the human 20-round playtest, on the build that carries A1-A5. A gate, not a feature.
4. **C2** — Play Console registration + 12-tester recruitment; start the calendar clock now, in parallel.
5. **A4** — prune the dead constants and dead test clauses; fold into the A1-A5 pass.

### Test first

- **B2** — friction + per-skin mass must be A/B'd behind a flag, and the test is whether the grip axis
  still matters (`docs/design/design-pillars.md:206-210`). Do not ship on judgment alone.
- **B1** — the 3-cue turn system is a feel bet. Validate on the G1 playtest before investing further,
  because extra turn ceremony is what Pillar 5 already taxes most (`docs/design/design-pillars.md:143-146`).

### Do later

- **E1** if A1 lands first (the series line is the thing E1 makes human).
- **E2** as a one-page decision paired with A1.
- **B3** before any further work reads `ART_AND_FEEL_SPEC.md` for geometry.
- **E3 / E4** when the release path (C2) becomes the bottleneck, not before.
- **C1** strictly after A1 and after open question 2 is answered
  (`docs/RESEARCH.md:294-295` — "Hot-seat only, or is friend-challenge in scope?").

### Discard for now

- **C3, C4, C5** — recorded as "never", with reasons, so they stop re-entering the queue.

---

## Recommendation

The three audits do not disagree about the problem: the loop has one beat of agency wrapped in two
beats of mandatory non-agency, and nothing a player does outlives the round
(`docs/design/core-loop.md:86-105`). The cheapest change that touches the most is A1. It is not a
progression system, and it must not become one — `docs/design/core-loop.md:239-242` argues the loop's
problem is not a shortage of reward *types*. It is that no outcome survives, and the research's revenue
case is too thin to pay for unlocks (`docs/RESEARCH.md:226-235`).

A1 is also the substrate: `docs/design/multiplayer-audit.md:183-189` shows the friend-challenge
differentiator has nothing to challenge *against* without a durable record, so building C1 first means
building it twice. Ship A1 in the same pass as the A2/A3/A5 label fixes, then run G1 on that build.

Two things are deliberately *not* in the top slot. C1 is the only evidence-backed differentiator and it
is still not first: its scope is undecided (`docs/RESEARCH.md:294-295`), its evidence is
snippet-sourced and paraphrased (`docs/design/multiplayer-audit.md:379-381`), and it is the largest job
on the board. C2 is first only in calendar terms — it is zero engineering and it unblocks the release
path, so it runs beside A1, not after it.

The honest counterweight: none of this is validated by a human. Every feel, pacing and social claim in
the input set is inference from code. A1 and the label fixes are cheap enough to ship on that footing;
B1, B2 and C1 are not, which is exactly why G1 outranks them.

---

## Ranked Build Order

| Rank | Item | Impact | Cost | Risk | Pillar fit | Timing |
|---:|---|---:|---:|---:|---|---|
| 1 | **A1** Persist a durable match/series record and surface it on the match-over gate | 5 | 1 | 1 | Serves the unwritten co-presence pillar; violates none of the five | now |
| 2 | **G1** Human 20-round hot-seat playtest of the patched APK (gate, not a feature) | 5 | 1 | 3 | Tests Pillars 1-2's hostility and Pillar 5's pace cost | now |
| 3 | **A2+A3+A5** Make the gate/verdict tell the truth: skin-accurate name, alternation labels + flicker-wins test, documented spin line | 3 | 1 | 1 | Pillar 4 (clean verdict, honest label) + Pillar 2 boundary | now |
| 4 | **C2** Play Console registration + recruit 12 testers | 4 | 2 | 2 | Release path; no pillar conflict | now |
| 5 | **A4** Delete dead phase constants + dead test clauses; stop calling the stalemate an anti-stall defence | 1 | 1 | 1 | Pillar 4 hygiene (labels vs behaviour) | now |
| 6 | **B3** Refresh `docs/ART_AND_FEEL_SPEC.md` to shipped geometry | 2 | 1 | 1 | Prevents future violations of Pillars 1-3 from stale numbers | next |
| 7 | **E2** Promote Co-presence to a written sixth pillar (stated sacrifice: progression) | 3 | 1 | 1 | Governance for Pillars 1-5 | next |
| 8 | **E1** Player initials in the settings sheet and on the score line | 3 | 2 | 1 | Serves co-presence; makes A1 a series between people | next |
| 9 | **B1** Full 3-cue turn system (mockup parity) | 2 | 3 | 3 | Pillar 5 (legibility) at its stated pace cost | next (test first) |
| 10 | **B2** Coulomb friction behind a flag + per-skin mass lever | 3 | 3 | 3 | Pillar 3 adjudicates: out if it flattens the grip axis | next (test first) |
| 11 | **C1** Async "challenge a friend remotely" (trajectory relay, never lockstep) | 4 | 5 | 4 | Must stay a side channel; never replaces the seated match | later |
| 12 | **E3** GitHub Actions release pipeline (verified absent from the repo today) | 3 | 4 | 2 | Release path | later |
| 13 | **E4** Keystore env-var injection + `.claude/`/`.mcp.json` gitignore + float guards | 2 | 2 | 1 | Production stance (CC0/no-secrets) | later |
| 14 | **C3** AI opponent | 2 | 5 | 5 | Violates the co-presence fantasy; blocked by non-determinism | never |
| 15 | **C4** Realtime online PvP / lockstep | 2 | 5 | 5 | Destroys co-presence; architecturally blocked | never |
| 16 | **C5** Clubs, guilds, chat, global leaderboards | 1 | 4 | 1 | Guild shell; no shared goal, no identity layer | never |

Deliberately absent from the queue: aim assistance, trajectory prediction, a prior-shot ghost trail,
wall or cushion geometry, any "defend" or "wait" action, and any second judge of the outcome. Each is
killed by a pillar tiebreaker (`docs/design/design-pillars.md:35-36`, `:57-58`, `:82-84`, `:102-104`).

---

## If you only do one thing

**Persist one durable match/series record and put it on the match-over gate.**

It is the single change both prior audits independently converge on, it closes the one leg of the loop
the game currently outsources entirely to the second human, and it is the hard prerequisite for the only
evidence-backed differentiator the research found. Roughly 20 lines on a `ConfigFile` that already
round-trips (`game/scripts/settings_store.gd:59-81`) plus one line in `_update_gate`
(`game/scripts/main.gd:514-523`) — no new systems, no art, no progression design. Ship it with the
A2/A3/A5 label fixes in the same pass, then run the 20-round playtest on that build: the persistence
line is what makes "want a 21st?" a question about a series rather than about a single unrecorded sitting.

---

## Assumptions and evidence limits

- **No human has played this build.** The 20-round hot-seat playtest is blocked on the user
  (`docs/handoff-2026-09-14.md:186`). Every impact score here is read off code, tests and design docs,
  not observed behaviour, and every feel claim in the input audits carries the same limit
  (`docs/design/core-loop.md:248-254`; `docs/design/design-pillars.md:244-248`).
- **Absence claims are grep-backed, not assumed.** `grep -rniE
  "ENetMultiplayer|MultiplayerAPI|MultiplayerPeer|WebSocket|HTTPRequest|HTTPClient|PacketPeer|matchmak|leaderboard|profile|account|guild|club|friend|RPC"`
  over `game/scripts`, `game/scenes`, `game/tests`, `game/project.godot` returns nothing. Case-insensitive
  grep for `matches_won|win_record|series_wins|head_to_head` over `game/scripts`, `game/tests` returns
  nothing. `grep -rn "StaticBody2D"` over `game/scenes`, `game/scripts` returns nothing, and no script
  reads `ExitZone` / `Area2D` / `body_exited` (the node is declared with no script at
  `game/scenes/main.tscn:93-96`). **GitHub Actions CI does not exist in this repo**: there is no
  `.github/` directory and no `*.yml` / `*.yaml` workflow file anywhere outside `.git`, `assets/` and the
  asset venv (E3 is therefore a plan, not a running gate — this corrects any cost estimate that assumes
  CI already gates work).
- **The "winner starts" label count is contested between the two audits, and my grep agrees with the
  higher one.** `docs/design/core-loop.md:129-136` counts **four** derived sites
  (`game/scripts/main.gd:516`, `game/scripts/main.gd:537`, `game/docs/turn_gate.md:29`,
  `game/tests/turn_state_test.gd:267`) and exempts the canonical mechanism comment at
  `game/scripts/turn_state.gd:105-108`, which it reads as correct. `docs/design/design-pillars.md:150-155`
  counts **five** "winner starts / winner first" sites, adding `game/scripts/turn_state.gd:19` and the
  opening clause of `game/scripts/turn_state.gd:107-108`. My grep found **five product sites**
  (`game/scripts/main.gd:516`, `game/scripts/main.gd:537`, `game/scripts/turn_state.gd:19`,
  `game/scripts/turn_state.gd:107`, `game/docs/turn_gate.md:29`) and **five test/doc sites**
  (`game/tests/turn_state_test.gd:267`, `game/tests/rounds_gate_test.gd:11`,
  `game/tests/rounds_gate_test.gd:99`, `game/tests/rounds_gate_test.gd:117`,
  `game/tests/rounds_gate_test.gd:225`). The discrepancy is a
  definitional one — whether the canonical comment's opening shorthand counts as a label site — not a
  factual one. A3 should fix all product sites plus the momentum attribution in
  `game/tests/rounds_gate_test.gd:225`; the fix is labelling only, the alternation in
  `game/scripts/turn_state.gd:88-91` is deliberate and stays.
- **`docs/ART_AND_FEEL_SPEC.md` is three phases stale** (`docs/handoff-2026-09-14.md:74`) — verified
  against `docs/ART_AND_FEEL_SPEC.md:43`, `:185`, `:296`, `:393`, `:395` vs `game/scripts/main.gd:92`,
  `game/scenes/main.tscn:44`, `game/scripts/aim_input.gd:46-48`. **No number in this artifact is taken
  from that spec.**
- **`README.md` understates the repo state.** `README.md:8-9` still says the playable skeleton "is not
  yet committed"; HEAD `666b94e` has many commits of game code (`docs/design/design-pillars.md:234-236`).
  Not ranked as an item because it is a one-line doc fix; flagged here so the contradiction is on record.
- **Research evidence is weak by the research's own admission.** No web page was opened during the
  research pass; all market and review data is search-snippet-sourced
  (`docs/RESEARCH.md:27-47`), and the "friend battle" complaint backing C1 is a paraphrased theme, not a
  quoted review (`docs/design/multiplayer-audit.md:378-381`). C1's impact score is therefore a 4 on a
  weak evidentiary base — do not over-invest on its strength.
- **The friend-challenge scope is unresolved** (`docs/RESEARCH.md:294-295`, open question 2). This
  artifact sequences C1 after A1 but does not resolve whether it is in scope.
- **Cost scores are calibrated to this repo's real workflow**, per `docs/handoff-2026-09-14.md:76-95`:
  headless Godot `--import` passes, per-suite headless runs (the 20-round gate needs `timeout 1500`, a
  120-180s timeout fails it spuriously), Xvfb `:99` live-render captures, and an Android AAB/APK export
  path. A "cost 1" item is a single editing session plus the import/unit-suite loop; a "cost 5" item is
  multi-session architecture. E3 carries cost 4 partly because no CI scaffolding exists to extend.
- **The three audit artifacts are untracked working-tree files** (`git status` shows `?? docs/design/`).
  They are not committed, so a fresh clone would not contain them. Not a ranked item; noted because the
  build order depends on them.
- **`docs/adr/` and `CONTEXT.md` do not exist** in this repo (`AGENTS.md:15-17` references them, but the
  `docs/agents/` files describe a convention, not files that are present), so no ADR vocabulary
  constrained the terms used here.
