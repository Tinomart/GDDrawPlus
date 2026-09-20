extends SceneTree

var failures := 0
const GRID := 512


func check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS  ", message)
	else:
		failures += 1
		print("  FAIL  ", message)


# Rasterises every UV triangle and reports {overlap: fraction of covered pixels hit by 2+ triangles, coverage: fraction of the tile covered}.
func analyse(mesh: ArrayMesh, surface: int) -> Dictionary:
	var arrays := mesh.surface_get_arrays(surface)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var counts := PackedByteArray()
	counts.resize(GRID * GRID)
	for t in range(idx.size() / 3):
		var a := uvs[idx[t * 3]] * GRID
		var b := uvs[idx[t * 3 + 1]] * GRID
		var c := uvs[idx[t * 3 + 2]] * GRID
		var area2 := (b - a).cross(c - a)
		if absf(area2) < 0.0001:
			continue
		var lo := a.min(b).min(c)
		var hi := a.max(b).max(c)
		for y in range(maxi(int(lo.y), 0), mini(int(hi.y) + 1, GRID)):
			for x in range(maxi(int(lo.x), 0), mini(int(hi.x) + 1, GRID)):
				var p := Vector2(x + 0.5, y + 0.5)
				var w0 := (b - p).cross(c - p) / area2
				var w1 := (c - p).cross(a - p) / area2
				var w2 := (a - p).cross(b - p) / area2
				# strictly inside so shared edges between neighbours do not count as overlap
				if w0 > 0.02 and w1 > 0.02 and w2 > 0.02:
					counts[y * GRID + x] = mini(counts[y * GRID + x] + 1, 255)
	var covered := 0
	var overlapped := 0
	for v in counts:
		if v >= 1:
			covered += 1
		if v >= 2:
			overlapped += 1
	return {"overlap": float(overlapped) / float(maxi(covered, 1)), "coverage": float(covered) / float(GRID * GRID)}


func unwrap(prim: PrimitiveMesh) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, prim.get_mesh_arrays())
	var adapter := GDDrawUVMeshAdapter.from_mesh(mesh)
	return adapter.build_mesh(adapter.auto_unwrap_xatlas())


func _init() -> void:
	var shapes := {
		"capsule": CapsuleMesh.new(),
		"sphere": SphereMesh.new(),
		"cylinder": CylinderMesh.new(),
		"torus": TorusMesh.new(),
		"box": BoxMesh.new(),
		"prism": PrismMesh.new(),
	}
	for shape_name in shapes:
		var result := unwrap(shapes[shape_name])
		var stats := analyse(result, 0)
		print("  %-9s overlap %.2f%%   coverage %.1f%%" % [shape_name, stats["overlap"] * 100.0, stats["coverage"] * 100.0])
		check(stats["overlap"] < 0.01, "%s: UV islands do not overlap" % shape_name)
		var arrs := result.surface_get_arrays(0)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for uv in (arrs[Mesh.ARRAY_TEX_UV] as PackedVector2Array):
			lo = lo.min(uv)
			hi = hi.max(uv)
		check(lo.x >= 0.0095 and lo.y >= 0.0095 and hi.x <= 0.9905 and hi.y <= 0.9905, "%s: the 1%% margin is honoured around the tile border (%s .. %s)" % [shape_name, lo, hi])
		check(stats["coverage"] > 0.28, "%s: UVs make reasonable use of the tile" % shape_name)

	print("== Old angle-based engine, for comparison (expected to overlap on smooth shapes)")
	var capsule_mesh := ArrayMesh.new()
	capsule_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, CapsuleMesh.new().get_mesh_arrays())
	var old_adapter := GDDrawUVMeshAdapter.from_mesh(capsule_mesh)
	var old_stats := analyse(old_adapter.build_mesh(old_adapter.auto_unwrap()), 0)
	print("  capsule (Smart UV Project) overlap %.2f%%   coverage %.1f%%" % [old_stats["overlap"] * 100.0, old_stats["coverage"] * 100.0])

	print("== Multi-surface mesh: every surface gets its own tile")
	var multi := ArrayMesh.new()
	multi.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, CapsuleMesh.new().get_mesh_arrays())
	multi.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, SphereMesh.new().get_mesh_arrays())
	var multi_adapter := GDDrawUVMeshAdapter.from_mesh(multi)
	var multi_out := multi_adapter.build_mesh(multi_adapter.auto_unwrap_xatlas())
	for s in range(2):
		var stats := analyse(multi_out, s)
		check(stats["overlap"] < 0.01 and stats["coverage"] > 0.28, "surface %d: no overlap, good coverage (%.1f%%)" % [s, stats["coverage"] * 100.0])
	check(multi_adapter.xatlas_fallback_surfaces.is_empty(), "no surface needed the angle-based fallback")

	print("== Restricting the unwrap to one surface leaves the others alone")
	var before := multi_adapter.data
	var only_first := multi_adapter.auto_unwrap_xatlas(0.02, before, PackedInt32Array([0]))
	var untouched := true
	for f in range(before.faces.size()):
		if before.get_face_material(f) == 1 and before.uv_faces[f] != only_first.uv_faces[f]:
			untouched = false
			break
	check(untouched, "surface 1 keeps its UVs when only surface 0 is unwrapped")

	print("RESULT: ", "ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)