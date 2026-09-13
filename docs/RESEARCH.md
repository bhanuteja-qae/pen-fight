# Pen Fight — Research Synthesis

Compiled 2026-09-12. Six parallel research passes covering market, Android failure modes, graphics,
physics/frame rate, game feel, and build workflow. Detailed findings live in
[`docs/research/`](research/); this document is the synthesis — what the findings *change*, where they
conflict, and what still needs a human decision.

---

## How to read this

| Appendix | Scope |
|---|---|
| [`01-market.md`](research/01-market.md) | Existing pen-fight titles, adjacent flick games, review themes, monetization benchmarks |
| [`02-android-problems.md`](research/02-android-problems.md) | Play policy gates, Godot export errors, on-device runtime bugs, perf traps, pre-build checklist |
| [`03-graphics.md`](research/03-graphics.md) | 2D vs 3D, asset loading, art sourcing and licenses, texture/import settings, scaling, render budget |
| [`04-physics-fps.md`](research/04-physics-fps.md) | Tick rate, interpolation, frame pacing, determinism, damping tuning, settle detection, OOB geometry, input latency |
| [`05-feel-polish.md`](research/05-feel-polish.md) | Aim interaction, impact feedback, haptics, audio, hot-seat turn readability, ceremony timing, the 20-round protocol |
| [`06-workflows.md`](research/06-workflows.md) | Headless export, GitHub Actions + GitLab CI, signing, Play tracks, crash reporting, Billing/AdMob maturity, test split |

Each appendix labels its own claims. Appendix 4 uses `[FACT]`/`[JUDGEMENT]`; appendix 5 uses
`[EST]`/`[REC]`; appendices 2 and 6 mark unverified claims inline. Trust those labels over this
summary, and trust the primary source over both.

---

## 0. Verification limitation — read before relying on any number here

**The research environment could not open a single web page.** Session egress policy denied `CONNECT`
to every external host with a gateway 403. Reproduced directly:

```
curl https://play.google.com/...        -> 000  (gateway 403 to CONNECT)
curl https://docs.godotengine.org/...   -> 000  (gateway 403 to CONNECT)
curl https://www.reddit.com/r/godot/    -> 000  (gateway 403 to CONNECT)
```

The proxy's own `recentRelayFailures` confirms `kind=connect_rejected`, policy denial, for all three.

So `WebFetch` was unusable for all six agents. Everything below rests on `WebSearch` — which runs
server-side and returns *search-result summaries*, not page content. **No primary source was read by
anyone.** Godot setting names, default values, Play policy dates, and plugin maintenance status are
all snippet-sourced.

This matters unevenly. Engine defaults that appear in dozens of indexed tutorials are probably right.
Policy deadlines and "is this plugin still maintained" are exactly the kind of fact that goes stale
and that snippets get wrong. §7 lists the specific pages a human needs to open.

---

## 1. Repo state — the actual blocker

Verified directly, not researched:

```
$ git log --all --oneline
d191456 Initial commit

$ git ls-tree -r --name-only d191456
README.md
```

**The repository contains one file: a one-line `README.md`.** There is no `project.godot`, no `.gd`
file, no scene, no export preset — on `main` or on `claude/pen-physics-game-plan-fd3o45`, in any
commit.

The Phase 0 skeleton that "compiles clean with zero errors" exists only in a working copy on some
machine. That is the highest-priority item in this document, ahead of every research finding:

- Phases 1–3 have nothing to modify.
- Phase 4's CI cannot build a project the repo does not contain.
- The work is one lost laptop away from gone.

**Insert a Phase 0.5 before anything else: commit and push the skeleton.** Include `project.godot`,
scenes, scripts, and a `.gitignore` covering `.godot/`, `android/build/`, `*.keystore`, and
`export_presets.cfg` (see §3.3 — that file holds plaintext keystore passwords).

---

## 2. Executive summary — the eight things that change the plan

