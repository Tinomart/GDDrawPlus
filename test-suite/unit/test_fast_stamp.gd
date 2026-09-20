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


func make_base(kind: String, size: int) -> Image:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	if kind == "opaque":
		for y in range(size):
			for x in range(size):
				image.set_pixel(x, y, Color(float(x) / size, float(y) / size, 0.5, 1.0))
	elif kind == "half":
		for y in range(size):
			for x in range(size):
				image.set_pixel(x, y, Color(0.2, 0.8, float(x) / size, 0.5))
	return image


## Paints one stroke (press, two drags, release) and returns the resulting image.
func paint(fast: bool, base: Image, settings: Dictionary) -> Image:
	var canvas := GDDrawCanvasControl.new()
	canvas.set_image(base.duplicate())
	canvas.fast_stamp_enabled = fast
	canvas.active_tool = GDDrawCanvasControl.ToolMode.BRUSH
	canvas.brush_size = int(settings["size"])
	canvas.brush_hardness = float(settings["hardness"])
	canvas.brush_head = int(settings["head"])
	canvas.pixel_perfect = bool(settings["perfect"])
	canvas.brush_touch_pixels = bool(settings["touch"])
	canvas.brush_color = settings["color"]
	var triangle := PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0)])
	var start: Vector2 = settings["start"]
	canvas.begin_uv_triangle_stroke(start, triangle)
	canvas.continue_uv_triangle_stroke(start + Vector2(0.21, 0.07), triangle, true)
	canvas.continue_uv_triangle_stroke(start + Vector2(0.33, 0.30), triangle, true)
	canvas.end_uv_triangle_stroke()
	var result: Image = canvas.get_image_copy()
	canvas.free()
	return result


func difference(a: Image, b: Image) -> Vector2:
	# returns (largest channel difference in 8-bit steps, number of pixels differing by more than 6 steps)
	var largest := 0
	var over := 0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := maxi(maxi(absi(roundi(ca.r * 255.0) - roundi(cb.r * 255.0)), absi(roundi(ca.g * 255.0) - roundi(cb.g * 255.0))), maxi(absi(roundi(ca.b * 255.0) - roundi(cb.b * 255.0)), absi(roundi(ca.a * 255.0) - roundi(cb.a * 255.0))))
			# fully transparent pixels have no colour
			if ca.a == 0.0 and cb.a == 0.0:
				d = 0
			largest = maxi(largest, d)
			if d > 6:
				over += 1
	return Vector2(largest, over)


