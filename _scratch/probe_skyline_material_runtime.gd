extends Node

const TARGET := "res://assets/art/environments/open_world/runtime/skyline_08/env_skyline_08_root_top3d.tscn"
var failures: Array[String] = []

func _ready() -> void:
	var packed := load(TARGET) as PackedScene
	if packed == null:
		failures.append("Skyline08正式场景加载失败")
		_report()
		return
	var instance := packed.instantiate()
	add_child(instance)
	for _i in 8:
		await get_tree().process_frame
	var mesh_count := instance.find_children("*", "MeshInstance3D", true, false).size()
	print("SKYLINE08_MATERIAL_RUNTIME mesh_count=", mesh_count)
	if mesh_count <= 0:
		failures.append("Skyline08没有MeshInstance3D")
	instance.queue_free()
	await get_tree().process_frame
	_report()

func _report() -> void:
	if failures.is_empty():
		print("PROBE_SKYLINE08_MATERIAL_OK")
	else:
		for message in failures:
			print("PROBE_SKYLINE08_MATERIAL_FAIL: " + message)
	get_tree().quit(0 if failures.is_empty() else 1)
