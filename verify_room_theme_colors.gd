#!/usr/bin/env godot --headless --script
## 验证房间主题色生成正确性
## 运行: cd ShellStorm2 && godot --headless --script verify_room_theme_colors.gd

extends SceneTree

func _init() -> void:
	print("=== 房间主题色验证 ===")
	
	# 验证 RoomTileSetBuilder 颜色数据
	var builder = preload("res://src/map/RoomTileSetBuilder.gd").new()
	var storage_theme = builder.get_room_theme_colors(RoomData.RoomType.STORAGE)
	var elite_theme = builder.get_room_theme_colors(RoomData.RoomType.ELITE)
	var extraction_theme = builder.get_room_theme_colors(RoomData.RoomType.EXTRACTION)
	
	print("\n[STORAGE 主题]")
	print("  floor: ", storage_theme.get("floor"))
	print("  accent: ", storage_theme.get("accent"))
	
	print("\n[ELITE 主题]")
	print("  floor: ", elite_theme.get("floor"))
	print("  accent_glow: ", elite_theme.get("accent_glow"))
	
	# 测试 RoomTileMapInitializer.configure() 是否正确应用 room_type
	var test_scene = load("res://scenes/RoomStorage.tscn")
	var room = test_scene.instantiate()
	var visualizer = room.get_node_or_null("Visualizer")
	if visualizer != null:
		print("\n[RoomStorage Visualizer 配置]")
		print("  初始 room_type: ", visualizer.room_type)
		# 调用 configure 注入 STORAGE 类型
		visualizer.configure(RoomData.RoomType.STORAGE, Vector2(960, 768), [])
		print("  configure后 room_type: ", visualizer.room_type)
		
		# 检查 TileSet 是否已构建
		var tilemap = visualizer.get_node_or_null("../FloorLayer")
		if tilemap != null and tilemap.tile_set != null:
			print("  TileSet 已构建: YES")
			print("  tile_size: ", tilemap.tile_set.tile_size)
		else:
			print("  TileSet: 未构建")
	
	room.free()
	
	print("\n=== 验证完成 ===")
	quit()