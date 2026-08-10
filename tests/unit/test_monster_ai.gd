extends RefCounted

const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const MonsterInterestScript := preload("res://scripts/monsters/monster_interest.gd")


func run() -> int:
	var failures := 0
	failures += _test_health_clamp_and_death()
	failures += _test_pick_nearest_target()
	failures += _test_resolve_state()
	failures += _test_chase_eyes_visible()
	failures += _test_lookdev_eyes_visible()
	failures += _test_patrol_and_velocity_helpers()
	failures += _test_proximity_and_prefer_interest()
	return failures


func _test_health_clamp_and_death() -> int:
	if not is_equal_approx(MonsterAIScript.apply_damage(50.0, 12.0), 38.0):
		push_error("Expected damage to subtract from health")
		return 1
	if not is_equal_approx(MonsterAIScript.apply_damage(5.0, 20.0), 0.0):
		push_error("Expected damage to clamp at zero")
		return 1
	if not MonsterAIScript.is_dead(0.0) or MonsterAIScript.is_dead(0.1):
		push_error("Expected is_dead only when health is zero or below")
		return 1
	if not is_equal_approx(MonsterAIScript.apply_heal(40.0, 20.0, 50.0), 50.0):
		push_error("Expected heal to clamp at max_health")
		return 1
	if not is_equal_approx(MonsterAIScript.apply_damage(30.0, -5.0), 30.0):
		push_error("Expected negative damage amounts to be ignored")
		return 1
	return 0


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
