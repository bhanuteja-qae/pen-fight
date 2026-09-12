# Physics & Frame Rate Research — Pen Fight (Godot 4.x)

Legend: **[FACT]** = verified against Godot source/docs, cited. **[JUDGEMENT]** = my analysis/recommendation for this project, not an engine guarantee.

---

## 1. Physics tick rate

### Documented defaults

| Setting | Type | Default | Source |
|---|---|---|---|
| `physics/common/physics_ticks_per_second` | int, range 1–1000 | **60** | [main.cpp GLOBAL_DEF_BASIC](https://github.com/godotengine/godot/blob/master/main/main.cpp) |
| `physics/common/max_physics_steps_per_frame` | int, range 1–100 | **8** | main.cpp GLOBAL_DEF_BASIC |
| `physics/common/physics_jitter_fix` | float, range 0–2 | **0.5** | main.cpp GLOBAL_DEF |
| `Engine.physics_ticks_per_second` | int property | 60 (mirrors project setting) | [Engine docs](https://docs.godotengine.org/en/stable/classes/class_engine.html) |
| `Engine.max_physics_steps_per_frame` | int property | 8 | Engine docs |

**[FACT]** `physics_ticks_per_second` controls how often the physics world steps *and* how often every node's `_physics_process()` runs — it is a fixed timestep, decoupled from render FPS. **[FACT]** `max_physics_steps_per_frame` caps how many physics steps Godot will run to "catch up" within a single rendered frame when the frame took longer than one physics tick's worth of time. ([Godot forum clarification](https://forum.godotengine.org/t/docs-clarification-regarding-max-physics-steps-by-frame/46990); [PR #65836 implementing the cap](https://github.com/godotengine/godot/pull/65836))

### The "physics death spiral"

**[JUDGEMENT + mechanism, documented behavior]** If a rendered frame takes longer than `1/physics_ticks_per_second` seconds, Godot must run more than one physics step to keep simulation time caught up with wall-clock time. If the *cause* of the slow frame was physics itself (too many bodies, too many contacts), running extra steps makes the next frame slower still — a positive feedback loop. `max_physics_steps_per_frame` (default 8) is the safety valve: once that many steps have run in one frame, Godot gives up catching up and the game **visibly slows down in simulated time** (a deliberate degrade-gracefully behavior) rather than spiraling to a hang. Raising `physics_ticks_per_second` without raising `max_physics_steps_per_frame` proportionally makes the spiral trigger sooner, because each real millisecond of lag now corresponds to more missed steps.

For Pen Fight this is a low risk: the scene has at most 2 dynamic bodies and a static table — nowhere near the body count that causes this spiral in practice. It matters mainly if you add debug-draw, particle effects, or run on a very slow/thermal-throttled Android device during a frame spike (e.g. GC pause, texture upload).

### Recommended tick rate for a 2D flick-collision game

**[JUDGEMENT]** Use **60 Hz** (the default). Reasoning:

- The gameplay involves two capsules colliding and sliding, not high-velocity projectiles or thin-wall tunneling scenarios — 60 Hz is standard for this class of game (top-down sports/board games).
- Godot does not interpolate the render of physics steps below the render frame rate *unless* physics interpolation is turned on (see §2). Without interpolation, running physics visibly slower than render FPS (e.g. 30) looks stuttery; running it faster than needed wastes CPU/battery for no visual gain unless interpolation is enabled.
- Mobile thermal/battery budget matters more than sub-frame collision precision here (see §3).

### Actual cost of 60 → 120 → 240

**[FACT]** CPU cost scales with tick rate: "CPU usage scales with the physics tick rate" (Engine docs, `physics_ticks_per_second`). Doubling the tick rate roughly doubles the CPU time spent in the physics step (broadphase, narrowphase, solver iterations, `_physics_process` callback execution) — **[JUDGEMENT]**: for a two-body 2D scene, this is small in absolute terms (physics step for 2 capsules is nowhere near the ~1-8ms budget of a 16.6ms/8.3ms frame), so 120 Hz would probably still hit target FPS on any target Android device. But it does directly increase power draw and heat, which for a mobile device matters for a game people play for many short turns in a row.

- **60 → 120**: ~2x physics-only CPU/battery cost, no meaningful gameplay benefit for this design (see next point).
- **120 → 240**: same again, further diminishing returns, and even less headroom for other frame work on lower-end Android SoCs.
- Also relevant: `physics/2d/solver/solver_iterations` defaults to **16** ([`physics_server_2d.cpp` GLOBAL_DEF](https://github.com/godotengine/godot/blob/master/servers/physics_2d/physics_server_2d.cpp)) — this affects constraint solver accuracy per step, independent of tick rate, and is a cheaper knob to raise than tick rate if contact resolution feels mushy.

### When low tick rate causes tunnelling / mushy collisions vs. when CCD is the fix

**[FACT]** `RigidBody2D.continuous_cd` (exposed as `continuous_cd` in the inspector) is an `int` enum `RigidBody2D.CCDMode`, default `CCD_MODE_DISABLED` (0), with `CCD_MODE_CAST_RAY` (1, faster/less precise) and `CCD_MODE_CAST_SHAPE` (2, precise, more expensive) options ([RigidBody2D.xml](https://github.com/godotengine/godot/blob/master/doc/classes/RigidBody2D.xml)). It works by predicting the swept path of a fast body for that step, instead of moving it then checking overlap after the fact.

**[JUDGEMENT]**
- Tunnelling happens when a body's per-tick displacement exceeds the thinnest dimension of the shape it should have collided with. At 60 Hz, a pen flicked at a very high impulse could, in theory, cross a thin wall/edge collider in one tick if velocity is high enough (`v * (1/60) > wall_thickness`). Given a table with real physical wall/edge colliders (not just a point/bounds test), this is the scenario to guard against, not pen-vs-pen collision (which is thick, so tunnelling through the *other pen* is much less likely at flick speeds).
- "Mushy" collision feel (interpenetration before push-out, soft-feeling impacts) is a solver/stiffness issue, not a tick-rate-alone issue — raising `solver_iterations` or the tick rate both help, but tick rate is the expensive fix; try solver iterations and contact bias tuning first.
- Correct order of operations: profile whether tunnelling/mushiness is actually observed at 60 Hz before spending the CPU/battery budget on a higher tick rate. If tunnelling only affects the walls (not pen-vs-pen), enabling `continuous_cd = CCD_MODE_CAST_SHAPE` on the pens is far cheaper than doubling the global tick rate, because CCD only costs extra work for the specific fast body, not for every physics step of everything in the scene.

---

## 2. Physics interpolation

### Version support

**[FACT]**
- **2D** physics interpolation shipped in **Godot 4.3** (announced in the 4.3 release notes; setting present since 4.3 Beta 1). Sources: [Godot 4.3 release coverage](https://gameworldobserver.com/2024/08/19/godot-4-3-release-2d-physics-interpolation-direct3d-12), [godot-proposals #2753](https://github.com/godotengine/godot-proposals/issues/2753) ("Add physics step interpolation in 3D (implemented in 2D since 4.3)").
- **3D** physics interpolation shipped in **Godot 4.4** (godot-proposals #2753 tracked 3D as not-yet-implemented as of 4.3; [Godot 4.4 release notes](https://godotengine.org/releases/4.4/) list it as a 4.4 feature).
- The setting is `physics/common/physics_interpolation` (bool), found at **Project Settings > Physics > Common > Physics Interpolation**. **Default: `false` (off)** — confirmed indirectly by [godot-proposals #12950](https://github.com/godotengine/godot-proposals/issues/12950), a still-open proposal to turn it **on by default for new projects**, which would be moot if it already defaulted to on.
- Per-node override: `Node.physics_interpolation_mode`, type `int` enum `Node.PhysicsInterpolationMode`, **default `PHYSICS_INTERPOLATION_MODE_INHERIT` (0)** — "Inherits `physics_interpolation_mode` from the node's parent. This is the default for any newly created node." ([Node.xml](https://github.com/godotengine/godot/blob/master/doc/classes/Node.xml)) Only takes effect if the project-level or `SceneTree.physics_interpolation` flag is also true.

### Interaction with `_physics_process` vs `_process`

**[FACT]** From the official interpolation docs: "Physics interpolation is optional, and disabled by default." The core rule once enabled: **all movement/transform changes on interpolated objects must happen inside `_physics_process()`, never in `_process()`.** Godot stores each interpolated node's previous-tick and current-tick transform and blends between them for however many render frames occur between two physics ticks; if you write a transform in `_process()`, you insert a value between the tracked previous/current states and get visible jitter — "This jitter may not be visible on your machine, but it will occur for some players." (Quick start guide, [raw source](https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/physics/interpolation/using_physics_interpolation.rst))

This extends beyond direct RigidBody motion: tweens, `NavigationAgent2D` movement, and any parent node repositioning must also happen on the physics tick if their children are interpolated, because children inherit the parent's interpolated transform history.

### What breaks

**[FACT]**
- **Teleports** (instant repositioning — e.g., resetting a pen after a foul, or snapping the camera): call `Node.reset_physics_interpolation()` immediately after the teleport. This resets the node's internal "previous transform" to match the new "current transform," preventing Godot from smoothly (and wrongly) sliding the object from its old position to the new one over the next tick.
- **Reparenting**: `Node.xml` documents explicitly: "If `ProjectSettings.physics/common/physics_interpolation` is enabled and reparenting causes a large change in global transform, the object may appear to move from its old position to its new one over the next physics tick. To avoid this, call `reset_physics_interpolation()` after reparenting."
- **Manual transform sets outside the physics tick** (e.g. setting `global_position` from an `_input()` handler or a `Timer` callback that isn't tied to physics) — same jitter mechanism as above.
- Recommended dev practice from the docs: temporarily set `physics_ticks_per_second` very low (e.g. 10) during development to make interpolation bugs (things set outside `_physics_process`) obviously visible, then restore to 60.

### Should Pen Fight turn it on?

**[JUDGEMENT]** Yes, with caveats, and it directly answers the stated motivation (60/90/120 Hz Android panels):

- Without interpolation, a 60 Hz physics step rendered on a 90/120 Hz display either (a) duplicates the same physics-derived transform across 1.5–2 extra render frames (visible stutter/judder during the fast slide-and-collide moment, which is exactly the visually important part of this game), or (b) if you raised the physics tick rate to match the panel to avoid stutter, you pay the CPU/battery cost in §1 and still don't cover every panel refresh rate variant.
- With `physics/common/physics_interpolation = true` and physics stays at 60 Hz, Godot renders a smoothly interpolated position at 90/120 Hz render rate for free, at the CPU cost of interpolation math (cheap) rather than doubling/tripling the physics simulation cost.
- Caveats specific to this project's plan: because the project already does turn-based, mostly-static gameplay, verify these spots don't move things outside `_physics_process`:
  - The turn setup that repositions a pen (if any "reset to start position" logic exists) must call `reset_physics_interpolation()`.
  - Camera nodes or aim-indicator nodes that follow the pen and are updated in `_process`/`_input` should either not be marked interpolated, or should be updated in `_physics_process`.
  - The stalemate/out-of-bounds check and any UI overlay reading `global_position` for display should read the *interpolated* visual transform only for rendering, and should keep using the raw physics-space transform for gameplay logic (win/OOB tests) — interpolation is a rendering-only smoothing layer, it doesn't change simulation truth.
- Bottom line: enable `physics/common/physics_interpolation`, audit every direct `Node2D.position/rotation/transform` write in the codebase to make sure it's either in `_physics_process` or followed by `reset_physics_interpolation()`, and keep `physics_ticks_per_second` at 60.

---

## 3. Frame pacing on Android

### VSync

**[FACT]** `display/window/vsync/vsync_mode` is an `int` enum, `DisplayServer.VSyncMode`:

| Value | Name | Behavior |
|---|---|---|
| 0 | `VSYNC_DISABLED` | Uncapped, tearing possible |
| 1 | `VSYNC_ENABLED` (default) | Locked to display refresh, no tearing |
| 2 | `VSYNC_ADAPTIVE` | Disables sync below refresh rate (reduces stutter, may tear), enables above |
| 3 | `VSYNC_MAILBOX` | Always shows most recent frame at vblank |

Source: [DisplayServer VSyncMode reference](https://godot-rust.github.io/docs/gdext/master/godot/classes/display_server/struct.VSyncMode.html); adaptive/mailbox fall back to `VSYNC_ENABLED` on macOS/some GPUs. Default confirmed as `VSYNC_ENABLED` in `main.cpp` (`DisplayServerEnums::VSYNC_ENABLED` initializer).

**[FACT]** `Engine.max_fps` — int, **default 0** ("uncapped"). Docs: "The maximum number of frames that can be rendered every second (FPS). A value of 0 means the framerate is uncapped." Also: capping FPS reduces power consumption (explicitly called out in the Engine docs).

**[JUDGEMENT, from community reports, treat as unverified-by-me-directly but widely reported]**: when VSync is enabled, `max_fps` is effectively overridden by the display's refresh rate unless `max_fps` is set *lower* than that refresh rate (in which case max_fps still throttles below it). i.e. VSync and max_fps are not mutually exclusive; VSync paces to the panel, max_fps is an additional ceiling.

### Does Godot request higher refresh rate on Android?

**[FACT — documented open bugs, not a documented guarantee of behavior]** This is currently unreliable/regressed on recent Android versions:

- [Issue #104179](https://github.com/godotengine/godot/issues/104179): "FPS is locked to 60 on Android 15, even with a 120 Hz display" — reproduced on Xiaomi 13 / VIVO X100 (Snapdragon 8 Gen 2, Android 15). The same project runs at 120 FPS fine on Android 13. FPS briefly spikes to 120 on app foreground/background transitions, then drops back to 60.
- [Issue #122827](https://github.com/godotengine/godot/issues/122827): games capped at 60 FPS on a Nothing Phone (2a), 120 Hz display, described as a recurring/ongoing problem across recent Godot versions.
- Context (not Godot-specific): Android's modern `Surface.setFrameRate()` API (targeting API 30+) is how apps should request a non-default refresh rate on current Android — [Android frame rate docs](https://developer.android.com/media/optimize/performance/frame-rate). Whether Godot's Android backend correctly calls this on a given Godot/Android version combination appears to be inconsistent per the linked issues, and is worth testing directly on your actual target devices rather than assuming.

**[JUDGEMENT]** Do not assume 90/120 Hz rendering "just works" on Android with Godot; treat it as best-effort. This raises the value of physics interpolation (§2): even if the render pacing is imperfect, having correct interpolated positions removes one variable, and 60 Hz physics is a safe target you don't need to change even if render FPS is uncertain per-device.

### Battery/thermal implications of high tick rate on phone

**[JUDGEMENT]** Physics simulation, `_physics_process` script execution, and any per-tick allocations run on every physics tick regardless of whether anything is visibly moving between turns. Running at 120+ Hz when render is capped at 60 means the CPU does physics work that never gets displayed at that rate — pure waste for battery/thermal budget, compounding on Android where sustained CPU usage triggers thermal throttling (which then *lowers* your achievable frame rate/tick rate — a self-defeating trade for a game whose core loop is "aim, flick, wait for stillness, repeat").

### Standard practice for turn-based games (idle most of the time)

**[FACT]** `OS.low_processor_usage_mode` (bool) — when true, "the engine reduces CPU usage... considerable sleep time is inserted between frames" and redraws are skipped when nothing changes; paired with `OS.low_processor_usage_mode_sleep_usec` to control the sleep interval (usec). This mode is primarily intended for editor-like/idle UI applications, and there are recent regressions reported in this area — [Issue #102914](https://github.com/godotengine/godot/issues/102914) ("Low Processor Usage Mode CPU usage still too high compared to 4.3") and [Issue #101058](https://github.com/godotengine/godot/issues/101058) ("low_processor_usage_mode increases CPU usage on empty scene") — so **[JUDGEMENT]** verify its actual effect on your Godot minor version before relying on it in production; it may not behave as documented in every 4.x release.

**[JUDGEMENT]** More robust and simpler for this specific game shape (long idle stretches between short bursts of physics activity):

1. Keep `physics_ticks_per_second` at 60 always (cheap when idle since sleeping bodies cost ~nothing per §6).
2. Set `Engine.max_fps` low (e.g. 30, or even 15) whenever both pens are `sleeping == true` (i.e., between turns, waiting for player input), and raise it back to display-refresh (unset/0, or match detected refresh) the instant a flick is released. This is directly analogous to how idle turn-based games (chess apps, board game apps) throttle render.
3. Do **not** throttle `physics_ticks_per_second` itself for this purpose — dropping tick rate mid-game changes simulation feel (damping/impulse behavior tuned at 60 Hz will feel different at a different tick rate — see §5) and is unnecessary since idle bodies barely cost anything physics-wise; throttle *render* FPS instead, which is where the real idle power draw comes from (GPU compositing, unnecessary draw calls).
4. Consider disabling `vsync` momentarily is unnecessary — simplest approach is `Engine.max_fps = 30` while idle, `Engine.max_fps = 0` (or device refresh) during the active turn animation.

---

## 4. Determinism and reproducibility

**[FACT]** Godot's built-in 2D physics (`GodotPhysics2D`) is explicitly **not deterministic across different machines**: "Godot physics is not deterministic between different computers because of differences in floating point implementations... The result of floating-point math can be slightly different on different CPUs, operating systems or versions" (community-documented, consistent with general float non-associativity issues; see [Snopek Games SG Physics 2D determinism writeup](https://www.snopekgames.com/tutorial/2021/getting-started-sg-physics-2d-and-deterministic-physics-godot/)).

**[FACT, more serious]** It is also **not guaranteed deterministic within the same machine/instance, run to run**: [Issue #112976](https://github.com/godotengine/godot/issues/112976), "Godot 2D physics is nondeterministic even within the same instance running on the same computer" — the reporter (building a TAS/replay tool for a 2D platformer) found that identical inputs sometimes produced different collision outcomes specifically when **3+ moving bodies collide simultaneously**, and traced part of it to doing a scene reload from `_process()` instead of `_physics_process()` (i.e. off the physics tick boundary) — switching the reload to `_physics_process()` removed the nondeterminism in their repro, but the underlying multi-body ordering sensitivity is still an open issue at time of writing.

**What breaks determinism [JUDGEMENT, informed by the above + general physics-engine knowledge]:**
- **Floating point**: different CPU/compiler/SIMD codepaths can produce bit-different results for the same math, especially across different devices (Android chipset diversity is severe here).
- **Iteration/processing order**: which body/contact gets resolved first in the solver can depend on internal broadphase ordering, which is not necessarily insertion-order-stable, especially with **3+ simultaneously colliding bodies** (directly relevant if you ever add hazards or a 3rd object to the table — with exactly 2 pens colliding it's a narrower, safer case, but not risk-free).
- **Variable timestep / off-tick mutation**: changing physics state from `_process()` or any callback not aligned to the physics tick (as in issue #112976).
- **Sleeping bodies**: waking/sleeping transitions are threshold-based on velocity magnitude (§6) which is itself float-derived and therefore has the same cross-device fragility; a body that "just barely" crosses vs. doesn't cross the sleep threshold can diverge in timing across runs/devices.
- **Threading**: `physics/2d/run_on_separate_thread` (project setting) moves 2D physics off the main thread; this and any multithreaded broadphase/solver internals are additional nondeterminism sources beyond single-threaded float issues, since thread scheduling can affect ordering.

**Implication for planned features [JUDGEMENT]:**
- **Replays via input-recording + resimulation**: not safely feasible cross-device with stock `GodotPhysics2D`, and the same-device case has at least one documented bug pattern (avoid it by keeping all body mutation strictly inside `_physics_process`, and note this project has only 2 dynamic bodies, which is the more resilient case, per issue #112976's description of the nondeterminism appearing with 3+ bodies).
- **Replays via transform-recording (record actual positions each tick, played back visually)** rather than re-simulating from inputs: fully safe, and is the standard workaround — record the ground truth trajectory rather than trying to reproduce it.
- **Online multiplayer lockstep** (each device simulates from the same inputs): **not safe** across heterogeneous Android hardware given the documented cross-device float nondeterminism — would require either a fixed-point physics replacement or a server-authoritative model (server simulates once, clients just render the result) instead of lockstep.
- **AI that searches impulses** (e.g. tree-searching flick angles/power against a simulated outcome): safe and unaffected by any of this, since it only needs the simulation to be *repeatable within one search* (same process, same tick), not deterministic across devices or wall-clock runs — this is the case issue #112976 doesn't even apply to as long as you don't rely on saved/replayed state.

### Alternatives

**[FACT]**
- **Rapier2D** via [godot-rapier-2d](https://github.com/appsinacup/godot-rapier-2d) (GDExtension around the Rust `rapier2d` crate): "Rapier Physics is cross-platform deterministic on all IEEE 754-2008 compliant 32- and 64-bit platforms" *in principle*, but the Godot integration itself currently has **cross-platform determinism disabled** per the project's own README notes — so out of the box it does not give you the guarantee, even though the underlying library can.
- **Box2D** via [godot-box2d](https://github.com/appsinacup/godot-box2d): "Box2D is binary deterministic, and Godot Box2D should also be binary deterministic, however no such tests were run yet" (project's own README hedge) — i.e. unverified claim, not a tested guarantee. Box2D v3 is also working toward cross-platform determinism upstream.
- **Jolt Physics** (`godot-jolt`, and native since Godot 4.4): **3D only.** "Jolt is a 3D physics library. It doesn't do 2D... GodotPhysics2D continues to be the physics engine for 2D games" — confirmed across multiple sources ([godot-jolt repo](https://github.com/godot-jolt/godot-jolt), [StraySpark migration guide](https://www.strayspark.studio/blog/godot-46-jolt-physics-migration-guide)). There is a community proposal to fake 2D-on-Jolt by using thin 3D shapes locked to a plane, but this is not an official or supported path and adds real complexity for a 2D-only game.

**[JUDGEMENT]** For Pen Fight specifically: none of the alternative engines currently ship a *verified* determinism guarantee in their Godot integration layer, so switching engines purely for determinism is not yet a safe bet — treat determinism as **not available today** for any online-multiplayer-lockstep or exact-replay-by-resimulation feature, and design those features (if pursued later) around server-authoritative simulation or trajectory recording instead.

---

## 5. Rigid body tuning for the pen-on-table feel

### Property reference

**[FACT]**, all from [RigidBody2D.xml](https://github.com/godotengine/godot/blob/master/doc/classes/RigidBody2D.xml) / [physics_material.h](https://github.com/godotengine/godot/blob/master/scene/resources/physics_material.h) / [physics_server_2d.cpp](https://github.com/godotengine/godot/blob/master/servers/physics_2d/physics_server_2d.cpp):

| Property | Default | Notes |
|---|---|---|
| `RigidBody2D.linear_damp` | `0.0` | Per-body damping; combines with project default per `linear_damp_mode` |
| `RigidBody2D.angular_damp` | `0.0` | Same, for rotation |
| `RigidBody2D.linear_damp_mode` | `DAMP_MODE_COMBINE` (0) | `COMBINE`: body value **adds** to area/project default. `REPLACE` (1): body value overrides it entirely |
| `RigidBody2D.angular_damp_mode` | `DAMP_MODE_COMBINE` (0) | Same for angular |
| `ProjectSettings.physics/2d/default_linear_damp` | **0.1** | Project-wide baseline linear damp |
| `ProjectSettings.physics/2d/default_angular_damp` | **1.0** | Project-wide baseline angular damp |
| `RigidBody2D.mass` | `1.0` | kg-equivalent units |
| `RigidBody2D.inertia` | `0.0` | `0.0` = auto-computed from mass + shape. Non-zero overrides auto calc |
| `RigidBody2D.center_of_mass_mode` | `CENTER_OF_MASS_MODE_AUTO` (0) | Auto-computed from shapes; `CUSTOM` (1) lets you override via `center_of_mass` |
| `RigidBody2D.continuous_cd` | `CCD_MODE_DISABLED` (0) | See §1 |
| `PhysicsMaterial.friction` | `1.0` | 0 = frictionless, 1 = max friction (used only for **contact/collision** friction between shapes, not travel damping) |
| `PhysicsMaterial.bounce` | `0.0` | Restitution, 0 = no bounce, 1 = perfectly elastic |
| `PhysicsMaterial.rough` | `false` | If true on a material, its friction "wins" (max of both) instead of the default (min of both) when two differing materials touch |
| `PhysicsMaterial.absorbent` | `false` | If true, subtracts this material's bounce from the other's instead of the default combine |
| `ProjectSettings.physics/2d/solver/solver_iterations` | **16** | Constraint solver iterations per step; raise this to firm up contact resolution before raising tick rate |
| `ProjectSettings.physics/2d/default_gravity` | **980.0 px/s²** | Irrelevant for a top-down table (see below) |

**[FACT]** Friction combine rule (from `PhysicsMaterial` docs): "If `rough` is true, the physics engine will use the friction of the object marked as rough when two objects collide. If false, the physics engine will use the **lowest** friction of all colliding objects instead. If true for both colliding objects, the physics engine will use the **highest** friction."

### Why top-down sliding friction is faked with damping, not a friction surface

**[JUDGEMENT]** `PhysicsMaterial.friction` in Godot 2D only matters at **contact** between two colliding shapes (it's Coulomb-style contact friction, resisting relative sliding *at the point of contact*, e.g. how much a pen resists spinning against another pen it's pressed against). It does **not** model the drag a flat object feels sliding across a table surface, because in a real top-down game there usually isn't a second physics body representing "the table" that the pen has an ongoing frictional contact with — the "table" is either a `StaticBody2D` boundary/wall only at the edges, or not a physics body at all, just background art. There's no continuous contact patch to apply Coulomb friction against.

This is exactly why 2D top-down games (this one included, per the stated design) fake table-sliding drag using **`linear_damp`/`angular_damp`** instead: damping is a velocity-proportional deceleration applied every physics step regardless of contact state, which is a reasonable approximation of real sliding friction (which is *roughly* velocity-independent in Coulomb friction, but velocity-proportional damping is dramatically simpler to tune and feels fine for arcade purposes) and it's "free" — no second collider needed.

**[JUDGEMENT — should you use a custom `_integrate_forces` instead?**
A custom `_integrate_forces(state)` override gives you per-tick access to `PhysicsDirectBodyState2D` (`state.linear_velocity`, `state.angular_velocity`, and the ability to apply arbitrary forces before the solver runs) and would let you implement true Coulomb-style friction (`F_friction = -μ * mass * gravity_equivalent * normalize(velocity)`, constant magnitude, direction-opposing) instead of Godot's default proportional damping (`F ∝ -damp * velocity`). This is more physically correct sliding behavior (objects with Coulomb friction decelerate *linearly* to a stop, whereas damped decay only asymptotically approaches zero and technically never fully stops, though it becomes imperceptible quickly) and gives finer control (e.g. friction only kicking in once speed is below some threshold, to avoid the game feeling like the pens are underwater at low speed vs. correct at high speed).

For this project: **`linear_damp`/`angular_damp` is almost certainly good enough** and much simpler to reason about and tune (2 constants vs. writing/debugging a custom integrator). Reach for `_integrate_forces` only if playtesting reveals a specific feel problem that damping alone can't produce — e.g., you want pens to "stick" more decisively rather than asymptotically creeping, or you want the friction magnitude to depend on which capsule end is leading (unlikely to matter for a symmetric pen).

**[JUDGEMENT]** Also set `gravity_scale = 0.0` on both pens (or `physics/2d/default_gravity = 0`) since this is a top-down table view — Godot 2D's default gravity (980 px/s² downward on the Y axis) models a side-view/platformer world, and would otherwise constantly accelerate your pens toward the bottom of the screen, which is wrong for a top-down table. If you rely on `linear_damp`/`angular_damp` alone with gravity zeroed, the pens will only move from your applied flick impulse and pen-pen collision impulses, then decay to rest — which is the correct top-down model.

### Starting value ranges for a capsule pen on a table

**[JUDGEMENT — starting points for playtesting, not measured/derived]**

| Constant | Suggested starting range | Notes |
|---|---|---|
| `linear_damp` (per pen) | `1.0` – `4.0` | Higher = pen stops sooner/shorter slide. Combine mode is additive with project default `0.1`, so effective damp ≈ your value + 0.1 |
| `angular_damp` (per pen) | `2.0` – `6.0` | Usually higher than linear damp — spinning looks chaotic and should settle faster than translation |
| `mass` | `1.0` (both pens equal) | Keep pens equal mass unless you deliberately want asymmetric knockback |
| `PhysicsMaterial.friction` (pen-pen contact) | `0.1` – `0.3` | Lower = pens glance/slide off each other more; higher = more grabby spin transfer on contact |
| `PhysicsMaterial.bounce` (pen-pen contact) | `0.0` – `0.2` | Real pens don't bounce much; keep this low so hits feel like a "thud" not a "billiard click" |
| `MAX_IMPULSE` | tune against damping, not in isolation | See method below — this is the one constant that must be tuned *last*, after damp values are set, because it defines what "hardest possible flick" travels given the damping in place |
| `physics/2d/solver/solver_iterations` | leave at `16` initially | Only raise if contact response feels soft/penetrating |

### Systematic tuning method (rather than guesswork)

**[JUDGEMENT — proposed methodology]**

1. **Fix everything except one variable.** Set `MAX_IMPULSE` to a large placeholder, zero `angular_damp`, and tune `linear_damp` first in isolation: apply a fixed test impulse (e.g. via a debug hotkey) directly along one axis on a pen with no obstacles, and measure/log distance traveled and time-to-stop (`state.linear_velocity.length() < ε`). Solve for the damp value that gives your desired "hardest flick crosses X% of the table" distance, using the closed form for exponential-like damping decay (`v(t) ≈ v0 * e^(-damp*t)` is Godot's per-tick damping approximation) as a starting guess, then correct empirically.
2. **Then tune `angular_damp`** the same way: apply a fixed test torque/spin, measure time for rotation to visually settle (not necessarily to sleep-threshold zero — see §6). Angular motion converging faster than linear motion (which is common design intent — a spinning pen looking "controlled" rather than helicoptering across the table) is the number you're chasing.
3. **Then tune pen-pen `friction`/`bounce`** with two pens on fixed converging trajectories at a fixed speed — this isolates contact behavior from travel behavior, which you already fixed in steps 1–2.
4. **Tune `MAX_IMPULSE` last**, against the now-fixed damping curve: pick the strongest flick you want to allow, and set `MAX_IMPULSE` so that flick corresponds to a specific, playtested "fastest reasonable slide" (e.g. crosses most of the table but stops well short of instantly reaching the far edge such that skill in aiming still matters, not raw power).
5. **Automate steps 1–3** with an in-editor debug scene or a headless test scene (`SceneTree.quit()` after N physics frames, printing final position/velocity) so each constant change can be reverified in seconds rather than by manual play each time — this turns tuning into a scripted parameter sweep instead of guesswork.
6. Re-verify feel at the actual target tick rate (60 Hz, per §1) since damping is expressed as a fraction of velocity removed **per tick** in the underlying integrator — if you ever revisit tick rate, damping constants must be re-tuned, they are not tick-rate-invariant (this exact concern was raised by the engine team in [godot-proposals discussion #9478, "Shouldn't damp be tick-rate independent?"](https://github.com/godotengine/godot-proposals/discussions/9478) — confirming damping-vs-tick-rate coupling is a known, real subtlety, not a hypothetical one).

---

## 6. Sleeping, settling, and turn-end detection

### Relevant API and settings

**[FACT]**
- `RigidBody2D.sleeping` (bool, default `false`) — current sleep state; can be set manually to force sleep/wake.
- `RigidBody2D.can_sleep` (bool, default `true`) — whether this body is allowed to fall asleep automatically at all.
- `RigidBody2D.sleeping_state_changed` (signal, no args) — "Emitted when the physics engine changes the body's sleeping state... **not emitted** when sleeping is changed manually" (i.e. only fires for automatic transitions, not for your own `body.sleeping = true` calls) — [RigidBody2D.xml](https://github.com/godotengine/godot/blob/master/doc/classes/RigidBody2D.xml).
- `ProjectSettings.physics/2d/sleep_threshold_linear` — float, **default `2.0`** (px/s) — [`physics_server_2d.cpp`](https://github.com/godotengine/godot/blob/master/servers/physics_2d/physics_server_2d.cpp).
- `ProjectSettings.physics/2d/sleep_threshold_angular` — float, **default `Math::deg_to_rad(8.0)`** rad/s (≈ 8°/s) — same source.
- `ProjectSettings.physics/2d/time_before_sleep` — float, **default `0.5`** seconds — same source. A body must stay under both velocity thresholds continuously for this long before it's put to sleep.
- These map to `PhysicsServer2D` space parameters `SPACE_PARAM_BODY_LINEAR_VELOCITY_SLEEP_THRESHOLD` / `SPACE_PARAM_BODY_ANGULAR_VELOCITY_SLEEP_THRESHOLD`, settable per-`World2D` at runtime via `PhysicsServer2D.space_set_param()` if you need per-scene overrides instead of a global project setting.

### How to detect "turn is over, everything has settled"

**[JUDGEMENT]** Three viable strategies, with trade-offs:

**A. Sleep signals (`sleeping_state_changed` on both pens, check both `sleeping == true`)**
- Pro: zero-cost (uses the engine's own settle detection, no polling math needed), and semantically exactly matches "the physics engine has decided this body isn't moving."
- **Failure mode**: a pen resting against a wall/edge or wedged against the other pen can, depending on tiny residual solver jitter from ongoing contact resolution, have its velocity bounce fractionally above `sleep_threshold_linear`/`angular` on some ticks, resetting the `time_before_sleep` timer repeatedly and never accumulating enough continuous quiet time to sleep — i.e. **a body in continuous light contact may never sleep**, even though it looks stationary to the player. This is a known general behavior of contact solvers, not a Godot-specific bug — [related report for RigidBody3D](https://bugnet.io/blog/fix-godot-rigidbody3d-sleeping-too-aggressively) and [RigidBody2D during stack collapse](https://bugnet.io/blog/fix-godot-physics-2d-rigidbody-sleeping-during-stack) show the sleep heuristic being either too eager or not eager enough depending on scenario, i.e. it isn't perfectly robust in either direction.

**B. Velocity-magnitude threshold, polled each `_physics_process`**
- e.g. `if state.linear_velocity.length() < V_EPS and abs(state.angular_velocity) < W_EPS: quiet_time += delta else: quiet_time = 0`, then declare "settled" once `quiet_time > SETTLE_TIME` for both pens.
- Pro: you control the thresholds and the debounce time directly (independent of the project's global sleep thresholds, so you can tune "gameplay settled" separately from "physics engine considers this body inactive").
- **Failure mode**: **a pen creeping forever under low damping** — if `linear_damp` is small, velocity decays asymptotically and may take many seconds to cross even a small epsilon threshold, especially with floating point residues; also same wall-contact chatter issue as strategy A if your epsilon is tight.

**C. Timeout (fixed wall-clock/tick budget per turn, e.g. "after 5 seconds, force-end the turn regardless")**
- Pro: guarantees the turn *will* end, no matter what — a hard backstop against both of the above failure modes.
- **Failure mode**: if used *alone*, either cuts off a legitimately still-sliding pen (turn ends while something is visibly moving — feels broken) or, if set generously long, makes every turn feel sluggish while waiting out worst-case creep even when the table is visually still.

**[JUDGEMENT — recommended combination]**: use **B as primary** (a velocity-magnitude+angular threshold, debounced by a short continuous-quiet duration, e.g. 0.2–0.3s) with **`sleeping_state_changed`/`sleeping` as a fast-path early exit** (if both are already asleep, you can trust that immediately, skip the polling wait) and **C as a hard safety timeout** (e.g. 4–6 seconds) so a pathological case (low damping, wall-hugging chatter) can't stall the game forever — this directly supports the planned stalemate rule too: if the "hasn't moved meaningfully" check under B triggers **immediately** at the start of a turn (velocity magnitude never exceeded some minimum in the first place), that's your stalemate/forfeit signal, distinct from "settled after moving."

```gdscript
# Example turn-settle detector (illustrative GDScript, not tested against a live project)
const V_EPS := 4.0      # px/s, above the default sleep threshold of 2.0 -- deliberately looser
const W_EPS := 0.2      # rad/s
const QUIET_TIME := 0.25 # seconds of continuous quiet before declaring "settled"
const TURN_TIMEOUT := 5.0 # hard backstop

var _quiet_accum := 0.0
var _turn_elapsed := 0.0
var _moved_at_all := false

func _physics_process(delta: float) -> void:
	_turn_elapsed += delta
	var all_quiet := true
	for pen in [pen_a, pen_b]:
		if pen.sleeping:
			continue # trust the engine's own determination for this body
		var v := pen.linear_velocity.length()
		var w := absf(pen.angular_velocity)
		if v > V_EPS or w > W_EPS:
			all_quiet = false
			_moved_at_all = true

	if all_quiet:
		_quiet_accum += delta
	else:
		_quiet_accum = 0.0

	if _quiet_accum >= QUIET_TIME or _turn_elapsed >= TURN_TIMEOUT:
		_end_turn(_moved_at_all)
```

---

## 7. Capsule extents vs. center for the out-of-bounds test

### Concrete Godot 4 approaches

**[FACT]**
1. **`Shape2D.get_rect()`** — every `Shape2D` (including `CapsuleShape2D`) has `get_rect() -> Rect2 const`, "Returns a Rect2 representing the shape's boundary" — this is in the **shape's local space**, so you must transform it to global space yourself (e.g. via the owning `CollisionShape2D`'s `global_transform`) if you need world-space extents. ([class_shape2d.rst](https://raw.githubusercontent.com/godotengine/godot-docs/master/classes/class_shape2d.rst))
2. **`CollisionShape2D` + `CapsuleShape2D` extents transformed manually**: `CapsuleShape2D.radius` (default `10.0`) and `CapsuleShape2D.height` (default `30.0`, "full height including the semicircles") give you the local capsule dimensions; combine with the `CollisionShape2D`'s `global_transform` (position + rotation) to compute the world-space endpoints of the capsule's central segment, then offset by `radius` perpendicular to the pen's long axis to get the actual outer extent points. This is more manual than `get_rect()` but gives you exact geometry (useful if you want "did the rounded tip cross the edge" precision, since `get_rect()`'s axis-aligned box over-estimates the corners of a rotated capsule).
3. **`Area2D` overlap on the table region** (`body_shape_exited(body_rid, body, body_shape_index, local_shape_index)` signal, or `body_exited(body)` if you don't need per-shape granularity): put an `Area2D` matching the table's playable bounds, and treat "a pen's shape stopped overlapping the table area" as the OOB signal. **[FACT]** these signals require `Area2D.monitoring = true` and fire on shape-level enter/exit specifically for `body_shape_entered`/`body_shape_exited` — [Area2D.xml](https://github.com/godotengine/godot/blob/master/doc/classes/Area2D.xml).
4. **Manual point/AABB-vs-table-Rect2 test each physics tick** (what the project currently does, but on the shape's extents instead of the center) — computed from approach (2), tested against the table's `Rect2` via `Rect2.intersects()` / `Rect2.encloses()`.

### Which gives correct behavior for a pen hanging half off the edge?

**[JUDGEMENT]**
- **Center-point test (current implementation)**: wrong for the stated design goal — a pen can be more than half off the table (center past the edge) and still be recovering/sliding, or conversely be mostly on the table with only a sliver hanging off and get falsely flagged, depending on exact geometry; it doesn't match the "capsule extents" plan already decided.
- **`Area2D.body_exited`** (whole-body exit): only fires once the *entire* shape has left the Area2D's shape — i.e. this tells you "fully off the table," not "starting to fall off" or "center of mass past the edge." Good for a hard "definitely lost" signal, but not for a nuanced center-of-mass rule (see below) and not event-driven per-frame for continuous checks like "is it now half off."
- **`Area2D.body_shape_exited`**: fires as soon as *any part* of the shape stops overlapping the monitored area — this is closer to "just touched the edge," i.e. too early/sensitive for a "fell off" determination by itself (a pen can have its rounded end briefly cross the table's Area2D boundary edge, sliding along it, without truly falling), but is a good **early warning / near-edge trigger** to switch to per-tick precise geometric checking rather than running expensive geometry every tick unconditionally.
- **Manual AABB/extent-vs-Rect2 test using `get_rect()` or the transformed capsule endpoints, run every tick (or only once near-edge, gated by the `Area2D` signal above for efficiency)**: gives you the actual answer needed — "is any part of the capsule's shape now beyond the table Rect2," which is what "capsule extents instead of center" in the stated plan means, and lets you implement whichever fairness rule you choose (see next).

**[JUDGEMENT — recommended combination]**: use an `Area2D` matching the table bounds as a cheap continuous trigger (`body_shape_exited`) to know *when* a pen first touches the boundary, then from that point run the precise capsule-extents-vs-table-`Rect2` test each physics tick until either the pen re-enters fully or is confirmed off — this avoids doing precise geometry math every single tick for the (very common, most of the game) case where both pens are nowhere near the edge.

### Geometric edge vs. center-of-mass — "the real schoolyard rule" and what feels fair

**[JUDGEMENT — this is a design opinion, not an engine fact]**
- The literal schoolyard "pen fight"/flick-football/tabletop-curling convention is almost universally **geometric**: if *any part* of the object is hanging past the edge such that it's no longer supported and would physically fall (i.e., its own weight/tip is past the table edge), it's out — not "the mathematical centroid crossed a line." This matches real-world intuition (you can see the pen's tip dangling over the edge and everyone agrees it's falling) more than a center-of-mass rule would.
- A **center-of-mass rule** is more forgiving (a pen can have its rounded tip well past the edge and still be "in" as long as its balance point hasn't crossed) and would feel *less* fair/intuitive to players who can visually see a chunk of the pen hanging off — it optimizes for "technically still balanced" over "looks like it fell," which mismatches player expectations built from the physical game this is based on.
- **Recommendation**: use the **geometric capsule-extent test** (any part of the shape crosses the table boundary = fallen), matching both the stated project plan and the real-world rule it's modeling. Reserve a center-of-mass-style check only if playtesting shows the geometric rule feels *too* strict (e.g., pens getting called "out" while still clearly recoverable/sliding along the edge) — in which case a middle ground is requiring the extent to be past the edge by some small margin (a few pixels) rather than switching rules entirely, which preserves the intuitive "I can see it's off" feel while adding a little tolerance for solver jitter at the boundary.

---

## 8. Input latency on the flick

### Touch delivery in Godot

**[FACT]**
- `InputEventScreenDrag` properties ([class_inputeventscreendrag.rst](https://raw.githubusercontent.com/godotengine/godot-docs/master/classes/class_inputeventscreendrag.rst)): `position` (Vector2, viewport coords), `relative` (Vector2, delta from previous drag event, content-scale-adjusted), `velocity` (Vector2, drag velocity, content-scale-adjusted), `screen_relative` and `screen_velocity` (unscaled, raw screen-pixel equivalents, unaffected by `content_scale` settings), `index` (multi-touch finger id), plus stylus-only `pressure`/`tilt`/`pen_inverted`.
- These events are generated by the platform's native touch pipeline and delivered into Godot's input queue; Godot does not control the underlying Android touch sampling rate (that's a hardware/driver property, commonly 60–240+ Hz depending on device, independent of Godot's render or physics rate).
- **[FACT — documented, historical]** Android touch input in Godot has had at least two relevant bugs worth being aware of:
  - A **touch dead-zone / slop** issue ([Issue #84138](https://github.com/godotengine/godot/issues/84138)): drag/position movement below roughly 20px wasn't registered at all on some devices, traced to Android's `ViewConfiguration` touch-slop mechanism; addressed by [PR #84331](https://github.com/godotengine/godot/pull/84331). If you're on an older Godot 4.x version, verify this is actually fixed in your version — a real dead zone at the start of a flick gesture would directly hurt "feels 1:1" responsiveness.
  - A longer-standing general **"input lag while dragging on Android"** report ([Issue #34480](https://github.com/godotengine/godot/issues/34480), older/3.x-era but conceptually relevant) with no single confirmed root cause in the thread, other than that `_input`, `_process`, and `_physics_process` polling approaches were all tried and none eliminated it outright at the time — treat this as a signal to **measure on your actual target devices** rather than assume any particular version is lag-free.

### `_input` vs `_physics_process` for reading drag input

**[JUDGEMENT]**
- `_input()` (or `_unhandled_input()`) receives events as soon as Godot's main thread processes the input queue for that frame — this is the lowest-latency place to *capture* raw sample data (position, timestamp via `Time.get_ticks_usec()` at the moment you receive the event), because it isn't throttled to the physics tick rate.
- Actually **applying** the resulting impulse to the `RigidBody2D` must happen in `_physics_process()` (or via `PhysicsServer2D` direct calls) — physics state (`apply_impulse`, `linear_velocity`, etc.) should only be touched on the physics tick, both for engine-contract reasons and to line up with interpolation (§2) if enabled.
- **Recommended pattern**: accumulate/buffer raw drag samples (position + `Time.get_ticks_usec()`) in `_input()` into an array, and consume/clear that buffer once per `_physics_process()` call to compute the release velocity and apply the impulse. This captures every touch sample Godot delivers (potentially more frequent than 60 Hz) without missing samples between physics ticks, while keeping the actual physics mutation on-tick.

### Computing a flick velocity that feels 1:1

**[JUDGEMENT]**
- **Last-two-points delta** (`(pos[-1] - pos[-2]) / (t[-1] - t[-2])`, or simply Godot's own `InputEventScreenDrag.velocity`/`screen_velocity` from the final drag event before release): most responsive to a sudden last-instant flick, but highly sensitive to a single noisy/outlier sample right at release (a common touch-digitizer artifact is a slightly erratic final sample as the finger lifts off).
- **Time-windowed average** (e.g. average velocity over the last ~80–120ms of samples, or a weighted average favoring more recent samples): smooths out that release-frame noise and produces a more consistent, predictable flick-to-impulse mapping, at the cost of slightly discounting a genuine very-last-instant direction change.
- **Recommendation**: use a short time window (not a fixed sample count, since sample rate varies by device) — e.g., filter the buffered samples to just those within the last ~100ms before release, compute total displacement over that window divided by elapsed time. This is a middle ground: still very responsive (100ms is imperceptibly recent to a human), but immune to single-sample noise. Godot's own `screen_velocity` on the final event is a reasonable fallback/cross-check but shouldn't be your sole source, since it reflects only the last two samples.

### Clamping to `MAX_IMPULSE` without flattening hard flicks

**[JUDGEMENT]**
- A hard clamp (`impulse = min(raw_impulse, MAX_IMPULSE)`) makes every sufficiently-hard flick feel identical past the cap — bad, since the design wants "hard flicks feel different from very hard flicks" up to some ceiling.
- Prefer a **soft compression curve** approaching the max asymptotically rather than a hard ceiling, e.g. map raw flick speed through something like `impulse = MAX_IMPULSE * (1.0 - exp(-raw_speed / K))` (tune `K` so typical "hard flick" speeds land around 70–90% of `MAX_IMPULSE`, leaving headroom for a perceptibly-but-not-dramatically stronger max flick), or a simple `clamp` combined with non-linear scaling below the cap (e.g. `pow(normalized_speed, 0.7)` before scaling to `MAX_IMPULSE`, so mid-strength flicks feel appropriately weighted rather than mapping linearly then hitting a wall).
- Either way, `MAX_IMPULSE` should be treated as "the impulse magnitude at which the pen crosses the whole table" (tuned per §5's step 4) rather than an arbitrary safety cap — that framing keeps the compression curve meaningful instead of an afterthought clamp.

### Measuring end-to-end touch-to-response latency on Android

**[JUDGEMENT — practical method, no single built-in Godot tool for this]**
1. **High-speed camera method** (most reliable, no code needed): film the phone screen and your finger at 120/240fps with another device, count frames between finger-contact/release and the first visible on-screen physics response; convert frame count to ms. This measures true end-to-end latency including touchscreen digitizer delay, OS input pipeline, and Godot/GPU compositing — nothing else does.
2. **In-engine instrumentation** (measures only the portion inside your app, not digitizer/OS latency): timestamp with `Time.get_ticks_usec()` the moment `_input()` first receives the release/final drag event, and again the frame the resulting visual change is actually presented (e.g. inside `_process()` after the impulse was applied, or via a debug overlay draw); log the delta. This *undercounts* real latency (misses touch-controller and OS compositor delay) but is useful for catching regressions you introduce in your own code (e.g. accidentally deferring impulse application by a frame).
3. Cross-check against `Engine.get_frames_per_second()` and physics tick timing (`Engine.get_physics_frames()`) during the same test to rule out "it's not your input code, it's just a slow/throttled frame" as the cause of any measured lag.

---

## 9. Slow-motion debugging

### `Engine.time_scale` vs. changing `physics_ticks_per_second`

**[FACT]** `Engine.time_scale` — float, **default `1.0`**. "The speed multiplier at which the in-game clock updates, compared to real time. A value of 2.0 makes the game update twice as fast, while 0.5 makes the game update half as fast. ... affects timers and delta-based simulations but not audio playback." ([Engine docs](https://docs.godotengine.org/en/stable/classes/class_engine.html))

**[JUDGEMENT]**
- `time_scale` **preserves the simulation you're trying to observe**: it scales the effective `delta` fed to `_physics_process` (and `_process`) each call, so at `time_scale = 0.25` the *same number of physics steps* still run per second of wall-clock game logic relative to itself, just spread across 4x more real-world seconds — you get a genuinely slow-motion replay of the same physics, same collision resolution order, same solver behavior, just stretched in real time. This is the correct tool for "watch this collision happen slower."
- **Lowering `physics_ticks_per_second` instead** does *not* give slow motion — it changes the actual simulation (bigger timestep per step = different, coarser integration, different damping-per-second behavior since damping is applied per-tick per §5, and potentially different collision outcomes entirely, i.e. it changes *what* happens, not just how fast you watch it happen). Use it only if you deliberately want to stress-test coarse-timestep behavior (e.g., verifying no tunnelling at low tick rate), not for observation/debugging purposes.
- **Recommendation**: use `Engine.time_scale` (e.g. set to `0.2`–`0.3` via a debug hotkey) for slow-motion inspection of a collision; never repurpose `physics_ticks_per_second` for this.

### Debug overlay: velocity vectors and contact points

**[FACT]** Relevant built-ins:
- `Engine.get_frames_per_second()`, `Engine.get_physics_frames()` for on-screen counters.
- `ProjectSettings`/Debug menu: **Debug > Visible Collision Shapes** (editor menu toggle) or programmatically `get_tree().debug_collisions_hint = true` before the collision shapes start drawing, for a built-in view of collider outlines (not vectors/contacts specifically, but useful alongside a custom overlay).
- `PhysicsDirectSpaceState2D` methods usable from `_integrate_forces` or `_physics_process` via `PhysicsServer2D.space_get_direct_state(get_world_2d().space)` or `get_world_2d().direct_space_state`:
  - `collide_shape(params) -> Array[Vector2]` — returns actual contact point pairs for a query shape against the space; usable to visualize where two pens are touching.
  - `get_rest_info(params) -> Dictionary` — nearest-collision info including collision point, normal, and the colliding object's velocity, for a query shape.
  - `intersect_shape` / `intersect_point` / `cast_motion` / `intersect_ray` — general spatial queries, useful for building custom debug probes (e.g. "is anything near the table edge right now").

**[JUDGEMENT — building the overlay]**
- For **velocity vectors**: in a debug-only `_draw()` (on a dedicated `CanvasLayer`/`Node2D` overlay, redrawn via `queue_redraw()` each `_physics_process`), draw a `draw_line()` from each pen's `global_position` to `global_position + linear_velocity * SCALE` (pick `SCALE` so typical flick speeds draw a readable few-hundred-pixel arrow), plus a small arc/label for `angular_velocity` if you want spin visualized too.
- For **contact points**: rather than querying `PhysicsDirectSpaceState2D` speculatively, it's simpler and cheaper to enable `RigidBody2D.contact_monitor = true` and set `max_contacts_reported` to a small number (default is `0`, meaning **no contacts are recorded at all** even with `contact_monitor` on — this is a common gotcha per the docs' explicit warning), then read `get_contact_count()` / `get_contact_local_position(i)` / `get_contact_collider_position(i)` each physics tick to draw a marker at each active contact — this uses the engine's already-computed contact data instead of re-querying the space redundantly.
- Gate all of this behind a debug build flag (`OS.is_debug_build()` or a custom autoload toggle) so it never runs in the shipped Android build — continuous per-tick `_draw()` and contact-array iteration is unnecessary CPU/battery cost in production, compounding the battery concerns already raised in §3.

---

## Summary of key numeric defaults referenced above

| Setting | Default | Source type |
|---|---|---|
| `physics/common/physics_ticks_per_second` | 60 | Engine source (`main.cpp`) |
| `physics/common/max_physics_steps_per_frame` | 8 | Engine source |
| `physics/common/physics_jitter_fix` | 0.5 | Engine source |
| `physics/common/physics_interpolation` | false | Inferred from proposal #12950 (still proposing to change this) |
| `physics/2d/default_gravity` | 980.0 px/s² | Engine source (`physics_server_2d.cpp`) |
| `physics/2d/default_linear_damp` | 0.1 | Engine source |
| `physics/2d/default_angular_damp` | 1.0 | Engine source |
| `physics/2d/sleep_threshold_linear` | 2.0 px/s | Engine source |
| `physics/2d/sleep_threshold_angular` | ~0.1396 rad/s (8°/s) | Engine source |
| `physics/2d/time_before_sleep` | 0.5 s | Engine source |
| `physics/2d/solver/solver_iterations` | 16 | Engine source |
| `display/window/vsync/vsync_mode` | VSYNC_ENABLED (1) | Engine source (`main.cpp`) |
| `Engine.max_fps` | 0 (uncapped) | Official docs |
| `Engine.time_scale` | 1.0 | Official docs |
| `RigidBody2D.linear_damp` / `angular_damp` | 0.0 | Header (`rigid_body_2d.h`) |
| `RigidBody2D.mass` | 1.0 | Header |
| `RigidBody2D.continuous_cd` | CCD_MODE_DISABLED (0) | doc XML |
| `RigidBody2D.max_contacts_reported` | 0 | doc XML |
| `PhysicsMaterial.friction` | 1.0 | Header |
| `PhysicsMaterial.bounce` | 0.0 | Header |
| `CapsuleShape2D.radius` / `height` | 10.0 / 30.0 | doc |
| `Node.physics_interpolation_mode` | INHERIT (0) | doc XML |
