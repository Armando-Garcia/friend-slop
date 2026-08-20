class_name DeliveryObjectiveSync
extends RefCounted

## Host-authoritative relic state transitions for multiplayer sync.

enum Action {
	PICKUP,
	DROP,
	DELIVER,
}

enum Phase {
	SEEK_ITEM = 0,
	CARRIED = 1,
	COMPLETE = 2,
}

enum NetworkOp {
	REQUEST_INTERACT,
	BROADCAST_STATE,
	BROADCAST_PING,
}


static func pack_snapshot(
	phase: int,
	carrier_peer_id: int,
	item_world_pos: Vector3
) -> Dictionary:
	return {
		"phase": phase,
		"carrier_peer_id": carrier_peer_id,
		"item_x": item_world_pos.x,
		"item_y": item_world_pos.y,
		"item_z": item_world_pos.z,
	}


static func unpack_snapshot(data: Dictionary) -> Dictionary:
	return {
		"phase": int(data.get("phase", Phase.SEEK_ITEM)),
		"carrier_peer_id": int(data.get("carrier_peer_id", -1)),
		"item_world_pos": Vector3(
			float(data.get("item_x", 0.0)),
			float(data.get("item_y", 0.0)),
			float(data.get("item_z", 0.0))
		),
	}


static func _in_range_xz(a: Vector3, b: Vector3, range_sq: float) -> bool:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz <= range_sq


static func apply_host_action(
	action: int,
	phase: int,
	carrier_peer_id: int,
	actor_peer_id: int,
	player_pos: Vector3,
	item_world_pos: Vector3,
	turn_in_pos: Vector3,
	interact_range_sq: float,
	float_height: float
) -> Dictionary:
	match action:
		Action.PICKUP:
			if phase != Phase.SEEK_ITEM:
				return {}
			if not _in_range_xz(player_pos, item_world_pos, interact_range_sq):
				return {}
			return {
				"phase": Phase.CARRIED,
				"carrier_peer_id": actor_peer_id,
				"item_world_pos": item_world_pos,
			}
		Action.DROP:
			if phase != Phase.CARRIED or carrier_peer_id != actor_peer_id:
				return {}
			var drop_pos := player_pos
			drop_pos.y = float_height
			return {
				"phase": Phase.SEEK_ITEM,
				"carrier_peer_id": -1,
				"item_world_pos": drop_pos,
			}
		Action.DELIVER:
			if phase != Phase.CARRIED or carrier_peer_id != actor_peer_id:
				return {}
			if not _in_range_xz(player_pos, turn_in_pos, interact_range_sq):
				return {}
			return {
				"phase": Phase.COMPLETE,
				"carrier_peer_id": -1,
				"item_world_pos": item_world_pos,
			}
	return {}


static func resolve_interact_action(
	phase: int,
	carrier_peer_id: int,
	actor_peer_id: int,
	player_pos: Vector3,
	item_world_pos: Vector3,
	turn_in_pos: Vector3,
	interact_range_sq: float
) -> int:
	match phase:
		Phase.SEEK_ITEM:
			if _in_range_xz(player_pos, item_world_pos, interact_range_sq):
				return Action.PICKUP
		Phase.CARRIED:
			if carrier_peer_id != actor_peer_id:
				return -1
			if _in_range_xz(player_pos, turn_in_pos, interact_range_sq):
				return Action.DELIVER
			return Action.DROP
	return -1
