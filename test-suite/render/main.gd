extends Node3D

const Channels := preload("res://gddraw_material_channels.gd")
const Baker := preload("res://gddraw_shader_baker.gd")

var frames := 0
var cases: Array = []
var index := 0
var phase := 0
var mesh_instance: MeshInstance3D
var baseline: Color
var baseline_off: Color
var failures := 0
var bake_started := false


func _ready() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 0, 2.5)
	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-30, 30, 0)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.2, 0.3)
	add_child(env)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = SphereMesh.new()
	add_child(mesh_instance)
	var checker := _checker(64)
	# each case: label, channel, a function preparing the ORIGINAL material
	cases = [
		["emission OFF -> new emission texture", "emission", func(m): m.albedo_texture = checker],
		["emission ON red, no texture -> new emission texture", "emission", func(m): m.albedo_texture = checker; m.emission_enabled = true; m.emission = Color(0.9, 0, 0)],
		["emission ON red (MULTIPLY op), no texture -> new texture", "emission", func(m): m.albedo_texture = checker; m.emission_enabled = true; m.emission = Color(0.9, 0.3, 0); m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY],
		["roughness 0.4 -> new roughness texture", "roughness", func(m): m.albedo_texture = checker; m.roughness = 0.4],
		["metallic 0.7 -> new metallic texture", "metallic", func(m): m.albedo_texture = checker; m.metallic = 0.7],
		["ao off -> new ao texture", "ao", func(m): m.albedo_texture = checker],
		["height off -> new height texture", "height", func(m): m.albedo_texture = checker],
		["normal off -> new flat normal texture", "normal", func(m): m.albedo_texture = checker],
	]


func _tex_from(image: Image) -> ImageTexture:
	return ImageTexture.create_from_image(image)


func _checker(size: int) -> ImageTexture:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			image.set_pixel(x, y, Color(1, 0.3, 0.1) if ((x / 8) + (y / 8)) % 2 == 0 else Color(0.1, 0.4, 1))
	return ImageTexture.create_from_image(image)


func _pixels() -> Array:
	var image := get_viewport().get_texture().get_image()
	var w := image.get_width()
	return [image.get_pixel(w / 2, w / 2), image.get_pixel(int(w * 0.42), int(w * 0.62))]


func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.03 and absf(a.g - b.g) < 0.03 and absf(a.b - b.b) < 0.03


func _process(_delta: float) -> void:
	frames += 1
	if index >= cases.size():
		if not bake_started:
			bake_started = true
			_run_bake_tests()
		return
	if frames % 4 == 1:
		var original := StandardMaterial3D.new()
		original.albedo_color = Color(0.8, 0.8, 0.8)
		(cases[index][2] as Callable).call(original)
		if phase == 0:
			mesh_instance.material_override = original
		else:
			# what GDDraw does: bake the material's current value into a new texture and assign it
			var converted := original.duplicate(true) as StandardMaterial3D
			var channel: String = cases[index][1]
			var image: Image = Channels.make_initial_image(original, channel, Vector2i(64, 64))
			var texture := _tex_from(image)
			for change in Channels.property_changes_for_new_texture(channel, texture):
				converted.set(str(change["property"]), change["value"])
			mesh_instance.material_override = converted
	if frames % 4 == 3:
		var pix := _pixels()
		if phase == 0:
			baseline = pix[0]
			baseline_off = pix[1]
			phase = 1
		else:
			var ok := _close(baseline, pix[0]) and _close(baseline_off, pix[1])
			if not ok:
				failures += 1
			print("RENDER  %s  %-58s before=(%.2f,%.2f,%.2f) after=(%.2f,%.2f,%.2f)" % ["OK  " if ok else "FAIL", cases[index][0], baseline.r, baseline.g, baseline.b, pix[0].r, pix[0].g, pix[0].b])
			phase = 0
			index += 1

func _srgb_to_linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


