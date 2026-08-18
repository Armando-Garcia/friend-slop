@tool
class_name AshIceAbility
extends "res://scripts/monsters/monster_ability.gd"

## Right-hand ice bolts: two curved shots 0.5s apart, then cooldown.

const AshIceProjectileScript := preload(
	"res://scripts/monsters/abilities/ash_ice_projectile.gd"
)
const GameWorldScript := preload("res://scripts/game_world.gd")

@export_range(1, 4, 1) var shots_per_burst: int = 2
@export_range(0.1, 2.0, 0.05) var burst_gap_sec: float = 0.5

var _burst_active: bool = false


func _ready() -> void:
	hand_side = HandSide.RIGHT
	if ability_id.is_empty():
		ability_id = "ash_ice"
	if display_name == "Ability":
		display_name = "Ice Bolt"
	telegraph_color = Color(0.45, 0.8, 1.0, 1.0)
	cooldown_sec = 6.0
	min_cast_range = 3.0
	max_cast_range = 14.0


func can_cast() -> bool:
	return _cooldown_left <= 0.0 and not _burst_active and is_inside_tree()


func reset_for_combo() -> void:
	super.reset_for_combo()
	_burst_active = false


func is_ready_to_cast(monster: Node3D, target: Node3D) -> bool:
	if not can_cast():
		return false
	var aim: Variant = _resolve_aim_point(monster, target)
	if not aim is Vector3:
		return false
	return _is_aim_in_cast_range(monster, aim as Vector3)


func is_target_in_range(monster: Node3D, target: Node3D) -> bool:
	var aim: Variant = _resolve_aim_point(monster, target)
	if not aim is Vector3:
		return false
	return _is_aim_in_cast_range(monster, aim as Vector3)


func begin_cast(monster: Node3D, target: Node3D) -> void:
	stop_windup_fx()
	_run_burst(monster, target)


func release_charge(monster: Node3D, target: Node3D) -> void:
	stop_windup_fx()
	_run_burst(monster, target)


func start_windup_fx(monster: Node3D) -> void:
	stop_windup_fx()
	var hand := resolve_hand(monster)
	if hand == null:
		return
	_windup_fx = Node3D.new()
	_windup_fx.name = "AshIceWindup"
	hand.add_child(_windup_fx)

	var glow := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	glow.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 0.85, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.75, 1.0)
	mat.emission_energy_multiplier = 4.5
	glow.material_override = mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_windup_fx.add_child(glow)

	var light := OmniLight3D.new()
	light.light_color = Color(0.45, 0.8, 1.0)
	light.light_energy = 3.2
	light.omni_range = 1.4
	light.shadow_enabled = false
	_windup_fx.add_child(light)


func _fire_cast(monster: Node3D, target: Node3D) -> void:
	## Preview Cast path — fire the full burst without waiting for AI windup.
	_run_burst(monster, target)


func _run_burst(monster: Node3D, target: Node3D) -> void:
	if _burst_active:
		return
	if monster == null:
		return
	_burst_active = true
	var shots := maxi(shots_per_burst, 1)
	for i in shots:
		if not is_inside_tree():
			break
		if monster == null or not is_instance_valid(monster):
			break
		var aim: Variant = _resolve_aim_point(monster, target)
		if not aim is Vector3:
			break
		var side := 1.0 if (i % 2) == 0 else -1.0
		_spawn_bolt_at(monster, aim as Vector3, side)
		if i < shots - 1:
			var tree := get_tree()
			if tree == null:
				break
			await tree.create_timer(burst_gap_sec).timeout
	begin_cooldown()
	_burst_active = false


func _spawn_bolt_at(monster: Node3D, aim: Vector3, side_sign: float) -> void:
	var parent := _projectile_parent(monster)
	var origin := resolve_cast_origin(monster)
	AshIceProjectileScript.spawn_toward_point(parent, origin, aim, monster, side_sign)


func _resolve_aim_point(monster: Node3D, target: Node3D) -> Variant:
	var live := _get_aggro_player(monster)
	if live != null:
		return live.global_position
	if monster != null and monster.has_method("get_last_aggro_player_aim"):
		var last = monster.call("get_last_aggro_player_aim")
		if last is Vector3:
			return last
	if target != null and is_instance_valid(target) and target.is_in_group("player"):
		return target.global_position
	return null


func _get_aggro_player(monster: Node3D) -> Node3D:
	if monster != null and monster.has_method("get_aggro_player_target"):
		var aggro: Variant = monster.call("get_aggro_player_target")
		if aggro is Node3D and is_instance_valid(aggro as Node3D):
			return aggro as Node3D
	return null


func _is_aim_in_cast_range(monster: Node3D, aim: Vector3) -> bool:
	if monster == null:
		return false
	var flat := Vector3(
		aim.x - monster.global_position.x,
		0.0,
		aim.z - monster.global_position.z
	)
	var dist := flat.length()
	return dist >= min_cast_range and dist <= max_cast_range


func _projectile_parent(monster: Node3D) -> Node:
	if has_meta("lookdev_preview_parent"):
		var preview_parent = get_meta("lookdev_preview_parent")
		if preview_parent is Node and is_instance_valid(preview_parent):
			return preview_parent as Node
	var tree := monster.get_tree() if monster != null else get_tree()
	if tree != null:
		var match_root := GameWorldScript.find_match_root(tree)
		if match_root != null:
			return match_root
		if tree.current_scene != null:
			return tree.current_scene
	return monster.get_parent() if monster != null else self
