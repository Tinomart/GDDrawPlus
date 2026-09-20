extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS  ", message)
	else:
		failures += 1
		print("  FAIL  ", message)

func _init() -> void:
	for pair in [["CylinderMesh", CylinderMesh.new()], ["SphereMesh", SphereMesh.new()], ["BoxMesh", BoxMesh.new()]]:
		var mesh: Mesh = pair[1]
		var adapter = GDDrawUVMeshAdapter.from_mesh(mesh)
		check(adapter != null, "%s: the UV editor can read the mesh" % pair[0])
		var triangles: int = GDDrawUVService.count_triangles(mesh)
		check(triangles > 0, "%s: triangles are counted (%d)" % [pair[0], triangles])
	print("RESULT: ", "ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)