@tool
class_name StreakSmoke
extends Node3D

## World-space 3D tube smoke for flare lookdev / gameplay.
## Modes: [method begin_trail] (path streak) and [method begin_rising] (locked rising column).
## Trail and Rising each have independent inspector settings. No billboards.

enum Mode { IDLE, TRAIL, RISING }

const RING_SIDES := 8

@export_group("Trail")
## World-space distance between trail samples along the tip path.
@export_range(0.02, 0.5, 0.01) var trail_sample_spacing: float = 0.06
## Base tube radius for fresh trail smoke.
@export_range(0.02, 0.6, 0.005) var trail_tube_radius: float = 0.11
## How much trail radius grows as a sample ages (1 = no growth).
@export_range(1.0, 3.0, 0.05) var trail_radius_grow: float = 1.55
## Seconds a trail sample lives before fully fading out.
@export_range(0.5, 20.0, 0.1) var trail_point_lifetime: float = 5.5
## Life fraction (0–1) where trail alpha fade begins. Lower = starts dissolving sooner.
@export_range(0.0, 0.95, 0.01) var trail_fade_start: float = 0.35
## Lifetime scale for smoke emitted at stream start. Lower = launch smoke dies faster.
@export_range(0.05, 1.0, 0.01) var trail_early_life_scale: float = 0.28
## Lifetime scale for smoke emitted later in the stream (1 = full trail_point_lifetime).
@export_range(0.05, 2.0, 0.01) var trail_late_life_scale: float = 1.0
## Seconds of streaming over which lifetime ramps from early → late scale.
@export_range(0.2, 12.0, 0.1) var trail_life_ramp_sec: float = 1.8
## Max trail samples. On overflow, older samples are thinned so the path stays long.
@export_range(64, 2048, 1) var trail_max_points: int = 1024
## Sideways wobble strength along the trail (0 = straight tube).
@export_range(0.0, 2.0, 0.01) var trail_oscillation_amplitude: float = 0.12
## How tightly the trail wobble snakes along its length / over time.
@export_range(0.05, 8.0, 0.05) var trail_oscillation_frequency: float = 1.4
## Fresh trail tint (near the tip). Alpha controls opacity.
@export var trail_warm_color: Color = Color(1.0, 0.45, 0.22, 0.75)
## Aged trail tint (toward the fade). Alpha controls opacity.
@export var trail_cool_color: Color = Color(0.55, 0.55, 0.58, 0.28)

@export_group("Rising")
## Upward speed of rising samples (units/sec) before the linger phase.
@export_range(0.2, 8.0, 0.05) var rising_rise_speed: float = 1.35
## Vertical spacing between new rising samples at the mouth.
@export_range(0.05, 1.0, 0.01) var rising_emit_spacing: float = 0.1
## Base tube radius at the rising mouth.
@export_range(0.02, 0.6, 0.005) var rising_tube_radius: float = 0.11
## Seconds a rising sample lives (rise + linger + fade).
@export_range(0.5, 20.0, 0.1) var rising_point_lifetime: float = 5.5
## Life fraction when rise eases to a stop and linger/expand/lighten begins.
@export_range(0.05, 0.9, 0.01) var rising_linger_start: float = 0.3
## Extra radius multiplier applied during linger (1 = no extra expand).
@export_range(1.0, 5.0, 0.05) var rising_linger_expand: float = 2.2
## Max rising samples kept in the column.
@export_range(64, 2048, 1) var rising_max_points: int = 256
## Column lean strength (angle-only; mouth stays fixed). 0 = straight up.
@export_range(0.0, 2.0, 0.01) var rising_oscillation_amplitude: float = 0.22
## How quickly the rising column lean snakes with height / time.
@export_range(0.05, 8.0, 0.05) var rising_oscillation_frequency: float = 1.8
## Height above the mouth before height-based widening starts.
@export_range(0.0, 2.0, 0.01) var rising_spread_start_height: float = 0.08
## Height span over which rising radius reaches rising_spread_amount.
@export_range(0.1, 4.0, 0.05) var rising_spread_distance: float = 0.7
## Max radius multiplier from height-based spread (before linger expand).
@export_range(1.0, 5.0, 0.05) var rising_spread_amount: float = 2.4
## Fresh rising tint near the mouth. Alpha controls opacity.
@export var rising_warm_color: Color = Color(1.0, 0.45, 0.22, 0.75)
## Aged / lingering rising tint. Lightens further toward pale during fade.
@export var rising_cool_color: Color = Color(0.72, 0.74, 0.78, 0.22)

