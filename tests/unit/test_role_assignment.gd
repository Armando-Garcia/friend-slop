class_name TestRoleAssignment
extends RefCounted

const GameStateScript := preload("res://scripts/game_state.gd")
const RoleAssignmentScript := preload("res://scripts/match/role_assignment.gd")


func run() -> int:
	var failures := 0
	failures += _test_default_roles_one_headmaster()
	failures += _test_valid_three_player_roster()
	failures += _test_rejects_two_headmasters()
	failures += _test_rejects_too_few_players()
	failures += _test_rejects_missing_role()
	failures += _test_relaxed_two_player_roster()
	return failures


func _test_default_roles_one_headmaster() -> int:
	var peers: Array = [1, 2, 3]
	var roles := RoleAssignmentScript.default_roles_for_peers(peers)
	var counts := RoleAssignmentScript.count_roles(roles)
	if counts.headmasters != 1:
		push_error("Expected default roles to assign one Headmaster")
		return 1
	if counts.apprentices != 2:
		push_error("Expected default roles to assign two Apprentices")
		return 1
	if int(roles[1]) != GameStateScript.PlayerRole.HEADMASTER:
		push_error("Expected lowest peer id to become Headmaster by default")
		return 1
	return 0


func _test_valid_three_player_roster() -> int:
	var peers: Array = [1, 2, 3]
	var roles := {
		1: GameStateScript.PlayerRole.HEADMASTER,
		2: GameStateScript.PlayerRole.APPRENTICE,
		3: GameStateScript.PlayerRole.APPRENTICE,
	}
	if RoleAssignmentScript.validate_horror_roster(peers, roles) != OK:
		push_error("Expected valid 3-player horror roster")
		return 1
	return 0


func _test_rejects_two_headmasters() -> int:
	var peers: Array = [1, 2, 3]
	var roles := {
		1: GameStateScript.PlayerRole.HEADMASTER,
		2: GameStateScript.PlayerRole.HEADMASTER,
		3: GameStateScript.PlayerRole.APPRENTICE,
	}
	if RoleAssignmentScript.validate_horror_roster(peers, roles) == OK:
		push_error("Expected roster with two Headmasters to fail validation")
		return 1
	return 0


func _test_rejects_too_few_players() -> int:
	var peers: Array = [1, 2]
	var roles := {
		1: GameStateScript.PlayerRole.HEADMASTER,
		2: GameStateScript.PlayerRole.APPRENTICE,
	}
	if RoleAssignmentScript.validate_horror_roster(peers, roles) == OK:
		push_error("Expected two-player roster to fail validation")
		return 1
	return 0


func _test_rejects_missing_role() -> int:
	var peers: Array = [1, 2, 3]
	var roles := {
		1: GameStateScript.PlayerRole.HEADMASTER,
		2: GameStateScript.PlayerRole.APPRENTICE,
	}
	if RoleAssignmentScript.validate_horror_roster(peers, roles) == OK:
		push_error("Expected roster missing a peer role to fail validation")
		return 1
	return 0


func _test_relaxed_two_player_roster() -> int:
	var peers: Array = [1, 2]
	var roles := {
		1: GameStateScript.PlayerRole.HEADMASTER,
		2: GameStateScript.PlayerRole.APPRENTICE,
	}
	if RoleAssignmentScript.validate_relaxed_roster(peers, roles) != OK:
		push_error("Expected relaxed roster to allow two players")
		return 1
	if RoleAssignmentScript.validate_horror_roster(peers, roles) == OK:
		push_error("Expected horror roster to still reject two players")
		return 1
	return 0
