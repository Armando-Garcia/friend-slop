class_name ChargerCharge
extends RefCounted

## Lock-on telegraph → locked ram → wall stun. Shared by charger.tscn lookdev,
## monster workspace, and the match. Pose-only previews never auto-stun.

enum Phase { IDLE, TELEGRAPH, CHARGE, WALL_STUN }

const CHARGE_SPEED_MULT := 2.3
const DEFAULT_TELEGRAPH_SEC := 1.2
const DEFAULT_WALL_STUN_SEC := 3.0
const WALL_GRACE_SEC := 0.35
const HEAD_READY_RAD := 0.05
const WALL_UP_DOT := 0.45
const WARD_GROUP := &"spell_ward"


var phase: Phase = Phase.IDLE
var age: float = 0.0
var pose_only: bool = false
var locked_dir: Vector3 = Vector3.FORWARD


func reset() -> void:
	phase = Phase.IDLE
	age = 0.0
	pose_only = false
	locked_dir = Vector3.FORWARD


func begin_telegraph() -> void:
	phase = Phase.TELEGRAPH
	age = 0.0


func begin_charge(dir: Vector3) -> void:
	phase = Phase.CHARGE
	age = 0.0
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		locked_dir = Vector3.FORWARD
	else:
		locked_dir = flat.normalized()


func begin_wall_stun() -> void:
	phase = Phase.WALL_STUN
	age = 0.0


func tick(delta: float) -> void:
	age += maxf(delta, 0.0)


func telegraph_progress(duration_sec: float) -> float:
	return clampf(age / maxf(duration_sec, 0.05), 0.0, 1.0)


func telegraph_ready(duration_sec: float, head_pitch: float, plunge_pitch: float) -> bool:
	if telegraph_progress(duration_sec) < 1.0:
		return false
	return absf(head_pitch - plunge_pitch) <= HEAD_READY_RAD


func wall_stun_ready(duration_sec: float) -> bool:
	return age + 0.0001 >= maxf(duration_sec, 0.05)


func can_read_walls() -> bool:
	return not pose_only and phase == Phase.CHARGE and age >= WALL_GRACE_SEC


func charge_velocity(speed: float) -> Vector3:
	var spd := maxf(speed, 0.0)
	return Vector3(locked_dir.x * spd, 0.0, locked_dir.z * spd)


static func charge_speed(sprint_speed: float) -> float:
	return maxf(0.0, sprint_speed) * CHARGE_SPEED_MULT


static func is_wall_collider(collider: Object, normal: Vector3) -> bool:
	if collider == null:
		return false
	if collider is Node and _is_ignored_wall_node(collider as Node):
		return false
	return normal.y < WALL_UP_DOT


static func collect_wall_excludes(body: CollisionObject3D, ward: Node) -> Array:
	var out: Array = []
	if body != null:
		out.append(body.get_rid())
	_collect_body_rids(ward, out)
	return out


static func _is_ignored_wall_node(node: Node) -> bool:
	var n := node
	while n != null:
		if n.is_in_group("player") or n.is_in_group("monster") or n.is_in_group(WARD_GROUP):
			return true
		if n is CharacterBody3D:
			return true
		var name_s := str(n.name).to_lower()
		if name_s == "floor" or name_s.begins_with("floor"):
			return true
		n = n.get_parent()
	return false


static func _collect_body_rids(node: Node, out: Array) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is CollisionObject3D:
		out.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		if child is Node:
			_collect_body_rids(child as Node, out)
