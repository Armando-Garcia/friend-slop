extends RefCounted

const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const MonsterInterestScript := preload("res://scripts/monsters/monster_interest.gd")


func run() -> int:
	var failures := 0
	failures += _test_pick_nearest_target()
	failures += _test_resolve_state()
	failures += _test_chase_eyes_visible()
	failures += _test_lookdev_eyes_visible()
	failures += _test_patrol_and_velocity_helpers()
	failures += _test_proximity_and_prefer_interest()
	failures += _test_chase_move_helpers()
	failures += _test_lookdev_live_is_off_outside_editor()
	return failures


func _test_pick_nearest_target() -> int:
	var origin := Vector3(0.0, 0.0, 0.0)
	var positions: Array = [
		Vector3(10.0, 0.0, 0.0),
		Vector3(3.0, 1.0, 0.0),
		Vector3(2.0, 0.0, 2.0),
	]
	var alive: Array = [true, true, false]
	var idx: int = MonsterAIScript.pick_nearest_target_index(
		origin, positions, alive, 12.0
	)
	if idx != 1:
		push_error("Expected nearest living target index 1, got %d" % idx)
		return 1
	var none: int = MonsterAIScript.pick_nearest_target_index(
		origin, positions, alive, 2.0
	)
	if none != -1:
		push_error("Expected no target within short chase_range")
		return 1
	return 0


func _test_resolve_state() -> int:
	var idle := MonsterAIScript.State.IDLE
	var patrol := MonsterAIScript.State.PATROL
	var chase := MonsterAIScript.State.CHASE
	var alert := MonsterAIScript.State.ALERT
	if MonsterAIScript.resolve_state(idle, true) != chase:
		push_error("Expected chase when a target is present")
		return 1
	if MonsterAIScript.resolve_state(patrol, false) != patrol:
		push_error("Expected patrol to continue without a target")
		return 1
	if MonsterAIScript.resolve_state(chase, false) != chase:
		push_error("Expected chase to persist without a target (grace before alert)")
		return 1
	if MonsterAIScript.resolve_state(alert, false) != alert:
		push_error("Expected alert to persist without a target")
		return 1
	if MonsterAIScript.resolve_state(alert, true) != chase:
		push_error("Expected alert to become chase when a target returns")
		return 1
	return 0


func _test_chase_eyes_visible() -> int:
	if MonsterAIScript.chase_eyes_visible(MonsterAIScript.State.IDLE):
		push_error("Expected eyes hidden while idle")
		return 1
	if MonsterAIScript.chase_eyes_visible(MonsterAIScript.State.PATROL):
		push_error("Expected eyes hidden while patrolling")
		return 1
	if not MonsterAIScript.chase_eyes_visible(MonsterAIScript.State.CHASE):
		push_error("Expected eyes visible while chasing")
		return 1
	if not MonsterAIScript.chase_eyes_visible(MonsterAIScript.State.ALERT):
		push_error("Expected eyes visible while alert")
		return 1
	return 0


func _test_lookdev_eyes_visible() -> int:
	if MonsterAIScript.lookdev_eyes_visible(MonsterAIScript.LookdevPose.PATROL):
		push_error("Expected lookdev patrol to hide eyes")
		return 1
	if not MonsterAIScript.lookdev_eyes_visible(MonsterAIScript.LookdevPose.CHASE):
		push_error("Expected lookdev chase to show eyes")
		return 1
	return 0


func _test_patrol_and_velocity_helpers() -> int:
	var point: Vector3 = MonsterAIScript.random_patrol_point(
		Vector3(1.0, 2.0, 3.0), 4.0, 0.0, 0.5
	)
	if not is_equal_approx(point.x, 3.0) or not is_equal_approx(point.z, 3.0):
		push_error("Expected patrol point along +X at half radius")
		return 1
	if not is_equal_approx(point.y, 2.0):
		push_error("Expected patrol point to keep origin Y")
		return 1
	var vel: Vector3 = MonsterAIScript.horizontal_velocity_toward(
		Vector3.ZERO, Vector3(10.0, 5.0, 0.0), 4.0, -1.0
	)
	if not is_equal_approx(vel.x, 4.0) or not is_equal_approx(vel.z, 0.0):
		push_error("Expected velocity along +X at move_speed")
		return 1
	if not is_equal_approx(vel.y, -1.0):
		push_error("Expected Y velocity to be preserved")
		return 1
	return 0


