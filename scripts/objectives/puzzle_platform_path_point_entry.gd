class_name PuzzlePlatformPathPointEntry
extends Resource

## One point along a PuzzleMovingPlatformNode's path. Pure data —
## PuzzlePlatformPathPointNode turns this into an actual scene node.
## For a LINE/POLYGON platform this is part of the route, visited in child
## order; for a CIRCLE platform it's ignored as a route point and only
## marks a stop angle (projected from `position`) with `stop_seconds`.

## Relative to the owning platform's anchor (its own position).
@export var position: Vector3 = Vector3.ZERO
## Seconds the platform pauses here. 0 = passes straight through.
@export_range(0.0, 10.0, 0.1) var stop_seconds: float = 0.0
