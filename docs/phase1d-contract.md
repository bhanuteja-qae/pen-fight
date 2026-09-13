# Phase 1d Build Contract — polish wave after review of main@76aad79

Review source: `docs/UI_AND_PHYSICS_PLAN.md` (claude branch, c039419) + the
fixed torque-arm/stalemate work already merged (9dfc3c1, afd20a3). This wave
implements the remaining six review points in **3 parallel agents, strict file
ownership, zero overlaps**. Every agent works against EXISTING interfaces; the
orchestrator integrates main.gd wiring, gates, commits.

## Agreed facts (already verified, do not re-derive)

- `apply_impulse(impulse, position)` takes an **offset from the body origin in
  global orientation** (basis_xform, no translation) — FIXED in 9dfc3c1.
- Stalemate forfeit (settled + no pen moved = loss) — FIXED in afd20a3.
- Audio API present in 4.7.2 binary: `add_bus`, `set_bus_volume`, `play`.
- Contact API present: `get_contact_count`, `get_contact`, `body_shape_entered`.
- Resize decision (UI_AND_PHYSICS §2D): **shrink the pen, keep the table near
  viewport** — preserves MAX_IMPULSE/damping/travel. Capsule 180×5 (radius 5,
  height 180), sprite scale 0.408, shadow (4,6), table_bounds 1180×640.
