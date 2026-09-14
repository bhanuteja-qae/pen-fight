# Pen-Fight — Multiplayer and Social Feature Audit

`game-design:multiplayer-feature-audit` applied to the shipped Phase-1 vertical slice
of `~/pen-fight` (Godot 4.7.2 / GDScript, Android target — `docs/handoff-2026-09-14.md:5`,
`:47`). Every repo claim below cites a file and line I opened; where a claim is an
inference about what a player would *feel*, it is marked **inference**, because no human
has played this build (`docs/handoff-2026-09-14.md:186` lists the 20-round hot-seat
playtest as blocked on the user).

This audit covers the *social* question only: what social experience this build actually
creates, for whom, at what coordination cost, and whether the online layers the research
proposes extend that experience or damage it. It does not re-argue the core loop —
`docs/design/core-loop.md` does that, and this document is written to be consistent with
it rather than to contradict it.

---

## Audit Target

**The whole shipped social surface:**

- The only multiplayer feature in the build: **local hot-seat**. Two players share one
  device and one table; a pen is flicked, released, watched, and the turn is handed over
  by a full-screen tap gate (`game/scripts/turn_gate.gd`, `game/scripts/main.gd:508-531`).
- The match wrapper: best-of-`{1,3,5,7}` (`game/scripts/settings_store.gd:21`,
  `rounds_to_win()` at `:32-33`), a running score carried on the gate prompt
  (`main.gd:519`), and a match-over tap that resets both players to 0-0
  (`main.gd:556-559`).
- The one persisted personalisation surface: four pen designs
  (`main.gd:106-123` `PEN_SKINS`; `settings_store.gd:27-28`, `:79-80`), persisted to
  `user://settings.cfg`.
- **Everything that is absent.** There is no networking of any kind.
  `grep -rniE "ENetMultiplayer|MultiplayerAPI|MultiplayerPeer|WebSocket|HTTPRequest|HTTPClient|PacketByte|PacketPeer|RPC|matchmak"` across
  `game/scripts`, `game/scenes`, `game/tests` and `game/project.godot` returns nothing;
  `project.godot` contains no network setting; and there is no friend, profile, account,
  leaderboard, chat, replay, ghost, guild, or club construct anywhere in the codebase.

**What kind of social experience it appears to aim for:** co-present, symmetric,
one-shot rivalry between two specific humans who can see each other's face. The
codebase is built *around* that rather than around any mediated system: the gate exists
specifically so a hot-seat player can never flick on the wrong turn (`main.gd:13-18`,
`main.gd:288-290`), and the settings sheet explicitly rejects the design mockup's
single-player framing because a hot-seat game "needs a pen row PER PLAYER where the
mockup's single-player framing had one 'My pen' row"
(`game/scripts/settings_screen.gd:21-23`; `Row` enum at `:34`; the two "…'s pen" labels
at `:340-341`).

---

## Social Promise

**What it actually sells, today:** *"You and the person next to you each get one pen,
one flick, and one shared minute of suspense — and you both watch the same shot land."*
Two people, one table, no account, no queue, no stranger.

**What it does not promise, and never pretends to:** rank against the world, belonging
to a community, status others can admire, or cooperation toward any shared goal. There
are no teammates (`TurnState` is constructed with exactly two pens, `main.gd:179`), no
group, and no durable identity beyond the slot ids `"red"` and `"blue"`
(`game/scripts/pen_body.gd:19`, `main.gd:124`) — pen-slot ids, not accounts.

**The tension to name early.** The research wants to add a *second, different* promise:
**"challenge a friend remotely"** (`docs/RESEARCH.md:237-239`) — the "one
evidence-backed differentiator", which answers the only concrete review complaint found
(users asking for a "friend battle option", `docs/research/01-market.md:44`, `:56`,
`:89(d)`, `:126`). That promise is asynchronous, distant, and mediated. It is compatible
with the co-present promise **only if it is layered as a side channel and never replaces
the seated match.** Holding that line is the whole job of this audit.

---

## Motivation Map

Judged, not listed — which motivations are actually doing work, and which are decorative.

