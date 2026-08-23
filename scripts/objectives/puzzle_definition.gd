class_name PuzzleDefinition
extends Resource

## A saved WizardChallengeHeight jump-puzzle layout: an ordered list of steps,
## pendulum traps, moving platforms, and base pieces (the ground-level
## footprint). Authored in scenes/objectives/puzzle_workshop.tscn, consumed
## by WizardChallengeHeight at match setup.

@export var puzzle_name: String = "New Puzzle"
@export var steps: Array[PuzzleStepEntry] = []
@export var pendulums: Array[PuzzlePendulumEntry] = []
@export var platforms: Array[PuzzleMovingPlatformEntry] = []
@export var base_pieces: Array[PuzzleBasePieceEntry] = []


## The step the statue spawns on: the one explicitly marked is_summit, else
## the last step, else null if the puzzle has no steps.
func find_summit_step() -> PuzzleStepEntry:
	for entry in steps:
		if entry != null and entry.is_summit:
			return entry
	if steps.is_empty():
		return null
	return steps[steps.size() - 1]
