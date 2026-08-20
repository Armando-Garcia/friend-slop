@tool
extends Node3D

## Lit studio for ward look-dev + cast-from-wand preview.
## Select WardWorkspace → Cast preview → Cast Ward (button or cast_now).

const WardShieldScript := preload("res://scripts/spells/ward_shield.gd")
const WardSpell := preload("res://resources/spells/ward.tres")

@export_group("Cast preview")
@export var hide_lookdev_ward_during_cast := true:
	set(value):
		hide_lookdev_ward_during_cast = value
		_refresh_lookdev_visibility()
## Extra push along the wand aim before spawn (0 = tip, same as gameplay).
@export_range(0.0, 1.5, 0.05, "or_greater") var tip_forward_nudge: float = 0.0
@export var cast_now := false:
	get:
		return false
	set(value):
		if value:
			cast_ward_preview()
@export var clear_now := false:
	get:
		return false
	set(value):
		if value:
			clear_cast_preview()
@export_tool_button("Cast Ward", "Callable")
var cast_ward_action := cast_ward_preview
@export_tool_button("Clear Preview", "Callable")
var clear_preview_action := clear_cast_preview

var _preview_ward: Node3D


func _ready() -> void:
	## Editor scene trees are often paused — keep previews ticking.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_cast_bucket()
	_refresh_lookdev_visibility()
	_force_wand_tip_visible()


func _force_wand_tip_visible() -> void:
	## PlayerWand hides tip when disarmed; keep it on for studio look-dev.
	var wand := _wand()
	if wand == null:
		return
	var tip := wand.get_node_or_null("Model/Tip") as Node3D
	if tip == null:
		tip = wand.get_node_or_null("Tip") as Node3D
	if tip != null:
		tip.visible = true


func cast_ward_preview() -> void:
	if not is_inside_tree():
		return
	clear_cast_preview()
	var wand := _wand()
	var origin := Vector3(0.15, 1.05, 1.15)
	var direction := Vector3(0.0, 0.0, -1.0)
	if wand != null:
		origin = _resolve_cast_origin(wand)
		## Workspace has no crosshair — cast along the wand shaft.
		direction = -wand.global_transform.basis.z
		if wand.has_method("play_cast_success"):
			wand.call("play_cast_success", WardSpell, true)
	if direction.length_squared() < 0.0001:
		direction = Vector3(0.0, 0.0, -1.0)
	else:
		direction = direction.normalized()
	origin += direction * tip_forward_nudge
	var bucket := _ensure_cast_bucket()
	_preview_ward = WardShieldScript.spawn(bucket, origin, direction) as Node3D
	if _preview_ward != null:
		_preview_ward.process_mode = Node.PROCESS_MODE_ALWAYS
		_preview_ward.tree_exited.connect(_on_preview_exited, CONNECT_ONE_SHOT)
	_refresh_lookdev_visibility()


func clear_cast_preview() -> void:
	var bucket := get_node_or_null("CastPreview")
	if bucket != null:
		for child in bucket.get_children():
			if Engine.is_editor_hint():
				child.free()
			else:
				child.queue_free()
	_preview_ward = null
	_refresh_lookdev_visibility()


func _on_preview_exited() -> void:
	_preview_ward = null
	_refresh_lookdev_visibility()


func _wand() -> Node3D:
	return get_node_or_null("Wand") as Node3D


func _lookdev_ward() -> Node3D:
	return get_node_or_null("Ward") as Node3D


func _resolve_cast_origin(wand: Node3D) -> Vector3:
	## PlayerWand is not @tool — bind CastOrigin from the scene tree instead.
	var tip := wand.get_node_or_null("Model/CastOrigin") as Node3D
	if tip == null:
		tip = wand.get_node_or_null("CastOrigin") as Node3D
	if tip != null:
		return tip.global_position
	if wand.has_method("get_cast_origin"):
		return wand.call("get_cast_origin") as Vector3
	return wand.global_position


func _ensure_cast_bucket() -> Node3D:
	var bucket := get_node_or_null("CastPreview") as Node3D
	if bucket != null:
		bucket.process_mode = Node.PROCESS_MODE_ALWAYS
		return bucket
	bucket = Node3D.new()
	bucket.name = "CastPreview"
	bucket.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(bucket)
	if Engine.is_editor_hint():
		var root := get_tree().edited_scene_root
		if root != null:
			bucket.owner = root
	return bucket


func _refresh_lookdev_visibility() -> void:
	var lookdev := _lookdev_ward()
	if lookdev == null:
		return
	var preview_live := _preview_ward != null and is_instance_valid(_preview_ward)
	lookdev.visible = not (hide_lookdev_ward_during_cast and preview_live)
