class_name TestMoon
extends RefCounted

const MoonScene := preload("res://scenes/environment/moon.tscn")


func run() -> int:
	var failures := 0
	failures += _test_shadow_distance_scales_with_maze()
	failures += _test_moon_light_follows_moon_position()
	failures += _test_moon_shadow_settings_reduce_artifacts()
	return failures


func _scene_root() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root
	return null


func _make_moon(position: Vector3) -> Dictionary:
	## Moon light sync requires an active scene tree (global transforms).
	var holder := Node3D.new()
	var moon: Moon = MoonScene.instantiate()
	holder.add_child(moon)
	var tree_root := _scene_root()
	if tree_root != null:
		tree_root.add_child(holder)
	moon.position = position
	return {"holder": holder, "moon": moon}


func _free_moon(fixture: Dictionary) -> void:
	var holder: Node = fixture.get("holder")
	if holder == null:
		return
	if holder.get_parent() != null:
		holder.get_parent().remove_child(holder)
	holder.free()


func _test_shadow_distance_scales_with_maze() -> int:
	var fixture := _make_moon(Vector3(40.0, 450.0, 50.0))
	var moon: Moon = fixture["moon"]
	moon.configure_for_maze(45, 45, 3.0)
	var moon_light: DirectionalLight3D = moon.get_node("MoonLight")
	if moon_light == null:
		_free_moon(fixture)
		push_error("Expected MoonLight node to exist")
		return 1
	if moon_light.directional_shadow_max_distance < 250.0:
		_free_moon(fixture)
		push_error("Expected moon shadow distance to cover large mazes")
		return 1
	if not moon.position.is_equal_approx(Vector3(40.0, 450.0, 50.0)):
		_free_moon(fixture)
		push_error("Expected configure_for_maze to keep the authored moon position")
		return 1
	_free_moon(fixture)
	return 0


func _test_moon_light_follows_moon_position() -> int:
	var fixture := _make_moon(Vector3(90.0, 300.0, 0.0))
	var moon: Moon = fixture["moon"]
	moon.configure_for_maze(45, 45, 3.0)
	var moon_light: DirectionalLight3D = moon.get_node("MoonLight")
	var light_dir := -moon_light.global_transform.basis.z
	var expected_cast := moon.light_cast_direction()
	if light_dir.dot(expected_cast) < 0.99:
		_free_moon(fixture)
		push_error("Expected moon light to cast from moon toward maze origin")
		return 1
	# Moving the moon should re-aim the light without changing the authored offset intent.
	moon.position = Vector3(0.0, 500.0, 0.0)
	moon._sync_light_from_moon_position()
	light_dir = -moon_light.global_transform.basis.z
	if light_dir.dot(Vector3.DOWN) < 0.99:
		_free_moon(fixture)
		push_error("Expected overhead moon to cast light straight down")
		return 1
	_free_moon(fixture)
	return 0


func _test_moon_shadow_settings_reduce_artifacts() -> int:
	var fixture := _make_moon(Vector3(20.0, 400.0, 20.0))
	var moon: Moon = fixture["moon"]
	moon.configure_for_maze(45, 45, 3.0)
	var moon_light: DirectionalLight3D = moon.get_node("MoonLight")
	var issue := ""
	if moon_light.directional_shadow_mode != DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS:
		issue = "Expected moon to use 4-split directional shadows for cloud coverage"
	elif not moon_light.directional_shadow_blend_splits:
		issue = "Expected moon cascade blending enabled for soft cloud shadow transitions"
	elif moon_light.directional_shadow_pancake_size < 10.0:
		issue = "Expected moon shadow pancake enabled for high cloud casters"
	elif moon_light.light_angular_distance > 0.0:
		issue = "Expected moon light angular distance off (no PCSS dither)"
	elif moon_light.shadow_blur > 1.5:
		issue = "Expected moon shadow blur to stay mild"
	elif moon_light.shadow_bias > 0.35:
		issue = "Expected moon shadow bias to stay moderate (avoid peter-panning)"
	elif moon_light.shadow_normal_bias < 1.5:
		issue = "Expected moon normal bias high enough to avoid floor streaking"
	elif moon_light.shadow_normal_bias > 6.0:
		issue = "Expected moon normal bias to stay moderate (avoid peter-panning)"
	elif moon_light.directional_shadow_max_distance < 42.0:
		issue = "Expected moon shadow distance to reach the cloud layer"
	elif moon_light.directional_shadow_max_distance > 420.0:
		issue = "Expected moon shadow distance capped to reduce cascade flicker"
	_free_moon(fixture)
	if not issue.is_empty():
		push_error(issue)
		return 1
	return 0
