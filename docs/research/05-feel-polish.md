# Game Feel & Polish — Pen Fight

Target: Godot 4.x, GDScript, Android, hot-seat 2-player, capsule RigidBody2D pens, table-top knockoff.
Convention used throughout: **[EST]** = established practice from cited sources. **[REC]** = my recommendation for this specific game, not sourced.

---

## 1. Game feel fundamentals applied to a flick game

### Sources
- Steve Swink, *Game Feel* (2009) — book, no single URL; concepts: real-time control, polish, metaphor, input→response tightness.
- Jan Willem Nijman (Vlambeer), "The Art of Screenshake," INDIGO Classes 2013 — [YouTube](https://www.youtube.com/watch?v=AJdEqssNZ-U), interactive version on [Internet Archive](https://archive.org/details/the-art-of-screenshake).
- Martin Jonasson & Petri Purho, "Juice it or Lose It," GDC Europe 2012 — [YouTube](https://www.youtube.com/watch?v=Fy0aCDmgnxg), [GDC Vault](https://www.gdcvault.com/play/1016487/juice-it-or-lose).
- Squirrel Eiserloh, "Math for Game Programmers: Juicing Your Cameras With Math," GDC 2016 — [transcript](https://archive.org/stream/GDC2016Eiserloh/GDC2016-Eiserloh_djvu.txt).

### [EST] Techniques that generalize to a turn-based impulse duel

Both Vlambeer's and Purho/Jonasson's talks make the same core claim demonstrated live on *Breakout*: no single effect matters much, but effects **compound**, and the cheapest ones (screen shake, squash/stretch, particles, sound layering, camera lag) give the largest perceived-quality jump per dev-hour. Nijman's list (~30 tricks) is aimed at continuous action (Nuclear Throne); a turn-based game gets a *subset* because there's no player character to animate idly and no continuous fire — the payoff windows are narrow and discrete: **release** and **impact**. That concentration is actually good news: you don't need 30 tricks, you need 6-8 done well at 2 moments.

### Ranked by effect-per-hour-of-work for this game

| Rank | Technique | Moment | Est. build time | Why it ranks here |
|---|---|---|---|---|
| 1 | Screen shake (trauma-based) | On pen-pen impact, scaled by impulse | 1–2 hrs | Cheapest possible "the world reacted" signal; camera-only code, no art needed |
| 2 | Hit-stop / freeze-frame (2–6 frames) | On impact | 1–2 hrs | One `Engine.time_scale` dip; makes weightless RigidBody collisions read as *weighty* |
| 3 | Squash & stretch on the pen body | Continuously, driven by velocity/angular velocity | 2–4 hrs | Turns a rigid capsule into something that reads as material (Swink's "polish" layer) — needs a shader or a Sprite2D scale hack since a real RigidBody2D collision shape shouldn't be squashed |
| 4 | Impact particles (burst, 8–15 sprites) | On impact, spawn at contact point | 2–3 hrs | Godot's `GPUParticles2D` one-shot burst is trivial and reads instantly as "something hit something" |
| 5 | Sound layering (transient + body + tail) | Release + impact + slide | 3–5 hrs (mostly asset sourcing) | Purho/Jonasson: sound is one of the highest-return juice categories because humans are extremely sensitive to audio-visual sync |
| 6 | Camera punch-in / follow on knockout | Pen falls off table | 2–3 hrs | Payoff moment — see §7 |
| 7 | Color flash / outline flash on hit object | On impact, 1–3 frames | 1 hr | Cheap silhouette-pop; diminishing returns once shake+particles exist |
| 8 | Haptics | Release, impact, loss | 2–4 hrs (Android-only complexity, see §4) | High value on a physical device you're literally slapping the table with, but platform-limited and needs a fallback/toggle |
| 9 | Trail/motion-blur on fast-moving pen | During flight | 3–6 hrs | Nice-to-have; RigidBody2D pens moving across a small table are on-screen briefly, so payoff is lower than impact-moment effects |
| 10 | Chromatic aberration / radial blur on big hits | Impact | 3–5 hrs (shader work) | Highest cost of the visual effects, most easily overdone; do last if at all |

**[REC]** Build rank 1–5 before anything else touches the project. That is the entire "juice pass" Vlambeer describes doing to *Breakout* in their talk, and it is achievable in a single day. Ranks 6–10 are the difference between "feels good" and "feels great," worth doing only after the 20-round test (§8) confirms the core loop itself is fun.

### Concrete magnitudes to start from (all [REC], tune from here)

| Effect | Starting value |
|---|---|
| Hit-stop duration | 3–5 frames at 60fps (50–80ms) for a normal hit; 8–10 frames (130–160ms) for the knockout hit |
| Screen shake trauma add per hit | `trauma = clamp(impulse_magnitude / max_expected_impulse, 0, 1)` — cap at 1.0 |
| Screen shake max offset | 8–12 px at trauma=1 on a phone screen (scale with resolution) |
| Screen shake max rotation | 2–4° at trauma=1 |
| Impact particle count | 8–15 |
| Impact particle lifetime | 0.3–0.6s |

---

## 2. The aiming and release interaction

### Survey of existing flick/pool games

| Game | Aim input | Power input | Aim feedback shown | Aim assist |
|---|---|---|---|---|
| **8 Ball Pool** (Miniclip) | Drag anywhere on screen to rotate cue/guideline (or dedicated "Aiming Wheel") [EST] | Separate power bar dragged downward, independent of aim gesture [EST] | Full guideline from cue ball through target ball, **plus predicted post-collision paths of both balls** [EST] | None needed — guideline *is* the assist; skill gate is power/spin control | [Miniclip support](https://support.miniclip.com/hc/en-us/articles/203747546-How-to-Aim-with-the-Cue-8-Ball-Pool), [basic controls](https://support.miniclip.com/hc/en-us/articles/35451942766865-Basic-Controls-Improving-your-skills-8-Ball-Pool) |
| **Carrom Pool** (Miniclip) | Drag the striker to aim | Same drag distance sets power (pull-and-release, single gesture) [EST] | In-game guideline; players are told to scale flick strength to shot distance [EST] | Guideline only | [Miniclip beginner guide](https://support.miniclip.com/hc/en-us/articles/4404675218577-How-to-Start-Playing-Carrom-Pool-A-Beginner-s-Guide) |
| **Angry Birds** | Drag bird back in slingshot (pull direction = launch direction, inverted) | Pull distance = power, single gesture | **No live prediction on the current shot** — instead it shows a dotted trail from the *previous* shot as a reference the player can match or adjust [EST] | None on the live shot; the retained trail is a form of "aim memory" not literal prediction | [Angry Birds Wiki](https://angrybirds.fandom.com/wiki/Slingshot), [AngryBirdsNest forum](https://www.angrybirdsnest.com/forums/topic/trajectory-dots-not-always-right/) |
| **Golf Battle / Golf Clash-likes** | Drag-back slingshot for direction, separate power meter (often a rising/falling bar you tap to stop) | Tap-to-stop power meter is the norm for golf mobile games (general genre convention, [EST] from category norms, not independently verified per-title here) | Full arc/trajectory line, adjustable wind indicator | Meter itself is the assist — timing skill replaces stick precision |
| **Flick Kick Football** | Drag-back-and-release slingshot on the ball | Pull distance = power | Minimal — mostly power/direction only, deliberately less assisted for a "skill" feel | Low |
| **Crossy Road** | Discrete swipe (one direction unit per swipe), not a drag-and-release analog gesture | N/A — no power, movement is grid-stepped | None (deterministic move) | N/A — different genre (it's not an impulse/physics game) |

### Drag-back-and-release vs drag-forward-push vs tap-hold-power-meter

**[EST]** The dominant pattern across every physics duel/pool-style game surveyed is **drag-back-and-release (slingshot)**, not drag-forward-to-push. Reasons visible across all of them:
- It maps 1:1 to the real-world mental model (pull back a slingshot, pull back a cue) — Swink's "metaphor" layer of game feel comes for free.
- It keeps the player's finger *off* the object being launched during the critical release instant, avoiding finger-occlusion of the aim point.
- It naturally produces a **cancel gesture**: releasing at zero pull distance (returning finger to the object) is a null flick, which is exactly the abort mechanism you'd want to add explicitly.

**Tap-and-hold-power-meter** (own separate gesture) is used when direction and power need independent precision curves — most common in golf-style games where direction is a fixed camera-relative arc and power needs fine timing skill. It adds a **second input phase**, which is more information overhead than a duel needs.

**Drag-forward-to-push** is rare in this genre because it inverts the "wind up" reading: the eye/hand naturally winds back before releasing energy forward (true of throwing, slingshots, pool cues, and archery — but not for e.g. a rifle-shot which uses hold-to-charge instead), so it fights the physical metaphor.

### Aim assist — does a physics duel need it?

**[REC]** No trajectory-prediction aim assist. The category leaders that show a live predictive line (8 Ball Pool) do so because pool trajectories after the first bounce are legitimately hard to compute mentally (physics-based cushion rebounds), and the skill ceiling is deliberately in *reading the guideline and executing precisely*, not in mental physics. Pen Fight's shots are single, short, straight-line impulses on an open table with no bank shots off walls (per the concept: launch across a table to knock the opponent off) — the "physics" a human needs to predict is trivial (a straight line from pull vector), so a drawn trajectory line would remove the entire skill expression the game has. Angry Birds' choice (show only the *previous* shot's ghost trail, not a live prediction) is the right reference point: it gives calibration without solving the aim for the player.

### What to show before commit

**[REC]** Minimum viable feedback, in priority order:
1. A **direction line/arrow** from the pen to the current drag point, so the player can confirm they're launching the way they intend — not a trajectory curve, just current-aim direction (this is not "assist," it's basic input legibility).
2. A **power indicator** tied to pull distance — either the line's length/thickness or a small numeric/bar readout, capped at a max pull distance so power cannot be pulled off-screen.
3. **No physics-preview arc.** Keep it a pure vector — this preserves the skill and matches Angry Birds/Carrom Pool's actual minimalism, not the pool-specific full-prediction case.
4. Optionally, after the *first* shot each match, show a faint ghost of the previous flick's direction/power (Angry Birds' trick) as a calibration aid without solving the aim.

### Cancel gesture

**[REC]** Yes, include one — it's nearly free given the slingshot model. Recommended rule: if the player drags back and then returns their finger to within some small radius (e.g. 20–30 px) of the pen's own position before releasing, treat it as a cancelled flick (no launch, reset aim UI). This matches how real slingshot games avoid "fat-finger" accidental launches and is the natural inverse of the pull gesture — no separate UI element needed.

---

## 3. Feedback at the moment of impact (the 200ms window)

### [EST] Standard toolkit, and why trauma > fixed sine for shake

Eiserloh's talk (GDC 2016) is the canonical source for trauma-based shake: maintain a `trauma` float in [0,1], raise it on impact events, decay it every frame, and compute the actual shake magnitude as `trauma^2` (or higher exponent) rather than trauma linearly. The squared relationship means small hits barely shake the camera while big hits shake disproportionately more — this reads as "punchy" because human perception of impact severity is itself non-linear, whereas a fixed-amplitude sine wave gives every hit the same "size" of shake regardless of how hard it actually was, which flattens the emotional read of a fight (every hit feels the same). Trauma decay additionally lets multiple hits *stack* naturally (a flurry of small impacts can compound into big visible shake) which a per-event fixed-duration sine cannot do without manual layering logic.
Sources: [Eiserloh GDC 2016 transcript](https://archive.org/stream/GDC2016Eiserloh/GDC2016-Eiserloh_djvu.txt), community Godot ports: [Godot 4 Recipes — Screen Shake](https://kidscancode.org/godot_recipes/4.x/2d/screen_shake/index.html), [Borderline Blog trauma-based writeup](http://blog.borderline.games/tutorials/gettinghit!/trauma-based-screenshake.html).

### The 200ms breakdown

| Effect | Timing | Magnitude to start | Godot 4 mechanism |
|---|---|---|---|
| Hit-stop / freeze | t=0, hold 50–160ms depending on hit size | `Engine.time_scale` dropped near-zero (not exactly 0 — see caveat below), then tweened/timed back to 1.0 | `Engine.time_scale = 0.02` then `await get_tree().create_timer(duration_real_sec).timeout` using **unscaled** timer, then restore. Use `Engine.time_scale`, not `get_tree().paused`, because pausing the tree stops the very Tweens/timers you'd use to end the freeze |
| Screen shake | Starts t=0, decays ~0.3–0.6s | `trauma = clamp(impulse/impulse_ref, 0, 1)`; offset = `max_offset * trauma^2 * randf_range(-1,1)` per axis; rotation similarly | `Camera2D.offset` set per-frame in `_process`; trauma decayed via `trauma = max(trauma - decay_rate * delta, 0)`, decay_rate ≈ 1.5–2.5/sec |
| Camera punch/zoom | t=0 to ~150ms | Zoom in ~3–8%, ease back over 150–250ms | `Tween` animating `Camera2D.zoom` |
| Impact particles | Spawn at t=0 | 8–15 particles, 0.3–0.6s lifetime, one-shot burst at contact point, direction biased away from surface normal | `GPUParticles2D` with `one_shot = true`, `explosiveness = 1.0`, `emitting = true` set on the frame of collision; [Godot 4 particles guide](https://godot-mcp.abyo.net/guides/godot4-particles) |
| Flash / outline | 1–3 frames | White or high-contrast flash on the struck pen, or an outline-shader pop | `CanvasItem.modulate` flashed via Tween, or a `CanvasItem.material` shader toggling an outline uniform |
| Chromatic/radial blur | Big hits only, ≤150ms | Small, subtle (this is the most-overdone effect in the list) | A `CanvasLayer`-wide `ColorRect` with a shader, driven by a Tween'd shader param |
| Sound: transient click | t=0, instant | Short (<50ms) high-frequency "tick" for the initial contact | `AudioStreamPlayer2D.play()` |
| Sound: body thud | t=0–20ms | Low-mid frequency thump, volume/pitch mapped to impulse (§5) | Same node or a second player, layered |
| Sound: slide loop | Starts as pen decelerates, fades out | Looping stream, volume tied to current linear velocity | `AudioStreamPlayer2D` with a looping `AudioStream`, volume set every physics frame from `RigidBody2D.linear_velocity.length()` |
| Haptics | t=0, ~10–30ms pulse for normal hit, longer for KO | See §4 | `Input.vibrate_handheld(duration_ms, amplitude)` |

**Caveat on hit-stop with RigidBody2D physics:** dropping `Engine.time_scale` all the way to 0 is known to cause Godot's physics engine to register spurious/duplicate collisions on the frame time resumes, per community reports ([Godot Forum thread](https://forum.godotengine.org/t/how-to-frame-freeze-without-pausing-entire-game/85550)). **[REC]** use a very small non-zero value (e.g. `0.02`) rather than exactly `0.0`, and keep the freeze short (≤160ms) so it reads as a freeze without meaningfully perturbing the simulation.

### GDScript sketch (trauma shake + hit-stop), [REC] starting point

```gdscript
# Camera2D script (or an autoload the camera reads from)
var trauma := 0.0
var trauma_decay := 2.0
var max_offset := 10.0
var max_roll_deg := 3.0
var rng := RandomNumberGenerator.new()

func add_trauma(amount: float) -> void:
    trauma = clamp(trauma + amount, 0.0, 1.0)

func _process(delta: float) -> void:
    if trauma > 0.0:
        trauma = max(trauma - trauma_decay * delta, 0.0)
        var t := trauma * trauma
        offset = Vector2(
            rng.randf_range(-1.0, 1.0),
            rng.randf_range(-1.0, 1.0)
        ) * max_offset * t
        rotation = deg_to_rad(max_roll_deg) * t * rng.randf_range(-1.0, 1.0)
    else:
        offset = Vector2.ZERO
        rotation = 0.0

# On collision:
func _on_pen_collision(impulse: float) -> void:
    add_trauma(clamp(impulse / IMPULSE_REF, 0.0, 1.0))
    _hit_stop(0.05 if impulse < IMPULSE_REF else 0.13)

func _hit_stop(seconds: float) -> void:
    Engine.time_scale = 0.02
    await get_tree().create_timer(seconds, true, false, true).timeout  # ignore_time_scale = true
    Engine.time_scale = 1.0
```

(`create_timer`'s 4th positional arg makes it ignore `time_scale` in Godot 4 — verify the exact `SceneTreeTimer` signature against your engine version before shipping; this is the mechanism, confirm signature in your installed Godot's docs.)

---

## 4. Haptics on Android from Godot 4

### What `Input.vibrate_handheld()` actually offers [EST]

- Signature (Godot 4, current): `Input.vibrate_handheld(duration_ms: int = 500, amplitude: float = -1.0) -> void`. `amplitude` is 0.0–1.0; `-1.0` (default) uses the platform's default vibration strength. Confirmed via the C# binding surface (`VibrateHandheld(int durationMs = 500, float amplitude = -1)`) and the amplitude proposal history.
- **Amplitude support is Android/iOS/Web but with caveats**: the underlying Android implementation passes duration and amplitude straight to `godot_java->vibrate(duration_ms, amplitude)` in `os_android.cpp`, mapping onto Android's `VibrationEffect.createOneShot(timing, amplitude)` (amplitude 1–255 on the Android side; Godot's float 0–1 is remapped). On Web, amplitude cannot be changed at all (browsers don't expose amplitude control) — duration only. On iOS pre-13, duration itself isn't respected either.
  Sources: [godot-proposals #9582](https://github.com/godotengine/godot-proposals/issues/9582), [os_android.cpp](https://github.com/godotengine/godot/blob/master/platform/android/os_android.cpp).
- **Limitations**: no built-in support for Android's predefined effects (`VibrationEffect.EFFECT_CLICK`, `EFFECT_TICK`, `EFFECT_DOUBLE_CLICK`, `EFFECT_HEAVY_CLICK`) and no waveform/pattern API (`createWaveform` with an array of timings+amplitudes+repeat-index) — Godot only exposes the one-shot duration+amplitude call. There is also a known crash bug: calling `vibrate_handheld` on Android **without the VIBRATE permission enabled crashes the app** rather than silently no-op'ing (tracked as [godot#103496](https://github.com/godotengine/godot/issues/103496)) — this makes the manifest permission a hard requirement, not an optional nicety.

### Manifest permission [EST]

In the Android export preset (Project → Export → Android preset → Options → Permissions), check **"Vibrate."** This causes Godot's build to inject `<uses-permission android:name="android.permission.VIBRATE"/>` into the generated `AndroidManifest.xml` automatically — no manual manifest editing needed with Godot's built-in Gradle/export build. Forgetting this checkbox is the most common cause of "vibration doesn't work" reports, and per the bug above, on current Godot it can crash rather than just fail silently. Source: [Godot export docs discussion / forum](https://forum.godotengine.org/t/how-to-implement-android-vibration/19983), [godot#31670](https://github.com/godotengine/godot/issues/31670).

### Getting finer control than Godot's native API [EST]

Godot's native call cannot reach Android's predefined effects or waveform patterns. Options, in order of effort:
1. **Community GDExtension/plugin wrappers** exist (e.g. [`Shin-NiL/Godot-Mobile-Vibration`](https://github.com/Shin-NiL/Godot-Mobile-Vibration), [`pkruszynski/godot-vibration-plugin`](https://github.com/pkruszynski/godot-vibration-plugin), [`literaldumb/GodotVibrate`](https://github.com/literaldumb/GodotVibrate)) that call `VibrationEffect.createWaveform`/predefined constants directly via JNI/Android plugin singletons. These are third-party and unmaintained-risk; vet before depending on one.
2. **Write a small custom Android plugin** (Godot Android plugin template) calling `Vibrator`/`VibratorManager.getDefaultVibrator().vibrate(VibrationEffect.createWaveform(timings, amplitudes, repeat))` directly — the correct approach if you actually need pattern haptics, but is real Android/Kotlin/Java work outside GDScript.
3. **Fake pattern haptics from GDScript** by chaining multiple `vibrate_handheld()` calls with `await get_tree().create_timer()` gaps — crude, imprecise (Godot's call has its own dispatch latency), acceptable for the simple pattern this game needs.

### [REC] Working pattern for this game

Given the game only needs three distinct feels (light tick / sharp thud / long buzz), native `vibrate_handheld` with amplitude is **sufficient** — a custom plugin is not worth building for this scope.

```gdscript
# Autoload: Haptics.gd
var enabled := true  # exposed as a settings toggle, persisted

func light_tick() -> void:
    if enabled:
        Input.vibrate_handheld(15, 0.35)   # release

func sharp_thud(impulse_normalized: float) -> void:
    if enabled:
        Input.vibrate_handheld(25, clamp(0.4 + impulse_normalized * 0.6, 0.4, 1.0))  # collision

func long_buzz() -> void:
    if enabled:
        Input.vibrate_handheld(220, 0.8)   # loss / knockout
```

Values (15/25/220ms, 0.35/0.4–1.0/0.8 amplitude) are starting points to tune by feel on a real device — Android vibration motors vary a lot device to device, and amplitude scaling is approximate.

### System-disabled haptics and the in-game toggle [REC]

Some users disable "Touch vibration" / "System haptics" at the OS level. Godot's `vibrate_handheld` has **no way to query whether the OS setting is on** — the call simply does nothing observable if the system has haptics off, so you cannot detect and auto-hide a toggle; you must always show your own in-game haptics toggle (defaulting on) regardless of the OS setting, both because (a) some players want haptics off in *this* game specifically even with them on system-wide (e.g., playing at night on a table, where every collision buzzing a phone against wood is audible and annoying), and (b) you cannot rely on OS state at all. Persist the toggle (e.g. via `ConfigFile` or a simple save file) and gate every haptics call through it, as in the `Haptics.gd` sketch above.

---

## 5. Audio

### Layering strategy [EST general practice, applied REC to this game]

Standard three-layer impact sound design (used broadly across physics/sports games): a **transient** (very short, high-frequency "tic"/"tok" that gives the ear a precise timing anchor for the exact contact frame), a **body** (the low-mid "thud"/"clack" that carries perceived mass/material), and a **tail** (longer decay or, here, a **slide loop** for the pens sliding on the table surface). This is the same three-part decomposition sound designers use for footsteps, punches, and ball-sport contact (general practice; not tied to one specific citation, standard in game audio production).

### Pitch randomization [EST]

Playing the exact same sample on every hit produces the "machine-gun" repetition effect very quickly, especially in a game with many small taps/collisions. Standard fix: randomize pitch ±5–10% per play (`pitch_scale` in Godot) and, if you have >1 sample recorded per sound category, round-robin between 2–4 variations chosen at random. This is baseline practice across virtually all game audio implementation guides.

```gdscript
func play_hit(player: AudioStreamPlayer2D, impulse_normalized: float) -> void:
    player.pitch_scale = randf_range(0.92, 1.08)
    player.volume_db = linear_to_db(clamp(0.3 + impulse_normalized * 0.7, 0.1, 1.0))
    player.play()
```

### Mapping collision impulse to volume/pitch [REC]

- **Volume**: linear or slight-curve map from normalized impulse magnitude (impulse / expected max impulse) to `volume_db` via `linear_to_db()`, floor around 0.1–0.2 linear so even the softest taps are audible, ceiling at 1.0.
- **Pitch**: harder hits often read better slightly *lower*-pitched (more mass/weight), softer hits slightly higher — an inverse micro-relationship layered on top of the ± random jitter, e.g. `pitch_scale = randf_range(0.92,1.08) - impulse_normalized * 0.05`.

### Slide loop tracking velocity [REC]

```gdscript
# On each pen, physics_process while linear_velocity.length() > threshold
func _physics_process(_delta):
    var speed := linear_velocity.length()
    if speed > slide_threshold:
        if not slide_player.playing:
            slide_player.play()
        slide_player.volume_db = linear_to_db(clamp(speed / max_speed, 0.0, 1.0))
    elif slide_player.playing:
        slide_player.stop()
```

### `AudioStreamPlayer` vs `AudioStreamPlayer2D` [EST]

`AudioStreamPlayer` is non-positional (best for UI sounds and music); `AudioStreamPlayer2D` attenuates/pans by distance from the audio listener/camera and is intended for sound effects tied to a world position. For a single-screen top-down table view where both pens are always fully visible and close together, **[REC]** positional attenuation buys little (the whole table fits on screen, distances are small), but using `AudioStreamPlayer2D` on each pen is still worth doing for the minor stereo panning it gives (sound appears to come from the side of the screen the collision happened on), which reinforces "something happened over there" — cheap and free. Use `AudioStreamPlayer` for all UI/menu/music/turn-transition stingers. Source: [Godot audio streams docs summary via search](https://docs.godotengine.org/en/stable/tutorials/audio/audio_streams.html).

### Audio bus setup for a one-line settings toggle [EST]

Standard structure: Master bus with two children, **Music** and **SFX** (add via the Audio panel, "+ Add Bus", then set each bus's parent to Master). Assign every `AudioStreamPlayer`/`AudioStreamPlayer2D` node's `bus` property to the matching bus name. A settings screen then needs only:

```gdscript
func set_sfx_enabled(on: bool) -> void:
    var idx := AudioServer.get_bus_index("SFX")
    AudioServer.set_bus_mute(idx, not on)

func set_music_volume(linear: float) -> void:
    var idx := AudioServer.get_bus_index("Music")
    AudioServer.set_bus_volume_db(idx, linear_to_db(linear))
```

Remember to save the bus layout as a `.tres` and confirm it's assigned as the project's Default Bus Layout under Project Settings → Audio → Buses, or the buses won't exist at runtime and `get_bus_index` calls will silently fail. [EST source](https://inglo-games.github.io/2020/04/22/audio-busses.html) and multiple tutorials converge on this exact structure.

### Godot audio latency setting on Android [EST]

The project setting is **`audio/driver/output_latency`** (Project Settings → Audio → Driver → Output Latency), a millisecond value. The engine's built-in default is **15ms**. On Android specifically this setting has known reliability problems: multiple current forum threads and an open engine issue ([godot#108204](https://github.com/godotengine/godot/issues/108204), filed against recent 4.x) report that on Android the setting **has no measurable effect on real output latency**, and Android audio in general has a persistent extra delay that's been reported since 2023 and is still open in 2026 discussion threads. Practical implication: **[REC]** do not spend calibration effort chasing sub-frame audio-sync tightness on Android via this setting alone — build in a small tolerance (a few dozen ms) for any timing-critical sync (e.g. hit-stop start vs. thud sound), and playtest specifically on real low/mid-range Android hardware, not just the desktop editor, since desktop audio latency is not representative. Sources: [Godot Forum — audio latency on Android](https://forum.godotengine.org/t/audio-latency-on-android/40339), [Godot Forum — audio latency on android devices](https://forum.godotengine.org/t/audio-latency-on-android-devices/134704), [godot#108204](https://github.com/godotengine/godot/issues/108204).

### Where to get free, commercial-safe SFX [EST]

| Source | License | Notes |
|---|---|---|
| [Kenney.nl](https://kenney.nl/) audio packs | **CC0** (public domain) | No attribution, no sign-up, safe for a paid game outright |
| [Freesound.org](https://freesound.org/) | Mixed — filter explicitly for **"Creative Commons 0"** | ~381,000 CC0 sounds as of Sept 2026; many others are CC-BY (need attribution) or more restrictive — always check per-file license, don't assume |
| [Sonniss GDC Game Audio Bundle](https://sonniss.com/gameaudiogdc) (annual, free) | Royalty-free for media production (games/film/TV/interactive) | 2026 edition ~7.47GB/347 WAV files; explicitly **prohibits AI/ML training use** but fine for direct use in a shipped game; every year back to 2015 stays downloadable |
| OpenGameArt.org | Mixed, filter for CC0 | Community-run, quality varies |

---

## 6. Turn transitions and readability in a hot-seat game

### [EST] Approaches used in shipped hot-seat/pass-and-play games

Hot-seat (a.k.a. pass-and-play) is a well-established category ([Wikipedia overview](https://en.wikipedia.org/wiki/Hotseat_(multiplayer_mode))); UI patterns observed across the category, general knowledge plus search findings:
- **Color coding**: assign each player a persistent color used consistently for their pen, their HUD elements, and any turn banner (seen broadly, e.g. red/blue paired schemes in board-game-style apps).
- **Screen-edge glow/border**: a colored border or glow around the whole screen during a player's turn — reinforces "whose turn" peripherally without requiring the player to read anything, visible even in the player's peripheral vision while they're focused on the pen.
- **Rotating the UI/camera 180°** for the other player: common in physical tabletop-style digital games (chess clocks, some board game apps) so each player's HUD is "up" from their own seating position; makes sense here since two players are physically on opposite sides of one phone/table.
- **Full-screen "P2's turn — tap when ready" gate**: an explicit modal that must be dismissed before the next turn's input becomes live — this is the single most common **mechanism to prevent the wrong-turn-flick failure**, because it forces a deliberate action (a tap) at the moment of handoff, during which the phone is physically changing hands.
- **Camera framing**: reframing/panning the camera toward the active player's pen at turn start, so the visual focus itself signals who's up.

### The most common hot-seat failure and what prevents it

**[EST]** The classic failure is: Player A finishes their turn, the phone is mid-handoff, and Player B (or A again, out of habit) flicks before realizing/registering the turn actually changed — an accidental or premature input during the transition window. This is a **timing/input-gating problem, not a legibility problem** — even a game with perfect color-coding and edge glow can suffer it if input is live the instant the previous turn ends and the phone is still moving between hands.

**[REC]** Design for this game:
1. **Hard input gate**: after a shot resolves (all bodies below velocity threshold, i.e. "settled"), enter an explicit `TurnTransition` state where the pens are **not interactable at all** — no drag/flick input is processed regardless of touches landing on the table area.
2. **Full-screen tap-to-continue banner** during that state: big, colored to the *incoming* player (not the outgoing one — reduce ambiguity), text "Player 2's turn — tap to begin," dismissible only by a tap in the banner's own hit area (not by touching the pen), matching the established full-screen-gate pattern above. This uses the physical handoff time productively — the banner should be showing while the phone is literally being passed across the table.
3. **Persistent secondary reinforcement while it's live**: a screen-edge glow/border in the active player's color for the whole duration of their turn (not just the transition), plus the pen the player is about to flick outlined/highlighted in their color. This is a Rank-cheap add given point 1 requires the transition state to exist anyway.
4. **180° UI rotation**: worth doing if the phone is expected to stay flat on the table between shots (matches "pen fight on a table" framing) rather than being picked up — the HUD (score, whose-turn banner) should read right-side-up from each player's own seat. **[REC]**: implement this only if playtesting (§8) shows players are confused by upside-down text; it's the highest-effort item on this list (requires either duplicating/mirroring UI or rotating a UI CanvasLayer) relative to its marginal benefit over color+gate+glow.

---

## 7. Round and match ceremony

### [EST] General pattern from scoring/highlight moments in other games

Payoff-moment pacing across sports/physics games (Rocket League goals, mobile sports titles, Angry Birds level completion) follows a consistent shape even where exact frame timings aren't publicly documented per-title: **(a)** a brief slow-motion or freeze on the decisive contact, **(b)** a camera move that follows the losing object/ball to its resting or "out" state, **(c)** a pause before the score/UI updates (letting the visual result land before the abstraction of a number appears), **(d)** an animated score-tick rather than an instant digit swap, **(e)** a short "sting" (sound + a burst of UI motion) confirming the win. Confirmed generally true of Rocket League's replay/goal-explosion camera behavior (camera locks to the scoring player, sequences run in slow motion around the decisive touch) per community discussion of its replay system: [Steam community thread on replay camera](https://steamcommunity.com/app/252950/discussions/0/1489992080498184308/). Exact publicly-documented frame counts for Rocket League's specific goal-explosion timing were not found in this research pass — treat the shape (not the seconds) as established, and the seconds below as **[REC]**.

### [REC] Timing to start from, for the pen falling off the table

| Beat | Duration | Notes |
|---|---|---|
| Hit-stop on the fatal collision | 150–200ms (longer than a normal hit's 50–80ms — this is the one deliberate outlier) | Reuses the hit-stop system from §3, just a bigger value |
| Slow-motion as the pen falls off the edge | 0.5–1.0s of in-game time stretched to ~1.0–1.5s real time (`Engine.time_scale` ~0.4–0.5) | Long enough to *see* it fall, not so long it drags |
| Camera follow on the falling pen | Starts at slow-mo onset, ends when pen leaves view or lands | A `Camera2D` `position` tween/follow targeting the falling `RigidBody2D`; consider a slight zoom-in |
| Return to normal time + hold before score updates | 300–500ms pause after time_scale returns to 1.0, before the score UI animates | Lets the visual result register before the abstraction (score number) appears — matches the general pattern above |
| Score-tick animation | 400–600ms | Animate the digit (count up, or a quick scale-pop on the new digit) rather than snapping it |
| Win sting (only on match win, not each round) | 1.5–2.5s | Full-screen win banner + sound; should be skippable by tap for repeat players who don't want to wait it out on round 15 of a session |

**[REC]** Make every ceremony beat **skippable by tap** after the first 2–3 rounds of a session (or via a settings toggle), because per the developer's own gate ("20 rounds and want a 21st"), a 3-second unSkippable ceremony every round adds a full minute of pure waiting across 20 rounds — the ceremony must serve *early* rounds' excitement without becoming friction by round 15.

---

## 8. The 20-round test — playtest protocol

The developer's own bar is explicit: *"you and one other person play 20 rounds and want a 21st."* Design the test to produce a clear pass/fail on that bar, not vague vibes.

### [REC] Protocol

**Setup**: Two players (ideally not the developer alone — get someone who hasn't seen the build), one physical phone, no coaching beyond the basic controls, screen-recorded if possible (or at minimum audio-recorded for verbal reactions) plus lightweight in-game instrumentation logging events to a local file.

**Instrument** (log per round, append to a local JSON/CSV via `FileAccess`):
- Round number, winner, match number (in case you play multiple 20-round matches)
- **Turn count** in the round (how many flicks total before a pen fell off)
- **Per-turn duration** (time from turn-gate dismissed to flick release) — surfaces decision-paralysis or, conversely, rounds that are over "too fast to think"
- **Flick power distribution**: log the normalized pull-distance/impulse of every flick taken, across both players and the whole session
- **"Do-nothing" turns**: a turn where the flick produces negligible velocity change to game state (e.g., pen barely moves, doesn't touch the opponent) — count these as a fraction of total turns
- **Fluke vs. skill endings**: manually tag (by the observer, in real time or on video review) whether the winning knockout was a clean, intentional hit or an accidental/lucky bounce (e.g., the pens barely grazed and one popped off from an unlikely angle) — this can't be fully automated without more physics introspection than is worth building for a 20-round test, so **[REC]** have the non-playing observer (or the developer, if playing) call it live and jot a tally

**Observe in the other player** (qualitative, written down immediately after, not relying on memory):
- Do they lean forward / react physically at impacts and knockouts, or stay flat? (Physical reaction is a strong tell for "juice" landing.)
- Do they ask "wait, whose turn is it?" at any point? (Direct signal on §6.)
- Do they start developing any stated *strategy* language ("I'm going to try to hit you at an angle," "I'll play defensive and stay in the corner") by round 5–10, or are they still just flicking blind by round 15? Strategy language emerging is a strong positive signal; its absence by round 10 is a warning sign.
- Do they reach for the phone again unprompted after round 20, or do they hand it back / put it down? This is the literal operationalization of the gate question — don't just ask "did you like it," watch what they *do* at round 20.

**Ask them** (after, not during):
1. "Want to play another round?" — the actual gate question, asked plainly, not leadingly.
2. "What were you thinking about right before you flicked?" — reveals whether there's a decision space at all, or if it's pure reflex/luck.
3. "Was there a round that felt unfair or like it came down to luck rather than your shot?" — surfaces the fluke-ending problem from the player's own perspective.
4. "Which round do you remember best, and why?" — surfaces whether the ceremony/juice moments (§3, §7) are actually memorable or forgettable.
5. "Did you ever lose track of whose turn it was?" — direct check on §6.

### What results mean "the mechanic is broken, stop"

**[REC]** thresholds, informed by general design reasoning about variance and skill expression (not a cited study — this is judgment applied to the specific gate):

| Signal | Healthy | Warning | Stop-and-rework |
|---|---|---|---|
| "Do-nothing" turns (flick that barely affects the board) | <10% of turns | 10–25% | >25% — power/control curve or table friction needs rework |
| Fluke-ending rounds (observer-tagged) | <25% of rounds | 25–50% | **>50%** — the physics/table setup is more luck than skill; see reasoning below |
| Round length distribution | Most rounds land in a similar band (e.g. 3–8 turns), with some short "high-skill quick kill" outliers and some long "grindy" outliers, forming a rough bell shape | Bimodal — nearly every round is either 1-2 turns (instant, no game) or 15+ turns (stalemate, nobody can finish) | Nearly all rounds are 1 turn (starting position/power is too strong — the game is a coinflip) or nearly all rounds never end within a reasonable turn cap (pens can't actually knock each other off — the core interaction fails) |
| Player asks "whose turn?" | 0 times in 20 rounds | 1–2 times, only in the first few rounds (learning curve) | Repeatedly, still happening by round 15 — turn-transition design (§6) has failed |
| Stated desire for round 21 | Immediate, unprompted, or "yes" without hesitation | "Sure" / lukewarm | "I'm good" / declines, or picks up their own phone instead |
| Strategy language by round 10 | Present, specific | Vague ("I'll just try harder") | None — still purely reactive by round 15-20 |

**Why >50% fluke endings specifically kills a game after five rounds, not after one**: a single lucky/unlucky round is tolerable and even fun (a "wow" moment) precisely *because* it's rare against a backdrop of skill-driven outcomes — it reads as drama. Once flukes are the majority outcome, the losing player's mental model shifts from "I made a mistake, I can improve" to "the outcome wasn't mine to control," which kills the two things a repeat-play game needs: a felt sense of agency (Swink's core "real-time control" pillar of game feel — control disconnected from outcome breaks the feel loop even if individual moments still look/sound great) and a reason to want a rematch specifically to *do better* rather than just to re-roll the dice. Five rounds is roughly the point a human stops attributing early bad luck to "warming up" and starts pattern-matching the game itself as unfair — hence it degrades specifically around round 5, not round 1.

---

## 9. Accessibility and comfort

**[REC]** for all of this section, applying established general mobile-UX and accessibility guidance to this specific game shape.

### One-handed reachability

Steven Hoober's thumb-zone research (originally UXmatters 2013, widely cited since) found that a majority of smartphone use is one-handed or thumb-driven, with reach naturally split into a "green" easy zone (bottom-center), a "yellow" stretch zone (mid-screen sides), and a "red" hard-to-reach zone (top corners) — [summary source](https://timgraf.com/ux-design/designing-for-the-thumb-zone-a-modern-guide-to-mobile-ux-that-respects-human-anatomy/), [Smashing Magazine overview](https://www.smashingmagazine.com/2016/09/the-thumb-zone-designing-for-mobile-users/). This is a two-thumbs, landscape or portrait table-top game where both players' pens are meant to be reachable by drag gestures across most of the screen — the aim/flick gesture itself is inherently large-area and not confined to a thumb zone, so the main application of this research is to **secondary UI** (pause button, settings, score display, the turn-transition tap target): put dismiss/confirm taps for the transition gate in the **bottom half** of the screen on the incoming player's side, not in a top corner, since that's the actual reachable zone for whichever hand is holding the phone during handoff.

### Left- vs right-handed players

Since the game is played by two people on opposite sides of one flat phone/table, "handedness" here is less about a single held device and more about drag direction — a right-handed and left-handed player pulling back toward themselves should both find comfortable arcs. **[REC]**: don't lock aim gestures to a specific drag angle or corner; let the pull vector be fully free-form (360°) so any hand posture and any seating side works without a handedness setting.

### Colour-blind-safe player differentiation

General practice: blue is safe against nearly all forms of color blindness, red/green pairings are the most commonly broken combination (protanopia/deuteranopia are the most common types), and pairing a color difference with a **shape or pattern** difference removes ambiguity entirely rather than relying on hue alone. [Source summary](https://www.hicreategames.com/color-blind-friendly-board-game-design/), general guidance also echoed in [Venngage's color-blind palette guide](https://venngage.com/blog/color-blind-friendly-palette/). **[REC]** for Pen Fight: use blue vs. orange (not red vs. green) for Player 1/Player 2, and additionally differentiate pens by a **secondary visual marker** independent of color — e.g. a cap/stripe shape, or simply distinct pen silhouettes/end-caps — so the game reads correctly even under full color-blindness or on a washed-out outdoor screen.

### No-shake option for motion sensitivity

Screen shake (§1, §3) is a known trigger for discomfort in motion-sensitive players. **[REC]**: expose a settings toggle ("Reduce screen shake" or "Reduce motion") that scales the trauma-based shake's `max_offset`/`max_roll_deg` to zero (or near-zero) while leaving hit-stop, particles, and sound untouched — this is a single multiplier in the shake code from §3, essentially free to add given the trauma system already centralizes shake magnitude in one place.

### Text size

**[REC]**: keep any in-game text (score, turn banner, settings) using Godot's theme font-size resources rather than hardcoded per-Label sizes, so a single "Larger text" accessibility toggle can scale a theme's base font size project-wide (`Theme.default_font_size` or a scaling multiplier applied to a shared `Theme` resource) instead of touching every scene. Given the score/turn-banner text is the only text most players will read mid-session, prioritize making *that* legible at arm's length on a table (large, high-contrast) by default, rather than treating text size purely as an accessibility opt-in.

---

## Summary source list

- Steve Swink, *Game Feel* (book; concepts referenced, no single URL)
- [The Art of Screenshake — Jan Willem Nijman, Vlambeer (YouTube)](https://www.youtube.com/watch?v=AJdEqssNZ-U)
- [Juice it or Lose It — Martin Jonasson & Petri Purho (YouTube)](https://www.youtube.com/watch?v=Fy0aCDmgnxg) / [GDC Vault](https://www.gdcvault.com/play/1016487/juice-it-or-lose)
- [Math for Game Programmers: Juicing Your Cameras With Math — Squirrel Eiserloh, GDC 2016 (transcript)](https://archive.org/stream/GDC2016Eiserloh/GDC2016-Eiserloh_djvu.txt)
- [Godot 4 Recipes — Screen Shake](https://kidscancode.org/godot_recipes/4.x/2d/screen_shake/index.html)
- [Borderline Blog — trauma-based screenshake](http://blog.borderline.games/tutorials/gettinghit!/trauma-based-screenshake.html)
- [Godot Forum — freeze without pausing entire game](https://forum.godotengine.org/t/how-to-frame-freeze-without-pausing-entire-game/85550)
- [Godot 4 GPUParticles2D guide](https://godot-mcp.abyo.net/guides/godot4-particles)
- [godot-proposals #9582 — vibrate_handheld amplitude](https://github.com/godotengine/godot-proposals/issues/9582)
- [godot #103496 — vibrate crash without VIBRATE permission](https://github.com/godotengine/godot/issues/103496)
- [os_android.cpp source](https://github.com/godotengine/godot/blob/master/platform/android/os_android.cpp)
- [Godot Forum — audio latency on Android](https://forum.godotengine.org/t/audio-latency-on-android/40339) / [and android devices](https://forum.godotengine.org/t/audio-latency-on-android-devices/134704)
- [godot #108204 — output_latency has no effect](https://github.com/godotengine/godot/issues/108204)
- [Kenney.nl](https://kenney.nl/) / [Freesound](https://freesound.org/) / [Sonniss GDC Bundle](https://sonniss.com/gameaudiogdc)
- [Miniclip — 8 Ball Pool aiming](https://support.miniclip.com/hc/en-us/articles/203747546-How-to-Aim-with-the-Cue-8-Ball-Pool) / [basic controls](https://support.miniclip.com/hc/en-us/articles/35451942766865-Basic-Controls-Improving-your-skills-8-Ball-Pool)
- [Miniclip — Carrom Pool beginner guide](https://support.miniclip.com/hc/en-us/articles/4404675218577-How-to-Start-Playing-Carrom-Pool-A-Beginner-s-Guide)
- [Angry Birds Wiki — Slingshot](https://angrybirds.fandom.com/wiki/Slingshot)
- [Hotseat (multiplayer mode) — Wikipedia](https://en.wikipedia.org/wiki/Hotseat_(multiplayer_mode))
- [Rocket League replay camera discussion](https://steamcommunity.com/app/252950/discussions/0/1489992080498184308/)
- [Steven Hoober thumb zone summary](https://timgraf.com/ux-design/designing-for-the-thumb-zone-a-modern-guide-to-mobile-ux-that-respects-human-anatomy/) / [Smashing Magazine](https://www.smashingmagazine.com/2016/09/the-thumb-zone-designing-for-mobile-users/)
- [Color-blind-friendly board game design](https://www.hicreategames.com/color-blind-friendly-board-game-design/) / [Venngage palette guide](https://venngage.com/blog/color-blind-friendly-palette/)
