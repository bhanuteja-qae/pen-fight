class_name AudioManager
extends Node
## Phase 1d audio agent (docs/phase1d-contract.md — Agent C). Agent C owns ONLY
## this file; main.gd wiring (pen.impact -> play_impact, flick_ready ->
## play_flick) is the orchestrator's job.
##
## API verification (cross-checked against the 4.7.2-stable binary strings AND
## the en/4.7 official class docs before writing any call):
##   - AudioServer.add_bus(at_position: int = -1) -> void   [NO name argument in
##     4.7 — a bus is added, then renamed via set_bus_name(); the old
##     add_bus(name) signature is gone from the binary]
##   - AudioServer.set_bus_name(bus_idx: int, name: String) -> void
##   - AudioServer.set_bus_volume_linear(bus_idx: int, volume: float) -> void
##     (set_bus_volume_db exists too; linear matches our 0..1 gain language)
##   - AudioServer.get_bus_index(bus_name: StringName) -> int  (-1 if missing)
##   - AudioServer.get_bus_count() -> int;  get_driver_name() -> String
##   - create_audio_stream_playback / add_stream_player: NOT present in the
##     4.7.2 binary (legacy 4.2-era API, removed). The documented GDScript
##     procedural path in 4.7 is AudioStreamPlayer + AudioStreamGenerator +
##     AudioStreamGeneratorPlayback — the official docs example literally does:
##         var playback  # AudioStreamGeneratorPlayback
##         func _ready():
##             $AudioStreamPlayer.play()
##             playback = $AudioStreamPlayer.get_stream_playback()
##             ... playback.push_frame(...)
##   - AudioStreamPlayer (Node): props stream (AudioStream), bus (StringName),
##     pitch_scale (float), volume_linear (float), max_polyphony (int);
##     methods play(from_position = 0.0), stop(), get_stream_playback() ->
##     AudioStreamPlayback, has_stream_playback() -> bool.
##   - AudioStreamGenerator (AudioStream): props mix_rate, buffer_length.
##   - AudioStreamGeneratorPlayback: clear_buffer(), can_push_buffer(amount),
##     push_buffer(frames: PackedVector2Array) -> bool.
##
## Failure policy (dummy-driver headless CI): everything is validation-guarded —
## every index is checked against get_bus_index/get_bus_count first, every
## playback handle is null-checked before use, and every failure path is a
## push_warning + return. If the playback path cannot be established the SFX
## pools stay empty and play_impact/play_flick become LOGGED NO-OPS (see the
## TODO at _setup_sfx) — the wiring stays correct and sound can be dropped in
## later behind that gate without touching main.gd.

# --- Bus layout ---------------------------------------------------------------

const BUS_MASTER := &"Master"
const BUS_SFX := &"SFX"
const BUS_MUSIC := &"Music"
const BUS_VOLUME_MASTER: float = 1.0
const BUS_VOLUME_SFX: float = 0.9
const BUS_VOLUME_MUSIC: float = 0.6

# --- Procedural SFX synthesis -------------------------------------------------

const SFX_MIX_RATE: float = 22050.0   # [TUNE] docs: keep low for GDScript generators
const SFX_BUFFER_SECONDS: float = 0.5 # max pre-roll before the audio thread catches up
const IMPACT_POOL_SIZE: int = 2       # 2 overlapping thuds max per tick
const TICK_POOL_SIZE: int = 2

## Impact gain mapping: impact_speed px/s -> 0..1 gain (docs/ART_AND_FEEL §4).
const IMPACT_MIN_SPEED: float = 60.0
const IMPACT_MAX_SPEED: float = 1600.0
const IMPACT_GAIN_MIN: float = 0.1
const IMPACT_GAIN_MAX: float = 1.0
## Pitch randomised per hit, magnitude ±5-10% (stops the machine-gun effect).
const IMPACT_PITCH_MIN: float = 0.05
const IMPACT_PITCH_MAX: float = 0.10

