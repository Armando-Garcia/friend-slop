extends RefCounted

const MonsterCasterCombatScript := preload(
	"res://scripts/monsters/monster_caster_combat.gd"
)
const MonsterComboStepScript := preload("res://scripts/monsters/monster_combo_step.gd")
const AshWretchScript := preload("res://scripts/monsters/ash_wretch.gd")
const EmberWretchScript := preload("res://scripts/monsters/ember_wretch.gd")
const AshIceAbilityScript := preload("res://scripts/monsters/abilities/ash_ice_ability.gd")
const AshFrostBreathFlightScript := preload(
	"res://scripts/monsters/abilities/ash_frost_breath_flight.gd"
)


func run() -> int:
	var failures := 0
	failures += _test_standing_still_gate()
	failures += _test_ash_combo_step_shape()
	failures += _test_ember_combo_step_shape()
	failures += _test_combo_trigger_constants()
	failures += _test_combo_cooldown_reset()
	return failures


func _test_standing_still_gate() -> int:
	if not MonsterCasterCombatScript.is_standing_still_velocity(Vector2.ZERO):
		push_error("Expected zero velocity to count as standing still")
		return 1
	if MonsterCasterCombatScript.is_standing_still_velocity(Vector2(0.2, 0.0)):
		push_error("Expected fast velocity to block charging")
		return 1
	if not MonsterCasterCombatScript.is_standing_still_velocity(Vector2(0.04, 0.04)):
		push_error("Expected slow drift to count as standing still")
		return 1
	return 0


func _test_ash_combo_step_shape() -> int:
	var close := AshWretchScript.build_close_combo_steps()
	var far := AshWretchScript.build_far_combo_steps()
	var at_five := AshWretchScript.build_combo_steps_for_distance(5.0)
	var beyond := AshWretchScript.build_combo_steps_for_distance(5.01)
	var close_ok: bool = (
		close.size() == 4
		and str(close[0].ability_id) == "ash_ward"
		and close[0].step_type == MonsterComboStepScript.StepType.INSTANT
		and str(close[1].ability_id) == "ash_frost_breath"
		and is_equal_approx(
			close[1].delay_after_prev_sec, AshFrostBreathFlightScript.COMBO_WARD_DELAY_SEC
		)
		and str(close[2].ability_id) == "ash_retreat_dash"
		and str(close[2].combo_variant) == "away"
		and is_equal_approx(
			close[2].delay_after_prev_sec, AshFrostBreathFlightScript.COMBO_AFTER_CLOUD_DELAY_SEC
		)
		and str(close[3].ability_id) == "ash_ice"
		and close[3].step_type == MonsterComboStepScript.StepType.INSTANT
	)
	var far_ok: bool = (
		far.size() == 4
		and str(far[0].ability_id) == "ash_retreat_dash"
		and str(far[0].combo_variant) == "close"
		and str(far[1].ability_id) == "ash_frost_breath"
		and is_equal_approx(
			far[1].delay_after_prev_sec, AshFrostBreathFlightScript.COMBO_WARD_DELAY_SEC
		)
		and str(far[2].ability_id) == "ash_retreat_dash"
		and str(far[2].combo_variant) == "away"
		and is_equal_approx(
			far[2].delay_after_prev_sec, AshFrostBreathFlightScript.COMBO_AFTER_CLOUD_DELAY_SEC
		)
		and str(far[3].ability_id) == "ash_ice"
		and far[3].step_type == MonsterComboStepScript.StepType.INSTANT
		and AshIceAbilityScript.COMBO_BURST_COUNT == 2
	)
	var split_ok: bool = (
		str(at_five[0].ability_id) == "ash_ward"
		and str(beyond[0].ability_id) == "ash_retreat_dash"
	)
	if not close_ok:
		push_error("Ash close combo step shape mismatch")
		return 1
	if not far_ok:
		push_error("Ash far combo step shape mismatch")
		return 1
	if not split_ok:
		push_error("Expected close combo at 5 m and far combo beyond 5 m")
		return 1
	return 0


func _test_ember_combo_step_shape() -> int:
	var steps := _build_ember_combo_steps()
	if steps.size() != 3:
		push_error("Expected 3 Ember combo steps, got %s" % steps.size())
		return 1
	if str(steps[0].ability_id) != "ember_halo":
		push_error("Expected Ember combo step 1 ember_halo")
		return 1
	if str(steps[1].ability_id) != "ember_dash":
		push_error("Expected Ember combo step 2 ember_dash")
		return 1
	if steps[1].step_type != MonsterComboStepScript.StepType.INSTANT:
		push_error("Expected Ember dash step INSTANT")
		return 1
	if str(steps[2].ability_id) != "ember_lob":
		push_error("Expected Ember combo step 3 ember_lob")
		return 1
	return 0


func _test_combo_trigger_constants() -> int:
	var ok := (
		is_equal_approx(AshWretchScript.WARD_BLOCK_COMBO_CHANCE, 0.5)
		and is_equal_approx(AshWretchScript.COMBO_SPLIT_RANGE, 5.0)
		and is_equal_approx(
			AshWretchScript.COMBO_TRIGGER_RANGE, AshFrostBreathFlightScript.MAX_TRAVEL_RANGE
		)
		and is_equal_approx(AshWretchScript.COMBO_LOCKOUT_SEC, 8.0)
		and is_equal_approx(EmberWretchScript.WARD_BLOCK_COMBO_CHANCE, 0.35)
		and is_equal_approx(EmberWretchScript.LOW_HP_COMBO_RATIO, 0.35)
		and is_equal_approx(EmberWretchScript.SIDESTEP_RANGE, 8.0)
		and is_equal_approx(EmberWretchScript.STRAFE_FURTHER_WEIGHT, 0.7)
	)
	if not ok:
		push_error("Combo trigger constants mismatch")
		return 1
	return 0


func _test_combo_cooldown_reset() -> int:
	var ice := AshIceAbilityScript.new()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("Expected a SceneTree for combo cooldown reset")
		return 1
	tree.root.add_child(ice)
	ice.begin_cooldown()
	ice._burst_active = true
	ice.reset_for_combo()
	var ready := ice.can_cast()
	ice.queue_free()
	if not ready:
		push_error("Expected Ash ice reset_for_combo to clear cooldown and burst lock")
		return 1
	return 0


func _build_ember_combo_steps() -> Array:
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
	return steps
