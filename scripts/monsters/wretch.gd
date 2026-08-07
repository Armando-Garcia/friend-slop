@tool
class_name Wretch
extends Monster

## Pack master: weak eyes, moderate ears, shares rat sight, rituals when a player is known.

const HEARING_SOURCE := &"hearing"
const PLAYER_LOCK_SOURCE := &"player_lock"
const PLAYER_LOCK_URGENCY := 2.1
const COMMAND_ABILITY_ID := "command_pack"

@export var ambient_summon_cooldown_sec: float = 20.0
@export var chase_summon_cooldown_sec: float = 8.0
## Keep a spotted player locked long enough to finish Command Pack windup.
@export_range(1.0, 12.0, 0.25) var player_lock_sec: float = 5.0

var _ritual: Node = null
var _last_rat_command_key: String = ""
var _locked_player: Node3D = null
var _player_lock_left: float = 0.0


func _ready() -> void:
	super._ready()
	_ritual = get_node_or_null("Ritual")
	## Sight/hearing + summons own aggro — do not use long proximity chase_range.
	chase_range = mini(chase_range, 3.0)
	_sync_lookdev_ritual()


func set_lookdev_pose(pose: MonsterAIScript.LookdevPose, enable_override: bool = true) -> void:
	super.set_lookdev_pose(pose, enable_override)
	_sync_lookdev_ritual()


func _sync_lookdev_ritual() -> void:
	if _ritual == null:
		_ritual = get_node_or_null("Ritual")
	if _ritual == null or not _ritual.has_method("set_active"):
		return
	var want := lookdev_override and lookdev_pose == MonsterAIScript.LookdevPose.CHASE
	_ritual.call("set_active", want)


func is_ai_chasing() -> bool:
	return _ai_state == MonsterAIScript.State.CHASE


func get_summon_cooldown_sec() -> float:
	if is_ai_chasing() and _interest_has_player_target(_interest):
		return chase_summon_cooldown_sec
	return ambient_summon_cooldown_sec


func get_locked_player_target() -> Node3D:
	## Sticky lock preferred; falls back to live interest.
	if _locked_player != null and is_instance_valid(_locked_player):
		return _locked_player
	if not _interest_has_player_target(_interest):
		return null
	return _interest.get("target") as Node3D


func is_locked_onto_player() -> bool:
	return get_locked_player_target() != null


func _append_default_interest_candidates(_out: Array) -> void:
	## Wretch uses Sight / Hearing / summon relay only — no wide proximity aggro.
	pass


func _gather_interest() -> RefCounted:
	var candidates: Array = []
	_append_sense_interest_candidates(candidates)
	var host := get_summon_host()
	if host != null and host.has_method("append_relayed_interests"):
		host.call("append_relayed_interests", candidates)
	_refresh_player_lock_from_candidates(candidates)
	if _locked_player != null and is_instance_valid(_locked_player):
		candidates.append(
			MonsterInterestScript.from_target(
				_locked_player, PLAYER_LOCK_URGENCY, PLAYER_LOCK_SOURCE
			)
		)
	return _prefer_interest(candidates)


func _physics_process(delta: float) -> void:
	_tick_player_lock(delta)
	super._physics_process(delta)
	if Engine.is_editor_hint() or not is_alive:
		return
	_direct_rats_from_interest()
	_update_ritual_pose()


func _pick_ready_ability(target: Node3D) -> Node:
	## Always try Command Pack first when a player is locked / spotted.
	if target != null and is_instance_valid(target) and target.is_in_group("player"):
		for ability in get_combat_abilities():
			if str(ability.get("ability_id")) != COMMAND_ABILITY_ID:
				continue
			if ability.has_method("is_ready_to_cast"):
				if bool(ability.call("is_ready_to_cast", self, target)):
					return ability
			elif bool(ability.call("can_cast")):
				return ability
	## Heard outside sight — fire Command Pack at the sound immediately.
	var hearing_aim = get_hearing_command_aim()
	if hearing_aim is Vector3:
		for ability in get_combat_abilities():
			if str(ability.get("ability_id")) != COMMAND_ABILITY_ID:
				continue
			if not bool(ability.call("can_cast")):
				continue
			if ability.has_method("set_pending_aim"):
				ability.call("set_pending_aim", hearing_aim as Vector3)
			return ability
	return super._pick_ready_ability(target)


func _try_start_cast(target: Node3D) -> bool:
	## Hearing casts have no player Node3D — still start Command Pack via pending aim.
	var hearing_aim = get_hearing_command_aim()
	if (
		(target == null or not is_instance_valid(target))
		and hearing_aim is Vector3
	):
		var cmd := _find_command_ability()
		if cmd != null and bool(cmd.call("can_cast")):
			if cmd.has_method("set_pending_aim"):
				cmd.call("set_pending_aim", hearing_aim as Vector3)
			_begin_ability_windup(cmd)
			## Faster reaction to sound than a full visual ritual charge.
			_cast_windup_left = minf(_cast_windup_left, 0.35)
			_tick_cast_windup(0.0, null)
			return true
	return super._try_start_cast(target)


