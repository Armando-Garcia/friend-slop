class_name TestFlareEffect
extends RefCounted

## FlareEffect spawn + aim wiring.

const FlareEffectScript := preload("res://scripts/spells/flare_effect.gd")
const FlareFlightScript := preload("res://scripts/spells/flare_flight.gd")


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += _test_flare_spawn_sets_global_position(tree)
	failures += _test_flare_launch_follows_aim(tree)
	return failures


func _test_flare_spawn_sets_global_position(tree: SceneTree) -> int:
	var world := Node3D.new()
	tree.root.add_child(world)
	var pos := Vector3(2.0, 4.0, -1.0)
	var flare := FlareEffectScript.spawn(world, pos, 0.1)
	if not flare.is_inside_tree():
		push_error("Expected spawned flare to enter the scene tree")
		world.queue_free()
		return 1
	if not flare.global_position.is_equal_approx(pos):
		push_error(
			"Expected flare at global %s, got %s" % [pos, flare.global_position]
		)
		world.queue_free()
		return 1
	world.queue_free()
	return 0


func _test_flare_launch_follows_aim(tree: SceneTree) -> int:
	var world := Node3D.new()
	tree.root.add_child(world)
	var origin := Vector3(1.0, 2.0, 3.0)
	var aim := Vector3(0.4, 0.2, -0.8).normalized()
	var expected := FlareFlightScript.launch_direction(aim)
	var flare := FlareEffectScript.spawn_launched(world, origin, aim)
	if not flare.is_inside_tree():
		push_error("Expected launched flare to enter the scene tree")
		world.queue_free()
		return 1
	if not flare.global_position.is_equal_approx(origin):
		push_error("Expected flare at spawn origin")
		world.queue_free()
		return 1
	var flown: Vector3 = flare.get("_direction")
	if not flown.is_equal_approx(expected):
		push_error("Expected flare to follow crosshair aim, got %s" % flown)
		world.queue_free()
		return 1
	var flying: bool = flare.get("_flying")
	if not flying:
		push_error("Expected launched flare to be flying")
		world.queue_free()
		return 1
	world.queue_free()
	return 0
