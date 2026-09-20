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
	if _frames == 12000:
		print("SCTEST  TIMEOUT")
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
		print("SCTEST  PASS  ", message)
	else:
		_fail += 1
		print("SCTEST  FAIL  ", message)


func _menu_disabled(dock: Control, command_name: String) -> bool:
	var menu: PopupMenu = dock.get("_image_menu")
	var commands: Dictionary = dock.get_script().get_script_constant_map()["MenuCommand"]
	return menu.is_item_disabled(menu.get_item_index(int(commands[command_name])))


func _menu_text(dock: Control, command_name: String) -> String:
	var menu: PopupMenu = dock.get("_image_menu")
	var commands: Dictionary = dock.get_script().get_script_constant_map()["MenuCommand"]
	return menu.get_item_text(menu.get_item_index(int(commands[command_name])))


func _sizes(layer_session) -> Array:
	var result := []
	for target in layer_session.paint_targets:
		result.push_back(target.size)
	return result


func _run() -> void:
	var ei := get_editor_interface()
	var dock := _find_dock()
	var size := 2048
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ms"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tex"))
	var ramp := Image.create_empty(512, 512, false, Image.FORMAT_RGBA8)
	for y in range(0, 512, 4):
		for x in range(0, 512, 4):
			ramp.fill_rect(Rect2i(x, y, 4, 4), Color(float(x) / 512.0, float(y) / 512.0, 0.5, 1.0))
	ramp.save_png(ProjectSettings.globalize_path("res://ms/sc_albedo.png"))
	ramp.save_png(ProjectSettings.globalize_path("res://ms/sc_roughness.png"))
	ramp.save_png(ProjectSettings.globalize_path("res://ms/sc_emission.png"))
	var albedo := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	albedo.fill(Color(0.5, 0.5, 0.5, 1))
	albedo.save_png(ProjectSettings.globalize_path("res://tex/sc_hero.png"))
	var root := Node3D.new()
	root.name = "ScRoot"
	var scene := PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, "res://sc_scene.tscn")
	ei.open_scene_from_path("res://sc_scene.tscn")
	await _wait(90)
	var edited_root := ei.get_edited_scene_root()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, CapsuleMesh.new().get_mesh_arrays())
	var material := StandardMaterial3D.new()
	var texture := ImageTexture.create_from_image(albedo)
	texture.set_meta("gddraw_source_path", "res://tex/sc_hero.png")
	material.albedo_texture = texture
	mesh.surface_set_material(0, material)
	var hero := MeshInstance3D.new()
	hero.name = "Hero"
	hero.mesh = mesh
	edited_root.add_child(hero)
	hero.owner = edited_root
	await _wait(5)
	dock.call("_select_canvas_mode", 1)
	await _wait(2)
	# keep the placeholder ImageTexture in place so the resized-save branch for ImageTextures is what gets tested
	(dock.get("_placeholder_texture_timer") as Timer).stop()
	print("SCTEST  == before a session")
	_check(_menu_disabled(dock, "IMAGE_SCALE") == false, "Scale Image is enabled with no 3D session")
	dock.call("_load_material_brush_material", "res://ms/sc_albedo.png")
	dock.set("_material_companion_channels", PackedStringArray(["roughness", "emission"]))
	dock.call("_refresh_material_companion_menu")
	(dock.get("_material_button") as Button).button_pressed = true
	await _wait(3)
	var discovery: Dictionary = GDDraw3DLayerDiscovery.new().discover([hero], GDDraw3DLayerDiscovery.Scope.SELECTED_SURFACE, "albedo")
	dock.set("_last_3d_import_roots", [hero])
	dock.call("_begin_3d_layer_session", discovery, true)
	await _wait(200)
	var layer_session = dock.get("_layer_session")
	print("SCTEST  == in a 3D session, targets: ", layer_session.paint_targets.size(), " sizes ", _sizes(layer_session))
	# paint a black stroke so there is content to follow through the scaling
	var canvas = dock.get("_canvas")
	canvas.brush_color = Color(0, 0, 0, 1)
	canvas.brush_size = 96
	var triangle := PackedVector2Array([Vector2(0.02, 0.02), Vector2(0.98, 0.02), Vector2(0.02, 0.98)])
	canvas.begin_uv_triangle_stroke(Vector2(0.2, 0.3), triangle)
	canvas.continue_uv_triangle_stroke(Vector2(0.22, 0.31), triangle, true)
	canvas.end_uv_triangle_stroke()
	await _wait(10)
	var before: Image = dock.call("_get_canvas_output_image")
	var stroke_pixel := Vector2i(int(0.21 * size), int(0.305 * size))
	_check(before.get_pixelv(stroke_pixel).r < 0.25, "the stroke is painted at the start (r=%.2f)" % before.get_pixelv(stroke_pixel).r)
	dock.call("_sync_menu_state")
	_check(_menu_disabled(dock, "IMAGE_SCALE") == false, "Scale Image is ENABLED in a 3D texture session")
	_check(_menu_text(dock, "IMAGE_SCALE") == "Scale Textures…", "and is called Scale Textures… (%s)" % _menu_text(dock, "IMAGE_SCALE"))
	_check(_menu_disabled(dock, "IMAGE_RESIZE_CANVAS") and _menu_disabled(dock, "IMAGE_CROP_RECTANGLE") and _menu_disabled(dock, "IMAGE_TRIM_TRANSPARENT"), "canvas resize / crop / trim stay disabled (they would shift pixels against the UVs)")
	var history = dock.get("_history")
	var target_count: int = layer_session.paint_targets.size()

	print("SCTEST  == the scale dialog")
	var active_id: String = layer_session.active_target_id
	dock.call("_start_scale_image")
	await _wait(2)
	var dialog: ConfirmationDialog = dock.get("_scale_image_dialog")
	var ids: PackedStringArray = dock.get("_scale_context_target_ids")
	_check(bool(dock.get("_scale_workflow_active")) and dialog.visible, "the dialog opens")
	_check(ids.size() == target_count and ids[0] == active_id, "it covers all %d textures of the object, active one first (%s)" % [target_count, str(ids)])
	_check(int((dock.get("_scale_width") as SpinBox).value) == size and (dock.get("_scale_interpolation") as OptionButton).selected == 1, "it starts at the current size with Bilinear")
	var description: Label = dock.get("_scale_description_label")
	_check(description.text.contains("%d textures" % target_count), "the description says how many textures: " + description.text)
	(dock.get("_scale_width") as SpinBox).value = 512
	await _wait(1)
	_check(int((dock.get("_scale_height") as SpinBox).value) == 512, "aspect ratio keeps the height in step")
	var t := Time.get_ticks_usec()
	dock.call("_apply_scale_image")
	print("SCTEST  apply took %.0f ms for %d textures %d -> 512" % [float(Time.get_ticks_usec() - t) / 1000.0, target_count, size])
	await _wait(10)
	_check(_sizes(layer_session).all(func(s): return s == Vector2i(512, 512)), "every texture is now 512x512: " + str(_sizes(layer_session)))
	var after: Image = dock.call("_get_canvas_output_image")
	_check(after.get_size() == Vector2i(512, 512), "the canvas is 512x512")
	var scaled_pixel := Vector2i(int(0.21 * 512), int(0.305 * 512))
	_check(after.get_pixelv(scaled_pixel).r < 0.25, "the stroke followed the scaling (r=%.2f)" % after.get_pixelv(scaled_pixel).r)
	_check(absf(after.get_pixelv(Vector2i(500, 500)).r - 0.5) < 0.03, "untouched areas keep their colour (r=%.2f)" % after.get_pixelv(Vector2i(500, 500)).r)
	var paint_texture: ImageTexture = dock.get("_paint_3d_texture")
	_check(paint_texture != null and Vector2i(paint_texture.get_size()) == Vector2i(512, 512), "the 3D preview texture follows: " + str(paint_texture.get_size() if paint_texture else "none"))
	_check(history.can_undo(), "it is one undoable step")
	_check(_menu_disabled(dock, "IMAGE_SCALE") == false, "the menu is still enabled afterwards")

	print("SCTEST  == undo / redo")
	dock.call("_undo")
	await _wait(6)
	_check(_sizes(layer_session).all(func(s): return s == Vector2i(size, size)), "undo restores %dx%d everywhere: %s" % [size, size, str(_sizes(layer_session))])
	_check((dock.call("_get_canvas_output_image") as Image).get_size() == Vector2i(size, size), "and the canvas")
	paint_texture = dock.get("_paint_3d_texture")
	_check(paint_texture != null and Vector2i(paint_texture.get_size()) == Vector2i(size, size), "and the 3D preview texture: " + str(paint_texture.get_size() if paint_texture else "none"))
	dock.call("_redo")
	await _wait(6)
	_check(_sizes(layer_session).all(func(s): return s == Vector2i(512, 512)), "redo scales again")
	paint_texture = dock.get("_paint_3d_texture")
	_check(paint_texture != null and Vector2i(paint_texture.get_size()) == Vector2i(512, 512), "and the 3D preview texture: " + str(paint_texture.get_size() if paint_texture else "none"))

	print("SCTEST  == painting still works at the new size")
	layer_session = dock.get("_layer_session")
	canvas = dock.get("_canvas")
	canvas.brush_color = Color(1, 0, 0, 1)
	canvas.brush_size = 40
	canvas.begin_uv_triangle_stroke(Vector2(0.7, 0.2), triangle)
	canvas.continue_uv_triangle_stroke(Vector2(0.72, 0.21), triangle, true)
	canvas.end_uv_triangle_stroke()
	await _wait(10)
	var painted: Image = dock.call("_get_canvas_output_image")
	var pixel := Vector2i(int(0.71 * 512), int(0.205 * 512))
	_check(absf(painted.get_pixelv(pixel).r - 0.7) < 0.05 and absf(painted.get_pixelv(pixel).g - 0.2) < 0.05, "a new stroke lands where it should (the material ramp colour for that UV) (%s)" % str(painted.get_pixelv(pixel)))
	_check(_sizes(layer_session).all(func(s): return s == Vector2i(512, 512)), "companion targets stay 512x512 after painting: " + str(_sizes(layer_session)))

	print("SCTEST  == saving a rescaled texture")
	var texture_session = dock.get("_texture_3d_session")
	var path: String = texture_session.texture_path
	var result: Dictionary = texture_session.save_image(dock.call("_get_canvas_output_image"), self)
	print("SCTEST  save result: ", result)
	var saved := Image.load_from_file(ProjectSettings.globalize_path(path))
	_check(saved != null and saved.get_size() == Vector2i(512, 512), "the PNG on disk is 512x512: " + str(saved.get_size() if saved else "none") + " " + path)
	var tex: Texture2D = texture_session.texture
	_check(tex != null and Vector2i(tex.get_size()) == Vector2i(512, 512), "the session texture is 512x512")
	_check(tex != null and str(tex.get_meta("gddraw_source_path", "")) == path, "it remembers the PNG path so the material is not left with an anonymous texture")
	_check(not texture_session.is_dirty(dock.call("_get_canvas_output_image")), "and is clean after saving")
	print("SCTEST  RESULT: ", "ALL PASSED" if _fail == 0 else "%d FAILED" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
