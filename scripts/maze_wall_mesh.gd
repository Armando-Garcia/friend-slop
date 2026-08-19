class_name MazeWallMesh
extends RefCounted

## Maze walls as a sausage graph: box + cylinder along each run, vertical
## capsule (post + sphere) at every dead-end and junction. Tubes stop at
## cell centers so ends are hemispheres, not flat caps.

const CYL_SEGMENTS := 12
const SPHERE_RINGS := 6


static func cylinder_radius(cell_size: float) -> float:
	return maxf(cell_size, 0.1) * 0.5


static func collect_runs(wall_grid: Array) -> Array:
	var runs: Array = []
	if wall_grid.is_empty() or wall_grid[0].is_empty():
		return runs
	var h_runs := _axis_runs(wall_grid, true)
	var v_runs := _axis_runs(wall_grid, false)
	var v_len := _cell_lengths(v_runs, false)
	for run in h_runs:
		var length: int = int(run["length"])
		if length >= 2:
			runs.append(run)
			continue
		var key := Vector2i(int(run["gx"]), int(run["gy"]))
		if int(v_len.get(key, 1)) < 2:
			runs.append(run)
	for run in v_runs:
		if int(run["length"]) >= 2:
			runs.append(run)
	return runs


static func collect_joints(runs: Array) -> Array:
	var joints := {}
	var counts := {}
	for run in runs:
		var cells: Array = run_cells(run)
		if cells.is_empty():
			continue
		for cell in cells:
			counts[cell] = int(counts.get(cell, 0)) + 1
		joints[cells[0]] = true
		joints[cells[cells.size() - 1]] = true
	for cell in counts:
		if int(counts[cell]) >= 2:
			joints[cell] = true
	return joints.keys()


static func run_cells(run: Dictionary) -> Array:
	var cells: Array = []
	var n: int = maxi(int(run["length"]), 1)
	var gx: int = int(run["gx"])
	var gy: int = int(run["gy"])
	var along_x: bool = bool(run["along_x"])
	for i in n:
		if along_x:
			cells.append(Vector2i(gx + i, gy))
		else:
			cells.append(Vector2i(gx, gy + i))
	return cells


static func run_pose(
	run: Dictionary,
	size: Vector3,
	grid_to_world: Callable,
	box_h: float,
	radius: float
) -> Dictionary:
	var cell := maxf(size.x, 0.1)
	var along_x: bool = bool(run["along_x"])
	var n: int = maxi(int(run["length"]), 1)
	var gx: int = int(run["gx"])
	var gy: int = int(run["gy"])
	var a: Vector3 = grid_to_world.call(gx, gy)
	var b: Vector3 = grid_to_world.call(
		gx + (n - 1 if along_x else 0),
		gy + (0 if along_x else n - 1)
	)
	var mid := (a + b) * 0.5
	## Center-to-center so caps bury in the joint spheres.
	var length := cell * float(maxi(n - 1, 0))
	var box_size := (
		Vector3(length, box_h, cell) if along_x else Vector3(cell, box_h, length)
	)
	var box_xform := Transform3D(
		Basis.IDENTITY, Vector3(mid.x, box_h * 0.5, mid.z)
	)
	var cyl_basis := (
		Basis.from_euler(Vector3(0.0, 0.0, PI * 0.5))
		if along_x
		else Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0))
	)
	var cyl_xform := Transform3D(cyl_basis, Vector3(mid.x, box_h, mid.z))
	return {
		"box_size": box_size,
		"box_xform": box_xform,
		"cyl_xform": cyl_xform,
		"cyl_len": length,
		"radius": radius,
	}


static func joint_pose(
	cell: Vector2i,
	grid_to_world: Callable,
	box_h: float,
	radius: float
) -> Dictionary:
	var p: Vector3 = grid_to_world.call(cell.x, cell.y)
	return {
		"post_xform": Transform3D(
			Basis.IDENTITY, Vector3(p.x, box_h * 0.5, p.z)
		),
		"post_h": box_h,
		"ball_xform": Transform3D(Basis.IDENTITY, Vector3(p.x, box_h, p.z)),
		"radius": radius,
	}


static func shaft_transform(pose: Dictionary) -> Transform3D:
	var origin: Vector3 = pose["box_xform"].origin
	var box_size: Vector3 = pose["box_size"]
	return Transform3D(Basis.from_scale(box_size), origin)


static func cap_transform(pose: Dictionary) -> Transform3D:
	var xf: Transform3D = pose["cyl_xform"]
	var radius: float = float(pose["radius"])
	var length: float = float(pose["cyl_len"])
	return xf.scaled_local(Vector3(radius, length, radius))


static func post_transform(pose: Dictionary) -> Transform3D:
	var xf: Transform3D = pose["post_xform"]
	var radius: float = float(pose["radius"])
	var post_h: float = float(pose["post_h"])
	return xf.scaled_local(Vector3(radius, post_h, radius))


static func ball_transform(pose: Dictionary) -> Transform3D:
	var xf: Transform3D = pose["ball_xform"]
	var radius: float = float(pose["radius"])
	return xf.scaled_local(Vector3(radius, radius, radius))


static func make_shaft_mesh() -> BoxMesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	return box


static func make_cap_mesh() -> CylinderMesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = CYL_SEGMENTS
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	return cyl


static func make_post_mesh() -> CylinderMesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = CYL_SEGMENTS
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = true
	return cyl


static func make_ball_mesh() -> SphereMesh:
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = CYL_SEGMENTS
	ball.rings = SPHERE_RINGS
	return ball


static func _axis_runs(wall_grid: Array, along_x: bool) -> Array:
	var runs: Array = []
	var gw: int = wall_grid.size()
	var gh: int = wall_grid[0].size()
	if along_x:
		for gy in gh:
			var gx := 0
			while gx < gw:
				if int(wall_grid[gx][gy]) != 1:
					gx += 1
					continue
				var start := gx
				while gx < gw and int(wall_grid[gx][gy]) == 1:
					gx += 1
				runs.append({
					"along_x": true,
					"gx": start,
					"gy": gy,
					"length": gx - start,
				})
		return runs
	for gx in gw:
		var gy := 0
		while gy < gh:
			if int(wall_grid[gx][gy]) != 1:
				gy += 1
				continue
			var start := gy
			while gy < gh and int(wall_grid[gx][gy]) == 1:
				gy += 1
			runs.append({
				"along_x": false,
				"gx": gx,
				"gy": start,
				"length": gy - start,
			})
	return runs


static func _cell_lengths(runs: Array, along_x: bool) -> Dictionary:
	var lengths := {}
	for run in runs:
		var n: int = int(run["length"])
		var gx: int = int(run["gx"])
		var gy: int = int(run["gy"])
		for i in n:
			var key := (
				Vector2i(gx + i, gy) if along_x else Vector2i(gx, gy + i)
			)
			lengths[key] = n
	return lengths
