extends SceneTree
## Wave-1 headless measurement harness for the four pen-profile candidates.
##
## Binding contract: docs/prototypes/CONTRACTS-pen-profiles.md (issue #8).
## Owned by Wave 1; Wave 2 sweeps the mass / linear-damping / angular-damping
## levers through SweepConfig and writes the result JSON under results/.
##
## Determinism: a sweep is a pure function of its SweepConfig. The shot pattern
## comes from a RandomNumberGenerator seeded by config.seed and is drawn in a
## fixed order, so every profile sees the identical shots. Identical configs
## produce byte-identical JSON.
##
## Run (project root is game/):
##   godot --headless --path game --script res://prototypes/pen_profiles/profile_sweep.gd

const CONTRACT_PROFILES: Array[String] = [
	"cobalt_control", "graphite_anchor", "ivory_glide", "amber_spin",
]

## Production geometry (game/scenes/main.tscn, never modified): pen capsule
## radius 5.0, height 180.0; table RectangleShape2D 1180x640.
const PEN_RADIUS := 5.0
const PEN_HEIGHT := 180.0
const TABLE_SIZE := Vector2(1180.0, 640.0)

## Launch lane: the harness is a single pen on an empty table (production has no
## walls), so it starts left-of-centre and fans shots along +X where the table
## has the most run-out. Fan + jitter keep the shots on the long axis while still
## exercising skew (spin) and grip offset.
const START_POSITION := Vector2(-420.0, 0.0)
const ANGLE_CENTRE_DEG := 20.0
const ANGLE_SPREAD_DEG := 15.0
const ANGLE_JITTER_DEG := 6.0
const POWER_MIN := 0.4
const POWER_MAX := 1.0

const PHYSICS_HZ := 60.0
const DT := 1.0 / PHYSICS_HZ
## Matches TurnState's 8 s in-flight backstop; a shot still moving at the cap is
## recorded with term="timeout" rather than silently dropped.
const MAX_FLIGHT_FRAMES := 480

const DEFAULT_SEED := 8
const DEFAULT_SHOTS := 12

const COBALT_MASS := 1.0
const COBALT_LINEAR_DAMP := 2.0
const COBALT_ANGULAR_DAMP := 1.5
const ANCHOR_MASS := 1.4


## One sweep request. Frozen by the contract: profile_name | mass | linear_damp |
## angular_damp | seed | shots. `linear_damp` is the body-level value from the
## shipped pen (main.tscn: 2.0); Godot combines it with the 2D default damp.
class SweepConfig:
	var profile_name: String
	var mass: float
	var linear_damp: float
	var angular_damp: float
	var seed: int
	var shots: int


## Run one sweep and return { config, shots[], aggregate }. Await it.
static func run(config: SweepConfig) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("profile_sweep: no SceneTree main loop; cannot run headless sweep")
		return {"config": _config_dict(config), "shots": [], "aggregate": {}}
	return await _run_on_tree(tree, config)


## Wave-2 seed-paired arm: run one config over an explicit seed set and return
## { profile_name, mass, linear_damp, angular_damp, shots_per_run, seeds, k,
##   runs[], stats }. `stats` mirrors noise_floor.gd (per-run metric level ->
## mean/stddev/min/max over the runs) so an arm is directly comparable to the
## Wave-1 floor.
static func run_series(config: SweepConfig, seeds: Array) -> Dictionary:
	var runs: Array = []
	for seed_value in seeds:
		var cfg := SweepConfig.new()
		cfg.profile_name = config.profile_name
		cfg.mass = config.mass
		cfg.linear_damp = config.linear_damp
		cfg.angular_damp = config.angular_damp
		cfg.seed = int(seed_value)
		cfg.shots = config.shots
		var result: Dictionary = await run(cfg)
		runs.append(result)
	return {
		"profile_name": config.profile_name,
		"mass": config.mass,
		"linear_damp": config.linear_damp,
		"angular_damp": config.angular_damp,
		"shots_per_run": config.shots,
		"seeds": seeds,
		"k": seeds.size(),
		"runs": runs,
		"stats": _series_stats(runs),
	}