func _test_proximity_and_prefer_interest() -> int:
	var near_u: float = MonsterAIScript.proximity_urgency(
		Vector3.ZERO, Vector3(2.0, 0.0, 0.0), 10.0
	)
	var far_u: float = MonsterAIScript.proximity_urgency(
		Vector3.ZERO, Vector3(8.0, 0.0, 0.0), 10.0
	)
	if near_u <= far_u or near_u <= 0.0:
		push_error("Expected nearer targets to score higher urgency")
		return 1
	if not is_equal_approx(
		MonsterAIScript.proximity_urgency(Vector3.ZERO, Vector3(20.0, 0, 0), 10.0),
		0.0
	):
		push_error("Expected out-of-range proximity urgency to be zero")
		return 1

	var low = MonsterInterestScript.from_position(Vector3(1, 0, 0), 0.4, &"a")
	var high = MonsterInterestScript.from_position(Vector3(2, 0, 0), 0.9, &"b")
	var none = MonsterInterestScript.from_position(Vector3(3, 0, 0), 0.0, &"c")
	var picked = MonsterAIScript.prefer_highest_urgency([low, none, high])
	if picked != high:
		push_error("Expected prefer_highest_urgency to pick the 0.9 candidate")
		return 1
	if MonsterAIScript.prefer_highest_urgency([none]) != null:
		push_error("Expected no actionable interest when all urgencies are zero")
		return 1
	return 0


func _test_chase_move_helpers() -> int:
	var failures := 0
	failures += _assert_chase_move_durations()
	failures += _assert_chase_move_directions()
	failures += _assert_chase_move_aggro_clamp()
	failures += _assert_weighted_strafe_away()
	failures += _assert_dash_landing_away()
	return 1 if failures > 0 else 0


func _assert_chase_move_durations() -> int:
	if not is_equal_approx(MonsterAIScript.max_aggro_move_distance(10.0), 8.0):
		push_error("Expected max aggro move distance to be 80% of chase_range")
		return 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var wait_sec: float = MonsterAIScript.pick_chase_wait_sec(rng, 1.0, 3.0)
	if wait_sec < 1.0 or wait_sec > 3.0:
		push_error("Expected chase wait duration within 1–3s")
		return 1
	var strafe_sec: float = MonsterAIScript.pick_chase_strafe_sec(rng, 1.2, 2.0)
	if strafe_sec < 1.2 or strafe_sec > 2.0:
		push_error("Expected strafe duration within 1.2–2.0s")
		return 1
	var retreat_sec: float = MonsterAIScript.pick_chase_retreat_sec(rng, 1.2, 3.2)
	if retreat_sec < 1.2 or retreat_sec > 3.2:
		push_error("Expected retreat duration within 1.2–3.2s")
		return 1
	var wretch_sec: float = MonsterAIScript.pick_wretch_post_cast_move_sec(rng, 0.5, 1.5)
	if wretch_sec < 0.5 or wretch_sec > 1.5:
		push_error("Expected wretch post-cast move within 0.5–1.5s")
		return 1
	return 0


func _assert_chase_move_directions() -> int:
	var from := Vector3(0.0, 0.0, 0.0)
	var player := Vector3(0.0, 0.0, -10.0)
	var strafe: Vector3 = MonsterAIScript.angled_strafe_dir(from, player, 1.0, 0.28)
	if strafe.length_squared() < 0.5:
		push_error("Expected non-zero angled strafe direction")
		return 1
	if strafe.x <= 0.0:
		push_error("Expected right strafe to push +X when facing -Z")
		return 1
	var retreat: Vector3 = MonsterAIScript.angled_retreat_dir(from, player, -1.0, 0.38)
	if retreat.z <= 0.0:
		push_error("Expected retreat to move away (+Z) from player on -Z")
		return 1
	return 0


