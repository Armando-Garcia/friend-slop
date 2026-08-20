class_name RoleAssignment
extends RefCounted

## Validates lobby rosters for asymmetric horror (3 apprentices + 1 headmaster at max).

const MIN_HORROR_PLAYERS := 3


static func role_label(role: int) -> String:
	match role:
		GameState.PlayerRole.HEADMASTER:
			return "Headmaster"
		_:
			return "Apprentice"


static func count_roles(roles: Dictionary) -> Dictionary:
	var apprentices := 0
	var headmasters := 0
	for peer_id in roles.keys():
		match int(roles[peer_id]):
			GameState.PlayerRole.HEADMASTER:
				headmasters += 1
			_:
				apprentices += 1
	return {"apprentices": apprentices, "headmasters": headmasters}


static func validate_relaxed_roster(peer_ids: Array, roles: Dictionary) -> Error:
	if peer_ids.is_empty():
		return ERR_INVALID_PARAMETER
	for peer_id in peer_ids:
		if not roles.has(peer_id):
			return ERR_INVALID_PARAMETER
	return OK


static func validate_horror_roster(peer_ids: Array, roles: Dictionary) -> Error:
	if peer_ids.is_empty():
		return ERR_INVALID_PARAMETER
	for peer_id in peer_ids:
		if not roles.has(peer_id):
			return ERR_INVALID_PARAMETER
	var counts := count_roles(roles)
	if peer_ids.size() < MIN_HORROR_PLAYERS:
		return ERR_INVALID_PARAMETER
	if counts.headmasters != 1:
		return ERR_INVALID_PARAMETER
	if counts.apprentices < 2:
		return ERR_INVALID_PARAMETER
	return OK


static func get_horror_start_block_reason(peer_ids: Array, roles: Dictionary) -> String:
	if validate_horror_roster(peer_ids, roles) == OK:
		return ""
	var peer_count := peer_ids.size()
	if peer_count < MIN_HORROR_PLAYERS:
		return "Need at least %d players (%d connected)." % [MIN_HORROR_PLAYERS, peer_count]
	var counts := count_roles(roles)
	if counts.headmasters != 1:
		return "Pick exactly one Headmaster before starting."
	if counts.apprentices < 2:
		return "Need at least two Apprentices before starting."
	return "Roster is not valid yet."


static func default_roles_for_peers(peer_ids: Array) -> Dictionary:
	var result: Dictionary = {}
	var sorted_ids: Array = peer_ids.duplicate()
	sorted_ids.sort()
	for index in range(sorted_ids.size()):
		var peer_id := int(sorted_ids[index])
		if index == 0:
			result[peer_id] = GameState.PlayerRole.HEADMASTER
		else:
			result[peer_id] = GameState.PlayerRole.APPRENTICE
	return result
