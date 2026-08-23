class_name RoundedBoxMesh
extends RefCounted

## Builds a box mesh whose bottom rim — the 4 edges where the sides meet the
## bottom face, and the 4 bottom corners — is filleted with a quarter-circle
## radius, while the top face and all 4 vertical corner edges stay perfectly
## sharp. Used for PuzzleStepNode's default step shape and
## WizardChallengeHeight's procedural steps, so steps read as less blocky
## without losing their flat, easy-to-stand-on top.
##
## Geometry: each bottom edge is a quarter-circle fillet swept along that
## edge's straight run (full length minus the radius at each end); each
## bottom corner is a triangle fan tapering from the sharp rim corner down to
## where the two edge fillets end, seaming exactly with both. At radius 0
## every fillet/corner cap collapses to nothing and this produces a plain box.

const SEGMENTS := 4


static func _safe_radius(size: Vector3, r: float) -> float:
	return clampf(r, 0.0, minf(size.y, minf(size.x, size.z)) * 0.5 * 0.9)


static func build_mesh(size: Vector3, bottom_radius: float) -> ArrayMesh:
	var r := _safe_radius(size, bottom_radius)
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	_add_top(st, hx, hy, hz)
	_add_walls(st, hx, hy, hz, r)
	_add_bottom(st, hx, hy, hz, r)
	if r > 0.0:
		_add_edge_fillet_x(st, 1.0, hx, hy, hz, r)
		_add_edge_fillet_x(st, -1.0, hx, hy, hz, r)
		_add_edge_fillet_z(st, 1.0, hx, hy, hz, r)
		_add_edge_fillet_z(st, -1.0, hx, hy, hz, r)
		_add_corner_fillet(st, hx, hy, hz, r, 1.0, 1.0)
		_add_corner_fillet(st, hx, hy, hz, r, 1.0, -1.0)
		_add_corner_fillet(st, hx, hy, hz, r, -1.0, 1.0)
		_add_corner_fillet(st, hx, hy, hz, r, -1.0, -1.0)

	st.generate_normals()
	return st.commit()


## Convex hull of the top face + the (unrounded) bottom rectangle — a cheap,
## slightly-generous approximation of the rounded shape for physics. Godot
## derives the convex collision hull from these points automatically.
static func build_collision_points(size: Vector3, _bottom_radius: float) -> PackedVector3Array:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	return PackedVector3Array([
		Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz),
		Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz), Vector3(-hx, -hy, hz),
	])


## --- Winding-safe triangle/quad helpers -------------------------------------
## `outward` need not be the exact face normal — any vector on the same side
## as the true outward normal is enough to pick the correct winding.

static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.dot(outward) < 0.0:
		var tmp := b
		b = c
		c = tmp
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## Quad given as 4 corners walked around its border (a -> b -> c -> d -> a).
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


## --- Flat faces ---------------------------------------------------------------

static func _add_top(st: SurfaceTool, hx: float, hy: float, hz: float) -> void:
	_add_quad(
		st,
		Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz),
		Vector3.UP
	)


static func _add_walls(st: SurfaceTool, hx: float, hy: float, hz: float, r: float) -> void:
	## The fillet takes over below this height, so the flat wall stops here.
	var by := -hy + r
	## +X wall
	_add_quad(st,
		Vector3(hx, by, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(hx, by, hz),
		Vector3.RIGHT)
	## -X wall
	_add_quad(st,
		Vector3(-hx, by, hz), Vector3(-hx, hy, hz), Vector3(-hx, hy, -hz), Vector3(-hx, by, -hz),
		Vector3.LEFT)
	## +Z wall
	_add_quad(st,
		Vector3(hx, by, hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz), Vector3(-hx, by, hz),
		Vector3.BACK)
	## -Z wall
	_add_quad(st,
		Vector3(-hx, by, -hz), Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, by, -hz),
		Vector3.FORWARD)


static func _add_bottom(st: SurfaceTool, hx: float, hy: float, hz: float, r: float) -> void:
	_add_quad(
		st,
		Vector3(-hx + r, -hy, hz - r), Vector3(hx - r, -hy, hz - r),
		Vector3(hx - r, -hy, -hz + r), Vector3(-hx + r, -hy, -hz + r),
		Vector3.DOWN
	)


## --- Bottom-rim fillets -------------------------------------------------------
## theta=0 sits at the top of the fillet (flush with the wall), theta=pi/2
## sits at the bottom (flush with the bottom face).

