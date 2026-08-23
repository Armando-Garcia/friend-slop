class_name StaircaseMesh
extends RefCounted

## Visually 10 discrete stair steps rising from the low end (z = -hz) to the
## high end (z = +hz), but collides exactly like the RAMP wedge (see
## PuzzleStepNode._build_ramp) so it "works just like a ramp" to walk up
## despite looking like stairs. Used for the stationary Staircase Step shape
## and the Moving Platform's Staircase tile shape.
##
## size: (width, max height, run length) — same convention as RAMP.

const STEP_COUNT := 10


static func build_mesh(size: Vector3) -> ArrayMesh:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var step_depth := size.z / float(STEP_COUNT)
	var step_height := size.y / float(STEP_COUNT)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in STEP_COUNT:
		var z0 := -hz + float(i) * step_depth
		var z1 := -hz + float(i + 1) * step_depth
		var y1 := -hy + float(i + 1) * step_height
		## Each step is a complete, independent box — any overlapping faces
		## at step boundaries end up fully enclosed inside the union of two
		## adjacent solid boxes, so they're never visible from outside.
		_add_box(st, -hx, hx, -hy, y1, z0, z1)
	st.generate_normals()
	return st.commit()


## Identical to PuzzleStepNode._build_ramp's collision wedge — a staircase
## collides exactly like a plain ramp.
static func ramp_collision_points(size: Vector3) -> PackedVector3Array:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var a := Vector3(-hx, -hy, -hz)
	var b := Vector3(hx, -hy, -hz)
	var c := Vector3(-hx, -hy, hz)
	var d := Vector3(hx, -hy, hz)
	var e := Vector3(-hx, hy, hz)
	var f := Vector3(hx, hy, hz)
	return PackedVector3Array([a, b, c, d, e, f])


## --- Winding-safe triangle/quad helpers -------------------------------------

static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.dot(outward) < 0.0:
		var tmp := b
		b = c
		c = tmp
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _add_quad(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	outward: Vector3
) -> void:
	_add_tri(st, a, b, c, outward)
	_add_tri(st, a, c, d, outward)


static func _add_box(
	st: SurfaceTool, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float
) -> void:
	var p := [
		Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1),
		Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1),
	]
	_add_quad(st, p[0], p[1], p[2], p[3], Vector3.DOWN)     ## bottom
	_add_quad(st, p[4], p[7], p[6], p[5], Vector3.UP)       ## top
	_add_quad(st, p[0], p[4], p[5], p[1], Vector3.FORWARD)  ## -z wall
	_add_quad(st, p[3], p[2], p[6], p[7], Vector3.BACK)     ## +z wall
	_add_quad(st, p[0], p[3], p[7], p[4], Vector3.LEFT)     ## -x wall
	_add_quad(st, p[1], p[5], p[6], p[2], Vector3.RIGHT)    ## +x wall
