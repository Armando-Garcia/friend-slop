class_name MazeHoleWallPiece
extends RefCounted

## Tunnel-only visuals for a carved hole cell. Wall frame lives in the maze multimesh.

const MazeHoleScript := preload("res://scripts/maze/maze_hole.gd")
const MazeHoleTunnelScript := preload("res://scripts/maze/maze_hole_tunnel.gd")
const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")


static func build_tunnel(parent: Node3D, cell_size: float) -> void:
	if parent == null:
		return
	var tunnel := MeshInstance3D.new()
	tunnel.name = "Tunnel"
	tunnel.mesh = MazeHoleTunnelScript.build_interior_mesh(cell_size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = MazeHoleScript.TUNNEL_COLOR
	mat.roughness = 1.0
	tunnel.material_override = mat
	tunnel.layers = WorldVisualLayersScript.WORLD
	tunnel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(tunnel)
