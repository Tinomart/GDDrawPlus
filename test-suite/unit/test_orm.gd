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


func save_png(name: String, color: Color, size := 64) -> String:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(color)
	var path := "res://tmp_orm/%s.png" % name
	image.save_png(ProjectSettings.globalize_path(path))
	return path


func near(a: float, b: float, tolerance := 0.02) -> bool:
	return absf(a - b) <= tolerance


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp_orm"))
	print("== File names")
	check(GDDrawMaterialSet.classify_file_name("beehive_orm")[0] == "orm", "beehive_orm is a packed ORM texture")
	check(GDDrawMaterialSet.classify_file_name("brick_arm")[0] == "orm", "brick_arm (occlusion/roughness/metallic) too")
	check(GDDrawMaterialSet.classify_file_name("BeeHive_heightmap")[0] == "height", "BeeHive_heightmap is a height map")
	check(GDDrawMaterialSet.classify_file_name("swarm")[0] == "", "swarm is not an ORM texture (needs a separator)")
	check(GDDrawMaterialSet.classify_file_name("stone_normal")[0] == "normal" and GDDrawMaterialSet.classify_file_name("stone_ao")[0] == "ao", "the other words still work")

	print("== A texture set with a packed ORM image")
	save_png("t_albedo", Color(0.8, 0.2, 0.1))
	save_png("t_orm", Color(0.9, 0.4, 0.2))
	save_png("t_normal", Color(0.5, 0.5, 1.0))
	save_png("t_heightmap", Color(0.3, 0.3, 0.3))
	var set_files := GDDrawMaterialSet.load_from_path("res://tmp_orm/t_albedo.png")
	check(set_files != null, "the set loads")
	if set_files:
		var channels := set_files.channels()
		check(channels == PackedStringArray(["albedo", "roughness", "metallic", "ao", "height", "normal"]), "all six channels are found: " + str(channels))
		check(near(set_files.sample("ao", Vector2(0.5, 0.5)).r, 0.9), "ambient occlusion is the red channel of the ORM image (%.2f)" % set_files.sample("ao", Vector2(0.5, 0.5)).r)
		check(near(set_files.sample("roughness", Vector2(0.5, 0.5)).r, 0.4), "roughness is the green channel (%.2f)" % set_files.sample("roughness", Vector2(0.5, 0.5)).r)
		check(near(set_files.sample("metallic", Vector2(0.5, 0.5)).r, 0.2), "metallic is the blue channel (%.2f)" % set_files.sample("metallic", Vector2(0.5, 0.5)).r)
		check(set_files.has_texture("roughness") and set_files.has_texture("ao"), "they count as textured channels")
		for channel in ["ao", "roughness", "metallic"]:
			var fast: Variant = set_files.fast_map(channel)
			check(fast is Image and (fast as Image).get_pixel(3, 3).is_equal_approx(set_files.sample(channel, Vector2(0.05, 0.05)).lerp(Color(0, 0, 0, 1), 0.0)) or (fast is Image and near((fast as Image).get_pixel(3, 3).r, set_files.sample(channel, Vector2(0.05, 0.05)).r)), "%s has a native fast map with the same value" % channel)
		var settings := set_files.target_settings()
		check(settings.has("height") and bool(settings["height"].get("heightmap_deep_parallax", false)) and int(settings["height"].get("heightmap_max_layers", 0)) == 32, "a texture set's height map gets deep parallax with layers: " + str(settings))
	print("== Separate files win over the packed one")
	save_png("u_albedo", Color.WHITE)
	save_png("u_orm", Color(0.9, 0.4, 0.2))
	save_png("u_roughness", Color(0.7, 0.7, 0.7))
	var set_mixed := GDDrawMaterialSet.load_from_path("res://tmp_orm/u_albedo.png")
	check(set_mixed != null and near(set_mixed.sample("roughness", Vector2(0.5, 0.5)).r, 0.7) and near(set_mixed.sample("metallic", Vector2(0.5, 0.5)).r, 0.2), "u_roughness.png is used for roughness, the ORM image still gives metallic")

	print("== An ORMMaterial3D")
	var orm_image := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	orm_image.fill(Color(1.0, 0.65, 0.16))
	var orm_texture := ImageTexture.create_from_image(orm_image)
	var orm_material := ORMMaterial3D.new()
	orm_material.set("orm_texture", orm_texture)
	orm_material.heightmap_enabled = true
	orm_material.heightmap_texture = ImageTexture.create_from_image(orm_image)
	orm_material.heightmap_scale = 3.5
	orm_material.heightmap_deep_parallax = true
	orm_material.heightmap_min_layers = 6
	orm_material.heightmap_max_layers = 20
	var before_signature := GDDrawMaterialSet.material_signature(orm_material)
	var from_orm := GDDrawMaterialSet.load_from_material(orm_material, "res://x/Demo.tres")
	check(from_orm != null and from_orm.has_texture("ao") and from_orm.has_texture("roughness") and from_orm.has_texture("metallic"), "ambient occlusion, roughness and metallic come from the orm_texture")
	if from_orm:
		check(near(from_orm.sample("roughness", Vector2(0.5, 0.5)).r, 0.65) and near(from_orm.sample("metallic", Vector2(0.5, 0.5)).r, 0.16) and near(from_orm.sample("ao", Vector2(0.5, 0.5)).r, 1.0), "with the values packed in it (0.65 / 0.16 / 1.0)")
		var settings2 := from_orm.target_settings()
		check(settings2.has("height") and is_equal_approx(float(settings2["height"]["heightmap_scale"]), 3.5) and bool(settings2["height"]["heightmap_deep_parallax"]) and int(settings2["height"]["heightmap_min_layers"]) == 6 and int(settings2["height"]["heightmap_max_layers"]) == 20, "the material's height settings are what gets copied to painted objects: " + str(settings2.get("height")))
	orm_material.set("orm_texture", null)
	check(GDDrawMaterialSet.material_signature(orm_material) != before_signature, "removing the ORM texture changes the signature (the brush notices the edit)")
	orm_material.heightmap_scale = 9.0
	orm_material.set("orm_texture", orm_texture)
	check(GDDrawMaterialSet.material_signature(orm_material) != before_signature, "and so does a different height scale")

	print("== glTF-style packed StandardMaterial3D keeps working (and is native now)")
	var packed := StandardMaterial3D.new()
	var packed_image := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	packed_image.fill(Color(0.0, 0.3, 0.8))
	var packed_texture := ImageTexture.create_from_image(packed_image)
	packed.roughness_texture = packed_texture
	packed.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	packed.metallic_texture = packed_texture
	packed.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	packed.metallic = 1.0  # Godot multiplies the metallic texture by this value (default 0)
	var from_packed := GDDrawMaterialSet.load_from_material(packed)
	check(from_packed != null and near(from_packed.sample("roughness", Vector2(0.5, 0.5)).r, 0.3) and near(from_packed.sample("metallic", Vector2(0.5, 0.5)).r, 0.8), "green is roughness, blue is metallic")
	if from_packed:
		var fast_rough: Variant = from_packed.fast_map("roughness")
		check(fast_rough is Image and near((fast_rough as Image).get_pixel(2, 2).r, 0.3), "the single channel is extracted for the native brush path")
		check(from_packed.target_settings().is_empty(), "no height texture, so no settings to copy")