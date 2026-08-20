class_name TestSimpleVoiceChatPeers
extends RefCounted

const SimpleVoiceChatScript := preload("res://scripts/voice/simple_voice_chat.gd")


func run() -> int:
	var failures := 0
	failures += _test_set_peers_filters_local_and_zero()
	failures += _test_set_peers_replaces_list()
	return failures


func _test_set_peers_filters_local_and_zero() -> int:
	var chat: Node = SimpleVoiceChatScript.new()
	chat.set("_local_steam_id", 111)
	var incoming: Array[int] = [0, 111, 222, 222, 333]
	chat.call("set_peers", incoming)
	var peers: Array = chat.call("get_peers")
	if peers.size() != 2 or int(peers[0]) != 222 or int(peers[1]) != 333:
		push_error("set_peers must drop 0/local and keep unique remotes, got %s" % str(peers))
		chat.free()
		return 1
	chat.free()
	return 0


func _test_set_peers_replaces_list() -> int:
	var chat: Node = SimpleVoiceChatScript.new()
	chat.set("_local_steam_id", 1)
	var first: Array[int] = [10, 20]
	var second: Array[int] = [30]
	chat.call("set_peers", first)
	chat.call("set_peers", second)
	var peers: Array = chat.call("get_peers")
	if peers.size() != 1 or int(peers[0]) != 30:
		push_error("set_peers must replace the peer list, got %s" % str(peers))
		chat.free()
		return 1
	chat.free()
	return 0
