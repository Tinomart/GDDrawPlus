@tool
extends EditorPlugin

var _frames := 0
var _started := false
var _fail := 0


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 240 and not _started:
		_started = true
		_run()
	if _frames == 16000:
		print("NOMTEST  TIMEOUT")
		get_tree().quit(2)


func _find_dock() -> Control:
	for control in get_editor_interface().get_base_control().find_children("GDDraw", "Control", true, false):
		if control.has_meta("gddraw_bottom_panel_dock"):
			return control
	return null


func _wait(frames := 4) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		print("NOMTEST  PASS  ", message)
	else:
		_fail += 1
		print("NOMTEST  FAIL  ", message)


func _dialog(dock: Control) -> ConfirmationDialog:
	return dock.get("_create_3d_texture_dialog")


func _load_model(dock: Control, node: Node3D) -> void:
	var roots: Array[Node] = [node]
	dock.call("_open_3d_scope_picker", roots)
	await _wait(3)
	dock.call("_confirm_3d_session_picker")
	await _wait(40)
	var unsaved: Window = dock.get("_save_3d_batch_dialog")
	if unsaved and unsaved.visible:
		unsaved.hide()
		dock.call("_continue_pending_session_transition")
		await _wait(40)


func _confirm_creation(dock: Control) -> int:
	var rounds := 0
	while _dialog(dock).visible and rounds < 4:
		rounds += 1
		print("NOMTEST  dialog ", rounds, ": ", _dialog(dock).dialog_text.replace("\n", " / ").replace("â€¢", "*").replace("Â·", "-"))
		_dialog(dock).hide()
		dock.call("_create_missing_3d_texture")
		await _wait(300)
	return rounds


func _channels(dock: Control, node_name: String) -> PackedStringArray:
	var result := PackedStringArray()
	var layer_session = dock.get("_layer_session")
	if layer_session:
		for target in layer_session.paint_targets:
			if str(target.binding.get("source_name", "")) == node_name or str(target.label).begins_with(node_name):
				result.push_back(str(target.channel_id))
	return result


func _stroke(canvas, uv: Vector2) -> void:
	var triangle := PackedVector2Array([Vector2(0.02, 0.02), Vector2(0.98, 0.02), Vector2(0.02, 0.98)])
	canvas.begin_uv_triangle_stroke(uv, triangle)
	canvas.continue_uv_triangle_stroke(uv + Vector2(0.02, 0.01), triangle, true)
	canvas.end_uv_triangle_stroke()


