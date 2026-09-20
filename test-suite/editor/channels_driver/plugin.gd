@tool
extends EditorPlugin

var failures := 0
var _frames := 0
var _started := false
var _plugin_ref


func check(condition: bool, message: String) -> void:
	if condition:
		print("CHTEST  PASS  ", message)
	else:
		failures += 1
		print("CHTEST  FAIL  ", message)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 240 and not _started:
		_started = true
		_run()
	if _frames == 7000:
		print("CHTEST  TIMEOUT")
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


func _make_node(node_name: String, material: StandardMaterial3D, parent: Node) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	# GDDraw paints ArrayMesh geometry (as imported scenes have), not PrimitiveMesh resources.
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, CapsuleMesh.new().get_mesh_arrays())
	mesh.surface_set_material(0, material)
	node.mesh = mesh
	parent.add_child(node)
	node.owner = parent
	return node


func _begin(node: Node3D, channel: String, create: bool, size := Vector2i(64, 64)) -> Dictionary:
	var discovery: Dictionary = GDDraw3DLayerDiscovery.new().discover([node], GDDraw3DLayerDiscovery.Scope.SELECTED_SURFACE, channel)
	var coordinator := GDDraw3DLayerCoordinator.new()
	var result: Dictionary = {"status": "error", "message": "discovery failed: " + str(discovery.get("message", ""))}
	if str(discovery.get("status")) == "ok":
		result = coordinator.begin(discovery, _plugin_ref, create, "res://gddraw/images", size)
	return {"discovery": discovery, "coordinator": coordinator, "result": result}


func _mat(node: MeshInstance3D) -> StandardMaterial3D:
	return node.get_active_material(0) as StandardMaterial3D


func _pixel(path: String, x := 3, y := 3) -> Color:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	return image.get_pixel(x, y) if image else Color(-1, -1, -1, -1)


