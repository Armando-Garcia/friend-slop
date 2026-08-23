extends RefCounted

const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const AshRetreatDashAbilityScript := preload(
	"res://scripts/monsters/abilities/ash_retreat_dash_ability.gd"
)


func run() -> int:
	var failures := 0
	failures += _test_landing_away_from_player()
	failures += _test_landing_clamped_to_aggro()
	failures += _test_backdash_cooldown()
	failures += _test_backdash_starts_then_strafes()
	failures += _test_backdash_blocked_on_cooldown()
	failures += _test_combo_close_landing()
	failures += _test_combo_away_near_90()
	return failures


func _test_landing_away_from_player() -> int:
	var player := Node3D.new()
	_attach(player)
	player.global_position = Vector3.ZERO
	var from := Vector3(0.0, 0.0, 4.0)
	var max_dist := MonsterAIScript.max_aggro_move_distance(11.0)
	var landing := MonsterAIScript.pick_dash_landing_away(from, player, 4.0, max_dist)
	player.queue_free()
	if landing.z <= from.z + 0.5:
		push_error("Expected backdash landing farther from player on +Z, got %s" % landing)
		return 1
	return 0


func _test_landing_clamped_to_aggro() -> int:
	var player := Node3D.new()
	_attach(player)
	player.global_position = Vector3.ZERO
	var max_dist := MonsterAIScript.max_aggro_move_distance(11.0)
	var from := Vector3(0.0, 0.0, max_dist - 0.2)
	var landing := MonsterAIScript.pick_dash_landing_away(from, player, 4.0, max_dist)
	var dist := MonsterAIScript.horizontal_distance(player.global_position, landing)
	player.queue_free()
	if dist > max_dist + 0.05:
		push_error("Expected backdash landing clamped to aggro cap, got %s" % dist)
		return 1
	return 0


func _test_backdash_cooldown() -> int:
	var dash := AshRetreatDashAbilityScript.new()
	_attach(dash)
	if not is_equal_approx(dash.cooldown_sec, 5.0):
		push_error("Expected Ash retreat dash cooldown 5s, got %s" % dash.cooldown_sec)
		dash.queue_free()
		return 1
	dash.begin_cooldown()
	var on_cd := not dash.can_cast()
	dash.reset_cooldown()
	var ready := dash.can_cast()
	dash.queue_free()
	if not on_cd:
		push_error("Expected retreat dash to be on cooldown after begin_cooldown")
		return 1
	if not ready:
		push_error("Expected reset_cooldown to clear retreat dash cooldown")
		return 1
	return 0


func _test_backdash_starts_then_strafes() -> int:
	var dash := AshRetreatDashAbilityScript.new()
	var host := _StrafeProbe.new()
	var player := Node3D.new()
	_attach(dash)
	_attach(host)
	_attach(player)
	host.global_position = Vector3(0.0, 0.0, 4.0)
	player.global_position = Vector3.ZERO
	var started := dash.try_backdash(host, player, -1.0)
	if not started or not dash.is_dashing():
		push_error("Expected Ash backdash to start")
		_free_nodes([dash, host, player])
		return 1
	var locked := dash._dash_dir
	if locked.z <= 0.0:
		push_error("Expected backdash direction away from player (+Z), got %s" % locked)
		_free_nodes([dash, host, player])
		return 1
	dash._dash_time_left = 0.0
	dash.tick_dash(host, 0.05)
	var strafed := host.strafe_count == 1 and is_equal_approx(host.last_side, -1.0)
	var still_dashing := dash.is_dashing()
	_free_nodes([dash, host, player])
	if still_dashing:
		push_error("Expected backdash to end after arrival/time")
		return 1
	if not strafed:
		push_error("Expected backdash end to start a chase strafe")
		return 1
	return 0


func _test_backdash_blocked_on_cooldown() -> int:
	var dash := AshRetreatDashAbilityScript.new()
	var host := _StrafeProbe.new()
	var player := Node3D.new()
	_attach(dash)
	_attach(host)
	_attach(player)
	host.global_position = Vector3(0.0, 0.0, 4.0)
	player.global_position = Vector3.ZERO
	dash.try_backdash(host, player, 1.0)
	dash._end_dash(host)
	var blocked := not dash.try_backdash(host, player, 1.0)
	_free_nodes([dash, host, player])
	if not blocked:
		push_error("Expected backdash to refuse while on 5s cooldown")
		return 1
	return 0


func _test_combo_close_landing() -> int:
	var player := Node3D.new()
	_attach(player)
	player.global_position = Vector3.ZERO
	var from := Vector3(0.0, 0.0, 10.0)
	var max_dist := MonsterAIScript.max_aggro_move_distance(11.0)
	var landing := MonsterAIScript.pick_dash_landing_at_range(
		from, player, AshRetreatDashAbilityScript.COMBO_CLOSE_RANGE, max_dist
	)
	var dist := MonsterAIScript.horizontal_distance(player.global_position, landing)
	player.queue_free()
	if absf(dist - AshRetreatDashAbilityScript.COMBO_CLOSE_RANGE) > 0.2:
		push_error("Expected combo close dash to land near 2.5m, got %s" % dist)
		return 1
	return 0


func _test_combo_away_near_90() -> int:
	var player := Node3D.new()
	_attach(player)
	player.global_position = Vector3.ZERO
	var from := Vector3(0.0, 0.0, 2.5)
	var inbound := Vector3(0.0, 0.0, -1.0)
	var landing := MonsterAIScript.pick_dash_landing_sidestep(
		from, player, inbound, AshRetreatDashAbilityScript.COMBO_AWAY_DISTANCE, 20.0
	)
	var move := landing - from
	move.y = 0.0
	player.queue_free()
	if move.length() < 1.0:
		push_error("Expected combo away dash to move, got %s" % landing)
		return 1
	var aligned := absf(inbound.dot(move.normalized()))
	if aligned > 0.35:
		push_error("Expected combo away dash near 90 degrees from inbound, dot %s" % aligned)
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


## Real Monster so the typed ability contract applies; records strafe requests
## instead of running chase locomotion.
class _StrafeProbe extends Monster:
	var strafe_count: int = 0
	var last_side: float = 0.0

	func _init() -> void:
		chase_range = 11.0
		move_speed = 2.8

	func start_chase_strafe(_target: Node3D, side_sign: float, _duration_sec: float) -> void:
		strafe_count += 1
		last_side = side_sign

	func _face_horizontal(_desired_vel: Vector3) -> void:
		pass
