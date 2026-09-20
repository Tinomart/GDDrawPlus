@tool
extends EditorPlugin

var _frames := 0
var _started := false
var _fail := 0


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 240 and not _started:
		_started = true
		_run()
	if _frames == 3000:
		print("FKTEST  TIMEOUT")
		get_tree().quit(2)


func _find_dock() -> Control:
	for control in get_editor_interface().get_base_control().find_children("GDDraw", "Control", true, false):
		if control.has_meta("gddraw_bottom_panel_dock"):
			return control
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("FKTEST  PASS  ", message)
	else:
		_fail += 1
		print("FKTEST  FAIL  ", message)


func _run() -> void:
	var config := ConfigFile.new()
	config.load("res://addons/GDDraw/plugin.cfg")
	var version := str(config.get_value("plugin", "version", ""))
	_check(str(config.get_value("plugin", "name", "")) == "GDDraw Plus", "the plugin is called GDDraw Plus")
	_check(version != "" and version.split(".").size() == 3, "the version is a plain x.y.z: " + version)
	var plugin_script := load("res://addons/GDDraw/GDDraw.gd") as GDScript
	_check(str(plugin_script.get_script_constant_map().get("PLUGIN_VERSION", "")) == version, "PLUGIN_VERSION matches plugin.cfg")
	var dock := _find_dock()
	_check(dock != null, "the dock is up")
	if dock == null:
		get_tree().quit(1)
		return
	var constants: Dictionary = dock.get_script().get_script_constant_map()
	_check(constants.get("UPDATES_ENABLED", true) == false, "in-editor updates are switched off (they would install the original GDDraw)")
	_check(dock.call("_check_for_updates", true) == false, "the automatic update check does nothing")
	await get_tree().process_frame
	_check(dock.call("_check_for_updates", false) == false, "Help > Check for Updates starts no request")
	await get_tree().process_frame
	var checker = dock.get("_update_checker")
	_check(checker == null or not checker.is_request_active(), "no update request is running")
	for file_name in ["LICENSE", "THIRD_PARTY_NOTICES.md"]:
		_check(FileAccess.file_exists("res://addons/GDDraw/" + file_name), "%s ships inside the addon" % file_name)
	var notices := FileAccess.get_file_as_string("res://addons/GDDraw/THIRD_PARTY_NOTICES.md")
	_check(notices.contains("Gator Model Studio") and notices.contains("Blackwater Gator Studios"), "the notices credit Gator Model Studio")
	_check(FileAccess.file_exists("res://addons/GDDraw/uv/LICENSE-GatorModelStudio.txt"), "the Gator license text sits next to the UV code")
	print("FKTEST  RESULT: ", "ALL PASSED" if _fail == 0 else "%d FAILED" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)