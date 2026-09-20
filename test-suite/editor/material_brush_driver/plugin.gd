@tool
extends EditorPlugin

var failures := 0
var _frames := 0
var _started := false


func check(condition: bool, message: String) -> void:
	if condition:
		print("MBTEST  PASS  ", message)
	else:
		failures += 1
		print("MBTEST  FAIL  ", message)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 240 and not _started:
		_started = true
		_run()
	if _frames == 9000:
		print("MBTEST  TIMEOUT")
		get_tree().quit(2)


func _find_dock() -> Control:
	for control in get_editor_interface().get_base_control().find_children("GDDraw", "Control", true, false):
		if control.has_meta("gddraw_bottom_panel_dock"):
			return control
	return null


func _save_png(path: String, size: Vector2i, fill: Color) -> ImageTexture:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(fill)
	image.save_png(path)
	var texture := ImageTexture.create_from_image(image)
	texture.set_meta("gddraw_source_path", path)
	return texture


func _save_quadrants(path: String, quadrants: Array) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var image := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, quadrants[0])
	image.set_pixel(1, 0, quadrants[1])
	image.set_pixel(0, 1, quadrants[2])
	image.set_pixel(1, 1, quadrants[3])
	image.save_png(ProjectSettings.globalize_path(path))


func _near(a: Color, b: Color, tolerance := 0.05) -> bool:
	return absf(a.r - b.r) <= tolerance and absf(a.g - b.g) <= tolerance and absf(a.b - b.b) <= tolerance and absf(a.a - b.a) <= tolerance


func _stroke(canvas, uv: Vector2) -> Color:
	var triangle := PackedVector2Array([uv + Vector2(-0.08, -0.08), uv + Vector2(0.3, -0.08), uv + Vector2(-0.08, 0.3)])
	canvas.begin_uv_triangle_stroke(uv, triangle)
	canvas.end_uv_triangle_stroke()
	var pixel: Vector2i = canvas.image_pixel_from_uv(uv)
	return canvas.get_image_copy().get_pixel(pixel.x, pixel.y)


