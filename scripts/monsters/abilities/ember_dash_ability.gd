@tool
class_name EmberDashAbility
extends "res://scripts/monsters/monster_ability.gd"

## Chase reposition: straight-line dash behind the player with a burning ground trail.

const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const EmberDashTrailSegmentScript := preload(
	"res://scripts/monsters/abilities/ember_dash_trail_segment.gd"
)
const GameWorldScript := preload("res://scripts/game_world.gd")

const ARRIVE_EPS := 0.4
const MAX_DASH_SEC := 2.5
const MONSTER_BODY_RADIUS := 0.2

@export_range(1.0, 5.0, 0.05) var speed_multiplier: float = 4.05
@export_range(0.0, 1.0, 0.05) var post_cast_dash_chance: float = 0.75
@export_range(0.0, 1.0, 0.05) var reposition_dash_chance: float = 0.3
@export_range(0.2, 1.0, 0.05) var landing_distance_mult: float = 0.7
@export_range(0.05, 0.95, 0.01) var low_health_reset_ratio: float = 0.35
@export_range(1.0, 2.0, 0.05) var trail_width_mult: float = 1.35
@export_range(0.1, 1.5, 0.05) var trail_segment_spacing: float = 0.35
@export_range(0.5, 12.0, 0.25) var trail_lifetime_sec: float = 4.0
@export_range(0.0, 30.0, 0.5) var burn_dps: float = 6.0
@export_range(0.05, 1.0, 0.05) var burn_slow_multiplier: float = 0.75
@export_range(0.1, 2.0, 0.05) var burn_refresh_sec: float = 0.5

var _dashing := false
var _dash_dir := Vector3.ZERO
var _dash_goal := Vector3.ZERO
var _dash_time_left := 0.0
var _trail_dist_accum := 0.0


func _ready() -> void:
	participates_in_cast_rotation = false
	if ability_id.is_empty():
		ability_id = "ember_dash"
	if display_name == "Ability":
		display_name = "Ember Dash"
	description = (
		"Dash across the player's view to land behind them, leaving a burning trail. "
		+ "Often follows a spell cast."
	)
	telegraph_color = Color(1.0, 0.15, 0.05, 1.0)
	cooldown_sec = 9.0
	windup_sec = 0.0
	requires_target = true
	requires_chase_target = true
	min_cast_range = 0.0
	max_cast_range = 40.0


func can_dash(monster: Node3D, target: Node3D) -> bool:
	if not can_cast():
		return false
	if monster == null or target == null or not is_instance_valid(target):
		return false
	if not monster.has_method("is_ai_chasing") or not monster.is_ai_chasing():
		return false
	var landing := _compute_landing(monster, target)
	var flat := landing - monster.global_position
	flat.y = 0.0
	return flat.length_squared() > 0.25


func is_dashing() -> bool:
	return _dashing


func fire_instant(monster: Node3D, target: Node3D) -> void:
	if not can_dash(monster, target):
		return
	start_dash(monster, target)


func fire_combo_step(monster: Node3D, target: Node3D) -> void:
	reset_for_combo()
	if monster == null or target == null or not is_instance_valid(target):
		return
	start_dash(monster, target)


func start_dash(monster: Node3D, target: Node3D) -> void:
	_dash_goal = _compute_landing(monster, target)
	var flat := _dash_goal - monster.global_position
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	_dash_dir = flat.normalized()
	_dashing = true
	_dash_time_left = MAX_DASH_SEC
	_trail_dist_accum = 0.0
	begin_cooldown()


func tick_dash(monster: CharacterBody3D, delta: float) -> bool:
	if not _dashing or monster == null:
		return false
	if _is_blocked_ahead(monster, delta):
		_end_dash(monster)
		return false
	_dash_time_left -= delta
	var speed := float(monster.get("move_speed")) * speed_multiplier
	monster.velocity.x = _dash_dir.x * speed
	monster.velocity.z = _dash_dir.z * speed
	if monster.has_method("_face_horizontal"):
		monster.call("_face_horizontal", _dash_dir)
	_spawn_trail_along_path(monster, delta, speed)
	var to_goal := _dash_goal - monster.global_position
	to_goal.y = 0.0
	if to_goal.length() <= ARRIVE_EPS or _dash_time_left <= 0.0:
		_end_dash(monster)
	return true


func _end_dash(monster: Node3D) -> void:
	_dashing = false
	if monster != null:
		monster.velocity.x = 0.0
		monster.velocity.z = 0.0


func _is_blocked_ahead(monster: CharacterBody3D, delta: float) -> bool:
	var world := monster.get_world_3d()
	if world == null:
		return false
	var speed := float(monster.get("move_speed")) * speed_multiplier
	var from := monster.global_position + Vector3(0.0, 0.35, 0.0)
	var to := from + _dash_dir * speed * delta * 1.25
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [monster.get_rid()]
	var hit := world.direct_space_state.intersect_ray(query)
	return not hit.is_empty()


func _spawn_trail_along_path(monster: Node3D, delta: float, speed: float) -> void:
	var step := speed * delta
	_trail_dist_accum += step
	if _trail_dist_accum < trail_segment_spacing:
		return
	_trail_dist_accum = 0.0
	var parent := _trail_parent(monster)
	var width := MONSTER_BODY_RADIUS * 2.0 * trail_width_mult
	EmberDashTrailSegmentScript.spawn(
		parent,
		monster.global_position,
		_dash_dir,
		width,
		trail_segment_spacing,
		trail_lifetime_sec,
		burn_dps,
		burn_slow_multiplier,
		burn_refresh_sec
	)


func _compute_landing(monster: Node3D, target: Node3D) -> Vector3:
	var max_cast := _max_combat_range(monster) * landing_distance_mult
	var max_dist := MonsterAIScript.max_aggro_move_distance(float(monster.get("chase_range")))
	return MonsterAIScript.pick_dash_landing_behind(
		monster.global_position, target, max_cast, max_dist
	)


func _max_combat_range(monster: Node3D) -> float:
	var best := 13.0
	var root := monster.get_node_or_null("Abilities")
	if root == null:
		return best
	for child in root.get_children():
		if child == self:
			continue
		if "max_cast_range" in child and bool(child.get("participates_in_cast_rotation")):
			best = maxf(best, float(child.get("max_cast_range")))
	return best


func _trail_parent(monster: Node3D) -> Node:
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
