@tool
class_name EmberWretch
extends Monster

## Ember variant: charge-hold-release caster combat with halo→dash→lob combo.

const MonsterComboStepScript := preload("res://scripts/monsters/monster_combo_step.gd")
const MonsterComboTriggersScript := preload("res://scripts/monsters/monster_combo_triggers.gd")
const DASH_ABILITY_ID := &"ember_dash"

const COMBO_TRIGGER_RANGE := 8.0
const RETREAT_COMBO_CHANCE := 0.7
const DAMAGE_COMBO_CHANCE := 0.7
const LOW_HP_COMBO_RATIO := 0.35

var _used_low_hp_combo: bool = false


func _ready() -> void:
	super._ready()
	_configure_caster_combo()


func _configure_caster_combo() -> void:
	var caster := get_node_or_null("CasterCombat")
	if caster == null or not caster.has_method("configure_combo"):
		return
	var steps: Array = []
	var halo := MonsterComboStepScript.new()
	halo.ability_id = "ember_halo"
	halo.step_type = MonsterComboStepScript.StepType.CHARGE_THROW
	steps.append(halo)
	var dash := MonsterComboStepScript.new()
	dash.ability_id = "ember_dash"
	dash.step_type = MonsterComboStepScript.StepType.INSTANT
	steps.append(dash)
	var lob := MonsterComboStepScript.new()
	lob.ability_id = "ember_lob"
	lob.step_type = MonsterComboStepScript.StepType.CHARGE_THROW
	steps.append(lob)
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
	var ratio_before := get_health_ratio()
	super.take_damage(amount, from)
	if not is_alive:
		return
	var dash := _get_dash_ability()
	if dash != null:
		if (
			ratio_before >= LOW_HP_COMBO_RATIO
			and get_health_ratio() < LOW_HP_COMBO_RATIO
		):
			dash.reset_cooldown()
	_try_ember_combo_triggers(from, ratio_before)


func _try_ember_combo_triggers(from: Node3D, ratio_before: float) -> void:
	var caster := get_node_or_null("CasterCombat")
	if caster == null or not caster.has_method("try_trigger_combo"):
		return
	var player := MonsterComboTriggersScript.resolve_attacking_player(from, self)
	if player == null:
		return
	if MonsterComboTriggersScript.is_player_within_range(self, player, COMBO_TRIGGER_RANGE):
		caster.call("try_trigger_combo", player, DAMAGE_COMBO_CHANCE)
	if (
		not _used_low_hp_combo
		and ratio_before >= LOW_HP_COMBO_RATIO
		and get_health_ratio() < LOW_HP_COMBO_RATIO
	):
		_used_low_hp_combo = true
		caster.call("try_trigger_combo", player, 1.0)


func is_chase_retreating() -> bool:
	var dash := _get_dash_ability()
	if dash != null and dash.is_dashing():
		return true
	return super.is_chase_retreating()


func _get_dash_ability() -> Node:
	return get_node_or_null("Abilities/EmberDash")
