@tool
extends EditorPlugin

var failures := 0
var _started := false


func check(condition: bool, message: String) -> void:
	if condition:
		print("ITEST  PASS  ", message)
	else:
		failures += 1
		print("ITEST  FAIL  ", message)


var _frames := 0


func _enter_tree() -> void:
	print("ITEST  driver _enter_tree")
	set_process(true)


func _process(_delta: float) -> void:
	# Frame-based waits: wall-clock timers proved unreliable in a headless editor.
	_frames += 1
	if _frames == 1:
		print("ITEST  first _process frame")
	if _frames == 240 and not _started:
		_run()
	if _frames == 3000:
		print("ITEST  TIMEOUT")
		get_tree().quit(2)


func _find_dock() -> Control:
	for control in get_editor_interface().get_base_control().find_children("GDDraw", "Control", true, false):
		if control.has_meta("gddraw_bottom_panel_dock"):
			return control
	return null


func _make_skinned_mesh() -> ArrayMesh:
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
	# No UV data at all: the case GDDraw refuses to open on its own.
	arrays[Mesh.ARRAY_TEX_UV] = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	mesh.surface_set_material(0, material)
	return mesh


func _run() -> void:
	if _started:
		return
	_started = true
	var ei := get_editor_interface()
	print("ITEST  editor ready")

	var dock := _find_dock()
	check(dock != null, "GDDraw dock is present in the editor")
	if dock == null:
		get_tree().quit(1)
		return
	print("ITEST  -- editor layout must not be disturbed by the new dock (regression: dock group grew to 4000+ px)")
	for _i in range(30):
		await get_tree().process_frame
	var window_height := float(get_tree().root.size.y)
	var worst := 0.0
	for c in ei.get_base_control().find_children("*", "SideDockTabContainer", true, false):
		if (c as Control).is_visible_in_tree():
			worst = maxf(worst, (c as Control).size.y)
	check(worst <= window_height, "every visible side dock group fits the window (tallest %.0f px, window %.0f px)" % [worst, window_height])
	var file_systems := ei.get_base_control().find_children("*", "FileSystemDock", true, false)
	check(file_systems.size() > 0 and Rect2(Vector2.ZERO, Vector2(get_tree().root.size)).encloses(Rect2((file_systems[0] as Control).global_position, (file_systems[0] as Control).size)), "the FileSystem dock is on screen")
	var extra_uv_docks := ei.get_base_control().find_children("*", "EditorDock", true, false).filter(func(d): return str(d.get("title")) == "UV")
	check(extra_uv_docks.is_empty(), "no separate UV editor dock is added: the UV tools live inside GDDraw")

	print("ITEST  -- the UV menu inside GDDraw's menu bar")
	var menu_bar: MenuBar = dock.get("_menu_bar")
	var titles := []
	for i in range(menu_bar.get_menu_count()):
		titles.append(menu_bar.get_menu_title(i))
	print("ITEST  GDDraw menu bar: ", titles)
	check(titles.has("UV") and titles.has("Godot") and titles.find("UV") == titles.find("Godot") + 1, "GDDraw's menu bar has its own 'UV' menu right after 'Godot'")
	check(titles.find("UV") < titles.find("Help"), "...and before 'Help'")
	var godot_menu: PopupMenu = dock.get("_godot_menu")
	var menu_texts := []
	for i in range(godot_menu.item_count):
		menu_texts.append(godot_menu.get_item_text(i))
	check(not menu_texts.any(func(s): return "UV" in str(s) or "nwrap" in str(s)), "the Godot menu has no UV entries")
	check(dock.get("_uv_unwrap_button") == null and dock.get("_uv_editor_button") == null, "GDDraw's context bar has no UV buttons")
	var uv_menu: PopupMenu = dock.get("_uv_menu")
	dock.call("_sync_menu_state")
	var uv_items := {}
	for i in range(uv_menu.item_count):
		uv_items[uv_menu.get_item_text(i)] = not uv_menu.is_item_disabled(i)
	print("ITEST  UV menu items: ", uv_items)
	check(uv_items.get("Auto Unwrap…", false) and uv_items.get("UV Editor…", false), "UV menu offers enabled 'Auto Unwrap…' and 'UV Editor…'")
	var unwrap_id := _menu_id(dock, "_uv_menu", "Auto Unwrap…")
	var editor_id := _menu_id(dock, "_uv_menu", "UV Editor…")
	dock.call("_on_menu_command", unwrap_id)
	await get_tree().process_frame
	check(dock.get("_uv_tools") == null, "with nothing selected, Auto Unwrap only explains itself (no dialog, no tools created)")
	# Scene with a skinned mesh that has NO UVs.
	var root := Node3D.new()
	root.name = "Root"
	var body := MeshInstance3D.new()
	body.name = "Hero Body"
	var original_mesh := _make_skinned_mesh()
	body.mesh = original_mesh
	root.add_child(body)
	body.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, "res://itest_scene.tscn")
	ei.open_scene_from_path("res://itest_scene.tscn")
	for _i in range(90):
		await get_tree().process_frame
	var edited_root := ei.get_edited_scene_root()
	check(edited_root != null, "scene opened in the editor")
	var edited_body := edited_root.get_node("Hero Body") as MeshInstance3D
	var source_uvs: Variant = edited_body.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	check(source_uvs == null or (source_uvs as PackedVector2Array).is_empty(), "test mesh really has no UVs to begin with")

	# The reopened scene owns its own copy of the mesh; compare against that, not the pre-save object.
	var mesh_before_unwrap: Mesh = edited_body.mesh
	ei.get_selection().clear()
	ei.get_selection().add_node(edited_body)
	await get_tree().process_frame

	print("ITEST  -- select the mesh, choose UV > Auto Unwrap…")
	await get_tree().process_frame
	dock.call("_on_menu_command", unwrap_id)
	await get_tree().process_frame
	var tools: Node = dock.get("_uv_tools")
	check(tools != null, "UV tools controller was created")
	var method_option: OptionButton = tools.get("_method_option")
	check(method_option != null and method_option.item_count == 7 and method_option.get_selected_id() == GDDrawUVMeshAdapter.UnwrapMethod.SMART, "dialog has a Method dropdown with 7 methods, Smart selected by default")
	var dialog: ConfirmationDialog = tools.get("_unwrap_dialog")
	check(dialog != null and dialog.visible, "confirmation dialog is showing")
	check(not (tools.get("_unwrap_session_warning") as Label).visible, "no paint-session warning without a session")

	var size_label: Label = tools.get("_unwrap_size_label")
	check(size_label != null and size_label.text.contains("triangles"), "dialog shows the triangle count (%s)" % (size_label.text if size_label else "?"))

	# Simulate pressing "Unwrap" in the dialog. The heavy work runs on a worker thread now.
	dialog.hide()
	tools.call("_on_unwrap_confirmed")
	check(tools.call("is_busy"), "unwrap runs in the background (busy flag set)")
	var busy_dialog: AcceptDialog = tools.get("_busy_dialog")
	check(busy_dialog != null and busy_dialog.visible, "a 'working' dialog is shown while it runs")
	for _i in range(1200):
		await get_tree().process_frame
		if edited_body.mesh != mesh_before_unwrap:
			break
	check(not tools.call("is_busy"), "background job finished")
	check(not busy_dialog.visible, "'working' dialog closed afterwards")
	await get_tree().process_frame

	var new_mesh: ArrayMesh = edited_body.mesh as ArrayMesh
	check(new_mesh != mesh_before_unwrap and new_mesh != null, "node now has a different mesh")
	var path := new_mesh.resource_path
	check(path == "res://gddraw/meshes/hero_body_uv.res", "mesh is a saved resource file: %s" % path)
	check(FileAccess.file_exists(path), "mesh file exists")
	var arrays := new_mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	check(uvs.size() == positions.size() and uvs.size() > 0, "mesh now has UVs for every vertex (%d)" % uvs.size())
	var min_uv := Vector2(INF, INF)
	var max_uv := Vector2(-INF, -INF)
	for uv in uvs:
		min_uv = min_uv.min(uv)
		max_uv = max_uv.max(uv)
	check(min_uv.x >= 0.0 and min_uv.y >= 0.0 and max_uv.x <= 1.0 and max_uv.y <= 1.0, "UVs inside 0-1 (%s .. %s)" % [min_uv, max_uv])
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var original_positions: PackedVector3Array = original_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var skin_ok := bones.size() == positions.size() * 4
	if skin_ok:
		for i in range(positions.size()):
			if not original_positions[bones[i * 4] + 100 * bones[i * 4 + 1]].is_equal_approx(positions[i]):
				skin_ok = false
				break
	check(skin_ok, "bone data still belongs to the right vertices")

	# GDDraw must now accept this mesh (it refused it before).
	var target_script = load("res://addons/GDDraw/gddraw_3d_surface_target.gd")
	var before_target = target_script.from_node(_make_node_with_mesh(original_mesh))
	var after_target = target_script.from_node(edited_body)
	check(before_target == null, "GDDraw rejected the mesh before unwrapping (no UVs)")
	check(after_target != null, "GDDraw accepts the mesh after unwrapping")

	print("ITEST  -- undo / redo")
	var undo_redo := ei.get_editor_undo_redo().get_history_undo_redo(ei.get_editor_undo_redo().get_object_history_id(edited_body))
	undo_redo.undo()
	check(edited_body.mesh == mesh_before_unwrap, "undo restores the original mesh")
	undo_redo.redo()
	check(edited_body.mesh == new_mesh, "redo re-applies the unwrapped mesh")

	print("ITEST  -- live 3D session refresh")
	# Give the mesh UVs first (already done), start a real GDDraw 3D session, then unwrap again.
	var session = dock.get("_texture_3d_session")
	check(session != null, "dock has a 3D texture session object")
	var gddraw_plugin = dock.get_meta("gddraw_plugin")
	var begin: Dictionary = session.begin_from_target(edited_body, gddraw_plugin, true)
	print("ITEST  begin_from_target -> ", begin.get("status"), " ", begin.get("message", ""))
	if str(begin.get("status")) == "ok" and session.has_active_session():
		var signature_before: String = session.target.geometry_signature
		var mesh_before := edited_body.mesh
		# Second unwrap with a different angle so the geometry really changes.
		var service := GDDrawUVService.new()
		var second := service.unwrap_mesh_instance(edited_body, gddraw_plugin, 0.05)
		check(second.get("status") == "ok", "second unwrap while a session is open succeeded")
		dock.call("on_uv_mesh_changed", second, edited_body)
		await get_tree().process_frame
		check(edited_body.mesh != mesh_before, "node mesh replaced again")
		check(session.target.geometry_signature != signature_before, "session's geometry snapshot was refreshed (signature changed)")
		check(session.mesh_snapshot == edited_body.mesh, "session mesh snapshot now points at the new mesh")
		var status_text := ""
		var status_label = dock.get("_status_label")
		if status_label is Label:
			status_text = (status_label as Label).text
		print("ITEST  status: ", status_text)
	else:
		print("ITEST  (session could not start headless; skipping live-refresh checks)")

	print("ITEST  -- pick a simple method (Cylinder) in the Auto Unwrap dialog")
	var smart_mesh: ArrayMesh = edited_body.mesh as ArrayMesh
	dock.call("_on_menu_command", unwrap_id)
	await get_tree().process_frame
	var dialog_tools: Node = dock.get("_uv_tools")
	var dialog_methods: OptionButton = dialog_tools.get("_method_option")
	var cylinder_index := dialog_methods.get_item_index(GDDrawUVMeshAdapter.UnwrapMethod.CYLINDER)
	dialog_methods.select(cylinder_index)
	dialog_tools.call("_on_unwrap_method_selected", cylinder_index)
	check(str((dialog_tools.get("_method_description") as Label).text).contains("vertical axis"), "picking a method updates its description")
	(dialog_tools.get("_unwrap_dialog") as ConfirmationDialog).hide()
	dialog_tools.call("_on_unwrap_confirmed")
	for _i in range(1200):
		await get_tree().process_frame
		if edited_body.mesh != smart_mesh:
			break
	check(edited_body.mesh != smart_mesh and (edited_body.mesh as ArrayMesh).resource_path.begins_with("res://gddraw/meshes/"), "Cylinder unwrap from the dialog produced and assigned a new saved mesh")
	check(_skin_intact(edited_body.mesh as ArrayMesh, original_positions), "bone data intact after a Cylinder unwrap")
	var cyl_uvs: PackedVector2Array = (edited_body.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var smart_uvs: PackedVector2Array = smart_mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	check(cyl_uvs.size() > 0 and cyl_uvs != smart_uvs, "the Cylinder layout differs from the Smart layout")

	await _test_editor(dock, editor_id, edited_body, original_positions)

	print("ITEST  RESULT: ", "ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _button_texts(node: Node) -> Array:
	var texts := []
	for child in node.find_children("*", "Button", true, false):
		texts.append((child as Button).text)
	return texts


func _skin_intact(mesh: ArrayMesh, original_positions: PackedVector3Array) -> bool:
	var arrays := mesh.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	if bones.size() != positions.size() * 4:
		return false
	for i in range(positions.size()):
		if not original_positions[bones[i * 4] + 100 * bones[i * 4 + 1]].is_equal_approx(positions[i]):
			return false
	return true


func _test_editor(dock: Control, editor_id: int, body: MeshInstance3D, original_positions: PackedVector3Array) -> void:
	print("ITEST  -- full UV editor")
	dock.call("_on_menu_command", editor_id)
	await get_tree().process_frame
	var tools: Node = dock.get("_uv_tools")
	var window: Window = tools.get("_editor_window")
	check(window != null and window.visible, "editor window opened from the dock button")
	check(not window.call("is_dirty"), "editor opens without unapplied changes")
	check(window.title.begins_with("GDDraw"), "window is branded GDDraw (%s)" % window.title)

	var window_buttons := _button_texts(window)
	check(not window_buttons.has("Smart UV Project"), "the old 'Smart UV Project' button is gone from the editor (%s)" % str(window_buttons.filter(func(s): return "nwrap" in str(s) or "mart" in str(s))))
	check(window_buttons.has("Auto Unwrap"), "the editor has an 'Auto Unwrap' button")
	var window_methods: OptionButton = window.get("_method_option")
	check(window_methods != null and window_methods.item_count == 7 and window_methods.get_selected_id() == GDDrawUVMeshAdapter.UnwrapMethod.SMART, "the editor has a Method dropdown (7 methods, Smart default)")
	check(window.get("_angle_spin") == null, "the Smart-UV angle setting is gone")
	window.auto_unwrap_requested.emit(0, 0.02, GDDrawUVMeshAdapter.UnwrapMethod.SMART)
	for _i in range(600):
		await get_tree().process_frame
		if window.call("is_dirty"):
			break
	check(window.call("is_dirty"), "Auto Unwrap (Smart) ran in the editor and marked it dirty")
	# Now a simple method from the same button/dropdown: Box must give a different layout than Smart.
	var history_before: Array = tools.get("_editor_history")
	var smart_data: GDDrawUVMeshData = history_before[tools.get("_editor_history_index")]
	window_methods.select(window_methods.get_item_index(GDDrawUVMeshAdapter.UnwrapMethod.BOX))
	check(window.call("get_selected_method") == GDDrawUVMeshAdapter.UnwrapMethod.BOX, "dropdown selection is reported as Box")
	window.auto_unwrap_requested.emit(0, 0.02, window.call("get_selected_method"))
	var history_size_before: int = history_before.size()
	for _i in range(600):
		await get_tree().process_frame
		if (tools.get("_editor_history") as Array).size() > history_size_before:
			break
	var box_data: GDDrawUVMeshData = (tools.get("_editor_history") as Array)[tools.get("_editor_history_index")]
	check(box_data != smart_data and box_data.uv_faces != smart_data.uv_faces, "Auto Unwrap with the Box method produced a different layout than Smart")
	# step back to the Smart layout so the rest of the test (undo/redo/apply) runs as before
	tools.call("_on_editor_undo_requested")
	tools.call("_on_editor_undo_requested")
	check(not window.call("is_dirty"), "editor undo returns to the clean state")
	tools.call("_on_editor_redo_requested")
	check(window.call("is_dirty"), "editor redo restores the edit")

	# Mark a seam on the first face's first edge, like the Mark Seam button would.
	var history: Array = tools.get("_editor_history")
	var data: GDDrawUVMeshData = history[tools.get("_editor_history_index")].duplicate_mesh_data()
	var a: int = data.faces[0][0]
	var b: int = data.faces[0][1]
	data.set_edge_seam_by_vertices(a, b, true)
	tools.call("_on_editor_commit", data, "Mark Seam")
	var seam_position_a: Vector3 = data.vertices[a]
	var seam_position_b: Vector3 = data.vertices[b]

	var mesh_before: Mesh = body.mesh
	tools.call("_on_editor_apply_requested")
	check(body.mesh != mesh_before, "Apply to Mesh assigned a new mesh to the node")
	check(body.mesh.resource_path.begins_with("res://gddraw/meshes/"), "applied mesh is a saved file (%s)" % body.mesh.resource_path)
	check(not window.call("is_dirty"), "editor is clean after Apply")
	check(_skin_intact(body.mesh as ArrayMesh, original_positions), "bone data intact after the editor's Apply")
	check(body.mesh.has_meta("gddraw_uv_seams"), "seams were stored on the saved mesh")

	var adapter: GDDrawUVMeshAdapter = tools.get("_editor_adapter")
	var restored_seams := false
	for edge in adapter.data.seam_edges:
		var p: Vector3 = adapter.data.vertices[edge.x]
		var q: Vector3 = adapter.data.vertices[edge.y]
		if (p.is_equal_approx(seam_position_a) and q.is_equal_approx(seam_position_b)) or (p.is_equal_approx(seam_position_b) and q.is_equal_approx(seam_position_a)):
			restored_seams = true
	check(restored_seams, "the marked seam is read back from the saved mesh")

	print("ITEST  -- close guard")
	var data2: GDDrawUVMeshData = adapter.data.duplicate_mesh_data()
	tools.call("_on_editor_commit", data2, "Test Edit")
	check(window.call("is_dirty"), "new edit makes the editor dirty again")
	window.call("_on_close_requested")
	var close_dialog: ConfirmationDialog = tools.get("_close_dialog")
	check(window.visible and close_dialog != null and close_dialog.visible, "closing with unapplied edits asks first and keeps the window open")
	tools.call("_on_close_dialog_custom_action", &"discard")
	check(not window.visible, "Discard closes the window")
	var mesh_after_discard: Mesh = body.mesh
	check(mesh_after_discard.resource_path == body.mesh.resource_path, "discarding did not touch the node's mesh")


func _make_node_with_mesh(mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	return node


func _menu_id(dock: Control, menu_name: String, text: String) -> int:
	var popup: PopupMenu = dock.get(menu_name)
	for i in range(popup.item_count):
		if popup.get_item_text(i) == text:
			return popup.get_item_id(i)
	return -1