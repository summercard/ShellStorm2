extends Node
## 只读探查 v9：
##  1) 打印 `编辑器参考_运行时自动隐藏` 子树每个节点的 visible（这批本该在运行时隐藏）
##  2) 从 98F 入口安全房正上方拍正交俯视图：全开 / 隐藏该批参考对象，用来对拍
##    玩家从安全房出来看到的那条亮蓝色地面带。

const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"
const TARGET_FLOOR := 98
const OUT_DIR := "I:/工作项目/shellstrom2/_scratch/"


func _ready() -> void:
	var scene := load(TOWER_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	tower.generate_through_floor_for_test(TARGET_FLOOR)
	await get_tree().process_frame
	var room_by_id := tower.get("_room_by_id") as Dictionary
	for id_value in room_by_id.keys():
		var room := room_by_id.get(id_value) as DungeonRoom3D
		if room != null:
			room.set_stream_state(1)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	print("=== 编辑器参考_运行时自动隐藏 子树 ===")
	var ref_roots: Array[Node] = []
	for value in tower.find_children("*", "Node3D", true, false):
		var node := value as Node3D
		if node == null:
			continue
		if "编辑器参考" in String(node.name) or "运行时自动隐藏" in String(node.name):
			ref_roots.append(node)
			print("  [root] %s  class=%s visible=%s" % [
				String(tower.get_path_to(node)), node.get_class(), str(node.visible)
			])
			for child in node.get_children():
				var c3 := child as Node3D
				print("     - %-40s %-20s visible_in_tree=%s own_visible=%s" % [
					String(child.name), child.get_class(),
					str(c3.visible_in_tree if c3 != null else false),
					str(c3.visible if c3 != null else false),
				])
	print("  roots=%d" % ref_roots.size())

	# 也打印所有 "30米地面参考" 直接搜索
	print("")
	print("=== 名字含「地面参考」的节点 ===")
	for value in tower.find_children("*", "Node3D", true, false):
		var node := value as Node3D
		if node == null:
			continue
		if "地面参考" in String(node.name):
			print("  %s visible_in_tree=%s own=%s class=%s" % [
				String(tower.get_path_to(node)), str(node.visible_in_tree),
				str(node.visible), node.get_class(),
			])

	var camera := Camera3D.new()
	camera.name = "ProbeOrthoCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 90.0
	camera.near = 0.05
	camera.far = 300.0
	tower.add_child(camera)
	camera.global_position = Vector3(27.5, -12.4, 2.5)
	camera.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	camera.current = true

	await _shoot("room98_all.png")

	for root in ref_roots:
		var node := root as Node3D
		if node != null:
			node.visible = false
	await _shoot("room98_no_ref.png")

	print("PROBE_V9_DONE")
	get_tree().quit(0)


func _shoot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(OUT_DIR + file_name)
	print("saved %s err=%d" % [file_name, error])
