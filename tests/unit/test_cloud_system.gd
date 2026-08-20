class_name TestCloudSystem
extends RefCounted

const CloudSystemScript := preload("res://scripts/environment/cloud_system.gd")
const CloudStateScript := preload("res://scripts/environment/cloud_state.gd")

var failures: int = 0


func run() -> int:
	test_deterministic_positions()
	test_count_scales_with_coverage()
	test_fixed_spawn_area()
	test_wind_speed_drives_velocity()
	test_clouds_cast_shadows()
	test_clouds_spawn_within_bounds()
	test_wrap_around()
	test_horizon_arc()
	return failures


func test_deterministic_positions() -> void:
	var bounds_min := Vector3(-100.0, 80.0, -100.0)
	var bounds_max := Vector3(100.0, 120.0, 100.0)
	var seed_value := 4242

	var system_a := _make_system(bounds_min, bounds_max, seed_value)
	var system_b := _make_system(bounds_min, bounds_max, seed_value)

	_assert_eq(
		system_a.get_cloud_count(),
		system_b.get_cloud_count(),
		"same seed should produce same cloud count"
	)

	var elapsed := 12.34
	for i in system_a.get_cloud_count():
		var state_a: CloudState = system_a.get_cloud_state(i)
		var state_b: CloudState = system_b.get_cloud_state(i)
		var pos_a := state_a.position_at(elapsed, bounds_min, bounds_max)
		var pos_b := state_b.position_at(elapsed, bounds_min, bounds_max)
		_assert_eq(pos_a, pos_b, "same seed should produce same cloud positions")
		_assert_eq(
			state_a.mesh_index,
			state_b.mesh_index,
			"same seed should pick the same pool mesh"
		)

	_free_system(system_a)
	_free_system(system_b)


func test_count_scales_with_coverage() -> void:
	var sparse := CloudSystemScript.new()
	sparse.spawn_size = Vector3(680.0, 40.0, 680.0)
	sparse.sky_coverage = 0.1
	var dense := CloudSystemScript.new()
	dense.spawn_size = Vector3(680.0, 40.0, 680.0)
	dense.sky_coverage = 0.8

	var root := Node3D.new()
	root.add_child(sparse)
	root.add_child(dense)
	sparse.configure_from_spawn_area(1234, 1000)
	dense.configure_from_spawn_area(1234, 1000)

	_assert_true(
		dense.get_cloud_count() > sparse.get_cloud_count(),
		"higher sky coverage should produce more clouds"
	)

	root.queue_free()


func test_fixed_spawn_area() -> void:
	var root := Node3D.new()
	var system: CloudSystem = CloudSystemScript.new()
	system.spawn_size = Vector3(500.0, 30.0, 400.0)
	system.spawn_center_y = 110.0
	root.add_child(system)
	# Maze dims must not change the fixed spawn box.
	system.configure_for_maze(15, 15, 3.0, 200.0, 1234, 1000)
	var size := system.get_bounds_max() - system.get_bounds_min()
	_assert_true(
		is_equal_approx(size.x, 500.0) and is_equal_approx(size.z, 400.0),
		"spawn bounds should match fixed spawn_size, not maze size"
	)
	_assert_true(
		is_equal_approx(size.y, 30.0),
		"spawn band thickness should match spawn_size.y"
	)
	_assert_true(
		is_equal_approx(system.get_travel_span(), 500.0),
		"travel span should be the larger horizontal spawn axis"
	)

	system.configure_for_maze(45, 45, 3.0, 200.0, 1234, 1000)
	var size_large_maze := system.get_bounds_max() - system.get_bounds_min()
	_assert_eq(size_large_maze, size, "maze size changes should not alter cloud spawn box")

	root.queue_free()


func test_wind_speed_drives_velocity() -> void:
	var root := Node3D.new()
	var system: CloudSystem = CloudSystemScript.new()
	system.spawn_size = Vector3(200.0, 20.0, 200.0)
	system.sky_coverage = 0.2
	system.wind_direction = 0.0
	system.wind_speed = 12.0
	root.add_child(system)
	system.configure_from_spawn_area(99, 1000)

	var drift := system.get_shared_drift_velocity()
	_assert_true(
		is_equal_approx(drift.length(), 12.0),
		"shared drift speed should match wind_speed"
	)
	_assert_true(
		system.get_cloud_count() > 0,
		"expected clouds for wind speed check"
	)
	var state: CloudState = system.get_cloud_state(0)
	_assert_true(
		is_equal_approx(state.velocity.length(), 12.0),
		"each cloud velocity should match wind_speed"
	)

	system.wind_speed = 3.0
	_assert_true(
		is_equal_approx(system.get_shared_drift_velocity().length(), 3.0),
		"updating wind_speed should update live drift velocity"
	)

	root.queue_free()