- **Competition — HIGH, and maximally legible.** This is the motivation carrying the
  game. It is the *intimate* kind the rubric prefers: a named rival you can see, a
  score line on the gate (`main.gd:519`), and a knockout you both watch resolve
  (`pen_body.gd:244-249`, `main.gd:456-457`). No matchmaking, no anonymous ranking wall
  — because there is no ranking of any kind. There is also no durable record of who won:
  the six persisted keys are `sound_on`, `haptics_on`, `screen_shake_on`, `match_length`,
  `pen_red`, `pen_blue` (`settings_store.gd:73-80`), and `_round_wins`
  (`main.gd:51`) is reset to `{"red": 0, "blue": 0}` on the match-over tap
  (`main.gd:556-559`). Competition is intense *within a session* and evaporates across
  sessions.
- **Collaboration — NONE.** Zero-sum by construction. Both pens leaving the table means
  the flicker loses (`turn_state.gd:200-203`) — there is no outcome either player can
  cooperate toward.
- **Collaborate-to-compete — NONE.** No teams, no factions, no cohort. Two pens,
  `main.gd:179`.
- **Belonging — NONE system-mediated.** Whatever belonging exists is supplied by the
  real-world friendship of the two people holding the phone, not by the game. There is
  no group to belong to, no ritual the system creates beyond the turn handoff, and no
  group memory. This is not a defect at the current scope; it is a limit of it.
- **Vanity / status — PRESENT as a primitive, effectively dormant.** Four pen designs
  are selectable and persisted (`main.gd:106-123`, `settings_store.gd:79-80`), so a
  taste signal *exists* — but it has almost no social surface to land on (see
  Community and Status Audit). Its only audience today is the one person sitting next
  to you, and even that audience is fed a contradictory label
  (`main.gd:643-650`, see Risk 3).
