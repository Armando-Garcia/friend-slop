class_name TestPlayerCharacterConfig
extends RefCounted

const GameStateScript := preload("res://scripts/game_state.gd")
const PlayerCharacterConfigScript := preload("res://scripts/match/player_character_config.gd")
const RoleLoadoutScript := preload("res://scripts/progression/role_loadout.gd")


func run() -> int:
	var failures := 0
	failures += _test_default_apprentice_summary()
	failures += _test_default_headmaster_summary()
	failures += _test_dict_round_trip()
	failures += _test_headmaster_starting_spells()
	failures += _test_apprentice_starting_spells()
	return failures


func _test_default_apprentice_summary() -> int:
	var config := PlayerCharacterConfigScript.create_default(GameStateScript.PlayerRole.APPRENTICE)
	if config.role != GameStateScript.PlayerRole.APPRENTICE:
		push_error("Expected default apprentice role")
		return 1
	if config.summary() != "Apprentice":
		push_error("Expected apprentice summary to show role label")
		return 1
	return 0


func _test_default_headmaster_summary() -> int:
	var config := PlayerCharacterConfigScript.create_default(GameStateScript.PlayerRole.HEADMASTER)
	if config.summary() != "Headmaster":
		push_error("Expected headmaster summary to show role label")
		return 1
	return 0


func _test_dict_round_trip() -> int:
	var original := PlayerCharacterConfigScript.create_default(GameStateScript.PlayerRole.HEADMASTER)
	original.team_id = 2
	var restored := PlayerCharacterConfigScript.from_dict(original.to_dict())
	if restored.role != GameStateScript.PlayerRole.HEADMASTER:
		push_error("Expected character config round-trip to preserve role")
		return 1
	if restored.team_id != 2:
		push_error("Expected character config round-trip to preserve team_id")
		return 1
	var legacy := PlayerCharacterConfigScript.from_dict(
		{"role": GameStateScript.PlayerRole.APPRENTICE}
	)
	if legacy.team_id != 0:
		push_error("Expected missing team_id to default to 0")
		return 1
	return 0


func _test_headmaster_starting_spells() -> int:
	var config := PlayerCharacterConfigScript.create_default(GameStateScript.PlayerRole.HEADMASTER)
	var spell_ids := config.get_starting_spell_ids()
	var expected_size := (
		RoleLoadoutScript.APPRENTICE_STARTER_SPELLS.size()
		+ RoleLoadoutScript.HEADMASTER_STARTER_SPELLS.size()
	)
	var missing := (
		spell_ids.size() != expected_size
		or not spell_ids.has("fake_wall")
		or not spell_ids.has("clone")
		or not spell_ids.has("show_me")
	)
	if missing:
		push_error("Expected headmaster config to expose union of starter spells")
		return 1
	return 0


func _test_apprentice_starting_spells() -> int:
	var config := PlayerCharacterConfigScript.create_default(GameStateScript.PlayerRole.APPRENTICE)
	var spell_ids := config.get_starting_spell_ids()
	if spell_ids.size() != RoleLoadoutScript.APPRENTICE_STARTER_SPELLS.size():
		push_error("Expected apprentice config to expose all apprentice starting spells")
		return 1
	if not spell_ids.has("fireball") or not spell_ids.has("light"):
		push_error("Expected apprentice loadout to include fireball and light")
		return 1
	return 0