func _wait(frames := 4) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _run() -> void:
	var ei := get_editor_interface()
	var dock := _find_dock()
	check(dock != null, "GDDraw dock present")
	if dock == null:
		get_tree().quit(1)
		return

	var red := Color(1, 0, 0, 1)
	var green := Color(0, 1, 0, 1)
	var blue := Color(0, 0, 1, 1)
	var white := Color(1, 1, 1, 1)
	_save_quadrants("res://ms/brick_albedo.png", [red, green, blue, white])
	_save_quadrants("res://ms/brick_roughness.png", [Color(0.1, 0.1, 0.1), Color(0.3, 0.3, 0.3), Color(0.7, 0.7, 0.7), Color(0.9, 0.9, 0.9)])
	_save_quadrants("res://ms/brick_metallic.png", [Color(0.2, 0.2, 0.2), Color(0.4, 0.4, 0.4), Color(0.6, 0.6, 0.6), Color(0.8, 0.8, 0.8)])
	_save_quadrants("res://ms/brick_normal.png", [Color(0.5, 0.5, 1), Color(0.5, 0.5, 1), Color(0.5, 0.5, 1), Color(0.5, 0.5, 1)])
	await _wait(2)

	print("MBTEST  == A) the tool and its options")
	var material_button: Button = dock.get("_material_button")
	var brush_button: Button = dock.get("_brush_button")
	var options: Control = dock.get("_material_options")
	var canvas = dock.get("_canvas")
	check(material_button != null and brush_button != null and options != null and canvas != null, "the dock has a Material Brush button and options")
	if material_button == null or options == null:
		get_tree().quit(1)
		return
	check(material_button.get_parent() == brush_button.get_parent() and material_button.get_index() == brush_button.get_index() + 1, "the button sits in the left tool rail, directly under the Brush")
	check(str(material_button.get_meta("inactive_icon_name")) == "material-brush_0.svg" and str(material_button.get_meta("active_icon_name")) == "material-brush_1.svg", "it has its own icon")
	check(ResourceLoader.exists("res://addons/GDDraw/icons/material-brush/material-brush_0.svg") or FileAccess.file_exists("res://addons/GDDraw/icons/material-brush/material-brush_0.svg"), "the icon file ships with the addon")
	check(options.get_parent() == dock.find_child("Tool Options Bar", true, false), "the options live in the tool options bar")
	check(not options.visible and not material_button.button_pressed and not canvas.material_pixel_source.is_valid(), "off by default: options hidden, canvas hook not set")

	var menu: MenuButton = dock.get("_material_menu")
	check(menu != null and menu.get_parent() == options, "the options have a Material menu")
	check(options.get_index() < dock.get("_brush_options").get_index(), "the material controls come before the brush options in the toolbar")
	# recents are remembered between runs; start from a clean slate
	dock.set("_material_recent", PackedStringArray())
	dock.set("_material_set", null)
	dock.call("_rebuild_material_menu")
	check(menu.text.begins_with("Choose material"), "with no material the menu invites you to choose one: " + menu.text)
	material_button.button_pressed = true
	await _wait(6)
	check(dock.get("_material_set") == null and options.visible, "choosing the tool with no material shows its options")
	check(not dock.get("_material_dialog").visible, "and does not force a file dialog open")
	var menu_popup := menu.get_popup()
	check(menu_popup.visible, "the Material menu opens by itself so New / Open are right there")
	menu_popup.hide()
	var new_index := menu_popup.get_item_index(1)
	var open_index := menu_popup.get_item_index(2)
	check(new_index >= 0 and "New Material" in menu_popup.get_item_text(new_index) and open_index >= 0 and "Open" in menu_popup.get_item_text(open_index), "the menu offers New Material and Open")
	check(menu_popup.is_item_disabled(menu_popup.get_item_index(3)), "Edit is disabled until there is a material")
	brush_button.button_pressed = true
	await _wait(2)

	var loaded: bool = dock.call("_load_material_brush_material", "res://ms/brick_albedo.png")
	check(loaded, "a texture set can be loaded from one of its images")
	var recent: PackedStringArray = dock.get("_material_recent")
	dock.call("_rebuild_material_menu")
	var recent_texts := []
	for i in range(menu_popup.item_count):
		recent_texts.append(menu_popup.get_item_text(i))
	check(recent.size() >= 1 and recent[0] == "res://ms/brick_albedo.png" and "brick" in recent_texts and menu.text.begins_with("brick"), "it is remembered as the most recent material and named on the menu button: " + menu.text)
	check(dock.call("_load_material_brush_material", "res://ms/brick_normal.png") and dock.get("_material_set").has_channel("normal"), "a normal map of the set can be picked and brings the normal channel")
	check(dock.call("_load_material_brush_material", "res://ms/brick_albedo.png"), "and the set is the same when picking its albedo")
	check(dock.get("_material_set") != null and dock.get("_material_set").display_name == "brick", "the brick set is loaded")

	material_button.button_pressed = true
	await _wait(2)
	check(material_button.button_pressed and not brush_button.button_pressed, "the tool button is pressed and the plain Brush is not")
	check(canvas.active_tool == GDDrawCanvasControl.ToolMode.BRUSH and canvas.material_pixel_source.is_valid(), "the canvas is in brush mode with the material hook set")
	check(options.visible and dock.get("_brush_options").visible, "material options show together with the normal brush options")
	var info: Label = dock.get("_material_info")
	check(not info.visible and "Albedo" in menu.tooltip_text and "brick" in menu.tooltip_text, "no info label clutters the toolbar; the Material menu tooltip says what is painted: " + menu.tooltip_text.replace("\n", " "))

	print("MBTEST  == B) painting in the albedo channel (plain 2D document)")
	canvas.brush_size = 4
	canvas.brush_color = Color(0, 0, 0, 1)
	canvas.clear_canvas()
	check(_near(_stroke(canvas, Vector2(0.25, 0.25)), red), "top-left quadrant paints red")
	check(_near(_stroke(canvas, Vector2(0.75, 0.25)), green), "top-right quadrant paints green")
	check(_near(_stroke(canvas, Vector2(0.25, 0.75)), blue), "bottom-left quadrant paints blue")
	check(_near(_stroke(canvas, Vector2(0.75, 0.75)), white), "bottom-right quadrant paints white")
	var scale_spin: SpinBox = dock.get("_material_scale")
	var rotation_spin: SpinBox = dock.get("_material_rotation")
	canvas.clear_canvas()
	rotation_spin.value = 180.0
	check(_near(_stroke(canvas, Vector2(0.25, 0.25)), white), "rotating 180 degrees swaps the corners")
	rotation_spin.value = 0.0
	canvas.clear_canvas()
	scale_spin.value = 2.0
	var left := _stroke(canvas, Vector2(0.25, 0.25))
	var right := _stroke(canvas, Vector2(0.75, 0.25))
	check(_near(left, right, 0.02) and left.a > 0.9, "at scale 2 the pattern repeats every half texture")
	scale_spin.value = 1.0
	check(is_equal_approx(float(scale_spin.value), 1.0), "scale spin box works")

	print("MBTEST  == C) leaving the tool")
	canvas.clear_canvas()
	brush_button.button_pressed = true
	await _wait(2)
	check(not canvas.material_pixel_source.is_valid() and not material_button.button_pressed and brush_button.button_pressed and not options.visible, "choosing the Brush turns the Material Brush off")
	check(_near(_stroke(canvas, Vector2(0.25, 0.25)), Color(0, 0, 0, 1)), "the normal brush paints its own colour again")
	material_button.button_pressed = true
	await _wait(2)
	check(canvas.material_pixel_source.is_valid(), "the Material Brush can be turned back on")
	var eraser: Button = dock.get("_eraser_button")
	eraser.button_pressed = true
	await _wait(2)
	check(not canvas.material_pixel_source.is_valid() and not material_button.button_pressed, "choosing the Eraser turns it off too")
	material_button.button_pressed = true
	await _wait(2)

	print("MBTEST  == D) other channels")
	var layer_session = dock.get("_layer_session")
	var active_target = layer_session.get_active_target()
	check(dock.call("_get_material_brush_channel") == "albedo", "a plain 2D document paints the albedo channel")
	active_target.channel_id = "roughness"
	dock.call("_update_material_brush_info")
	check(not info.visible and "Roughness" in menu.tooltip_text, "the menu tooltip follows the channel")
	canvas.clear_canvas()
	var gray := _stroke(canvas, Vector2(0.25, 0.25))
	check(_near(gray, Color(0.1, 0.1, 0.1, 1.0), 0.03), "a roughness target paints the material's roughness map as gray (%s)" % str(gray))
	active_target.channel_id = "ao"
	dock.call("_update_material_brush_info")
	check(info.visible and "No ambient occlusion" in info.text and info.text.length() < 32, "a channel the material lacks is called out, briefly: " + info.text)
	canvas.clear_canvas()
	var before: PackedByteArray = canvas.get_image_copy().get_data()
	_stroke(canvas, Vector2(0.25, 0.25))
	check(canvas.get_image_copy().get_data() == before, "and nothing is painted for it")
	active_target.channel_id = "rgba"

	print("MBTEST  == E) a real 3D roughness session")
	var root := Node3D.new()
	root.name = "MbRoot"
	var scene := PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, "res://mb_scene.tscn")
	ei.open_scene_from_path("res://mb_scene.tscn")
	await _wait(90)
	var edited_root := ei.get_edited_scene_root()
	var hero := MeshInstance3D.new()
	hero.name = "Hero"
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, CapsuleMesh.new().get_mesh_arrays())
	var hero_material := StandardMaterial3D.new()
	hero_material.albedo_texture = _save_png("res://tex/mb_hero_albedo.png", Vector2i(64, 64), Color.WHITE)
	hero_material.roughness = 0.4
	mesh.surface_set_material(0, hero_material)
	hero.mesh = mesh
	edited_root.add_child(hero)
	hero.owner = edited_root
	await _wait(5)
	dock.call("_select_canvas_mode", 1)
	await _wait(2)
	dock.call("_on_channel_selected", 2)
	var discovery: Dictionary = GDDraw3DLayerDiscovery.new().discover([hero], GDDraw3DLayerDiscovery.Scope.SELECTED_SURFACE, "roughness")
	dock.call("_begin_3d_layer_session", discovery, true)
	await _wait(120)
	var session = dock.get("_texture_3d_session")
	check(session != null and session.has_active_session() and session.channel == "roughness", "a roughness session is open")
	if session != null and session.has_active_session() and session.channel == "roughness":
		canvas = dock.get("_canvas")
		material_button = dock.get("_material_button")
		if not material_button.button_pressed:
			material_button.button_pressed = true
			await _wait(2)
		check(dock.call("_get_material_brush_channel") == "roughness", "the brush reads the channel from the paint target")
		check(not dock.get("_material_info").visible and "Roughness" in dock.get("_material_menu").tooltip_text, "the menu tooltip says Roughness")
		canvas.brush_size = 4
		var painted := _stroke(canvas, Vector2(0.25, 0.75))
		check(_near(painted, Color(0.7, 0.7, 0.7, 1.0), 0.04), "a stroke in the roughness session paints the roughness map (%s)" % str(painted))
		var target = dock.get("_layer_session").get_active_target()
		check(target != null and target.channel_id == "roughness", "the paint target is the roughness one")
		dock.call("_undo")
		var pixel: Vector2i = canvas.image_pixel_from_uv(Vector2(0.25, 0.75))
		check(not _near(canvas.get_image_copy().get_pixel(pixel.x, pixel.y), Color(0.7, 0.7, 0.7, 1.0), 0.04), "undo removes the material stroke")
		dock.call("_redo")
		check(_near(canvas.get_image_copy().get_pixel(pixel.x, pixel.y), Color(0.7, 0.7, 0.7, 1.0), 0.04), "redo brings it back")

	print("MBTEST  == F) companion channels: one stroke paints several textures")
	var companion_button: MenuButton = dock.get("_material_companion_button")
	check(companion_button != null and companion_button.get_popup().item_count == 7, "the options have an 'Also paint' menu with the seven channels")
	# Also paint follows the selected material: its textured channels were ticked when it was picked (the set has a normal map)
	var loaded_ticks: PackedStringArray = dock.get("_material_companion_channels")
	check(loaded_ticks.has("normal") and not loaded_ticks.has("albedo"), "Also paint follows the selected material (ticked: %s)" % str(loaded_ticks))
	dock.set("_material_companion_channels", PackedStringArray())
	dock.call("_refresh_material_companion_menu")
	check(companion_button.text == "Also paint", "the ticks can be cleared by hand")
	dock.call("_on_material_companion_toggled", 2)
	dock.call("_on_material_companion_toggled", 3)
	check(dock.get("_material_companion_channels") == PackedStringArray(["roughness", "metallic"]) and companion_button.text == "Also paint (2)", "ticking Roughness and Metallic is remembered: " + companion_button.text)
	check(companion_button.get_popup().is_item_checked(2) and companion_button.get_popup().is_item_checked(3) and not companion_button.get_popup().is_item_checked(0), "the menu shows the ticks")

	dock.call("_clear_3d_texture_session_state", false)
	await _wait(10)
	dock.call("_on_channel_selected", 0)
	var albedo_discovery: Dictionary = GDDraw3DLayerDiscovery.new().discover([hero], GDDraw3DLayerDiscovery.Scope.SELECTED_SURFACE, "albedo")
	check(str(albedo_discovery.get("status")) == "ok" and albedo_discovery.get("targets", []).size() == 1, "discovery still lists just the albedo target")
	var material_button_f: Button = dock.get("_material_button")
	if not material_button_f.button_pressed:
		material_button_f.button_pressed = true
		await _wait(2)
	check(dock.get("_material_brush_active"), "the Material Brush is active")
	dock.call("_begin_3d_layer_session", albedo_discovery, true)
	await _wait(150)
	var layer_session_f = dock.get("_layer_session")
	var coordinator = dock.get("_texture_3d_layer_coordinator")
	check(layer_session_f != null and coordinator != null and layer_session_f.paint_targets.size() == 3, "the session opened three paint targets (albedo + roughness + metallic): %d" % (layer_session_f.paint_targets.size() if layer_session_f else -1))
	var channels_open := []
	for paint_target in layer_session_f.paint_targets:
		channels_open.append(str(paint_target.channel_id))
	check(channels_open == ["albedo", "roughness", "metallic"], "in that order: " + str(channels_open))
	check(coordinator.get_preview_entries().size() == 1, "only the albedo target has a 3D preview")
	var found_binding: Dictionary = coordinator.get_binding_for_source_node(hero)
	check(not found_binding.is_empty() and str(found_binding.get("target_id")) == layer_session_f.active_target_id, "the scene object still resolves to the albedo target")
	var hero_override := hero.get_active_material(0) as StandardMaterial3D
	check(hero_override != null and hero_override.roughness_texture != null and hero_override.metallic_texture != null, "the material now has roughness and metallic textures")

	canvas = dock.get("_canvas")
	canvas.brush_size = 4
	canvas.brush_color = Color(0, 0, 0, 1)
	var rough_target
	var metal_target
	for paint_target in layer_session_f.paint_targets:
		if str(paint_target.channel_id) == "roughness":
			rough_target = paint_target
		elif str(paint_target.channel_id) == "metallic":
			metal_target = paint_target
	var rough_before: Color = rough_target.get_selected_layer_image().get_pixel(16, 16)
	var far_before: Color = rough_target.get_selected_layer_image().get_pixel(58, 58)
	var painted_albedo := _stroke(canvas, Vector2(0.25, 0.25))
	check(_near(painted_albedo, red), "the stroke paints the albedo target from the albedo map")
	var rough_after: Color = rough_target.get_selected_layer_image().get_pixel(16, 16)
	var metal_after: Color = metal_target.get_selected_layer_image().get_pixel(16, 16)
	check(_near(rough_after, Color(0.1, 0.1, 0.1, 1.0), 0.03) and not _near(rough_before, rough_after, 0.05), "and the roughness target from the roughness map (%s -> %s)" % [str(rough_before), str(rough_after)])
	check(_near(metal_after, Color(0.2, 0.2, 0.2, 1.0), 0.03), "and the metallic target from the metallic map (%s)" % str(metal_after))
	check(_near(rough_target.get_selected_layer_image().get_pixel(58, 58), far_before, 0.001), "pixels away from the stroke are untouched")
	var dirty_ids: PackedStringArray = coordinator.get_dirty_target_ids(canvas.get_image_copy())
	check(rough_target.target_id in dirty_ids and metal_target.target_id in dirty_ids, "the companion targets count as unsaved changes")

	dock.call("_undo")
	await _wait(2)
	# undo restores the session state, which replaces the changed target objects: look them up again
	var rough_undone: Color = dock.get("_layer_session").get_target(rough_target.target_id).get_selected_layer_image().get_pixel(16, 16)
	var metal_undone: Color = dock.get("_layer_session").get_target(metal_target.target_id).get_selected_layer_image().get_pixel(16, 16)
	check(_near(rough_undone, rough_before, 0.01) and _near(metal_undone, Color(0.0, 0.0, 0.0, 1.0), 0.06), "undo takes the stroke out of every channel together (%s, %s)" % [str(rough_undone), str(metal_undone)])
	dock.call("_redo")
	await _wait(2)
	rough_target = dock.get("_layer_session").get_target(rough_target.target_id)
	metal_target = dock.get("_layer_session").get_target(metal_target.target_id)
	check(_near(rough_target.get_selected_layer_image().get_pixel(16, 16), rough_after, 0.01) and _near(metal_target.get_selected_layer_image().get_pixel(16, 16), metal_after, 0.01), "redo brings it back in every channel")

	# a channel the material lacks is skipped: untick roughness in the material by using a set without it
	check(dock.call("_load_material_brush_material", "res://ms/brick_albedo.png"), "reloading the material works")
	var texture_session_f = coordinator.get_texture_session(rough_target.target_id)
	check(texture_session_f != null and texture_session_f.channel == "roughness", "each companion has its own texture session")
	if texture_session_f != null:
		var saved: Dictionary = texture_session_f.save_image(rough_target.get_selected_layer_image(), dock.get("_plugin"))
		check(str(saved.get("status")) == "ok", "a companion texture can be saved on its own: " + str(saved.get("message")))
		var written := Image.load_from_file(ProjectSettings.globalize_path(texture_session_f.texture_path))
		check(written != null and _near(written.get_pixel(16, 16), Color(0.1, 0.1, 0.1, 1.0), 0.03), "the saved roughness PNG holds the stamped material (%s)" % texture_session_f.texture_path)

	# selecting a companion target (Layers panel) works and does not break painting
	layer_session_f.route_hit_to_target(rough_target.target_id)
	dock.call("_sync_canvas_to_active_layer", false, false)
	await _wait(4)
	check(str(dock.get("_layer_session").get_active_target().channel_id) == "roughness" and dock.call("_get_material_brush_channel") == "roughness", "a companion target can be made active")
	var rough_hit := _stroke(canvas, Vector2(0.75, 0.25))
	check(_near(rough_hit, Color(0.3, 0.3, 0.3, 1.0), 0.04), "and the brush then paints it directly (%s)" % str(rough_hit))
	layer_session_f.route_hit_to_target(layer_session_f.paint_targets[0].target_id)
	dock.call("_sync_canvas_to_active_layer", false, false)
	await _wait(2)
	print("MBTEST  == G) creating a new material and editing it in the Inspector")
	check(dock.call("_load_material_brush_material", "res://ms/brick_albedo.png") and menu_popup.is_item_disabled(menu_popup.get_item_index(3)), "a texture set on disk cannot go in the Inspector: Edit is disabled")
	menu_popup.id_pressed.emit(1)
	await _wait(3)
	var created_path := "res://gddraw/materials/material_brush_1.tres"
	check(FileAccess.file_exists(created_path), "New created " + created_path)
	var set_g = dock.get("_material_set")
	check(set_g != null and set_g.source_material is StandardMaterial3D and set_g.source_material.resource_path == created_path, "the brush uses the new StandardMaterial3D")
	check(dock.get("_material_recent")[0] == created_path and not menu_popup.is_item_disabled(menu_popup.get_item_index(3)) and menu.text.begins_with("material_brush_1"), "it is the most recent material, named on the menu, and Edit is enabled")
	check(ei.get_inspector().get_edited_object() == set_g.source_material, "the material is open in the Inspector")
	check(dock.get("_material_poll_timer") != null and not dock.get("_material_poll_timer").is_stopped(), "the brush is watching the material for edits")

	var edited: StandardMaterial3D = set_g.source_material
	edited.albedo_color = Color(0.2, 0.4, 0.6, 1.0)
	dock.call("_poll_material_brush_material")
	check(_near(dock.get("_material_set").sample("albedo", Vector2(0.5, 0.5)), Color(0.2, 0.4, 0.6, 1.0), 0.01), "the brush follows an albedo colour edit")
	edited.roughness = 0.3
	dock.call("_poll_material_brush_material")
	check(_near(dock.get("_material_set").sample("roughness", Vector2(0.5, 0.5)), Color(0.3, 0.3, 0.3, 1.0), 0.01), "and a roughness value edit")
	var gray_image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	gray_image.fill(Color(0.55, 0.55, 0.55, 1.0))
	edited.metallic = 1.0  # like in a real render: the texture multiplies the metallic value
	edited.metallic_texture = ImageTexture.create_from_image(gray_image)
	dock.call("_poll_material_brush_material")
	check(dock.get("_material_set").has_texture("metallic") and _near(dock.get("_material_set").sample("metallic", Vector2(0.5, 0.5)), Color(0.55, 0.55, 0.55, 1.0), 0.02), "and a texture assigned in the Inspector")
	var saved_text := FileAccess.get_file_as_string(created_path)
	check("albedo_color" in saved_text and "metallic_texture" in saved_text and "roughness = 0.3" in saved_text, "GDDraw saved the created material file after the edits")
	canvas = dock.get("_canvas")
	canvas.brush_size = 4
	var from_new := _stroke(canvas, Vector2(0.6, 0.6))
	check(_near(from_new, Color(0.2, 0.4, 0.6, 1.0), 0.03), "painting with the new material uses its albedo colour (%s)" % str(from_new))

	var other := StandardMaterial3D.new()
	ResourceSaver.save(other, "res://ms/other.tres")
	check(dock.call("_load_material_brush_material", "res://ms/other.tres"), "an existing .tres material loads")
	var other_live: StandardMaterial3D = dock.get("_material_set").source_material
	other_live.roughness = 0.9
	dock.call("_poll_material_brush_material")
	check(_near(dock.get("_material_set").sample("roughness", Vector2(0.5, 0.5)), Color(0.9, 0.9, 0.9, 1.0), 0.01), "edits to an existing material also reach the brush")
	check(not ("roughness = 0.9" in FileAccess.get_file_as_string("res://ms/other.tres")), "but GDDraw does not overwrite materials it did not create")
	dock.call("_edit_material_brush_material_in_inspector")
	check(ei.get_inspector().get_edited_object() == other_live, "Edit opens the current material in the Inspector")
	print("MBTEST  == H) shader materials as brush sources")
	var menu_h: MenuButton = dock.get("_material_menu")
	var popup_h := menu_h.get_popup()
	dock.call("_rebuild_material_menu")
	var shader_item := popup_h.get_item_index(4)
	check(shader_item >= 0 and "Shader Material" in popup_h.get_item_text(shader_item), "the Material menu offers New Shader Material")
	var submenu_found := false
	for i in range(popup_h.item_count):
		if popup_h.get_item_text(i) == "Shader Bake Size" and popup_h.get_item_submenu_node(i) != null:
			submenu_found = true
	check(submenu_found and dock.get("_material_size_menu").item_count == 4, "and a Shader Bake Size submenu with four sizes")
	dock.call("_on_material_bake_size_selected", 256)
	check(dock.get("_material_bake_size") == 256 and dock.get("_material_size_menu").is_item_checked(0) and not dock.get("_material_size_menu").is_item_checked(1), "choosing a size is remembered and ticked")
	dock.call("_on_material_bake_size_selected", 12345)
	check(dock.get("_material_bake_size") == 256, "an unknown size is ignored")

	popup_h.id_pressed.emit(4)
	await _wait(3)
	var shader_path := "res://gddraw/materials/material_brush_shader_1.tres"
	check(FileAccess.file_exists(shader_path) and "shader_type spatial" in FileAccess.get_file_as_string(shader_path), "New Shader Material created " + shader_path + " with its shader inside")
	var shader_material: ShaderMaterial = dock.get("_material_shader")
	check(shader_material != null and shader_material.resource_path == shader_path, "the brush uses the new ShaderMaterial")
	check(menu_h.text.begins_with("material_brush_shader_1") and not popup_h.is_item_disabled(popup_h.get_item_index(3)), "it is named on the menu button and Edit is enabled")
	check(ei.get_inspector().get_edited_object() == shader_material, "the ShaderMaterial is open in the Inspector")
	for _i in range(400):
		if not dock.get("_material_baking"):
			break
		await _wait(1)
	check(not dock.get("_material_baking"), "the bake finished")
	print("MBTEST  info  bake result: set=", dock.get("_material_set"), " notice='", dock.get("_material_last_notice"), "'")
	# With a real renderer (not in the headless run) the shader is baked for real: paint with it.
	var baked_set = dock.get("_material_set")
	if baked_set != null and baked_set.shader_material == shader_material:
		print("MBTEST  info  a renderer is available: checking the baked material")
		check(baked_set.channels() == PackedStringArray(["albedo", "roughness", "metallic"]), "the template shader bakes albedo, roughness and metallic: " + str(baked_set.channels()))
		check(baked_set.has_texture("albedo") and baked_set.sample("albedo", Vector2(0.3, 0.3)).a > 0.99, "the baked albedo is an opaque image")
		canvas = dock.get("_canvas")
		canvas.brush_size = 4
		canvas.clear_canvas()
		if not dock.get("_material_brush_active"):
			(dock.get("_material_button") as Button).button_pressed = true
			await _wait(2)
		var painted_from_shader := _stroke(canvas, Vector2(0.4, 0.4))
		var expected_from_shader: Color = baked_set.sample("albedo", Vector2(0.4, 0.4))
		check(_near(painted_from_shader, expected_from_shader, 0.08), "a stroke paints the baked shader's colour (%s vs %s)" % [str(painted_from_shader), str(expected_from_shader)])
		check(dock.get("_material_last_notice") == "" or not ("Could not bake" in dock.get("_material_last_notice")), "and there was no bake error")
	dock.call("_poll_material_brush_material")
	shader_material.set_shader_parameter("stripes", 20.0)
	dock.call("_poll_material_brush_material")
	await _wait(5)
	check("stripes = 20.0" in FileAccess.get_file_as_string(shader_path), "a parameter change made in the Inspector is saved to the material file")
	for _i in range(400):
		if not dock.get("_material_baking"):
			break
		await _wait(1)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ms"))
	var plain_shader := FileAccess.open("res://ms/plain.gdshader", FileAccess.WRITE)
	plain_shader.store_string("shader_type spatial;\nvoid fragment() {\n\tALBEDO = vec3(UV, 0.0);\n\tROUGHNESS = 0.4;\n}\n")
	plain_shader.close()
	var empty_shader := FileAccess.open("res://ms/empty.gdshader", FileAccess.WRITE)
	empty_shader.store_string("shader_type spatial;\nvoid vertex() {\n\tVERTEX.y += 0.1;\n}\n")
	empty_shader.close()
	await _wait(3)
	check(dock.call("_load_material_brush_material", "res://ms/plain.gdshader"), "a .gdshader file can be chosen")
	check(dock.get("_material_shader") != null and dock.get("_material_shader").resource_path == "" and dock.get("_material_recent")[0] == "res://ms/plain.gdshader", "it is wrapped in a ShaderMaterial and remembered")
	for _i in range(400):
		if not dock.get("_material_baking"):
			break
		await _wait(1)
	var before_shader = dock.get("_material_shader")
	check(not dock.call("_load_material_brush_material", "res://ms/empty.gdshader"), "a shader with nothing to bake is refused")
	check("nothing the brush can bake" in dock.get("_material_last_notice") and dock.get("_material_shader") == before_shader, "with a message, keeping the current material")
	check(dock.call("_load_material_brush_material", "res://ms/brick_albedo.png") and dock.get("_material_shader") == null, "choosing a normal material drops the shader")
	print("MBTEST  == I) the native Material Brush path paints what the per-pixel path paints")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ms"))
	var gradient := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
	for gy in range(256):
		for gx in range(256):
			gradient.set_pixel(gx, gy, Color(float(gx) / 255.0, float(gy) / 255.0, 0.5, 1.0))
	gradient.save_png(ProjectSettings.globalize_path("res://ms/ramp_albedo.png"))
	var gray_ramp := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
	for gy in range(256):
		for gx in range(256):
			var level := float(gx) / 255.0
			gray_ramp.set_pixel(gx, gy, Color(level, level, level, 1.0))
	gray_ramp.save_png(ProjectSettings.globalize_path("res://ms/ramp_roughness.png"))
	await _wait(3)
	check(dock.call("_load_material_brush_material", "res://ms/ramp_albedo.png"), "a gradient texture set loads")
	var ramp_set = dock.get("_material_set")
	check(ramp_set.fast_map("albedo") is Image and ramp_set.fast_map("roughness") is Image, "its maps can be used natively")
	var stamp_canvas = dock.get("_canvas")
	var base_image := Image.create_empty(512, 512, false, Image.FORMAT_RGBA8)
	stamp_canvas.set_image(base_image)
	dock.call("_reset_layer_session_for_image", stamp_canvas.get_image_copy(), "2d", "2D Document", "RGBA", "rgba")
	var rotation_box: SpinBox = dock.get("_material_rotation")
	var scale_box: SpinBox = dock.get("_material_scale")
	rotation_box.value = 0.0
	if not dock.get("_material_brush_active"):
		(dock.get("_material_button") as Button).button_pressed = true
		await _wait(2)
	stamp_canvas.brush_size = 48
	stamp_canvas.brush_color = Color(0, 0, 0, 1)
	var tri_i := PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0)])
	for scale_value in [1.0, 2.0, 3.7]:
		scale_box.value = scale_value
		var paints := []
		for use_native in [true, false]:
			stamp_canvas.set_image(Image.create_empty(512, 512, false, Image.FORMAT_RGBA8))
			stamp_canvas.fast_stamp_enabled = use_native
			stamp_canvas.begin_uv_triangle_stroke(Vector2(0.25, 0.3), tri_i)
			stamp_canvas.continue_uv_triangle_stroke(Vector2(0.45, 0.4), tri_i, true)
			stamp_canvas.continue_uv_triangle_stroke(Vector2(0.6, 0.62), tri_i, true)
			stamp_canvas.end_uv_triangle_stroke()
			paints.append(stamp_canvas.get_image_copy())
		var total_difference := 0.0
		var counted := 0
		var worst := 0.0
		var native_image: Image = paints[0]
		var slow_image: Image = paints[1]
		for py in range(150, 360):
			for px in range(100, 340):
				var a := native_image.get_pixel(px, py)
				var b := slow_image.get_pixel(px, py)
				if a.a > 0.0 or b.a > 0.0:
					var d := maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))
					total_difference += d
					counted += 1
					worst = maxf(worst, d)
		check(counted > 1000 and total_difference / float(counted) < 0.02 and worst < 0.15, "scale %s: native and per-pixel strokes agree (mean difference %.4f, worst %.3f over %d pixels)" % [str(scale_value), total_difference / maxf(1.0, float(counted)), worst, counted])
	check(dock.get("_material_tiles").size() > 0, "the native path built its material tile (it really ran)")
	stamp_canvas.fast_stamp_enabled = true
	scale_box.value = 1.0
	# a rotation is not handled natively: the stroke still paints (per pixel)
	rotation_box.value = 30.0
	check(dock.call("_material_region_provider", Rect2i(0, 0, 8, 8)) == null, "with a rotation the native provider steps aside")
	stamp_canvas.set_image(Image.create_empty(512, 512, false, Image.FORMAT_RGBA8))
	stamp_canvas.brush_size = 20
	stamp_canvas.begin_uv_triangle_stroke(Vector2(0.5, 0.5), tri_i)
	stamp_canvas.end_uv_triangle_stroke()
	check(stamp_canvas.get_image_copy().get_pixel(256, 256).a > 0.9, "and painting with a rotation still works")
	rotation_box.value = 0.0
	# native stamps are recorded in a coverage image for the companion channels
	dock.call("_reset_material_stroke")
	dock.set("_material_companion_channels", PackedStringArray(["roughness"]))
	var ok_wants: bool = dock.call("_material_wants_companions")
	print("MBTEST  info  companions wanted in a plain 2D document: ", ok_wants)
	var probe_stamp := Image.create_empty(3, 3, false, Image.FORMAT_RGBA8)
	for py in range(3):
		for px in range(3):
			probe_stamp.set_pixel(px, py, Color(1, 1, 1, 0.0 if px == 1 and py == 1 else 1.0))
	# the recorder only records when companions are wanted (3D session); call the pieces directly
	dock.set("_material_mask_image", Image.create_empty(64, 64, false, Image.FORMAT_RGBA8))
	(dock.get("_material_mask_image") as Image).blend_rect(probe_stamp, Rect2i(0, 0, 3, 3), Vector2i(10, 10))
	var as_dictionary: Dictionary = dock.call("_material_mask_image_to_dictionary", dock.get("_material_mask_image"), Rect2i(10, 10, 3, 3))
	check(as_dictionary.size() == 8 and as_dictionary.has(10 * 64 + 10) and not as_dictionary.has(11 * 64 + 11), "the coverage image converts to the per-pixel mask (%d pixels)" % as_dictionary.size())
	dock.set("_material_companion_channels", PackedStringArray())
	dock.call("_reset_material_stroke")

	print("MBTEST  == J) renaming and deleting materials")
	var menu_j: MenuButton = dock.get("_material_menu")
	var popup_j := menu_j.get_popup()
	check(dock.call("_load_material_brush_material", "res://ms/brick_albedo.png"), "a texture set is loaded")
	dock.call("_rebuild_material_menu")
	var rename_index := popup_j.get_item_index(5)
	var delete_index := popup_j.get_item_index(6)
	check(rename_index >= 0 and delete_index >= 0 and "Rename" in popup_j.get_item_text(rename_index) and "Delete" in popup_j.get_item_text(delete_index), "the Material menu offers Rename and Delete")
	check(popup_j.is_item_disabled(rename_index) and popup_j.is_item_disabled(delete_index), "both are disabled for a texture set (there is no material file)")
	check(not dock.call("_rename_material_brush_material", "anything") and not dock.call("_delete_material_brush_material", false), "and refuse when called anyway")

	popup_j.id_pressed.emit(1)
	await _wait(3)
	var first_path: String = dock.get("_material_recent")[0]
	check(first_path.begins_with("res://gddraw/materials/material_brush_") and FileAccess.file_exists(first_path), "a new material exists: " + first_path)
	dock.call("_rebuild_material_menu")
	check(not popup_j.is_item_disabled(popup_j.get_item_index(5)) and not popup_j.is_item_disabled(popup_j.get_item_index(6)), "Rename and Delete are enabled for a material file")
	dock.call("_ask_rename_material_brush_material")
	check(dock.get("_material_rename_edit").text == first_path.get_file().get_basename(), "the rename dialog starts with the current name")
	check(not dock.call("_rename_material_brush_material", ""), "an empty name is refused")
	check(not dock.call("_rename_material_brush_material", "a/b"), "a name with a slash is refused")
	check(dock.call("_rename_material_brush_material", "granite"), "renaming to a free name works")
	var granite_path := "res://gddraw/materials/granite.tres"
	check(FileAccess.file_exists(granite_path) and not FileAccess.file_exists(first_path), "the file has the new name and the old one is gone")
	check(dock.get("_material_recent")[0] == granite_path and dock.get("_material_set").source_material.resource_path == granite_path, "the recent list and the loaded material follow")
	check(dock.get("_material_menu").text.begins_with("granite"), "the Material menu shows the new name: " + dock.get("_material_menu").text)
	check("resource_name = \"granite\"" in FileAccess.get_file_as_string(granite_path), "the material's own name inside the file is updated")
	check(dock.call("_rename_material_brush_material", "granite.tres"), "typing the extension is fine")

	popup_j.id_pressed.emit(1)
	await _wait(3)
	var second_path: String = dock.get("_material_recent")[0]
	check(second_path != granite_path and not dock.call("_rename_material_brush_material", "granite"), "renaming onto an existing file is refused")
	check(FileAccess.file_exists(second_path) and FileAccess.file_exists(granite_path), "and nothing was lost")

	dock.call("_ask_delete_material_brush_material")
	check(second_path.get_file() in dock.get("_material_delete_dialog").dialog_text, "the delete dialog names the file")
	check(dock.call("_delete_material_brush_material", false), "deleting works")
	check(not FileAccess.file_exists(second_path), "the file is gone")
	check(dock.get("_material_set") == null and dock.get("_material_shader") == null and not (second_path in dock.get("_material_recent")), "the brush forgot it and the recent list dropped it")
	check(dock.get("_material_menu").text.begins_with("Choose material"), "the menu asks for a material again")
	dock.call("_rebuild_material_menu")
	check(popup_j.is_item_disabled(popup_j.get_item_index(6)), "Delete is disabled again")

	# a shader material file can be renamed and deleted the same way
	popup_j.id_pressed.emit(4)
	await _wait(3)
	var shader_file: String = dock.get("_material_recent")[0]
	check(dock.call("_rename_material_brush_material", "marble") and FileAccess.file_exists("res://gddraw/materials/marble.tres") and dock.get("_material_shader_path") == "res://gddraw/materials/marble.tres", "a shader material can be renamed too")
	for _i in range(400):
		if not dock.get("_material_baking"):
			break
		await _wait(1)
	check(dock.call("_delete_material_brush_material", false) and not FileAccess.file_exists("res://gddraw/materials/marble.tres") and dock.get("_material_shader") == null, "and deleted")
	print("MBTEST  == K) companion channels painted natively match the per-pixel route")
	dock.call("_clear_3d_texture_session_state", false)
	await _wait(10)
	var native_root := ei.get_edited_scene_root()
	var native_mesh := ArrayMesh.new()
	native_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, SphereMesh.new().get_mesh_arrays())
	var native_material := StandardMaterial3D.new()
	native_material.albedo_texture = _save_png("res://tex/native_hero.png", Vector2i(256, 256), Color(0.4, 0.4, 0.4, 1))
	native_mesh.surface_set_material(0, native_material)
	var native_hero := MeshInstance3D.new()
	native_hero.name = "NativeHero"
	native_hero.mesh = native_mesh
	native_root.add_child(native_hero)
	native_hero.owner = native_root
	await _wait(5)
	dock.call("_select_canvas_mode", 1)
	await _wait(2)
	dock.call("_load_material_brush_material", "res://ms/ramp_albedo.png")
	dock.set("_material_companion_channels", PackedStringArray(["roughness"]))
	dock.call("_refresh_material_companion_menu")
	dock.get("_material_scale").value = 1.0
	dock.get("_material_rotation").value = 0.0
	if not dock.get("_material_brush_active"):
		(dock.get("_material_button") as Button).button_pressed = true
		await _wait(2)
	var native_discovery: Dictionary = GDDraw3DLayerDiscovery.new().discover([native_hero], GDDraw3DLayerDiscovery.Scope.SELECTED_SURFACE, "albedo")
	dock.call("_begin_3d_layer_session", native_discovery, true)
	await _wait(150)
	var native_session = dock.get("_layer_session")
	var native_rough_id := ""
	for paint_target in native_session.paint_targets:
		if str(paint_target.channel_id) == "roughness":
			native_rough_id = paint_target.target_id
	check(native_session.paint_targets.size() == 2 and native_rough_id != "", "a two-target session (albedo + roughness) is open")
	var native_canvas = dock.get("_canvas")
	native_canvas.brush_size = 24
	var native_tri := PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0)])
	var before_rough: Image = native_session.get_target(native_rough_id).get_selected_layer_image()
	var results := []
	for use_native in [true, false]:
		native_canvas.fast_stamp_enabled = use_native
		native_canvas.begin_uv_triangle_stroke(Vector2(0.3, 0.3), native_tri)
		native_canvas.continue_uv_triangle_stroke(Vector2(0.45, 0.4), native_tri, true)
		native_canvas.continue_uv_triangle_stroke(Vector2(0.55, 0.6), native_tri, true)
		native_canvas.end_uv_triangle_stroke()
		await _wait(2)
		results.append(dock.get("_layer_session").get_target(native_rough_id).get_selected_layer_image())
		dock.call("_undo")
		await _wait(2)
		var restored: Image = dock.get("_layer_session").get_target(native_rough_id).get_selected_layer_image()
		check(restored.get_data() == before_rough.get_data(), "undo restores the companion (%s route)" % ("native" if use_native else "per-pixel"))
	native_canvas.fast_stamp_enabled = true
	var native_image: Image = results[0]
	var slow_image: Image = results[1]
	var changed_pixels := 0
	var difference_sum := 0.0
	for py in range(256):
		for px in range(256):
			var a := native_image.get_pixel(px, py)
			var b := slow_image.get_pixel(px, py)
			if not before_rough.get_pixel(px, py).is_equal_approx(a) or not before_rough.get_pixel(px, py).is_equal_approx(b):
				changed_pixels += 1
				difference_sum += maxf(absf(a.r - b.r), absf(a.a - b.a))
	check(changed_pixels > 500 and difference_sum / float(changed_pixels) < 0.03, "the roughness companion matches (%d changed pixels, mean difference %.4f)" % [changed_pixels, difference_sum / maxf(1.0, float(changed_pixels))])
	print("MBTEST  == L) normal maps")
	dock.call("_clear_3d_texture_session_state", false)
	await _wait(10)
	_save_quadrants("res://ms/wave_albedo.png", [Color(0.3, 0.3, 0.3), Color(0.3, 0.3, 0.3), Color(0.3, 0.3, 0.3), Color(0.3, 0.3, 0.3)])
	_save_quadrants("res://ms/wave_normal.png", [Color(0.7, 0.5, 1.0), Color(0.3, 0.5, 1.0), Color(0.5, 0.7, 1.0), Color(0.5, 0.3, 1.0)])
	_save_quadrants("res://ms/flatx_albedo.png", [Color(0.3, 0.3, 0.3), Color(0.3, 0.3, 0.3), Color(0.3, 0.3, 0.3), Color(0.3, 0.3, 0.3)])
	_save_quadrants("res://ms/flatx_normal_dx.png", [Color(0.7, 0.4, 1.0), Color(0.7, 0.4, 1.0), Color(0.7, 0.4, 1.0), Color(0.7, 0.4, 1.0)])
	await _wait(3)
	check(dock.call("_load_material_brush_material", "res://ms/wave_albedo.png") and dock.get("_material_set").has_channel("normal"), "a set with a normal map loads")
	dock.call("_select_canvas_mode", 0)
	var normal_canvas = dock.get("_canvas")
	normal_canvas.set_image(Image.create_empty(256, 256, false, Image.FORMAT_RGBA8))
	dock.call("_reset_layer_session_for_image", normal_canvas.get_image_copy(), "2d", "2D Document", "RGBA", "rgba")
	var normal_rotation: SpinBox = dock.get("_material_rotation")
	var normal_scale_box: SpinBox = dock.get("_material_scale")
	normal_rotation.value = 0.0
	normal_scale_box.value = 1.0
	if not dock.get("_material_brush_active"):
		(dock.get("_material_button") as Button).button_pressed = true
		await _wait(2)
	normal_canvas.brush_size = 16
	dock.get("_layer_session").get_active_target().channel_id = "normal"
	dock.call("_update_material_brush_info")
	for spec in [[Vector2(0.25, 0.25), Color(0.7, 0.5, 1.0)], [Vector2(0.75, 0.25), Color(0.3, 0.5, 1.0)], [Vector2(0.25, 0.75), Color(0.5, 0.7, 1.0)], [Vector2(0.75, 0.75), Color(0.5, 0.3, 1.0)]]:
		normal_canvas.set_image(Image.create_empty(256, 256, false, Image.FORMAT_RGBA8))
		check(_near(_stroke(normal_canvas, spec[0]), spec[1], 0.04), "the normal target paints the normal map's %s quadrant (%s)" % [str(spec[0]), str(spec[1])])
	check(dock.get("_material_menu").tooltip_text.contains("Normal"), "the menu says it paints Normal")
	# rotating the pattern turns the normals with it
	dock.call("_load_material_brush_material", "res://ms/flatx_albedo.png")
	var flatx = dock.get("_material_set")
	check(flatx.has_channel("normal") and flatx.flip_normal_green, "a normal_dx file is recognised as DirectX")
	dock.call("_rebuild_material_menu")
	var flip_item: int = dock.get("_material_menu").get_popup().get_item_index(7)
	check(flip_item >= 0 and dock.get("_material_menu").get_popup().is_item_checked(flip_item) and not dock.get("_material_menu").get_popup().is_item_disabled(flip_item), "the menu shows Flip Normal Green ticked")
	normal_canvas.set_image(Image.create_empty(256, 256, false, Image.FORMAT_RGBA8))
	var upright := _stroke(normal_canvas, Vector2(0.5, 0.5))
	check(_near(upright, Color(0.7, 0.6, 1.0), 0.04), "the flipped map paints green 0.4 as 0.6 (%s)" % str(upright))
	dock.call("_toggle_material_normal_flip")
	normal_canvas.set_image(Image.create_empty(256, 256, false, Image.FORMAT_RGBA8))
	var unflipped := _stroke(normal_canvas, Vector2(0.5, 0.5))
	check(_near(unflipped, Color(0.7, 0.4, 1.0), 0.04), "un-ticking the flip gives the stored green back (%s)" % str(unflipped))
	normal_rotation.value = 90.0
	normal_canvas.set_image(Image.create_empty(256, 256, false, Image.FORMAT_RGBA8))
	var turned := _stroke(normal_canvas, Vector2(0.5, 0.5))
	check(_near(turned, Color(0.4, 0.3, 1.0), 0.05), "a 90 degree rotation turns the normals: (0.2, -0.1) -> (-0.1, -0.2) (%s)" % str(turned))
	normal_rotation.value = 0.0
	dock.call("_load_material_brush_material", "res://ms/wave_albedo.png")

	# painting the normal channel of a mesh
	var normal_root := ei.get_edited_scene_root()
	var normal_mesh := ArrayMesh.new()
	normal_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, SphereMesh.new().get_mesh_arrays())
	var normal_material := StandardMaterial3D.new()
	normal_material.albedo_texture = _save_png("res://tex/normal_hero.png", Vector2i(128, 128), Color(0.5, 0.5, 0.5, 1))
	normal_mesh.surface_set_material(0, normal_material)
	var normal_hero := MeshInstance3D.new()
	normal_hero.name = "NormalHero"
	normal_hero.mesh = normal_mesh
	normal_root.add_child(normal_hero)
	normal_hero.owner = normal_root
	await _wait(5)
	dock.call("_select_canvas_mode", 1)
	await _wait(2)
	dock.call("_on_channel_selected", 6)
	check(dock.get("_paint_channel") == "normal", "the Paint Channel dropdown offers Normal as its seventh entry")
	var normal_discovery: Dictionary = GDDraw3DLayerDiscovery.new().discover([normal_hero], GDDraw3DLayerDiscovery.Scope.SELECTED_SURFACE, "normal")
	check(str(normal_discovery.get("status")) == "ok", "the mesh offers a normal target (created on confirmation)")
	dock.call("_begin_3d_layer_session", normal_discovery, true)
	await _wait(150)
	var normal_session = dock.get("_texture_3d_session")
	check(normal_session != null and normal_session.has_active_session() and normal_session.channel == "normal", "a normal-map session is open")
	var live_material := normal_hero.get_active_material(0) as StandardMaterial3D
	check(live_material != null and live_material.normal_enabled and live_material.normal_texture != null and is_equal_approx(live_material.normal_scale, 1.0), "the mesh material now has normal mapping switched on with its own texture")
	normal_canvas = dock.get("_canvas")
	var flat_before: Color = normal_canvas.get_image_copy().get_pixel(10, 10)
	check(_near(flat_before, Color(0.5, 0.5, 1.0, 1.0), 0.01), "the new normal map starts flat (%s)" % str(flat_before))
	if not dock.get("_material_brush_active"):
		(dock.get("_material_button") as Button).button_pressed = true
		await _wait(2)
	normal_canvas.brush_size = 12
	var painted_normal := _stroke(normal_canvas, Vector2(0.25, 0.25))
	check(_near(painted_normal, Color(0.7, 0.5, 1.0, 1.0), 0.05), "a stroke paints the material's normals into it (%s)" % str(painted_normal))
	print("MBTEST  RESULT: ", "ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)
