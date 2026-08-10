class_name SummonHost
extends Node

## Tracks host-linked summons. Scene-tree entrypoint under a Monster (or future player).

signal summons_changed

@export var max_summons: int = 3
@export var default_leash_radius: float = 10.0

var _summons: Array[Node] = []
var _pending_spawns: int = 0


func can_spawn() -> bool:
	_prune()
	return (_summons.size() + _pending_spawns) < max_summons


func summon_count() -> int:
	_prune()
	return _summons.size()


func begin_pending_spawn() -> void:
	_pending_spawns += 1


func complete_pending_spawn() -> void:
	_pending_spawns = maxi(0, _pending_spawns - 1)


func register_summon(summon: Node) -> void:
	if summon == null:
		return
	_prune()
	if _summons.has(summon):
		return
	_summons.append(summon)
	if not summon.tree_exiting.is_connected(_on_summon_exiting):
		summon.tree_exiting.connect(_on_summon_exiting.bind(summon))
	summons_changed.emit()


func unregister_summon(summon: Node) -> void:
	if summon == null:
		return
	_summons.erase(summon)
	summons_changed.emit()


func kill_all() -> void:
	_prune()
	var snapshot := _summons.duplicate()
	_summons.clear()
	for summon in snapshot:
		if summon == null or not is_instance_valid(summon):
			continue
		if summon.has_method("die"):
			summon.call("die")
		elif summon.is_inside_tree():
			summon.queue_free()
	summons_changed.emit()


func command_attack(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_prune()
	for summon in _summons:
		if summon == null or not is_instance_valid(summon):
			continue
		if summon.has_method("set_forced_hunt"):
			summon.call("set_forced_hunt", target, true)


func command_investigate(world_position: Vector3) -> void:
	_prune()
	for summon in _summons:
		if summon == null or not is_instance_valid(summon):
			continue
		if summon.has_method("set_forced_investigate"):
			summon.call("set_forced_investigate", world_position, true)


func append_relayed_interests(out: Array) -> void:
	_prune()
	for summon in _summons:
		if summon == null or not is_instance_valid(summon):
			continue
		if summon.has_method("get_relayed_player_interest"):
			var interest = summon.call("get_relayed_player_interest")
			if interest != null:
				out.append(interest)


func _prune() -> void:
	var kept: Array[Node] = []
	for summon in _summons:
		if summon != null and is_instance_valid(summon) and summon.is_inside_tree():
			kept.append(summon)
	_summons = kept


func _on_summon_exiting(summon: Node) -> void:
	_summons.erase(summon)
	summons_changed.emit()
