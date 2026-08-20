extends RefCounted

const LoadoutScript := preload("res://scripts/spells/character_spell_loadout.gd")
const SpellDefinitionScript := preload("res://scripts/spells/spell_definition.gd")


func run() -> int:
	var failures := 0
	failures += _test_unknown_spell_not_known()
	failures += _test_learn_and_query()
	failures += _test_learn_unknown_fails()
	failures += _test_unlearn()
	failures += _test_starting_vs_learned_sets()
	failures += _test_flare_ammo_bucket()
	return failures


func _make_loadout() -> LoadoutScript:
	var loadout := LoadoutScript.new()
	var show_me := SpellDefinitionScript.new()
	show_me.id = "show_me"
	show_me.display_name = "Show Me"
	var haste := SpellDefinitionScript.new()
	haste.id = "haste"
	haste.display_name = "Haste"
	loadout.configure([show_me, haste])
	return loadout


func _test_unknown_spell_not_known() -> int:
	var loadout := _make_loadout()
	if loadout.knows("show_me"):
		push_error("Expected unknown spell to be absent from loadout")
		return 1
	return 0


func _test_learn_and_query() -> int:
	var loadout := _make_loadout()
	if not loadout.learn_spell("show_me", "test"):
		push_error("Expected learn_spell to succeed")
		return 1
	if not loadout.knows("show_me"):
		push_error("Expected spell to be known after learn")
		return 1
	var spells := loadout.get_known_spells()
	if spells.size() != 1 or spells[0].id != "show_me":
		push_error("Expected get_known_spells to return learned spell")
		return 1
	return 0


func _test_learn_unknown_fails() -> int:
	var loadout := _make_loadout()
	if loadout.learn_spell("missing"):
		push_error("Expected learn_spell to fail for unknown id")
		return 1
	return 0


func _test_unlearn() -> int:
	var loadout := _make_loadout()
	loadout.learn_spell("show_me")
	loadout.unlearn_spell("show_me")
	if loadout.knows("show_me"):
		push_error("Expected spell to be removed after unlearn")
		return 1
	return 0


func _test_starting_vs_learned_sets() -> int:
	var loadout := _make_loadout()
	loadout.apply_starting_spells(["show_me"])
	if not loadout.learn_spell("haste", "tome"):
		push_error("Expected tome learn to succeed")
		return 1
	var starting_ids := loadout.get_starting_spell_ids()
	var learned_ids := loadout.get_learned_spell_ids()
	if starting_ids != ["show_me"]:
		push_error("Expected starting set to contain only show_me")
		return 1
	if learned_ids != ["haste"]:
		push_error("Expected learned set to contain only haste")
		return 1
	if loadout.get_known_spell_ids().size() != 2:
		push_error("Expected known set to be union of starting and learned")
		return 1
	if loadout.learn_spell("show_me", "tome"):
		push_error("Expected learning an already-starting spell to fail")
		return 1
	return 0


func _test_flare_ammo_bucket() -> int:
	var FlareEffectScript := preload("res://scripts/spells/flare_effect.gd")
	FlareEffectScript._invalidate_authored_ammo_cache()
	var authored_max: int = FlareEffectScript.authored_ammo_max()
	var authored_refill: float = FlareEffectScript.authored_ammo_refill_sec()
	var loadout := LoadoutScript.new()
	var flare := SpellDefinitionScript.new()
	flare.id = "flare"
	flare.display_name = "Flare"
	flare.cooldown_sec = 0.0
	loadout.configure([flare])
	loadout.apply_starting_spells(["flare"])
	var failures := 0
	if loadout.ammo_count("flare") != authored_max:
		push_error(
			"Expected flare bucket to start full at %s, got %s"
			% [authored_max, loadout.ammo_count("flare")]
		)
		failures += 1
	if loadout.is_on_cooldown("flare"):
		push_error("Expected full flare bucket to be castable")
		failures += 1
	loadout.start_cooldown("flare")
	if loadout.ammo_count("flare") != authored_max - 1:
		push_error("Expected casting flare to spend one ammo")
		failures += 1
	var refill := loadout.remaining_ammo_refill_sec("flare")
	if refill <= authored_refill * 0.75 or refill > authored_refill + 0.05:
		push_error(
			"Expected refill timer near %ss after spend, got %s"
			% [authored_refill, refill]
		)
		failures += 1
	for _i in range(authored_max - 1):
		loadout.start_cooldown("flare")
	if loadout.ammo_count("flare") != 0:
		push_error("Expected empty flare bucket after spending all ammo")
		failures += 1
	if not loadout.is_on_cooldown("flare"):
		push_error("Expected empty flare bucket to block casting")
		failures += 1
	if loadout.spend_ammo("flare"):
		push_error("Expected spend_ammo to fail when empty")
		failures += 1
	return failures
