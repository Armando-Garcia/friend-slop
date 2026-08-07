@tool
class_name MonsterAbility
extends Node3D

## Base for authored combat abilities under Monster/Abilities/.
## Scene-tree source of truth — cast FX attach to monster hands when present.

enum HandSide { RIGHT, LEFT }

const WINDUP_SEC_DEFAULT := 0.55

@export var ability_id: String = ""
@export var display_name: String = "Ability"
@export_multiline var description: String = ""
@export_range(0.0, 60.0, 0.1) var cooldown_sec: float = 5.0
@export_range(0.1, 3.0, 0.05) var windup_sec: float = WINDUP_SEC_DEFAULT
@export var telegraph_color: Color = Color(1.0, 0.3, 0.1, 1.0)
@export var hand_side: HandSide = HandSide.RIGHT
## When false, ability can cast without a player target (ambient summons).
@export var requires_target: bool = true
## When true, needs a chase interest target but ignores range bands.
@export var requires_chase_target: bool = false
@export_range(0.0, 30.0, 0.1) var min_cast_range: float = 3.0
@export_range(0.0, 40.0, 0.1) var max_cast_range: float = 12.0

@export_tool_button("Preview Cast", "Callable")
var preview_cast_action := preview_cast

var _cooldown_left: float = 0.0
var _windup_fx: Node3D = null


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)


func get_hand_side() -> HandSide:
	return hand_side


func can_cast() -> bool:
	return _cooldown_left <= 0.0 and is_inside_tree()


func is_ready_to_cast(monster: Node3D, target: Node3D) -> bool:
	if not can_cast():
		return false
	if not requires_target:
		return true
	if requires_chase_target:
		return target != null and is_instance_valid(target)
	return is_target_in_range(monster, target)


func is_target_in_range(monster: Node3D, target: Node3D) -> bool:
	if not requires_target:
		return true
	if requires_chase_target:
		return target != null and is_instance_valid(target)
	if monster == null or target == null:
		return false
	var dist := flat_distance_to(monster, target)
	return dist >= min_cast_range and dist <= max_cast_range


func preferred_cast_range() -> float:
	return (min_cast_range + max_cast_range) * 0.5


func flat_distance_to(monster: Node3D, target: Node3D) -> float:
	if monster == null or target == null:
		return 0.0
	var flat := Vector3(
		target.global_position.x - monster.global_position.x,
		0.0,
		target.global_position.z - monster.global_position.z
	)
	return flat.length()


func begin_cooldown() -> void:
	_cooldown_left = maxf(0.0, cooldown_sec)


## Override: attach windup VFX to the correct hand.
func start_windup_fx(monster: Node3D) -> void:
	stop_windup_fx()
	var hand := resolve_hand(monster)
	if hand == null:
		return
	_windup_fx = _build_default_windup_fx()
	hand.add_child(_windup_fx)


func stop_windup_fx() -> void:
	if _windup_fx != null and is_instance_valid(_windup_fx):
		_windup_fx.queue_free()
	_windup_fx = null


## Override to spawn combat projectile. Called after windup completes.
func begin_cast(monster: Node3D, target: Node3D) -> void:
	stop_windup_fx()
	begin_cooldown()
	_fire_cast(monster, target)


func preview_cast() -> void:
	var monster := _find_monster()
	start_windup_fx(monster)
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(windup_sec).timeout
	if not is_inside_tree():
		return
	if monster != null and is_instance_valid(monster):
		var aim := monster.global_position + (-monster.global_transform.basis.z * 6.0)
		var dummy := Node3D.new()
		dummy.global_position = aim
		monster.get_parent().add_child(dummy)
		_fire_cast(monster, dummy)
		dummy.queue_free()
	stop_windup_fx()


func resolve_hand(monster: Node3D) -> Node3D:
	if monster == null:
		return null
	var path := "%RightHand" if hand_side == HandSide.RIGHT else "%LeftHand"
	var hand := monster.get_node_or_null(path) as Node3D
	if hand != null:
		return hand
	var fallbacks := [
		"Body/Hands/RightHand" if hand_side == HandSide.RIGHT else "Body/Hands/LeftHand",
		"MidBody/Hands/RightHand" if hand_side == HandSide.RIGHT else "MidBody/Hands/LeftHand",
	]
	for fallback in fallbacks:
		hand = monster.get_node_or_null(fallback) as Node3D
		if hand != null:
			return hand
	return null


func resolve_cast_origin(monster: Node3D) -> Vector3:
	var hand := resolve_hand(monster)
	if hand != null:
		return hand.global_position
	if monster != null:
		return monster.global_position + Vector3(0.0, 0.55, 0.0)
	return global_position


func _fire_cast(_monster: Node3D, _target: Node3D) -> void:
	pass


func _find_monster() -> Node3D:
	var n: Node = self
	while n != null:
		if n.is_in_group("monster") or n.has_method("get_ability_placeholders"):
			return n as Node3D
		n = n.get_parent()
	return null


func _build_default_windup_fx() -> Node3D:
	var root := Node3D.new()
	root.name = "WindupFx"
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	sphere.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(telegraph_color.r, telegraph_color.g, telegraph_color.b, 0.7)
	mat.emission_enabled = true
	mat.emission = telegraph_color
	mat.emission_energy_multiplier = 3.5
	sphere.material_override = mat
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sphere)
	var light := OmniLight3D.new()
	light.light_color = telegraph_color
	light.light_energy = 2.4
	light.omni_range = 1.2
	light.shadow_enabled = false
	root.add_child(light)
	return root


func _exit_tree() -> void:
	stop_windup_fx()
