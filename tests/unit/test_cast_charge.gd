extends RefCounted

const SpellDefinitionScript := preload("res://scripts/spells/spell_definition.gd")
const GrowingOrbScript := preload("res://scenes/spells/_shared/growing_orb_cast.gd")
const FireballChargeScript := preload("res://scenes/spells/fireball/cast.gd")
const FlareChargeScript := preload("res://scenes/spells/flare/cast.gd")
const WardChargeScript := preload("res://scenes/spells/ward/cast.gd")
const FireballCastScene := preload("res://scenes/spells/fireball/cast.tscn")
const FlareCastScene := preload("res://scenes/spells/flare/cast.tscn")
const WardCastScene := preload("res://scenes/spells/ward/cast.tscn")
const GrowingOrbScene := preload("res://scenes/spells/_shared/growing_orb_cast.tscn")


func run() -> int:
	var failures := 0
	failures += _test_folder_cast_scenes_are_distinct()
	failures += _test_export_overrides_folder_cast()
	failures += _test_scenes_instantiate()
	return failures


func _test_folder_cast_scenes_are_distinct() -> int:
	var fireball := SpellDefinitionScript.new()
	fireball.id = "fireball"
	var flare := SpellDefinitionScript.new()
	flare.id = "flare"
	var generic := SpellDefinitionScript.new()
	generic.id = "pull"
	if fireball.get_cast_charge_scene() != FireballCastScene:
		push_error("fireball/cast.tscn should be the fireball charge scene")
		return 1
	if flare.get_cast_charge_scene() != FlareCastScene:
		push_error("flare/cast.tscn should be the flare charge scene")
		return 1
	if generic.get_cast_charge_scene() != GrowingOrbScene:
		push_error("Spells without cast.tscn should use the shared growing orb")
		return 1
	return 0


func _test_export_overrides_folder_cast() -> int:
	var spell := SpellDefinitionScript.new()
	spell.id = "fireball"
	spell.cast_charge_scene = FlareCastScene
	if spell.get_cast_charge_scene() != FlareCastScene:
		push_error("cast_charge_scene export should override the folder cast scene")
		return 1
	return 0


func _test_scenes_instantiate() -> int:
	var fire: Node = FireballCastScene.instantiate()
	var flare: Node = FlareCastScene.instantiate()
	var ward: Node = WardCastScene.instantiate()
	var orb: Node = GrowingOrbScene.instantiate()
	var ok: bool = (
		fire.get_script() == FireballChargeScript
		and flare.get_script() == FlareChargeScript
		and ward.get_script() == WardChargeScript
		and orb.get_script() == GrowingOrbScript
	)
	fire.free()
	flare.free()
	ward.free()
	orb.free()
	if not ok:
		push_error("Cast scenes must instantiate their authored scripts")
		return 1
	return 0
