extends RefCounted

## Unit coverage for Summon base contracts (host, leash, relay, aggro).

const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const MonsterInterestScript := preload("res://scripts/monsters/monster_interest.gd")
const SummonHostScript := preload("res://scripts/monsters/summon_host.gd")
const SummonScript := preload("res://scripts/monsters/summon.gd")


func run() -> int:
	var failures := 0
	failures += _test_summon_host_kill_and_command()
	failures += _test_summon_host_relay()
	failures += _test_summon_aggro_and_clear()
	failures += _test_summon_sight_and_hearing_relay()
	failures += _test_leash_helpers()
	return failures


## A Character with its own HP pool, so SummonHost.kill_all spends it the same way
## it spends a real Summon's. Command plumbing is recorded instead of driving AI.
class FakeSummon extends Character:
	var hunt_target: Node3D = null
	var investigate_pos: Vector3 = Vector3.ZERO
	var has_investigate: bool = false
	var relay_sight: RefCounted = null
	var relay_hearing: RefCounted = null

	func _init() -> void:
		var pool := CombatHealth.new()
		pool.name = "Health"
		add_child(pool)

	func set_forced_hunt(target: Node3D, _free_leash: bool = true) -> void:
		hunt_target = target
		has_investigate = false

	func set_forced_investigate(world_position: Vector3, _free_leash: bool = true) -> void:
		hunt_target = null
		investigate_pos = world_position
		has_investigate = true

	func append_relayed_interests(out: Array) -> void:
		if relay_sight != null:
			out.append(relay_sight)
		if relay_hearing != null:
			out.append(relay_hearing)


func _test_summon_host_kill_and_command() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		push_error("Expected SceneTree for SummonHost tests")
		return 1
	var holder := Node.new()
	tree.root.add_child(holder)
	var host: Node = SummonHostScript.new()
	holder.add_child(host)
	var a := FakeSummon.new()
	var b := FakeSummon.new()
	holder.add_child(a)
	holder.add_child(b)
	host.call("register_summon", a)
	host.call("register_summon", b)
	var target := Node3D.new()
	holder.add_child(target)
	var err := ""
	if int(host.call("summon_count")) != 2:
		err = "Expected two registered summons"
	else:
		host.call("command_attack", target)
		if a.hunt_target != target or b.hunt_target != target:
			err = "Expected command_attack to set forced hunt on summons"
		else:
			host.call("command_investigate", Vector3(3.0, 0.0, 4.0))
			if not a.has_investigate or not is_equal_approx(a.investigate_pos.x, 3.0):
				err = "Expected command_investigate to set investigate goal"
			else:
				host.call("kill_all")
				if a.is_alive() or b.is_alive():
					err = "Expected kill_all to empty every summon HP pool"
				elif int(host.call("summon_count")) != 0:
					err = "Expected summon list cleared after kill_all"
	holder.queue_free()
	if not err.is_empty():
		push_error(err)
		return 1
	return 0


func _test_summon_host_relay() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		push_error("Expected SceneTree for SummonHost relay test")
		return 1
	var holder := Node.new()
	tree.root.add_child(holder)
	var host: Node = SummonHostScript.new()
	holder.add_child(host)
	var summon := FakeSummon.new()
	holder.add_child(summon)
	var player := Node3D.new()
	holder.add_child(player)
	summon.relay_sight = MonsterInterestScript.from_target(player, 2.25, &"summon_sight")
	summon.relay_hearing = MonsterInterestScript.from_position(
		Vector3(1.0, 0.0, 2.0), 1.85, &"summon_hearing"
	)
	host.call("register_summon", summon)
	var out: Array = []
	host.call("append_relayed_interests", out)
	var err := ""
	if out.size() != 2:
		err = "Expected sight + hearing relay interests, got %d" % out.size()
	elif str(out[0].get("source")) != "summon_sight":
		err = "Expected first relayed interest to be summon_sight"
	elif str(out[1].get("source")) != "summon_hearing":
		err = "Expected second relayed interest to be summon_hearing"
	holder.queue_free()
	if not err.is_empty():
		push_error(err)
		return 1
	return 0


func _test_summon_aggro_and_clear() -> int:
	var summon: Node = SummonScript.new()
	var target := Node3D.new()
	var fail := _assert_forced_hunt_then_clear(summon, target)
	if fail != 0:
		target.free()
		summon.free()
		return fail
	fail = _assert_host_mirror_and_command_persist(summon)
	target.free()
	summon.free()
	return fail


