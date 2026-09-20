extends SceneTree

var failures := 0


func check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS  ", message)
	else:
		failures += 1
		print("  FAIL  ", message)


func _init() -> void:
	run()
	print("RESULT: ", "ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)


func make_skinned_surface(mesh: ArrayMesh, primitive: PrimitiveMesh, skinned: bool, blend: bool) -> void:
	var arrays := primitive.get_mesh_arrays()
	var count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	if skinned:
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		var colors := PackedColorArray()
		for i in range(count):
			# Encode the original vertex index into the bones so we can track it.
			bones.append_array(PackedInt32Array([i % 100, (i / 100) % 100, 3, 4]))
			weights.append_array(PackedFloat32Array([0.6, 0.3, 0.06, 0.04]))
			colors.push_back(Color(float(i) / float(count), 0.5, 0.25, 1.0))
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = arrays[Mesh.ARRAY_TEX_UV]
	var blend_arrays: Array = []
	if blend:
		var shape: Array = []
		shape.resize(Mesh.ARRAY_MAX)
		var shifted := PackedVector3Array()
		for p in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			shifted.push_back(p + Vector3(0, 0.1, 0))
		shape[Mesh.ARRAY_VERTEX] = shifted
		shape[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
		blend_arrays.push_back(shape)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blend_arrays)


func run() -> void:
	print("== Build test mesh (skinned capsule + box, one blend shape)")
	var source := ArrayMesh.new()
	source.resource_name = "TestBody"
	source.add_blend_shape("smile")
	var capsule := CapsuleMesh.new()
	capsule.radial_segments = 16
	capsule.rings = 8
	make_skinned_surface(source, capsule, true, true)
	source.surface_set_name(0, "Body")
	make_skinned_surface(source, BoxMesh.new(), false, true)
	source.surface_set_name(1, "Box")
	var source_mat := StandardMaterial3D.new()
	source.surface_set_material(0, source_mat)

	var source_arrays := source.surface_get_arrays(0)
	var source_positions: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
	print("  source: %d surfaces, surface0 has %d vertices" % [source.get_surface_count(), source_positions.size()])

	print("== Import")
	var t0 := Time.get_ticks_msec()
	var adapter := GDDrawUVMeshAdapter.from_mesh(source)
	check(adapter != null, "adapter created")
	if adapter == null:
		return
	print("  welded: %d vertices, %d faces  (%d ms)" % [adapter.data.vertices.size(), adapter.data.faces.size(), Time.get_ticks_msec() - t0])
	check(adapter.data.faces.size() > 0, "faces imported")
	check(adapter.data.is_valid(), "GDDrawUVMeshData is valid")

	print("== Auto unwrap")
	t0 = Time.get_ticks_msec()
	var unwrapped := adapter.auto_unwrap_xatlas()
	print("  unwrap took %d ms" % (Time.get_ticks_msec() - t0))
	check(unwrapped != null, "unwrap returned data")
	if unwrapped == null:
		return
	check(unwrapped.has_uv_map, "has_uv_map set")

	print("== Rebuild")
	t0 = Time.get_ticks_msec()
	var rebuilt := adapter.build_mesh(unwrapped)
	print("  rebuild took %d ms" % (Time.get_ticks_msec() - t0))
	check(rebuilt.get_surface_count() == source.get_surface_count(), "surface count preserved")
	check(rebuilt.surface_get_material(0) == source_mat, "material preserved on surface 0")
	check(rebuilt.surface_get_name(0) == "Body" and rebuilt.surface_get_name(1) == "Box", "surface names preserved")
	check(rebuilt.get_blend_shape_count() == 1 and rebuilt.get_blend_shape_name(0) == "smile", "blend shape name preserved")
	check(rebuilt.resource_name == "TestBody", "resource name preserved")

	for s in range(source.get_surface_count()):
		var src: Array = source.surface_get_arrays(s)
		var out: Array = rebuilt.surface_get_arrays(s)
		var src_pos: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var out_pos: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
		var out_uv: PackedVector2Array = out[Mesh.ARRAY_TEX_UV]
		var src_idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
		var out_idx: PackedInt32Array = out[Mesh.ARRAY_INDEX]
		print("== Surface %d: %d -> %d vertices, %d -> %d indices" % [s, src_pos.size(), out_pos.size(), src_idx.size(), out_idx.size()])
		check(out_idx.size() == src_idx.size(), "surface %d: triangle count preserved" % s)
		check(out_pos.size() >= src_pos.size(), "surface %d: vertices only split, never lost" % s)

		# Geometry preserved triangle-by-triangle (same position at every corner).
		var geometry_ok := true
		for i in range(src_idx.size()):
			if not src_pos[src_idx[i]].is_equal_approx(out_pos[out_idx[i]]):
				geometry_ok = false
				break
		check(geometry_ok, "surface %d: every triangle corner keeps its position" % s)

		# UV1 within 0-1 and non-degenerate.
		var in_range := true
		var min_uv := Vector2(INF, INF)
		var max_uv := Vector2(-INF, -INF)
		for uv in out_uv:
			min_uv = min_uv.min(uv)
			max_uv = max_uv.max(uv)
			if uv.x < -0.0001 or uv.y < -0.0001 or uv.x > 1.0001 or uv.y > 1.0001:
				in_range = false
		check(in_range, "surface %d: UVs inside 0-1 (range %s .. %s)" % [s, min_uv, max_uv])
		check((max_uv - min_uv).x > 0.3 and (max_uv - min_uv).y > 0.3, "surface %d: UVs use a meaningful part of the tile" % s)

		# UV2 / other attributes preserved through the vertex remap.
		var src_uv2: PackedVector2Array = src[Mesh.ARRAY_TEX_UV2]
		var out_uv2: PackedVector2Array = out[Mesh.ARRAY_TEX_UV2]
		var src_normals: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
		var out_normals: PackedVector3Array = out[Mesh.ARRAY_NORMAL]
		var attrs_ok := true
		for i in range(src_idx.size()):
			var a := src_idx[i]
			var b := out_idx[i]
			# Normals are stored octahedral-compressed by Godot, so allow quantisation error.
			if src_uv2[a].distance_to(out_uv2[b]) > 0.001 or src_normals[a].distance_to(out_normals[b]) > 0.02:
				attrs_ok = false
				print("      corner %d: uv2 %s vs %s, normal %s vs %s" % [i, src_uv2[a], out_uv2[b], src_normals[a], out_normals[b]])
				break
		check(attrs_ok, "surface %d: UV2 + normals identical per corner" % s)

		# Blend shape remapped consistently (position + 0.1 in y at every corner).
		var blend: Array = rebuilt.surface_get_blend_shape_arrays(s)
		check(blend.size() == 1, "surface %d: blend shape present" % s)
		if blend.size() == 1:
			var blend_pos: PackedVector3Array = blend[0][Mesh.ARRAY_VERTEX]
			var blend_ok := blend_pos.size() == out_pos.size()
			if blend_ok:
				for i in range(out_pos.size()):
					if not blend_pos[i].is_equal_approx(out_pos[i] + Vector3(0, 0.1, 0)):
						blend_ok = false
						break
			check(blend_ok, "surface %d: blend shape deltas follow their vertices" % s)

		# The important one: skinning survives.
		if s == 0:
			var out_bones: PackedInt32Array = out[Mesh.ARRAY_BONES]
			var out_weights: PackedFloat32Array = out[Mesh.ARRAY_WEIGHTS]
			var out_colors: PackedColorArray = out[Mesh.ARRAY_COLOR]
			check(out_bones.size() == out_pos.size() * 4, "bones array has 4 influences per vertex")
			check(out_weights.size() == out_pos.size() * 4, "weights array has 4 influences per vertex")
			var skin_ok := true
			var bad := ""
			for i in range(out_pos.size()):
				var original := out_bones[i * 4] + 100 * out_bones[i * 4 + 1]
				var reasons := PackedStringArray()
				if not src_pos[original].is_equal_approx(out_pos[i]):
					reasons.push_back("position")
				if out_bones[i * 4 + 2] != 3 or out_bones[i * 4 + 3] != 4:
					reasons.push_back("bone ids")
				# Weights are stored as 16-bit normalised values; colors as 8-bit.
				if absf(out_weights[i * 4] - 0.6) > 0.001 or absf(out_weights[i * 4 + 3] - 0.04) > 0.001:
					reasons.push_back("weights %s" % [out_weights.slice(i * 4, i * 4 + 4)])
				if absf(out_colors[i].r - float(original) / float(src_pos.size())) > 0.005:
					reasons.push_back("color")
				if not reasons.is_empty():
					skin_ok = false
					bad = "vertex %d (orig %d): %s" % [i, original, ", ".join(reasons)]
					break
			check(skin_ok, "surface 0: bones/weights/colors still belong to the right vertex %s" % bad)

	print("== Idempotence: unwrapped mesh imports back with the same UVs")
	var again := GDDrawUVMeshAdapter.from_mesh(rebuilt)
	check(again != null and again.data.faces.size() == adapter.data.faces.size(), "re-import has the same face count")
	if again != null:
		var rebuilt_again := again.build_mesh()
		check(rebuilt_again.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == rebuilt.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), "rebuilding without changes does not split further")

	print("== Non-indexed mesh input")
	var flat := ArrayMesh.new()
	var flat_arrays: Array = []
	flat_arrays.resize(Mesh.ARRAY_MAX)
	flat_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)])
	flat.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, flat_arrays)
	var flat_adapter := GDDrawUVMeshAdapter.from_mesh(flat)
	check(flat_adapter != null, "non-indexed mesh imports")
	if flat_adapter != null:
		var flat_out := flat_adapter.build_mesh(flat_adapter.auto_unwrap_xatlas())
		check(flat_out.get_surface_count() == 1, "non-indexed mesh rebuilds")

	print("== PrimitiveMesh input (not an ArrayMesh)")
	var box_adapter := GDDrawUVMeshAdapter.from_mesh(BoxMesh.new())
	check(box_adapter != null, "BoxMesh imports")
	if box_adapter != null:
		var box_out := box_adapter.build_mesh(box_adapter.auto_unwrap_xatlas())
		check(box_out.get_surface_count() == 1, "BoxMesh rebuilds into an ArrayMesh")

	print("== Unsupported primitive types pass through")
	var lines := ArrayMesh.new()
	var line_arrays: Array = []
	line_arrays.resize(Mesh.ARRAY_MAX)
	line_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT])
	lines.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line_arrays)
	check(GDDrawUVMeshAdapter.from_mesh(lines) == null, "line-only mesh is rejected")