func test_clouds_cast_shadows() -> void:
	var system := _make_system(
		Vector3(-100.0, 80.0, -100.0), Vector3(100.0, 120.0, 100.0), 999
	)
	var holder := system.get_node("Clouds")
	_assert_true(holder.get_child_count() > 0, "cloud holder should have children")

	for child in holder.get_children():
		var root: Node3D = child as Node3D
		_assert_true(root != null, "cloud child should be a Node3D scene instance")
		var mesh: MeshInstance3D = root.get_node_or_null("Mesh") as MeshInstance3D
		_assert_true(mesh != null, "cloud should have a Mesh child")
		_assert_true(mesh.mesh != null, "cloud should use a pool mesh")
		var shadow: MeshInstance3D = root.get_node_or_null("ShadowCaster") as MeshInstance3D
		_assert_true(shadow != null, "cloud should have an opaque shadow caster")
		_assert_true(
			shadow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
			"cloud shadow proxy should cast shadows only"
		)
		_assert_true(
			shadow.mesh is BoxMesh or shadow.mesh is SphereMesh,
			"cloud shadow proxy should use a simple box/sphere mesh"
		)

	_free_system(system)


func test_clouds_spawn_within_bounds() -> void:
	var bounds_min := Vector3(-120.0, 90.0, -120.0)
	var bounds_max := Vector3(120.0, 150.0, 120.0)
	var system := _make_system(bounds_min, bounds_max, 5555)

	for i in system.get_cloud_count():
		var state: CloudState = system.get_cloud_state(i)
		var pos := state.position_at(0.0, bounds_min, bounds_max)
		_assert_true(
			pos.x >= bounds_min.x and pos.x <= bounds_max.x,
			"cloud x position should be within bounds"
		)
		_assert_true(
			pos.y >= bounds_min.y and pos.y <= bounds_max.y,
			"cloud y position should be within bounds"
		)
		_assert_true(
			pos.z >= bounds_min.z and pos.z <= bounds_max.z,
			"cloud z position should be within bounds"
		)

	_free_system(system)


func test_wrap_around() -> void:
	var state := CloudStateScript.new()
	state.base_position = Vector3(0.0, 100.0, 0.0)
	state.velocity = Vector3(10.0, 0.0, 0.0)
	state.arc_amplitude = 0.0

	var bounds_min := Vector3(-50.0, 90.0, -50.0)
	var bounds_max := Vector3(50.0, 110.0, 50.0)

	var pos_before := state.position_at(4.0, bounds_min, bounds_max)
	var pos_after := state.position_at(14.0, bounds_min, bounds_max)

	_assert_true(
		pos_after.x < bounds_max.x,
		"cloud should wrap back into bounds"
	)
	_assert_true(
		pos_after.x >= bounds_min.x,
		"wrapped cloud should remain inside bounds"
	)
	_assert_eq(
		pos_before.x,
		pos_after.x,
		"positions should repeat after one full wrap cycle"
	)


func test_horizon_arc() -> void:
	var state := CloudStateScript.new()
	state.base_position = Vector3(0.0, 100.0, 0.0)
	state.velocity = Vector3(4.0, 0.0, 0.0)
	state.arc_amplitude = 6.0
	state.arc_wavelength = 40.0
	state.arc_phase = 0.0

	var bounds_min := Vector3(-200.0, 80.0, -200.0)
	var bounds_max := Vector3(200.0, 140.0, 200.0)

	var flat_y := state.position_at(0.0, bounds_min, bounds_max).y
	var arced_y := state.position_at(2.5, bounds_min, bounds_max).y
	_assert_true(
		not is_equal_approx(flat_y, arced_y),
		"clouds should follow a slight vertical arc while drifting"
	)


func _make_system(bounds_min: Vector3, bounds_max: Vector3, seed_value: int) -> CloudSystem:
	var root := Node3D.new()
	var system: CloudSystem = CloudSystemScript.new()
	root.add_child(system)
	system.configure(bounds_min, bounds_max, seed_value, Time.get_ticks_msec())
	return system


func _free_system(system: CloudSystem) -> void:
	if system != null and system.get_parent() != null:
		system.get_parent().queue_free()


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		failures += 1
		push_error("  FAIL: %s" % message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		print("  PASS: %s" % message)
	else:
		failures += 1
		push_error("  FAIL: %s (expected %s, got %s)" % [message, expected, actual])
