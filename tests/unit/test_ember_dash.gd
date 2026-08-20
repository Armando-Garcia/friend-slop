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
	failures += _test_sidestep_opposite_player_move()
	failures += _test_sidestep_half_combo_distance()
	return failures


func _test_player_facing_flat() -> int:
	var player := Node3D.new()
	player.transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var forward := MonsterAIScript.player_facing_flat(player)
	player.queue_free()
	if forward.length_squared() < 0.9:
		push_error("Expected default player facing to be unit length")
		return 1
	return 0


func _test_pick_dash_landing_behind() -> int:
	var player := Node3D.new()
	_attach(player)
	player.global_position = Vector3(0.0, 0.0, 0.0)
	player.transform.basis = Basis.IDENTITY
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
	player.queue_free()
	if dist > max_dist + 0.05:
		push_error("Expected landing clamped to aggro move cap")
		return 1
	return 0


func _test_dash_direction_locked() -> int:
	var dash := EmberDashAbilityScript.new()
	var monster := CharacterBody3D.new()
	var player := Node3D.new()
	_attach(dash)
	_attach(monster)
	_attach(player)
	monster.global_position = Vector3(0.0, 0.0, 0.0)
	player.global_position = Vector3(0.0, 0.0, -8.0)
	dash.start_dash(monster, player)
	if not dash.is_dashing():
		push_error("Expected dash to start with a valid landing")
		_free_nodes([dash, monster, player])
		return 1
	var locked := dash._dash_dir
	dash.tick_dash(monster, 0.05)
	var drifted := dash._dash_dir.distance_to(locked) > 0.001
	_free_nodes([dash, monster, player])
	if drifted:
		push_error("Expected dash direction to stay locked during tick")
		return 1
	return 0


func _test_dash_cooldown_reset() -> int:
	var dash := EmberDashAbilityScript.new()
	_attach(dash)
	dash.cooldown_sec = 12.0
	dash.begin_cooldown()
	if dash.can_cast():
		push_error("Expected dash to be on cooldown after begin_cooldown")
		dash.queue_free()
		return 1
	dash.reset_cooldown()
	var ready := dash.can_cast()
	dash.queue_free()
	if not ready:
		push_error("Expected reset_cooldown to clear dash cooldown")
		return 1
	return 0


func _test_sidestep_opposite_player_move() -> int:
	var player := CharacterBody3D.new()
	_attach(player)
	player.global_position = Vector3(0.0, 0.0, -8.0)
	player.velocity = Vector3(3.0, 0.0, 0.0)
	var landing := EmberDashAbilityScript.pick_sidestep_landing(
		Vector3.ZERO, player, 4.0, 1.0
	)
	player.queue_free()
	if landing.x >= -0.01:
		push_error("Expected sidestep opposite player +X movement, got %s" % landing)
		return 1
	return 0


func _test_sidestep_half_combo_distance() -> int:
	var dash := EmberDashAbilityScript.new()
	_attach(dash)
	var half_ok := is_equal_approx(EmberDashAbilityScript.SIDESTEP_DISTANCE_MULT, 0.5)
	var cd_ok := is_equal_approx(dash.cooldown_sec, 5.0)
	dash.queue_free()
	if not half_ok:
		push_error("Expected sidestep distance to be half combo dash range")
		return 1
	if not cd_ok:
		push_error("Expected ember dash sidestep cooldown 5s")
		return 1
	return 0


func _attach(node: Node) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	tree.root.add_child(node)


func _free_nodes(nodes: Array) -> void:
	for node in nodes:
		if node is Node and is_instance_valid(node):
			(node as Node).queue_free()
