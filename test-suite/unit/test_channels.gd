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


func make_texture(fill: Color, size := Vector2i(8, 8)) -> ImageTexture:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(fill)
	return ImageTexture.create_from_image(image)


func run() -> void:
	print("== Definitions")
	check(GDDrawMaterialChannels.ids() == PackedStringArray(["albedo", "emission", "roughness", "metallic", "ao", "height", "normal"]), "seven channels in UI order")
	check(GDDrawMaterialChannels.has_channel("roughness") and GDDrawMaterialChannels.has_channel("normal") and not GDDrawMaterialChannels.is_scalar("normal"), "normal maps are a colour channel")
	var flat := GDDrawMaterialChannels.make_initial_image(StandardMaterial3D.new(), "normal", Vector2i(16, 16))
	var flat_pixel := flat.get_pixel(3, 3)
	check(absf(flat_pixel.r - 0.5) < 0.01 and absf(flat_pixel.g - 0.5) < 0.01 and flat_pixel.b > 0.99, "a new normal map starts flat (0.5, 0.5, 1.0): the surface looks as before")
	var normal_changes := {}
	for change in GDDrawMaterialChannels.property_changes_for_new_texture("normal", ImageTexture.new()):
		normal_changes[change["property"]] = change["value"]
	check(normal_changes.get("normal_enabled") == true and is_equal_approx(float(normal_changes.get("normal_scale", 0.0)), 1.0) and normal_changes.has("normal_texture"), "assigning a new normal texture switches normal mapping on at scale 1")
	check(GDDrawMaterialChannels.texture_property("normal") == "normal_texture" and GDDrawMaterialChannels.file_suffix("normal") == "normal", "normal texture property and file suffix")
	check(GDDrawMaterialChannels.get_definition("nonsense")["id"] == "albedo", "unknown channel ids fall back to albedo")
	check(GDDrawMaterialChannels.is_scalar("roughness") and GDDrawMaterialChannels.is_scalar("height") and not GDDrawMaterialChannels.is_scalar("emission") and not GDDrawMaterialChannels.is_scalar("albedo"), "scalar vs color kinds")
	check(GDDrawMaterialChannels.texture_property("ao") == "ao_texture" and GDDrawMaterialChannels.texture_property("height") == "heightmap_texture", "texture property names")
	# every declared property must really exist on StandardMaterial3D
	var probe := StandardMaterial3D.new()
	var property_names := {}
	for p in probe.get_property_list():
		property_names[p["name"]] = true
	var all_exist := true
	for definition in GDDrawMaterialChannels.CHANNELS:
		for key in ["texture", "enable", "value", "selector"]:
			var name: String = definition[key]
			if name != "" and not property_names.has(name):
				all_exist = false
				print("      missing property on StandardMaterial3D: ", name)
	check(all_exist, "every property named in the channel table exists on StandardMaterial3D")
	for name in GDDrawMaterialChannels.OTHER_TEXTURE_PROPERTIES:
		if not property_names.has(name):
			all_exist = false
			print("      missing packed-check property: ", name)
	check(all_exist, "every property used for packed-texture detection exists")

	print("== Read / write texture")
	var material := StandardMaterial3D.new()
	var rough_tex := make_texture(Color(0.3, 0.3, 0.3))
	check(GDDrawMaterialChannels.read_texture(material, "roughness") == null, "empty slot reads as null")
	check(GDDrawMaterialChannels.write_texture(material, "roughness", rough_tex), "write_texture sets the roughness slot")
	check(material.roughness_texture == rough_tex and GDDrawMaterialChannels.read_texture(material, "roughness") == rough_tex, "the material now holds it")
	check(not GDDrawMaterialChannels.is_packed(material, "roughness"), "a texture used only by roughness is not packed")
	check(GDDrawMaterialChannels.get_editable_texture(material, "roughness") == rough_tex, "and is editable")

	print("== Packed textures (glTF style: one texture for metallic + roughness)")
	var packed_material := StandardMaterial3D.new()
	var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	for y in range(4):
		for x in range(4):
			# R unused, G = roughness 0.8, B = metallic 0.25
			image.set_pixel(x, y, Color(0.0, 0.8, 0.25, 1.0))
	var packed_texture := ImageTexture.create_from_image(image)
	packed_material.roughness_texture = packed_texture
	packed_material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	packed_material.metallic_texture = packed_texture
	packed_material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	packed_material.roughness = 1.0
	packed_material.metallic = 1.0
	check(GDDrawMaterialChannels.is_packed(packed_material, "roughness") and GDDrawMaterialChannels.is_packed(packed_material, "metallic"), "shared texture is detected as packed for both channels")
	check(GDDrawMaterialChannels.get_editable_texture(packed_material, "roughness") == null, "a packed texture is not directly editable (would clobber the other channel)")
	var rough_image := GDDrawMaterialChannels.make_initial_image(packed_material, "roughness", Vector2i(64, 64))
	check(rough_image.get_size() == Vector2i(4, 4), "unpacking keeps the source resolution")
	check(is_equal_approx(rough_image.get_pixel(1, 1).r, 0.8) and is_equal_approx(rough_image.get_pixel(1, 1).g, 0.8) and is_equal_approx(rough_image.get_pixel(1, 1).b, 0.8), "roughness unpacked from the GREEN channel (0.8) as gray")
	var metal_image := GDDrawMaterialChannels.make_initial_image(packed_material, "metallic", Vector2i(64, 64))
	check(absf(metal_image.get_pixel(2, 2).r - 0.25) < 0.005, "metallic unpacked from the BLUE channel (0.25)")
	packed_material.roughness = 0.5
	var scaled := GDDrawMaterialChannels.make_initial_image(packed_material, "roughness", Vector2i(64, 64))
	check(absf(scaled.get_pixel(0, 0).r - 0.4) < 0.005, "the roughness multiplier (0.5) is baked in: 0.8 x 0.5 = 0.4")
	check(GDDrawMaterialChannels.is_packed(packed_material, "albedo") == false, "albedo is never treated as packed")

	print("== New textures for empty slots")
	var plain := StandardMaterial3D.new()
	plain.roughness = 0.4
	plain.metallic = 0.2
	var r := GDDrawMaterialChannels.make_initial_image(plain, "roughness", Vector2i(32, 16))
	check(r.get_size() == Vector2i(32, 16) and absf(r.get_pixel(3, 3).r - 0.4) < 0.005, "roughness texture starts at the material's roughness (0.4)")
	var m := GDDrawMaterialChannels.make_initial_image(plain, "metallic", Vector2i(16, 16))
	check(absf(m.get_pixel(0, 0).r - 0.2) < 0.005, "metallic texture starts at the material's metallic (0.2)")
	var ao := GDDrawMaterialChannels.make_initial_image(plain, "ao", Vector2i(16, 16))
	check(absf(ao.get_pixel(0, 0).r - 1.0) < 0.005, "ambient occlusion starts white (no occlusion)")
	var height := GDDrawMaterialChannels.make_initial_image(plain, "height", Vector2i(16, 16))
	check(absf(height.get_pixel(0, 0).r - 1.0) < 0.01, "height starts white (a white heightmap shifts nothing, so the surface looks as before)")
	var dark := GDDrawMaterialChannels.make_initial_image(plain, "emission", Vector2i(16, 16))
	check(dark.get_pixel(0, 0).is_equal_approx(Color.BLACK), "emission starts black when emission is off")
	plain.emission_enabled = true
	plain.emission = Color(1.0, 0.5, 0.0)
	var glow := GDDrawMaterialChannels.make_initial_image(plain, "emission", Vector2i(16, 16))
	var glow_pixel := glow.get_pixel(0, 0)
	check(absf(glow_pixel.r - 1.0) < 0.01 and absf(glow_pixel.g - 0.5) < 0.01 and absf(glow_pixel.b) < 0.01, "emission starts at the current emission colour")
	plain.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	var multiplied_glow := GDDrawMaterialChannels.make_initial_image(plain, "emission", Vector2i(16, 16))
	check(multiplied_glow.get_pixel(0, 0).is_equal_approx(Color.BLACK), "with the Multiply operator and no texture nothing glows, so emission starts black")
	plain.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
	check(GDDrawMaterialChannels.matching_size(plain, Vector2i(1024, 1024)) == Vector2i(1024, 1024), "size falls back to the requested size")
	plain.albedo_texture = make_texture(Color.WHITE, Vector2i(256, 128))
	check(GDDrawMaterialChannels.matching_size(plain, Vector2i(1024, 1024)) == Vector2i(256, 128), "size follows the albedo texture so all channels share the UV resolution")

	print("== Material changes that accompany a new texture")
	var fresh := StandardMaterial3D.new()
	fresh.roughness = 0.4
	var tex := make_texture(Color(0.4, 0.4, 0.4))
	var changes := GDDrawMaterialChannels.property_changes_for_new_texture("roughness", tex)
	var by_name := {}
	for change in changes:
		by_name[change["property"]] = change["value"]
	check(by_name.get("roughness_texture") == tex and is_equal_approx(float(by_name.get("roughness")), 1.0) and int(by_name.get("roughness_texture_channel")) == 0, "roughness: texture assigned, multiplier reset to 1, RED channel read")
	by_name.clear()
	for change in GDDrawMaterialChannels.property_changes_for_new_texture("ao", tex):
		by_name[change["property"]] = change["value"]
	check(by_name.get("ao_enabled") == true and by_name.has("ao_texture"), "ambient occlusion: switched on")
	by_name.clear()
	for change in GDDrawMaterialChannels.property_changes_for_new_texture("emission", tex):
		by_name[change["property"]] = change["value"]
	check(by_name.get("emission_enabled") == true and by_name.get("emission") == Color.WHITE and by_name.get("emission_operator") == BaseMaterial3D.EMISSION_OP_MULTIPLY, "emission: switched on, colour white AND the Multiply operator (with the default Add operator a white colour lights everything white)")
	check(GDDrawMaterialChannels.property_changes_for_new_texture("albedo", tex).size() == 1, "albedo: only the texture (existing behaviour unchanged)")
	# applying them must reproduce the original look: fill 0.4 x multiplier 1.0
	for change in GDDrawMaterialChannels.property_changes_for_new_texture("roughness", tex):
		fresh.set(change["property"], change["value"])
	check(fresh.roughness_texture == tex and is_equal_approx(fresh.roughness, 1.0), "applied to a StandardMaterial3D")

	print("== Brush colour")
	check(GDDrawMaterialChannels.constrain_color(Color(1, 0, 0), "albedo") == Color(1, 0, 0), "colour channels keep the picked colour")
	var gray := GDDrawMaterialChannels.constrain_color(Color(1, 0, 0), "roughness")
	check(is_equal_approx(gray.r, gray.g) and is_equal_approx(gray.g, gray.b) and gray.a == 1.0 and gray.r > 0.1 and gray.r < 0.4, "a picked red becomes a dark gray for scalar channels (%s)" % str(gray))
	check(GDDrawMaterialChannels.constrain_color(Color(0.6, 0.6, 0.6, 0.3), "metallic").is_equal_approx(Color(0.6, 0.6, 0.6, 1.0)), "gray stays the same value, alpha forced opaque")
