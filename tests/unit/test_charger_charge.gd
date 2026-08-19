extends RefCounted

const ChargeScript := preload("res://scripts/monsters/charger_charge.gd")
const LaunchScript := preload("res://scripts/monsters/charger_launch.gd")
const WardScript := preload("res://scripts/spells/ward_shield.gd")


func run() -> int:
	var failures := 0
	failures += _test_charge_speed_is_230_percent_sprint()
	failures += _test_charge_speed_honors_mult()
	failures += _test_telegraph_waits_for_red_and_bow()
	failures += _test_pose_only_never_reads_walls()
	failures += _test_live_charge_reads_walls_after_grace()
	failures += _test_player_and_ward_are_not_walls()
	failures += _test_wall_stun_duration()
	failures += _test_search_about_face_is_180()
	failures += _test_search_sweep_is_slow()
	failures += _test_search_ready_after_duration()
	failures += _test_locked_dir_does_not_steer()
	failures += _test_telegraph_never_reads_walls()
	return failures


func _test_charge_speed_is_230_percent_sprint() -> int:
	var speed := ChargeScript.charge_speed(5.0)
	if not is_equal_approx(speed, 11.5):
		push_error("Expected default ram at 230%% of sprint 5, got %s" % speed)
		return 1
	if not is_equal_approx(LaunchScript.charge_speed(5.0), 11.5):
		push_error("ChargerLaunch.charge_speed should match the default 230%% ram")
		return 1
	return 0


func _test_charge_speed_honors_mult() -> int:
	var speed := ChargeScript.charge_speed(5.0, 3.2)
	if not is_equal_approx(speed, 16.0):
		push_error("Expected 3.2× sprint 5 = 16, got %s" % speed)
		return 1
	if not is_equal_approx(LaunchScript.charge_speed(5.0, 3.2), 16.0):
		push_error("ChargerLaunch.charge_speed should honor the authored mult")
		return 1
	return 0


func _test_telegraph_waits_for_red_and_bow() -> int:
	var charge: RefCounted = ChargeScript.new()
	charge.call("begin_telegraph")
	charge.call("tick", 0.6)
	var plunge := LaunchScript.plunge_pitch_rad(338.0)
	if bool(charge.call("telegraph_ready", 1.2, plunge, plunge)):
		push_error("Telegraph must stay up until tint finishes")
		return 1
	charge.call("tick", 0.7)
	if bool(charge.call("telegraph_ready", 1.2, 0.0, plunge)):
		push_error("Telegraph must wait until the head finishes bowing")
		return 1
	if not bool(charge.call("telegraph_ready", 1.2, plunge, plunge)):
		push_error("Telegraph should end when fully red and bowed")
		return 1
	return 0


func _test_pose_only_never_reads_walls() -> int:
	var charge: RefCounted = ChargeScript.new()
	charge.set("pose_only", true)
	charge.call("begin_charge", Vector3.FORWARD)
	charge.call("tick", 1.0)
	if bool(charge.call("can_read_walls")):
		push_error("Inspector pose charge must not wall-stun itself")
		return 1
	return 0


func _test_live_charge_reads_walls_after_grace() -> int:
	var charge: RefCounted = ChargeScript.new()
	charge.call("begin_charge", Vector3.FORWARD)
	charge.call("tick", 0.1)
	if bool(charge.call("can_read_walls")):
		push_error("Live ram needs a short grace so the ward is not a wall")
		return 1
	charge.call("tick", 0.3)
	if not bool(charge.call("can_read_walls")):
		push_error("Live ram should read walls after grace")
		return 1
	return 0


func _test_player_and_ward_are_not_walls() -> int:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	if ChargeScript.is_wall_collider(player, Vector3.BACK):
		player.free()
		push_error("A player must not end the ram")
		return 1
	player.free()
	var ward := Node3D.new()
	ward.add_to_group(str(WardScript.GROUP))
	var body := StaticBody3D.new()
	ward.add_child(body)
	if ChargeScript.is_wall_collider(body, Vector3.BACK):
		ward.free()
		push_error("The held ward must not count as a wall")
		return 1
	ward.free()
	var wall := StaticBody3D.new()
	var is_wall := ChargeScript.is_wall_collider(wall, Vector3.BACK)
	wall.free()
	if not is_wall:
		push_error("A maze wall should end the ram")
		return 1
	return 0


func _test_wall_stun_duration() -> int:
	var charge: RefCounted = ChargeScript.new()
	charge.call("begin_wall_stun")
	charge.call("tick", 1.0)
	if bool(charge.call("wall_stun_ready", 3.0)):
		push_error("Wall stun should last the full authored duration")
		return 1
	charge.call("tick", 2.1)
	if not bool(charge.call("wall_stun_ready", 3.0)):
		push_error("Wall stun should end after the authored duration")
		return 1
	return 0


func _test_search_about_face_is_180() -> int:
	var fwd: Vector3 = ChargeScript.heading_from_yaw(0.0)
	if fwd.distance_to(Vector3(0.0, 0.0, -1.0)) > 0.001:
		push_error("Yaw 0 should look down -Z, got %s" % fwd)
		return 1
	var back: Vector3 = ChargeScript.about_face_heading(0.0)
	if back.distance_to(Vector3(0.0, 0.0, 1.0)) > 0.001:
		push_error("About-face from yaw 0 should look +Z, got %s" % back)
		return 1
	if ChargeScript.about_face_done(0.0, 0.0):
		push_error("Search should not skip the 180 turn")
		return 1
	if not ChargeScript.about_face_done(PI, 0.0):
		push_error("About-face should finish at 180 degrees")
		return 1
	return 0


func _test_search_sweep_is_slow() -> int:
	var at_rest := ChargeScript.search_yaw_offset(0.0, 0.55, 0.28)
	if not is_equal_approx(at_rest, 0.0):
		push_error("Search sweep should start at 0, got %s" % at_rest)
		return 1
	var early := ChargeScript.search_yaw_offset(0.15, 0.55, 0.28)
	if absf(early) > 0.25:
		push_error("Search sweep moved too far in 0.15s, got %s" % early)
		return 1
	var later := ChargeScript.search_yaw_offset(0.9, 0.55, 0.28)
	if absf(later) < 0.2:
		push_error("Search sweep should keep turning slowly, got %s" % later)
		return 1
	return 0


func _test_search_ready_after_duration() -> int:
	var charge: RefCounted = ChargeScript.new()
	charge.call("begin_search")
	charge.call("tick", 1.0)
	if bool(charge.call("search_ready", 2.4)):
		push_error("Search should last the full authored duration")
		return 1
	charge.call("tick", 1.5)
	if not bool(charge.call("search_ready", 2.4)):
		push_error("Search should end after the authored duration")
		return 1
	return 0


func _test_locked_dir_does_not_steer() -> int:
	var charge: RefCounted = ChargeScript.new()
	charge.call("begin_charge", Vector3(1.0, 4.0, 0.0))
	var vel: Vector3 = charge.call("charge_velocity", 10.0)
	if absf(vel.z) > 0.001 or vel.x <= 0.0:
		push_error("Charge velocity must stay on the locked XZ dir, got %s" % vel)
		return 1
	if not is_equal_approx(vel.length(), 10.0):
		push_error("Expected ram speed 10 along the lock, got %s" % vel.length())
		return 1
	return 0


func _test_telegraph_never_reads_walls() -> int:
	var charge: RefCounted = ChargeScript.new()
	charge.call("begin_telegraph")
	charge.call("tick", 2.0)
	if bool(charge.call("can_read_walls")):
		push_error("Telegraph must not wall-stun")
		return 1
	return 0
