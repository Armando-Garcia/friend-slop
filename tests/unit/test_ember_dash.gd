extends RefCounted

const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const EmberDashAbilityScript := preload(
	"res://scripts/monsters/abilities/ember_dash_ability.gd"
)


func run() -> int:
	var failures := 0
	failures += _test_player_facing_flat()
	failures += _test_pick_dash_landing_behind()
	failures += _test_dash_direction_locked()
	failures += _test_dash_cooldown_reset()
	return failures


func _test_player_facing_flat() -> int:
	var player := Node3D.new()
	player.transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var forward := MonsterAIScript.player_facing_flat(player)
	if forward.length_squared() < 0.9:
		push_error("Expected default player facing to be unit length")
		return 1
	player.queue_free()
	return 0


func _test_pick_dash_landing_behind() -> int:
	var player := Node3D.new()
	player.global_position = Vector3(0.0, 0.0, 0.0)
	player.transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var monster_pos := Vector3(2.0, 0.0, 1.0)
	var max_dist := MonsterAIScript.max_aggro_move_distance(14.0)
	var landing := MonsterAIScript.pick_dash_landing_behind(
		monster_pos, player, 13.0, max_dist
	)
	var forward := MonsterAIScript.player_facing_flat(player)
	var to_landing := landing - player.global_position
	to_landing.y = 0.0
	if to_landing.dot(forward) >= 0.0:
		push_error("Expected dash landing behind player facing")
		player.queue_free()
		return 1
	var dist := MonsterAIScript.horizontal_distance(player.global_position, landing)
	if dist > max_dist + 0.05:
		push_error("Expected landing clamped to aggro move cap")
		player.queue_free()
		return 1
	player.queue_free()
	return 0


func _test_dash_direction_locked() -> int:
	var dash := EmberDashAbilityScript.new()
	var monster := CharacterBody3D.new()
	var player := Node3D.new()
	monster.global_position = Vector3(0.0, 0.0, 0.0)
	player.global_position = Vector3(0.0, 0.0, -8.0)
	dash.start_dash(monster, player)
	if not dash.is_dashing():
		push_error("Expected dash to start with a valid landing")
		return 1
	var locked := dash._dash_dir
	dash.tick_dash(monster, 0.05)
	if dash._dash_dir.distance_to(locked) > 0.001:
		push_error("Expected dash direction to stay locked during tick")
		return 1
	return 0


func _test_dash_cooldown_reset() -> int:
	var dash := EmberDashAbilityScript.new()
	dash.cooldown_sec = 12.0
	dash.begin_cooldown()
	if dash.can_cast():
		push_error("Expected dash to be on cooldown after begin_cooldown")
		return 1
	dash.reset_cooldown()
	if not dash.can_cast():
		push_error("Expected reset_cooldown to clear dash cooldown")
		return 1
	return 0