- OOB rule (reviewer's decision, confirmed): **keep geometric capsule-extent
  rule**, add a **few-px tolerance** to absorb solver jitter near the boundary
  (the "better third option" — NOT centre-of-mass).
- angular_damp 4.0 → **1.5** in the SAME change as the resize (ω ∝ 1/L doubles
  when L halves; I goes 10800 → 2700).
- Aim UI per UI_AND_PHYSICS §4 + `assets/design/aim-ui.png` mockup: launch
  cone, power fill, MAX tick, pull band, grab ring, spin arc.
- Touch-first input (UI_AND_PHYSICS §5.6 / review): handle
  `InputEventScreenTouch` / `InputEventScreenDrag` directly (keep mouse as the
  desktop/debug fallback — both feed the SAME gesture state machine).

## Agent roles (dispatch in one parallel wave)

### Agent A — physics geometry + contact signal
**Owns:** `game/scenes/main.tscn`, `game/scripts/pen_body.gd`
*(nothing else)*

1. Resize per the decided contract:
   - `main.tscn`: `CapsuleShape2D` radius 10→**5**, height 360→**180**;
     both pen `Sprite2D` + both `Shadow` `scale = Vector2(0.408, 0.408)`;
     shadow positions (9,14)→**(4,6)**; `table_bounds` size 1120×600→**1180×640**.
   - `pen_body.gd`: `DEFAULT_PEN_RADIUS 10.0→5.0`, `DEFAULT_PEN_HALF_LEN
     170.0→85.0` (fallback extents only — scene normally supplies the shape).
   - `main.tscn`: `angular_damp 4.0→1.5` on BOTH pens (linear_damp stays 2.0).
   - Keep the scene's pen positions; do NOT touch spawns unless the table
     bounds change requires it (bounds grew only 30px/side — they fit).
2. OOB tolerance: in `pen_body.gd`, add
   `const OOB_TOLERANCE_PX := 8.0  # [TUNE] absorb solver jitter at the edge`
   and apply it in the geometric out-of-bounds test (inflate the acceptable
   region by tolerance beyond the radius inset — the capsule ENDPOINTS may be
   up to radius+tolerance past the rect before `out_of_bounds` fires). The
   verdict stays geometric capsule-extent, never centre-of-mass.
3. NEW contact signal (for the audio agent):
   ```gdscript
   signal impact(pen_uid: String, impact_speed: float)
   ```
   Emitted once per physics tick (throttled, max ~1 per 3 frames) when
   `state.get_contact_count() > 0` AND the linear speed at that tick exceeds
   `IMPACT_MIN_SPEED := 60.0` (px/s, [TUNE]). impact_speed = current linear
   velocity magnitude. Add the constants + a throttling counter; DO NOT wire
   any consumer.
4. Reset/clear any new per-flight state in `apply_flick`, `reset`, `_ready`.

**Gate check (do not run the engine):** structural — tabs, no stale dimension
references (search for `360`, `(9, 14)`, old scale `Vector2(1, 1)`/absent
scale), all-new symbols exist, no other file touched.

### Agent B — touch-first input + aim overlay
**Owns:** `game/scripts/aim_input.gd`, NEW `game/scripts/aim_overlay.gd`
*(nothing else — main.gd wiring is the orchestrator's)*

1. `aim_input.gd` touch-first:
   - Handle `InputEventScreenTouch` (pressed/released) and
     `InputEventScreenDrag` in ADDITION to the existing mouse path — all feed
     the ONE gesture state machine (`_dragging`, press pos, release). Keep the
     existing mouse handling as the desktop/debug fallback.
   - Keep signal shape EXACTLY: `flick_ready(direction: Vector2, power: float,
     contact_offset: float)` — main.gd already consumes three args.
   - Expose live gesture state for the overlay: `get_drag_info() -> Dictionary`
     with keys `dragging`, `press_pos`, `current_pos`, `grab_offset`
     (-1..1 along barrel), `direction` (unit), `power` (0..1) —
     recomputed per frame while dragging; empty/zeroed when idle.
2. `aim_overlay.gd` (NEW, `extends Node2D`, drawn via `draw_string`/primitive
   drawing exactly like `debug_overlay.gd` — headless-safe, no realtime-UI
   dependencies):
   - API: `set_pen(pen: PenBody)`, `show_drag(info: Dictionary)`,
     `clear()`.
   - Draws, anchored on the pen, per UI_AND_PHYSICS §4 + the aim-ui.png
     mockup: **grab marker ring** on the barrel at the grab point (before
     power), then while dragging: **pull band** (grab→finger, dashed, dim),
     **launch cone** from grab point along direction, translucent alpha
     0.5→0.04 taper with slight widening, **power fill** (warmer fill to the
     current power) + **MAX tick** where full power lands, and the **spin arc**
     — a curved arrow whose direction is sign(r × J) and weight ∝ |ω|;
     vanishes when the drag runs along the barrel (r×J≈0). No trajectory
     prediction — cone shows heading+power only.
   - Pens must draw OVER the translucent UI; the grab ring over the pen
     (set z-order so the overlay sits beneath the pens except the ring —
     pragmatic: draw the ring slightly offset on top).
   - Fully no-op when idle (zero drawing when there is no active drag).
3. Do NOT touch main.gd, pen_body.gd, or audio. The overlay only reads the
   pen (global_position, rotation, get_half_len()) and `get_drag_info()`.

**Gate check:** structural only. All symbols referenced exist in the binary or
are defined in your two files.

### Agent C — audio buses + layered impact sound
**Owns:** NEW `game/scripts/audio.gd` (nothing else)

1. `class_name AudioManager extends Node`:
   - `func _ready() -> void`: warm the audio system; create buses
     `Master`, `SFX`, `Music` via `add_bus`. Everything guarded —
     on a headless/dummy-driver box (our CI) the server falls back to the
     dummy driver: any call that fails must be a logged warning, never a
     crash. Default volumes: Master 1.0, SFX 0.9, Music 0.6
     (`set_bus_volume`).
   - `func play_impact(impact_speed: float) -> void` (SFX): a short layered
     thud — the spec's two-layer transient (a low thump + a click) with
     **pitch randomised ±5–10 %** per hit (stops the machine-gun effect);
     gain scaled with impact_speed (map 60..1600 px/s → 0.1..1.0).
     Use a generated/low-fidelity sound path that works without bundled audio
     FILES: either a tiny generated WAV in `res://assets/audio/` (create it
     with a build script under YOUR ownership) or AudioStream playback of a
     procedurally generated buffer — pick the one that verifiably exists in
     the 4.7.2 API (check the binary, e.g. `create_audio_stream_playback`,
     `add_stream_player`, `play`). If NO viable audio-file path exists on the
     dummy driver, make `play_impact` a **logged no-op with a clear TODO** —
     correctness of wiring > fabricated sound.
   - `func play_flick(power: float) -> void` (SFX): a light whoosh tick, pitch
     by power (or no-op path as above).
   - `func set_sfx_volume(v: float)`, `set_music_volume(v)` — future settings
     hook.
2. NO other files. Do not touch main.gd (the orchestrator connects the pen
   `impact` signal → `play_impact` and `flick_ready` → `play_flick` at
   integration).

**Gate check:** structural; the class loads during import (no parse errors);
API names verified against the binary before use.

## Orchestrator integration (AFTER the wave returns, orchestrator-only)

- main.gd: create `aim_overlay` + `audio` nodes; connect
  `pen.impact -> audio.play_impact`; `aim_input.flick_ready ->
  audio.play_flick`; call `overlay.set_pen(pen)` + feed drag info per frame in
  `_sync_aim_zone`-adjacent code.
- Re-run gates: double import; turn_state_test; auto_flick_test (knockout);
  20-round gate (must PASS at the NEW scale — may need a few no-decision
  rounds, that is fine); torque probe unchanged.
- Live render: Xvfb + autoplay; capture frames; vision-check the **smaller
  pen on the bigger playfield**, the aim overlay with a scripted synthetic
  drag if possible, and the audio bus warnings being benign on the dummy
  driver.
- Commit + push.

## Non-goals this wave

- No Coulomb friction (optional, behind a flag — parked as its own ticket).
- No camera roll change, no haptics, no particles.
- No trajectory prediction (explicitly forbidden by the spec).