func _run() -> void:
	var ei := get_editor_interface()
	var dock := _find_dock()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ms"))
	var ramp := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(0, 256, 4):
		for x in range(0, 256, 4):
			ramp.fill_rect(Rect2i(x, y, 4, 4), Color(float(x) / 256.0, float(y) / 256.0, 0.5, 1.0))
	for n in ["albedo", "height", "normal"]:
		ramp.save_png(ProjectSettings.globalize_path("res://ms/nom_%s.png" % n))
	var root := Node3D.new()
	root.name = "NomRoot"
	var scene := PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, "res://nom_scene.tscn")
	ei.open_scene_from_path("res://nom_scene.tscn")
	await _wait(90)
	var edited_root := ei.get_edited_scene_root()
	var cylinder := MeshInstance3D.new()
	cylinder.name = "Cylinder"
	cylinder.mesh = CylinderMesh.new()
	var two_surfaces := MeshInstance3D.new()
	two_surfaces.name = "TwoSurfaces"
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, CapsuleMesh.new().get_mesh_arrays())
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
	two_surfaces.mesh = array_mesh
	var third := MeshInstance3D.new()
	third.name = "Sphere"
	third.mesh = SphereMesh.new()
	for m in [cylinder, two_surfaces, third]:
		edited_root.add_child(m)
		m.owner = edited_root
	await _wait(5)
	dock.call("_select_canvas_mode", 1)
	await _wait(2)
	(dock.get("_placeholder_texture_timer") as Timer).stop()

	print("NOMTEST  == a MeshInstance3D with a CylinderMesh and NO material")
	_check(cylinder.get_active_material(0) == null, "the cylinder has no material to begin with")
	var roots: Array[Node] = [cylinder]
	dock.call("_open_3d_scope_picker", roots)
	await _wait(3)
	var disc: Dictionary = dock.get("_session_picker_layer_discovery")
	print("NOMTEST  picker: status=", disc.get("status"), " message=", disc.get("message"), " targets=", (disc.get("targets", []) as Array).size())
	_check(str(disc.get("status")) == "ok" and (disc.get("targets", []) as Array).size() == 1, "the picker lists it as a target instead of refusing")
	dock.call("_confirm_3d_session_picker")
	await _wait(40)
	_check(_dialog(dock).visible, "GDDraw asks whether to create the missing material and texture")
	var rounds := await _confirm_creation(dock)
	print("NOMTEST  dialogs: ", rounds, "  channels: ", _channels(dock, "Cylinder"))
	_check(_channels(dock, "Cylinder").has("albedo"), "the session opens with an albedo target")
	var created := cylinder.get_surface_override_material(0) as StandardMaterial3D
	_check(created != null and created.albedo_texture != null, "a StandardMaterial3D with an albedo texture was assigned as a surface override")
	var path := str(created.albedo_texture.get_meta("gddraw_source_path", "")) if created and created.albedo_texture else ""
	_check(path.begins_with("res://") and FileAccess.file_exists(path), "the PNG exists on disk: " + path)
	_check(cylinder.mesh.get("material") == null, "the mesh resource itself was not modified")
	var canvas = dock.get("_canvas")
	canvas.brush_color = Color(1, 0, 0, 1)
	canvas.brush_size = 40
	_stroke(canvas, Vector2(0.4, 0.4))
	await _wait(20)
	var image: Image = dock.call("_get_canvas_output_image")
	var px := image.get_pixel(int(0.41 * image.get_width()), int(0.405 * image.get_height()))
	_check(px.r > 0.8 and px.g < 0.3, "painting works on it (%s)" % str(px))

	print("NOMTEST  == a mesh with two surfaces, neither has a material")
	await _load_model(dock, two_surfaces)
	var rounds2 := await _confirm_creation(dock)
	var ls = dock.get("_layer_session")
	var count := 0
	for target in ls.paint_targets:
		if str(target.binding.get("source_name", "")) == "TwoSurfaces" or str(target.label).begins_with("TwoSurfaces"):
			count += 1
	print("NOMTEST  dialogs: ", rounds2, "  targets for TwoSurfaces: ", count)
	_check(count == 2, "both surfaces got a target")
	_check(two_surfaces.get_surface_override_material(0) is StandardMaterial3D and two_surfaces.get_surface_override_material(1) is StandardMaterial3D, "and both got their own material")

	print("NOMTEST  == Material Brush with height + normal companions on a mesh with no material")
	dock.set("_material_companion_channels", PackedStringArray(["height", "normal"]))
	dock.call("_refresh_material_companion_menu")
	(dock.get("_material_button") as Button).button_pressed = true
	await _wait(3)
	dock.call("_load_material_brush_material", "res://ms/nom_albedo.png")
	await _wait(10)
	dock.set("_material_companion_channels", PackedStringArray(["height", "normal"]))
	await _load_model(dock, third)
	var rounds3 := await _confirm_creation(dock)
	print("NOMTEST  dialogs: ", rounds3, "  channels: ", _channels(dock, "Sphere"))
	_check(rounds3 >= 1, "a create dialog came up")
	_check(_channels(dock, "Sphere").has("albedo") and _channels(dock, "Sphere").has("height") and _channels(dock, "Sphere").has("normal"), "the sphere ends up with albedo, height and normal (asked in %d step(s))" % rounds3)
	canvas = dock.get("_canvas")
	canvas.brush_size = 40
	_stroke(canvas, Vector2(0.6, 0.2))
	await _wait(20)
	ls = dock.get("_layer_session")
	var painted := PackedStringArray()
	for target in ls.paint_targets:
		if not (str(target.binding.get("source_name", "")) == "Sphere" or str(target.label).begins_with("Sphere")):
			continue
		var img: Image = target.composite()
		var a := img.get_pixel(int(0.61 * img.get_width()), int(0.205 * img.get_height()))
		var b := img.get_pixel(int(0.05 * img.get_width()), int(0.95 * img.get_height()))
		if not a.is_equal_approx(b):
			painted.push_back(str(target.channel_id))
	_check(painted.has("height") and painted.has("normal"), "one stroke painted the extra channels too: " + str(painted))
	print("NOMTEST  == UV tools on a built-in CylinderMesh (a fresh one, no session)")
	var fresh := MeshInstance3D.new()
	fresh.name = "FreshCylinder"
	fresh.mesh = CylinderMesh.new()
	edited_root.add_child(fresh)
	fresh.owner = edited_root
	await _wait(5)
	dock.call("_clear_3d_texture_session_state", false)
	await _wait(10)
	ei.get_selection().clear()
	ei.get_selection().add_node(fresh)
	await _wait(5)
	dock.call("_ensure_uv_tools")
	var tools = dock.get("_uv_tools")
	var results := []
	tools.connect("unwrap_finished", func(result: Dictionary, _node): results.push_back(result))
	dock.call("_on_uv_menu_auto_unwrap")
	await _wait(30)
	var unwrap_dialog: ConfirmationDialog = null
	for child in tools.get_children():
		if child is ConfirmationDialog and str(child.title).begins_with("Auto-Unwrap"):
			unwrap_dialog = child
	_check(unwrap_dialog != null and unwrap_dialog.visible, "Auto Unwrap opens its dialog for a CylinderMesh")
	if unwrap_dialog:
		unwrap_dialog.hide()
	await _wait(3)
	tools.call("_on_unwrap_confirmed")
	for k in range(500):
		await _wait(5)
		if not results.is_empty():
			break
	print("NOMTEST  unwrap result: ", results[0].get("status") if not results.is_empty() else "none", " | ", results[0].get("message") if not results.is_empty() else "")
	_check(not results.is_empty() and str(results[0].get("status")) == "ok", "the unwrap finishes and assigns a new mesh")
	dock.call("_on_uv_menu_editor")
	await _wait(60)
	var editor_visible := false
	for window in ei.get_base_control().find_children("*", "Window", true, false):
		if window.visible and str(window.title).contains("UV Editor"):
			editor_visible = true
	_check(editor_visible, "the UV Editor opens for it")
	print("NOMTEST  RESULT: ", "ALL PASSED" if _fail == 0 else "%d FAILED" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)