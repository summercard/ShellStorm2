extends Node

const SCENE_PATH := "res://scenes/open_world_layout_edit/open_world_chunk_layout_edit.tscn"
const GROUND_Y := -100.0
var failures: Array[String] = []

func _ready() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		failures.append("布局场景加载失败")
		_report()
		return
	var root := packed.instantiate()
	add_child(root)
	await get_tree().process_frame
	var ground := root.get_node_or_null("open_world_ground_500x500") as Node3D
	_expect(ground != null, "缺少地表")
	for name in ["Tower1FoundationBox", "Tower2FoundationBox", "Tower3FoundationBox", "Skyline08FoundationBox"]:
		var node := root.get_node_or_null(name) as MeshInstance3D
		_expect(node != null, "缺少基础盒 " + name)
		if node == null:
			continue
		var box := _world_box(node)
		var bottom := box.position.y
		var top := box.end.y
		print("FOUNDATION name=%s top=%.3f bottom=%.3f size_y=%.3f scale_y=%.6f" % [name, top, bottom, box.size.y, node.scale.y])
		_expect(bottom <= GROUND_Y + 0.01 and top >= GROUND_Y - 0.01, "%s 包络未覆盖地表 Y=%.3f：[%0.3f, %0.3f]" % [name, GROUND_Y, bottom, top])
	root.free()
	_report()

func _world_box(node: MeshInstance3D) -> AABB:
	var mesh_box := node.mesh.get_aabb()
	var result := AABB()
	var found := false
	for i in 8:
		var point := mesh_box.get_endpoint(i)
		var world := node.global_transform * point
		if not found:
			result = AABB(world, Vector3.ZERO)
			found = true
		else:
			result = result.expand(world)
	return result

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _report() -> void:
	if failures.is_empty():
		print("PROBE_MANUAL_LAYOUT_DEEP_GROUND_OK")
	else:
		for message in failures:
			print("PROBE_MANUAL_LAYOUT_DEEP_GROUND_FAIL: " + message)
	get_tree().quit(0 if failures.is_empty() else 1)
