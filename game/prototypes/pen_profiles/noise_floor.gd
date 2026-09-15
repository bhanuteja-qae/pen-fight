extends SceneTree
## Wave-1 noise floor for the pen-profile prototype (issue #8).
##
## Runs ONE baseline config (Cobalt/Control) over a fixed set of K=20 seeds and
## reports per-metric mean/stddev. Wave 2 may call a parameter range "measured"
## only when its effect exceeds this spread. If the effect sits inside these
## stddevs, then the effect does not exceed noise, and that is said plainly.
##
## Run (project root is game/):
##   godot --headless --path game --script res://prototypes/pen_profiles/noise_floor.gd

const ProfileSweep = preload("res://prototypes/pen_profiles/profile_sweep.gd")

const PROFILE_NAME := "cobalt_control"
const BASELINE_MASS := 1.0
const BASELINE_LINEAR_DAMP := 2.0
const BASELINE_ANGULAR_DAMP := 1.5

## Fixed seed set. Never add/remove seeds to save time (contract budget rule:
## reduce shots, never seeds).
const SEEDS: Array[int] = [
	1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
	11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
]

## Baseline flights are ~2-3 s of simulated time and headless physics runs at
## wall-clock 1x, so the 20xK budget must stay well under the 300 s gate.
const SHOTS_PER_RUN := 4

const PER_SHOT_METRICS: Array[String] = [
	"travel_px", "peak_speed", "settle_time_s",
	"contact_impulse", "angular_travel_deg", "dispersion_deg",
]
const RATE_METRICS: Array[String] = ["self_oob_rate", "timed_out_rate"]

const OUT_PATH := "user://pen_profiles_noise_floor.json"


func _init() -> void:
	call_deferred("_drive")


func _drive() -> void:
	var runs: Array = []
	for seed_value in SEEDS:
		var cfg := ProfileSweep.SweepConfig.new()
		cfg.profile_name = PROFILE_NAME
		cfg.mass = BASELINE_MASS
		cfg.linear_damp = BASELINE_LINEAR_DAMP
		cfg.angular_damp = BASELINE_ANGULAR_DAMP
		cfg.seed = seed_value
		cfg.shots = SHOTS_PER_RUN
		var result: Dictionary = await ProfileSweep.run(cfg)
		runs.append(result)
		var agg: Dictionary = result.get("aggregate", {})
		print("noise_floor[seed=%d]: travel_p50=%.1f peak_p50=%.1f settle_p50=%.3f spin_p50=%.1f disp_p50=%.2f oob=%.3f timeout=%.3f" % [
			seed_value,
			float(agg.get("travel_px_p50", 0.0)), float(agg.get("peak_speed_p50", 0.0)),
			float(agg.get("settle_time_s_p50", 0.0)), float(agg.get("angular_travel_deg_p50", 0.0)),
			float(agg.get("dispersion_deg_p50", 0.0)), float(agg.get("self_oob_rate", 0.0)),
			float(agg.get("timed_out_rate", 0.0)),
		])

	var stats := _compute_stats(runs)
	print("noise_floor: per-metric spread over K=%d runs (%d shots/run)" % [SEEDS.size(), SHOTS_PER_RUN])
	for metric in stats.keys():
		var s: Dictionary = stats[metric]
		print("noise_floor: %s mean=%.4f stddev=%.4f min=%.4f max=%.4f" % [
			metric, float(s["mean"]), float(s["stddev"]),
			float(s["min"]), float(s["max"]),
		])

	var out := {
		"profile_name": PROFILE_NAME,
		"mass": BASELINE_MASS,
		"linear_damp": BASELINE_LINEAR_DAMP,
		"angular_damp": BASELINE_ANGULAR_DAMP,
		"shots_per_run": SHOTS_PER_RUN,
		"seeds": SEEDS,
		"k": SEEDS.size(),
		"stats": stats,
	}
	ProfileSweep.write_json(out, OUT_PATH)
	print("noise_floor: wrote %s" % ProjectSettings.globalize_path(OUT_PATH))
	print("noise_floor: ALL PASS")
	quit(0)


## Per-run metric level -> mean/stddev/min/max across the K runs. Per-shot
## metrics use the run's shot mean; the rates use the run's rate directly.
func _compute_stats(runs: Array) -> Dictionary:
	var stats := {}
	for metric in PER_SHOT_METRICS:
		var values: Array[float] = []
		for result in runs:
			var agg: Dictionary = result.get("aggregate", {})
			var means: Dictionary = agg.get("mean", {})
			values.append(float(means.get(metric, 0.0)))
		stats[metric] = _describe(values)
	for metric in RATE_METRICS:
		var values: Array[float] = []
		for result in runs:
			var agg: Dictionary = result.get("aggregate", {})
			values.append(float(agg.get(metric, 0.0)))
		stats[metric] = _describe(values)
	return stats


func _describe(values: Array[float]) -> Dictionary:
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
