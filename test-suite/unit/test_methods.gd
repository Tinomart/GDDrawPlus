extends SceneTree

var failures := 0
const GRID := 512


func check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS  ", message)
	else:
		failures += 1
		print("  FAIL  ", message)


func overlap_fraction(mesh: ArrayMesh, surface: int) -> float:
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
				if (b - p).cross(c - p) / area2 > 0.02 and (c - p).cross(a - p) / area2 > 0.02 and (a - p).cross(b - p) / area2 > 0.02:
					counts[y * GRID + x] = mini(counts[y * GRID + x] + 1, 255)
	var covered := 0
	var overlapped := 0
	for v in counts:
		if v >= 1:
			covered += 1
		if v >= 2:
			overlapped += 1
	return float(overlapped) / float(maxi(covered, 1))


func _init() -> void:
	print("== Method list")
	var ids := []
	for entry in GDDrawUVMeshAdapter.METHODS:
		ids.append(entry["id"])
		check(not str(entry["label"]).is_empty() and not str(entry["tooltip"]).is_empty(), "method '%s' has a label and a tooltip" % entry["label"])
	check(ids[0] == GDDrawUVMeshAdapter.UnwrapMethod.SMART, "Smart is the first (default) method")
	check(ids.size() == 7, "seven methods offered (smart + box + cylinder + sphere + 3 planar)")

	var shapes := {"capsule": CapsuleMesh.new(), "box": BoxMesh.new(), "torus": TorusMesh.new(), "cylinder": CylinderMesh.new()}
	var margin := 0.02
	for shape_name in shapes:
		var src := ArrayMesh.new()
		# Skinned, so we also verify that every method keeps bone data.
		var arrays := (shapes[shape_name] as PrimitiveMesh).get_mesh_arrays()
		var count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		for i in range(count):
			bones.append_array(PackedInt32Array([i % 100, (i / 100) % 100, 0, 0]))
			weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		src.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var src_pos: PackedVector3Array = src.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var adapter := GDDrawUVMeshAdapter.from_mesh(src)
		print("== %s" % shape_name)
		for entry in GDDrawUVMeshAdapter.METHODS:
			var method: int = entry["id"]
			var t0 := Time.get_ticks_msec()
			var unwrapped := adapter.unwrap(method, margin)
			var built := adapter.build_mesh(unwrapped)
			var out := built.surface_get_arrays(0)
			var uvs: PackedVector2Array = out[Mesh.ARRAY_TEX_UV]
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			var finite := true
			for uv in uvs:
				lo = lo.min(uv)
				hi = hi.max(uv)
				if not is_finite(uv.x) or not is_finite(uv.y):
					finite = false
			var label := "%s / %s" % [shape_name, entry["label"]]
			check(finite and uvs.size() > 0, "%s: produces finite UVs (%d ms)" % [label, Time.get_ticks_msec() - t0])
			check(lo.x >= margin * 0.9 and lo.y >= margin * 0.9 and hi.x <= 1.0 - margin * 0.9 and hi.y <= 1.0 - margin * 0.9, "%s: inside the tile with the %.0f%% margin (%s .. %s)" % [label, margin * 100.0, lo, hi])
			check((hi - lo).x > 0.2 or (hi - lo).y > 0.2, "%s: uses a meaningful part of the tile" % label)
			# skinning must survive every method
			var out_pos: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
			var out_bones: PackedInt32Array = out[Mesh.ARRAY_BONES]
			var skin_ok := out_bones.size() == out_pos.size() * 4
			if skin_ok:
				for i in range(out_pos.size()):
					if not src_pos[out_bones[i * 4] + 100 * out_bones[i * 4 + 1]].is_equal_approx(out_pos[i]):
						skin_ok = false
						break
			check(skin_ok, "%s: bone data intact" % label)
			if method == GDDrawUVMeshAdapter.UnwrapMethod.BOX or method == GDDrawUVMeshAdapter.UnwrapMethod.SMART:
				var overlap := overlap_fraction(built, 0)
				check(overlap < 0.01, "%s: islands do not overlap (%.2f%%)" % [label, overlap * 100.0])

	print("== Multi-surface: each surface gets its own tile, and one surface can be redone alone")
	var multi := ArrayMesh.new()
	multi.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, CapsuleMesh.new().get_mesh_arrays())
	multi.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
	var multi_adapter := GDDrawUVMeshAdapter.from_mesh(multi)
	var first := multi_adapter.unwrap(GDDrawUVMeshAdapter.UnwrapMethod.CYLINDER, 0.02)
	var second := multi_adapter.unwrap(GDDrawUVMeshAdapter.UnwrapMethod.BOX, 0.02, first, PackedInt32Array([1]))
	var surface0_kept := true
	var surface1_changed := false
	for f in range(first.faces.size()):
		if first.get_face_material(f) == 0 and first.uv_faces[f] != second.uv_faces[f]:
			surface0_kept = false
		if first.get_face_material(f) == 1 and first.uv_faces[f] != second.uv_faces[f]:
			surface1_changed = true
	check(surface0_kept, "re-unwrapping surface 1 leaves surface 0 untouched")
	check(surface1_changed, "surface 1 really changed to the new method")

	print("RESULT: ", "ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)
