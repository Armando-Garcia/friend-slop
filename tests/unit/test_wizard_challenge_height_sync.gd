class_name TestWizardChallengeHeightSync
extends RefCounted

const SyncScript := preload("res://scripts/objectives/wizard_challenge_height_sync.gd")

const INTERACT_RANGE_SQ := 1.8 * 1.8


func run() -> int:
	var failures := 0
	failures += _test_snapshot_round_trip()
	failures += _test_host_win_in_range()
	failures += _test_host_win_rejects_out_of_range()
	failures += _test_host_win_rejects_when_already_complete()
	return failures


func _test_snapshot_round_trip() -> int:
	var packed := SyncScript.pack_snapshot(SyncScript.Phase.COMPLETE, 3)
	var unpacked := SyncScript.unpack_snapshot(packed)
	if int(unpacked.get("phase", -1)) != SyncScript.Phase.COMPLETE:
		push_error("Expected complete phase in unpacked snapshot")
		return 1
	if int(unpacked.get("winner_peer_id", -1)) != 3:
		push_error("Expected winner peer id in unpacked snapshot")
		return 1
	return 0


func _test_host_win_in_range() -> int:
	var statue_pos := Vector3(4.0, 0.0, 0.0)
	var result := SyncScript.apply_host_win(
		SyncScript.Phase.ACTIVE,
		2,
		statue_pos,
		statue_pos,
		INTERACT_RANGE_SQ
	)
	if result.is_empty() or int(result.get("phase", -1)) != SyncScript.Phase.COMPLETE:
		push_error("Expected an in-range host win to complete the challenge")
		return 1
	if int(result.get("winner_peer_id", -1)) != 2:
		push_error("Expected the acting peer to be recorded as winner")
		return 1
	return 0


func _test_host_win_rejects_out_of_range() -> int:
	var result := SyncScript.apply_host_win(
		SyncScript.Phase.ACTIVE,
		2,
		Vector3(50.0, 0.0, 0.0),
		Vector3.ZERO,
		INTERACT_RANGE_SQ
	)
	if not result.is_empty():
		push_error("Expected an out-of-range host win attempt to be rejected")
		return 1
	return 0


func _test_host_win_rejects_when_already_complete() -> int:
	var result := SyncScript.apply_host_win(
		SyncScript.Phase.COMPLETE,
		2,
		Vector3.ZERO,
		Vector3.ZERO,
		INTERACT_RANGE_SQ
	)
	if not result.is_empty():
		push_error("Expected a host win attempt after completion to be rejected")
		return 1
	return 0