## Thud = low thump + click (the spec's two-layer transient), pre-synthesised.
const THUD_DURATION: float = 0.28
const THUMP_F0: float = 220.0         # Hz, sweeping down to THUMP_F1
const THUMP_F1: float = 90.0
const THUMP_SWEEP_TIME: float = 0.14
const THUMP_DECAY: float = 7.0
const THUMP_GAIN: float = 0.85
const CLICK_DELAY: float = 0.003      # s after the thump starts
const CLICK_F0: float = 2600.0        # Hz, sweeping down to CLICK_F1
const CLICK_F1: float = 1400.0
const CLICK_DECAY: float = 60.0
const CLICK_GAIN: float = 0.30

## Flick tick: a short bright blip, pitch scaled by flick power.
const TICK_DURATION: float = 0.09
const TICK_FREQ: float = 1500.0
const TICK_DECAY: float = 45.0
const TICK_GAIN: float = 0.5
const FLICK_PITCH_PER_POWER: float = 0.8

# --- State --------------------------------------------------------------------

var _master_bus: int = -1
var _sfx_bus: int = -1
var _music_bus: int = -1
var _rng := RandomNumberGenerator.new()
var _thud_frames: PackedVector2Array = PackedVector2Array()
var _tick_frames: PackedVector2Array = PackedVector2Array()
var _thud_pool: Array[AudioStreamPlayer] = []
var _tick_pool: Array[AudioStreamPlayer] = []
var _thud_rr: int = 0
var _tick_rr: int = 0
var _no_playback_warned: bool = false
## Whether _setup_sfx ran without already failing (avoids duplicate synthesis
## if the node ever re-enters the tree).
var _ready_done: bool = false


# --- Lifecycle ----------------------------------------------------------------

## Warm the audio system: log the driver, build the Master/SFX/Music bus graph
## with the contract's default volumes, and pre-synthesise the SFX buffers.
func _ready() -> void:
	if _ready_done:
		return
	_ready_done = true
	print("AudioManager: audio driver = '%s' (bus_count=%d)" % [AudioServer.get_driver_name(), AudioServer.get_bus_count()])
	_setup_buses()
	_setup_sfx()


## Create (or resolve) the three buses and apply their default volumes.
## Every index is derived from get_bus_count()/get_bus_index() before use, so a
## degraded/dummy audio server can never send us out of range.
func _setup_buses() -> void:
	_master_bus = _ensure_bus(BUS_MASTER, "Master", BUS_VOLUME_MASTER)
	_sfx_bus = _ensure_bus(BUS_SFX, "SFX", BUS_VOLUME_SFX)
	_music_bus = _ensure_bus(BUS_MUSIC, "Music", BUS_VOLUME_MUSIC)
	print("AudioManager: buses Master/SFX/Music -> indexes %d/%d/%d, volumes 1.0/0.9/0.6" % [_master_bus, _sfx_bus, _music_bus])


## Find a bus by StringName; create it (add_bus appends at the end, then
## set_bus_name) if missing, then set its linear volume. Returns -1 on failure.
func _ensure_bus(name: StringName, rename_to: String, volume: float) -> int:
	var idx := AudioServer.get_bus_index(name)
	if idx >= 0:
		AudioServer.set_bus_volume_linear(idx, volume)
		return idx
	var count := AudioServer.get_bus_count()
	if count <= 0:
		push_warning("AudioManager: AudioServer reports no buses; cannot create '%s'" % rename_to)
		return -1
	AudioServer.add_bus()           # appends at the end (at_position = -1)
	idx = count
	AudioServer.set_bus_name(idx, rename_to)
	AudioServer.set_bus_volume_linear(idx, volume)
	return idx