func _assert_chase_move_aggro_clamp() -> int:
	## Cap is absolute distance from the player (e.g. 0.8 * chase_range).
	var player := Vector3(0.0, 0.0, 0.0)
	var inside := Vector3(0.0, 0.0, -5.0)
	if not MonsterAIScript.can_retreat_farther(inside, player, 8.0):
		push_error("Expected retreat allowed inside max aggro distance")
		return 1
	var at_cap := Vector3(0.0, 0.0, -8.0)
	if MonsterAIScript.can_retreat_farther(at_cap, player, 8.0):
		push_error("Expected retreat blocked at max aggro distance")
		return 1
	var clamped: Vector3 = MonsterAIScript.retreat_velocity_clamped(
		at_cap, player, Vector3(0.0, 0.0, -1.0), 4.0, -1.0, 8.0
	)
	if not is_equal_approx(clamped.x, 0.0) or not is_equal_approx(clamped.z, 0.0):
		push_error("Expected clamped retreat velocity to zero at aggro cap")
		return 1
	if not is_equal_approx(clamped.y, -1.0):
		push_error("Expected clamped retreat to preserve Y velocity")
		return 1
	## Start facing +X; target facing -Z so yaw must change.
	var yaw0 := PI * 0.5
	var yaw1: float = MonsterAIScript.rotate_yaw_toward(
		yaw0, Vector3(0.0, 0.0, -1.0), 10.0, 0.05
	)
	if is_equal_approx(yaw1, yaw0):
		push_error("Expected rotate_yaw_toward to change yaw toward -Z")
		return 1
	return 0


func _assert_weighted_strafe_away() -> int:
	var from := Vector3(8.0, 0.0, 0.0)
	var player := Vector3(0.0, 0.0, 1.0)
	var further := MonsterAIScript.strafe_sign_further_from_player(from, player)
	var toward := MonsterAIScript.toward_player_flat(from, player)
	var right := Vector3(-toward.z, 0.0, toward.x).normalized()
	var d_pos := MonsterAIScript.horizontal_distance(from + right * 0.5, player)
	var d_neg := MonsterAIScript.horizontal_distance(from - right * 0.5, player)
	var expected := 1.0 if d_pos >= d_neg else -1.0
	if not is_equal_approx(further, expected):
		push_error("Expected strafe sign to pick the farther lateral, got %s" % further)
		return 1
	if not is_equal_approx(MonsterAIScript.pick_weighted_strafe_sign(1.0, 0.0, 0.7), 1.0):
		push_error("Expected 70% band to keep the farther strafe sign")
		return 1
	if not is_equal_approx(MonsterAIScript.pick_weighted_strafe_sign(1.0, 0.69, 0.7), 1.0):
		push_error("Expected roll under 0.7 to keep the farther strafe sign")
		return 1
	if not is_equal_approx(MonsterAIScript.pick_weighted_strafe_sign(1.0, 0.7, 0.7), -1.0):
		push_error("Expected 30% band to flip toward the closer strafe")
		return 1
	return 0


func _assert_dash_landing_away() -> int:
	var player := Node3D.new()
	player.global_position = Vector3.ZERO
	var from := Vector3(0.0, 0.0, 3.0)
	var landing: Vector3 = MonsterAIScript.pick_dash_landing_away(from, player, 4.0, 20.0)
	player.free()
	if landing.z <= from.z:
		push_error("Expected pick_dash_landing_away to move farther from the player")
		return 1
	return 0


func _test_lookdev_live_is_off_outside_editor() -> int:
	var node := Node.new()
	node.set_meta("lookdev_live_ai", true)
	if MonsterAIScript.is_lookdev_live(node):
		push_error("Lookdev live AI should be off outside the editor")
		node.free()
		return 1
	if MonsterAIScript.is_lookdev_live(null):
		push_error("null must not count as lookdev live")
		node.free()
		return 1
	node.free()
	return 0