1. **Nothing is committed.** Phase 0 is not done in any sense the repo can see. (§1)
2. **The Godot version is now a hard gate that must be decided before Phase 1, not at Phase 4.**
   Godot 4.3 and 4.4 emit `.so` files that are not 16 KB-page aligned, and Play has blocked upload of
   such AABs since 2025-11-01. The fix landed in 4.5. But 4.5.2–4.6.2 carry a stretch-mode regression
   that pushes UI off-screen on Android. And Sentry's Godot SDK requires ≥4.5. The intersection points
   at **pinning current 4.7.x**. One decision, four phases affected. (§3.1)
3. **The physics work in Phase 1 is smaller than expected and better specified.** Keep the tick rate at
   the default 60 Hz; turn *on* `physics/common/physics_interpolation` instead (this is the correct answer
   to 90/120 Hz Android panels, and Godot's own Android refresh-rate handling is unreliable). Reach for
   `continuous_cd` only if tunnelling actually appears. (§3.2)
4. **The stalemate rule and the settle detector are the same mechanism.** A hybrid velocity-threshold
   detector with a ~0.25 s quiet debounce and a 4–6 s hard timeout gives you turn-end detection *and*
   the forfeit rule from one piece of code. Neither sleep signals alone nor a velocity threshold alone
   is robust. (§3.2)
5. **Stay in 2D.** A pen is a tempting 3D object, but real 3D would force rewriting the physics and
   input layers for tumble realism a turn-based flick game barely registers. Pre-rendered sprite sheets
   baked from a 3D model are a later content-only upgrade on the same 2D physics. (§3.4)
6. **Play's calendar is the critical path, not the CI pipeline.** The 12-tester / 14-day closed-testing
   requirement for personal developer accounts is waiting time you cannot compress. Start Play Console
   registration and tester recruitment during Phase 1–2, in parallel with development. Phase 4 as written
   serialises this and adds weeks. Also: `applicationId` is immutable after first publish — pick it now. (§3.3)
7. **Make the turn/score state machine pure GDScript with no scene-tree or physics dependency, in Phase 2.**
   That single structural choice is what makes any automated testing possible at all; physics and feel stay
   playtest-only regardless. Retrofitting it later is the expensive path. (§3.5)
8. **The monetization case is weak enough to question Phase 5's existence.** (§4)

---

## 3. Cross-cutting decisions

### 3.1 Engine version — decide first, it constrains everything

| Constraint | Source | Implication |
|---|---|---|
| 16 KB page alignment required for Play upload since 2025-11-01 | Appendix 2 §1 | Rules out 4.3, 4.4 |
| Alignment fix landed in Godot 4.5 (NDK bump) | Appendix 2 §1 | Floor is 4.5 |
| Stretch-mode/safe-area regression in 4.5.2–4.6.2 pushes content off-screen on Android | Appendix 2 §3 | Avoid that band |
| Sentry Godot SDK requires ≥4.5-stable | Appendix 6 §8 | Consistent with floor |
| Play requires target API 36 for new apps from 2026-08-31 | Appendix 2 §1 | Needs a recent build template |

**→ Pin current stable 4.7.x.** Pin it identically on every dev machine and in CI; export templates must
match the editor version *exactly*, including the `.stable` suffix, or the export fails cryptically.

Re-verify the stretch-mode regression against whatever version you pin, on a notched device. It was live
across three minor releases, which is a bad sign for assuming it is fixed.

### 3.2 Physics — what Phase 1 should actually do

The original Phase 1 listed four items. The research refines them and adds two:

| Phase 1 item | What the research says |
|---|---|
| Fix out-of-bounds to test capsule extents | Use an `Area2D` over the table for a cheap `body_shape_exited` trigger, *then* run precise capsule-extent-vs-`Rect2` geometry near the edge. Geometric ("any part off") matches the real schoolyard rule better than a centre-of-mass rule. (Appendix 4 §7) |
| Add stalemate handling | Falls out of the settle detector for free — see item 4 in §2. (Appendix 4 §6) |
| Tune `LINEAR_DAMP`, `ANGULAR_DAMP`, `MAX_IMPULSE` on a real device | Tune in that order: damping first, `MAX_IMPULSE` last against a fixed damping curve. Note the project default damp of 0.1/1.0 *combines additively* with per-body values unless `damp_mode` is `Replace`. Fake table friction with damping, not a friction surface. (Appendix 4 §5) |
| Slow-motion debug toggle | `Engine.time_scale` (0.2–0.3), never `physics_ticks_per_second` — lowering the tick rate changes *what happens*, not just how fast you watch it. (Appendix 4 §9) |
| **Add:** enable `physics/common/physics_interpolation` | Correct fix for 90/120 Hz panels. Requires auditing every transform write into `_physics_process` and calling `reset_physics_interpolation()` after any teleport. Do this while the codebase is still small. (Appendix 4 §2) |
| **Add:** build the debug overlay with `contact_monitor` | Set `contact_monitor = true` *and* `max_contacts_reported` to non-zero — the default of 0 records no contacts even with the monitor on. Gate the whole overlay behind `OS.is_debug_build()`. (Appendix 4 §9) |

**One design constraint that emerged from combining appendices 4 and 5:** hit-stop and slow-motion
perturb the simulation slightly (and `time_scale = 0` is reported to produce spurious duplicate
collisions on resume — use ~0.02, not 0). So **resolve the win condition before the ceremony plays**,
never during it. Decide the outcome geometrically, then run the slow-mo, shake and camera follow as
pure presentation over an already-settled result. Otherwise the knockout ceremony can change who won.

### 3.3 Release path — start it early, in parallel

Two items are immutable or slow, and both are scheduled too late in the original plan:

- **`applicationId`** cannot change after first publish. A malformed one (underscores, capitals, a
  segment starting with a digit) exports with *no error* and fails only at install with "cannot parse
  package". Pick `com.<something>.penfight` now and put it in the repo.
- **The 12-tester / 14-day closed-testing requirement** for personal developer accounts is calendar
  time. It gates production access, not the build. Recruiting 12 real testers is a social task with a
  two-week clock attached — begin it during Phase 1–2.

Secrets hygiene, since it interacts with §1's `.gitignore`: `export_presets.cfg` stores keystore path and
passwords **in plaintext**. Never commit it. Inject via `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` / `_USER` /
`_PASSWORD`, keystore itself as a base64 CI secret. And the headless export has a known bug where the first
run fails because the `.godot` cache is empty — run `--headless --editor --quit --import` **twice** before
exporting, and don't trust the exit code alone. (Appendix 6 §1)

### 3.4 Graphics — 2D, and fake the expensive parts

Stay in pure 2D with capsule colliders. Beyond that, the cheap-polish list is more valuable than the
art-sourcing list, because it is what makes a placeholder-free screen affordable:

- Skip real-time `Light2D` shadows — measurable FPS cost on Android, as few as ~5 dynamic lights hurts.
  Fake shadows with an offset sprite.
- `CanvasModulate` for mood, a cheap vignette, a tiling table texture, a small gloss shader on the pen
  barrel. Near-zero cost, reads as deliberate.
- Enable ETC2/ASTC VRAM compression **before** importing final art; if you toggle it afterwards, delete
  `.godot/` to force reimport (the editor's "Fix Import" is buggy here).
- One shared atlas, textures capped 1024×1024, mipmaps off, linear filtering.
- `canvas_items` stretch mode + `expand` aspect, with UI in its own safe-area `CanvasLayer` separate from
  the scaled playfield. Cross-check against the 4.5.2–4.6.2 regression in §3.1.

Licensing traps worth naming: **CC-BY-NC and "free for personal use" assets cannot ship in a Play Store
game.** Kenney.nl (CC0) is the safest single source.

For loading: `preload()` only small constants; warm everything a match needs via
`ResourceLoader.load_threaded_request()` from a splash screen; pool anything spawned repeatedly so no
`instantiate()` happens mid-turn.

### 3.5 Feel — the ranked list

Appendix 5's ordering is by effect-per-hour, and the top item is not an effect at all:

1. **Hard turn-transition gate** — full-screen tap-to-continue with input locked during handoff. Fixes the
   single most common hot-seat failure (a player flicking on the wrong turn). Nearly free, since you need a
   "settled" state anyway for §3.2.
2. **Trauma-based screen shake** on impact — `trauma²` decay, `Camera2D.offset`. ~1–2 hours for the cheapest
   possible "the world reacted" signal.
3. **Hit-stop**, 2–6 frames, `time_scale ≈ 0.02` not 0, with the §3.2 constraint about not running during
   win evaluation.
4. **Layered impact sound** — transient + thud + slide loop, ±5–10% pitch randomisation, volume and pitch
   mapped to collision impulse. Biggest audio return.
5. Set up **Master/SFX/Music buses on day one** so the settings toggle is one `AudioServer` call. Cheap now,
   annoying to retrofit.
6. **Slingshot drag-back aim with a plain direction vector and power bar — and no trajectory prediction.**
   This game's skill ceiling depends on *not* solving the aim for the player. 8 Ball Pool's guideline fits
   pool's harder mental geometry, not a straight-line flick. The cancel gesture (release near the pen) falls
   out of the slingshot model for free.
7. **Make the knockout ceremony skippable after the first few rounds** — 150–200 ms hit-stop plus a slow-mo
   camera follow is great at round 3 and friction by round 15 of the 20-round test.

On haptics, be sceptical: `Input.vibrate_handheld()`'s amplitude support is marked `[EST]` in appendix 5,
the vibrate permission must be enabled in the export preset or the call may crash, and the OS-level haptics
setting cannot be queried — so ship an in-game toggle. Verify this one on hardware before designing around it.

---

## 4. The uncomfortable finding: the business case is weak

This is the part worth arguing about, so here is the evidence rather than the conclusion first.

**The niche is crowded at the bottom.** At least 8–10 Play apps, 2 recent iOS entrants, 5+ browser clones, and
a CodeCanyon white-label template all implement this exact mechanic. New entrants launched within the last year.
The best-documented live competitor sits at roughly 68K installs and 3.3★.

**It is genuinely underserved at the top.** No competitor shows real online PvP matchmaking, live-ops cadence,
or production polish. Two now-delisted pen-fight apps reached 100K and 1M+ installs, so the category ceiling has
been six to seven figures even for unpolished work.

**But the revenue math is thin.** Realistic planning band is ARPDAU **$0.01–$0.05** (casual, ads-only), with
India-weighted interstitial eCPM likely **under $1**, against headline averages of $4.80+. All demand signals
found are India-centric.

So: Phase 5 exists to add Play Billing, a remove-ads SKU, interstitials, and later skins. Against a plausible
ceiling in the tens of thousands of installs at ARPDAU $0.01–0.05, that work is unlikely to repay its own
engineering time, let alone the ongoing cost of an ads SDK's Data Safety compliance. **I would cut Phase 5 to
just the remove-ads IAP, or defer monetization entirely until the 20-round gate and a soft launch produce real
retention numbers.** Skins in particular were already deferred in the original plan for lack of an art pipeline;
the revenue data says they would not pay for one.

The one evidence-backed differentiator is a **"challenge a friend remotely"** mode — it directly answers the
only concrete user complaint found in the review data (players asking for friend-battle options) and no
competitor appears to have it. That is a larger job than skins and a better one.

### 4.1 A new constraint on that differentiator

Combining appendix 1's recommendation with appendix 4's determinism finding produces a conclusion neither
pass reached alone:

**Godot 2D physics is documented as non-deterministic — not just across devices, but run-to-run on the same
machine.** Jolt is 3D-only. Rapier2D and Box2D ports claim determinism but it is unverified or disabled in
their Godot integrations.

Two consequences:

- **Friend-challenge must not be real-time lockstep.** Replaying inputs on two devices will diverge. Send the
  outcome or the recorded trajectory, not the impulse for each side to re-simulate. Async turn-relay is both the
  cheaper architecture and the only correct one here.
- **It strengthens the original pushback on an AI opponent.** The earlier plan called impulse search "a much
  larger job than it sounds." It is worse than that: impulse search depends on the simulation being reproducible,
  and on stock GodotPhysics2D it is not. A searched impulse need not produce the same result when actually
  played. That is an architectural block, not a scope problem — it would require swapping the physics backend,
  not just writing more code.

Replays have the same constraint: record trajectories, never re-simulate from inputs.

---

## 5. Revised phase ordering

Changes from the original plan are marked.

| Phase | Content | Change |
|---|---|---|
| **0.5** | Commit and push the skeleton. `.gitignore` for `.godot/`, `android/build/`, `*.keystore`, `export_presets.cfg`. | **NEW — blocking** |
| **0.75** | Pin Godot 4.7.x everywhere. Decide `applicationId`. Set export format AAB + custom build, arm64-v8a + armeabi-v7a. Enable ETC2/ASTC. Install JDK 17 + matching SDK/NDK. | **NEW** — was implicit in Phase 4, but §3.1 and §3.3 make it a prerequisite |
| **1** | Core feel, per §3.2 — plus physics interpolation and the contact-monitor overlay. Gate: 20 rounds, want a 21st. | Refined |
| **1.5** | Start Play Console registration + recruit 12 testers. Runs in parallel; it is calendar time. | **NEW — moved earlier from Phase 4** |
| **2** | Match structure — with the turn/score state machine as pure GDScript, no scene tree, unit-tested under GUT or GdUnit4. | Refined (§2 item 7) |
| **3** | Presentation, per §3.4 and §3.5. Nothing left as `draw_rect`. | Unchanged in intent |
| **4** | CI: GitHub Actions on `barichello/godot-ci`, double `--import`, tag-driven versionCode, signed AAB. Sentry for crashes. | Refined; tester recruitment already done |
| **5** | Monetization — **scope cut, see §4.** | **Reduced / questioned** |
| **6** | Soft launch, staged rollout, watch ANR and D1. | Unchanged |

Two items from the original plan survive unchanged and are worth restating because the research reinforced both:
the 20-round gate in Phase 1 is the right gate, and the AI opponent is correctly deferred — now for a stronger
reason (§4.1).

---

## 6. Open questions needing your decision

These are not research gaps; they are calls only you can make.

1. **Is this project a business or a craft exercise?** §4 says the revenue ceiling is low. If it is a craft
   exercise, cut Phases 4–6 to "ship it once" and spend the time on feel. If it is a business, the
   friend-challenge mode is the only lever the evidence supports, and that changes the architecture in Phase 2.
2. **Hot-seat only, or is friend-challenge in scope?** Decide before Phase 2 — it determines whether the state
   machine needs to be serialisable over a wire, and §4.1 constrains how.
3. **Orientation.** Landscape suits a table; portrait suits one-handed play. This affects every layout decision
   in Phase 3, and appendix 2 notes Godot has historically ignored this setting on some versions, so it needs
   device verification either way.
4. **Target minimum device.** "Tune against a real device" needs a specific device. India-weighted traffic
   implies a low-end floor, which constrains §3.4's budget.
5. **Godot version.** §3.1 recommends 4.7.x. Confirm it, since re-pinning later invalidates the CI setup.

---

## 7. Verification ledger

Because of §0, these load-bearing claims were never read from a primary source. Open these pages before
relying on them:

| Claim | Page to check |
|---|---|
| 16 KB page alignment deadline + which Godot version fixed it | `android-developers.googleblog.com` 16 KB post; Godot PR #106358 |
| Target API 36 deadline and extension date | Play Console Help — target API level requirements |
| 12-tester / 14-day closed testing scope (does it apply to *your* account type?) | Play Console Help — testing requirements |
| `physics_interpolation` 2D version support and default | Godot docs — Physics interpolation |
| Every setting name and default in appendix 4's tables | Godot docs — Project Settings |
| `Input.vibrate_handheld()` amplitude support and permission requirement | Godot docs — `Input`; Android export preset |
| `SceneTreeTimer` / `create_timer()` `ignore_time_scale` argument signature | Godot docs — `SceneTree` |
| Plugin maintenance status: Billing, Sentry, AdMob, `r0adkll/upload-google-play` | Each repo's releases page |
| Android vitals ANR/crash thresholds where Play penalises the listing | Play Console Help — Android vitals |
| Competitor install counts and ratings | The Play Store listings themselves |

The market data in appendix 1 is the weakest section overall — review themes could not be read at all.
Installing three competitors by hand would improve it more than any further desk research.
