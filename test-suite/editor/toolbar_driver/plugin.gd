@tool
extends EditorPlugin

var failures := 0
var _frames := 0
var _started := false


func check(condition: bool, message: String) -> void:
	if condition:
		print("TBTEST  PASS  ", message)
	else:
		failures += 1
		print("TBTEST  FAIL  ", message)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 240 and not _started:
		_started = true
		_run()
	if _frames == 3000:
		print("TBTEST  TIMEOUT")
		get_tree().quit(2)


func _find_dock() -> Control:
	for control in get_editor_interface().get_base_control().find_children("GDDraw", "Control", true, false):
		if control.has_meta("gddraw_bottom_panel_dock"):
			return control
	return null


func _wait(frames := 6) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _inside(inner: Rect2, outer: Rect2) -> bool:
	return inner.position.x >= outer.position.x - 0.5 and inner.end.x <= outer.end.x + 0.5


func _bar_overflows(scroll: ScrollContainer, bar: Control) -> bool:
	return bar.get_combined_minimum_size().x > scroll.size.x + 1.0


func _run() -> void:
	var dock := _find_dock()
	check(dock != null, "GDDraw dock present")
	if dock == null:
		get_tree().quit(1)
		return

	var row := dock.find_child("Tool Options Row", true, false) as HBoxContainer
	var scroll := dock.find_child("Tool Options Scroll", true, false) as ScrollContainer
	var bar := dock.find_child("Tool Options Bar", true, false) as HBoxContainer
	var view := dock.find_child("View Mode Selector", true, false) as OptionButton
	var channel := dock.find_child("Paint Channel Selector", true, false) as OptionButton
	var link := dock.find_child("View Link Separator", true, false) as Control
	check(row != null and scroll != null and bar != null and view != null and channel != null, "options row, scroll area, bar, view selector and channel selector exist")
	if row == null or scroll == null or bar == null or view == null or channel == null:
		get_tree().quit(1)
		return
	check(bar.get_parent() == scroll and scroll.get_parent() == row, "tool options live inside the scroll area of the row")
	check(view.get_parent() == row and link.get_parent() == row, "view selector and link toggle are pinned outside the scroll area")
	check(channel.get_parent() == bar, "channel selector scrolls with the tool options")
	check(channel.custom_minimum_size.x <= 110 and channel.clip_text, "channel selector is compact (110 px minimum, clipped text)")
	check(scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "the scroll area only scrolls horizontally")

	# Take the row out of the dock and squeeze it into fixed-width holders.
	var holder := Control.new()
	holder.clip_contents = true
	get_editor_interface().get_base_control().add_child(holder)
	holder.position = Vector2.ZERO
	row.reparent(holder, false)
	row.position = Vector2.ZERO
	# Realistic state: the default tool (brush options) plus the channel selector in 3D mode.
	channel.visible = true
	var real_min := 0.0
	var real_height_wide := 0.0
	var real_height_narrow := 0.0
	for width in [1600.0, 1000.0, 700.0, 500.0]:
		holder.size = Vector2(width, 80)
		row.size = Vector2(width, 0)
		await _wait()
		var holder_rect_r := Rect2(holder.global_position, holder.size)
		var hbar_r := scroll.get_h_scroll_bar()
		var need := bar.get_combined_minimum_size().x
		print("TBTEST  info  realistic width ", int(width), ": tools need ", need, " px, scroll area ", scroll.size.x, ", scrollbar visible ", hbar_r.visible, ", row height ", row.size.y)
		check(_inside(view.get_global_rect(), holder_rect_r) and view.is_visible_in_tree(), "realistic width %d: the 2D/3D selector is fully visible" % int(width))
		check(not _bar_overflows(scroll, bar) or hbar_r.visible, "realistic width %d: scrollbar shown exactly when the tools do not fit" % int(width))
		if width == 1600.0:
			real_min = need
			real_height_wide = row.size.y
			check(need < 1400.0 and not hbar_r.visible, "realistic width 1600: the normal toolbar fits with no scrollbar (needs %d px)" % int(need))
		real_height_narrow = row.size.y
	print("TBTEST  info  row height: wide ", real_height_wide, " / narrow ", real_height_narrow)
	# The brush size box accepts big brushes (it used to stop at 96; big brushes are drawn natively now).
	var brush_size_box: SpinBox = dock.get("_brush_size")
	check(brush_size_box != null and brush_size_box.max_value >= 512, "the brush size goes up to %d" % int(brush_size_box.max_value if brush_size_box else 0))
	if brush_size_box:
		brush_size_box.value = 400
		check(dock.get("_canvas").brush_size == 400, "and a 400 px brush is applied to the canvas")
		brush_size_box.value = 12
	# Worst case: every tool's options visible at once (never happens in practice).
	for name in ["_brush_options", "_shape_options", "_text_options", "_selection_options", "_eyedropper_options", "_channel_selector"]:
		var node = dock.get(name)
		if node is Control:
			node.visible = true
	channel.visible = true

	var natural_content := 0.0

	var last_height := 0.0
	for width in [1600.0, 900.0, 600.0, 420.0, 320.0]:
		holder.size = Vector2(width, 80)
		row.size = Vector2(width, 0)
		await _wait()
		var holder_rect := Rect2(holder.global_position, holder.size)
		var v := view.get_global_rect()
		var label := "width %d" % int(width)
		check(view.is_visible_in_tree() and _inside(v, holder_rect), label + ": the 2D/3D selector is fully visible " + str(v) + " in " + str(holder_rect))
		check(_inside(row.get_global_rect(), holder_rect), label + ": the row does not overflow its space (row " + str(row.get_global_rect()) + ")")
		var hbar := scroll.get_h_scroll_bar()
		var overflows := bar.size.x > scroll.size.x + 1.0 or bar.get_combined_minimum_size().x > scroll.size.x + 1.0
		print("TBTEST  info  ", label, ": scroll width ", scroll.size.x, ", content min ", bar.get_combined_minimum_size().x, ", scrollbar visible ", hbar.visible, ", row height ", row.size.y)
		natural_content = bar.get_combined_minimum_size().x
		last_height = row.size.y
		if natural_content > scroll.size.x + 1.0:
			check(hbar.visible, label + ": scrollbar appears when the tools do not fit")

	# Narrow: scroll all the way right, channel selector must be reachable and the view selector still pinned.
	holder.size = Vector2(420, 80)
	row.size = Vector2(420, 0)
	await _wait()
	scroll.scroll_horizontal = 0
	await _wait(3)
	var start_rect := channel.get_global_rect()
	scroll.scroll_horizontal = 100000
	await _wait(3)
	var scrolled_rect := channel.get_global_rect()
	var scroll_rect := scroll.get_global_rect()
	check(scrolled_rect.position.x < start_rect.position.x - 1.0, "scrolling right moves the tool options left")
	check(_inside(scrolled_rect, scroll_rect), "scrolled to the end, the channel selector is inside the scroll area " + str(scrolled_rect) + " vs " + str(scroll_rect))
	check(_inside(view.get_global_rect(), Rect2(holder.global_position, holder.size)), "the 2D/3D selector did not move while scrolling")

	# Mouse wheel over the bar scrolls it sideways (vertical wheel, no vertical scrollbar).
	scroll.scroll_horizontal = 0
	await _wait(2)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.factor = 1.0
	wheel.position = Vector2(20, 10)
	wheel.global_position = scroll.global_position + wheel.position
	get_viewport().push_input(wheel, false)
	await _wait(2)
	check(scroll.scroll_horizontal > 0, "mouse wheel scrolls the tool options sideways (scroll_horizontal=" + str(scroll.scroll_horizontal) + ")")

	print("TBTEST  RESULT: ", "ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)
