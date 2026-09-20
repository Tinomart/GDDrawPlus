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


func braces_balanced(code: String) -> bool:
	var depth := 0
	for character in code:
		if character == "{":
			depth += 1
		elif character == "}":
			depth -= 1
		if depth < 0:
			return false
	return depth == 0


func run() -> void:
	print("== Which channels a shader writes")
	var full := "shader_type spatial;\nvoid fragment() {\n\tALBEDO = vec3(1.0);\n\tROUGHNESS = 0.3;\n\tMETALLIC = 0.0;\n\tEMISSION = vec3(0.0);\n\tAO = 0.8;\n}\n"
	check(GDDrawShaderBaker.detect_channels(full) == PackedStringArray(["albedo", "emission", "roughness", "metallic", "ao"]), "all five outputs are found: " + str(GDDrawShaderBaker.detect_channels(full)))
	var partial := "shader_type spatial;\nvoid fragment() {\n\tALBEDO = vec3(1.0);\n\tROUGHNESS += 0.1;\n}\n"
	check(GDDrawShaderBaker.detect_channels(partial) == PackedStringArray(["albedo", "roughness"]), "only what is written counts, compound assignments included")
	var tricky := "shader_type spatial;\n// METALLIC = 1.0;\n/* EMISSION = vec3(1.0); */\nvoid fragment() {\n\tALBEDO = vec3(1.0);\n\tif (ROUGHNESS == 0.5) { ALBEDO = vec3(0.0); }\n}\n"
	check(GDDrawShaderBaker.detect_channels(tricky) == PackedStringArray(["albedo"]), "comments and comparisons (==) are not assignments")
	check(GDDrawShaderBaker.detect_channels("shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0); }\n") == PackedStringArray(["albedo"]), "a canvas_item shader gives the albedo channel")
	check(GDDrawShaderBaker.detect_channels("shader_type sky;\nvoid sky() { COLOR = vec3(1.0); }\n").is_empty(), "other shader types cannot be baked")
	check(GDDrawShaderBaker.detect_channels("shader_type spatial;\nvoid vertex() { VERTEX.y += 1.0; }\n").is_empty(), "a spatial shader without fragment() cannot be baked")
	check(GDDrawShaderBaker.detect_channels(GDDrawShaderBaker.TEMPLATE_CODE) == PackedStringArray(["albedo", "roughness", "metallic", "normal", "height"]), "the template shader bakes albedo, roughness, metallic, normal and height: " + str(GDDrawShaderBaker.detect_channels(GDDrawShaderBaker.TEMPLATE_CODE)))

	print("== Rewriting for one channel")
	var roughness_code := GDDrawShaderBaker.make_channel_shader_code(full, "roughness")
	check("render_mode unshaded, cull_disabled;" in roughness_code, "an unshaded render_mode is added when there is none")
	check(roughness_code.find("ALBEDO = mix(pow(") > roughness_code.find("AO = 0.8;"), "the output stage runs after the shader's own code")
	check("vec3(ROUGHNESS)" in roughness_code and braces_balanced(roughness_code), "roughness is the value written out, braces stay balanced")
	check(roughness_code.ends_with("}\n"), "the shader still ends with its closing brace")
	var emission_code := GDDrawShaderBaker.make_channel_shader_code(full, "emission")
	check("ALBEDO = EMISSION;" in emission_code, "the emission pass copies EMISSION to the colour")
	var albedo_code := GDDrawShaderBaker.make_channel_shader_code(full, "albedo")
	check("EMISSION = vec3(0.0);" in albedo_code and "ALBEDO = mix" not in albedo_code, "the albedo pass keeps ALBEDO and silences emission")
	var with_modes := "shader_type spatial;\nrender_mode blend_mix, cull_back;\nvoid fragment() { ALBEDO = vec3(0.5); }\n"
	var merged := GDDrawShaderBaker.make_channel_shader_code(with_modes, "albedo")
	check("render_mode blend_mix, unshaded, cull_disabled;" in merged, "existing render modes are kept and the cull mode replaced: " + merged.split("\n")[1])
	var already := "shader_type spatial;\nrender_mode unshaded;\nvoid fragment() { ALBEDO = vec3(0.5); }\n"
	var already_code := GDDrawShaderBaker.make_channel_shader_code(already, "albedo")
	check(already_code.count("unshaded") == 1 and "cull_disabled" in already_code, "unshaded is not added twice")
	var nested := "shader_type spatial;\nuniform float k = 0.5;\nvoid fragment() {\n\t// } a comment brace\n\tif (UV.x > k) { ROUGHNESS = 0.2; } else { ROUGHNESS = 0.9; }\n\t/* } */\n}\nfloat helper() { return 1.0; }\n"
	var nested_code := GDDrawShaderBaker.make_channel_shader_code(nested, "roughness")
	var body_end := nested_code.find("vec3 _gddraw_v")
	check(body_end > nested_code.find("ROUGHNESS = 0.9;") and body_end < nested_code.find("float helper()"), "the output stage lands at the end of fragment(), not inside a nested block or comment")
	check(GDDrawShaderBaker.make_channel_shader_code(full, "height") == "" and GDDrawShaderBaker.make_channel_shader_code(full, "nonsense") == "", "channels a shader cannot write are refused")
	var canvas := "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(0.2, 0.4, 0.6, 1.0); }\n"
	check(GDDrawShaderBaker.make_channel_shader_code(canvas, "albedo") == canvas and GDDrawShaderBaker.make_channel_shader_code(canvas, "roughness") == "", "a canvas_item shader is used as it is for albedo only")
	check(GDDrawShaderBaker.make_channel_shader_code("shader_type spatial;\nvoid vertex() {}\n", "albedo") == "", "no fragment() -> nothing to rewrite")

	print("== Change detection")
	var shader := Shader.new()
	shader.code = GDDrawShaderBaker.TEMPLATE_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	var first := GDDrawShaderBaker.material_signature(material)
	check(first != "" and first == GDDrawShaderBaker.material_signature(material), "the signature is stable while nothing changes")
	material.set_shader_parameter("stripes", 25.0)
	var second := GDDrawShaderBaker.material_signature(material)
	check(second != first, "changing a shader parameter changes the signature")
	shader.code = GDDrawShaderBaker.TEMPLATE_CODE.replace("0.05, 0.55, 0.60", "0.10, 0.55, 0.22")
	check(GDDrawShaderBaker.material_signature(material) != second, "editing the shader code changes it too")
	check(GDDrawShaderBaker.material_signature(null) == "" and GDDrawShaderBaker.material_signature(ShaderMaterial.new()) == "", "no material or no shader gives an empty signature")

	print("== A set from baked images")
	var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.4, 0.4, 0.4, 1.0))
	var baked := GDDrawMaterialSet.load_from_baked({"albedo": image, "roughness": image, "normal": image, "sheen": image}, "demo", material, "res://x/demo.tres")
	check(baked != null and baked.channels() == PackedStringArray(["albedo", "roughness", "normal"]) and baked.shader_material == material, "channels the brush does not know are dropped: " + str(baked.channels() if baked else []))
	check(baked != null and absf(baked.sample("roughness", Vector2(0.5, 0.5)).r - 0.4) < 0.01 and baked.display_name == "demo", "the baked image is sampled like any other map")
	check(GDDrawMaterialSet.load_from_baked({}, "empty", material) == null, "an empty bake gives no set")

	print("== Normals, height and the vertex function")
	var with_normal := "shader_type spatial;\nvoid fragment() {\n\tNORMAL_MAP = vec3(0.5, 0.5, 1.0);\n\tNORMAL_MAP_DEPTH = 2.0;\n}\n"
	check(GDDrawShaderBaker.detect_channels(with_normal) == PackedStringArray(["normal"]), "NORMAL_MAP is a channel, NORMAL_MAP_DEPTH is not: " + str(GDDrawShaderBaker.detect_channels(with_normal)))
	var normal_code := GDDrawShaderBaker.make_channel_shader_code(with_normal, "normal")
	check("clamp(NORMAL_MAP" in normal_code and "ALBEDO = mix(pow(" in normal_code and braces_balanced(normal_code), "the normal pass writes NORMAL_MAP out unchanged (converted for the sRGB output)")
	var vertex_only := "shader_type spatial;\nvoid vertex() {\n\tVERTEX.y += 0.2;\n}\nvoid fragment() {\n\tALBEDO = vec3(1.0);\n}\n"
	check(GDDrawShaderBaker.detect_channels(vertex_only) == PackedStringArray(["albedo", "height"]), "a vertex function that moves vertices gives a height channel")
	var vertex_reads := "shader_type spatial;\nvarying float shade;\nvoid vertex() {\n\tshade = VERTEX.y;\n\tif (VERTEX.y == 0.0) { shade = 1.0; }\n}\nvoid fragment() {\n\tALBEDO = vec3(shade);\n}\n"
	check(GDDrawShaderBaker.detect_channels(vertex_reads) == PackedStringArray(["albedo"]), "reading VERTEX (or comparing it) is not moving it")
	var albedo_wrapped := GDDrawShaderBaker.make_channel_shader_code(vertex_only, "albedo")
	check("vec3 _gddraw_rest = VERTEX;" in albedo_wrapped and albedo_wrapped.find("VERTEX = _gddraw_rest;") > albedo_wrapped.find("VERTEX.y += 0.2;") and braces_balanced(albedo_wrapped), "colour passes put the vertices back after vertex() ran")
	check("_gddraw_height" not in albedo_wrapped, "and do not measure the height")
	var height_probe := GDDrawShaderBaker.make_channel_shader_code(vertex_only, "height", 0.0, 1.0, 2.5)
	check("varying float _gddraw_height;" in height_probe and "dot(VERTEX - _gddraw_rest, _gddraw_normal)" in height_probe and "0.5 + _gddraw_height * 2.5" in height_probe and braces_balanced(height_probe), "the height probe pass measures the displacement along the normal")
	var height_final := GDDrawShaderBaker.make_channel_shader_code(vertex_only, "height", -0.25, 2.0)
	check("(_gddraw_height - (-0.25)) * 0.5" in height_final, "the final height pass maps its range onto 0..1: " + str(height_final.find("_gddraw_height - (")))
	check(GDDrawShaderBaker.make_channel_shader_code(with_normal, "height") == "", "no vertex function -> no height")
	var no_vertex_wrap := GDDrawShaderBaker.make_channel_shader_code(with_normal, "albedo")
	check("_gddraw_rest" not in no_vertex_wrap, "a shader without vertex() is left alone")
	var commented_vertex := "shader_type spatial;\n// void vertex() { VERTEX.y += 1.0; }\nvoid fragment() {\n\tALBEDO = vec3(1.0);\n}\n"
	check(GDDrawShaderBaker.detect_channels(commented_vertex) == PackedStringArray(["albedo"]), "a commented-out vertex function does not count")