class_name BroomFlight
extends Node

## Toggleable broom mount shared by every PlayableCharacter.
## Mount via inventory hotbar when the player has a broom item.
## Broom under Body/BroomMount stays hidden until mounted.

const BroomLocomotionScript := preload("res://scripts/headmaster/broom_locomotion.gd")
const InputPromptScript := preload("res://scripts/ui/input_prompt.gd")
const BroomScene := preload("res://scenes/characters/broom.tscn")
const DroppedBroomScript := preload("res://scripts/headmaster/dropped_broom.gd")
const PlayerInventoryScript := preload("res://scripts/inventory/player_inventory.gd")

@export_group("Flight feel")
@export_range(0.5, 40.0, 0.1, "or_greater") var move_speed: float = (
	BroomLocomotionScript.MAX_SPEED
)
@export_range(0.5, 80.0, 0.1, "or_greater") var sprint_speed: float = 15.0
@export_range(0.0, 40.0, 0.1, "or_greater") var friction: float = (
	BroomLocomotionScript.FRICTION
)
@export_range(0.5, 40.0, 0.1, "or_greater") var acceleration: float = (
	BroomLocomotionScript.ACCEL
)
@export_range(0.5, 40.0, 0.1, "or_greater") var climb_speed: float = (
	BroomLocomotionScript.CLIMB_SPEED
)

var _player: CharacterBody3D
var _active := false
## World-space XZ momentum — camera turns do not redirect coasting.
var _planar_vel := Vector3.ZERO
var _mount_visual: Node3D
var _mount_anchor: Node3D


static func ensure_on(player: CharacterBody3D, _summon_allowed: bool = false) -> Node:
	if player == null:
		return null
	var existing := player.get_node_or_null("BroomFlight")
	if existing != null:
		if existing.has_method("configure"):
			existing.call("configure", player)
		return existing
	var flight = new()
	flight.name = "BroomFlight"
	player.add_child(flight)
	flight.configure(player)
	return flight


func configure(player: CharacterBody3D) -> void:
	_player = player


func is_active() -> bool:
	return _active


func get_planar_velocity() -> Vector3:
	return _planar_vel


func get_prompt() -> String:
	if _active:
		var action := _broom_hotbar_action()
		if action.is_empty():
			return "Dismount broom"
		return InputPromptScript.with_action(action, "Dismount broom")
	if _has_broom():
		var action := _broom_hotbar_action()
		if action.is_empty():
			return "Mount broom (move to hotbar 1–4)"
		return InputPromptScript.with_action(action, "Mount broom")
	return ""


func _ready() -> void:
	if _player == null:
		_player = get_parent() as CharacterBody3D
	_ensure_mount_visual()
	_apply_mount_pose(false)


func mount() -> void:
	if _active or _player == null:
		return
	if not _has_broom():
		return
	_active = true
	_planar_vel = Vector3.ZERO
	_ensure_mount_visual()
	_apply_mount_pose(true)
	_sync_player_broom_flag(true)


func mount_world_broom() -> void:
	## Pick up a world broom: add to inventory and mount.
	if _active or _player == null:
		return
	var inventory := _inventory()
	if inventory != null and inventory.has_method("has") and inventory.has_method("add"):
		if not bool(inventory.call("has", PlayerInventoryScript.ITEM_BROOM)):
			inventory.call("add", PlayerInventoryScript.ITEM_BROOM)
	mount()


func dismount(drop_to_world: bool) -> void:
	if not _active:
		return
	var drop_vel := _planar_vel
	var drop_pos := Vector3.ZERO
	if _player != null:
		drop_pos = _player.global_position
	_active = false
	_planar_vel = Vector3.ZERO
	_apply_mount_pose(false)
	_sync_player_broom_flag(false)
	if drop_to_world and _player != null:
		_revoke_broom()
		DroppedBroomScript.spawn_networked(drop_pos, drop_vel, _player)


func knock_off(_fireball_dir: Vector3) -> void:
	if not _active or _player == null:
		return
	var broom_vel := _planar_vel
	if broom_vel.length_squared() < 2.25:
		var forward := _facing_forward()
		broom_vel = BroomLocomotionScript.flat_forward(forward) * 1.5
	broom_vel.y = 2.0
	var drop_pos := _player.global_position
	_active = false
	_planar_vel = Vector3.ZERO
	_revoke_broom()
	_apply_mount_pose(false)
	_sync_player_broom_flag(false)
	DroppedBroomScript.spawn_networked(drop_pos, broom_vel, _player)


