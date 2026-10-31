extends SceneTree
## 验证 layout_model 的布局函数能否在 headless 里直接驱动（不经工坊 UI）。

const MODEL := preload("res://tools/scene_builder/layout_model.gd")

func _initialize() -> void:
	var cat: Dictionary = MODEL.catalog()
	print("CLI_CATALOG rows=%d errors=%d" % [cat["rows"].size(), cat["errors"].size()])
	# 找一件公馆地砖与一件护墙
	var floor_row := {}
	var wall_row := {}
	for row in cat["rows"]:
		var slug := str(row.get("slug", ""))
		if slug == "manor_floor_wood":
			floor_row = row
		elif slug == "manor_wall_standard":
			wall_row = row
	print("CLI_FLOOR found=%s size=%s" % [not floor_row.is_empty(), str(MODEL.component_size(floor_row))])
	print("CLI_WALL  found=%s size=%s" % [not wall_row.is_empty(), str(MODEL.component_size(wall_row))])

	# 25×25 房间：矩形铺点（工坊「矩形」模式用的就是它）
	var a := Vector3(-12.5, 0.0, -12.5)
	var b := Vector3(12.5, 0.0, 12.5)
	var points: Array = MODEL.rectangle_points(a, b, 5.0)
	print("CLI_RECT_25x25 points=%d" % points.size())
	print("CLI_RECT_SAMPLE %s ... %s" % [str(points[0]), str(points[points.size() - 1])])

	# 直线铺墙
	var wall_points: Array = MODEL.line_points(Vector3(-12.5, 0.0, -12.5), Vector3(12.5, 0.0, -12.5), 5.0)
	print("CLI_LINE_NORTH points=%d" % wall_points.size())

	# 轮廓内判定（工坊「限制在房间内」用的）
	var outline := PackedVector2Array([
		Vector2(-12.5, -12.5), Vector2(12.5, -12.5),
		Vector2(12.5, 12.5), Vector2(-12.5, 12.5)])
	var inside_count := 0
	for p in points:
		if MODEL.inside(Vector2(p.x, p.z), outline):
			inside_count += 1
	print("CLI_INSIDE inside=%d / %d" % [inside_count, points.size()])

	# 实例化组件（这才是真正"摆"）
	var floor_node: Node3D = MODEL.instantiate_component(floor_row)
	var wall_node: Node3D = MODEL.instantiate_component(wall_row)
	print("CLI_INSTANTIATE floor=%s wall=%s" %
		["ok" if floor_node != null else "FAIL", "ok" if wall_node != null else "FAIL"])
	if floor_node != null:
		var meshes := floor_node.find_children("*", "MeshInstance3D", true, false)
		print("CLI_FLOOR_MESHES %d" % meshes.size())
		floor_node.free()
	if wall_node != null:
		wall_node.free()

	# 尺寸适配判定
	print("CLI_FITS floor_at_origin=%s" % MODEL.fits(Vector3(0, 0, 0), floor_row, 0.0, outline))
	print("CLI_FITS wall_at_north=%s" % MODEL.fits(Vector3(0, 0, -12.5), wall_row, 0.0, outline))
	quit(0)
