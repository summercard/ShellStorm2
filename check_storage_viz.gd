#!/usr/bin/env godot --headless --script
## 诊断：验证 RoomStorage 的 Visualizer configure() 是否正确
extends SceneTree

func _init() -> void:
	print("=== RoomStorage Visualizer 诊断 ===")
	
	var scene = load("res://scenes/RoomStorage.tscn")
	var room = scene.instantiate()
	root.add_child(room)
	
	var viz = room.get_node_or_null("Visualizer")
	print("Visualizer: ", viz)
	if viz != null:
		print("  script: ", viz.get_script().resource_path.get_file())
		print("  初始 room_type: ", viz.room_type)
		print("  初始 room_type (int): ", int(viz.room_type))
		
		# 调用 configure
		viz.configure(RoomData.RoomType.STORAGE, Vector2(960, 768), [])
		print("  configure后 room_type: ", viz.room_type)
		print("  configure后 room_type (int): ", int(viz.room_type))
		
		# 检查 FloorLayer
		var tilemap = room.get_node_or_null("FloorLayer")
		if tilemap != null:
			print("  FloorLayer.tile_set: ", tilemap.tile_set)
	
	room.free()
	print("=== 完成 ===")
	quit()