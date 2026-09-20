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
	if _frames == 14000:
		print("PHTEST  TIMEOUT")
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
		print("PHTEST  PASS  ", message)
	else:
		_fail += 1
		print("PHTEST  FAIL  ", message)


func _embedded_images(root: Node) -> int:
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://ph_check.tscn")
	var text := FileAccess.get_file_as_string("res://ph_check.tscn")
	return text.count('[sub_resource type="Image"')


func _kinds(sessions: Array) -> String:
	var parts := []
	for s in sessions:
		parts.push_back("%s:%s" % [s.channel, "ImageTexture" if s.texture is ImageTexture else s.texture.get_class()])
	return ", ".join(parts)


func _run() -> void:
	var ei := get_editor_interface()
	var dock := _find_dock()
	var size := 1024
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ms"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tex"))
	var ramp := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(0, 256, 4):
		for x in range(0, 256, 4):
			ramp.fill_rect(Rect2i(x, y, 4, 4), Color(float(x) / 256.0, float(y) / 256.0, 0.5, 1.0))
	for n in ["albedo", "roughness", "emission"]:
		ramp.save_png(ProjectSettings.globalize_path("res://ms/ph_%s.png" % n))
	var albedo := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	albedo.fill(Color(0.5, 0.5, 0.5, 1))
	albedo.save_png(ProjectSettings.globalize_path("res://tex/ph_hero.png"))
	var root := Node3D.new()
	root.name = "PhRoot"
	var scene := PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, "res://ph_scene.tscn")
	ei.open_scene_from_path("res://ph_scene.tscn")
	await _wait(90)
	var edited_root := ei.get_edited_scene_root()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, CapsuleMesh.new().get_mesh_arrays())
	var material := StandardMaterial3D.new()
	var texture := ImageTexture.create_from_image(albedo)
	texture.set_meta("gddraw_source_path", "res://tex/ph_hero.png")
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
	(dock.get("_placeholder_texture_timer") as Timer).stop()
	dock.call("_load_material_brush_material", "res://ms/ph_albedo.png")
	dock.set("_material_companion_channels", PackedStringArray(["roughness", "emission"]))
	dock.call("_refresh_material_companion_menu")
	(dock.get("_material_button") as Button).button_pressed = true
	await _wait(3)
	var discovery: Dictionary = GDDraw3DLayerDiscovery.new().discover([hero], GDDraw3DLayerDiscovery.Scope.SELECTED_SURFACE, "albedo")
	dock.set("_last_3d_import_roots", [hero])
	dock.call("_begin_3d_layer_session", discovery, true)
	await _wait(200)
	var coordinator = dock.get("_texture_3d_layer_coordinator")
	var sessions: Array = coordinator.texture_sessions.values()
	print("PHTEST  sessions: ", _kinds(sessions))
	_check(sessions.size() == 3, "three textures in the session (albedo + 2 companions)")
	var placeholders := sessions.filter(func(s): return s.texture is ImageTexture).size()
	_check(placeholders >= 2, "the created textures start as in-memory ImageTextures (%d)" % placeholders)
	var embedded_before := _embedded_images(edited_root)
	_check(embedded_before >= 2, "and a scene saved now embeds their pixels (%d embedded images) - the bug this fixes" % embedded_before)

	print("PHTEST  == paint, save the active texture, and try to swap too early")
	var canvas = dock.get("_canvas")
	canvas.brush_color = Color(0, 0, 0, 1)
	canvas.brush_size = 64
	var triangle := PackedVector2Array([Vector2(0.02, 0.02), Vector2(0.98, 0.02), Vector2(0.02, 0.98)])
	canvas.begin_uv_triangle_stroke(Vector2(0.2, 0.3), triangle)
	canvas.continue_uv_triangle_stroke(Vector2(0.22, 0.31), triangle, true)
	canvas.end_uv_triangle_stroke()
	await _wait(10)
	var active = coordinator.get_active_texture_session()
	var painted_image: Image = dock.call("_get_canvas_output_image")
	var result: Dictionary = active.save_image(painted_image, self)
	_check(str(result.get("status", "")) == "ok", "saved the painted texture: " + str(result.get("message", "")))
	dock.call("_request_resource_filesystem_scan")
	dock.call("_swap_placeholder_textures", true)
	_check(active.texture is ImageTexture, "the swap refuses while Godot still has the OLD image imported (painted pixels are kept)")
	_check(is_equal_approx(GDDrawMaterialChannels.read_texture(active.material, active.channel).get_image().get_pixel(int(0.21 * size), int(0.305 * size)).r, 0.0) or GDDrawMaterialChannels.read_texture(active.material, active.channel).get_image().get_pixel(int(0.21 * size), int(0.305 * size)).r < 0.9, "and the material still shows the painting")

	print("PHTEST  == waiting for the import, then the swap")
	var swapped := false
	for i in range(1500):
		await _wait(2)
		dock.call("_swap_placeholder_textures")
		if sessions.all(func(s): return not (s.texture is ImageTexture)):
			swapped = true
			break
	print("PHTEST  sessions after waiting: ", _kinds(sessions))
	var stroke := Vector2i(int(0.21 * size), int(0.305 * size))
	_check(swapped, "every placeholder is replaced by the imported PNG once Godot has imported it")
	for s in sessions:
		var live := GDDrawMaterialChannels.read_texture(s.target.get_material_for_slot(s.material_slot), s.channel)
		_check(live != null and not (live is ImageTexture) and live.resource_path == s.texture_path, "%s: the scene material uses %s" % [s.channel, s.texture_path])
		var private_tex := GDDrawMaterialChannels.read_texture(s.material, s.channel)
		_check(private_tex != null and not (private_tex is ImageTexture), "%s: and so does the session material" % s.channel)
	var swapped_active := GDDrawMaterialChannels.read_texture(active.material, active.channel).get_image()
	_check(swapped_active.get_pixel(int(0.21 * size), int(0.305 * size)).r < 0.9 or swapped_active.get_pixel(int(0.21 * size), int(0.305 * size)).g < 0.9, "the painted pixels came through the swap")
	var embedded_after := _embedded_images(edited_root)
	_check(embedded_after == 0, "a scene saved now embeds no images (%d)" % embedded_after)
	var scene_bytes := FileAccess.get_file_as_bytes("res://ph_check.tscn").size()
	_check(scene_bytes < 200000, "and stays small (%d bytes)" % scene_bytes)
	_check(dock.get("_material_brush_active") != null, "the dock is still healthy")
	print("PHTEST  RESULT: ", "ALL PASSED" if _fail == 0 else "%d FAILED" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