## Bottom fillet running along the wall at x = sign_x * hx, swept over the
## straight portion of the edge (the run between the two corner fillets).
static func _add_edge_fillet_x(
	st: SurfaceTool,
	sign_x: float,
	hx: float,
	hy: float,
	hz: float,
	r: float
) -> void:
	var z0 := -(hz - r)
	var z1 := hz - r
	var outward_ref := Vector3(sign_x, -1.0, 0.0)
	var dtheta := (PI * 0.5) / float(SEGMENTS)
	for i in SEGMENTS:
		var t0 := float(i) * dtheta
		var t1 := float(i + 1) * dtheta
		var y0 := -hy + r * (1.0 - sin(t0))
		var x0 := sign_x * (hx - r * (1.0 - cos(t0)))
		var y1 := -hy + r * (1.0 - sin(t1))
		var x1 := sign_x * (hx - r * (1.0 - cos(t1)))
		var a := Vector3(x0, y0, z0)
		var b := Vector3(x1, y1, z0)
		var c := Vector3(x1, y1, z1)
		var d := Vector3(x0, y0, z1)
		_add_quad(st, a, b, c, d, outward_ref)


## Bottom fillet running along the wall at z = sign_z * hz.
static func _add_edge_fillet_z(
	st: SurfaceTool,
	sign_z: float,
	hx: float,
	hy: float,
	hz: float,
	r: float
) -> void:
	var x0 := -(hx - r)
	var x1 := hx - r
	var outward_ref := Vector3(0.0, -1.0, sign_z)
	var dtheta := (PI * 0.5) / float(SEGMENTS)
	for i in SEGMENTS:
		var t0 := float(i) * dtheta
		var t1 := float(i + 1) * dtheta
		var y0 := -hy + r * (1.0 - sin(t0))
		var z0 := sign_z * (hz - r * (1.0 - cos(t0)))
		var y1 := -hy + r * (1.0 - sin(t1))
		var z1 := sign_z * (hz - r * (1.0 - cos(t1)))
		var a := Vector3(x0, y0, z0)
		var b := Vector3(x1, y0, z0)
		var c := Vector3(x1, y1, z1)
		var d := Vector3(x0, y1, z1)
		_add_quad(st, a, b, c, d, outward_ref)


## --- Bottom-corner caps ---------------------------------------------------
## The two edge fillets meeting at a corner both stop `r` short of it (their
## straight runs are inset), leaving a gap bounded by: the sharp rim corner
## point (where the two walls meet, unrounded); the X-wall fillet's end
## profile (fixed z, sweeping down to the bottom corner); and the Z-wall
## fillet's end profile (fixed x, sweeping down to that same bottom corner).
## A single triangle fan from the sharp rim corner to that combined curve
## exactly seams with both walls (whose own bottom edges run straight into
## the rim corner) and both fillet ends, with no rounding at the rim itself
## — keeping the vertical corner edge above it perfectly sharp.

static func _add_corner_fillet(
	st: SurfaceTool, hx: float, hy: float, hz: float, r: float, sign_x: float, sign_z: float
) -> void:
	var apex := Vector3(sign_x * hx, -hy + r, sign_z * hz)
	var outward_ref := Vector3(sign_x, -1.0, sign_z)
	var dtheta := (PI * 0.5) / float(SEGMENTS)

	var loop: Array[Vector3] = []
	## X-wall fillet's end profile (z fixed at sign_z * (hz - r)): rim -> bottom corner.
	for i in SEGMENTS + 1:
		var theta := float(i) * dtheta
		loop.append(Vector3(
			sign_x * (hx - r * (1.0 - cos(theta))),
			-hy + r * (1.0 - sin(theta)),
			sign_z * (hz - r)
		))
	## Z-wall fillet's end profile (x fixed at sign_x * (hx - r)): bottom corner -> rim.
	## Runs theta backward so the loop continues from the shared bottom-corner point.
	for i in range(SEGMENTS - 1, -1, -1):
		var theta := float(i) * dtheta
		loop.append(Vector3(
			sign_x * (hx - r),
			-hy + r * (1.0 - sin(theta)),
			sign_z * (hz - r * (1.0 - cos(theta)))
		))

	for i in loop.size() - 1:
		_add_tri(st, apex, loop[i], loop[i + 1], outward_ref)
