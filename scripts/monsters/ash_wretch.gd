@tool
class_name AshWretch
extends Monster

## Ash variant: charge-hold-release caster combat with ward→frost→ice combo.

const MonsterComboStepScript := preload("res://scripts/monsters/monster_combo_step.gd")
const MonsterComboTriggersScript := preload("res://scripts/monsters/monster_combo_triggers.gd")
const AshFrostBreathFlightScript := preload(
	"res://scripts/monsters/abilities/ash_frost_breath_flight.gd"
)
const LAST_AGGRO_SOURCE := &"last_aggro"
const LAST_AGGRO_URGENCY := 1.2

const COMBO_TRIGGER_RANGE := 8.0
const RETREAT_COMBO_CHANCE := 0.85
const DAMAGE_COMBO_CHANCE := 0.85

var _last_aggro_player_pos: Vector3 = Vector3.ZERO
var _has_last_aggro_player: bool = false


func _ready() -> void:
	super._ready()
	_configure_caster_combo()


func _configure_caster_combo() -> void:
	var caster := get_node_or_null("CasterCombat")
	if caster == null or not caster.has_method("configure_combo"):
		return
	var steps: Array = []
	var ward := MonsterComboStepScript.new()
	ward.ability_id = "ash_ward"
	ward.step_type = MonsterComboStepScript.StepType.INSTANT
	steps.append(ward)
	var frost := MonsterComboStepScript.new()
	frost.ability_id = "ash_frost_breath"
	frost.step_type = MonsterComboStepScript.StepType.INSTANT
	frost.delay_after_prev_sec = AshFrostBreathFlightScript.COMBO_WARD_DELAY_SEC
	steps.append(frost)
	var ice := MonsterComboStepScript.new()
	ice.ability_id = "ash_ice"
	ice.step_type = MonsterComboStepScript.StepType.CHARGE_THROW
	steps.append(ice)
	caster.call("configure_combo", steps)
	if caster.has_method("set"):
		caster.set("combo_trigger_max_range", COMBO_TRIGGER_RANGE)


func get_retreat_combo_chance(target: Node3D) -> float:
	var player := MonsterComboTriggersScript.resolve_attacking_player(target, self)
	if player == null:
		return -1.0
	if not MonsterComboTriggersScript.is_player_within_range(self, player, COMBO_TRIGGER_RANGE):
		return -1.0
	return RETREAT_COMBO_CHANCE


func take_damage(amount: float, from: Node3D = null) -> void:
	super.take_damage(amount, from)
	if not is_alive:
		return
	_try_damage_combo(from)


func _try_damage_combo(from: Node3D) -> void:
	var player := MonsterComboTriggersScript.resolve_attacking_player(from, self)
	if player == null:
		return
	if not MonsterComboTriggersScript.is_player_within_range(self, player, COMBO_TRIGGER_RANGE):
		return
	var caster := get_node_or_null("CasterCombat")
	if caster == null or not caster.has_method("try_trigger_combo"):
		return
	caster.call("try_trigger_combo", player, DAMAGE_COMBO_CHANCE)


func _gather_interest() -> RefCounted:
	_update_last_aggro_player()
	var interest := super._gather_interest()
	if _interest_is_actionable(interest):
		return interest
	if _ai_state == MonsterAIScript.State.CHASE and _has_last_aggro_player:
		return MonsterInterestScript.from_position(
			_last_aggro_player_pos, LAST_AGGRO_URGENCY, LAST_AGGRO_SOURCE
		)
	return interest


func get_aggro_player_target() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var players := tree.get_nodes_in_group("player")
	var positions: Array = []
	var alive_flags: Array = []
	var nodes: Array = []
	for node in players:
		if node is Node3D:
			var n3 := node as Node3D
			positions.append(n3.global_position)
			var alive_value = n3.get("is_alive")
			alive_flags.append(true if alive_value == null else bool(alive_value))
			nodes.append(n3)
	var idx: int = MonsterAIScript.pick_nearest_target_index(
		global_position, positions, alive_flags, chase_range
	)
	if idx < 0:
		return null
	return nodes[idx] as Node3D


func has_aggro_player() -> bool:
	return get_aggro_player_target() != null


func get_last_aggro_player_aim() -> Variant:
	if _has_last_aggro_player:
		return _last_aggro_player_pos
	return null


func _update_last_aggro_player() -> void:
	var target := get_aggro_player_target()
	if target == null:
		return
	_last_aggro_player_pos = target.global_position
	_has_last_aggro_player = true


func _move_toward_cast_range(target: Node3D, ability: Node) -> void:
	target = get_aggro_player_target() if get_aggro_player_target() != null else target
	if target == null:
		super._move_toward_cast_range(target, ability)
		return
	if not _should_turnaround_retreat(target, ability):
		super._move_toward_cast_range(target, ability)
		return
	if is_chase_retreating() or is_chase_moving():
		return
	var side := 1.0 if randf() < 0.5 else -1.0
	var duration := randf_range(chase_retreat_min_sec, chase_retreat_max_sec)
	start_chase_retreat(target, side, duration)


func _should_turnaround_retreat(target: Node3D, ability: Node) -> bool:
	var dist := MonsterAIScript.horizontal_distance(global_position, target.global_position)
	if dist <= COMBO_TRIGGER_RANGE:
		return true
	return _is_cast_band_too_close(target, ability)


func _is_cast_band_too_close(target: Node3D, ability: Node) -> bool:
	var min_r := float(ability.get("min_cast_range")) if "min_cast_range" in ability else 3.0
	var ideal := MonsterCombatSpacingScript.preferred_cast_ideal(ability)
	var dist := MonsterAIScript.horizontal_distance(global_position, target.global_position)
	return dist < min_r or dist < ideal - 0.45