## Pre-synthesise the thud/tick PCM and build the round-robin AudioStreamPlayer
## pools (one procedural [AudioStreamGenerator] stream per node, all on SFX).
##
## TODO(audio): if ANY step here fails on a headless/dummy-driver box (no
## playback could be created), the pools stay empty and play_impact/play_flick
## degrade to LOGGED NO-OPS via _log_no_playback. The wiring stays correct;
## real sound can be dropped in behind that gate later (e.g. sample playback or
## a generated WAV in res://assets/audio) without touching main.gd.
func _setup_sfx() -> void:
	_thud_frames = _build_thud_frames()
	_tick_frames = _build_tick_frames()
	for i in range(IMPACT_POOL_SIZE):
		var p := _make_sfx_player()
		if p != null:
			_thud_pool.append(p)
	for i in range(TICK_POOL_SIZE):
		var p := _make_sfx_player()
		if p != null:
			_tick_pool.append(p)
	if _thud_pool.is_empty() or _tick_frames.is_empty():
		push_warning("AudioManager: could not create AudioStreamPlayer(s) — SFX are logged no-ops (see TODO)")


## One pooled player: a fresh AudioStreamGenerator stream + AudioStreamPlayer
## node routed to the SFX bus, attached as a child of this node.
func _make_sfx_player() -> AudioStreamPlayer:
	var gen := AudioStreamGenerator.new()
	if gen == null:
		return null
	gen.mix_rate = SFX_MIX_RATE
	gen.buffer_length = SFX_BUFFER_SECONDS
	var p := AudioStreamPlayer.new()
	if p == null:
		return null
	p.stream = gen
	p.bus = BUS_SFX
	p.max_polyphony = 1
	add_child(p)
	return p


# --- Public API (main.gd wiring) ----------------------------------------------

## Layered impact thud on the SFX bus. `impact_speed` in px/s: gain maps the
## contract's 60..1600 range onto 0.1..1.0, and pitch is randomised ±5-10% per
## hit. Never throws: unplayable audio degrades to a logged no-op.
func play_impact(impact_speed: float) -> void:
	if impact_speed <= 0.0:
		return
	var t := clampf((impact_speed - IMPACT_MIN_SPEED) / (IMPACT_MAX_SPEED - IMPACT_MIN_SPEED), 0.0, 1.0)
	var gain := IMPACT_GAIN_MIN + (IMPACT_GAIN_MAX - IMPACT_GAIN_MIN) * t
	var pitch := 1.0 + _rng.randf_range(-1.0, 1.0) * _rng.randf_range(IMPACT_PITCH_MIN, IMPACT_PITCH_MAX)
	_fire(_next_thud_player(), _thud_frames, pitch, gain)


## Light flick tick on the SFX bus, pitch rising with flick power (0..1).
func play_flick(power: float) -> void:
	var p := clampf(power, 0.0, 1.0)
	_fire(_next_tick_player(), _tick_frames, 1.0 + p * FLICK_PITCH_PER_POWER, TICK_GAIN)


## Settings hook: SFX bus volume, 0..1 linear.
func set_sfx_volume(v: float) -> void:
	_set_bus_linear(_sfx_bus, v)


## Settings hook: Music bus volume, 0..1 linear.
func set_music_volume(v: float) -> void:
	_set_bus_linear(_music_bus, v)


# --- Internals ----------------------------------------------------------------

func _set_bus_linear(bus_idx: int, v: float) -> void:
	if bus_idx < 0:
		return
	AudioServer.set_bus_volume_linear(bus_idx, clampf(v, 0.0, 1.0))


func _next_thud_player() -> AudioStreamPlayer:
	if _thud_pool.is_empty():
		return null
	_thud_rr = (_thud_rr + 1) % _thud_pool.size()
	return _thud_pool[_thud_rr]


func _next_tick_player() -> AudioStreamPlayer:
	if _tick_pool.is_empty():
		return null
	_tick_rr = (_tick_rr + 1) % _tick_pool.size()
	return _tick_pool[_tick_rr]


