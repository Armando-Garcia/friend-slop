extends SceneTree

## Bakes the fixed cloud mesh pool under assets/environment/clouds/.
## Usage: godot --headless --path . -s res://tools/bake_cloud_meshes.gd

const CloudMeshBuilderScript := preload("res://scripts/environment/cloud_mesh_builder.gd")

const OUTPUT_DIR := "res://assets/environment/clouds"
const POOL_COUNT := 8
## Stable seeds so re-baking keeps the same shapes unless you change these.
const BAKE_SEEDS := [
	1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008,
]


func _init() -> void:
	call_deferred("_bake_and_quit")


func _bake_and_quit() -> void:
	var dir := DirAccess.open("res://assets/environment")
	if dir == null:
		push_error("bake_cloud_meshes: missing res://assets/environment")
		quit(1)
		return
	if not dir.dir_exists("clouds"):
		var err := dir.make_dir("clouds")
		if err != OK:
			push_error("bake_cloud_meshes: could not create clouds dir (%s)" % error_string(err))
			quit(1)
			return

	for i in POOL_COUNT:
		var seed_value: int = BAKE_SEEDS[i]
		var mesh: ArrayMesh = CloudMeshBuilderScript.build(
			seed_value,
			CloudMeshBuilderScript.REFERENCE_RADIUS
		)
		var path := "%s/cloud_%02d.res" % [OUTPUT_DIR, i + 1]
		var save_err := ResourceSaver.save(mesh, path)
		if save_err != OK:
			push_error("bake_cloud_meshes: failed to save %s (%s)" % [path, error_string(save_err)])
			quit(1)
			return
		print("Wrote %s (seed=%d)" % [path, seed_value])

	print("Baked %d cloud meshes." % POOL_COUNT)
	quit(0)
