extends RefCounted

const WardMeshBuilderScript := preload("res://scripts/spells/ward_mesh_builder.gd")
const WardShieldScript := preload("res://scripts/spells/ward_shield.gd")
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
	return failures


func _test_cap_is_one_third_sphere_surface() -> int:
	var fraction := WardMeshBuilderScript.surface_fraction_of_sphere()
	if absf(fraction - (1.0 / 3.0)) > 0.001:
		push_error("Expected ward dome surface fraction to be 1/3 of a sphere")
		return 1
	return 0


func _test_duration_and_radius_constants() -> int:
	if not is_equal_approx(WardShieldScript.DURATION_SEC, 1.0):
		push_error("Expected ward to linger for 1 second")
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
