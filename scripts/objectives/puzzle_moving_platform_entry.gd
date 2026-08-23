class_name PuzzleMovingPlatformEntry
extends Resource

## One saved moving platform in a WizardChallengeHeight jump-puzzle tower.
## Pure data — PuzzleMovingPlatformNode turns this into an actual scene
## node, both in the puzzle workshop and at match runtime.

enum PathType { LINE, CIRCLE, POLYGON }
enum TileShape { BOX, STAIRCASE }

## Path anchor: the LINE/POLYGON start, or the CIRCLE's center. Relative to
## the tower base center.
@export var position: Vector3 = Vector3.ZERO
@export var path_type: PathType = PathType.LINE
## Meters per second traveled along the path.
@export_range(0.2, 10.0, 0.1) var speed: float = 2.0
## Regular ride-along tile, or a jump tile that launches the player on footfall.
@export var is_jump_tile: bool = false
## STAIRCASE looks like 10 stair steps but collides like a plain ramp — a
## "moving version" of the stationary Staircase step.
@export var tile_shape: TileShape = TileShape.BOX
@export var tile_size: Vector3 = Vector3(1.6, 0.3, 1.6)
## CIRCLE only: radius of the loop.
@export_range(0.5, 10.0, 0.1) var circle_radius: float = 3.0
## CIRCLE only: orientation of the circle's plane.
@export var circle_rotation_degrees: Vector3 = Vector3.ZERO
## POLYGON only: loop back to the first point instead of ping-ponging.
@export var closed_loop: bool = true
## LINE/POLYGON: the route, visited in child order. CIRCLE: stop markers only.
@export var path_points: Array[PuzzlePlatformPathPointEntry] = []
