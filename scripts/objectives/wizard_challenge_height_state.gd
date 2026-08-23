class_name WizardChallengeHeightState
extends RefCounted

## Pure race-to-the-top state for unit tests. First player to reach the
## summit statue and interact wins the challenge for the whole match.

enum Phase {
	ACTIVE,
	COMPLETE,
}

const QUEST_HINT := "Race to the top of the tower and press the button at the statue"

var phase: Phase = Phase.ACTIVE
var winner: Node = null


func try_win(player: Node, player_pos: Vector3, statue_pos: Vector3, range_sq: float) -> bool:
	if phase != Phase.ACTIVE:
		return false
	var dx := player_pos.x - statue_pos.x
	var dz := player_pos.z - statue_pos.z
	if dx * dx + dz * dz > range_sq:
		return false
	phase = Phase.COMPLETE
	winner = player
	return true


func get_status_lines() -> PackedStringArray:
	match phase:
		Phase.ACTIVE:
			return PackedStringArray([QUEST_HINT])
		Phase.COMPLETE:
			return PackedStringArray(["Wizard's challenge complete!"])
	return PackedStringArray()
