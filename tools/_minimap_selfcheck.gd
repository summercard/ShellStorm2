extends SceneTree

## 开发期自检：真实尺寸（305.6×212 = 382×265 × HUD_UI_SCALE 0.8）下验证小地图不溢出。
##   godot --headless --path <project> --script res://tools/_minimap_selfcheck.gd
## 不进验收套件；断言在 verify_tactical_inventory_minimap_flow 里。

const REAL_SIZE := Vector2(305.6, 212.0)

var _failures: Array[String] = []


func _initialize() -> void:
	var script = load("res://src/ui/DungeonMinimap3D.gd")
	var panel: Control = script.new()
	panel.size = REAL_SIZE
	root.add_child(panel)

	var records := _synthetic_floor()
	panel.configure(records, {})
	for r in records:
		panel.reveal_room(str(r["id"]))
	panel.set_current_room("room_03")
	var enemies: Array[Vector3] = [Vector3(6, 0, 3)]
	panel.set_enemy_positions(enemies)
	panel.set_player_state(Vector3(0, 0, 0), Vector3.RIGHT)

	var snap: Dictionary = panel.get_snapshot()
	_expect(str(snap.get("tile_style", "")) == "egt_room_tile", "tile_style 未生效")
	_expect(not bool(snap.get("player_centered", true)), "仍是居中雷达")
	_expect(bool(snap.get("fixed_scale", false)), "未声明固定缩放")

	var ppm := float(snap.get("px_per_m", 0.0))
	var bounds: Rect2 = panel._floor_bounds_world()
	var drawn := bounds.size * ppm
	print("panel=%s  bounds=%s  ppm=%.3f  drawn=%s" % [panel.size, bounds.size, ppm, drawn])

	# 核心断言：满层不得溢出面板
	_expect(drawn.x <= panel.size.x + 0.5, "地图横向溢出面板（%.1f > %.1f）" % [drawn.x, panel.size.x])
	_expect(drawn.y <= panel.size.y + 0.5, "地图纵向溢出面板（%.1f > %.1f）" % [drawn.y, panel.size.y])

	# 房间矩形必须落在面板内
	for r in records:
		var rect: Rect2 = panel.get_room_screen_rect(str(r["id"]))
		_expect(
			rect.position.x >= -0.5 and rect.end.x <= panel.size.x + 0.5
			and rect.position.y >= -0.5 and rect.end.y <= panel.size.y + 0.5,
			"%s 房间矩形越界 %s" % [str(r["id"]), rect]
		)

	# 地图不随玩家移动、缩放不变
	var before: Vector2 = panel.get_room_screen_rect("room_01").get_center()
	panel.set_player_state(Vector3(40, 0, -20), Vector3.LEFT)
	var after: Vector2 = panel.get_room_screen_rect("room_01").get_center()
	_expect(before.is_equal_approx(after), "玩家移动后地图跟着动了")
	_expect(
		is_equal_approx(ppm, float(panel.get_snapshot().get("px_per_m", 0.0))),
		"玩家移动导致缩放变化"
	)

	if _failures.is_empty():
		print("MINIMAP SELFCHECK OK")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _room(id: String, type_id: String, center: Vector2, w: float, h: float, doors: Array, targets: Dictionary) -> Dictionary:
	return {
		"id": id, "type": type_id, "size": "medium",
		"position": Vector3(center.x, 0.0, center.y),
		"doors": doors, "door_targets": targets,
		"main": true, "parent": "", "index": 0, "vertical_level": 0,
		"custom_dimensions": Vector2(w, h),
		"door_endpoint_owners": {},
	}


## 一个**满层**尺度的合成层：6 间 25m 房横排 35m 步长 + 一条支线，总跨度 210×60m。
## 这是最坏情况 —— 用它来证明角落态不会溢出。
func _synthetic_floor() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var step := 35.0
	result.append(_room("room_01", "SAFE", Vector2(0, 0), 15, 15, ["east"], {"east": "room_02"}))
	result.append(_room("room_02", "STORAGE", Vector2(step, 0), 25, 25, ["west", "east"],
		{"west": "room_01", "east": "room_03"}))
	result.append(_room("room_03", "COMBAT", Vector2(step * 2, 0), 25, 25, ["west", "east", "south"],
		{"west": "room_02", "east": "room_04", "south": "room_05"}))
	result.append(_room("room_04", "BOSS", Vector2(step * 3, 0), 25, 25, ["west"], {"west": "room_03"}))
	result.append(_room("room_05", "SHOP", Vector2(step * 2, step), 25, 25, ["north", "east"],
		{"north": "room_03", "east": "room_06"}))
	result.append(_room("room_06", "EXTRACTION", Vector2(step * 3, step), 25, 25, ["west"], {"west": "room_05"}))
	return result
