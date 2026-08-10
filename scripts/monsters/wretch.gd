@tool
class_name Wretch
extends Monster

## Pack master: weak eyes, moderate ears, shares rat sight, rituals when a player is known.

const HEARING_SOURCE := &"hearing"
const PLAYER_LOCK_SOURCE := &"player_lock"
const SUMMON_SIGHT_SOURCE := &"summon_sight"
const PLAYER_LOCK_URGENCY := 2.1
const COMMAND_ABILITY_ID := "command_pack"
## Alert hearing extends beyond chase hearing (outer ring only → alert).
const ALERT_HEAR_RANGE_MULT := 1.33
const RitualPoseScript := preload("res://scripts/monsters/wretch_ritual_pose.gd")

@export var ambient_summon_cooldown_sec: float = 20.0
@export var chase_summon_cooldown_sec: float = 5.33
## Keep a spotted player locked long enough to finish Command Pack windup.
@export_range(1.0, 12.0, 0.25) var player_lock_sec: float = 5.0
## Base yaw turn rate (rad/s). Hearing turns use half of this.
@export_range(0.5, 12.0, 0.1) var face_turn_speed_rad: float = 4.0

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
	if _ritual == null:
		return
	if lookdev_override and lookdev_pose == MonsterAIScript.LookdevPose.CHASE:
		if _ritual.has_method("set_ritual_phase"):
			_ritual.call("set_ritual_phase", RitualPoseScript.RitualPhase.CHASE)
		elif _ritual.has_method("set_active"):
			_ritual.call("set_active", true)
	elif _ritual.has_method("set_ritual_phase"):
		_ritual.call("set_ritual_phase", RitualPoseScript.RitualPhase.OFF)
	elif _ritual.has_method("set_active"):
		_ritual.call("set_active", false)


func is_ai_chasing() -> bool:
	return _ai_state == MonsterAIScript.State.CHASE


func get_summon_cooldown_sec() -> float:
	## Alert uses animation-gated casting in SummonRats.begin_cooldown.
	if is_ai_alert():
		return 0.0
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
	_tick_alert_hearing()
	_direct_rats_from_interest()
	_update_ritual_pose()


func _prefer_interest(candidates: Array) -> RefCounted:
	## Rat vision of a player outranks ambient hearing for host chase.
	var best_summon: RefCounted = null
	var best_summon_u := 0.0
	for item in candidates:
		if item == null:
			continue
		if str(item.get("source")) != String(SUMMON_SIGHT_SOURCE):
			continue
		if not item.has_method("is_actionable") or not bool(item.call("is_actionable")):
			continue
		var urgency := float(item.get("urgency"))
		if best_summon == null or urgency > best_summon_u:
			best_summon = item
			best_summon_u = urgency
	if best_summon != null:
		return best_summon
	return super._prefer_interest(candidates)


func _tick_alert_hearing() -> void:
	## Outer hearing ring (chase hear * 1.33) raises alert without forcing chase.
	if is_ai_chasing():
		return
	if not _has_alert_band_hearing():
		return
	if is_ai_alert():
		## Keep alert fresh while the outer-band noise continues.
		_alert_timer = 0.0
	else:
		_enter_alert()


func _chase_hear_range() -> float:
	var hearing := get_node_or_null("Senses/Hearing")
	if hearing != null and "hear_range" in hearing:
		return float(hearing.get("hear_range"))
	return 10.0


func _alert_hear_range() -> float:
	return _chase_hear_range() * ALERT_HEAR_RANGE_MULT


func _has_alert_band_hearing() -> bool:
	var chase_r := _chase_hear_range()
	var alert_r := _alert_hear_range()
	var hearing := get_node_or_null("Senses/Hearing")
	if hearing != null and bool(hearing.get("has_last_heard")):
		var heard_pos: Vector3 = hearing.get("last_heard_position") as Vector3
		if _distance_in_band(heard_pos, chase_r, alert_r):
			return true
	var tree := get_tree()
	if tree == null:
		return false
	var hub := tree.root.get_node_or_null("SteamProximityVoiceHub")
	for node in tree.get_nodes_in_group("player"):
		if not (node is Node3D):
			continue
		var player := node as Node3D
		if not _player_is_speaking(hub, player):
			continue
		if _distance_in_band(player.global_position, chase_r, alert_r):
			return true
	return false


