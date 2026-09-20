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
		print("NMTEST  TIMEOUT")
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
		print("NMTEST  PASS  ", message)
	else:
		_fail += 1
		print("NMTEST  FAIL  ", message)


func _make_mesh(node_name: String, with_material: bool, texture_path: String) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, CapsuleMesh.new().get_mesh_arrays())
	if with_material:
		var material := StandardMaterial3D.new()
		var image := Image.create_empty(512, 512, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.5, 0.5, 0.5, 1))
		image.save_png(ProjectSettings.globalize_path(texture_path))
		var texture := ImageTexture.create_from_image(image)
		texture.set_meta("gddraw_source_path", texture_path)
		material.albedo_texture = texture
		mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	return instance


func _channels_for(layer_session, node_name: String) -> PackedStringArray:
	var result := PackedStringArray()
	for target in layer_session.paint_targets:
		if str(target.binding.get("source_name", "")) == node_name or str(target.label).contains(node_name):
			result.push_back(str(target.channel_id))
	return result


func _dialog_visible(dock: Control) -> bool:
	return (dock.get("_create_3d_texture_dialog") as ConfirmationDialog).visible


func _load_model(dock: Control, mesh: Node3D, auto_discard := true) -> void:
	var roots: Array[Node] = [mesh]
	dock.call("_open_3d_scope_picker", roots)
	await _wait(3)
	dock.call("_confirm_3d_session_picker")
	await _wait(30)
	var unsaved: Window = dock.get("_save_3d_batch_dialog")
	if unsaved and unsaved.visible and auto_discard:
		unsaved.hide()
		dock.call("_continue_pending_session_transition")
		await _wait(30)


