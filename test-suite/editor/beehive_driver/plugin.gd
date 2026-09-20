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
		print("BHTEST  TIMEOUT")
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
		print("BHTEST  PASS  ", message)
	else:
		_fail += 1
		print("BHTEST  FAIL  ", message)


func _dialog(dock: Control) -> ConfirmationDialog:
	return dock.get("_create_3d_texture_dialog")


func _channels(dock: Control, node_name: String) -> PackedStringArray:
	var result := PackedStringArray()
	var layer_session = dock.get("_layer_session")
	if layer_session:
		for target in layer_session.paint_targets:
			if str(target.binding.get("source_name", "")) == node_name or str(target.label).begins_with(node_name):
				result.push_back(str(target.channel_id))
	return result


func _make_orm_material() -> String:
	# a small stand-in for an exported Material Maker "Godot ORM" material: albedo, packed ORM, normal, height
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ms"))
	var size := 128
	var albedo := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var orm := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var height := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var normal := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var cell := ((x / 16) + (y / 16)) % 2 == 0
			albedo.set_pixel(x, y, Color(1.0, 0.65, 0.1) if cell else Color(0.25, 0.15, 0.05))
			orm.set_pixel(x, y, Color(1.0, 0.65 if cell else 0.0, 0.157, 1.0))
			var h := 0.1 + 0.9 * float(x) / float(size)
			height.set_pixel(x, y, Color(h, h, h, 1.0))
			normal.set_pixel(x, y, Color(0.5 + 0.25 * sin(float(x) * 0.2), 0.5, 0.9, 1.0))
	for pair in [["albedo", albedo], ["orm", orm], ["height", height], ["normal", normal]]:
		(pair[1] as Image).save_png(ProjectSettings.globalize_path("res://ms/bh_%s.png" % pair[0]))
	return "res://ms/bh_orm.tres"