var _mode: Mode = Mode.IDLE
var _tip := Vector3.ZERO
var _has_tip := false
var _tip_node: Node3D
var _last_sample := Vector3.ZERO
var _has_last_sample := false
var _tube: Dictionary = {}
var _has_tube := false
var _rising_emit_accum := 0.0
var _rising_origin := Vector3.ZERO
var _has_rising_origin := false
var _time := 0.0
## Seconds since begin_trail — stamps each sample so early stream can die faster.
var _trail_stream_t := 0.0
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	top_level = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_mesh()
	set_process(true)


## Sample this node's global_position each frame as the smoke tip.
func bind_tip(tip: Node3D) -> void:
	_tip_node = tip


## Explicit tip world position (also works when no tip node is bound).
func follow_tip(global_pos: Vector3) -> void:
	_tip = global_pos
	_has_tip = true


## Start continuous trail mode following the tip.
func begin_trail() -> void:
	_mode = Mode.TRAIL
	_clear_tube()
	_has_last_sample = false
	_rising_emit_accum = 0.0
	_has_rising_origin = false
	_trail_stream_t = 0.0
	_sync_tip_from_node()
	if _has_tip:
		_ensure_tube(false)
		_append_point(_tip, 0.0)
		_last_sample = _tip
		_has_last_sample = true
	_rebuild_mesh()


## Start a single rising column locked at the current tip world position.
func begin_rising() -> void:
	_mode = Mode.RISING
	_clear_tube()
	_has_last_sample = false
	_rising_emit_accum = 0.0
	_trail_stream_t = 0.0
	_sync_tip_from_node()
	## Lock the mouth when rising starts — stream stays put even if the tip moves.
	_rising_origin = _tip if _has_tip else global_position
	_has_rising_origin = true
	_ensure_tube(true)
	## First sample sits above the mouth; the mouth itself is a fixed mesh pin.
	_append_rising_point(maxf(rising_emit_spacing, 0.01), 0.0)
	_rebuild_mesh()


## Stop emitting and clear the tube mesh.
func stop() -> void:
	_mode = Mode.IDLE
	_clear_tube()
	_has_last_sample = false
	_has_rising_origin = false
	_rebuild_mesh()


func _process(delta: float) -> void:
	_time += delta
	_sync_tip_from_node()
	if _mode == Mode.IDLE:
		return
	if _mode == Mode.TRAIL:
		_trail_stream_t += delta
	_age_tube(delta)
	match _mode:
		Mode.TRAIL:
			_step_trail()
		Mode.RISING:
			_step_rising(delta)
	_rebuild_mesh()


func _sync_tip_from_node() -> void:
	if _tip_node != null and is_instance_valid(_tip_node):
		_tip = _tip_node.global_position
		_has_tip = true


func _ensure_mesh() -> void:
	_mesh_instance = get_node_or_null("TubeMesh") as MeshInstance3D
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "TubeMesh"
		_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh_instance)
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.vertex_color_use_as_albedo = true
		_material.albedo_color = Color(1, 1, 1, 1)
		_material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		_material.no_depth_test = false
		## Soft alpha dissolve — don't write opaque depth while fading out.
		_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mesh_instance.material_override = _material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _clear_tube() -> void:
	_tube = {}
	_has_tube = false


func _ensure_tube(rising: bool) -> void:
	if _has_tube:
		_tube["rising"] = rising
		return
	_tube = {
		"points": [],
		"seed": _tip.x + _time,
		"rising": rising,
	}
	_has_tube = true


func _points() -> Array:
	return _tube["points"] as Array


func _append_point(pos: Vector3, age: float) -> void:
	var points := _points()
	points.append({
		"pos": pos,
		"age": age,
		"height": 0.0,
		"emit_t": _trail_stream_t,
	})
	_enforce_point_budget(points, trail_max_points)


func _append_rising_point(height: float, age: float) -> void:
	var points := _points()
	points.append({
		"pos": Vector3.ZERO,
		"age": age,
		"height": height,
		"emit_t": 0.0,
	})
	_enforce_point_budget(points, rising_max_points)


