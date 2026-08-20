class_name TestNetworkManager
extends RefCounted

const NetworkManagerScript := preload("res://scripts/network/network_manager.gd")
const MultiplayerTransportScript := preload("res://scripts/network/multiplayer_transport.gd")
const LobbyMatchStateScript := preload("res://scripts/match/lobby_match_state.gd")
const GameStateScript := preload("res://scripts/game_state.gd")


func run() -> int:
	var failures := 0
	failures += _test_compute_player_index_for_host_only()
	failures += _test_compute_player_index_for_three_peers()
	failures += _test_disconnect_session_delegates_to_transport()
	failures += _test_collect_lobby_peer_ids()
	failures += _test_client_player_index_from_lobby_roster()
	failures += _test_format_lobby_player_label()
	failures += _test_normalize_lobby_roles()
	failures += _test_pack_roles_for_peers()
	return failures


func _test_compute_player_index_for_host_only() -> int:
	if NetworkManagerScript.compute_player_index_for_peers(1, []) != 0:
		push_error("Expected host peer id 1 to map to player index 0")
		return 1
	return 0


func _test_compute_player_index_for_three_peers() -> int:
	var peers: Array = [2, 3]
	if NetworkManagerScript.compute_player_index_for_peers(1, peers) != 0:
		push_error("Expected host to remain player index 0")
		return 1
	if NetworkManagerScript.compute_player_index_for_peers(2, peers) != 1:
		push_error("Expected client peer 2 to map to player index 1")
		return 1
	if NetworkManagerScript.compute_player_index_for_peers(3, peers) != 2:
		push_error("Expected client peer 3 to map to player index 2")
		return 1
	return 0


func _test_collect_lobby_peer_ids() -> int:
	var host_only := NetworkManagerScript.collect_lobby_peer_ids(1, [])
	if host_only != [1]:
		push_error("Expected host-only lobby to contain peer 1")
		return 1

	var host_and_client := NetworkManagerScript.collect_lobby_peer_ids(1, [2])
	if host_and_client != [1, 2]:
		push_error("Expected lobby roster [1, 2] for host with one client")
		return 1

	var client_view := NetworkManagerScript.collect_lobby_peer_ids(2, [])
	if client_view != [1, 2]:
		push_error("Expected joining client roster [1, 2]")
		return 1
	return 0


func _test_client_player_index_from_lobby_roster() -> int:
	var client_roster := NetworkManagerScript.collect_lobby_peer_ids(2, [])
	if NetworkManagerScript.compute_player_index_for_peers(2, []) != -1:
		push_error("Expected empty peer list to miss client peer id 2")
		return 1
	if client_roster.find(2) != 1:
		push_error("Expected client peer id 2 to be player index 1 in lobby roster")
		return 1
	return 0


func _test_format_lobby_player_label() -> int:
	var peers: Array = [2, 3]
	if NetworkManagerScript.format_lobby_player_label(1, 1, peers) != "Host (You)":
		push_error("Expected host self label")
		return 1
	if NetworkManagerScript.format_lobby_player_label(2, 1, peers) != "Player 2":
		push_error("Expected client label for peer 2")
		return 1
	if NetworkManagerScript.format_lobby_player_label(2, 2, peers) != "Player 2 (You)":
		push_error("Expected client self label for peer 2")
		return 1
	return 0


func _test_disconnect_session_delegates_to_transport() -> int:
	var manager := NetworkManagerScript.new()
	var fake := _FakeTransport.new()
	manager.transport = fake
	manager.is_session_active = true

	manager.disconnect_session()

	if manager.is_session_active:
		push_error("Expected disconnect_session to clear session flag")
		return 1
	if fake.disconnect_calls != 1:
		push_error("Expected disconnect_session to delegate to transport")
		return 1
	return 0


func _test_normalize_lobby_roles() -> int:
	var normalized := LobbyMatchStateScript.normalize_roles({
		"1": GameStateScript.PlayerRole.HEADMASTER,
		2: GameStateScript.PlayerRole.APPRENTICE,
	})
	if int(normalized[1]) != GameStateScript.PlayerRole.HEADMASTER:
		push_error("Expected normalized roles to coerce string keys to int")
		return 1
	if int(normalized[2]) != GameStateScript.PlayerRole.APPRENTICE:
		push_error("Expected normalized roles to preserve int keys")
		return 1
	return 0


func _test_pack_roles_for_peers() -> int:
	var roles := {
		1: GameStateScript.PlayerRole.HEADMASTER,
		2: GameStateScript.PlayerRole.APPRENTICE,
		99: GameStateScript.PlayerRole.APPRENTICE,
	}
	var peers: Array[int] = [1, 2]
	var packed := LobbyMatchStateScript.pack_roles_for_peers(roles, peers)
	if packed.size() != 2:
		push_error("Expected packed roles to include only connected peers")
		return 1
	if int(packed[1]) != GameStateScript.PlayerRole.HEADMASTER:
		push_error("Expected packed roles to include Headmaster for peer 1")
		return 1
	return 0


class _FakeTransport extends MultiplayerTransportScript:
	var disconnect_calls := 0

	func disconnect_session() -> void:
		disconnect_calls += 1
