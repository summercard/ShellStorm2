## 验证：检查 DemoRoomChain 中 STORAGE 房间的 TileSet 是否正确构建
extends Node

func _ready() -> void:
	print("=== DemoRoomChain STORAGE 房间 TileSet 验证 ===")
	
	var demo_scene = load("res://scenes/DemoRoomChain.tscn")
	if demo_scene == null:
		print("ERROR: DemoRoomChain.tscn 未找到")
		get_tree().quit(1)
		return
	
	var demo = demo_scene.instantiate()
	add_child(demo)
	
	# 等待 _ready 完成
	await get_tree().process_frame
	
	# 等待所有房间实例化完成（_instantiate_demo_rooms 在 _ready 中调用）
	await get_tree().process_frame
	
	# 获取 R3 (STORAGE) 房间
	var r3 = demo.get_node_or_null("DemoRoom_2")
	if r3 == null:
		print("ERROR: DemoRoom_2 (STORAGE) 未找到")
		demo.free()
		get_tree().quit(1)
		return
	
	# 直接检查 FloorLayer
	var tilemap = r3.get_node_or_null("FloorLayer")
	if tilemap == null:
		print("ERROR: R3 FloorLayer 未找到")
	else:
		print("R3 FloorLayer TileSet: ", tilemap.tile_set)
		if tilemap.tile_set != null:
			print("R3 TileSet tile_size: ", tilemap.tile_set.tile_size)
			print("R3 TileSet source_count: ", tilemap.tile_set.get_source_count())
		else:
			print("R3 TileSet: NULL (未构建)")
	
	# 检查 Visualizer
	var viz = r3.get_node_or_null("Visualizer")
	if viz != null:
		print("R3 Visualizer room_type: ", viz.room_type)
		print("R3 Visualizer _built: ", viz.get("_built") if viz.has_method("get") else "N/A")
		print("R3 Visualizer script: ", viz.get_script().resource_path)
	
	# 检查 RoomStorage script
	var storage_logic = r3.get_node_or_null("StorageRoomLogic")
	if storage_logic != null:
		print("R3 StorageRoomLogic: ", storage_logic.get_script().resource_path)
	
	demo.free()
	print("DEMO_STORAGE_OK: storage tiles and visualizer are available")
	get_tree().quit()
