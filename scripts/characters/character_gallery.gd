@tool
extends Node3D

## Standalone inspect scene for PlayableCharacter / Apprentice / Headmaster.
## Marks the tree so nested instances stay preview-only when F6-run.


func _enter_tree() -> void:
	set_meta("character_preview_scene", true)
