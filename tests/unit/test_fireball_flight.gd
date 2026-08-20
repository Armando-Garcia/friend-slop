class_name TestFireballFlight
extends RefCounted

const FireballFlightScript := preload("res://scripts/spells/fireball_flight.gd")
const FireballProjectileScript := preload("res://scripts/spells/fireball_projectile.gd")
const FireballExplosionEffectScript := preload("res://scripts/spells/fireball_explosion_effect.gd")
const FireballParticlesScript := preload("res://scripts/spells/fireball_particles.gd")
const FireballLightingScript := preload("res://scripts/spells/fireball_lighting.gd")


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += _test_normal_lifetime()
	failures += _test_smoke_trail_fade_delay()
	failures += _test_smoke_uses_mist_texture_without_shadows()
	failures += _test_embers_use_fine_spark_texture()
	failures += _test_burst_particle_defaults()
	failures += _test_hit_radius_matches_visual()
	failures += _test_cast_lights_use_shadows()
	failures += _test_spawn_sets_global_position(tree)
	failures += _test_explosion_spawn_sets_global_position(tree)
	failures += _test_max_lifetime_spawns_explosion_at_global_position(tree)
	return failures


func _test_normal_lifetime() -> int:
	if not FireballFlightScript.should_finish_normal(FireballFlightScript.MAX_LIFETIME):
		push_error("Expected normal fireball to finish at max lifetime")
		return 1
	if FireballFlightScript.should_finish_normal(FireballFlightScript.MAX_LIFETIME - 0.1):
		push_error("Expected normal fireball to keep flying before max lifetime")
		return 1
	return 0


func _test_smoke_trail_fade_delay() -> int:
	var delay := FireballParticlesScript.smoke_trail_fade_delay_sec(2.0)
	if not is_equal_approx(delay, 2.35):
		push_error("Expected smoke trail fade delay to include padding")
		return 1
	return 0


func _test_smoke_uses_mist_texture_without_shadows() -> int:
	var smoke := FireballParticlesScript.make_smoke_trail_emitter()
	if smoke.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		push_error("Expected smoke particles to disable shadow casting")
		return 1
	var mat := smoke.material_override as StandardMaterial3D
	if mat == null or mat.albedo_texture == null:
		push_error("Expected smoke particles to use a soft mist albedo texture")
		return 1
	if not (mat.albedo_texture is GradientTexture2D):
		push_error("Expected smoke mist texture to be a radial GradientTexture2D")
		return 1
	return 0


func _test_embers_use_fine_spark_texture() -> int:
	var embers := FireballParticlesScript.make_comet_spark_emitter()
	var mat := embers.material_override as StandardMaterial3D
	if mat == null or mat.albedo_texture == null:
		push_error("Expected ember particles to use a soft spark albedo texture")
		return 1
	if mat.blend_mode != BaseMaterial3D.BLEND_MODE_ADD:
		push_error("Expected ember particles to use additive blending")
		return 1
	var mesh := embers.mesh as QuadMesh
	if mesh == null or mesh.size.x > 0.08:
		push_error("Expected ember mesh quads to stay tiny for fine sparks")
		return 1
	if embers.scale_amount_max > 0.1:
		push_error("Expected ember scale to stay fine-particle sized")
		return 1
	return 0


func _test_burst_particle_defaults() -> int:
	var burst := FireballParticlesScript.make_burst(
		"TestBurst",
		32,
		Color.WHITE,
		2.0,
		8.0,
		0.5,
		0.9
	)
	var failures := 0
	if burst.amount != 32:
		push_error("Expected burst particle amount to match request")
		failures += 1
	if not burst.one_shot:
		push_error("Expected burst particles to be one-shot")
		failures += 1
	if burst.local_coords:
		push_error("Expected burst particles to use world coordinates")
		failures += 1
	if burst.material_override == null:
		push_error("Expected burst particles to assign a material")
		failures += 1
	else:
		var mat := burst.material_override as StandardMaterial3D
		if mat.albedo_color != Color(1.0, 1.0, 1.0, 1.0):
			push_error("Expected particle material to use white albedo for vertex colors")
			failures += 1
		if not mat.vertex_color_use_as_albedo:
			push_error("Expected particle material to tint from vertex colors")
			failures += 1
	if burst.mesh == null:
		push_error("Expected burst particles to assign a render mesh")
		failures += 1
	return failures


