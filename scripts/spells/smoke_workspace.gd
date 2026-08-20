@tool
extends Node3D

## Smoke look-dev studio: trail path preview + rising linger preview.
## Tune StreakSmoke Trail / Rising groups on the child node; does not touch Flare gameplay.

@export_group("Trail preview")
## Helix path radius used by Play Trail Path.
@export_range(0.5, 8.0, 0.1) var trail_path_radius: float = 2.2
## Helix path height used by Play Trail Path.
@export_range(0.5, 6.0, 0.1) var trail_path_height: float = 1.4
## How long a trail/rising preview runs before auto-stopping.
@export_range(2.0, 30.0, 0.5) var trail_duration_sec: float = 8.0
@export_tool_button("Play Trail Path", "Callable")
var play_trail_action := play_trail_preview
@export_tool_button("Play Rising Stream", "Callable")
var play_rising_action := play_rising_preview
@export_tool_button("Stop Smoke", "Callable")
var stop_smoke_action := stop_smoke

var _smoke: StreakSmoke
var _tip: Node3D
var _preview_mode := ""
var _preview_t := 0.0
var _preview_active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cache_nodes()
	set_process(true)


func _process(delta: float) -> void:
	if not _preview_active or _smoke == null or _tip == null:
		return
	_preview_t += delta
	match _preview_mode:
		"trail":
			_tip.global_position = _trail_tip_position(_preview_t)
			_smoke.follow_tip(_tip.global_position)
			_sync_tip_light()
			if _preview_t >= trail_duration_sec:
				_preview_active = false
		"rising":
			_smoke.follow_tip(_tip.global_position)
			_sync_tip_light()
			if _preview_t >= trail_duration_sec:
				_preview_active = false


func _sync_tip_light() -> void:
	var light := get_node_or_null("TipLight") as Node3D
	if light != null and _tip != null:
		light.global_position = _tip.global_position


func play_trail_preview() -> void:
	_cache_nodes()
	if _smoke == null or _tip == null:
		return
	_preview_mode = "trail"
	_preview_t = 0.0
	_preview_active = true
	_tip.global_position = _trail_tip_position(0.0)
	_smoke.follow_tip(_tip.global_position)
	_smoke.begin_trail()


func play_rising_preview() -> void:
	_cache_nodes()
	if _smoke == null or _tip == null:
		return
	_preview_mode = "rising"
	_preview_t = 0.0
	_preview_active = true
	_tip.global_position = Vector3(0.0, 0.35, 0.0)
	_smoke.follow_tip(_tip.global_position)
	_smoke.begin_rising()


func stop_smoke() -> void:
	_preview_active = false
	_preview_mode = ""
	_cache_nodes()
	if _smoke != null:
		_smoke.stop()


func _trail_tip_position(elapsed: float) -> Vector3:
	var u := clampf(elapsed / maxf(trail_duration_sec, 0.01), 0.0, 1.0)
	## Helix-ish path so the trail reads in 3D from the default camera.
	var angle := u * TAU * 1.35
	var x := cos(angle) * trail_path_radius * (0.35 + u * 0.65)
	var z := sin(angle) * trail_path_radius * (0.35 + u * 0.65) - 0.4
	var y := 0.4 + u * trail_path_height + sin(angle * 2.0) * 0.15
	return Vector3(x, y, z)


func _cache_nodes() -> void:
	_smoke = get_node_or_null("StreakSmoke") as StreakSmoke
	_tip = get_node_or_null("DummyTip") as Node3D
	if _smoke != null and _tip != null:
		_smoke.bind_tip(_tip)