func _enforce_point_budget(points: Array, max_points: int) -> void:
	var budget := maxi(int(max_points), 8)
	while points.size() > budget:
		## Prefer thinning older smoke so the path can stay long behind a fast tip.
		if not _thin_oldest_points(points):
			points.pop_front()


func _thin_oldest_points(points: Array) -> bool:
	## Drop every other sample in the oldest half — keeps length, lowers density.
	var half := int(points.size() / 2.0)
	if half < 4:
		return false
	var removed := false
	var i := half - 1
	while i >= 0:
		points.remove_at(i)
		removed = true
		i -= 2
	return removed


func _active_point_lifetime() -> float:
	if _mode == Mode.RISING:
		return rising_point_lifetime
	return trail_point_lifetime


func _lifetime_for_point(pt: Dictionary) -> float:
	var base := maxf(_active_point_lifetime(), 0.05)
	if _mode != Mode.TRAIL:
		return base
	var ramp := maxf(float(trail_life_ramp_sec), 0.05)
	var emit_t := float(pt.get("emit_t", 0.0))
	var u := clampf(emit_t / ramp, 0.0, 1.0)
	## Ease toward late life so early stream stays short-lived longer into the shot.
	u = u * u
	var early := maxf(float(trail_early_life_scale), 0.05)
	var late := maxf(float(trail_late_life_scale), 0.05)
	var life_scale := lerpf(early, late, u)
	return maxf(base * life_scale, 0.05)


func _fade_start_for_point(pt: Dictionary) -> float:
	var fade_start := clampf(float(_active_fade_start()), 0.0, 0.95)
	if _mode != Mode.TRAIL:
		return fade_start
	## Early stream also begins dissolving sooner in its (already shorter) life.
	var ramp := maxf(float(trail_life_ramp_sec), 0.05)
	var emit_t := float(pt.get("emit_t", 0.0))
	var u := clampf(emit_t / ramp, 0.0, 1.0)
	u = u * u
	var early_fade := clampf(fade_start * 0.45, 0.0, fade_start)
	return lerpf(early_fade, fade_start, u)


func _active_fade_start() -> float:
	if _mode == Mode.RISING:
		## Rising uses the linger window for fade — no separate hard fade dump.
		return rising_linger_start
	return trail_fade_start


func _active_osc_amplitude() -> float:
	if _mode == Mode.RISING:
		return rising_oscillation_amplitude
	return trail_oscillation_amplitude


func _active_osc_frequency() -> float:
	if _mode == Mode.RISING:
		return rising_oscillation_frequency
	return trail_oscillation_frequency


func _active_warm_color() -> Color:
	if _mode == Mode.RISING:
		return rising_warm_color
	return trail_warm_color


func _active_cool_color() -> Color:
	if _mode == Mode.RISING:
		return rising_cool_color
	return trail_cool_color


func _step_trail() -> void:
	if not _has_tip:
		return
	_ensure_tube(false)
	var points := _points()
	if not _has_last_sample or points.is_empty():
		_append_point(_tip, 0.0)
		_last_sample = _tip
		_has_last_sample = true
		return
	var spacing := maxf(trail_sample_spacing, 0.01)
	var delta_pos := _tip - _last_sample
	var dist := delta_pos.length()
	if dist < spacing:
		return
	var steps := int(floor(dist / spacing))
	var dir := delta_pos / dist
	for i in range(1, steps + 1):
		var sample := _last_sample + dir * (spacing * float(i))
		_append_point(sample, 0.0)
	_last_sample = _last_sample + dir * (spacing * float(steps))


