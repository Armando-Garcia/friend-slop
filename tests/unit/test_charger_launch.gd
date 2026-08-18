extends RefCounted

const ChargerLaunchScript := preload("res://scripts/monsters/charger_launch.gd")


func run() -> int:
	var failures := 0
	failures += _test_charge_speed_is_double_sprint()
	failures += _test_landing_cells_skip_walls_and_nearby()
	failures += _test_pick_prefers_unused_cells()
	failures += _test_launch_arc_reaches_target()
	failures += _test_fallback_stays_on_ground_plane()
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
	if not is_equal_approx(speed, 10.0):
		push_error("Expected charger ram at 200%% of sprint 5, got %s" % speed)
		return 1
	if not is_equal_approx(ChargerLaunchScript.charge_speed(0.0), 0.0):
		push_error("Expected zero sprint to yield zero charge speed")
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