func _run() -> void:
	var ei := get_editor_interface()
	var dock := _find_dock()
	check(dock != null, "GDDraw dock present")
	if dock == null:
		get_tree().quit(1)
		return
	_plugin_ref = dock.get_meta("gddraw_plugin")

	# Scene: blank root we add nodes to.
	var root := Node3D.new()
	root.name = "ChannelRoot"
	var scene := PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, "res://channel_scene.tscn")
	ei.open_scene_from_path("res://channel_scene.tscn")
	for _i in range(90):
		await get_tree().process_frame
	var edited_root := ei.get_edited_scene_root()
	check(edited_root != null, "scene opened")

	# Hero: albedo texture on disk, roughness 0.4, metallic 0.2, nothing else.
	var hero_material := StandardMaterial3D.new()
	hero_material.albedo_texture = _save_png("res://tex/hero_albedo.png", Vector2i(64, 64), Color.WHITE)
	hero_material.roughness = 0.4
	hero_material.metallic = 0.2
	var hero := _make_node("Hero", hero_material, edited_root)

	# Packed: glTF style, one texture for roughness (G) and metallic (B).
	var packed_material := StandardMaterial3D.new()
	packed_material.albedo_texture = _save_png("res://tex/packed_albedo.png", Vector2i(32, 32), Color.WHITE)
	var packed_texture := _save_png("res://tex/packed_mr.png", Vector2i(32, 32), Color(0.0, 0.8, 0.25, 1.0))
	packed_material.roughness_texture = packed_texture
	packed_material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	packed_material.metallic_texture = packed_texture
	packed_material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	packed_material.roughness = 1.0
	packed_material.metallic = 1.0
	var packed := _make_node("Packed", packed_material, edited_root)
	await get_tree().process_frame

	print("CHTEST  == A) discovery and creation, no dock involved")
	var albedo_run := _begin(hero, "albedo", false)
	var albedo_targets: Array = albedo_run["discovery"].get("targets", [])
	check(str(albedo_run["discovery"].get("status")) == "ok" and albedo_targets.size() == 1 and albedo_targets[0]["channel"] == "albedo", "albedo discovery is unchanged: one supported target")
	check(str(albedo_run["result"].get("status")) == "ok", "albedo session opens exactly as before (%s)" % str(albedo_run["result"].get("message")))
	var albedo_session = albedo_run["coordinator"].get_active_texture_session()
	check(albedo_session != null and albedo_session.channel == "albedo" and albedo_session.texture_path == "res://tex/hero_albedo.png", "albedo session paints the existing albedo file")

	var rough_discovery: Dictionary = GDDraw3DLayerDiscovery.new().discover([hero], GDDraw3DLayerDiscovery.Scope.SELECTED_SURFACE, "roughness")
	var rough_targets: Array = rough_discovery.get("targets", [])
	check(str(rough_discovery.get("status")) == "ok" and rough_targets.size() == 1, "roughness discovery finds one target")
	if rough_targets.size() == 1:
		check(rough_targets[0]["channel"] == "roughness" and bool(rough_targets[0]["missing_texture"]), "it is a roughness target whose texture is still missing")
		check(str(rough_targets[0]["label"]).contains("Roughness"), "its label names the channel (%s)" % str(rough_targets[0]["label"]))
	var rough_pending := _begin(hero, "roughness", false)
	check(str(rough_pending["result"].get("status")) == "needs_create", "without permission nothing is created (needs_create)")
	check(hero_material.roughness_texture == null and is_equal_approx(hero_material.roughness, 0.4) and hero.get_surface_override_material(0) == null, "and the material is untouched (no override created)")
	var rough_run := _begin(hero, "roughness", true)
	check(str(rough_run["result"].get("status")) == "ok", "with permission the roughness session opens (%s)" % str(rough_run["result"].get("message")))
	var rough_session = rough_run["coordinator"].get_active_texture_session()
	if rough_session:
		check(rough_session.channel == "roughness", "the session paints the roughness channel")
		check(rough_session.texture_path.ends_with("_roughness.png") and FileAccess.file_exists(rough_session.texture_path), "a roughness PNG was created: %s" % rough_session.texture_path)
		var rp := _pixel(rough_session.texture_path)
		check(absf(rp.r - 0.4) < 0.01 and absf(rp.g - 0.4) < 0.01 and absf(rp.b - 0.4) < 0.01, "it starts at the material's roughness 0.4 as gray (%s)" % str(rp))
	var hero_live := _mat(hero)
	check(hero_live.roughness_texture != null and is_equal_approx(hero_live.roughness, 1.0), "material: texture assigned, roughness multiplier reset to 1.0 (so the texture is the value)")
	check(is_equal_approx(hero_material.roughness, 0.4) and hero_material.roughness_texture == null, "the mesh's own material is left alone: GDDraw edits a surface override copy")
	check(hero_live.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED, "material reads the RED channel")
	check(hero_live.albedo_texture != null and str(hero_live.albedo_texture.get_meta("gddraw_source_path")) == "res://tex/hero_albedo.png", "the albedo texture is untouched")

	var again := _begin(hero, "roughness", false)
	check(str(again["result"].get("status")) == "ok", "the second time the roughness texture is simply opened")
	var again_session = again["coordinator"].get_active_texture_session()
	check(again_session != null and again_session.texture_path == rough_session.texture_path, "it is the same file")

	for spec in [["metallic", 0.2], ["ao", 1.0], ["height", 1.0]]:
		var run := _begin(hero, spec[0], true)
		var session = run["coordinator"].get_active_texture_session()
		check(str(run["result"].get("status")) == "ok" and session != null, "%s: session opens after creating its texture" % spec[0])
		if session:
			var p := _pixel(session.texture_path)
			check(absf(p.r - float(spec[1])) < 0.01, "%s: starts at %s (got %s)" % [spec[0], str(spec[1]), str(p.r)])
	hero_live = _mat(hero)
	check(is_equal_approx(hero_live.metallic, 1.0) and hero_live.metallic_texture != null, "metallic: multiplier reset to 1.0, texture assigned")
	check(hero_live.ao_enabled and hero_live.ao_texture != null, "ambient occlusion: switched on with its texture")
	check(hero_live.heightmap_enabled and hero_live.heightmap_texture != null, "height: switched on with its texture")
	var emission_run := _begin(hero, "emission", true)
	var emission_session = emission_run["coordinator"].get_active_texture_session()
	check(emission_session != null and hero_live.emission_enabled and hero_live.emission == Color.WHITE and hero_live.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY, "emission: switched on, colour white, Multiply operator")
	if emission_session:
		check(_pixel(emission_session.texture_path).is_equal_approx(Color.BLACK), "emission texture starts black (nothing glows yet)")

	print("CHTEST  == A2) a packed texture is never overwritten")
	var packed_discovery: Dictionary = GDDraw3DLayerDiscovery.new().discover([packed], GDDraw3DLayerDiscovery.Scope.SELECTED_SURFACE, "roughness")
	var packed_targets: Array = packed_discovery.get("targets", [])
	check(packed_targets.size() == 1 and bool(packed_targets[0]["missing_texture"]) and str(packed_targets[0]["label"]).contains("Packed"), "roughness on a packed texture is offered as 'will be separated'")
	var packed_run := _begin(packed, "roughness", true)
	var packed_session = packed_run["coordinator"].get_active_texture_session()
	check(str(packed_run["result"].get("status")) == "ok" and packed_session != null, "a dedicated roughness texture is created (%s)" % str(packed_run["result"].get("message")))
	if packed_session:
		var pp := _pixel(packed_session.texture_path, 2, 2)
		check(absf(pp.r - 0.8) < 0.01, "it was unpacked from the GREEN channel: 0.8 (got %s)" % str(pp.r))
		var packed_live := _mat(packed)
		check(packed_live.roughness_texture != packed_live.metallic_texture and packed_live.roughness_texture != null, "roughness and metallic no longer share a texture")
		var metallic_image: Image = packed_live.metallic_texture.get_image() if packed_live.metallic_texture else null
		check(metallic_image != null and absf(metallic_image.get_pixel(2, 2).b - 0.25) < 0.01 and absf(metallic_image.get_pixel(2, 2).g - 0.8) < 0.01, "metallic still uses the original packed texture (its pixels are unchanged)")
		var original := _pixel("res://tex/packed_mr.png", 2, 2)
		check(absf(original.g - 0.8) < 0.01 and absf(original.b - 0.25) < 0.01, "the original packed file on disk is unchanged")

	print("CHTEST  == A3) saving writes the channel's own file")
	if rough_session:
		var painted := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
		painted.fill(Color(0.9, 0.9, 0.9, 1.0))
		var saved: Dictionary = rough_session.save_image(painted, _plugin_ref)
		check(str(saved.get("status")) == "ok", "save_image succeeds (%s)" % str(saved.get("message")))
		check(absf(_pixel(rough_session.texture_path).r - 0.9) < 0.01, "the roughness PNG now holds the painted value")
		check(str(hero_material.albedo_texture.get_meta("gddraw_source_path")) == "res://tex/hero_albedo.png" and absf(_pixel("res://tex/hero_albedo.png").r - 1.0) < 0.01, "the albedo file is not touched by a roughness save")

	print("CHTEST  == B) the toolbar dropdown")
	var selector: OptionButton = dock.get("_channel_selector")
	var view_selector: OptionButton = dock.get("_view_mode_selector")
	check(selector != null and view_selector != null, "the dock has a channel dropdown")
	if selector and view_selector:
		# the channel dropdown is the last item of the scrolling tool area, which sits directly left of the pinned 2D/3D/Split selector
		var scroll_area: Node = selector.get_parent().get_parent()
		check(scroll_area is ScrollContainer and scroll_area.get_parent() == view_selector.get_parent() and scroll_area.get_index() == view_selector.get_index() - 1 and selector.get_index() == selector.get_parent().get_child_count() - 1, "it sits directly left of the 2D/3D/Split selector (end of the scrolling tool area)")
		var labels := []
		for i in range(selector.item_count):
			labels.append(selector.get_item_text(i))
		check(labels == ["Albedo", "Emission", "Roughness", "Metallic", "Ambient Occlusion", "Height", "Normal"], "it lists the seven channels: %s" % str(labels))
		dock.call("_sync_channel_selector_from_session")
		check(not selector.visible, "it is hidden in 2D mode")
		dock.call("_select_canvas_mode", 1)
		await get_tree().process_frame
		dock.call("_sync_channel_selector_from_session")
		check(selector.visible, "it appears in 3D mode")
		check(selector.selected == 0 and dock.get("_paint_channel") == "albedo", "Albedo is the default")

		var canvas = dock.get("_canvas")
		dock.call("_on_channel_selected", 2)
		check(dock.get("_paint_channel") == "roughness", "choosing Roughness with no session just selects it for the next session")
		dock.call("_set_foreground_color", Color(1, 0, 0))
		check(is_equal_approx(canvas.brush_color.r, 1.0) and is_equal_approx(canvas.brush_color.g, 0.0), "no session yet: the brush colour is not restricted")

		print("CHTEST  == B2) a real 3D session in the roughness channel")
		var session_discovery: Dictionary = GDDraw3DLayerDiscovery.new().discover([hero], GDDraw3DLayerDiscovery.Scope.SELECTED_SURFACE, "roughness")
		dock.call("_begin_3d_layer_session", session_discovery, true)
		for _i in range(120):
			await get_tree().process_frame
		var dock_session = dock.get("_texture_3d_session")
		check(dock_session != null and dock_session.has_active_session() and dock_session.channel == "roughness", "the dock opened a roughness session")
		check(dock.call("_get_effective_paint_channel") == "roughness", "the dock reports roughness as the painted channel")
		check(selector.selected == 2, "the dropdown shows Roughness")
		dock.call("_set_foreground_color", Color(1, 0, 0))
		check(is_equal_approx(canvas.brush_color.r, canvas.brush_color.g) and is_equal_approx(canvas.brush_color.g, canvas.brush_color.b), "in a scalar channel a picked red becomes gray (%s)" % str(canvas.brush_color))

		print("CHTEST  == B3) switching channel reopens the same objects")
		selector.select(1)
		dock.call("_on_channel_selected", 1)
		for _i in range(30):
			await get_tree().process_frame
		if int(dock.get("_pending_session_transition")) != 0:
			dock.call("_continue_pending_session_transition")
			for _i in range(120):
				await get_tree().process_frame
		dock_session = dock.get("_texture_3d_session")
		check(dock_session != null and dock_session.has_active_session() and dock_session.channel == "emission", "choosing Emission reopened the objects in the emission channel")
		check(selector.selected == 1, "the dropdown follows")
		dock.call("_set_foreground_color", Color(1, 0, 0))
		check(is_equal_approx(canvas.brush_color.r, 1.0) and is_equal_approx(canvas.brush_color.g, 0.0), "emission is a colour channel: red stays red")

	print("CHTEST  RESULT: ", "ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)
