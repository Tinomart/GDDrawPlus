@tool
extends EditorPlugin

var failures := 0
var _frames := 0
var _started := false
var _counts := {}


func check(condition: bool, message: String) -> void:
	if condition:
		print("HKTEST  PASS  ", message)
	else:
		failures += 1
		print("HKTEST  FAIL  ", message)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 240 and not _started:
		_started = true
		_run()
	if _frames == 3000:
		print("HKTEST  TIMEOUT")
		get_tree().quit(2)


func _find_dock() -> Control:
	for control in get_editor_interface().get_base_control().find_children("GDDraw", "Control", true, false):
		if control.has_meta("gddraw_bottom_panel_dock"):
			return control
	return null


func _key(keycode: Key, ctrl := true, shift := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	ev.pressed = true
	return ev


func _mouse_press(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	return ev


func _count(popup_name: String, id: int) -> int:
	return int(_counts.get(popup_name + str(id), 0))


func _run() -> void:
	var dock := _find_dock()
	check(dock != null, "GDDraw dock present")
	if dock == null:
		get_tree().quit(1)
		return
	var viewport := get_editor_interface().get_base_control().get_viewport()
	for menu_name in ["_file_menu", "_edit_menu", "_view_menu", "_select_menu"]:
		var popup: PopupMenu = dock.get(menu_name)
		popup.id_pressed.connect(func(id: int) -> void: _counts[menu_name + str(id)] = _count(menu_name, id) + 1)
	var save_id := -1
	var undo_id := -1
	var file_menu: PopupMenu = dock.get("_file_menu")
	for i in range(file_menu.item_count):
		if file_menu.get_item_text(i) == "Save":
			save_id = file_menu.get_item_id(i)
	var edit_menu: PopupMenu = dock.get("_edit_menu")
	for i in range(edit_menu.item_count):
		if edit_menu.get_item_text(i) == "Undo":
			undo_id = edit_menu.get_item_id(i)
	# Show the GDDraw bottom panel, as it is when the user works with it.
	(dock.get_meta("gddraw_plugin") as EditorPlugin).make_bottom_panel_item_visible(dock)
	for _i in range(20):
		await get_tree().process_frame
	print("HKTEST  dock visible in tree: ", dock.is_visible_in_tree(), "  rect: ", dock.get_global_rect())
	check(dock.is_visible_in_tree(), "GDDraw bottom panel is open, like in real use")

	var rect := dock.get_global_rect()
	var inside := rect.get_center()
	var outside := Vector2(6, 6)
	var new_id := _menu_id(dock, "_file_menu", "New")
	var select_all_id := _select_all_id(dock)

	print("HKTEST  -- A) window-wide accelerators (the reported bug): a real key event, no click in GDDraw")
	# Viewport.push_input reaches MenuBar accelerators, which reproduced the bug before the fix.
	for spec in [[KEY_S, save_id, "Ctrl+S"], [KEY_A, select_all_id, "Ctrl+A"], [KEY_N, new_id, "Ctrl+N"], [KEY_O, _menu_id(dock, "_file_menu", "Open…"), "Ctrl+O"], [KEY_W, _menu_id(dock, "_file_menu", "Close"), "Ctrl+W (GDDraw 0.3.0+)"]]:
		_counts.clear()
		viewport.push_input(_key(spec[0]))
		for _i in range(3):
			await get_tree().process_frame
		check(_fired(spec[1]) == 0, "%s pushed into the editor window is NOT taken by GDDraw (fired %d)" % [spec[2], _fired(spec[1])])
		_close_dialogs(dock)

	print("HKTEST  -- B) scoping logic (handler called with each event)")
	check(not dock.call("_shortcut_is_scoped_to_gddraw"), "initially GDDraw is not in scope")
	check(_dispatch(dock, _key(KEY_S), save_id) == 0, "Ctrl+S with no click: not handled by GDDraw")

	dock.call("_input", _motion(inside))
	check(not dock.call("_shortcut_is_scoped_to_gddraw"), "hovering the dock does not put GDDraw in scope")
	check(_dispatch(dock, _key(KEY_S), save_id) == 0, "Ctrl+S while only hovering: not handled by GDDraw")

	dock.call("_input", _mouse_press(inside))
	check(dock.call("_shortcut_is_scoped_to_gddraw"), "after a click inside GDDraw it is in scope")
	check(_dispatch(dock, _key(KEY_S), save_id) == 1, "Ctrl+S after clicking in GDDraw: GDDraw's Save fires once")
	check(_dispatch(dock, _key(KEY_N), new_id) == 1, "Ctrl+N after clicking in GDDraw: GDDraw's New fires once")
	var save_as_id := _menu_id(dock, "_file_menu", "Save As…")
	check(_dispatch(dock, _key(KEY_S, true, true), save_as_id) == 1, "Ctrl+Shift+S after clicking in GDDraw: 'Save As' fires once")
	check(_dispatch(dock, _key(KEY_S, true, true), save_id) == 0, "...and Ctrl+Shift+S is not mistaken for plain Save")
	check(_dispatch(dock, _key(KEY_S, false), save_id) == 0, "plain 'S' (no Ctrl) does not trigger Save")

	dock.call("_input", _mouse_press(outside))
	check(not dock.call("_shortcut_is_scoped_to_gddraw"), "after clicking elsewhere in the editor GDDraw is out of scope again")
	check(_dispatch(dock, _key(KEY_S), save_id) == 0, "Ctrl+S after clicking elsewhere: Godot's again")

	dock.call("_input", _mouse_press(inside))
	dock.hide()
	await get_tree().process_frame
	check(not dock.call("_shortcut_is_scoped_to_gddraw"), "a hidden GDDraw panel is never in scope")
	check(_dispatch(dock, _key(KEY_S), save_id) == 0, "Ctrl+S with GDDraw's panel hidden: not handled by GDDraw")
	dock.show()
	await get_tree().process_frame

	print("HKTEST  RESULT: ", "ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _fired(id: int) -> int:
	var total := 0
	for menu_name in ["_file_menu", "_edit_menu", "_view_menu", "_select_menu"]:
		total += _count(menu_name, id)
	return total


func _close_dialogs(dock: Control) -> void:
	for dialog in dock.find_children("*", "FileDialog", true, false):
		(dialog as FileDialog).hide()
	for dialog in dock.find_children("*", "ConfirmationDialog", true, false):
		(dialog as ConfirmationDialog).hide()


func _motion(pos: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	return ev


# Hands `event` to the dock's _input and returns how often menu command `id` fired.
func _dispatch(dock: Control, event: InputEvent, id: int) -> int:
	_counts.clear()
	dock.call("_input", event)
	var fired := _fired(id)
	_close_dialogs(dock)
	return fired

func _menu_id(dock: Control, menu_name: String, text: String) -> int:
	var popup: PopupMenu = dock.get(menu_name)
	for i in range(popup.item_count):
		if popup.get_item_text(i) == text:
			return popup.get_item_id(i)
	return -1


func _select_all_id(dock: Control) -> int:
	return _menu_id(dock, "_select_menu", "Select All")


func _menu_name_for(dock: Control, id: int) -> String:
	for menu_name in ["_file_menu", "_edit_menu", "_view_menu", "_select_menu"]:
		var popup: PopupMenu = dock.get(menu_name)
		for i in range(popup.item_count):
			if popup.get_item_id(i) == id:
				return menu_name
	return ""


