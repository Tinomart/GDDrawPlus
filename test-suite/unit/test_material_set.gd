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


func save_png(path: String, fill: Color, size := Vector2i(4, 4)) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(fill)
	image.save_png(ProjectSettings.globalize_path(path))


func near(a: float, b: float, tolerance := 0.01) -> bool:
	return absf(a - b) <= tolerance


func near_color(a: Color, b: Color, tolerance := 0.01) -> bool:
	return near(a.r, b.r, tolerance) and near(a.g, b.g, tolerance) and near(a.b, b.b, tolerance)


func run() -> void:
	print("== File name classification")
	var cases := {
		"brick_albedo": ["albedo", "brick"],
		"Brick_Roughness": ["roughness", "brick"],
		"brick_ambient_occlusion": ["ao", "brick"],
		"brick_ao": ["ao", "brick"],
		"bricks_depth": ["height", "bricks"],
		"WoodBaseColor": ["albedo", "wood"],
		"brick-metallic": ["metallic", "brick"],
		"brick_emission": ["emission", "brick"],
		"brick_normal": ["normal", "brick"],
		"cacao": ["", "cacao"],
		"brick": ["", "brick"],
		"albedo": ["albedo", ""],
	}
	for base_name: String in cases:
		var result := GDDrawMaterialSet.classify_file_name(base_name)
		check(result[0] == cases[base_name][0] and result[1] == cases[base_name][1], "%s -> %s / '%s' (got %s / '%s')" % [base_name, cases[base_name][0], cases[base_name][1], result[0], result[1]])
	check(GDDrawMaterialSet.name_for_path("res://x/brick_albedo.png") == "brick" and GDDrawMaterialSet.name_for_path("res://x/Bark.tres") == "Bark" and GDDrawMaterialSet.name_for_path("res://x/plain.png") == "plain", "display names")

	print("== Texture set from files")
	save_png("res://ms_test/brick_albedo.png", Color(1.0, 0.0, 0.0, 1.0))
	save_png("res://ms_test/brick_roughness.png", Color(0.6, 0.6, 0.6, 1.0))
	save_png("res://ms_test/brick_metallic.png", Color(0.2, 0.2, 0.2, 1.0))
	save_png("res://ms_test/brick_normal.png", Color(0.5, 0.5, 1.0, 1.0))
	save_png("res://ms_test/stone_albedo.png", Color(0.0, 1.0, 0.0, 1.0))
	save_png("res://ms_test/plain.png", Color(0.0, 0.0, 1.0, 1.0))
	var errors: Array = []
	var brick := GDDrawMaterialSet.load_from_path("res://ms_test/brick_albedo.png", errors)
	check(brick != null, "a set loads from its albedo image")
	if brick:
		check(brick.channels() == PackedStringArray(["albedo", "roughness", "metallic", "normal"]), "siblings are found by name: " + str(brick.channels()))
		check(brick.display_name == "brick", "display name is the shared prefix")
		check(not brick.has_channel("ao") and not brick.has_channel("emission"), "channels the set lacks are absent")
		check(brick.sample("albedo", Vector2(0.3, 0.3)).is_equal_approx(Color(1, 0, 0, 1)), "albedo samples the red image")
		var rough := brick.sample("roughness", Vector2(0.1, 0.9))
		check(near(rough.r, 0.6) and near(rough.g, 0.6) and near(rough.b, 0.6) and rough.a == 1.0, "roughness samples as gray 0.6")
		check(near(brick.sample("metallic", Vector2(0.5, 0.5)).r, 0.2), "metallic samples as gray 0.2")
		check(brick.sample("ao", Vector2(0.5, 0.5)).a == 0.0, "a missing channel samples as transparent")
		check(brick.sample("albedo", Vector2(1.3, 2.3)).is_equal_approx(brick.sample("albedo", Vector2(0.3, 0.3))), "sampling wraps (tiles)")
		check(brick.describe() == "Albedo, Roughness, Metallic, Normal", "description lists the channels: " + brick.describe())
	var from_roughness := GDDrawMaterialSet.load_from_path("res://ms_test/brick_roughness.png", errors)
	check(from_roughness != null and from_roughness.channels() == PackedStringArray(["albedo", "roughness", "metallic", "normal"]), "picking any image of the set finds the whole set")
	var stone := GDDrawMaterialSet.load_from_path("res://ms_test/stone_albedo.png", errors)
	check(stone != null and stone.channels() == PackedStringArray(["albedo"]), "another set in the same folder is not mixed in")
	var plain := GDDrawMaterialSet.load_from_path("res://ms_test/plain.png", errors)
	check(plain != null and plain.channels() == PackedStringArray(["albedo"]) and plain.sample("albedo", Vector2(0.5, 0.5)).is_equal_approx(Color(0, 0, 1, 1)), "an image without a channel word is a plain albedo texture")

	print("== Bilinear sampling")
	var gradient := Image.create_empty(2, 1, false, Image.FORMAT_RGBA8)
	gradient.set_pixel(0, 0, Color.BLACK)
	gradient.set_pixel(1, 0, Color.WHITE)
	gradient.save_png(ProjectSettings.globalize_path("res://ms_test/ramp_albedo.png"))
	var ramp := GDDrawMaterialSet.load_from_path("res://ms_test/ramp_albedo.png", errors)
	if ramp:
		check(near(ramp.sample("albedo", Vector2(0.5, 0.5)).r, 0.5, 0.02), "halfway between two texels is the average")
		check(near(ramp.sample("albedo", Vector2(0.25, 0.5)).r, 0.0, 0.02) and near(ramp.sample("albedo", Vector2(0.75, 0.5)).r, 1.0, 0.02), "texel centers give the texel colors")
		check(near(ramp.sample("albedo", Vector2(0.0, 0.5)).r, 0.5, 0.02), "wrap-around blends the last texel with the first")

	print("== Rejected input")
	errors = []
	var from_normal := GDDrawMaterialSet.load_from_path("res://ms_test/brick_normal.png", errors)
	check(from_normal != null and from_normal.has_channel("normal") and from_normal.has_channel("albedo"), "picking a normal map finds the rest of its set")
	errors = []
	check(GDDrawMaterialSet.load_from_path("res://ms_test/missing_albedo.png", errors) == null and not errors.is_empty(), "a missing file is rejected with a message")
	errors = []
	check(GDDrawMaterialSet.load_from_path("res://ms_test/notes.txt", errors) == null and not errors.is_empty(), "an unsupported file type is rejected with a message")

	print("== StandardMaterial3D")
	var albedo_image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	albedo_image.fill(Color(1.0, 1.0, 1.0, 1.0))
	albedo_image.save_png(ProjectSettings.globalize_path("res://ms_test/mat_albedo_tex.png"))
	var packed_image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	packed_image.fill(Color(0.0, 0.8, 0.25, 1.0))
	packed_image.save_png(ProjectSettings.globalize_path("res://ms_test/mat_orm.png"))
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(albedo_image)
	material.albedo_color = Color(0.5, 0.5, 0.5, 1.0)
	material.roughness = 0.3
	material.roughness_texture = ImageTexture.create_from_image(packed_image)
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	material.metallic = 0.7
	material.ao_enabled = true
	material.ao_texture = ImageTexture.create_from_image(packed_image)
	material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	material.emission_enabled = false
	ResourceSaver.save(material, "res://ms_test/mat.tres")
	var from_material := GDDrawMaterialSet.load_from_path("res://ms_test/mat.tres", errors)
	check(from_material != null, "a StandardMaterial3D loads")
	if from_material:
		check(from_material.display_name == "mat", "material display name")
		check(from_material.has_texture("albedo") and near(from_material.sample("albedo", Vector2(0.5, 0.5)).r, 0.5), "albedo texture is multiplied by the albedo color")
		check(from_material.has_texture("roughness") and near(from_material.sample("roughness", Vector2(0.5, 0.5)).r, 0.8 * 0.3), "roughness = texture (green channel 0.8) x roughness value 0.3")
		check(from_material.has_texture("ao") and near(from_material.sample("ao", Vector2(0.5, 0.5)).r, 0.25), "ao reads its own channel (blue 0.25)")
		check(from_material.has_channel("metallic") and not from_material.has_texture("metallic") and near(from_material.sample("metallic", Vector2(0.5, 0.5)).r, 0.7), "a plain metallic value is offered as a constant")
		check(not from_material.has_channel("emission"), "disabled emission is not offered")
		check(not from_material.has_channel("height"), "no heightmap -> no height channel")
		check("Metallic (value)" in from_material.describe(), "constants are marked in the description: " + from_material.describe())
	errors = []
	check(GDDrawMaterialSet.load_from_path("res://ms_test/brick_albedo.tres", errors) == null and not errors.is_empty(), "a missing .tres is rejected")

	print("== Emission operator")
	var glow_image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	glow_image.fill(Color(0.0, 0.5, 0.0, 1.0))
	var glow := StandardMaterial3D.new()
	glow.emission_enabled = true
	glow.emission = Color(0.2, 0.0, 0.0, 1.0)
	glow.emission_texture = ImageTexture.create_from_image(glow_image)
	var added := GDDrawMaterialSet.load_from_material(glow, "res://ms_test/glow_add.tres")
	check(added != null and added.has_texture("emission") and near_color(added.sample("emission", Vector2(0.5, 0.5)), Color(0.2, 0.5, 0.0, 1.0)), "with the default Add operator the emission colour is added to the texture")
	glow.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	glow.emission = Color(1.0, 1.0, 1.0, 1.0)
	var multiplied := GDDrawMaterialSet.load_from_material(glow, "res://ms_test/glow_mul.tres")
	check(multiplied != null and near_color(multiplied.sample("emission", Vector2(0.5, 0.5)), Color(0.0, 0.5, 0.0, 1.0)), "with the Multiply operator the emission colour tints the texture")

	print("== Normal maps")
	save_png("res://ms_test/slate_albedo.png", Color(0.3, 0.3, 0.3, 1.0))
	save_png("res://ms_test/slate_normal_dx.png", Color(0.6, 0.3, 1.0, 1.0))
	var slate := GDDrawMaterialSet.load_from_path("res://ms_test/slate_normal_dx.png", errors)
	check(slate != null and slate.has_channel("normal") and slate.flip_normal_green, "a DirectX normal map (normal_dx) is flipped automatically")
	if slate:
		var flipped := slate.sample("normal", Vector2(0.5, 0.5))
		check(near(flipped.r, 0.6) and near(flipped.g, 0.7) and near(flipped.b, 1.0), "its green channel is inverted (0.3 -> 0.7): %s" % str(flipped))
		var fast: Variant = slate.fast_map("normal")
		check(fast is Image and near((fast as Image).get_pixel(1, 1).g, 0.7, 0.02), "and so is its native map")
		slate.flip_normal_green = false
		check(near(slate.sample("normal", Vector2(0.5, 0.5)).g, 0.3), "turning the flip off gives the stored green back")
		check(near((slate.fast_map("normal") as Image).get_pixel(1, 1).g, 0.3, 0.02), "and the native map follows")
	check(brick != null and not brick.flip_normal_green, "an OpenGL normal map is left as it is")
	var bumpy_image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	bumpy_image.fill(Color(0.6, 0.5, 1.0, 1.0))
	var bumpy := StandardMaterial3D.new()
	bumpy.normal_enabled = true
	bumpy.normal_texture = ImageTexture.create_from_image(bumpy_image)
	bumpy.normal_scale = 2.0
	var bumpy_set := GDDrawMaterialSet.load_from_material(bumpy, "res://ms_test/bumpy.tres")
	check(bumpy_set != null and bumpy_set.has_texture("normal") and near(bumpy_set.sample("normal", Vector2(0.5, 0.5)).r, 0.7, 0.02), "a material's normal scale strengthens the sampled normal (0.6 at scale 2 -> 0.7)")
	check(bumpy_set.fast_map("normal") == null, "a scaled normal map is painted per pixel")
	bumpy.normal_scale = 1.0
	var plain_bumpy := GDDrawMaterialSet.load_from_material(bumpy, "res://ms_test/bumpy.tres")
	check(plain_bumpy.fast_map("normal") is Image, "an unscaled one can be painted natively")
	bumpy.normal_enabled = false
	var off_set := GDDrawMaterialSet.load_from_material(bumpy, "res://ms_test/bumpy.tres")
	check(off_set != null and not off_set.has_channel("normal"), "normal mapping switched off gives no normal channel")