class_name CloudState
extends RefCounted

## Immutable description of a single low-poly cloud.
## Position is computed deterministically from elapsed match time.

var index: int = 0
var base_position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var radius: float = 1.0
## Index into CloudSystem's fixed mesh pool.
var mesh_index: int = 0
var arc_amplitude: float = 0.0
var arc_wavelength: float = 1.0
var arc_phase: float = 0.0


func position_at(elapsed_sec: float, bounds_min: Vector3, bounds_max: Vector3) -> Vector3:
	var dx := velocity.x * elapsed_sec
	var dz := velocity.z * elapsed_sec
	var distance := Vector2(dx, dz).length()
	var arc_y := arc_amplitude * sin((distance / arc_wavelength) * TAU + arc_phase)

	var size_x := bounds_max.x - bounds_min.x
	var size_z := bounds_max.z - bounds_min.z
	var y := clampf(
		base_position.y + arc_y,
		bounds_min.y,
		bounds_max.y
	)
	return Vector3(
		_wrap(base_position.x + dx, bounds_min.x, size_x),
		y,
		_wrap(base_position.z + dz, bounds_min.z, size_z)
	)


func _wrap(value: float, min_value: float, size: float) -> float:
	if size <= 0.0:
		return min_value
	var offset := fposmod(value - min_value, size)
	return min_value + offset
