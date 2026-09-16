# Pen Fight — Art & Feel Implementation Spec

A handoff document. It defines the coordinate system, the art, the exact project
settings, the scene tree, and the feel layer, so that implementation is a matter of
following numbers rather than making judgement calls.

Read §0 before trusting any number here — and **§0.5 for what the code actually does now**. This
document is the pre-implementation design intent. Where it and the shipped build disagree, the build wins,
and §0.5 lists every place that happens.

---

## 0. How to read this document

Every value carries one of these labels. **They are not decoration — treat them differently.**

| Label | Meaning | What you must do |
|---|---|---|
| `[FIXED]` | A contract other parts of this doc depend on (coordinates, sprite sizes, file paths). | Do not change without updating everything downstream. |
| `[DEFAULT]` | Godot's own documented default, verified against the engine source by the research pass. | Use as-is. |
| `[TUNE]` | A starting point for playtesting, derived or estimated. Not measured. | Ship the starting value, then tune on a real device. |
| `[VERIFY]` | An API name, signature or behaviour I could **not** check against the Godot docs. | Confirm before relying on it. Each one names the check. |

**Why `[VERIFY]` exists.** The research behind this project ran in an environment whose
egress policy blocked every external host, so no Godot documentation page was ever
opened — everything came from search-result summaries. Engine defaults that appear in
many indexed tutorials are probably right; exact signatures and orientation conventions
are exactly the kind of thing that gets misremembered. **No code in this document has
been compiled or run.** There is no Godot binary in the environment that produced it.

Treat the code as a precise description of intent, not as known-good source.

## 0.5 Shipped reality (2026-09-16)

The build exists now and disagrees with this document in a handful of places. This is the short version, so
that nobody re-derives a stale number; each affected section carries an inline correction too.

| Thing | This doc | Shipped | Cite |
|---|---|---|---|
| Design viewport | `1280 × 720` | `1280 × 720` ✔ | `game/project.godot:24-25` |
| Stretch aspect | `expand` | **`keep_height`** | `game/project.godot:27` |
| Renderer | `mobile`, or `gl_compatibility` | **`gl_compatibility`** | `game/project.godot:45` |
| Physics tick | `240` ✔ | `240` ✔ | `game/project.godot:36` |
| World origin | viewport top-left, centre `(640, 360)` | **the table centre** — the playfield is centred on the origin and uses negative coordinates | `game/scripts/main.gd:102` |
| **Playfield rect** | **`Rect2(80, 60, 1120, 600)`** | **`Rect2(-590, -320, 1180, 640)`** | `game/scripts/main.gd:102` |
| Table art | `1440 × 840` centred at `(640, 360)` | `1440 × 840` at `(0, 0)`, unscaled: `130 px` bleed per side horizontally, `100 px` vertically | `game/scenes/main.tscn:29-34`, `game/assets/table.png` |
| Pen length | `360 px` | **`180 px`** (half-length `85` + radius `5`) | `game/scripts/pen_body.gd:48-49` |
| Pen barrel radius | `10` | **`5`** | `game/scripts/pen_body.gd:48` |
| Pen art canvas | `440 × 96`, pen spans `x 40…400` | **`540 × 96`**, drawn at `scale = 0.333333` | `game/scenes/main.tscn:52-59`, `game/assets/pen_bic.png` |
| Full-power drag | `MAX_DRAG = 220 px` | **`160 px`** (`max_drag_pixels`) | `game/scripts/aim_input.gd:50` |
| Cancel radius | `CANCEL_RADIUS = 34 px` | **`30 px`** (`min_drag_pixels`, measured from the press point) | `game/scripts/aim_input.gd:46` |
| Grab zone | "on or near the active pen" | the pen's **capsule** + `grab_margin_px = 26` — the drag may start anywhere along the barrel | `game/scripts/aim_input.gd:53` |
| `MAX_IMPULSE` | `1600` | `1600` ✔ | `game/scripts/pen_body.gd:42` |
| Settle angular | `0.25 rad/s` | **`0.4 rad/s`** | `game/scripts/pen_body.gd:29` |
| Settle hold | `0.25 s` ✔ | `0.25 s` ✔ | `game/scripts/pen_body.gd:30` |
| In-flight backstop | `SETTLE_TIMEOUT = 6.0 s` | **`RESOLVE_TIMEOUT = 8.0 s`** | `game/scripts/turn_state.gd:83` |
| Stalemate and idle | one "forfeit turn" | **two separate verdicts**: the stalemate forfeit (a turn where no pen ever moved) and an idle forfeit at `FORFEIT_TIMEOUT = 15 s` (a turn left unattended) | `game/scripts/turn_state.gd:40-51`, `game/scripts/main.gd:97` |
| Out-of-bounds verdict | **centre of mass** (§6) | **capsule extents — "any part off"**, radius-inset with an `8 px` tolerance. The code says so in as many words: "never centre-of-mass" | `game/scripts/pen_body.gd:270-284` |
| Turn phases | `AIMING` / `RESOLVING` / `JUDGING` | `AIM` / `IN_FLIGHT` / `SETTLED` / `ROUND_OVER` | `game/scripts/turn_state.gd:40-43` |
| Round verdicts | — | `knockout` / `self_oob` / `stalemate` / `idle` / `backstop`, tallied per session | `docs/design/core-loop.md` §Re-check |

