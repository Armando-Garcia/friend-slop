class_name PuzzleBasePieceEntry
extends Resource

## One saved base piece in a WizardChallengeHeight jump-puzzle tower's
## footprint. Pure data — PuzzleBasePieceNode (scripts/objectives/
## puzzle_base_piece_node.gd) turns this into an actual scene node, both in
## the puzzle workshop and at match runtime. A puzzle can have any number of
## base pieces (e.g. a rectangular base plus a hole cut somewhere in it).

enum Shape {
	RECT_BASE,
	RECT_HOLE,
	CYLINDER_HOLE,
}

## Local position relative to the tower base center (the clearing center).
@export var position: Vector3 = Vector3.ZERO
@export_range(0.0, 360.0, 1.0) var rotation_y_degrees: float = 0.0
@export var shape: Shape = Shape.RECT_BASE
## RECT_BASE: (length, unused, width) — a flat slab. RECT_HOLE: (length,
## depth, width) — an open-topped rectangular pit. CYLINDER_HOLE: (radius,
## depth, unused) — an open-topped round pit.
@export var size: Vector3 = Vector3(5.4, 0.2, 5.4)
