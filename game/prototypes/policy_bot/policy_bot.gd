class_name PolicyBot
## A deliberately shallow, live-geometry policy.  It authors a few plausible
## flicks, ranks them from the current snapshot, and leaves the one actual
## outcome entirely to PenBody's normal physics path.

class Snapshot:
	var pen_pos: Vector2 = Vector2.ZERO
	var pen_rot: float = 0.0
	var opp_pos: Vector2 = Vector2.ZERO
	var opp_rot: float = 0.0
	var table_rect: Rect2 = Rect2()
	var oob_margin: float = 13.0


class Candidate:
	var impulse: float = 0.0
	var contact_offset: float = 0.0
	var spin: float = 0.0
	var score: float = 0.0
	# Direction is authored from the live snapshot.  Spin is represented by an
	# off-centre contact and a perpendicular skew in this vector; PenBody owns
	# the resulting torque.
	var direction: Vector2 = Vector2.RIGHT


# Test-only accounting makes the non-simulation boundary observable.  There is
# intentionally no policy operation that can increment _physics_step_attempts.
static var _commit_calls: int = 0
static var _physics_step_attempts: int = 0


static func reset_instrumentation() -> void:
	_commit_calls = 0
	_physics_step_attempts = 0


static func commit_calls() -> int:
	return _commit_calls


static func physics_step_attempts() -> int:
	return _physics_step_attempts


static func candidates(s: Snapshot, persona: String) -> Array[Candidate]:
	var target := s.opp_pos - s.pen_pos
	var distance := target.length()
	var direct := _safe_direction(target, Vector2.UP.rotated(s.pen_rot))
	var center := s.table_rect.get_center()
	var inward := _safe_direction(center - s.pen_pos, -direct)
	var clearance := _edge_clearance(s.pen_pos, s.table_rect, s.oob_margin)
	var authored: Array[Dictionary] = _authored_set(persona)
	var result: Array[Candidate] = []

	for spec in authored:
		var candidate := Candidate.new()
		candidate.impulse = clampf(float(spec["impulse"]), 0.0, 1.0)
		candidate.contact_offset = clampf(float(spec["contact"]), -1.0, 1.0)
		candidate.spin = clampf(float(spec["spin"]), -1.0, 1.0)
		var skew: float = float(spec["skew"])
		candidate.direction = _safe_direction(direct.rotated(skew), direct)
		candidate.score = _score(candidate, persona, direct, inward, distance, clearance)
		result.append(candidate)
	return result


static func choose(s: Snapshot, persona: String, rng: RandomNumberGenerator) -> Candidate:
	var options := candidates(s, persona)
	if options.is_empty():
		return Candidate.new()
	var best := options[0]
	var best_score := best.score + rng.randf_range(-0.035, 0.035)
	for index in range(1, options.size()):
		var option := options[index]
		var noisy_score := option.score + rng.randf_range(-0.035, 0.035)
		if noisy_score > best_score:
			best = option
			best_score = noisy_score
	return best


static func commit(candidate: Candidate, pen_body: PenBody) -> void:
	_commit_calls += 1
	pen_body.apply_flick(candidate.direction, candidate.impulse, candidate.contact_offset)


static func _authored_set(persona: String) -> Array[Dictionary]:
	match persona:
		"spin":
			return [
				{"impulse": 0.64, "contact": -0.88, "spin": -0.85, "skew": -0.29},
				{"impulse": 0.68, "contact": 0.88, "spin": 0.85, "skew": 0.29},
				{"impulse": 0.73, "contact": -0.68, "spin": -0.62, "skew": -0.20},
				{"impulse": 0.73, "contact": 0.68, "spin": 0.62, "skew": 0.20},
				{"impulse": 0.78, "contact": 0.45, "spin": 0.38, "skew": 0.12},
			]
		"edge":
			return [
				{"impulse": 0.78, "contact": 0.18, "spin": 0.12, "skew": -0.13},
				{"impulse": 0.82, "contact": -0.18, "spin": -0.12, "skew": 0.13},
				{"impulse": 0.88, "contact": 0.35, "spin": 0.25, "skew": -0.20},
				{"impulse": 0.88, "contact": -0.35, "spin": -0.25, "skew": 0.20},
				{"impulse": 0.94, "contact": 0.0, "spin": 0.0, "skew": 0.0},
			]
		_:
			return [
				{"impulse": 0.76, "contact": 0.0, "spin": 0.0, "skew": 0.0},
				{"impulse": 0.82, "contact": 0.12, "spin": 0.10, "skew": 0.05},
				{"impulse": 0.82, "contact": -0.12, "spin": -0.10, "skew": -0.05},
				{"impulse": 0.89, "contact": 0.22, "spin": 0.16, "skew": 0.09},
				{"impulse": 0.89, "contact": -0.22, "spin": -0.16, "skew": -0.09},
			]


static func _score(candidate: Candidate, persona: String, direct: Vector2, inward: Vector2, distance: float, clearance: float) -> float:
	var alignment := candidate.direction.dot(direct)
	var safety := maxf(candidate.direction.dot(inward), -0.5)
	var reach := clampf(distance / 600.0, 0.0, 1.0)
	var spin_amount := absf(candidate.spin)
	match persona:
		"spin":
			return alignment * 0.48 + spin_amount * 0.38 + reach * 0.14 + safety * 0.05
		"edge":
			# Near an edge, favour a controlled, straight finishing shove; away from
			# it, retain enough inward safety to avoid a self-elimination habit.
			return alignment * 0.57 + candidate.impulse * 0.18 + (1.0 - clearance) * 0.18 + safety * 0.07
		_:
			return alignment * 0.70 + candidate.impulse * 0.20 + reach * 0.10 + safety * 0.05


static func _safe_direction(value: Vector2, fallback: Vector2) -> Vector2:
	if value.length_squared() > 0.0001:
		return value.normalized()
	if fallback.length_squared() > 0.0001:
		return fallback.normalized()
	return Vector2.RIGHT


static func _edge_clearance(point: Vector2, table: Rect2, margin: float) -> float:
	if table.size.x <= 0.0 or table.size.y <= 0.0:
		return 0.5
	var nearest := minf(minf(point.x - table.position.x, table.end.x - point.x), minf(point.y - table.position.y, table.end.y - point.y))
	var scale := maxf(minf(table.size.x, table.size.y) * 0.5 - margin, 1.0)
	return clampf(nearest / scale, 0.0, 1.0)