## Retrigger one player with the given PCM, pitch and gain: stop any current
## playback, start a fresh one (per the docs example, play() must come first so
## get_stream_playback() has an active playback to return), then push the
## pre-synthesised frames. All steps null/index-guarded.
func _fire(player: AudioStreamPlayer, frames: PackedVector2Array, pitch: float, gain: float) -> void:
	if player == null:
		_log_no_playback()
		return
	var pb := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		_log_no_playback()
		return
	# One-shot retrigger sequence, per the engine source
	# (servers/audio/effects/audio_stream_generator.cpp): clear_buffer() has
	# ERR_FAIL_COND(active), so the generator must be INACTIVE before clearing.
	# AudioStreamPlayer.stop() -> playback.active = false -> clear is legal.
	# Then push, then play to restart. Never reset an active generator (that
	# was the pre-fix bug: every impact on a ringing pool player raised a
	# hard engine ERROR on the dummy driver).
	if player.is_playing():
		player.stop()
	pb.clear_buffer()
	if frames.size() > 0 and pb.can_push_buffer(frames.size()):
		pb.push_buffer(frames)
	else:
		push_warning("AudioManager: SFX generator buffer busy (%d frames free) — hit dropped" % pb.get_frames_available())
		return
	player.pitch_scale = pitch
	player.volume_linear = gain
	player.play(0.0)


func _log_no_playback() -> void:
	if _no_playback_warned:
		return
	_no_playback_warned = true
	push_warning("AudioManager: SFX playback unavailable (headless/dummy driver) — play_impact/play_flick are logged no-ops for now")


# --- One-time PCM synthesis ---------------------------------------------------

## The layered thud: a low thump (exponential sine sweep 220->90 Hz, fast exp
## decay) plus a delayed bright click (2600->1400 Hz, very fast decay). Mono,
## duplicated to both channels, so a single push_buffer call plays the whole
## two-layer transient. Roughly 6k frames at 22050 Hz — built once at _ready.
func _build_thud_frames() -> PackedVector2Array:
	var total := int(THUD_DURATION * SFX_MIX_RATE)
	# PackedVector2Array supports append() when constructed as an empty literal
	# (no .new() in 4.7 — proven by aim_overlay._arc_points). Build by append.
	var frames := PackedVector2Array()
	var thump_phase := 0.0
	var click_phase := 0.0
	for i in range(total):
		var t := float(i) / SFX_MIX_RATE
		thump_phase = fmod(thump_phase + _thump_freq(t) / SFX_MIX_RATE, 1.0)
		var sample := sin(thump_phase * TAU) * exp(-THUMP_DECAY * t) * THUMP_GAIN
		var tc := t - CLICK_DELAY
		if tc > 0.0:
			click_phase = fmod(click_phase + _click_freq(tc) / SFX_MIX_RATE, 1.0)
			sample += sin(click_phase * TAU) * exp(-CLICK_DECAY * tc) * CLICK_GAIN
		frames.append(Vector2(clampf(sample, -1.0, 1.0), clampf(sample, -1.0, 1.0)))
	return frames


## The flick tick: one short decaying blip at TICK_FREQ. Pitch variation is
## applied per hit via AudioStreamPlayer.pitch_scale, not baked into the PCM.
func _build_tick_frames() -> PackedVector2Array:
	var total := int(TICK_DURATION * SFX_MIX_RATE)
	var frames := PackedVector2Array()
	var phase := 0.0
	for i in range(total):
		var t := float(i) / SFX_MIX_RATE
		phase = fmod(phase + TICK_FREQ / SFX_MIX_RATE, 1.0)
		var sample := sin(phase * TAU) * exp(-TICK_DECAY * t) * TICK_GAIN
		frames.append(Vector2(sample, sample))
	return frames


func _thump_freq(t: float) -> float:
	var k := minf(t / THUMP_SWEEP_TIME, 1.0)
	return THUMP_F0 + (THUMP_F1 - THUMP_F0) * k


func _click_freq(t: float) -> float:
	return CLICK_F0 + (CLICK_F1 - CLICK_F0) * minf(t / 0.05, 1.0)