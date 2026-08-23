class_name WizardChallengeHeightSync
extends RefCounted

## Host-authoritative "race to the top" state transitions for multiplayer sync.
## Mirrors DeliveryObjectiveSync's request/broadcast shape but there is only
## one meaningful action: the first in-range interact at the statue wins.

enum Phase {
	ACTIVE = 0,
	COMPLETE = 1,
}

enum NetworkOp {
	REQUEST_WIN,
	BROADCAST_STATE,
}


static func pack_snapshot(phase: int, winner_peer_id: int) -> Dictionary:
	return {
		"phase": phase,
		"winner_peer_id": winner_peer_id,
	}


static func unpack_snapshot(data: Dictionary) -> Dictionary:
	return {
		"phase": int(data.get("phase", Phase.ACTIVE)),
		"winner_peer_id": int(data.get("winner_peer_id", -1)),
	}


static func _in_range_xz(a: Vector3, b: Vector3, range_sq: float) -> bool:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz <= range_sq


## Returns {} if the win request is rejected (already complete / out of range),
## otherwise the new {phase, winner_peer_id} snapshot to broadcast.
static func apply_host_win(
	phase: int,
	actor_peer_id: int,
	player_pos: Vector3,
	statue_pos: Vector3,
	interact_range_sq: float
) -> Dictionary:
	if phase != Phase.ACTIVE:
		return {}
	if not _in_range_xz(player_pos, statue_pos, interact_range_sq):
		return {}
	return {
		"phase": Phase.COMPLETE,
		"winner_peer_id": actor_peer_id,
	}
