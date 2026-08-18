extends RefCounted

const ChargerLaunchScript := preload("res://scripts/monsters/charger_launch.gd")


class _GravityHost extends RefCounted:
	var gravity: Variant = null


func run() -> int:
	var failures := 0
	failures += _test_charge_speed_is_double_sprint()
	failures += _test_patrol_speed_is_80_percent_walk()
	failures += _test_landing_cells_skip_walls_and_nearby()
	failures += _test_pick_prefers_unused_cells()
	failures += _test_launch_arc_reaches_target()
	failures += _test_fallback_stays_on_ground_plane()
	failures += _test_head_plunge_is_down_in_330_360()
	failures += _test_head_toss_is_up()
	failures += _test_gravity_of_skips_null_and_non_floats()
	return failures


func _make_grid() -> Array:
	## 5x5 wall grid with a plus-shaped corridor of open cells.
	var grid: Array = []
	for x in range(5):
		var col: Array = []
		for _y in range(5):
			col.append(1)
		grid.append(col)
	for i in range(5):
		grid[2][i] = 0
		grid[i][2] = 0
	return grid


func _test_charge_speed_is_double_sprint() -> int:
	var speed := ChargerLaunchScript.charge_speed(5.0)
	if not is_equal_approx(speed, 11.5):
		push_error("Expected charger ram at 230%% of sprint 5, got %s" % speed)
		return 1
	if not is_equal_approx(ChargerLaunchScript.charge_speed(0.0), 0.0):
		push_error("Expected zero sprint to yield zero charge speed")
		return 1
	return 0


func _test_patrol_speed_is_80_percent_walk() -> int:
	var speed := ChargerLaunchScript.patrol_speed(3.0)
	if not is_equal_approx(speed, 2.4):
		push_error("Expected charger patrol at 80%% of walk 3, got %s" % speed)
		return 1
	return 0


func _test_landing_cells_skip_walls_and_nearby() -> int:
	var grid := _make_grid()
	var from := Vector2i(2, 2)
	var cells := ChargerLaunchScript.collect_landing_cells(grid, from, 2)
	if cells.is_empty():
		push_error("Expected open landings at least 2 cells away")
		return 1
	for cell in cells:
		if not ChargerLaunchScript.is_open_cell(grid, cell):
			push_error("Landing %s is not an open ground cell" % cell)
			return 1
		if ChargerLaunchScript.chebyshev(from, cell) < 2:
			push_error("Landing %s is closer than 2 cells" % cell)
			return 1
	if cells.has(Vector2i(2, 3)) or cells.has(Vector2i(1, 2)):
		push_error("Adjacent open cells must not be valid landings")
		return 1
	if not cells.has(Vector2i(2, 0)) and not cells.has(Vector2i(0, 2)):
		push_error("Expected far corridor cells such as (2,0) or (0,2)")
		return 1
	return 0


func _test_pick_prefers_unused_cells() -> int:
	var cells: Array[Vector2i] = [Vector2i(0, 2), Vector2i(4, 2)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var used := {Vector2i(0, 2): true}
	var picked := ChargerLaunchScript.pick_landing_cell(cells, rng, used)
	if picked != Vector2i(4, 2):
		push_error("Expected unused landing (4,2), got %s" % picked)
		return 1
	return 0


func _test_launch_arc_reaches_target() -> int:
	var from := Vector3(0.0, 0.2, 0.0)
	var to := Vector3(6.0, 0.2, 0.0)
	var gravity := 18.0
	var flight := ChargerLaunchScript.flight_time_for_distance(6.0)
	var vel := ChargerLaunchScript.launch_velocity(from, to, gravity, flight)
	var landed := ChargerLaunchScript.integrate_launch(from, vel, gravity, flight)
	if landed.distance_to(to) > 0.001:
		push_error("Expected ballistic landing at %s, got %s" % [to, landed])
		return 1
	if vel.y <= 0.0:
		push_error("Expected an upward launch so the player leaves the ground")
		return 1
	return 0


func _test_fallback_stays_on_ground_plane() -> int:
	var from := Vector3(1.0, 0.4, 2.0)
	var land := ChargerLaunchScript.fallback_landing(from, Vector3(0.0, 4.0, -1.0), 3.0)
	if not is_equal_approx(land.y, from.y):
		push_error("Fallback landing must keep the current ground height")
		return 1
	var flat := Vector3(land.x - from.x, 0.0, land.z - from.z)
	if flat.length() < 5.9:
		push_error("Fallback landing should be at least 2 cells (6m) away")
		return 1
	return 0


func _test_head_plunge_is_down_in_330_360() -> int:
	if not is_equal_approx(ChargerLaunchScript.plunge_pitch_rad(360.0), 0.0):
		push_error("Expected 360° plunge to be level (0 rad)")
		return 1
	var down := ChargerLaunchScript.plunge_pitch_rad(330.0)
	if down >= 0.0 or not is_equal_approx(down, deg_to_rad(-30.0)):
		push_error("Expected 330° plunge to be 30° snout-down, got %s" % down)
		return 1
	var mid := ChargerLaunchScript.plunge_pitch_rad(338.0)
	if mid >= 0.0 or mid <= down:
		push_error("Expected default 338° between level and 330° down")
		return 1
	return 0


func _test_head_toss_is_up() -> int:
	var toss := ChargerLaunchScript.toss_pitch_rad(60.0)
	if toss <= 0.0 or not is_equal_approx(toss, deg_to_rad(60.0)):
		push_error("Expected 60° toss to lift the snout, got %s" % toss)
		return 1
	return 0


func _test_gravity_of_skips_null_and_non_floats() -> int:
	if not is_equal_approx(ChargerLaunchScript.gravity_of(null, 18.0), 18.0):
		push_error("Expected null node to keep fallback gravity")
		return 1
	var host := _GravityHost.new()
	if not is_equal_approx(ChargerLaunchScript.gravity_of(host, 18.0), 18.0):
		push_error("Expected null gravity property to keep fallback")
		return 1
	host.gravity = 9.8
	var got := ChargerLaunchScript.gravity_of(host, 18.0)
	if not is_equal_approx(got, 9.8):
		push_error("Expected float gravity from the node, got %s" % got)
		return 1
	host.gravity = 12
	if not is_equal_approx(ChargerLaunchScript.gravity_of(host, 18.0), 12.0):
		push_error("Expected int gravity to coerce to float")
		return 1
	host.gravity = Vector3.DOWN
	if not is_equal_approx(ChargerLaunchScript.gravity_of(host, 18.0), 18.0):
		push_error("Expected non-numeric gravity to keep fallback")
		return 1
	return 0
