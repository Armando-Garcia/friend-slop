class_name MazeHoleTunnel
extends RefCounted

## Square + domed tunnel interior (open at both corridor mouths).

const MazeHoleScript := preload("res://scripts/maze/maze_hole.gd")

const WALL_THICKNESS := 0.05
const ARCH_SEGMENTS := 12


static func build_interior_mesh(depth: float) -> ArrayMesh:
	var half_w := MazeHoleScript.HOLE_WIDTH * 0.5
	var rect_h := MazeHoleScript.HOLE_RECT_HEIGHT
	var inner_half_w := half_w - WALL_THICKNESS
	var half_d := depth * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	_add_quad(
		st,
		Vector3(-inner_half_w, 0.0, -half_d),
		Vector3(-inner_half_w, 0.0, half_d),
		Vector3(-inner_half_w, rect_h, half_d),
		Vector3(-inner_half_w, rect_h, -half_d),
		Vector3.RIGHT
	)
	_add_quad(
		st,
		Vector3(inner_half_w, 0.0, half_d),
		Vector3(inner_half_w, 0.0, -half_d),
		Vector3(inner_half_w, rect_h, -half_d),
		Vector3(inner_half_w, rect_h, half_d),
		Vector3.LEFT
	)
	_add_quad(
		st,
		Vector3(-inner_half_w, 0.0, -half_d),
		Vector3(inner_half_w, 0.0, -half_d),
		Vector3(inner_half_w, 0.0, half_d),
		Vector3(-inner_half_w, 0.0, half_d),
		Vector3.UP
	)
	_add_inner_arch(st, inner_half_w, rect_h, half_d)
	st.generate_normals()
	return st.commit()


static func _add_inner_arch(
	st: SurfaceTool,
	inner_half_w: float,
	inner_rect_h: float,
	half_d: float
) -> void:
	for i in range(ARCH_SEGMENTS):
		var t0 := float(i) / float(ARCH_SEGMENTS)
		var t1 := float(i + 1) / float(ARCH_SEGMENTS)
		var ang0 := PI * t0
		var ang1 := PI * t1
		var p0 := Vector3(
			cos(ang0) * inner_half_w, inner_rect_h + sin(ang0) * inner_half_w, -half_d
		)
		var p1 := Vector3(
			cos(ang1) * inner_half_w, inner_rect_h + sin(ang1) * inner_half_w, -half_d
		)
		var p2 := Vector3(
			cos(ang1) * inner_half_w, inner_rect_h + sin(ang1) * inner_half_w, half_d
		)
		var p3 := Vector3(
			cos(ang0) * inner_half_w, inner_rect_h + sin(ang0) * inner_half_w, half_d
		)
		var normal := (p1 - p0).cross(p3 - p0).normalized()
		if normal.y > -0.01:
			normal = -normal
		_add_quad(st, p0, p1, p2, p3, normal)


static func _add_quad(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	normal: Vector3
) -> void:
	st.set_normal(normal)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.set_normal(normal)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)
