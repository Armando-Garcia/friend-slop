extends RefCounted

const WardMeshBuilderScript := preload("res://scripts/spells/ward_mesh_builder.gd")
const WardShieldScript := preload("res://scripts/spells/ward_shield.gd")
const WardScene := preload("res://scenes/spells/ward/ward.tscn")
const ChargerWardAbilityScript := preload(
	"res://scripts/monsters/abilities/charger_ward_ability.gd"
)
const FireballProjectileScript := preload("res://scripts/spells/fireball_projectile.gd")


func run() -> int:
	var failures := 0
	failures += _test_cap_is_one_third_sphere_surface()
	failures += _test_duration_and_radius_constants()
	failures += _test_builder_makes_mesh()
	failures += _test_integrity_tint_goes_red()
	failures += _test_charger_ward_hp_is_four_fireballs()
	failures += _test_baked_scene_keeps_mesh_when_radius_unchanged()
	failures += _test_follow_then_plant_starts_fade()
	failures += _test_runtime_uses_force_field_shader()
	failures += _test_pose_exports_are_tunable()
	return failures


func _test_cap_is_one_third_sphere_surface() -> int:
	var fraction := WardMeshBuilderScript.surface_fraction_of_sphere()
	if absf(fraction - (1.0 / 3.0)) > 0.001:
		push_error("Expected ward dome surface fraction to be 1/3 of a sphere")
		return 1
	return 0


func _test_duration_and_radius_constants() -> int:
	if not is_equal_approx(WardShieldScript.DURATION_SEC, 1.0):
		push_error("Expected ward to linger for 1 second by default")
		return 1
	if WardShieldScript.RADIUS <= 0.5:
		push_error("Expected ward radius large enough to block a fireball")
		return 1
	if not is_equal_approx(WardShieldScript.RADIUS, WardMeshBuilderScript.DEFAULT_RADIUS):
		push_error("Expected WardShield.RADIUS to match mesh builder default")
		return 1
	return 0


func _test_builder_makes_mesh() -> int:
	var mesh := WardMeshBuilderScript.build_mesh()
	if mesh == null or mesh.get_surface_count() < 1:
		push_error("Expected ward mesh builder to produce a surface")
		return 1
	var shape := WardMeshBuilderScript.build_collision_shape()
	if shape == null or shape.points.size() < 8:
		push_error("Expected ward collision shape with dome points")
		return 1
	var larger := WardMeshBuilderScript.build_mesh(2.5, 0.5)
	if larger == null or larger.get_surface_count() < 1:
		push_error("Expected builder to accept radius / surface_fraction overrides")
		return 1
	return 0


func _test_integrity_tint_goes_red() -> int:
	var full := WardShieldScript.integrity_tint(1.0)
	var empty := WardShieldScript.integrity_tint(0.0)
	if not full.is_equal_approx(WardShieldScript.SHIELD_BLUE):
		push_error("Expected full-integrity ward to stay shield blue")
		return 1
	if empty.r <= full.r or empty.g >= full.g:
		push_error("Expected depleted ward tint to read redder than blue")
		return 1
	return 0


func _test_charger_ward_hp_is_four_fireballs() -> int:
	var hp := ChargerWardAbilityScript.default_shield_hit_points()
	var want := FireballProjectileScript.DEFAULT_HIT_DAMAGE * 4.0
	if not is_equal_approx(hp, want):
		push_error("Expected charger ward HP %s (4 fireballs), got %s" % [want, hp])
		return 1
	return 0


func _test_baked_scene_keeps_mesh_when_radius_unchanged() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("Expected SceneTree to instantiate the baked ward")
		return 1
	var packed: PackedScene = WardScene
	if packed == null:
		push_error("Expected scenes/spells/ward.tscn")
		return 1
	var ward: Node3D = packed.instantiate() as Node3D
	tree.root.add_child(ward)
	var dome := ward.get_node_or_null("Dome") as MeshInstance3D
	var baked: Mesh = null if dome == null else dome.mesh
	var same_radius := float(ward.get("radius"))
	ward.set("radius", same_radius)
	var kept := dome != null and dome.mesh != null and dome.mesh == baked
	ward.set("radius", same_radius + 0.25)
	var rebuilt := dome != null and dome.mesh != null and dome.mesh != baked
	tree.root.remove_child(ward)
	ward.queue_free()
	if not kept:
		push_error("Expected an unchanged radius to keep the baked ward mesh")
		return 1
	if not rebuilt:
		push_error("Expected a radius change to rebuild the ward mesh")
		return 1
	return 0


