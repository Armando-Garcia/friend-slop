class_name PuzzleStepEntry
extends Resource

## One saved step in a WizardChallengeHeight jump-puzzle tower. Pure data —
## PuzzleStepNode (scripts/objectives/puzzle_step_node.gd) turns this into
## an actual scene node, both in the puzzle workshop and at match runtime.

enum Shape {
	BOX,
	CYLINDER,
	RAMP,
	STAIRCASE,
}

enum Trap {
	NONE,
	CRUMBLE,
	LAUNCH,
}

## Local position relative to the tower base center (the clearing center).
@export var position: Vector3 = Vector3.ZERO
@export_range(0.0, 360.0, 1.0) var rotation_y_degrees: float = 0.0
@export var shape: Shape = Shape.BOX
## Box: full extents (x, y, z), bottom rim rounded off. Cylinder: (diameter,
## height, diameter). Ramp: (width, max height, run length). Staircase: same
## convention as Ramp — 10 visual steps, ramp-shaped collision.
@export var size: Vector3 = Vector3(1.6, 0.3, 1.15)
## The final step — the statue spawns here. Only one step per puzzle should
## be marked; adding a Summit object in PuzzleWorkshop enforces that.
@export var is_summit: bool = false
@export var trap_type: Trap = Trap.NONE
## Meaning depends on trap_type: CRUMBLE = seconds standing on it before it
## drops away, LAUNCH = launch strength multiplier (1.0 = a normal ember-halo
## jump pad pop, higher launches the player higher).
@export var trap_param: float = 0.6