func _step_rising(delta: float) -> void:
	if not _has_rising_origin:
		return
	## One continuous column: samples rise, then linger/expand/lighten at the top.
	_ensure_tube(true)
	var points := _points()
	var life := maxf(rising_point_lifetime, 0.05)
	var linger_at := clampf(float(rising_linger_start), 0.05, 0.9)
	for pt in points:
		var age := float(pt["age"])
		var life_t := clampf(age / life, 0.0, 1.0)
		var rise_mul := 1.0
		if life_t > linger_at:
			## Ease rise to a stop so smoke hangs in place while it expands and fades.
			var u := (life_t - linger_at) / maxf(1.0 - linger_at, 0.001)
			u = clampf(u, 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			rise_mul = 1.0 - u
		pt["height"] = float(pt["height"]) + rising_rise_speed * delta * rise_mul
	_rising_emit_accum += rising_rise_speed * delta
	var spacing := maxf(rising_emit_spacing, 0.01)
	while _rising_emit_accum >= spacing:
		_rising_emit_accum -= spacing
		## Spawn just above the locked mouth — never at height 0 (avoids zero-length flicker).
		_append_rising_point(spacing, 0.0)


func _display_pos(pos: Vector3, seed_v: float, along: float) -> Vector3:
	return _oscillate(pos, seed_v, along)


func _rising_origin_pos() -> Vector3:
	return _rising_origin if _has_rising_origin else _tip


func _rising_world_pos(height: float, seed_v: float, life_t: float = 0.0) -> Vector3:
	var origin := _rising_origin_pos()
	var h := maxf(height, 0.0)
	if h <= 0.0:
		return origin
	## Oscillation is lean only: lateral offset scales with height so the mouth never moves.
	var osc_amp := rising_oscillation_amplitude
	if osc_amp <= 0.0001:
		return origin + Vector3(0.0, h, 0.0)
	var osc_freq := rising_oscillation_frequency
	var phase := h * osc_freq + _time * osc_freq + seed_v
	## Calm the lean as smoke ages so the fading tip doesn't sparkle/flicker.
	var lean := osc_amp * h * (1.0 - clampf(life_t, 0.0, 1.0) * 0.9)
	return origin + Vector3(sin(phase) * lean, h, cos(phase * 0.85 + seed_v) * lean)


func _oscillate(pos: Vector3, seed_v: float, along: float) -> Vector3:
	var osc_amp := _active_osc_amplitude()
	if osc_amp <= 0.0001:
		return pos
	var osc_freq := _active_osc_frequency()
	var phase := along * osc_freq + _time * osc_freq + seed_v
	var amp := osc_amp * clampf(along * 0.35 + 0.15, 0.15, 1.0)
	return Vector3(
		pos.x + sin(phase) * amp,
		pos.y,
		pos.z + cos(phase * 0.85 + seed_v) * amp
	)


func _age_tube(delta: float) -> void:
	if not _has_tube:
		return
	## Cull only after full fade (alpha hits 0 at that sample's lifetime).
	var points := _points()
	var kept: Array = []
	for pt in points:
		pt["age"] = float(pt["age"]) + delta
		if float(pt["age"]) < _lifetime_for_point(pt):
			kept.append(pt)
	_tube["points"] = kept


func _rebuild_mesh() -> void:
	_ensure_mesh()
	if not _has_tube:
		_mesh_instance.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if not _emit_tube(st):
		_mesh_instance.mesh = null
		return
	st.generate_normals()
	_mesh_instance.mesh = st.commit()
	## Mesh is authored in world space while this node is top_level at identity.
	global_transform = Transform3D.IDENTITY


func _emit_tube(st: SurfaceTool) -> bool:
	var points := _points()
	var rising: bool = bool(_tube.get("rising", false))
	if points.is_empty() and not (rising and _has_rising_origin):
		return false
	var seed_v: float = float(_tube.get("seed", 0.0))
	var warm := _active_warm_color()
	var cool := _active_cool_color()
	var centers: Array[Vector3] = []
	var ages: Array[float] = []
	var heights: Array[float] = []
	var lives: Array[float] = []
	var fade_starts: Array[float] = []
	var along_acc := 0.0
	var min_rising_h := maxf(rising_emit_spacing, 0.01) * 0.35
	for i in range(points.size()):
		var pt: Dictionary = points[i]
		var age: float = float(pt["age"])
		var height: float = float(pt.get("height", 0.0))
		## Rising samples too close to the mouth are skipped — mouth is pinned below.
		if rising and height < min_rising_h:
			continue
		var pos: Vector3
		if rising:
			var life := _lifetime_for_point(pt)
			var life_t := clampf(age / maxf(life, 0.05), 0.0, 1.0)
			pos = _rising_world_pos(height, seed_v, life_t)
		else:
			pos = _display_pos(pt["pos"], seed_v, along_acc)
		if not centers.is_empty():
			along_acc += centers[centers.size() - 1].distance_to(pos)
		centers.append(pos)
		ages.append(age)
		heights.append(height)
		lives.append(_lifetime_for_point(pt))
		fade_starts.append(_fade_start_for_point(pt))
	## Rising mouth is a fixed world pin — never oscillated, never aged.
	if rising and _has_rising_origin:
		var mouth := _rising_origin_pos()
		if centers.is_empty() or centers[centers.size() - 1].distance_to(mouth) > 0.0001:
			centers.append(mouth)
			ages.append(0.0)
			heights.append(0.0)
			lives.append(maxf(rising_point_lifetime, 0.05))
			fade_starts.append(clampf(float(rising_linger_start), 0.05, 0.9))
	## Keep the live tip attached so the tube never gaps off the emitter.
	elif _mode == Mode.TRAIL and not rising and _has_tip:
		var tip_pos := _display_pos(_tip, seed_v, along_acc)
		var needs_tip := centers.is_empty()
		if not needs_tip:
			needs_tip = centers[centers.size() - 1].distance_to(tip_pos) > 0.001
		if needs_tip or centers.size() < 2:
			var tip_pt := {"emit_t": _trail_stream_t, "age": 0.0}
			centers.append(tip_pos)
			ages.append(0.0)
			heights.append(0.0)
			lives.append(_lifetime_for_point(tip_pt))
			fade_starts.append(_fade_start_for_point(tip_pt))
	if centers.size() < 2:
		return false
	var frames: Array = _parallel_transport_frames(centers)
	var wrote := false
	for i in range(centers.size() - 1):
		var life_a := maxf(lives[i], 0.05)
		var life_b := maxf(lives[i + 1], 0.05)
		var life_t_a := clampf(ages[i] / life_a, 0.0, 1.0)
		var life_t_b := clampf(ages[i + 1] / life_b, 0.0, 1.0)
		var radius_a := _radius_at(life_t_a, heights[i], rising)
		var radius_b := _radius_at(life_t_b, heights[i + 1], rising)
		var color_a := _color_at(life_t_a, warm, cool, fade_starts[i], rising)
		var color_b := _color_at(life_t_b, warm, cool, fade_starts[i + 1], rising)
		## Never hard-skip rising tip segments — that pops the column top and flickers.
		if not rising and color_a.a <= 0.008 and color_b.a <= 0.008:
			continue
		_emit_tube_segment(
			st,
			centers[i],
			frames[i],
			radius_a,
			color_a,
			centers[i + 1],
			frames[i + 1],
			radius_b,
			color_b
		)
		wrote = true
	return wrote


func _color_at(
	life_t: float,
	warm: Color,
	cool: Color,
	fade_start: float = -1.0,
	rising: bool = false
) -> Color:
	if rising:
		return _rising_color_at(life_t, warm, cool)
	## Trail: color cools with age; alpha dissolves by end of lifetime.
	var color := warm.lerp(cool, life_t)
	var base_a := lerpf(warm.a, cool.a, life_t)
	var start := fade_start
	if start < 0.0:
		start = clampf(float(_active_fade_start()), 0.0, 0.95)
	else:
		start = clampf(start, 0.0, 0.95)
	if life_t <= start:
		color.a = base_a
		return color
	var fade_t := (life_t - start) / maxf(1.0 - start, 0.001)
	fade_t = clampf(fade_t, 0.0, 1.0)
	fade_t = fade_t * fade_t * (3.0 - 2.0 * fade_t)
	color.a = base_a * pow(1.0 - fade_t, 0.85)
	return color


func _rising_color_at(life_t: float, warm: Color, cool: Color) -> Color:
	## Rise → linger: hang, lighten, expand visually, then slowly dissolve (no hard dump).
	var linger_at := clampf(float(rising_linger_start), 0.05, 0.9)
	var color := warm.lerp(cool, clampf(life_t / maxf(linger_at, 0.05), 0.0, 1.0))
	var base_a := lerpf(warm.a, cool.a, clampf(life_t, 0.0, 1.0))
	if life_t <= linger_at:
		color.a = base_a
		return color
	var linger_t := (life_t - linger_at) / maxf(1.0 - linger_at, 0.001)
	linger_t = clampf(linger_t, 0.0, 1.0)
	## Lighten toward soft pale smoke while hanging in place.
	var pale := Color(0.88, 0.9, 0.93, base_a)
	color = color.lerp(pale, linger_t)
	## Slow dissolve across the full linger window — stays readable, then eases away.
	color.a = base_a * pow(1.0 - linger_t, 0.75)
	return color


func _radius_at(life_t: float, height: float, rising: bool) -> float:
	if rising:
		var span := maxf(rising_spread_distance, 0.05)
		var spread_t := clampf((height - rising_spread_start_height) / span, 0.0, 1.0)
		var radius := rising_tube_radius * lerpf(1.0, rising_spread_amount, spread_t)
		## During linger, expand further instead of thinning.
		var linger_at := clampf(float(rising_linger_start), 0.05, 0.9)
		if life_t > linger_at:
			var linger_t := (life_t - linger_at) / maxf(1.0 - linger_at, 0.001)
			linger_t = clampf(linger_t, 0.0, 1.0)
			linger_t = linger_t * linger_t * (3.0 - 2.0 * linger_t)
			radius *= lerpf(1.0, maxf(float(rising_linger_expand), 1.0), linger_t)
		return radius
	return trail_tube_radius * lerpf(1.0, trail_radius_grow, life_t)


func _parallel_transport_frames(centers: Array[Vector3]) -> Array:
	## Keep ring sides aligned along the path so segments don't twist into gaps.
	var frames: Array = []
	if centers.is_empty():
		return frames
	var tangent := Vector3.FORWARD
	if centers.size() >= 2:
		tangent = centers[1] - centers[0]
	if tangent.length_squared() < 0.000001:
		tangent = Vector3.UP
	tangent = tangent.normalized()
	var normal := Vector3.UP
	if absf(tangent.dot(normal)) > 0.92:
		normal = Vector3.RIGHT
	normal = tangent.cross(normal).cross(tangent).normalized()
	var binormal := tangent.cross(normal).normalized()
	frames.append({"tangent": tangent, "normal": normal, "binormal": binormal})
	for i in range(1, centers.size()):
		var prev_t: Vector3 = frames[i - 1]["tangent"]
		var next_t := centers[i] - centers[i - 1]
		if i + 1 < centers.size():
			next_t = centers[i + 1] - centers[i]
		if next_t.length_squared() < 0.000001:
			next_t = prev_t
		next_t = next_t.normalized()
		var prev_n: Vector3 = frames[i - 1]["normal"]
		var axis := prev_t.cross(next_t)
		var next_n := prev_n
		if axis.length_squared() > 0.000001:
			var angle := atan2(axis.length(), clampf(prev_t.dot(next_t), -1.0, 1.0))
			next_n = prev_n.rotated(axis.normalized(), angle).normalized()
		## Re-orthonormalize against the new tangent.
		next_n = next_t.cross(next_n).cross(next_t).normalized()
		var next_b := next_t.cross(next_n).normalized()
		frames.append({"tangent": next_t, "normal": next_n, "binormal": next_b})
	return frames


func _emit_tube_segment(
	st: SurfaceTool,
	pos_a: Vector3,
	frame_a: Dictionary,
	radius_a: float,
	color_a: Color,
	pos_b: Vector3,
	frame_b: Dictionary,
	radius_b: float,
	color_b: Color
) -> void:
	var ring_a := _ring_vertices(pos_a, frame_a, radius_a)
	var ring_b := _ring_vertices(pos_b, frame_b, radius_b)
	for side in range(RING_SIDES):
		var n0 := side
		var n1 := (side + 1) % RING_SIDES
		_add_tri(st, ring_a[n0], ring_a[n1], ring_b[n0], color_a, color_a, color_b)
		_add_tri(st, ring_a[n1], ring_b[n1], ring_b[n0], color_a, color_b, color_b)


func _ring_vertices(center: Vector3, frame: Dictionary, radius: float) -> Array[Vector3]:
	var normal: Vector3 = frame["normal"]
	var binormal: Vector3 = frame["binormal"]
	var out: Array[Vector3] = []
	for side in range(RING_SIDES):
		var ang := TAU * float(side) / float(RING_SIDES)
		var offset := (normal * cos(ang) + binormal * sin(ang)) * radius
		out.append(center + offset)
	return out


func _add_tri(
	st: SurfaceTool,
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	c0: Color,
	c1: Color,
	c2: Color
) -> void:
	st.set_color(c0)
	st.add_vertex(p0)
	st.set_color(c1)
	st.add_vertex(p1)
	st.set_color(c2)
	st.add_vertex(p2)
