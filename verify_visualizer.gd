#!/usr/bin/env godot --headless --script
## 诊断：验证房间 Visualizer configure() 是否正确注入 room_type
## 运行: cd ShellStorm2 && godot --headless --script verify_vidualizer.gd

extends SceneTree

func _init() -> void:
	print("=== Visualizer configure 诊断 ===")
	
	# 1. 测试 RoomStorage 场景
	print("\n--- [RoomStorage] ---")
	var storage_scene = load("res://scenes/RoomStorage.tscn")
	var room = storage_scene.instantiate()
	root.add_child(room)
	
	var visualizer = room.get_node_or_null("Visualizer")
	print("Visualizer 节点: ", visualizer)
	if visualizer != null:
		print("  script 类型: ", visualizer.get_script().resource_path)
		print("  初始 room_type export: ", visualizer.room_type)
		print("  has_method('configure'): ", visualizer.has_method("configure"))
		print("  has_method('build'): ", visualizer.has_method("build"))
		
		# 尝试调用 configure
		visualizer.configure(RoomData.RoomType.STORAGE, Vector2(960, 768), [])
		print("  configure 后 room_type: ", visualizer.room_type)
		
		# 检查 FloorLayer TileSet
		var tilemap = room.get_node_or_null("FloorLayer")
		if tilemap != null:
			print("  FloorLayer: ", tilemap)
			print("  TileSet: ", tilemap.tile_set)
			if tilemap.tile_set != null:
				print("  TileSet tile_size: ", tilemap.tile_set.tile_size)
				# 检查 TileSet 源数量
				print("  TileSet source 数量: ", tilemap.tile_set.get_source_count())
	
	room.free()
	
	# 2. 测试 RoomCombat 场景
	print("\n--- [RoomCombat] ---")
	var combat_scene = load("res://scenes/RoomCombat.tscn")
	var combat_room = combat_scene.instantiate()
	root.add_child(combat_room)
	
	var combat_visualizer = combat_room.get_node_or_null("Visualizer")
	print("Visualizer 节点: ", combat_visualizer)
	if combat_visualizer != null:
		print("  script 类型: ", combat_visualizer.get_script().resource_path)
		print("  初始 room_type export: ", combat_visualizer.room_type)
		print("  has_method('configure'): ", combat_visualizer.has_method("configure"))
		
		# 直接调用 RoomVisualizer.configure()
		combat_visualizer.configure(RoomData.RoomType.ELITE, Vector2(960, 768), [])
		print("  configure 后 room_type: ", combat_visualizer.room_type)
		
		var tilemap = combat_room.get_node_or_null("FloorLayer")
		if tilemap != null:
			print("  TileSet: ", tilemap.tile_set)
	
	combat_room.free()
	
	# 3. 测试 RoomTileSetBuilder 颜色
	print("\n--- [RoomTileSetBuilder 颜色检查] ---")
	var builder = preload("res://src/map/RoomTileSetBuilder.gd").new()
	var room_types := [
		RoomData.RoomType.COMBAT,
		RoomData.RoomType.ELITE,
		RoomData.RoomType.STORAGE,
		RoomData.RoomType.EXTRACTION,
		RoomData.RoomType.MERCHANT,
		RoomData.RoomType.TRAP,
	]
	for rt in room_types:
		var theme = builder.get_room_theme_colors(rt)
		print("  %s: floor=%s, accent=%s, accent_glow=%s" % [
			RoomData.get_type_name(rt),
			theme.get("floor"),
			theme.get("accent"),
			theme.get("accent_glow")
		])
	
	print("\n=== 诊断完成 ===")
	quit()