class_name PuzzlePendulumEntry
extends Resource

## One saved pendulum trap in a WizardChallengeHeight jump-puzzle tower. Pure
## data — PuzzlePendulumNode (puzzle_pendulum_node.gd) turns this into an
## actual scene node, both in the puzzle workshop and at match runtime.

## The floating peg's position, relative to the tower base center.
@export var position: Vector3 = Vector3.ZERO
## String length — also the radius of the arc the bob swings through.
@export_range(0.5, 8.0, 0.1) var radius: float = 2.5
## How fast the bob swings back and forth. ~1.0 is a lazy multi-second swing.
@export_range(0.05, 4.0, 0.05) var speed: float = 1.0
## How far the bob swings to either side of straight-down (degrees).
@export_range(5.0, 90.0, 1.0) var swing_amplitude_degrees: float = 45.0
## Diameter of the swinging bob.
@export_range(0.3, 3.0, 0.05) var bob_size: float = 0.8
## Yaw of the swing plane — which direction the pendulum swings across.
@export_range(0.0, 360.0, 1.0) var swing_plane_rotation_degrees: float = 0.0
## Launch pads planted at the swing's extremes, one per side.
@export var bounce_pad_left: bool = false
@export var bounce_pad_right: bool = false
