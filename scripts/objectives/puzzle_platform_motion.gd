class_name PuzzlePlatformMotion
extends RefCounted

## Pure path/stop math for PuzzleMovingPlatformNode, kept separate from the
## scene node so it can be unit tested without a live scene tree.
##
## Two independent little state machines:
## - "waypoint" state drives LINE and POLYGON paths: a platform travels one
##   segment (current -> next) at a time, either looping (closed) or
##   reversing direction at the ends (open / ping-pong), pausing whenever it
##   arrives at a waypoint with a positive dwell time.
## - "circle" state drives CIRCLE paths: a platform sweeps an angle at a
##   constant angular speed, pausing at any stop angle it reaches.
## Both stash any leftover motion after a stop resolves, and cap the number
## of waypoints/stops crossed in one call so a huge delta (or a zero-length
## segment) can't spin the loop forever.
const MAX_CROSSINGS_PER_STEP := 8


## --- Waypoint paths (LINE / POLYGON) ---------------------------------------

static func default_waypoint_state() -> Dictionary:
	return {
		"current": 0,
		"next": 1,
		"progress": 0.0,
		"direction": 1,
		"paused": false,
		"pause_timer": 0.0,
	}


## `points`: Array[Vector3] visited in order. `stop_seconds`: Array[float],
## parallel to `points` — dwell time when arriving at that point (0 = pass
## straight through). `closed`: loop back to point 0, vs. reverse direction
## at the ends (ping-pong). Returns a new state; does not mutate `state`.
static func advance_waypoint_state(
	state: Dictionary,
	points: Array,
	stop_seconds: Array,
	speed: float,
	delta: float,
	closed: bool
) -> Dictionary:
	var s := state.duplicate()
	if points.size() < 2 or speed <= 0.0:
		return s
	_clamp_waypoint_indices(s, points.size())

	if bool(s.get("paused", false)):
		var pause_timer: float = maxf(0.0, float(s.get("pause_timer", 0.0)) - delta)
		s.pause_timer = pause_timer
		if pause_timer <= 0.0:
			s.paused = false
		return s

	var remaining := speed * delta
	var guard := 0
	while remaining > 0.0 and guard < MAX_CROSSINGS_PER_STEP:
		guard += 1
		var a: Vector3 = points[int(s.current)]
		var b: Vector3 = points[int(s.next)]
		var seg_len := a.distance_to(b)
		var progress: float = float(s.progress) + remaining
		if seg_len <= 0.0001 or progress < seg_len:
			s.progress = progress
			remaining = 0.0
			break
		remaining = progress - seg_len
		s.current = s.next
		s.progress = 0.0
		if closed:
			s.next = (int(s.current) + 1) % points.size()
		else:
			if int(s.current) == points.size() - 1:
				s.direction = -1
			elif int(s.current) == 0:
				s.direction = 1
			s.next = int(s.current) + int(s.direction)
		var dwell := 0.0
		if int(s.current) < stop_seconds.size():
			dwell = float(stop_seconds[int(s.current)])
		if dwell > 0.0:
			s.paused = true
			s.pause_timer = dwell
			remaining = 0.0
	return s


static func waypoint_state_position(state: Dictionary, points: Array) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	if points.size() == 1:
		return points[0]
	var current: int = clampi(int(state.get("current", 0)), 0, points.size() - 1)
	var next: int = clampi(int(state.get("next", 1)), 0, points.size() - 1)
	var a: Vector3 = points[current]
	var b: Vector3 = points[next]
	var seg_len := a.distance_to(b)
	var progress := float(state.get("progress", 0.0))
	var t := 0.0 if seg_len <= 0.0001 else clampf(progress / seg_len, 0.0, 1.0)
	return a.lerp(b, t)


static func _clamp_waypoint_indices(state: Dictionary, point_count: int) -> void:
	if int(state.get("current", 0)) >= point_count or int(state.get("next", 1)) >= point_count:
		state.current = 0
		state.next = 1
		state.progress = 0.0


## --- Circle paths -----------------------------------------------------------

static func default_circle_state() -> Dictionary:
	return {"angle": 0.0, "paused": false, "pause_timer": 0.0}


## `stops`: Array of {"angle": float radians, "seconds": float}. Sweeps at
## `speed / radius` rad/s, always increasing angle (one direction).
static func advance_circle_state(
	state: Dictionary, stops: Array, radius: float, speed: float, delta: float
) -> Dictionary:
	var s := state.duplicate()
	if radius <= 0.0001 or speed <= 0.0:
		return s

	if bool(s.get("paused", false)):
		var pause_timer: float = maxf(0.0, float(s.get("pause_timer", 0.0)) - delta)
		s.pause_timer = pause_timer
		if pause_timer <= 0.0:
			s.paused = false
		return s

	var angle: float = float(s.get("angle", 0.0))
	var remaining := (speed / radius) * delta
	var guard := 0
	while remaining > 0.0 and guard < MAX_CROSSINGS_PER_STEP and not stops.is_empty():
		guard += 1
		var found := _next_stop_ahead(angle, stops)
		if found.is_empty():
			angle += remaining
			remaining = 0.0
			break
		var gap: float = found.gap
		if remaining < gap:
			angle += remaining
			remaining = 0.0
		else:
			angle += gap
			remaining -= gap
			var dwell: float = float(found.stop.seconds)
			if dwell > 0.0:
				s.paused = true
				s.pause_timer = dwell
				remaining = 0.0
	if stops.is_empty():
		angle += remaining
	s.angle = fposmod(angle, TAU)
	return s


## Nearest stop strictly ahead of `angle` (never the one we're standing on —
## that one needs a full lap before it re-triggers). Empty dict if none.
static func _next_stop_ahead(angle: float, stops: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_gap := INF
	for stop in stops:
		var gap := fposmod(float(stop.angle) - angle, TAU)
		if gap <= 0.0001:
			gap = TAU
		if gap < best_gap:
			best_gap = gap
			best = {"stop": stop, "gap": gap}
	return best


static func circle_position(state: Dictionary, radius: float) -> Vector3:
	var angle: float = float(state.get("angle", 0.0))
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