func _linear_to_srgb(v: float) -> float:
	return v * 12.92 if v <= 0.0031308 else 1.055 * pow(v, 1.0 / 2.4) - 0.055


func _bake_check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("RENDER  %s  bake: %-56s %s" % ["OK  " if ok else "FAIL", label, detail])


func _near(a: float, b: float, tolerance := 0.03) -> bool:
	return absf(a - b) <= tolerance


func _bake_shader(code: String, size := 64, parameters := {}) -> Dictionary:
	var shader := Shader.new()
	shader.code = code
	var material := ShaderMaterial.new()
	material.shader = shader
	for parameter_name in parameters:
		material.set_shader_parameter(parameter_name, parameters[parameter_name])
	return await Baker.bake(self, material, size)


# Shader materials baked into images: the values that come out must be the values the shader wrote.
func _run_bake_tests() -> void:
	var spatial_code := """shader_type spatial;
uniform vec3 tint : source_color = vec3(1.0, 0.2, 0.1);
void fragment() {
	ALBEDO = tint * UV.x;
	ROUGHNESS = 0.3;
	METALLIC = UV.y;
	EMISSION = vec3(0.0, 0.5, 0.0) * step(0.5, UV.x);
	AO = 0.8;
}
"""
	var images: Dictionary = await _bake_shader(spatial_code)
	_bake_check("all five channels are drawn", images.keys().size() == 5, str(images.keys()))
	if images.size() == 5:
		var left_x := 16
		var right_x := 48
		var u_right := (right_x + 0.5) / 64.0
		var rough: Color = (images["roughness"] as Image).get_pixel(right_x, 20)
		_bake_check("roughness 0.3 comes out as 0.3", _near(rough.r, 0.3, 0.02) and _near(rough.g, 0.3, 0.02), "got %.3f" % rough.r)
		var metal_row := 24
		var metal: Color = (images["metallic"] as Image).get_pixel(left_x, metal_row)
		_bake_check("metallic = UV.y (a vertical ramp)", _near(metal.r, (metal_row + 0.5) / 64.0, 0.02), "row %d got %.3f, expected %.3f" % [metal_row, metal.r, (metal_row + 0.5) / 64.0])
		var occlusion: Color = (images["ao"] as Image).get_pixel(left_x, 40)
		_bake_check("ao 0.8 comes out as 0.8", _near(occlusion.r, 0.8, 0.02), "got %.3f" % occlusion.r)
		var glow_left: Color = (images["emission"] as Image).get_pixel(left_x, 20)
		var glow_right: Color = (images["emission"] as Image).get_pixel(right_x, 20)
		_bake_check("emission is black on the left and green on the right", glow_left.g < 0.03 and _near(glow_right.g, _linear_to_srgb(0.5), 0.03) and glow_right.r < 0.03, "left %.3f right %.3f (sRGB of 0.5 = %.3f)" % [glow_left.g, glow_right.g, _linear_to_srgb(0.5)])
		var albedo_pixel: Color = (images["albedo"] as Image).get_pixel(right_x, 20)
		var expected_red := _linear_to_srgb(_srgb_to_linear(1.0) * u_right)
		var expected_green := _linear_to_srgb(_srgb_to_linear(0.2) * u_right)
		_bake_check("albedo is the shader's colour (sRGB encoded)", _near(albedo_pixel.r, expected_red, 0.03) and _near(albedo_pixel.g, expected_green, 0.03), "got (%.3f, %.3f), expected (%.3f, %.3f)" % [albedo_pixel.r, albedo_pixel.g, expected_red, expected_green])
		_bake_check("the bake is opaque", albedo_pixel.a > 0.99, "alpha %.2f" % albedo_pixel.a)

	var nested_code := """shader_type spatial;
render_mode blend_mix, cull_back;
uniform float level = 0.6;
// ROUGHNESS = 0.0; a comment must be ignored
void fragment() {
	if (UV.x > 0.5) { ROUGHNESS = level; } else { ROUGHNESS = 0.1; }
	/* } */
}
"""
	var nested: Dictionary = await _bake_shader(nested_code)
	if nested.has("roughness"):
		var image: Image = nested["roughness"]
		_bake_check("existing render modes and nested blocks survive", _near(image.get_pixel(16, 20).r, 0.1, 0.02) and _near(image.get_pixel(48, 20).r, 0.6, 0.02), "left %.3f right %.3f" % [image.get_pixel(16, 20).r, image.get_pixel(48, 20).r])
	else:
		_bake_check("existing render modes and nested blocks survive", false, "no roughness image")
	var changed: Dictionary = await _bake_shader(nested_code, 64, {"level": 0.9})
	if changed.has("roughness"):
		_bake_check("shader parameters set on the material are used", _near((changed["roughness"] as Image).get_pixel(48, 20).r, 0.9, 0.02), "got %.3f" % (changed["roughness"] as Image).get_pixel(48, 20).r)
	else:
		_bake_check("shader parameters set on the material are used", false, "no roughness image")

	var canvas_code := "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(UV.x, 0.5, 0.0, 1.0); }\n"
	var canvas: Dictionary = await _bake_shader(canvas_code)
	if canvas.has("albedo"):
		var pixel: Color = (canvas["albedo"] as Image).get_pixel(48, 20)
		_bake_check("a canvas_item shader gives the albedo as drawn", _near(pixel.r, (48 + 0.5) / 64.0, 0.03) and _near(pixel.g, 0.5, 0.03), "got (%.3f, %.3f)" % [pixel.r, pixel.g])
	else:
		_bake_check("a canvas_item shader gives the albedo as drawn", false, "no albedo image")

	var big: Dictionary = await _bake_shader(Baker.TEMPLATE_CODE, 256)
	_bake_check("the template shader bakes at 256 px", big.has("albedo") and (big["albedo"] as Image).get_width() == 256 and big.has("roughness"), str(big.keys()))
	if big.has("albedo") and big.has("roughness"):
		# The template has to be obvious when painted: strong colour contrast, bands a brush can cross.
		var albedo_image: Image = big["albedo"]
		var rough_image: Image = big["roughness"]
		var low := 1.0
		var high := 0.0
		var rough_low := 1.0
		var rough_high := 0.0
		var crossings := 0
		var last_dark := true
		for x in range(256):
			var pixel := albedo_image.get_pixel(x, 128)
			low = minf(low, pixel.r)
			high = maxf(high, pixel.r)
			var dark := pixel.r < 0.5
			if x > 0 and dark != last_dark:
				crossings += 1
			last_dark = dark
			var rough := rough_image.get_pixel(x, 128).r
			rough_low = minf(rough_low, rough)
			rough_high = maxf(rough_high, rough)
		_bake_check("the template has strong colour contrast", high - low > 0.6, "red spans %.2f to %.2f" % [low, high])
		_bake_check("and roughness varies between shiny and matte", rough_high - rough_low > 0.5, "roughness spans %.2f to %.2f" % [rough_low, rough_high])
		_bake_check("with bands narrow enough to see in a stroke", crossings >= 12, "%d colour changes along one row of 256 px" % crossings)

	# normal maps, vertex functions and height maps
	var normal_bake: Dictionary = await _bake_shader("shader_type spatial;\nvoid fragment() {\n\tNORMAL_MAP = vec3(0.5 + 0.3 * UV.x, 0.5 - 0.2 * UV.y, 1.0);\n}\n")
	if normal_bake.has("normal"):
		var n_pixel: Color = (normal_bake["normal"] as Image).get_pixel(48, 16)
		_bake_check("a NORMAL_MAP comes out as written", _near(n_pixel.r, 0.5 + 0.3 * (48.5 / 64.0), 0.02) and _near(n_pixel.g, 0.5 - 0.2 * (16.5 / 64.0), 0.02) and n_pixel.b > 0.97, "got (%.3f, %.3f, %.3f)" % [n_pixel.r, n_pixel.g, n_pixel.b])
	else:
		_bake_check("a NORMAL_MAP comes out as written", false, "no normal image")
	var moved: Dictionary = await _bake_shader("shader_type spatial;\nvoid vertex() {\n\tVERTEX.x += 0.5;\n\tVERTEX.y += 0.3;\n}\nvoid fragment() {\n\tALBEDO = vec3(UV.x);\n}\n")
	if moved.has("albedo"):
		var m_pixel: Color = (moved["albedo"] as Image).get_pixel(48, 20)
		_bake_check("a vertex function that shifts the geometry does not warp the colour bake", _near(m_pixel.r, _linear_to_srgb((48 + 0.5) / 64.0), 0.03), "got %.3f, expected %.3f" % [m_pixel.r, _linear_to_srgb((48 + 0.5) / 64.0)])
	else:
		_bake_check("a vertex function that shifts the geometry does not warp the colour bake", false, "no albedo image")
	var height_bake: Dictionary = await _bake_shader("shader_type spatial;\nvoid vertex() {\n\tVERTEX += NORMAL * UV.x * 0.4;\n}\nvoid fragment() {\n\tALBEDO = vec3(0.5);\n}\n")
	if height_bake.has("height"):
		var h_image: Image = height_bake["height"]
		_bake_check("vertex displacement along the normal becomes a 0..1 height map", _near(h_image.get_pixel(16, 30).r, 0.26, 0.05) and _near(h_image.get_pixel(48, 30).r, 0.76, 0.05) and _near(h_image.get_pixel(48, 5).r, h_image.get_pixel(48, 58).r, 0.03), "x=.26 -> %.3f, x=.76 -> %.3f" % [h_image.get_pixel(16, 30).r, h_image.get_pixel(48, 30).r])
	else:
		_bake_check("vertex displacement along the normal becomes a 0..1 height map", false, "no height image")
	var height_y: Dictionary = await _bake_shader("shader_type spatial;\nvoid vertex() {\n\tVERTEX.y += (1.0 - UV.y) * 3.0;\n}\nvoid fragment() {\n\tALBEDO = vec3(0.5);\n}\n")
	if height_y.has("height"):
		var hy_image: Image = height_y["height"]
		_bake_check("VERTEX.y += works as a height too (higher at the top)", hy_image.get_pixel(30, 2).r > 0.9 and hy_image.get_pixel(30, 61).r < 0.1 and _near(hy_image.get_pixel(30, 32).r, 0.5, 0.06), "top %.3f middle %.3f bottom %.3f" % [hy_image.get_pixel(30, 2).r, hy_image.get_pixel(30, 32).r, hy_image.get_pixel(30, 61).r])
	else:
		_bake_check("VERTEX.y += works as a height too (higher at the top)", false, "no height image")
	var flat_bake: Dictionary = await _bake_shader("shader_type spatial;\nvoid vertex() {\n\tVERTEX += NORMAL * 0.0;\n}\nvoid fragment() {\n\tALBEDO = vec3(0.5);\n}\n")
	_bake_check("a vertex function that does not actually move anything gives no height", not flat_bake.has("height"), str(flat_bake.keys()))
	var template_bake: Dictionary = await _bake_shader(Baker.TEMPLATE_CODE, 256)
	_bake_check("the template bakes all five of its channels", template_bake.size() == 5 and template_bake.has("normal") and template_bake.has("height"), str(template_bake.keys()))
	if template_bake.has("height") and template_bake.has("normal"):
		var height_span: Vector2 = Baker._value_span(template_bake["height"])
		var normal_span: Vector2 = Baker._value_span(template_bake["normal"])
		_bake_check("with a height that fills 0..1 and normals that lean both ways", height_span.y - height_span.x > 0.85 and normal_span.x < 0.35 and normal_span.y > 0.65, "height %.2f..%.2f, normal red %.2f..%.2f" % [height_span.x, height_span.y, normal_span.x, normal_span.y])
	print("RENDER  RESULT: ", "ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit()