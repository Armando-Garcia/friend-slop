class_name TestRoleLoadout
extends RefCounted

const GameStateScript := preload("res://scripts/game_state.gd")
const RoleLoadoutScript := preload("res://scripts/progression/role_loadout.gd")


func run() -> int:
	var failures := 0
	failures += _test_headmaster_gets_union_of_starters()
	failures += _test_apprentice_starter_kit()
	failures += _test_role_labels()
	return failures


func _test_headmaster_gets_union_of_starters() -> int:
	var spell_ids := RoleLoadoutScript.get_starting_spell_ids(GameStateScript.PlayerRole.HEADMASTER)
	var expected_size := (
		RoleLoadoutScript.APPRENTICE_STARTER_SPELLS.size()
		+ RoleLoadoutScript.HEADMASTER_STARTER_SPELLS.size()
	)
	var missing := (
		spell_ids.size() != expected_size
		or not spell_ids.has("fake_wall")
		or not spell_ids.has("clone")
		or not spell_ids.has("show_me")
		or not spell_ids.has("fireball")
		or not spell_ids.has("dispell")
		or not spell_ids.has("flare")
	)
	if missing:
		push_error("Expected headmaster loadout to be union of apprentice and headmaster starters")
		return 1
	return 0


func _test_apprentice_starter_kit() -> int:
	var spell_ids := RoleLoadoutScript.get_starting_spell_ids(
		GameStateScript.PlayerRole.APPRENTICE
	)
	var expected := RoleLoadoutScript.APPRENTICE_STARTER_SPELLS
	var missing_required := (
		not spell_ids.has("show_me")
		or not spell_ids.has("light")
		or not spell_ids.has("light_ball")
		or not spell_ids.has("target")
		or not spell_ids.has("pull")
		or not spell_ids.has("follow")
		or not spell_ids.has("stop")
		or not spell_ids.has("dispell")
		or not spell_ids.has("flare")
		or not spell_ids.has("ward")
	)
	var has_headmaster_spell := false
	for headmaster_id in RoleLoadoutScript.HEADMASTER_STARTER_SPELLS:
		if spell_ids.has(headmaster_id):
			has_headmaster_spell = true
			break
	if spell_ids.size() != expected.size() or missing_required or has_headmaster_spell:
		push_error("Expected apprentice loadout to match apprentice starter kit only")
		return 1
	return 0


func _test_role_labels() -> int:
	if RoleLoadoutScript.role_label(GameStateScript.PlayerRole.HEADMASTER) != "Headmaster":
		push_error("Expected headmaster role label")
		return 1
	if RoleLoadoutScript.role_label(GameStateScript.PlayerRole.APPRENTICE) != "Apprentice":
		push_error("Expected apprentice role label")
		return 1
	return 0