## Serialize a result deterministically (sorted keys, 6-decimal floats).
static func write_json(result: Dictionary, path: String) -> void:
	var text := JSON.stringify(_round_variant(result), "  ", true)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("profile_sweep: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(text + "\n")
	f.close()


# --- Default gate driver -----------------------------------------------------------

func _init() -> void:
	call_deferred("_drive_default")


func _drive_default() -> void:
	# Wave 2 arm mode (see _parse_arm_args): `-- --out=... [--mass=...] ...`.
	# No `--out` -> the Wave-1 default gate run below is unchanged.
	var args := _parse_arm_args(OS.get_cmdline_user_args())
	if not args.is_empty():
		await _drive_arm(args)
		return

	var baseline := _make_config("cobalt_control", COBALT_MASS, COBALT_LINEAR_DAMP,
		COBALT_ANGULAR_DAMP, DEFAULT_SEED, DEFAULT_SHOTS)
	var anchor := _make_config("graphite_anchor", ANCHOR_MASS, COBALT_LINEAR_DAMP,
		COBALT_ANGULAR_DAMP, DEFAULT_SEED, DEFAULT_SHOTS)

	var baseline_result: Dictionary = await run(baseline)
	print("profile_sweep: " + _aggregate_line(baseline_result))
	var anchor_result: Dictionary = await run(anchor)
	print("profile_sweep: " + _aggregate_line(anchor_result))

	# Wave 1 owns no results/ files: the default run writes outside the repo.
	var path := "user://pen_profiles_wave1_sweep.json"
	write_json({"runs": {"cobalt_control": baseline_result, "graphite_anchor": anchor_result}}, path)
	print("profile_sweep: wrote %s" % ProjectSettings.globalize_path(path))
	print("profile_sweep: ALL PASS")
	quit(0)


static func _make_config(profile_name: String, mass: float, linear_damp: float,
		angular_damp: float, seed_value: int, shots: int) -> SweepConfig:
	var cfg := SweepConfig.new()
	cfg.profile_name = profile_name
	cfg.mass = mass
	cfg.linear_damp = linear_damp
	cfg.angular_damp = angular_damp
	cfg.seed = seed_value
	cfg.shots = shots
	return cfg


# --- Wave-2 CLI arm driver ----------------------------------------------------------

## Parse `key=value` tokens from `OS.get_cmdline_user_args()` (the args after `--`).
## Returns {} unless `--out=...` is present, so the default gate run is untouched.
## Accepted keys (dashes or underscores): arm, profile, mass, linear_damp,
## angular_damp, shots, seed_start, seed_end, out. Values are floats/ints only
## where the sweep expects them; no other CLI surface is added.
static func _parse_arm_args(argv: PackedStringArray) -> Dictionary:
	var raw := {}
	for token in argv:
		var text := str(token)
		if not text.contains("="):
			continue
		var parts := text.split("=", true, 1)
		var key := parts[0].lstrip("-").replace("-", "_")
		raw[key] = parts[1]
	if not raw.has("out"):
		return {}
	return {
		"arm": str(raw.get("arm", "arm")),
		"profile": str(raw.get("profile", "cobalt_control")),
		"mass": float(raw.get("mass", COBALT_MASS)),
		"linear_damp": float(raw.get("linear_damp", COBALT_LINEAR_DAMP)),
		"angular_damp": float(raw.get("angular_damp", COBALT_ANGULAR_DAMP)),
		"shots": int(raw.get("shots", 4)),
		"seed_start": int(raw.get("seed_start", 1)),
		"seed_end": int(raw.get("seed_end", 20)),
		"out": str(raw["out"]),
	}


## Run one arm over an inclusive seed range, write its JSON, print its stats, quit.
func _drive_arm(args: Dictionary) -> void:
	var seeds: Array = []
	for s in range(int(args["seed_start"]), int(args["seed_end"]) + 1):
		seeds.append(s)
	var base := _make_config(str(args["profile"]), float(args["mass"]),
		float(args["linear_damp"]), float(args["angular_damp"]), 0, int(args["shots"]))
	var series: Dictionary = await run_series(base, seeds)
	series["arm"] = str(args["arm"])
	write_json(series, str(args["out"]))
	var stats: Dictionary = series.get("stats", {})
	var tag := str(args["arm"])
	print("profile_sweep[%s]: profile=%s mass=%.3f lin_damp=%.3f ang_damp=%.3f seeds=%d..%d shots=%d k=%d" % [
		tag, str(args["profile"]), float(args["mass"]),
		float(args["linear_damp"]), float(args["angular_damp"]),
		int(args["seed_start"]), int(args["seed_end"]), int(args["shots"]), seeds.size(),
	])
	for metric in stats.keys():
		var st: Dictionary = stats[metric]
		print("profile_sweep[%s]: %s mean=%.4f stddev=%.4f min=%.4f max=%.4f" % [
			tag, metric, float(st["mean"]), float(st["stddev"]),
			float(st["min"]), float(st["max"]),
		])
	print("profile_sweep[%s]: wrote %s" % [tag, ProjectSettings.globalize_path(str(args["out"]))])
	print("profile_sweep[%s]: ALL PASS" % tag)
	quit(0)


# --- World construction (in code; no production scene edits) ------------------------

static func _run_on_tree(tree: SceneTree, config: SweepConfig) -> Dictionary:
	var world := _build_world(tree, config)
	var pen: PenBody = world.get("pen")
	var root: Node = world.get("root")

	var rows: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = config.seed
	for i in range(maxi(config.shots, 0)):
		var dir_deg := _shot_dir_deg(rng, i, config.shots)
		var power := rng.randf_range(POWER_MIN, POWER_MAX)
		var offset := rng.randf_range(-1.0, 1.0)
		var row: Dictionary = await _run_shot(tree, pen, i, dir_deg, power, offset)
		rows.append(row)

	_free_world(root)

	var result := {
		"config": _config_dict(config),
		"shots": rows,
		"aggregate": _aggregate(rows),
	}
	return result


static func _build_world(tree: SceneTree, config: SweepConfig) -> Dictionary:
	var root: Node = tree.root
	var world := Node2D.new()
	world.name = "PenProfileWorld"
	root.add_child(world)

	var table := Node2D.new()
	table.name = "Table"
	world.add_child(table)
	var table_shape := CollisionShape2D.new()
	var table_rect := RectangleShape2D.new()
	table_rect.size = TABLE_SIZE
	table_shape.shape = table_rect
	table.add_child(table_shape)

	var pen := PenBody.new()
	pen.pen_id = "red"
	# Profile levers are applied ONLY as RigidBody2D runtime properties.
	pen.mass = config.mass
	pen.linear_damp = config.linear_damp
	pen.angular_damp = config.angular_damp
	pen.contact_monitor = true
	pen.max_contacts_reported = 4
	pen.position = START_POSITION
	# Children must exist before the pen enters the tree so _ready() reads the
	# capsule and resolves the table on the same frame.
	var pen_shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = PEN_RADIUS
	capsule.height = PEN_HEIGHT
	pen_shape.shape = capsule
	pen_shape.rotation = PI * 0.5
	pen.add_child(pen_shape)
	world.add_child(pen)

	return {"root": root, "world": world, "pen": pen}


static func _free_world(root: Node) -> void:
	if root == null:
		return
	var world: Node = root.get_node_or_null("PenProfileWorld")
	if world == null:
		return
	root.remove_child(world)
	world.free()


# --- Shot measurement --------------------------------------------------------------

## One seeded shot. `dir_deg` is a fan across ANGLE_SPREAD_DEG with jitter;
## power is a 0..1 human drag fraction and offset is the grip position as a
## fraction of half-length. The profile parameters are already on the body.
static func _run_shot(tree: SceneTree, pen: PenBody, index: int, dir_deg: float,
		power: float, offset: float) -> Dictionary:
	pen.reset()
	pen.rotation = 0.0
	pen.global_position = START_POSITION
	pen.reset_physics_interpolation()

	var dir := Vector2.RIGHT.rotated(deg_to_rad(dir_deg))
	var launch: Vector2 = pen.global_position
	pen.apply_flick(dir, power, offset)

	var last: Vector2 = launch
	var travel_px := 0.0
	var angular_travel_deg := 0.0
	var peak_speed := 0.0
	var quiet_time := 0.0
	var frames := 0
	var term := ""
	while frames < MAX_FLIGHT_FRAMES:
		await tree.physics_frame
		frames += 1
		var pos: Vector2 = pen.global_position
		travel_px += (pos - last).length()
		last = pos
		var spin: float = absf(pen.angular_velocity)
		angular_travel_deg += rad_to_deg(spin) * DT
		var speed: float = pen.linear_velocity.length()
		if speed > peak_speed:
			peak_speed = speed
		if pen.is_out_of_bounds_test():
			term = "oob"
			break
		if speed < PenBody.SETTLE_LINEAR_VEL and spin < PenBody.SETTLE_ANGULAR_VEL:
			quiet_time += DT
			if quiet_time >= PenBody.SETTLE_DEBOUNCE:
				term = "settled"
				break
		else:
			quiet_time = 0.0
	if term == "":
		term = "timeout"

	var displacement: Vector2 = pen.global_position - launch
	var travel_dir: Vector2 = displacement.normalized() if displacement.length() > 0.0001 else dir
	# Pen barrel is the body's local +X (the capsule child is rotated 90 deg).
	var barrel_axis := Vector2.RIGHT.rotated(pen.rotation)
	var dot := absf(barrel_axis.normalized().dot(travel_dir))
	var dispersion_deg := rad_to_deg(acos(clampf(dot, 0.0, 1.0)))

	return {
		"shot": index,
		"power": power,
		"dir_deg": dir_deg,
		"contact_offset": offset,
		"travel_px": travel_px,
		"peak_speed": peak_speed,
		"settle_time_s": float(frames) * DT,
		"contact_impulse": power * PenBody.MAX_IMPULSE,
		"angular_travel_deg": angular_travel_deg,
		"dispersion_deg": dispersion_deg,
		"self_oob": term == "oob",
		"term": term,
	}


static func _shot_dir_deg(rng: RandomNumberGenerator, index: int, shots: int) -> float:
	var t := 0.0 if shots <= 1 else float(index) / float(shots - 1)
	var fan := lerpf(ANGLE_CENTRE_DEG - ANGLE_SPREAD_DEG,
		ANGLE_CENTRE_DEG + ANGLE_SPREAD_DEG, t)
	return fan + rng.randf_range(-ANGLE_JITTER_DEG, ANGLE_JITTER_DEG)


# --- Aggregation -------------------------------------------------------------------

static func _aggregate(rows: Array) -> Dictionary:
	var travel: Array[float] = []
	var peak: Array[float] = []
	var settle: Array[float] = []
	var contact: Array[float] = []
	var spin: Array[float] = []
	var dispersion: Array[float] = []
	var oob_count := 0
	var timeout_count := 0
	for row in rows:
		travel.append(row["travel_px"])
		peak.append(row["peak_speed"])
		settle.append(row["settle_time_s"])
		contact.append(row["contact_impulse"])
		spin.append(row["angular_travel_deg"])
		dispersion.append(row["dispersion_deg"])
		if row["self_oob"]:
			oob_count += 1
		if row["term"] == "timeout":
			timeout_count += 1
	var n := rows.size()
	var denom := maxf(float(n), 1.0)
	return {
		"n": n,
		"self_oob_rate": float(oob_count) / denom,
		"timed_out_rate": float(timeout_count) / denom,
		"travel_px_p50": _p50(travel),
		"peak_speed_p50": _p50(peak),
		"settle_time_s_p50": _p50(settle),
		"contact_impulse_p50": _p50(contact),
		"angular_travel_deg_p50": _p50(spin),
		"dispersion_deg_p50": _p50(dispersion),
		"mean": {
			"travel_px": _mean(travel),
			"peak_speed": _mean(peak),
			"settle_time_s": _mean(settle),
			"contact_impulse": _mean(contact),
			"angular_travel_deg": _mean(spin),
			"dispersion_deg": _mean(dispersion),
		},
	}


static func _p50(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	var mid := n / 2
	if n % 2 == 1:
		return sorted[mid]
	return (sorted[mid - 1] + sorted[mid]) * 0.5


## Wave-2: per-run metric level across the K seed runs -> mean/stddev/min/max,
## exactly matching noise_floor.gd's statistic so arm-vs-floor comparison is
## apples-to-apples. Per-shot metrics use the run's shot mean; rates use the run.
static func _series_stats(runs: Array) -> Dictionary:
	var per_shot: Array[String] = [
		"travel_px", "peak_speed", "settle_time_s",
		"contact_impulse", "angular_travel_deg", "dispersion_deg",
	]
	var rates: Array[String] = ["self_oob_rate", "timed_out_rate"]
	var stats := {}
	for metric in per_shot:
		var values: Array[float] = []
		for result in runs:
			var mean_block: Dictionary = result.get("aggregate", {}).get("mean", {})
			values.append(float(mean_block.get(metric, 0.0)))
		stats[metric] = _describe(values)
	for metric in rates:
		var values: Array[float] = []
		for result in runs:
			values.append(float(result.get("aggregate", {}).get(metric, 0.0)))
		stats[metric] = _describe(values)
	return stats


static func _describe(values: Array[float]) -> Dictionary:
	var n := values.size()
	if n == 0:
		return {"n": 0, "mean": 0.0, "stddev": 0.0, "min": 0.0, "max": 0.0}
	var total := 0.0
	var lo := values[0]
	var hi := values[0]
	for v in values:
		total += v
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var mean := total / float(n)
	var variance := 0.0
	if n > 1:
		var sq := 0.0
		for v in values:
			sq += (v - mean) * (v - mean)
		variance = sq / float(n - 1)
	return {"n": n, "mean": mean, "stddev": sqrt(variance), "min": lo, "max": hi}


static func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / float(values.size())


# --- Formatting helpers ------------------------------------------------------------

static func _config_dict(config: SweepConfig) -> Dictionary:
	return {
		"profile_name": config.profile_name,
		"mass": config.mass,
		"linear_damp": config.linear_damp,
		"angular_damp": config.angular_damp,
		"seed": config.seed,
		"shots": config.shots,
	}


static func _aggregate_line(result: Dictionary) -> String:
	var c: Dictionary = result.get("config", {})
	var a: Dictionary = result.get("aggregate", {})
	return ("%s mass=%.3f lin_damp=%.3f ang_damp=%.3f seed=%d shots=%d | " +
		"travel_p50=%.1f peak_p50=%.1f settle_p50=%.3f contact_p50=%.1f " +
		"spin_p50=%.1f disp_p50=%.2f oob_rate=%.3f timeout_rate=%.3f") % [
		str(c.get("profile_name", "?")), float(c.get("mass", 0.0)),
		float(c.get("linear_damp", 0.0)), float(c.get("angular_damp", 0.0)),
		int(c.get("seed", 0)), int(a.get("n", 0)),
		float(a.get("travel_px_p50", 0.0)), float(a.get("peak_speed_p50", 0.0)),
		float(a.get("settle_time_s_p50", 0.0)), float(a.get("contact_impulse_p50", 0.0)),
		float(a.get("angular_travel_deg_p50", 0.0)), float(a.get("dispersion_deg_p50", 0.0)),
		float(a.get("self_oob_rate", 0.0)), float(a.get("timed_out_rate", 0.0)),
	]


## Round every float to 6 decimals and normalise negative zero so repeated runs
## of the same config serialize to identical bytes (contract determinism rule).
static func _round_variant(value: Variant) -> Variant:
	if value is float:
		var r := snappedf(value, 0.000001)
		if absf(r) < 0.0000005:
			r = 0.0
		return r
	if value is Dictionary:
		var out := {}
		for key in value.keys():
			out[key] = _round_variant(value[key])
		return out
	if value is Array:
		var arr: Array = []
		for item in value:
			arr.append(_round_variant(item))
		return arr
	return value