func _test_hit_radius_matches_visual() -> int:
	if FireballFlightScript.HIT_RADIUS >= FireballFlightScript.VISUAL_RADIUS:
		push_error("Expected fireball hit radius to stay inside the visible orb")
		return 1
	if FireballFlightScript.HIT_RADIUS <= 0.0:
		push_error("Expected fireball hit radius to stay positive")
		return 1
	return 0


func _test_cast_lights_use_shadows() -> int:
	var travel := FireballLightingScript.make_travel_cast_light()
	if travel.shadow_enabled:
		push_error("Expected travel fireball light to skip shadows to avoid square shadow artifacts")
		return 1

	var flash := FireballLightingScript.make_explosion_flash_light()
	if not flash.shadow_enabled:
		push_error("Expected explosion flash light to cast shadows")
		return 1
	return 0


func _test_spawn_sets_global_position(tree: SceneTree) -> int:
	var world := Node3D.new()
	world.position = Vector3(10.0, 0.0, 0.0)
	tree.root.add_child(world)

	var origin := Vector3(5.0, 2.0, 3.0)
	var projectile := FireballProjectileScript.spawn(
		world, origin, Vector3(0.0, 0.0, -1.0)
	)
	if not projectile.is_inside_tree():
		push_error("Expected spawned fireball projectile to enter the scene tree")
		world.queue_free()
		return 1
	if not projectile.global_position.is_equal_approx(origin):
		push_error(
			"Expected fireball projectile at global %s, got %s"
			% [origin, projectile.global_position]
		)
		world.queue_free()
		return 1

	world.queue_free()
	return 0


func _test_explosion_spawn_sets_global_position(tree: SceneTree) -> int:
	var world := Node3D.new()
	world.position = Vector3(0.0, 5.0, 0.0)
	tree.root.add_child(world)

	var impact := Vector3(3.0, 1.0, -2.0)
	var effect := FireballExplosionEffectScript.spawn(world, impact)
	if not effect.is_inside_tree():
		push_error("Expected spawned explosion effect to enter the scene tree")
		world.queue_free()
		return 1
	if not effect.global_position.is_equal_approx(impact):
		push_error(
			"Expected explosion effect at global %s, got %s"
			% [impact, effect.global_position]
		)
		world.queue_free()
		return 1

	world.queue_free()
	return 0


func _test_max_lifetime_spawns_explosion_at_global_position(tree: SceneTree) -> int:
	var world := Node3D.new()
	world.position = Vector3(8.0, 2.0, -3.0)
	tree.root.add_child(world)

	var origin := Vector3(1.0, 4.0, 2.0)
	var projectile := FireballProjectileScript.spawn(
		world, origin, Vector3(0.0, 0.0, -1.0)
	)
	if not projectile.is_inside_tree():
		push_error("Expected projectile in tree before max-lifetime finish")
		world.queue_free()
		return 1

	projectile._physics_process(FireballFlightScript.MAX_LIFETIME)

	var explosion: FireballExplosionEffect = null
	for child in world.get_children():
		if child is FireballExplosionEffect:
			explosion = child
			break

	if explosion == null:
		push_error("Expected max-lifetime projectile to spawn explosion effect")
		world.queue_free()
		return 1
	if not explosion.is_inside_tree():
		push_error("Expected explosion effect to enter scene tree via _finish path")
		world.queue_free()
		return 1
	if not explosion.global_position.is_equal_approx(origin):
		push_error(
			"Expected explosion at global %s after max lifetime, got %s"
			% [origin, explosion.global_position]
		)
		world.queue_free()
		return 1

	world.queue_free()
	return 0