func _tick_cast_windup(delta: float, target: Node3D) -> void:
	## Face the heard point while winding up a sound-aimed Command Pack.
	if target == null and _casting_ability != null:
		var hearing_aim = get_hearing_command_aim()
		if hearing_aim is Vector3:
			var aim: Vector3 = hearing_aim as Vector3
			var toward := Vector3(
				aim.x - global_position.x,
				0.0,
				aim.z - global_position.z
			)
			_face_horizontal(toward)
	## Allow Command Pack to finish without a player Node3D (uses pending aim).
	if (
		_casting_ability != null
		and str(_casting_ability.get("ability_id")) == COMMAND_ABILITY_ID
		and (target == null or not is_instance_valid(target))
	):
		velocity.x = 0.0
		velocity.z = 0.0
		_cast_windup_left -= delta
		if _cast_windup_left > 0.0:
			return
		var ability := _casting_ability
		_casting_ability = null
		_cast_windup_left = 0.0
		if ability != null and is_instance_valid(ability) and ability.has_method("begin_cast"):
			ability.call("begin_cast", self, null)
		return
	super._tick_cast_windup(delta, target)


func get_hearing_command_aim():
	## Sound aim only when not visually locked and the sound is outside sight range.
	if is_locked_onto_player():
		return null
	if _interest == null:
		return null
	if str(_interest.get("source")) != String(HEARING_SOURCE):
		return null
	if not bool(_interest.get("has_goal_position")):
		return null
	var goal: Vector3 = _interest.call("resolved_goal_position", global_position)
	var sight_r := _visual_sight_range()
	var flat := Vector3(
		goal.x - global_position.x,
		0.0,
		goal.z - global_position.z
	)
	if flat.length() <= sight_r:
		return null
	return goal


func _visual_sight_range() -> float:
	var sight := get_node_or_null("Senses/Sight")
	if sight != null and "sight_range" in sight:
		return float(sight.get("sight_range"))
	return 2.5


func _find_command_ability() -> Node:
	for ability in get_combat_abilities():
		if str(ability.get("ability_id")) == COMMAND_ABILITY_ID:
			return ability
	return null


func _begin_ability_windup(ability: Node) -> void:
	## Hold aggro through the full Command Pack ritual windup.
	if (
		ability != null
		and str(ability.get("ability_id")) == COMMAND_ABILITY_ID
		and _locked_player != null
		and is_instance_valid(_locked_player)
	):
		_player_lock_left = maxf(_player_lock_left, player_lock_sec)
	super._begin_ability_windup(ability)


func _tick_chase(_delta: float) -> void:
	## Packmaster stands still while directing rats / ritualizing.
	velocity.x = 0.0
	velocity.z = 0.0
	if _interest_has_player_target(_interest):
		var target: Node3D = _interest.get("target") as Node3D
		if target != null and is_instance_valid(target):
			var toward := Vector3(
				target.global_position.x - global_position.x,
				0.0,
				target.global_position.z - global_position.z
			)
			_face_horizontal(toward)
		return
	## Hearing-only: face the sound, stay put.
	if _interest != null and _interest.get("has_goal_position"):
		var goal: Vector3 = _interest.call("resolved_goal_position", global_position)
		var toward_sound := Vector3(
			goal.x - global_position.x,
			0.0,
			goal.z - global_position.z
		)
		_face_horizontal(toward_sound)


func _direct_rats_from_interest() -> void:
	## Hearing no longer auto-sends rats — Command Pack orb handles investigate on arrival.
	if _ai_state != MonsterAIScript.State.CHASE:
		_last_rat_command_key = ""


func _update_ritual_pose() -> void:
	var want := (
		(is_locked_onto_player() or get_hearing_command_aim() is Vector3)
		and (is_ai_chasing() or _casting_ability != null)
	)
	if _ritual != null and _ritual.has_method("set_active"):
		_ritual.call("set_active", want)


func _refresh_player_lock_from_candidates(candidates: Array) -> void:
	for item in candidates:
		if item == null:
			continue
		var target: Node3D = item.get("target") as Node3D
		if target == null or not is_instance_valid(target):
			continue
		if not target.is_in_group("player"):
			continue
		_locked_player = target
		_player_lock_left = player_lock_sec
		return


func _tick_player_lock(delta: float) -> void:
	if _locked_player == null:
		return
	if not is_instance_valid(_locked_player):
		_clear_player_lock()
		return
	var alive_value = _locked_player.get("is_alive")
	if alive_value != null and not bool(alive_value):
		_clear_player_lock()
		return
	## Keep lock alive while Command Pack is winding up / in flight setup.
	if (
		_casting_ability != null
		and str(_casting_ability.get("ability_id")) == COMMAND_ABILITY_ID
	):
		_player_lock_left = maxf(_player_lock_left, 0.75)
		return
	_player_lock_left = maxf(0.0, _player_lock_left - delta)
	if _player_lock_left <= 0.0:
		_clear_player_lock()


func _clear_player_lock() -> void:
	_locked_player = null
	_player_lock_left = 0.0


func _interest_has_player_target(interest: RefCounted) -> bool:
	if interest == null:
		return false
	var target: Node3D = interest.get("target") as Node3D
	if target == null or not is_instance_valid(target):
		return false
	return target.is_in_group("player")