func _test_follow_then_plant_starts_fade() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("Expected SceneTree for ward follow")
		return 1
	var ward: Node3D = WardScene.instantiate() as Node3D
	tree.root.add_child(ward)
	ward.call("start_wand_follow", Vector3.ZERO, Vector3(0.0, 0.0, -1.0), 1)
	var hold := float(ward.get("hold_forward"))
	ward.call("follow_wand", Vector3(0.0, 0.0, 2.0), Vector3(0.0, 0.0, -1.0))
	var following := bool(ward.call("is_channel_following"))
	var moved := absf(ward.global_position.z - (2.0 - hold)) < 0.05
	var beam := ward.get_node_or_null("Beam") as Node3D
	var has_beam := beam != null
	var along_z := beam != null and beam.scale.z > beam.scale.y + 0.1
	var r := float(ward.get("radius"))
	var apex_z := ward.global_position.z - r
	var tip_z := INF
	if beam != null:
		tip_z = beam.global_position.z - beam.scale.z * 0.5
	var stopped_at_glass := tip_z + 0.002 >= apex_z
	ward.call("plant")
	var planted := ward.global_position
	ward.call("follow_wand", Vector3(0.0, 0.0, 8.0), Vector3(0.0, 0.0, -1.0))
	var stayed := ward.global_position.is_equal_approx(planted)
	var still_follow := bool(ward.call("is_channel_following"))
	tree.root.remove_child(ward)
	ward.queue_free()
	if (
		not following
		or not moved
		or not has_beam
		or not along_z
		or not stopped_at_glass
		or still_follow
		or not stayed
	):
		push_error("Expected camera-locked ward whose beam stops at the inner dome")
		return 1
	return 0


func _test_runtime_uses_force_field_shader() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("Expected SceneTree for ward field material")
		return 1
	var ward: Node3D = WardScene.instantiate() as Node3D
	tree.root.add_child(ward)
	ward.call("start_wand_follow", Vector3.ZERO, Vector3(0.0, 0.0, -1.0), 1)
	var dome := ward.get_node_or_null("Dome") as MeshInstance3D
	var beam_mesh := ward.get_node_or_null("Beam/Mesh") as MeshInstance3D
	var is_cyl := beam_mesh != null and beam_mesh.mesh is CylinderMesh
	var dome_mat := null if dome == null else dome.material_override as ShaderMaterial
	var beam_mat := null if beam_mesh == null else beam_mesh.material_override as ShaderMaterial
	var dome_ok := (
		dome_mat != null
		and dome_mat.shader != null
		and str(dome_mat.shader.resource_path).ends_with("force_field.gdshader")
	)
	var beam_ok := (
		beam_mat != null
		and beam_mat.shader != null
		and str(beam_mat.shader.resource_path).ends_with("force_field.gdshader")
	)
	tree.root.remove_child(ward)
	ward.queue_free()
	if not dome_ok or not beam_ok or not is_cyl:
		push_error("Expected a force-field cylinder beam, not a sphere")
		return 1
	return 0


func _test_pose_exports_are_tunable() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("Expected SceneTree for ward pose exports")
		return 1
	var ward: Node3D = WardScene.instantiate() as Node3D
	tree.root.add_child(ward)
	var default_sec := float(ward.get("duration_sec"))
	var default_hold := float(ward.get("hold_forward"))
	var default_width := float(ward.get("beam_diameter"))
	ward.set("duration_sec", 3.5)
	ward.set("hold_forward", 2.2)
	ward.set("beam_diameter", 0.1)
	var tuned_sec := float(ward.get("duration_sec"))
	var tuned_hold := float(ward.get("hold_forward"))
	var tuned_width := float(ward.get("beam_diameter"))
	ward.call("start_wand_follow", Vector3.ZERO, Vector3(0.0, 0.0, -1.0), 1)
	var beam := ward.get_node_or_null("Beam") as Node3D
	var thick := beam != null and is_equal_approx(beam.scale.x, beam.scale.y) and beam.scale.x > 1.5
	tree.root.remove_child(ward)
	ward.queue_free()
	var defaults_ok := (
		is_equal_approx(default_sec, WardShieldScript.DURATION_SEC)
		and is_equal_approx(default_hold, WardShieldScript.HOLD_FORWARD)
		and is_equal_approx(default_width, WardShieldScript.DEFAULT_BEAM_DIAMETER)
	)
	var tuned_ok := (
		is_equal_approx(tuned_sec, 3.5)
		and is_equal_approx(tuned_hold, 2.2)
		and is_equal_approx(tuned_width, 0.1)
	)
	if not defaults_ok or not tuned_ok or beam == null or not thick:
		push_error("Expected Ward linger, hold distance, and beam width to be tunable")
		return 1
	return 0