**Nodes this document specifies that the build does not have:**

- `Pen.tscn` — **there is no pen scene.** `game/scenes/` contains `main.tscn` alone; the pens are
  `RigidBody2D` nodes inside it (`PenRed`, `PenBlue`) driven by `game/scripts/pen_body.gd`.
- `Pens` (the `Node2D` container), `UI` (`CanvasLayer`) and `TurnGate` (`Control`) — the HUD, the turn gate
  and the aim overlay are built in code, not in the scene tree.
- `TableArea` — shipped as `ExitZone` (`Area2D`) and it carries **no script**: nothing connects
  `body_exited`. Out-of-bounds is polled in `pen_body.gd`, so §6's "why `TableArea` exists" is moot.
- `Pen.gd` (§5's sketch) — shipped as `pen_body.gd`, which integrates through `_integrate_forces` and reads
  the radius and half-length off the shape node rather than using the constants sketched there.

**What shipped from §9's feel layer:** #1 the turn gate, #2 trauma shake (`MAX_OFFSET 10`, `MAX_ROLL 3°`,
decay `2.0`), #3 hit-stop (`time_scale 0.02`, 2–6 frames, with the shake master switch kept separate),
#4 the layered impact sound, #5 the audio buses, #7 a knockout ceremony, #8 haptics (`haptics.gd`). **Not
shipped: #6 particles** — there is no particle system in `game/` at all. §9's ordering constraint is
honoured: the ceremony fires once per *decided* round, after the verdict.

**§10's build order is complete through step 10.** Step 11 — the 20-round test — is the open gate
(`docs/design/feature-priorities.md` rank 2), and the build now prints the loop's own numbers for it
(`docs/design/core-loop.md` §Re-check). One visual check nobody has recorded: whether the lip drawn in
`table.png` lines up with the *shipped* rect (the numbers above put the playfield `130 px` inside the art
horizontally, `100 px` vertically, where §1 assumed `80 px`).

---

## 1. The coordinate contract `[FIXED]`

Everything else depends on this. Set it first and do not drift from it.

| Thing | Value |
|---|---|
| Design viewport | `1280 × 720` |
| World origin | Top-left of the viewport, `+X` right, `+Y` down (Godot 2D default) |
| Viewport centre | `(640, 360)` |
| Table sprite | centred at `(640, 360)`, texture `1440 × 840`, scale `1.0` |
| **Playfield rect** | **`Rect2(80, 60, 1120, 600)`** — x `80…1200`, y `60…660` |
| Pen length in world units | `360 px` |
| Pen barrel width | `20 px` (capsule radius `10`) |

