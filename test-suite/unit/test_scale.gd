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


func ms(start: int) -> float:
	return float(Time.get_ticks_usec() - start) / 1000.0


func run() -> void:
	var target := GDDrawPaintTarget.new()

	print("== Big layers are resampled natively")
	var gradient := Image.create_empty(1024, 1024, false, Image.FORMAT_RGBA8)
	for y in range(0, 1024, 4):
		for x in range(0, 1024, 4):
			gradient.fill_rect(Rect2i(x, y, 4, 4), Color(float(x) / 1024.0, float(y) / 1024.0, 0.25, 1.0))
	var small: Image = target._resample_layer_image(gradient, Vector2i(256, 256), 1)
	check(small.get_size() == Vector2i(256, 256) and small.get_format() == Image.FORMAT_RGBA8, "a 1024 image scales to 256x256 RGBA8")
	var probe := small.get_pixel(100, 60)
	check(absf(probe.r - (400.0 + 1.5) / 1024.0) < 0.012 and absf(probe.g - (240.0 + 1.5) / 1024.0) < 0.012 and absf(probe.b - 0.25) < 0.01, "bilinear shrinking averages the pixels it covers %s" % str(probe))
	var nearest: Image = target._resample_layer_image(gradient, Vector2i(256, 256), 0)
	var picked := nearest.get_pixel(100, 60)
	check(absf(picked.r - 400.0 / 1024.0) < 0.005 + 4.0 / 1024.0 and absf(picked.g - 240.0 / 1024.0) < 0.005 + 4.0 / 1024.0, "nearest picks a pixel from the block %s" % str(picked))
	check(gradient.get_size() == Vector2i(1024, 1024) and gradient.get_pixel(0, 0).is_equal_approx(Color(0, 0, 0.25, 1.0)) or absf(gradient.get_pixel(0, 0).b - 0.25) < 0.01, "the source image is left alone")
	small.set_pixel(0, 0, Color(1, 1, 1, 1))
	var again: Image = target._resample_layer_image(gradient, Vector2i(256, 256), 1)
	check(again.get_pixel(0, 0).r < 0.1, "results do not share memory with the source or each other")
	var grown: Image = target._resample_layer_image(gradient.get_region(Rect2i(0, 0, 300, 300)), Vector2i(600, 600), 1)
	check(grown.get_size() == Vector2i(600, 600), "enlarging works too")

	print("== Transparency")
	var halves := Image.create_empty(1024, 1024, false, Image.FORMAT_RGBA8)
	halves.fill(Color(0, 0, 0, 0))
	halves.fill_rect(Rect2i(0, 0, 510, 1024), Color(1, 0, 0, 1))
	var edge: Image = target._resample_layer_image(halves, Vector2i(256, 256), 1)
	var solid := edge.get_pixel(10, 100)
	var boundary := edge.get_pixel(127, 100)
	var empty := edge.get_pixel(200, 100)
	check(solid.is_equal_approx(Color(1, 0, 0, 1)), "opaque pixels stay opaque red %s" % str(solid))
	check(absf(boundary.a - 0.5) < 0.05 and boundary.r > 0.97 and boundary.g < 0.03 and boundary.b < 0.03, "a half-covered pixel is half transparent red, not dark red %s" % str(boundary))
	check(empty.a == 0.0 and empty.r == 0.0 and empty.g == 0.0, "empty pixels stay empty %s" % str(empty))
	var edge_nearest: Image = target._resample_layer_image(halves, Vector2i(256, 256), 0)
	check(edge_nearest.get_pixel(10, 100).is_equal_approx(Color(1, 0, 0, 1)) and edge_nearest.get_pixel(200, 100).a == 0.0, "nearest keeps the layer content too")

	print("== Small layers keep the exact per-pixel path")
	var tiny := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	for y in range(4):
		for x in range(4):
			tiny.set_pixel(x, y, Color(float(x) / 3.0, float(y) / 3.0, 0.0, 1.0))
	var tiny_up: Image = target._resample_layer_image(tiny, Vector2i(8, 8), 0)
	check(tiny_up.get_size() == Vector2i(8, 8) and tiny_up.get_pixel(0, 0) == tiny.get_pixel(0, 0) and tiny_up.get_pixel(7, 7) == tiny.get_pixel(3, 3), "a 4x4 layer still goes through the loop")

	print("== Speed on a 4096x4096 layer")
	var big := Image.create_empty(4096, 4096, false, Image.FORMAT_RGBA8)
	big.fill(Color(0.3, 0.5, 0.7, 1))
	var t := Time.get_ticks_usec()
	var big_small: Image = target._resample_layer_image(big, Vector2i(1024, 1024), 1)
	var opaque_ms := ms(t)
	print("  opaque 4096 -> 1024 bilinear: %.0f ms" % opaque_ms)
	check(big_small.get_size() == Vector2i(1024, 1024) and absf(big_small.get_pixel(500, 500).g - 0.5) < 0.01 and opaque_ms < 3000.0, "an opaque 4096 image shrinks in %.0f ms" % opaque_ms)
	big.set_pixel(0, 0, Color(0, 0, 0, 0))
	t = Time.get_ticks_usec()
	var big_alpha: Image = target._resample_layer_image(big, Vector2i(1024, 1024), 1)
	var alpha_ms := ms(t)
	print("  4096 with transparency -> 1024 bilinear: %.0f ms" % alpha_ms)
	check(big_alpha.get_size() == Vector2i(1024, 1024) and absf(big_alpha.get_pixel(500, 500).g - 0.5) < 0.01 and alpha_ms < 20000.0, "with transparency it takes %.0f ms" % alpha_ms)
	t = Time.get_ticks_usec()
	target._resample_layer_image(big, Vector2i(1024, 1024), 0)
	print("  4096 -> 1024 nearest: %.0f ms" % ms(t))

	print("== scale_layers end to end")
	var session := GDDrawLayerSession.new()
	var group_id := session.add_object_group("Obj")
	var made = session.create_target(group_id, Vector2i(512, 512), null, "T", "albedo")
	check(made != null, "a 512 paint target exists")
	if made:
		var node = made.get_selected_layer()
		node.image.fill(Color(0.2, 0.4, 0.6, 1))
		check(made.scale_layers(Vector2i(128, 128), 1) and made.size == Vector2i(128, 128), "scale_layers changes the target size")
		var layer = made.get_selected_layer()
		check(layer.image.get_size() == Vector2i(128, 128) and layer.image.get_pixel(60, 60).is_equal_approx(Color(0.2, 0.4, 0.6, 1)), "the layer image follows, colours intact")
		check(layer.eraser_source.get_size() == Vector2i(128, 128), "and its eraser source")