func _distance_in_band(world_position: Vector3, inner_r: float, outer_r: float) -> bool:
	var flat := Vector3(
		world_position.x - global_position.x,
		0.0,
		world_position.z - global_position.z
	)
	var dist := flat.length()
	return dist > inner_r and dist <= outer_r


func _player_is_speaking(hub: Node, player: Node3D) -> bool:
	if hub == null or not hub.has_method("is_peer_speaking"):
		return false
	var peer_id := 0
	if player.has_method("get_multiplayer_authority"):
		peer_id = int(player.get_multiplayer_authority())
	if peer_id <= 0:
		return false
	return bool(hub.call("is_peer_speaking", peer_id))


func _pick_ready_ability(target: Node3D) -> Node:
	## Alert: keep casting Summon Rats until the pack is full (max 3).
	if is_ai_alert():
		var host := get_summon_host()
		if host != null and host.has_method("can_spawn") and bool(host.call("can_spawn")):
			for ability in get_combat_abilities():
				if str(ability.get("ability_id")) != "summon_rats":
					continue
				if ability.has_method("is_ready_to_cast"):
					if bool(ability.call("is_ready_to_cast", self, target)):
						return ability
				elif bool(ability.call("can_cast")):
					return ability
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
			_face_toward_hearing(toward, delta)
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


func _tick_chase(delta: float) -> void:
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
	## Hearing-only: face the sound slowly, stay put.
	if _interest != null and _interest.get("has_goal_position"):
		var goal: Vector3 = _interest.call("resolved_goal_position", global_position)
		var toward_sound := Vector3(
			goal.x - global_position.x,
			0.0,
			goal.z - global_position.z
		)
		_face_toward_hearing(toward_sound, delta)


func _tick_alert(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	var hear_goal = _hearing_face_goal()
	if hear_goal is Vector3:
		var goal: Vector3 = hear_goal as Vector3
		var toward := Vector3(
			goal.x - global_position.x,
			0.0,
			goal.z - global_position.z
		)
		_face_toward_hearing(toward, delta)


func _hearing_face_goal():
	## Prefer live hearing interest, then lingering last-heard point.
	if (
		_interest != null
		and str(_interest.get("source")) == String(HEARING_SOURCE)
		and bool(_interest.get("has_goal_position"))
	):
		return _interest.call("resolved_goal_position", global_position)
	var hearing := get_node_or_null("Senses/Hearing")
	if hearing != null and bool(hearing.get("has_last_heard")):
		return hearing.get("last_heard_position")
	return null


func _face_toward_hearing(desired: Vector3, delta: float) -> void:
	## Half the normal face turn rate when reacting to sound.
	_face_horizontal_at_speed(desired, delta, face_turn_speed_rad * 0.5)


func _face_horizontal_at_speed(desired: Vector3, delta: float, speed_rad: float) -> void:
	var flat := Vector3(desired.x, 0.0, desired.z)
	if flat.length_squared() < 0.0001:
		return
	var target_basis := Basis.looking_at(flat.normalized(), Vector3.UP)
	var target_yaw := target_basis.get_euler().y
	rotation.y = rotate_toward(rotation.y, target_yaw, maxf(speed_rad, 0.01) * delta)


func _direct_rats_from_interest() -> void:
	## Hearing no longer auto-sends rats — Command Pack orb handles investigate on arrival.
	if _ai_state != MonsterAIScript.State.CHASE:
		_last_rat_command_key = ""


func _update_ritual_pose() -> void:
	if _ritual == null:
		_ritual = get_node_or_null("Ritual")
	if _ritual == null:
		return
	var phase: int = RitualPoseScript.RitualPhase.OFF
	if (
		_casting_ability != null
		or (
			is_ai_chasing()
			and (is_locked_onto_player() or get_hearing_command_aim() is Vector3)
		)
	):
		phase = RitualPoseScript.RitualPhase.CHASE
	elif is_ai_alert():
		phase = RitualPoseScript.RitualPhase.ALERT
	if _ritual.has_method("set_ritual_phase"):
		_ritual.call("set_ritual_phase", phase)
	elif _ritual.has_method("set_active"):
		_ritual.call("set_active", phase != RitualPoseScript.RitualPhase.OFF)


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