func run() -> void:
	print("== The native stamp gives the same picture as the per-pixel one")
	var size := 160
	var cases := [
		{"label": "round soft, size 40, on transparent", "size": 40, "hardness": 0.5, "head": GDDrawCanvasControl.BrushHead.CIRCLE, "perfect": false, "touch": false, "color": Color(1, 0.2, 0.1, 1), "base": "clear", "start": Vector2(0.3, 0.3)},
		{"label": "round soft, size 33 (odd), on opaque", "size": 33, "hardness": 0.75, "head": GDDrawCanvasControl.BrushHead.CIRCLE, "perfect": false, "touch": true, "color": Color(0.1, 0.3, 1, 1), "base": "opaque", "start": Vector2(0.2, 0.25)},
		{"label": "round hard, size 64, half-transparent base", "size": 64, "hardness": 1.0, "head": GDDrawCanvasControl.BrushHead.CIRCLE, "perfect": false, "touch": true, "color": Color(0, 0.7, 0.2, 1), "base": "half", "start": Vector2(0.25, 0.3)},
		{"label": "square soft, size 24", "size": 24, "hardness": 0.3, "head": GDDrawCanvasControl.BrushHead.SQUARE, "perfect": false, "touch": true, "color": Color(1, 1, 0, 1), "base": "opaque", "start": Vector2(0.3, 0.2)},
		{"label": "pixel-perfect square, size 20", "size": 20, "hardness": 0.75, "head": GDDrawCanvasControl.BrushHead.SQUARE, "perfect": true, "touch": true, "color": Color(0.9, 0.9, 0.9, 1), "base": "clear", "start": Vector2(0.3, 0.3)},
		{"label": "pixel-perfect round, size 30", "size": 30, "hardness": 0.75, "head": GDDrawCanvasControl.BrushHead.CIRCLE, "perfect": true, "touch": true, "color": Color(0.3, 0.6, 0.9, 1), "base": "opaque", "start": Vector2(0.3, 0.3)},
		{"label": "half-opacity brush, size 50, on opaque", "size": 50, "hardness": 0.6, "head": GDDrawCanvasControl.BrushHead.CIRCLE, "perfect": false, "touch": false, "color": Color(1, 0, 0.5, 0.5), "base": "opaque", "start": Vector2(0.25, 0.25)},
		{"label": "low-opacity brush, size 50, on transparent", "size": 50, "hardness": 0.6, "head": GDDrawCanvasControl.BrushHead.CIRCLE, "perfect": false, "touch": true, "color": Color(0.2, 0.9, 0.5, 0.25), "base": "clear", "start": Vector2(0.25, 0.25)},
		{"label": "runs off the image edge", "size": 60, "hardness": 0.75, "head": GDDrawCanvasControl.BrushHead.CIRCLE, "perfect": false, "touch": true, "color": Color(1, 0.5, 0, 1), "base": "opaque", "start": Vector2(0.02, 0.5)},
		{"label": "runs off the far edge", "size": 60, "hardness": 0.75, "head": GDDrawCanvasControl.BrushHead.SQUARE, "perfect": true, "touch": true, "color": Color(0, 0.5, 1, 1), "base": "clear", "start": Vector2(0.75, 0.8)},
		{"label": "small pixel-perfect square, size 9", "size": 9, "hardness": 0.75, "head": GDDrawCanvasControl.BrushHead.SQUARE, "perfect": true, "touch": true, "color": Color(0.9, 0.2, 0.9, 1), "base": "opaque", "start": Vector2(0.3, 0.3)},
		{"label": "small pixel-perfect round, size 8", "size": 8, "hardness": 0.75, "head": GDDrawCanvasControl.BrushHead.CIRCLE, "perfect": true, "touch": true, "color": Color(0.2, 0.9, 0.9, 1), "base": "clear", "start": Vector2(0.3, 0.3)},
		{"label": "small soft round, size 8", "size": 8, "hardness": 0.75, "head": GDDrawCanvasControl.BrushHead.CIRCLE, "perfect": false, "touch": true, "color": Color(0.9, 0.9, 0.2, 1), "base": "opaque", "start": Vector2(0.3, 0.3)},
		{"label": "large, size 200 (bigger than the image half)", "size": 200, "hardness": 0.5, "head": GDDrawCanvasControl.BrushHead.CIRCLE, "perfect": false, "touch": true, "color": Color(0.5, 0.2, 0.8, 0.8), "base": "opaque", "start": Vector2(0.4, 0.4)},
	]
	for settings: Dictionary in cases:
		var base := make_base(str(settings["base"]), size)
		var fast := paint(true, base, settings)
		var slow := paint(false, base, settings)
		var slow_changed := not (slow.get_data() == base.get_data())
		var d := difference(fast, slow)
		check(slow_changed and d.x <= 6.0 and d.y == 0.0, "%s: largest difference %d step(s) of 255, %d pixels differ by more than six" % [settings["label"], int(d.x), int(d.y)])

	print("== It is only used when the result is the same")
	var probe := GDDrawCanvasControl.new()
	probe.set_image(make_base("clear", 64))
	probe.active_tool = GDDrawCanvasControl.ToolMode.BRUSH
	probe.brush_size = 40
	probe.brush_color = Color.RED
	var tri := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)])
	# no stroke in progress: the fast path must refuse
	check(not probe.call("_try_fast_stamp", Vector2i(32, 32)), "outside a stroke it is not used")
	probe.begin_uv_triangle_stroke(Vector2(0.5, 0.5), tri)
	check(probe.call("_try_fast_stamp", Vector2i(32, 32)), "during a plain brush stroke it is used")
	probe.alpha_lock = true
	check(not probe.call("_try_fast_stamp", Vector2i(32, 32)), "not with alpha lock")
	probe.alpha_lock = false
	probe.stroke_overlap_enabled = false
	check(not probe.call("_try_fast_stamp", Vector2i(32, 32)), "not when strokes may not overlap themselves")
	probe.stroke_overlap_enabled = true
	probe.mirror_mode = GDDrawCanvasControl.MirrorMode.HORIZONTAL
	check(not probe.call("_try_fast_stamp", Vector2i(32, 32)), "not with mirroring")
	probe.mirror_mode = GDDrawCanvasControl.MirrorMode.OFF
	probe.material_pixel_source = func(_x, _y, color, _coverage): return color
	check(not probe.call("_try_fast_stamp", Vector2i(32, 32)), "not with the Material Brush")
	probe.material_pixel_source = Callable()
	probe.brush_size = 4
	check(not probe.call("_try_fast_stamp", Vector2i(32, 32)), "not for tiny brushes (pixel art stays exactly as before)")
	probe.brush_size = 40
	probe.active_tool = GDDrawCanvasControl.ToolMode.ERASER
	check(not probe.call("_try_fast_stamp", Vector2i(32, 32)), "not for the eraser")
	probe.end_uv_triangle_stroke()
	probe.free()

	print("== Speed")
	var big := make_base("clear", 2048)
	var timing := GDDrawCanvasControl.new()
	timing.set_image(big)
	timing.active_tool = GDDrawCanvasControl.ToolMode.BRUSH
	timing.brush_size = 96
	timing.pixel_perfect = false
	timing.brush_color = Color.RED
	timing.begin_uv_triangle_stroke(Vector2(0.5, 0.5), tri)
	var started := Time.get_ticks_usec()
	for i in range(20):
		timing.call("_stamp_unmirrored", Vector2i(400 + i * 30, 900))
	var fast_ms := float(Time.get_ticks_usec() - started) / 1000.0 / 20.0
	timing.fast_stamp_enabled = false
	started = Time.get_ticks_usec()
	for i in range(3):
		timing.call("_stamp_unmirrored", Vector2i(400 + i * 30, 1300))
	var slow_ms := float(Time.get_ticks_usec() - started) / 1000.0 / 3.0
	timing.end_uv_triangle_stroke()
	print("  a 96 px stamp: %.2f ms native, %.2f ms per-pixel" % [fast_ms, slow_ms])
	check(fast_ms * 5.0 < slow_ms, "the native stamp is at least 5x faster (%.2f vs %.2f ms)" % [fast_ms, slow_ms])
	timing.free()