func _run() -> void:
	var ei := get_editor_interface()
	var dock := _find_dock()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ms"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tex"))
	var ramp := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(0, 256, 4):
		for x in range(0, 256, 4):
			ramp.fill_rect(Rect2i(x, y, 4, 4), Color(float(x) / 256.0, float(y) / 256.0, 0.5, 1.0))
	for n in ["albedo", "height", "normal"]:
		ramp.save_png(ProjectSettings.globalize_path("res://ms/nm_%s.png" % n))
	var root := Node3D.new()
	root.name = "NmRoot"
	var scene := PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, "res://nm_scene.tscn")
	ei.open_scene_from_path("res://nm_scene.tscn")
	await _wait(90)
	var edited_root := ei.get_edited_scene_root()
	var first := _make_mesh("First", true, "res://tex/nm_first.png")
	var second := _make_mesh("Second", true, "res://tex/nm_second.png")
	var third := _make_mesh("Third", false, "")
	for mesh in [first, second, third]:
		edited_root.add_child(mesh)
		mesh.owner = edited_root
	await _wait(5)
	dock.call("_select_canvas_mode", 1)
	await _wait(2)
	(dock.get("_placeholder_texture_timer") as Timer).stop()
	dock.call("_load_material_brush_material", "res://ms/nm_albedo.png")
	dock.set("_material_companion_channels", PackedStringArray(["height", "normal"]))
	dock.call("_refresh_material_companion_menu")
	(dock.get("_material_button") as Button).button_pressed = true
	await _wait(3)

	print("NMTEST  == model 1 (has a material with an albedo texture), Also paint = height + normal")
	await _load_model(dock, first)
	var dialog_first := _dialog_visible(dock)
	print("NMTEST  dialog visible: ", dialog_first, " text: ", (dock.get("_create_3d_texture_dialog") as ConfirmationDialog).dialog_text.replace("\n", " / "))
	if dialog_first:
		(dock.get("_create_3d_texture_dialog") as ConfirmationDialog).hide()
		dock.call("_create_missing_3d_texture")
		await _wait(200)
	var layer_session = dock.get("_layer_session")
	print("NMTEST  targets: ", _channels_for(layer_session, "First"))
	_check(_channels_for(layer_session, "First").has("height") and _channels_for(layer_session, "First").has("normal"), "model 1 has height and normal targets")

	print("NMTEST  == paint on model 1 so the session has unsaved changes, then load model 2")
	var canvas = dock.get("_canvas")
	canvas.brush_size = 64
	var triangle := PackedVector2Array([Vector2(0.02, 0.02), Vector2(0.98, 0.02), Vector2(0.02, 0.98)])
	canvas.begin_uv_triangle_stroke(Vector2(0.4, 0.3), triangle)
	canvas.continue_uv_triangle_stroke(Vector2(0.42, 0.31), triangle, true)
	canvas.end_uv_triangle_stroke()
	await _wait(20)
	await _load_model(dock, second)
	var save_dialog: Window = dock.get("_save_3d_batch_dialog")
	print("NMTEST  unsaved-changes dialog visible: ", save_dialog.visible if save_dialog else "none")
	if save_dialog and save_dialog.visible:
		save_dialog.hide()
		dock.call("_continue_pending_session_transition")
		await _wait(30)
	var dialog_second := _dialog_visible(dock)
	print("NMTEST  create dialog visible: ", dialog_second, " text: ", (dock.get("_create_3d_texture_dialog") as ConfirmationDialog).dialog_text.replace("\n", " / "))
	_check(dialog_second, "model 2: the 'Create Missing 3D Textures' dialog pops up")
	if dialog_second:
		(dock.get("_create_3d_texture_dialog") as ConfirmationDialog).hide()
		dock.call("_create_missing_3d_texture")
		await _wait(200)
	layer_session = dock.get("_layer_session")
	print("NMTEST  targets: ", _channels_for(layer_session, "Second"))
	_check(_channels_for(layer_session, "Second").has("height") and _channels_for(layer_session, "Second").has("normal"), "model 2 ends up with height and normal targets")

	print("NMTEST  == painting right after the textures were created")
	canvas = dock.get("_canvas")
	var active_before = layer_session.get_active_target()
	print("NMTEST  active target: ", active_before.label, " (", active_before.channel_id, ")")
	canvas.begin_uv_triangle_stroke(Vector2(0.6, 0.2), triangle)
	canvas.continue_uv_triangle_stroke(Vector2(0.62, 0.21), triangle, true)
	canvas.end_uv_triangle_stroke()
	await _wait(20)
	layer_session = dock.get("_layer_session")
	var painted_channels := PackedStringArray()
	for target in layer_session.paint_targets:
		if str(target.binding.get("source_name", "")) != str(layer_session.get_active_target().binding.get("source_name", "")):
			continue
		var image: Image = target.composite()
		var probe := image.get_pixel(int(0.61 * image.get_width()), int(0.205 * image.get_height()))
		var background := image.get_pixel(int(0.05 * image.get_width()), int(0.95 * image.get_height()))
		print("NMTEST  ", target.channel_id, ": painted pixel ", probe, " background ", background)
		if not probe.is_equal_approx(background):
			painted_channels.push_back(str(target.channel_id))
	_check(painted_channels.has("height") and painted_channels.has("normal"), "the stroke painted height and normal too: " + str(painted_channels))
	print("NMTEST  == model 3: a MeshInstance3D with no material at all (GDDraw creates one)")
	await _load_model(dock, third)
	var dialog3 := _dialog_visible(dock)
	print("NMTEST  dialog visible: ", dialog3)
	_check(dialog3, "model 3: the create dialog pops up (no more 'assign a material first' refusal)")
	if dialog3:
		(dock.get("_create_3d_texture_dialog") as ConfirmationDialog).hide()
		dock.call("_create_missing_3d_texture")
		await _wait(300)
	_check(third.get_surface_override_material(0) is StandardMaterial3D, "and a StandardMaterial3D was created for it")
	print("NMTEST  == model 4: a CSG box with no material (GDDraw creates the material itself)")
	var csg := CSGBox3D.new()
	csg.name = "Csg"
	edited_root.add_child(csg)
	csg.owner = edited_root
	await _wait(5)
	await _load_model(dock, csg)
	var rounds := 0
	while _dialog_visible(dock) and rounds < 4:
		rounds += 1
		print("NMTEST  dialog ", rounds, ": ", (dock.get("_create_3d_texture_dialog") as ConfirmationDialog).dialog_text.replace("\n", " / ").replace("â€¢", "*").replace("Â·", "-"))
		(dock.get("_create_3d_texture_dialog") as ConfirmationDialog).hide()
		dock.call("_create_missing_3d_texture")
		await _wait(200)
	layer_session = dock.get("_layer_session")
	var csg_channels := _channels_for(layer_session, "Csg")
	print("NMTEST  targets: ", csg_channels)
	_check(rounds >= 1, "a create dialog popped up for the CSG box")
	_check(csg_channels.has("albedo") and not csg_channels.has("height"), "the CSG box gets its albedo texture (CSG shapes cannot have other channels)")
	var notice4 := str(dock.get("_material_last_notice"))
	print("NMTEST  notice: ", notice4)
	_check(notice4.contains("Csg") and notice4.contains("CSG"), "and the user is told why Height/Normal are not painted on it")

	print("NMTEST  == model loaded while the Material Brush is NOT the active tool, then the tool is picked")
	var fifth := _make_mesh("Fifth", true, "res://tex/nm_fifth.png")
	edited_root.add_child(fifth)
	fifth.owner = edited_root
	await _wait(5)
	(dock.get("_material_button") as Button).button_pressed = false
	await _wait(3)
	await _load_model(dock, fifth)
	var save_dialog5: Window = dock.get("_save_3d_batch_dialog")
	if save_dialog5 and save_dialog5.visible:
		save_dialog5.hide()
		dock.call("_continue_pending_session_transition")
		await _wait(30)
	print("NMTEST  targets before choosing the tool: ", _channels_for(dock.get("_layer_session"), "Fifth"))
	(dock.get("_create_3d_texture_dialog") as ConfirmationDialog).hide()
	(dock.get("_material_button") as Button).button_pressed = true
	await _wait(30)
	var dialog_fifth := _dialog_visible(dock)
	print("NMTEST  dialog after choosing the Material Brush: ", dialog_fifth)
	_check(dialog_fifth, "choosing the Material Brush pops the create dialog for the loaded model")
	print("NMTEST  == the after-load check itself: channels ticked later are noticed, and a declined offer is not repeated")
	dock.set("_material_companion_channels", PackedStringArray())
	(dock.get("_create_3d_texture_dialog") as ConfirmationDialog).hide()
	var sixth := _make_mesh("Sixth", true, "res://tex/nm_sixth.png")
	edited_root.add_child(sixth)
	sixth.owner = edited_root
	await _wait(5)
	await _load_model(dock, sixth)
	var sd6: Window = dock.get("_save_3d_batch_dialog")
	if sd6 and sd6.visible:
		sd6.hide()
		dock.call("_continue_pending_session_transition")
		await _wait(30)
	_check(_channels_for(dock.get("_layer_session"), "Sixth") == PackedStringArray(["albedo"]), "model 6 opened with albedo only (no Also paint channels ticked)")
	(dock.get("_create_3d_texture_dialog") as ConfirmationDialog).hide()
	dock.set("_material_companion_channels", PackedStringArray(["height", "normal"]))
	dock.set("_material_companion_offered", "")
	dock.call("_check_material_companions_after_load")
	await _wait(30)
	_check(_dialog_visible(dock), "the after-load check pops the create dialog for the missing channels")
	(dock.get("_create_3d_texture_dialog") as ConfirmationDialog).hide()
	dock.call("_cancel_missing_3d_texture")
	_check(str(dock.get("_material_last_notice")).contains("canceled"), "declining tells the user those channels will not be painted")
	dock.call("_check_material_companions_after_load")
	await _wait(30)
	_check(not _dialog_visible(dock), "and the same offer is not repeated straight away")
	print("NMTEST  == Also paint follows the selected material")
	(dock.get("_create_3d_texture_dialog") as ConfirmationDialog).hide()
	dock.set("_material_companion_channels", PackedStringArray(["emission"]))
	dock.set("_material_known_channels", PackedStringArray())
	dock.call("_load_material_brush_material", "res://ms/nm_albedo.png")
	await _wait(30)
	var ticks: PackedStringArray = dock.get("_material_companion_channels")
	print("NMTEST  ticks after picking a texture set with albedo+height+normal: ", ticks, "  notice: ", dock.get("_material_last_notice"))
	_check(ticks == PackedStringArray(["height", "normal"]), "picking a material ticks exactly its channels except the painted one (albedo)")
	_check(str(dock.get("_material_last_notice")).contains("height") or str(dock.get("_material_last_notice")).to_lower().contains("height"), "and says so")
	var plain := StandardMaterial3D.new()
	plain.albedo_texture = ResourceLoader.load("res://ms/nm_albedo.png") as Texture2D
	ResourceSaver.save(plain, "res://ms/nm_plain.tres")
	await _wait(5)
	dock.call("_load_material_brush_material", "res://ms/nm_plain.tres")
	await _wait(5)
	ticks = dock.get("_material_companion_channels")
	print("NMTEST  ticks after picking an albedo-only material: ", ticks)
	_check(ticks.is_empty(), "an albedo-only material ticks nothing (the old ticks are cleared)")
	var live_material: StandardMaterial3D = (dock.get("_material_set")).source_material
	live_material.roughness_texture = ResourceLoader.load("res://ms/nm_height.png") as Texture2D
	await _wait(60)
	dock.call("_poll_material_brush_material")
	await _wait(5)
	ticks = dock.get("_material_companion_channels")
	print("NMTEST  ticks after adding a roughness texture to that material in the Inspector: ", ticks)
	_check(ticks == PackedStringArray(["roughness"]), "a channel added to the material later is ticked as it appears")
	dock.call("_toggle_companion_for_test") if dock.has_method("_toggle_companion_for_test") else null
	dock.set("_material_companion_channels", PackedStringArray(["emission"]))
	dock.set("_material_restoring", true)
	dock.call("_load_material_brush_material", "res://ms/nm_albedo.png")
	dock.set("_material_restoring", false)
	await _wait(5)
	ticks = dock.get("_material_companion_channels")
	_check(ticks == PackedStringArray(["emission"]), "the remembered material coming back at start-up keeps the remembered ticks: " + str(ticks))
	print("NMTEST  == picking a material with an open session asks for the missing textures")
	dock.set("_material_companion_channels", PackedStringArray())
	dock.set("_material_known_channels", PackedStringArray())
	(dock.get("_create_3d_texture_dialog") as ConfirmationDialog).hide()
	dock.set("_material_autotick_mode", "")
	dock.call("_load_material_brush_material", "res://ms/nm_albedo.png")
	await _wait(60)
	var wanted_dialog := _dialog_visible(dock)
	print("NMTEST  dialog: ", wanted_dialog, "  ", (dock.get("_create_3d_texture_dialog") as ConfirmationDialog).dialog_text.replace("\n", " / ").replace("â€¢", "*").replace("Â·", "-"))
	_check(wanted_dialog, "choosing a material with height+normal on an object that lacks them pops the create dialog")
	print("NMTEST  RESULT: ", "ALL PASSED" if _fail == 0 else "%d FAILED" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)