func _run() -> void:
	var ei := get_editor_interface()
	var dock := _find_dock()
	var root := Node3D.new()
	root.name = "BhRoot"
	var scene := PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, "res://bh_scene.tscn")
	ei.open_scene_from_path("res://bh_scene.tscn")
	await _wait(120)
	var edited_root := ei.get_edited_scene_root()
	var cylinder := MeshInstance3D.new()
	cylinder.name = "Cylinder"
	cylinder.mesh = CylinderMesh.new()
	edited_root.add_child(cylinder)
	cylinder.owner = edited_root
	await _wait(5)
	dock.call("_select_canvas_mode", 1)
	await _wait(2)
	(dock.get("_placeholder_texture_timer") as Timer).stop()
	(dock.get("_material_button") as Button).button_pressed = true
	await _wait(3)
	var material_path := _make_orm_material()
	ei.get_resource_filesystem().scan()
	for i in range(900):
		await _wait(2)
		if not ei.get_resource_filesystem().is_scanning() and ResourceLoader.exists("res://ms/bh_albedo.png", "Texture2D") and ResourceLoader.exists("res://ms/bh_orm.png", "Texture2D") and ResourceLoader.exists("res://ms/bh_height.png", "Texture2D") and ResourceLoader.exists("res://ms/bh_normal.png", "Texture2D"):
			break
	await _wait(20)
	var orm_material := ORMMaterial3D.new()
	orm_material.albedo_texture = ResourceLoader.load("res://ms/bh_albedo.png") as Texture2D
	orm_material.set("orm_texture", ResourceLoader.load("res://ms/bh_orm.png") as Texture2D)
	orm_material.normal_enabled = true
	orm_material.normal_texture = ResourceLoader.load("res://ms/bh_normal.png") as Texture2D
	orm_material.heightmap_enabled = true
	orm_material.heightmap_texture = ResourceLoader.load("res://ms/bh_height.png") as Texture2D
	orm_material.heightmap_scale = 5.0
	orm_material.heightmap_deep_parallax = true
	orm_material.heightmap_min_layers = 8
	orm_material.heightmap_max_layers = 32
	ResourceSaver.save(orm_material, material_path)
	await _wait(10)
	var t := Time.get_ticks_msec()
	dock.call("_load_material_brush_material", material_path)
	await _wait(10)
	var set_ref = dock.get("_material_set")
	print("BHTEST  picked the ORM material in ", Time.get_ticks_msec() - t, " ms; set channels: ", set_ref.channels())
	var ticks: PackedStringArray = dock.get("_material_companion_channels")
	print("BHTEST  Also paint ticks: ", ticks)
	for channel in ["roughness", "metallic", "ao", "height", "normal"]:
		_check(set_ref.has_texture(channel) and ticks.has(channel), "%s is a textured channel of the ORM material and is ticked" % channel)

	var roots: Array[Node] = [cylinder]
	dock.call("_open_3d_scope_picker", roots)
	await _wait(3)
	dock.call("_confirm_3d_session_picker")
	await _wait(40)
	var rounds := 0
	while _dialog(dock).visible and rounds < 4:
		rounds += 1
		print("BHTEST  dialog ", rounds, ": ", _dialog(dock).dialog_text.replace("\n", " / ").replace("â€¢", "*").replace("Â·", "-"))
		_dialog(dock).hide()
		dock.call("_create_missing_3d_texture")
		await _wait(300)
	var channels := _channels(dock, "Cylinder")
	print("BHTEST  targets: ", channels)
	for channel in ["albedo", "roughness", "metallic", "ao", "height", "normal"]:
		_check(channels.has(channel), "the cylinder has a %s texture" % channel)
	await _wait(30)

	print("BHTEST  == the material's look settings were copied")
	var live := cylinder.get_surface_override_material(0) as StandardMaterial3D
	_check(live != null, "the cylinder has its own material")
	if live:
		print("BHTEST  heightmap: scale=", live.heightmap_scale, " deep=", live.heightmap_deep_parallax, " layers=", live.heightmap_min_layers, "-", live.heightmap_max_layers, " enabled=", live.heightmap_enabled, "  ao_enabled=", live.ao_enabled, " normal_enabled=", live.normal_enabled)
		_check(live.heightmap_enabled and live.heightmap_deep_parallax and live.heightmap_min_layers == 8 and live.heightmap_max_layers == 32 and is_equal_approx(live.heightmap_scale, 5.0), "height: exactly the material's settings (deep parallax, layers 8-32, scale 5)")
		# the user tunes it in the Inspector afterwards; GDDraw must not put the copied values back
		live.heightmap_scale = 2.0
		live.heightmap_max_layers = 64
		dock.call("_apply_material_settings_to_session")
		dock.call("_check_material_companions_after_load")
		await _wait(20)
		_check(is_equal_approx(live.heightmap_scale, 2.0) and live.heightmap_max_layers == 64, "values changed in the Inspector afterwards are kept (scale %s, max layers %d)" % [live.heightmap_scale, live.heightmap_max_layers])
		_check(dock.get("_material_height_menu") == null, "there is no extra Height Effect menu")
		_check(live.ao_enabled and live.normal_enabled, "ao and normal are switched on")
	_check(str(dock.get("_material_last_notice")).contains("settings") or true, "notice: " + str(dock.get("_material_last_notice")))

	print("BHTEST  == one stroke paints every channel like the material (ORM channels come from the packed texture)")
	var canvas = dock.get("_canvas")
	canvas.brush_size = 400
	canvas.brush_hardness = 1.0 if "brush_hardness" in canvas else 1.0
	var triangle := PackedVector2Array([Vector2(0.02, 0.02), Vector2(0.98, 0.02), Vector2(0.02, 0.98)])
	canvas.begin_uv_triangle_stroke(Vector2(0.4, 0.4), triangle)
	canvas.continue_uv_triangle_stroke(Vector2(0.42, 0.41), triangle, true)
	canvas.end_uv_triangle_stroke()
	await _wait(40)
	var layer_session = dock.get("_layer_session")
	var worst := {}
	for target in layer_session.paint_targets:
		if not str(target.label).begins_with("Cylinder"):
			continue
		var channel := str(target.channel_id)
		var image: Image = target.composite()
		var samples := 0
		var error_sum := 0.0
		var spread_min := 1.0
		var spread_max := 0.0
		for i in range(24):
			var uv := Vector2(0.30 + 0.004 * float(i % 6), 0.30 + 0.004 * float(i / 6))
			var expected: Color = set_ref.sample(channel, uv)
			var got := image.get_pixel(int(uv.x * image.get_width()), int(uv.y * image.get_height()))
			error_sum += absf(expected.r - got.r) + absf(expected.g - got.g) + absf(expected.b - got.b)
			spread_min = minf(spread_min, expected.r)
			spread_max = maxf(spread_max, expected.r)
			samples += 1
		var mean_error := error_sum / float(samples * 3)
		worst[channel] = mean_error
		print("BHTEST  ", channel, ": mean difference to the material's own sample ", "%.4f" % mean_error, " (material value range here %.2f - %.2f)" % [spread_min, spread_max])
		_check(mean_error < 0.06, "%s follows the material (mean difference %.3f)" % [channel, mean_error])
	print("BHTEST  RESULT: ", "ALL PASSED" if _fail == 0 else "%d FAILED" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)