class_name DeliveryObjectiveState
extends RefCounted

## Pure pickup / deliver state for unit tests.

enum Phase {
	SEEK_ITEM,
	CARRIED,
	COMPLETE,
}

const QUEST_HINT := "Find the relic, and deliver it to the drop off location"

var phase: Phase = Phase.SEEK_ITEM
var carrier: Node = null


func try_pickup(player: Node, player_pos: Vector3, item_pos: Vector3, range_sq: float) -> bool:
	if phase != Phase.SEEK_ITEM:
		return false
	var dx := player_pos.x - item_pos.x
	var dz := player_pos.z - item_pos.z
	if dx * dx + dz * dz > range_sq:
		return false
	phase = Phase.CARRIED
	carrier = player
	return true


func try_deliver(player: Node, player_pos: Vector3, turn_in_pos: Vector3, range_sq: float) -> bool:
	if phase != Phase.CARRIED or carrier != player:
		return false
	var dx := player_pos.x - turn_in_pos.x
	var dz := player_pos.z - turn_in_pos.z
	if dx * dx + dz * dz > range_sq:
		return false
	phase = Phase.COMPLETE
	carrier = null
	return true


func try_drop(player: Node, _drop_pos: Vector3) -> bool:
	if phase != Phase.CARRIED or carrier != player:
		return false
	phase = Phase.SEEK_ITEM
	carrier = null
	return true


func get_status_lines() -> PackedStringArray:
	match phase:
		Phase.SEEK_ITEM, Phase.CARRIED:
			return PackedStringArray([QUEST_HINT])
		Phase.COMPLETE:
			return PackedStringArray(["Objective complete!"])
	return PackedStringArray()