func apply_locomotion(player: CharacterBody3D, delta: float, speed_multiplier: float = 1.0) -> void:
	if not _active or player == null:
		return
	var throttle := 0.0
	if Input.is_action_pressed("move_forward"):
		throttle += 1.0
	if Input.is_action_pressed("move_back"):
		throttle -= 1.0
	var strafe := 0.0
	if Input.is_action_pressed("move_right"):
		strafe += 1.0
	if Input.is_action_pressed("move_left"):
		strafe -= 1.0
	var boosting := Input.is_action_pressed("sprint")
	var haste := maxf(speed_multiplier, 0.1)
	var max_speed := (sprint_speed if boosting else move_speed) * haste
	var wish := BroomLocomotionScript.wish_direction(
		_facing_forward(), throttle, strafe
	)
	_planar_vel = BroomLocomotionScript.step_planar_velocity(
		_planar_vel, wish, delta, max_speed, acceleration, friction
	)
	var ascend := Input.is_action_pressed("jump")
	var descend := (
		Input.is_action_pressed("crouch") or Input.is_action_pressed("fly_descend")
	)
	var vertical := BroomLocomotionScript.vertical_velocity(ascend, descend, climb_speed)
	player.velocity.x = _planar_vel.x
	player.velocity.z = _planar_vel.z
	player.velocity.y = vertical


func set_active_visual(active: bool) -> void:
	## Remote peers: show mount/dismount pose from replicated broom_active.
	if active == _active and _mount_visual != null:
		_apply_mount_pose(active)
		return
	_active = active
	if active:
		_ensure_mount_visual()
	_apply_mount_pose(active)


func _inventory() -> Node:
	if _player == null:
		return null
	var inv := _player.get_node_or_null("%PlayerInventory")
	if inv != null:
		return inv
	return _player.get_node_or_null("PlayerInventory")


func _has_broom() -> bool:
	var inventory := _inventory()
	if inventory == null or not inventory.has_method("has"):
		return false
	return bool(inventory.call("has", PlayerInventoryScript.ITEM_BROOM))


func _revoke_broom() -> void:
	var inventory := _inventory()
	if inventory != null and inventory.has_method("remove"):
		inventory.call("remove", PlayerInventoryScript.ITEM_BROOM)


func _broom_hotbar_action() -> String:
	var inventory := _inventory()
	if inventory == null or not inventory.has_method("find_slot"):
		return ""
	var slot := int(inventory.call("find_slot", PlayerInventoryScript.ITEM_BROOM))
	if slot < 0 or slot >= PlayerInventoryScript.HOTBAR_COUNT:
		return ""
	return "hotbar_%d" % (slot + 1)


func _facing_forward() -> Vector3:
	if _player == null:
		return Vector3.FORWARD
	var head: Node3D = _player.get_node_or_null("Head") as Node3D
	if head != null:
		return -head.global_transform.basis.z
	return -_player.global_transform.basis.z


func _ensure_mount_visual() -> void:
	if _mount_visual != null and is_instance_valid(_mount_visual):
		return
	if _player == null:
		return
	## Prefer Body/BroomMount so the broom yaws with the torso, not the camera pitch.
	_mount_anchor = _player.get_node_or_null("Body/BroomMount") as Node3D
	if _mount_anchor == null:
		_mount_anchor = _player.get_node_or_null("BroomMount") as Node3D
	if _mount_anchor == null:
		var body: Node3D = _player.get_node_or_null("Body") as Node3D
		_mount_anchor = Node3D.new()
		_mount_anchor.name = "BroomMount"
		if body != null:
			body.add_child(_mount_anchor)
		else:
			_player.add_child(_mount_anchor)
		_mount_anchor.position = Vector3(0.0, 0.15, -0.15)
		_mount_anchor.rotation_degrees = Vector3(12.0, 0.0, 0.0)
	## Prefer the scene-authored broom under BroomMount; else spawn a runtime copy.
	_mount_visual = _mount_anchor.get_node_or_null("Broom") as Node3D
	if _mount_visual == null:
		_mount_visual = BroomScene.instantiate() as Node3D
		_mount_visual.name = "Broom"
		_mount_anchor.add_child(_mount_visual)
		_mount_visual.visible = false


func _apply_mount_pose(mounted: bool) -> void:
	_ensure_mount_visual()
	## Anchor must stay visible; only the broom mesh toggles.
	if _mount_anchor != null:
		_mount_anchor.visible = true
	if _mount_visual != null:
		_mount_visual.visible = mounted


func _sync_player_broom_flag(active: bool) -> void:
	if _player != null:
		_player.set("broom_active", active)
