class_name MonsterInterest
extends RefCounted

## One candidate goal for Monster AI (chase / investigate / flee hint).
## Produced by default player targeting, senses, or subclass preferencing.

var target: Node3D = null
var goal_position: Vector3 = Vector3.ZERO
var has_goal_position: bool = false
## Higher wins in default _prefer_interest. 0 = ignore.
var urgency: float = 0.0
## Pathing / behavior hints for later brains (ignored by v1 movement).
var prefer_dark: bool = false
var avoid_light: bool = false
var source: StringName = &""


func is_actionable() -> bool:
	if urgency <= 0.0:
		return false
	if target != null and is_instance_valid(target):
		return true
	return has_goal_position


func resolved_goal_position(fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if target != null and is_instance_valid(target):
		return target.global_position
	if has_goal_position:
		return goal_position
	return fallback


static func from_target(
	p_target: Node3D,
	p_urgency: float,
	p_source: StringName = &""
) -> MonsterInterest:
	var interest := MonsterInterest.new()
	interest.target = p_target
	interest.urgency = p_urgency
	interest.source = p_source
	return interest


static func from_position(
	p_position: Vector3,
	p_urgency: float,
	p_source: StringName = &""
) -> MonsterInterest:
	var interest := MonsterInterest.new()
	interest.goal_position = p_position
	interest.has_goal_position = true
	interest.urgency = p_urgency
	interest.source = p_source
	return interest
