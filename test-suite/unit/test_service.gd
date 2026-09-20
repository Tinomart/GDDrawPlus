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


func run() -> void:
	# Skinned test mesh: capsule with bones/weights, surface named "Body".
	var capsule := CapsuleMesh.new()
	capsule.radial_segments = 24
	capsule.rings = 12
	var arrays := capsule.get_mesh_arrays()
	var count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for i in range(count):
		bones.append_array(PackedInt32Array([i % 100, (i / 100) % 100, 0, 0]))
		weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var source := ArrayMesh.new()
	source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	source.surface_set_material(0, material)
	var source_positions: PackedVector3Array = source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Hero Body"
	mesh_instance.mesh = source
	root.add_child(mesh_instance)

	var service := GDDrawUVService.new()
	check(service.can_unwrap(mesh_instance), "can_unwrap accepts a MeshInstance3D with a mesh")
	check(not service.can_unwrap(Node3D.new()), "can_unwrap rejects other nodes")

	print("== Unwrap + save + assign (no editor plugin: direct assignment)")
	var result := service.unwrap_mesh_instance(mesh_instance, null)
	print("  ", result.get("message"))
	check(result.get("status") == "ok", "unwrap succeeded")
	if result.get("status") != "ok":
		return
	var path: String = result["path"]
	check(path.begins_with("res://gddraw/meshes/") and path.ends_with(".res"), "saved under res://gddraw/meshes/: %s" % path)
	check(path.get_file() == "hero_body_uv.res", "file name derived from node name")
	check(FileAccess.file_exists(path), "file exists on disk")
	check(mesh_instance.mesh == result["mesh"], "new mesh assigned to the node")
	check(mesh_instance.mesh != source, "original mesh object untouched and replaced")
	check(mesh_instance.mesh.resource_path == path, "assigned mesh is bound to the saved file")
	check(source.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].size() == source_positions.size(), "original mesh still has its own arrays")
	check(mesh_instance.mesh.surface_get_material(0) == material, "material carried over")

	print("== Second unwrap gets a unique file name")
	var second := service.unwrap_mesh_instance(mesh_instance, null)
	check(second.get("status") == "ok" and str(second["path"]).get_file() == "hero_body_uv_002.res", "second file is hero_body_uv_002.res (got %s)" % str(second.get("path")))
	mesh_instance.mesh = result["mesh"]

	print("== Reload from disk: skinning must survive serialisation")
	var reloaded: ArrayMesh = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(reloaded != null, "saved .res loads")
	if reloaded != null:
		var out: Array = reloaded.surface_get_arrays(0)
		var out_pos: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
		var out_bones: PackedInt32Array = out[Mesh.ARRAY_BONES]
		var out_weights: PackedFloat32Array = out[Mesh.ARRAY_WEIGHTS]
		var out_uv: PackedVector2Array = out[Mesh.ARRAY_TEX_UV]
		check(out_bones.size() == out_pos.size() * 4, "bones survive the disk round-trip")
		var ok := true
		for i in range(out_pos.size()):
			var original := out_bones[i * 4] + 100 * out_bones[i * 4 + 1]
			if not source_positions[original].is_equal_approx(out_pos[i]) or absf(out_weights[i * 4] - 1.0) > 0.001:
				ok = false
				break
		check(ok, "every vertex still points at the bones it started with")
		var min_uv := Vector2(INF, INF)
		var max_uv := Vector2(-INF, -INF)
		for uv in out_uv:
			min_uv = min_uv.min(uv)
			max_uv = max_uv.max(uv)
		check(min_uv.x >= 0.0 and min_uv.y >= 0.0 and max_uv.x <= 1.0 and max_uv.y <= 1.0, "UVs inside 0-1 after reload (%s .. %s)" % [min_uv, max_uv])

	print("== Error handling")
	var empty := MeshInstance3D.new()
	check(service.unwrap_mesh_instance(empty, null).get("status") == "error", "no mesh -> error result")
	var lines := ArrayMesh.new()
	var line_arrays: Array = []
	line_arrays.resize(Mesh.ARRAY_MAX)
	line_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT])
	lines.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line_arrays)
	var line_instance := MeshInstance3D.new()
	line_instance.mesh = lines
	check(service.unwrap_mesh_instance(line_instance, null).get("status") == "error", "line-only mesh -> error result")
	var bad_dir := service.unwrap_mesh_instance(mesh_instance, null, 0.02, "res://addons/GDDraw/meshes")
	check(bad_dir.get("status") == "error", "refuses to write inside the plugin folder")