> **Shipped (2026-09-16):** none of the three rows above survived contact with the build. The playfield is
> `Rect2(-590, -320, 1180, 640)` in a world whose **origin is the table centre** (so the "viewport centre
> `(640, 360)`" row is not how anything is placed), the pen is **`180 px`** long with a **`5 px`** barrel
> radius, and the table sprite sits at `(0, 0)`. The full table is in §0.5.

The table texture is deliberately larger than the viewport (`1440 × 840` vs `1280 × 720`).
The extra 80px per side is **bleed** so that a wider phone (`expand` aspect shows more
world) does not run out of table. The bleed is floor, not desk.

**The playfield rect is authoritative, not the art.** The desk edge drawn in
`table.png` is aligned to `Rect2(80, 60, 1120, 600)` exactly, but the physics must read
the constant, never measure the texture. If you ever change the table art, re-align the
art to the rect — not the other way round.

> **Shipped (2026-09-16):** the principle held, and better than stated — the physics reads a rect, never
> the texture. `main.gd:102` holds `TABLE_RECT = Rect2(-590, -320, 1180, 640)` for `TurnState`, and
> `pen_body.gd` independently *discovers* the same rect from `TableBounds`'s `RectangleShape2D`
> (`size = Vector2(1180, 640)` in `main.tscn`). Two paths, one number, no texture measurement. The claim
> that the art is aligned to `Rect2(80, 60, 1120, 600)` was never re-checked against the shipped rect.

---

## 2. Assets shipped

```
assets/sprites/
  src/
    pen_cobalt.svg          P1 pen, vector source
    pen_amber.svg           P2 pen, vector source
    pen_cobalt_shadow.svg   P1 contact shadow silhouette
    pen_amber_shadow.svg    P2 contact shadow silhouette
    table.svg               desk + floor
  pen_cobalt.png            440 × 96  RGBA
  pen_cobalt@2x.png         880 × 192 RGBA
  pen_amber.png             440 × 96  RGBA
  pen_amber@2x.png          880 × 192 RGBA
  pen_cobalt_shadow.png     440 × 96  RGBA
  pen_amber_shadow.png      440 × 96  RGBA
  table.png                 1440 × 840 RGB
  export.sh                 regenerates every PNG from src/
```

> **Pen designs (current, 2026-09):** the four selectable designs are `bic`,
> `jotter`, `sharpie` and `uniball` (`Main.PEN_SKINS`), drawn from
> `game/assets/pen_<design>{,_shadow}.png` — 540 px wide, authored by
> `game/assets/generate_pens_nb2.py` from the photo references and CREDITS in
> `game/assets/nb2/refs/`. The `assets/sprites/` set above is the earlier
> vector-sourced amber/cobalt pair: `main.tscn` still carries amber/cobalt as
> its built-in textures, and `Main._apply_settings()` replaces them at startup
> with the design on each slot — falling back to `Main.DEFAULT_SKINS` when a
> stored save names a design that no longer exists.

### Sprite geometry `[FIXED]`

All four pen/shadow textures share one canvas so that offsets are trivial:

```
440 × 96 canvas
pen occupies x 40…400  (length 360)          <- matches capsule height
barrel centreline at y = 48  (canvas centre) <- matches capsule centre
barrel spans y 38…58   (width 20)            <- matches capsule radius 10
clip protrudes to y ≈ 30                     <- ART ONLY, not collision
```

> **Shipped (2026-09-16):** the canvas is **`540 × 96`**, not `440 × 96`, and the pens are drawn at
> `scale = 0.333333` (`main.tscn`), so one art pixel is one third of a world unit. The centreline
> convention still holds: the barrel axis sits on the body origin and no sprite offset is set. The
> "one texture pixel is one world unit" rule further down is therefore **not** how the build works.

Because the barrel centre sits at the canvas centre, a `Sprite2D` with default
`centered = true` and `offset = (0, 0)` puts the barrel axis exactly on the
`RigidBody2D` origin. **Do not set a sprite offset.**

**Orientation:** the pen lies along **X**, with the **tip at −X (left)** and the cap/plunger
at +X. A capsule is symmetric so this does not affect physics, but keep it consistent —
anything you add later that cares about the tip (ink scuff, a scratch decal) depends on it.

**Start with the 1× textures.** At 1×, one texture pixel is one world unit and every
number in this document works with `scale = 1`. The `@2x` set exists for when you want
crispness on high-DPI panels; switching to it means setting `Sprite2D.scale = (0.5, 0.5)`,
and forgetting that is a classic way to get pens twice the intended size.

### Regenerating

```bash
assets/sprites/export.sh
```

It uses Playwright's `headless_shell`, **not** `chrome --headless`. Full Chrome reserves
~98 px of window height, so `--window-size=1280,600` gives you a ~502 px viewport and
silently crops the bottom of the output. That bug cost real time during art production;
the script avoids it and says why. Override with `HEADLESS_SHELL=/path/to/headless_shell`.

---

## 3. Project settings

Set every one of these. Names are as reported by the research pass.

| Setting | Value | Label |
|---|---|---|
| `display/window/size/viewport_width` | `1280` | `[FIXED]` |
| `display/window/size/viewport_height` | `720` | `[FIXED]` |
| `display/window/stretch/mode` | `canvas_items` | `[TUNE]` |
| `display/window/stretch/aspect` | `expand` | `[TUNE]` |
| `display/window/handheld/orientation` | `landscape` | `[VERIFY]` — Godot has historically ignored this on some versions; confirm on a real device, the editor preview is not authoritative |
| `rendering/renderer/rendering_method` | `mobile` | `[TUNE]` — or `gl_compatibility` for the widest device support; do not leave it on `forward_plus` |
| `rendering/textures/vram_compression/import_etc2_astc` | `true` | `[FIXED]` — Android export fails without it. Set it **before** importing art; if you toggle it afterwards, delete `.godot/` to force a reimport, because the editor's "Fix Import" is buggy here |
| `physics/common/physics_ticks_per_second` | `240` | `[TUNE]` — raised from the 60 default on 2026-09-16: at 60 Hz a full-power flick (1600 px/s) advanced 26.7 px per tick, wider than the ~20 px contact window of two 10 px capsules, so hits on an adjacent pen tunnelled or dead-mushed (user report; regression `game/tests/adjacent_pen_hit_test.gd`). 240 Hz = 6.7 px/tick. Physics CPU is trivial for two bodies |
| `physics/common/max_physics_steps_per_frame` | `16` | `[TUNE]` — 240 Hz needs 8 steps/frame at 30 fps render; keep headroom for slower devices |
| `physics/common/physics_interpolation` | `true` | `[TUNE]` — **turn this on.** It is the correct answer to 90/120 Hz Android panels, and Godot's own refresh-rate handling on Android is unreliable. See the trap in §11 |
| `physics/2d/sleep_threshold_linear` | `2.0` px/s | `[DEFAULT]` |
| `physics/2d/sleep_threshold_angular` | `deg_to_rad(8.0)` | `[DEFAULT]` |
| `physics/2d/time_before_sleep` | `0.5` s | `[DEFAULT]` |
| `physics/2d/solver/solver_iterations` | `16` | `[DEFAULT]` — only raise if contacts feel soft |
| `input_devices/pointing/emulate_mouse_from_touch` | `false` | `[TUNE]` — prevents touch double-firing as synthetic mouse events |

---

## 4. Scene tree

```
Main (Node2D)                       Main.gd
├── Table (Sprite2D)                texture: table.png, position (640, 360)
├── Pens (Node2D)
│   ├── PenA (RigidBody2D)          Pen.tscn, player_id = 1
│   └── PenB (RigidBody2D)          Pen.tscn, player_id = 2
├── TableArea (Area2D)              broad-phase "left the table" trigger
│   └── CollisionShape2D            RectangleShape2D 1120 × 600 at (640, 360)
├── Camera2D                        position (640, 360), ShakeCamera.gd
├── FX (Node2D)                     particle one-shots are spawned here
└── UI (CanvasLayer)                HUD, turn gate, power bar
    ├── HUD (Control)
    └── TurnGate (Control)          full-screen, blocks input between turns
```

> **Shipped (2026-09-16):** the real tree (`game/scenes/main.tscn`) is `Main` → `Background` (Sprite2D),
> `CanvasModulate`, `Table` (Node2D → `Sprite2D` + `TableBounds`), `PenRed` / `PenBlue` (`RigidBody2D` →
> `Shadow` + `Sprite2D` + `CollisionShape2D`), `ExitZone` (Area2D, **no script**) and `Camera2D`. There is
> no `Pens` container, no `FX`, no `UI` layer and no `TurnGate` node — the HUD, the turn gate and the aim
> overlay are built in code, and the shake lives in `game/scripts/feel.gd` rather than a `ShakeCamera.gd`.

`TurnManager` is **not** a node. Put it in a plain GDScript class with no scene-tree or
physics dependency, so it can be unit-tested headlessly in CI. This is the single
structural decision that makes any automated testing of this project possible; retrofitting
it later is the expensive path.

**There are no walls.** Do not add `StaticBody2D` borders around the table — pens are
supposed to leave it. The only collision in the scene is pen-against-pen.

**Collision layers:** both pens on layer `1`, mask `1`. `TableArea` on its own layer,
monitoring layer `1`, with `monitorable = false`.

---

## 5. `Pen.tscn`

> **Shipped (2026-09-16): this scene does not exist.** `game/scenes/` contains `main.tscn` alone; the pens
> are `RigidBody2D` nodes inside it (`PenRed`, `PenBlue`) driven by `game/scripts/pen_body.gd`. The tree
> and values below are still the right *shape* of answer — read them as design intent, and §0.5 for what
> the build actually sets.

```
Pen (RigidBody2D)
├── Shadow (Sprite2D)          drawn FIRST so it sits behind
├── Body (Sprite2D)
└── CollisionShape2D
```

### Node values

| Node | Property | Value | Label |
|---|---|---|---|
| `Pen` | `mass` | `1.0` | `[TUNE]` — keep both pens equal unless you want asymmetric knockback |
| `Pen` | `linear_damp` | `2.0` | `[TUNE]` — range `1.0–4.0` |
| `Pen` | `angular_damp` | `4.0` | `[TUNE]` — range `2.0–6.0`; spin should settle faster than travel. **Shipped: `1.5`** — tuned down so a corner flick keeps spinning |
| `Pen` | `linear_damp_mode` | `Combine` | `[DEFAULT]` — **additive** with the project default `0.1`, so effective damp ≈ `2.1` |
| `Pen` | `can_sleep` | `true` | `[DEFAULT]` |
| `Pen` | `contact_monitor` | `true` | `[FIXED]` |
| `Pen` | `max_contacts_reported` | `4` | `[FIXED]` — **the default is `0`, which reports no contacts even with `contact_monitor` on.** This trips people up constantly |
| `Pen` | `continuous_cd` | `Disabled` | `[TUNE]` — switch to `CCD_MODE_CAST_SHAPE` only if you actually observe tunnelling at high flick speed |
| `Pen.physics_material_override` | `friction` | `0.2` | `[TUNE]` — range `0.1–0.3` |
| `Pen.physics_material_override` | `bounce` | `0.1` | `[TUNE]` — range `0.0–0.2`; real pens thud, they don't click like billiards |
| `Body` | `texture` | `pen_cobalt.png` / `pen_amber.png` | `[FIXED]` |
| `Body` | `centered` / `offset` | `true` / `(0,0)` | `[FIXED]` |
| `Shadow` | `texture` | matching `*_shadow.png` | `[FIXED]` |
| `Shadow` | `position` | `(9, 14)` | `[TUNE]` — local, so it rotates with the pen |
| `Shadow` | `modulate` | `Color(0, 0, 0, 0.44)` | `[TUNE]` |
| `CollisionShape2D` | `shape` | `CapsuleShape2D`, `radius = 10`, `height = 360` | `[FIXED]` — **shipped: `radius = 5.0`, `height = 180.0`** (`main.tscn:12-14`), read off the shape node by `pen_body.gd` |
| `CollisionShape2D` | `rotation` | `PI / 2` | `[VERIFY]` |

### The capsule orientation `[VERIFY]`

`CapsuleShape2D` in Godot 4 is believed to run along **Y** (vertical), so laying it along
the pen's X axis needs `CollisionShape2D.rotation = PI / 2`.

**Resolved (2026-09-16): it does run along Y, and the rotation is in the shipped scene.**
`CollisionShape2D.rotation = 1.5707963` on both pens in `main.tscn`, and `pen_body.gd` reads the capsule's
endpoints as `Vector2(0, ±half_length)` in shape-local space. The `[VERIFY]` can be dropped.

**Check it visually, do not assume.** Run with *Debug → Visible Collision Shapes* on. The
capsule outline must lie along the pen barrel and cover it end to end. If it is
perpendicular, remove the rotation. If it is the right orientation but the wrong length,
`height` may exclude the caps in your engine version — set it so the outline reaches the
tip and the cap end.

Nothing else in this document works if the capsule is wrong, so fix it before continuing.

### `Pen.gd` `[VERIFY — never compiled]`

> **Shipped (2026-09-16):** the sketch below was never compiled as written; its job is done by
> `game/scripts/pen_body.gd`, which integrates through `_integrate_forces` and derives radius and
> half-length from the shape node instead of holding them as constants.

```gdscript
class_name Pen
extends RigidBody2D

@export var player_id: int = 1

## Under both of these, continuously, for SETTLE_HOLD seconds = settled.
const SETTLE_LINEAR  := 6.0    # px/s      [TUNE]
const SETTLE_ANGULAR := 0.25   # rad/s     [TUNE]
const SETTLE_HOLD    := 0.25   # s         [TUNE]
## Above this at any point in a turn, the pen counts as having actually moved.
const MOVED_LINEAR   := 25.0   # px/s      [TUNE]

var _quiet := 0.0
var _moved := false

func _ready() -> void:
    contact_monitor = true
    max_contacts_reported = 4

func _physics_process(delta: float) -> void:
    var lin := linear_velocity.length()
    var ang := absf(angular_velocity)
    if lin > MOVED_LINEAR:
        _moved = true
    _quiet = _quiet + delta if (lin < SETTLE_LINEAR and ang < SETTLE_ANGULAR) else 0.0

func begin_turn() -> void:
    _moved = false
    _quiet = 0.0

func launch(impulse: Vector2) -> void:
    sleeping = false          # a sleeping body ignores impulses
    apply_central_impulse(impulse)

func is_settled() -> bool:
    return sleeping or _quiet >= SETTLE_HOLD

func moved_this_turn() -> bool:
    return _moved

## Both ends of the capsule in global space.
func capsule_ends() -> PackedVector2Array:
    var cap := ($CollisionShape2D as CollisionShape2D).shape as CapsuleShape2D
    var half := maxf(cap.height * 0.5 - cap.radius, 0.0)
    var axis := Vector2.RIGHT.rotated(global_rotation)
    return PackedVector2Array([global_position - axis * half,
                               global_position + axis * half])
```

---

## 6. The table, and when a pen is out

### The out-of-bounds rule — read this before implementing

> **Shipped (2026-09-16): the opposite rule won.** The build ships the **capsule-extents** verdict — "any
> part off" — not centre of mass: a capsule is on the table iff both endpoints of its central segment lie
> inside `TABLE_RECT` shrunk by the capsule radius, relaxed by an `8 px` tolerance so solver jitter at the
> edge does not false-trigger (`game/scripts/pen_body.gd:270-284`, recorded as contract §3.2). The code
> comment says "**never centre-of-mass**" in as many words. Read the argument below as the design
> conversation, not as a plan: the half of the original idea this section was pushing back on — *test the
> capsule extents, not the centre point* — is what shipped, and the "a pen lying half off the desk is a
> pen" intuition was traded away for a verdict that is unambiguous to poll.

The original plan said to *"fix out-of-bounds to test the capsule extents, not the centre
point."* I want to push back on half of that, because getting it wrong changes how the
game feels to play.

A real pen on a real desk does not fall when its front edge crosses the lip. It falls when
its **centre of mass** passes the edge and it tips. A pen lying half off the desk is a
normal, tense, entirely stable situation — and it is one of the better moments in the
physical game.

So:

- **The verdict is centre of mass.** `not playfield.has_point(pen.global_position)` — one line,
  and it is the physically correct rule.
- **The capsule extents are for presentation, not the verdict.** Use them to detect
  "overhanging the edge" so you can tilt the sprite slightly or play a teeter. Optional polish.

The genuine bug in a naive centre-point test is usually not the rule but the *reference*:
testing the sprite's position, or a position that lags a frame behind physics. Test
`global_position` of the `RigidBody2D`, read inside `_physics_process`.

If after playtesting you decide "any part off = out" is more fun, it is a two-line change —
but ship the centre-of-mass rule first and see.

```gdscript
const PLAYFIELD := Rect2(-590, -320, 1180, 640)   # [FIXED] §1 — shipped value, main.gd:102

func is_out(pen: Pen) -> bool:
    return not PLAYFIELD.has_point(pen.global_position)

## Presentation only: is any part of the pen past the edge?
func is_overhanging(pen: Pen) -> bool:
    for p in pen.capsule_ends():
        if not PLAYFIELD.has_point(p):
            return true
    return false
```

### Why `TableArea` exists

Testing two `Rect2.has_point` calls per physics tick costs nothing, so the `Area2D` is not
a performance optimisation. It is there so you get a **signal** at the moment a pen leaves,
which is the natural place to fire the knockout ceremony. Connect `body_exited`. If you
would rather poll in `_physics_process`, that is fine too — delete the `Area2D` and say so.

---

## 7. Turn lifecycle

> **Shipped (2026-09-16):** the "plain class, no scene tree" decision held — `game/scripts/turn_state.gd`
> has no physics or scene dependency and is unit-tested headlessly. The phases are `AIM` / `IN_FLIGHT` /
> `SETTLED` / `ROUND_OVER`; a decided round parks in `ROUND_OVER` behind a gate the player taps through;
> the backstop is `RESOLVE_TIMEOUT = 8.0 s`, not `6.0`; and the **stalemate forfeit is separate from the
> idle forfeit**, which fires at `FORFEIT_TIMEOUT = 15 s` (`main.gd:97`) — "a turn nobody took" is a
> different verdict from "a turn where nothing moved".

One state machine, in a plain class, no scene tree.

```
AIMING ──(release)──> RESOLVING ──(both settled | timeout)──> JUDGING
                                                                 │
                    ┌────────────────────────────────────────────┤
                    │                                            │
            a pen is out                              nobody out
                    │                                            │
                    ▼                                            ▼
              ROUND_OVER                            (neither moved?) ──yes──> forfeit turn
                                                            │no
                                                            ▼
                                                       hand over ──> AIMING (other player)
```

### Settle detection and the stalemate rule are the same mechanism

This is worth stating plainly because it saves you writing two things: the detector that
answers *"has everything stopped?"* also answers *"did anything actually happen?"* A turn
where no pen ever exceeded `MOVED_LINEAR` is a stalemate, and it forfeits.

Use all three of these together — each alone has a failure mode:

| Signal | Fails when |
|---|---|
| `sleeping` / `sleeping_state_changed` | A pen resting against another pen may never quite sleep |
| velocity below threshold | Under low damping a pen can creep below the threshold forever |
| hard timeout | — this is the backstop that makes the other two safe |

```gdscript
const SETTLE_TIMEOUT := 8.0   # s   [TUNE] — shipped as RESOLVE_TIMEOUT (turn_state.gd:83)

var _resolving := 0.0

func _physics_process(delta: float) -> void:
    if state != State.RESOLVING:
        return
    _resolving += delta
    if (pen_a.is_settled() and pen_b.is_settled()) or _resolving >= SETTLE_TIMEOUT:
        _judge()

func _judge() -> void:
    _resolving = 0.0
    if is_out(pen_a):   return _round_over(2)
    if is_out(pen_b):   return _round_over(1)
    if not pen_a.moved_this_turn() and not pen_b.moved_this_turn():
        return _forfeit_turn()      # stalemate
    _hand_over()
```

**`sleeping_state_changed` is only emitted for automatic transitions** — setting
`sleeping = true` yourself does not fire it. That is why the code above polls rather than
relying on the signal.

---

## 8. Input — aim and flick

Handle `InputEventScreenTouch` / `InputEventScreenDrag` **directly**. Do not rely on mouse
emulation (§3 turns it off), and test with two fingers on the screen at once, because in
hot-seat play both players' hands end up over the device.

The interaction is **slingshot drag-back**:

1. Touch down on or near the active pen → begin aiming.
2. Drag away → the launch direction is `pen.global_position - touch_position`, and power is
   proportional to drag distance, clamped.
3. Release → launch.
4. **Release with the touch back over the pen → cancel.** This falls out of the model for
   free; do not build a separate cancel button.

```gdscript
const MAX_DRAG     := 160.0   # px of drag = full power   [TUNE] — shipped (aim_input.gd:50)
const MAX_IMPULSE  := 1600.0  #                           [TUNE, see below]
const CANCEL_RADIUS := 30.0   # px                        [TUNE] — shipped (aim_input.gd:46); the grab zone is the pen capsule + 26 px, not a circle

func _flick_impulse(pen: Pen, touch: Vector2) -> Vector2:
    var pull := pen.global_position - touch
    if pull.length() < CANCEL_RADIUS:
        return Vector2.ZERO                      # cancelled
    var power := clampf(pull.length() / MAX_DRAG, 0.0, 1.0)
    return pull.normalized() * power * MAX_IMPULSE
```

### Deriving `MAX_IMPULSE` instead of guessing it `[TUNE]`

Tune damping **first**, then `MAX_IMPULSE` last, against the damping you settled on.
For a body with mass `m` and linear damp `d` under roughly exponential decay, a flick
travels approximately:

```
distance ≈ impulse / (mass × damp)
```

With `mass = 1.0` and effective `damp = 2.1` (your `2.0` plus the project default `0.1`),
a full-power flick crossing ~70 % of the 1120-px table (≈ 780 px) needs — **the shipped table is
`1180 px` wide, so re-derive against that**
`impulse ≈ 780 × 1 × 2.1 ≈ 1640` — hence the starting value of `1600`.

This is an approximation, not a derivation from Godot's integrator. Its value is that when
you change `linear_damp`, you can re-derive `MAX_IMPULSE` in one line instead of
re-guessing.

### No trajectory prediction

Draw the drag line, a power bar, and a **short** heading arrow. Do **not** draw a predicted
path. The skill ceiling of this game depends on the player estimating the outcome; 8 Ball
Pool's aiming guideline exists because pool geometry is genuinely hard to do in your head,
and a straight-line flick is not.

Mark `MAX_IMPULSE` on the power bar so a player can feel where the clamp is (see the
in-game reference image — the `MAX` tick).

---

## 9. The feel layer

> **Shipped (2026-09-16):** items 1–5, 7 and 8 are in (`game/scripts/feel.gd`, `audio.gd`, `haptics.gd`).
> **Item 6, particles, is not built** — there is no particle system anywhere in `game/`. The ordering
> constraint below is honoured in the build: the ceremony fires once per *decided* round, after the
> verdict, and the hit-stop keeps its own master switch separate from screen shake.

Ranked by effect per hour of work. **Build them in this order.** Items 1–4 are most of
the perceived quality.

| # | Effect | Numbers | Notes |
|---|---|---|---|
| 1 | **Turn hand-over gate** | full-screen, input locked, tap to continue | Fixes the commonest hot-seat failure — a player flicking on the wrong turn. Nearly free once §7 exists |
| 2 | **Trauma screen shake** | `trauma += clamp(impulse / IMPULSE_REF, 0, 1)`; `offset = max_offset × trauma²`; `max_offset = 10 px`; `max_roll = 3°`; decay `2.0`/s | `trauma²` decay, not a fixed sine. ~1–2 hours for the cheapest "the world reacted" signal |
| 3 | **Hit-stop** | `Engine.time_scale = 0.02` for `50 ms` normal / `130 ms` knockout | **Never `0.0`** — that reportedly produces duplicate collisions when time resumes |
| 4 | **Layered impact sound** | transient click + body thud + slide loop; pitch randomised `±5–10 %`; volume and pitch mapped to collision impulse | Biggest audio return. Pitch randomisation is what stops it sounding like a machine gun |
| 5 | Audio buses | `Master / SFX / Music` from day one | The settings toggle becomes one `AudioServer` call. Cheap now, annoying to retrofit |
| 6 | Impact particles | 8–15 particles, lifetime `0.3–0.6 s`, `one_shot = true`, `explosiveness = 1.0`, at the contact point | Pool these; do not `instantiate()` mid-turn |
| 7 | Knockout ceremony | `150–200 ms` hit-stop, slow-mo camera follow on the falling pen, then the score tick | **Make it skippable after round 2.** Great at round 3, friction by round 15 |
| 8 | Haptics | `~10–30 ms` on impact, longer on loss | See the caveat below |

### The ordering constraint that will bite you

**Resolve the win condition before the ceremony plays.**

Hit-stop and slow-motion perturb the simulation. If the knockout ceremony is running while
`_judge()` is still deciding, the ceremony can change who won. Decide the outcome first
(§7), *then* play the presentation over an already-settled result. The ceremony is a
rendering of a decision, never part of making it.

### Camera shake `[VERIFY — never compiled]`

```gdscript
extends Camera2D

const MAX_OFFSET   := 10.0
const MAX_ROLL_DEG := 3.0
const DECAY        := 2.0

var _trauma := 0.0
var _rng := RandomNumberGenerator.new()

func add_trauma(amount: float) -> void:
    _trauma = clampf(_trauma + amount, 0.0, 1.0)

func _process(delta: float) -> void:
    if _trauma <= 0.0:
        offset = Vector2.ZERO
        rotation = 0.0
        return
    _trauma = maxf(_trauma - DECAY * delta, 0.0)
    var t := _trauma * _trauma
    offset = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * MAX_OFFSET * t
    rotation = deg_to_rad(MAX_ROLL_DEG) * t * _rng.randf_range(-1.0, 1.0)
```

### Hit-stop `[VERIFY — never compiled]`

```gdscript
func hit_stop(seconds: float) -> void:
    Engine.time_scale = 0.02
    await get_tree().create_timer(seconds, true, false, true).timeout
    Engine.time_scale = 1.0
```

`[VERIFY]` The fourth argument to `create_timer()` is believed to be `ignore_time_scale`.
Confirm the signature in your engine version — if the timer is affected by `time_scale`,
the freeze lasts 50× too long and the game will appear to hang.

### Haptics `[VERIFY]`

`Input.vibrate_handheld(duration_ms, amplitude)` — **the amplitude parameter is unconfirmed**,
and may be ignored or absent depending on version and platform. Also:

- The **Vibrate permission must be enabled in the Android export preset**, or the call may crash.
- The OS-level haptics setting **cannot be queried**, so ship an in-game toggle and default it on.

Verify on hardware before designing anything around haptic nuance. Treat it as "a buzz is
available" until proven otherwise.

---

## 10. Build order, with acceptance criteria

> **Shipped (2026-09-16):** steps 1–10 are done. Step 11 — the 20-round test — is the open gate
> (`docs/design/feature-priorities.md` rank 2), and it is now instrumented: the build prints the loop's
> own numbers (`docs/design/core-loop.md` §Re-check). Treat this section as a checklist you can re-run,
> not as work outstanding.

Do not start a step until the previous one passes. Each criterion is something you can
physically check.

| # | Step | Done when |
|---|---|---|
| 1 | Commit the existing Godot skeleton to the repo | `git ls-files` shows `project.godot`, scenes and scripts. **Nothing in the repository is a game yet — this blocks everything** |
| 2 | Apply §3 project settings | The project runs at 1280×720 and the window letterboxes correctly when resized |
| 3 | Build `Pen.tscn` per §5 | With *Visible Collision Shapes* on, the capsule lies along the barrel, tip to cap. §5's `[VERIFY]` resolved |
| 4 | Place the table and both pens per §4 | The desk edge in the art coincides with `Rect2(80, 60, 1120, 600)`. Drop a temporary marker at each rect corner to confirm. **Shipped rect: `Rect2(-590, -320, 1180, 640)`** — this visual check is still unrecorded |
| 5 | Flick input (§8) | A drag launches the pen; releasing over the pen cancels; hard flicks visibly differ from soft ones |
| 6 | Damping pass | A full-power flick crosses ~70 % of the table and stops. Tune `linear_damp`, then re-derive `MAX_IMPULSE` |
| 7 | Settle + stalemate (§7) | Turns end reliably. A deliberate zero-power flick forfeits. A pen resting against the other pen still ends the turn |
| 8 | Out-of-bounds (§6) | Pushing a pen off the edge ends the round for the right player. A pen hanging half off does **not** lose |
| 9 | Turn gate (feel #1) | Two people can play ten rounds without either flicking on the wrong turn |
| 10 | Shake + hit-stop + sound (feel #2–4) | Impacts feel like impacts |
| 11 | **The 20-round test** | You and one other person play 20 rounds and want a 21st. If not, stop and rethink the mechanic before building anything else |

Step 11 is a real gate, not a formality. Everything after it — match structure, menus,
build pipeline, monetization — is wasted if the core does not pass.

---

## 11. Traps

Each of these has bitten this kind of project before.

1. **`max_contacts_reported` defaults to `0`.** `contact_monitor = true` alone reports nothing.
2. **Physics interpolation requires discipline.** With it on, every transform write must
   happen in `_physics_process`, and any teleport or reposition must be followed by
   `reset_physics_interpolation()` — otherwise the pen visibly smears across the screen from
   its old position. Turn it on now, while the codebase is small.
3. **Do not add walls.** Pens must be able to leave the table.
4. **Do not use `Light2D` or 2D shadows.** As few as ~5 dynamic lights measurably costs FPS
   on Android. The contact shadow is a baked sprite; that is the whole shadow system.
5. **Do not lower `physics_ticks_per_second` for slow motion.** It changes *what happens*, not
   just how fast you watch it. Use `Engine.time_scale`.
6. **Do not `instantiate()` during a turn.** Pool particles and audio players; warm the pool
   during the loading screen.
7. **Enable ETC2/ASTC before importing art** (§3), or you get a confusing reimport bug later.
8. **The engine version is a hard gate.** Godot 4.3 and 4.4 emit `.so` files that are not
   16 KB-page aligned, which Google Play has blocked at upload since 2025-11-01 — and it is
   not caught at export time, only at upload. 4.5.2–4.6.2 carry an Android stretch-mode
   regression that pushes UI off-screen. Pin **4.7.x**. See `docs/RESEARCH.md` §3.1.
9. **Godot 2D physics is not deterministic**, run-to-run on the same machine. Do not build
   replays by re-simulating recorded inputs, and do not plan lockstep netcode. Record
   trajectories instead. This also blocks impulse-search AI on the stock backend.

---

## 12. Where the rest of the reasoning lives

- `docs/RESEARCH.md` — synthesis: engine version gate, the revised phase order, the market case.
- `docs/research/03-graphics.md` — why flat 2D, texture import settings, the cheap-polish list.
- `docs/research/04-physics-fps.md` — tick rate, interpolation, determinism, damping, settle detection, every number in §5 with its source.
- `docs/research/05-feel-polish.md` — the full feel toolkit, the 20-round playtest protocol.
- `assets/design/pen-design-sheet.png` — pen construction, callouts, collider-vs-art.
- `assets/design/pen-fight-table.png` — the target in-game look.