- **Knowledge exchange — REAL, but oral and co-present.** The game has a genuine,
  teachable skill: the corner-flick spin produced by grabbing off the barrel centre
  (`pen_body.gd:121-134`, `apply_flick`'s `contact_offset`), played with no trajectory
  prediction by explicit design and no bank shots off walls
  (`docs/research/05-feel-polish.md:76`). That is exactly the kind of thing players
  teach each other *in the room* — "grab it at the cap like this." There is zero
  in-game channel for it, and the ideal teaching mode for a hot-seat game is a person
  beside you. **Inference:** this is the build's least-acknowledged social strength and
  a co-presence argument, not an online one.

**Which are merely implied?** Belonging, vanity, and knowledge exchange are all
implied-and-unbuilt. Only competition is load-bearing. A social layer that tries to
carry belonging or status on this foundation has nothing to stand on yet.

---

## Time and Synchronization Audit

**Classification: realtime synchronous, co-located** — the most demanding band on the
scale, and the only one the build supports.

- **Minimum players:** 2, physically present, sharing one device (`main.gd:179`,
  `turn_gate.gd`).
- **Typical interaction length:** one flick is a ≤160 px drag
  (`docs/design/core-loop.md:41-46`) plus flight up to the 8 s backstop
  (`turn_state.gd:58`); a round is a few seconds to under a minute once the gate tap
  and ceremony are counted; a best-of-5 match is roughly 5-10 minutes of shared
  attention.
- **Overlap required:** 100%, and not merely overlapping *screens* — overlapping
  *rooms*. This is the highest coordination cost that exists, and it is the price the
  design pays for zero scheduling software and zero accounts.
- **What happens when a participant misses a step:** the 15 s idle forfeit fires against
  the absent player (`main.gd:87`, `FORFEIT_TIMEOUT`; consumed in
  `turn_state.gd:239-247`). A player who leaves entirely parks the game at the gate —
  the loop's re-entry leg is outsourced to the second human
  (`docs/design/core-loop.md:76-77`, `:101-104`).
- **Burst-friendly?** Yes, and this is a strength. Best-of-1 (`settings_store.gd:21`)
  makes a two-minute participation band real. A single round is a valid session.
- **Mobile-friendly?** Yes for the audience, with one caveat: the turn gate is a
  full-screen modal tap, and the research already flagged the ceremony cost — "a
  3-second unskippable ceremony every round adds a full minute of pure waiting across
  20 rounds" (`docs/research/05-feel-polish.md:317`). The gate is dismissed by any tap
  and the F key (`main.gd:331-348`; `turn_gate.gd:64-82`), so it is skippable. Keep it:
  it is the fix for the category's #1 hot-seat failure (`main.gd:13-18`).

**Time-model mismatch to call out.** The research's proposed differentiator, if built
naively, would move the game from a *co-located realtime* feature to a *non-realtime
asynchronous* one — a different product with a different coordination burden and a
different promise. The research already derived the correct constraint: friend-challenge
"must not be real-time lockstep… Async turn-relay is both the cheaper architecture and
the only correct one here" because Godot 2D physics is documented non-deterministic
run-to-run (`docs/RESEARCH.md:241-254`). That is not a preference; it is a hard block on
the realtime online version.

---

## Social Depth Audit

Using the skill's 7-rung ladder. The honest reading requires one caveat up front: this
ladder assumes *mediated* social play, and hot-seat is not mediated. The system
contributes very little to the social loop because the humans are standing in the same
room and supply the relatedness themselves. Measured as a system, the depth is
near-floor; measured as an experience, the relatedness is high. Both are true and the
recommendations depend on keeping them distinct.

| Rung | Where Pen-Fight sits | Evidence |
|---|---|---|
| 1. Awareness | **Present, but degenerate** — the "other" is co-present, not mediated. There is no way to be aware of any player you cannot see. | `main.gd:179`, `turn_gate.gd` |
| 2. Comparison | **Ephemeral only** — an in-session score line on the gate; nothing durable, nothing cross-session. | `main.gd:519`, `:556-559`, `settings_store.gd:73-80` |
| 3. Indirect exchange | **Absent.** Nothing is sent, gifted, traded, or borrowed. | grep: no such construct |
| 4. Communication | **Absent in-system**; supplied entirely by the two humans talking out loud. | grep: no chat/ping/request |
| 5. Coordination | **Present as an obligation, not a plan** — the turn gate enforces "it's your turn" and the forfeit clock enforces "act." That is timing discipline, not division of labour. | `main.gd:508-531`, `turn_state.gd:239-247` |
| 6. Collective strategy | **Absent.** No shared objective exists. | `turn_state.gd:200-209` |
| 7. Community identity | **Absent, and out of scope.** No groups, roles, rituals, reputation, or group memory. | grep: no such construct |

- **Current depth:** rung 1 (system-mediated awareness) with a single rung-2 artifact —
  an ephemeral, non-persistent score readout. The strongest relatedness in the build is
  *below* the ladder's floor: physical co-presence.
- **Intended depth (per the research):** rung 2-3. A "challenge a friend remotely" mode
  is, structurally, a comparison plus an indirect exchange — you send someone a shot to
  beat, and they send back a result. The research is careful to keep it there: not
  realtime, not matchmade, not a league (`docs/RESEARCH.md:237-239`, `:246-254`).
- **Gap:** small and credible *in the abstract*, but **gated on a prerequisite that does
  not exist.** Rung 2 requires something durable to compare. Today nothing survives the
  round: the only persisted state is six settings keys (`settings_store.gd:73-80`) and
  `_round_wins` is zeroed on the match-over tap (`main.gd:556-559`). A challenge mode
  with no persisted record has nothing to challenge *against*. The persistence fix in
  `docs/design/core-loop.md:228-237` is therefore not just a loop fix — it is the
  substrate any comparison layer, online or local, needs first.

**Do not treat deeper as better here.** Every rung above 3 costs moderation, identity,
accounts, and a network layer this build does not have and the research does not
justify (`docs/RESEARCH.md:226-235` argues the revenue case is thin). Rungs 5-7 are not
merely expensive; they are wrong for a game whose entire fantasy is two people at one
table.

---

## Community and Status Audit

**Durable social structure: none, by design.** There is no onboarding into a group, no
reason to remain in one, no rituals, no group history, no discoverability, no roles, no
moderation surface. The "group" is exactly two people and it lasts one sitting. The
blunt question the rubric asks — *why would a player bother joining or maintaining this
group?* — has a clean answer: **they would not, because there is nothing to join.** For
the current scope that is correct, not broken. It becomes broken the moment a
leaderboard or club is bolted on, because those constructs assume an identity layer and
a persisted record, neither of which exists.

**The status layer (four checks).** The only status candidate is the pen skin
(`main.gd:106-123`; `settings_store.gd:27-28`, `:79-80`):

1. **Visibility — FAIL.** A skin is visible only to the person holding the phone and
   whoever is physically beside them. There is no profile, showcase, avatar, or public
   surface of any kind. A player's chosen design is, socially, invisible.
2. **Legibility — FAIL, and worse than invisible: contradictory.** Even for the one
   in-room audience, the gate and verdict prompt hardcode `red → "Amber"`,
   `blue → "Cobalt"` (`main.gd:643-650`) regardless of the skin actually rendered, while
   `PEN_SKINS` includes `graphite` and `ivory` (`main.gd:115-122`) and `set_pen_skin`
   swaps the art for that slot (`main.gd:131-144`). `red`/`blue` here are player-slot
   ids, not art ids (`pen_body.gd:19`; the nuance is spelled out in
   `docs/design/core-loop.md:159-174`). So the score line can read *"Amber wins the round
   2-1"* while the only pen in that slot is drawn as ivory. The signal is mislabelled
   for the sole audience it has.
3. **Desirability — WEAK.** Four procedurally-rendered designs
   (`game/assets/generate_pens_real.py`, cited `docs/handoff-2026-09-14.md:60`) with no
   rarity, mastery, or tenure semantics attached. Nothing here is aspirational; they are
   preference options, and `main.gd:102-105` says so outright ("the extra designs are
   preference options, not extra players").
4. **Fairness — NOT YET MEANINGFUL.** Nothing is being signalled, so nothing can be
   unfair. That is honest but empty: if a future layer tried to make skins a status
   signal, it would be signalling taste only, and nobody else could read it.

**Verdict:** this is a *private vanity system on a co-presence game*. It is not
"status fog" in the usual sense — nothing has been built to be prestigious. It is
dormant, and the cheapest way to wake it is not a network feature; it is making the skin
name match the skin (see Recommendations, Do now).

---

## Risks / Failure Modes

Named against the skill's failure patterns. Ordered by damage.

**1. Solo/co-presence fantasy violation — the bolt-on online layer.**
The rubric's "solo fantasy violation" pattern inverts here: this is not a solo game, so
the fantasy at risk is *co-presence* itself. Adding online PvP, matchmaking, or global
rank turns a game whose authenticity is "two people at one desk in the same room"
(`docs/research/01-market.md:90`) into an asynchronous solo grind against an absent
stranger — losing the one thing the research itself identifies as the category's real
edge and entering the exact crowded-low-end competition the research warns against
(`docs/research/01-market.md:88-90`). **Inference:** the shot that used to make both
players wince becomes a number you read alone. Nothing in the codebase is built for
identity or accounts, so this risk is not "later work" — it is a re-architecture.

**2. Coordination overkill — asking a phone audience to synchronize like a raid team,
and being blocked from doing it anyway.**
The realtime-lockstep version of friend-challenge demands simultaneous availability from
people who play in two-minute bursts (`settings_store.gd:21`), *and* it cannot be built:
Godot 2D physics is non-deterministic run-to-run, so replaying impulses on two devices
diverges. Send the recorded outcome/trajectory, never the impulses
(`docs/RESEARCH.md:241-261`). This is the single biggest technical trap in the social
space, and it also forecloses the AI opponent (same block, `docs/RESEARCH.md:255-259`).

**3. Status fog — prestige that cannot be seen or decoded.**
The skin system is the visible symptom: private (`main.gd:106-123`), and for its one
audience actively mislabelled by `_display_name()` (`main.gd:643-650`). Any future
prestige layer inherits this: there is no surface to display it on and no identity to
attach it to, so the system would generate "signals" that no player can read.

**4. Social wallpaper — social features with nothing durable underneath.**
The tempting least-effort additions (leaderboard, friends list, "share your win") are
all wallpaper here, because nothing survives a round: six settings keys are the entire
persisted state (`settings_store.gd:73-80`) and the score is zeroed on the match-over tap
(`main.gd:556-559`). A leaderboard over zero durable outcomes is a wall of blanks.

**5. Guild shell / empty belonging.**
Clubs, groups, or chat would be a shell with no purpose: there is no shared goal
(`turn_state.gd:200-209`), no team, and exactly two participants. The rubric's blunt
question — *why stay in this group?* — has no answer. Defer until a reason exists, and
probably never.

**6. Shallow relatedness — the failure mode that does **not** apply, and must not be
"fixed."**
Worth stating because it is the most likely misdiagnosis. Hot-seat is the *opposite* of
shallow relatedness: two people share a device, take literal turns, and watch the same
outcome. The rubric's shallow-relatedness pattern describes players "adjacent, not
meaningfully connected" — here they are maximally connected by construction. The
corrective is therefore *not* to add mediated connection; it is to make the system stop
mis-describing the connection it already hosts (Risk 3) and to give it a durable record
so sessions accumulate instead of evaporating (Risk 4).

**7. Comparison numbness — not present today, and there for the taking.**
There is no ranking to go stale (`grep`: no leaderboard). This is an opportunity, not a
defect: the research's own recommended shape — an intimate, named, two-person comparison
— is the anti-numbness choice the rubric prefers over a global wall
(`docs/research/01-market.md:126`). Kept small, it stays legible.

---

## Recommendations

### Do now (no network; strengthens the co-present fantasy)

1. **Persist one durable two-player record and surface it on the match-over gate.** This
   is `docs/design/core-loop.md:228-237` verbatim, and it is a prerequisite for every
   other social option in this document: comparison needs something that survives the
   round, and today nothing does (`settings_store.gd:73-80`, `main.gd:556-559`). Two new
   keys plus a line in `main.gd` `_update_gate` gives the game its first rung-2 artifact
   that outlives a session.
2. **Make the skin name match the skin.** Derive the gate label from
   `settings_store.pen_for(player)` (`settings_store.gd:48-49`) instead of the hardcoded
   `_display_name()` map (`main.gd:643-650`). This is the cheapest possible status fix:
   it makes the one social surface in the game stop contradicting the one status signal
   in the game, for the only audience that exists.
3. **Name the two players in the session, not the default art.** The settings sheet
   already reframed the mockup to per-player rows
   (`settings_screen.gd:21-23`, `:340-341`) but still labels them "Amber's pen" /
   "Cobalt's pen". Let the two people enter initials so the gate reads *"Sam wins the
   round 3-2"* instead of *"Amber wins the round 3-2"*. Zero network, and it converts a
   pen-slot id into a person — the first real identity the game has ever had.
4. **Protect the teachable skill and the shared watch.** No aim assistance, no trajectory
   preview, no outcome readout before resolution
   (`docs/research/05-feel-polish.md:76`, `docs/design/core-loop.md:219-222`). The corner
   flick is the thing one player teaches another in the room; a prediction line would
   delete the lesson along with the skill.

### Do later (only if the friend-challenge differentiator is greenlit)

5. **Build the async turn-relay exactly as the research constrains it** — a side-channel
   challenge that sends the *recorded outcome or trajectory*, never impulses to
   re-simulate (`docs/RESEARCH.md:241-261`), and never the primary mode. Sequence it
   after item 1: a challenge needs a scoreboard to challenge against. Keep it out of the
   ranked/session path so the seated match stays the product.
6. **Give the challenge exchange a legible target.** One named friend, one durable
   head-to-head record — an intimate two-person ledger, not a ranking
   (`docs/research/01-market.md:126`). This is rung 2-3 done properly: comparison plus
   indirect exchange, with no accounts, no matchmaking, and no moderation surface.

### Avoid

7. **Real-time online PvP / lockstep.** Architecturally blocked by non-determinism
   (`docs/RESEARCH.md:246-254`) and wrong for the audience's time model.
8. **Matchmaking, ELO, global leaderboards.** No identity, no durable record, and it
   vaporises the co-presence fantasy. The category's top competitor already owns this
   ground (`docs/research/01-market.md:34`), and the research warns that generic entries
   "would need to out-market, not out-build" (`docs/research/01-market.md:88`).
9. **Clubs, guilds, chat, in-game social feeds.** Guild-shell risk with no shared goal to
   justify them (`turn_state.gd:200-209`); a chat channel for two people in the same room
   is a solution to a problem the room already solves.
10. **An AI opponent as a social substitute.** Same architectural block as real-time
    online (`docs/RESEARCH.md:255-259`), and it is not a social feature — it fills the
    seat the second human occupies, which is the opposite of extending the fantasy.

---

## Action Table

| Issue | Why it hurts | Player it hurts most | Suggested change | Expected effect |
|---|---|---|---|---|
| No outcome survives a round; `_round_wins` zeroed on the match-over tap (`main.gd:556-559`), only six settings keys persist (`settings_store.gd:73-80`) | Competition is the only load-bearing motivation and it evaporates between sessions; no comparison layer of any kind can be built on it | The returning pair who want a standing score; the solo player with nobody to hand the phone to (`docs/design/core-loop.md:101-104`) | Persist a match/series record and surface it on the match-over gate (item 1) | The game gains its first durable, legible comparison artifact; unblocks every later social option |
| Gate names Amber/Cobalt regardless of the rendered skin (`main.gd:643-650` vs `PEN_SKINS` `:106-123`) | The one status signal in the game is mislabelled for its only audience; the player's choice is actively contradicted | The player who customised their pen and now reads someone else's name on their win | Derive the label from `settings_store.pen_for(player)` (item 2) | The chosen pen is named correctly; the taste signal becomes readable at zero cost |
| Players are pen-slot ids `"red"`/`"blue"` (`pen_body.gd:19`, `main.gd:124`), never people | There is no identity to attach a record, a remake, or any future social feature to | The pair who want "our series" rather than "Amber vs Cobalt" | Let players set initials; render the score line with them (item 3) | First real identity in the build; a hook any later comparison layer needs |
| Research proposes "challenge a friend remotely" (`RESEARCH.md:237-239`) on top of a build with no durable state | A challenge with no scoreboard has nothing to challenge against; building it first means building it twice | The player the research's differentiator is meant to attract | Sequence it after the persistence fix (item 5); async relay only, trajectory not impulses | Differentiator lands on a foundation instead of a void; stays cheap and correct |
| Temptation to add realtime online PvP / matchmaking (`RESEARCH.md:222` notes no competitor has it) | Blocked by physics non-determinism (`RESEARCH.md:246-254`); demands simultaneous availability from a burst-play audience; destroys the co-presence fantasy | The whole audience; worst for the in-room pair the game was built for | Avoid entirely; if online is ever built, it is async relay, never lockstep (items 5-6) | Protection of the one authentic edge; avoidance of a re-architecture that cannot ship |
| Temptation to add clubs/chat/leaderboards | Guild-shell and wallpaper risk: no shared goal, two participants, no durable outcomes, no accounts | The player who joins hoping for community and finds a blank wall | Defer; revisit only if a durable record and a real group goal ever exist (items 7-9) | Prevents dead UI and moderation burden on a game with nothing for a group to do |
| Ceremony/tap cost compounds across a match (`05-feel-polish.md:317`; gate at `main.gd:508-531`) | Social goodwill is spent on waiting between the beats the two players came for | Both players, worst at round 15 of a 20-round sitting | Keep the gate; do not lengthen the ceremony; keep best-of-1/3 the default bands | More time in shared suspense, less time staring at a dimmed screen |

---

## Assumptions and evidence limits

- **No human has played this build.** The 20-round hot-seat playtest is blocked on the
  user (`docs/handoff-2026-09-14.md:186`). Every statement about how a social beat
  *feels* is marked **inference**; everything else is read off the shipped code, the
  tests, and the design/research docs.
- **The research's own evidence is weak by its own admission.** The session could not open
  a single web page, so all market and review data is search-snippet-sourced and
  unverified (`docs/RESEARCH.md:27-47`); the "friend battle" complaint is a paraphrased
  *theme*, not a quoted review (`docs/research/01-market.md:53-56`). The differentiator's
  provenance is therefore suggestive, not firm — do not over-invest on its strength.
- **The friend-challenge scope is unresolved.** `docs/RESEARCH.md:294-295` open question 2
  ("Hot-seat only, or is friend-challenge in scope?") is unanswered and explicitly gates
  Phase 2. This audit does not resolve it; it constrains it.
- **Behaviour facts vs labelling facts.** The status findings mix both and are separated
  deliberately: the skin/name mismatch is a *labelling* defect (the pen in the slot is the
  right player's pen; only the name is wrong — see `docs/design/core-loop.md:159-174`),
  whereas the absence of persistence and networking are *behaviour* facts proven by
  `settings_store.gd:73-80` and by the greps recorded under Audit Target.
- **Absence claims are grep-backed, not assumption-backed.** Every "there is no X"
  statement above rests on
  `grep -rniE "ENetMultiplayer|MultiplayerAPI|MultiplayerPeer|WebSocket|HTTPRequest|HTTPClient|PacketPeer|RPC|matchmak|chat|guild|club|leaderboard|friend"`
  over `game/` (excluding `game/android/build/`, generated build output) returning nothing,
  plus the same search over `game/project.godot`.
- **`docs/ART_AND_FEEL_SPEC.md` is three phases stale** (360 px pens / 1120×600 table vs
  the shipped 180 px / 1180×640 — `docs/handoff-2026-09-14.md:74`), so no geometry claim
  here is taken from it. `CONTEXT.md` and `docs/adr/` do not exist in this repo.
- **Not verified by me, and not load-bearing:** competitor install/rating figures
  (`docs/research/01-market.md:11-38`) and the market ARPDAU band
  (`docs/research/01-market.md:111`) are quoted only to show what the research asserts,
  not as established fact.