func _assert_forced_hunt_then_clear(summon: Node, target: Node3D) -> int:
	summon.call("set_forced_hunt", target, true)
	if int(summon.get("aggro_mode")) != SummonScript.AggroMode.COMMAND_HUNT:
		push_error("Expected COMMAND_HUNT after set_forced_hunt")
		return 1
	if bool(summon.get("leash_enabled")):
		push_error("Expected leash disabled during forced hunt")
		return 1
	summon.call("clear_forced_hunt")
	if int(summon.get("aggro_mode")) != SummonScript.AggroMode.BOUND:
		push_error("Expected BOUND after clear_forced_hunt")
		return 1
	if not bool(summon.get("leash_enabled")):
		push_error("Expected leash re-enabled after clear_forced_hunt")
		return 1
	return 0


func _assert_host_mirror_and_command_persist(summon: Node) -> int:
	summon.call("sync_from_host_state", MonsterAIScript.State.CHASE)
	if int(summon.get("aggro_mode")) != SummonScript.AggroMode.HOST_MIRROR:
		push_error("Expected HOST_MIRROR when host chases")
		return 1
	summon.call("set_forced_investigate", Vector3(5.0, 0.0, 0.0), true)
	summon.call("sync_from_host_state", MonsterAIScript.State.CHASE)
	if int(summon.get("aggro_mode")) != SummonScript.AggroMode.COMMAND_INVESTIGATE:
		push_error("Expected command mode to persist while host is hot")
		return 1
	summon.call("sync_from_host_state", MonsterAIScript.State.PATROL)
	if int(summon.get("aggro_mode")) != SummonScript.AggroMode.RECALL:
		push_error("Expected calm host to recall pack home")
		return 1
	summon.call("finish_recall")
	if int(summon.get("aggro_mode")) != SummonScript.AggroMode.BOUND:
		push_error("Expected BOUND after recall finishes")
		return 1
	return 0


func _test_summon_sight_and_hearing_relay() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		push_error("Expected SceneTree for summon relay test")
		return 1
	var holder := Node.new()
	tree.root.add_child(holder)
	var summon: Node = SummonScript.new()
	holder.add_child(summon)
	var player := Node3D.new()
	holder.add_child(player)
	player.add_to_group("player")
	## Inject interest as if Sight produced a player chase target.
	summon.set(
		"_interest",
		MonsterInterestScript.from_target(player, 1.4, &"sight")
	)
	var err := ""
	var sight = summon.call("get_relayed_player_interest")
	if sight == null or str(sight.get("source")) != "summon_sight":
		err = "Expected get_relayed_player_interest to emit summon_sight"
	elif not is_equal_approx(float(sight.get("urgency")), 2.25):
		err = "Expected summon_sight urgency 2.25"
	else:
		summon.set(
			"_interest",
			MonsterInterestScript.from_position(Vector3(2.0, 0.0, 1.0), 1.15, &"hearing")
		)
		if summon.call("get_relayed_player_interest") != null:
			err = "Expected hearing interest not to relay as summon_sight"
		else:
			var hearing = summon.call("get_relayed_hearing_interest")
			if hearing == null or str(hearing.get("source")) != "summon_hearing":
				err = "Expected get_relayed_hearing_interest to emit summon_hearing"
			else:
				var out: Array = []
				summon.call("append_relayed_interests", out)
				if out.size() != 1 or str(out[0].get("source")) != "summon_hearing":
					err = "Expected append_relayed_interests to include hearing only"
	holder.queue_free()
	if not err.is_empty():
		push_error(err)
		return 1
	return 0


func _test_leash_helpers() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		push_error("Expected SceneTree for leash helpers")
		return 1
	var holder := Node.new()
	tree.root.add_child(holder)
	var summon: Node = SummonScript.new()
	holder.add_child(summon)
	var host_node := Node3D.new()
	holder.add_child(host_node)
	host_node.global_position = Vector3.ZERO
	summon.call("bind_to_host", host_node, 8.0)
	var err := ""
	if not is_equal_approx(float(summon.get("leash_radius")), 8.0):
		err = "Expected bind_to_host to set leash_radius"
	elif int(summon.get("aggro_mode")) != SummonScript.AggroMode.BOUND:
		err = "Expected BOUND after bind_to_host"
	elif not bool(summon.call("_point_inside_leash", Vector3(4.0, 0.0, 0.0))):
		err = "Expected point inside leash"
	elif bool(summon.call("_point_inside_leash", Vector3(20.0, 0.0, 0.0))):
		err = "Expected far point outside leash"
	holder.queue_free()
	if not err.is_empty():
		push_error(err)
		return 1
	return 0
