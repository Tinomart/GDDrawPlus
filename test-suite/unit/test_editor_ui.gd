extends SceneTree

var failures := 0
var _frames := 0
var _window: GDDrawUVEditorWindow
var _commits := 0
var _last_commit: GDDrawUVMeshData


func check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS  ", message)
	else:
		failures += 1
		print("  FAIL  ", message)


func _initialize() -> void:
	var capsule := CapsuleMesh.new()
	capsule.radial_segments = 16
	capsule.rings = 8
	var source := ArrayMesh.new()
	source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, capsule.get_mesh_arrays())
	var box := BoxMesh.new()
	source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	var adapter := GDDrawUVMeshAdapter.from_mesh(source)
	check(adapter != null, "adapter created")

	_window = GDDrawUVEditorWindow.new()
	_window.mesh_commit_requested.connect(func(mesh_data, action_name):
		_commits += 1
		_last_commit = mesh_data
		print("  commit requested: ", action_name))
	root.add_child(_window)
	var checker := GDDrawUVOperations.create_checker_texture(64, 4)
	var seeded := adapter.auto_unwrap_xatlas()
	_window.set_data(seeded, [checker, checker], PackedStringArray(["Body", "Box"]), 0)
	_window.open_editor()
	check(_window.visible, "window opened")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		print("== Run Pack Islands through the window's own button handler (background job)")
		_window._on_pack()
	if _frames > 5 and _commits > 0 and _frames < 100000:
		_finish()
		return true
	if _frames == 900:
		check(false, "pack islands never committed (background job stuck?)")
		_finish()
		return true
	return false


func _finish() -> void:
	if _last_commit != null:
		check(_last_commit.has_uv_map, "committed mesh has UVs")
		var bounds := GDDrawUVOperations.get_uv_bounds(_last_commit, GDDrawUVOperations.all_faces(_last_commit))
		check(bounds.size.x > 0.3 and bounds.size.y > 0.3, "committed UV layout is non-trivial (%s)" % str(bounds))
		# Exercise a few more window operations directly.
		_window._on_select_all()
		_window._on_relax()
		_window._on_frame_all()
	print("RESULT: ", "ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)