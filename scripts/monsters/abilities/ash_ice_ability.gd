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


func begin_cast(monster: Node3D, target: Node3D) -> void:
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
	if monster == null or target == null:
		return
	_burst_active = true
	var shots := maxi(shots_per_burst, 1)
	for i in shots:
		if not is_inside_tree():
			break
		if monster == null or not is_instance_valid(monster):
			break
		var aim := target
		if aim == null or not is_instance_valid(aim):
			break
		var side := 1.0 if (i % 2) == 0 else -1.0
		_spawn_bolt(monster, aim, side)
		if i < shots - 1:
			var tree := get_tree()
			if tree == null:
				break
			await tree.create_timer(burst_gap_sec).timeout
	begin_cooldown()
	_burst_active = false


func _spawn_bolt(monster: Node3D, target: Node3D, side_sign: float) -> void:
	var parent := _projectile_parent(monster)
	var origin := resolve_cast_origin(monster)
	AshIceProjectileScript.spawn(parent, origin, target, monster, side_sign)


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
