extends Node
## 一次性勘察探针：实测**各层生成器**产出的房间平面包络，用于回答
## 「把楼层壳体缩到 100F 的 90×80 矩形之后，别的楼层装不装得下」。
##
## 只读 `FloorPlanGenerator.generate()` 的返回值，不建塔楼、不读 .glb。
## 对 98F 额外打印区块00 覆盖后的结果（那才是真实运行的 98F 布局）。

const FLOOR_PLAN_GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const TARGET_OUTLINE := Rect2(-50.0, -35.0, 90.0, 80.0)

## 逐层：99 - 层号 = sequence_index，physical = sequence + 1（与 TowerDescent3D 同口径）
const FLOORS: Array[int] = [98, 97, 96, 95, 90, 85]


func _ready() -> void:
	print("目标轮廓（= 100F 天台）= x[%.0f, %.0f] z[%.0f, %.0f]  = %.0f × %.0f m" % [
		TARGET_OUTLINE.position.x, TARGET_OUTLINE.end.x,
		TARGET_OUTLINE.position.y, TARGET_OUTLINE.end.y,
		TARGET_OUTLINE.size.x, TARGET_OUTLINE.size.y,
	])
	print("")
	for floor_number in FLOORS:
		var sequence_index := 99 - floor_number
		var physical_index := sequence_index + 1
		var stair_side := "east" if sequence_index % 2 == 1 else "west"
		var plan: Dictionary = FLOOR_PLAN_GENERATOR.generate({
			"run_seed": 990321,
			"floor_number": floor_number,
			"floor_index": physical_index,
			"sequence_index": sequence_index,
			"entry_side": stair_side,
			"boss_floor": floor_number % 5 == 0,
		})
		_report(floor_number, physical_index, plan, "生成器内置房表")

	print("")
	print("=== 4 个楼梯井（固定世界常量）对目标轮廓 ===")
	for entry in [
		["west", Rect2(-45.0, 0.0, 15.0, 30.0)],
		["east", Rect2(35.0, -25.0, 15.0, 30.0)],
		["north", Rect2(-25.0, -45.0, 30.0, 15.0)],
		["south", Rect2(0.0, 35.0, 30.0, 15.0)],
	]:
		var side := str(entry[0])
		var hole := entry[1] as Rect2
		var over: Array[String] = []
		if hole.position.x < TARGET_OUTLINE.position.x:
			over.append("西越 %.1f" % (TARGET_OUTLINE.position.x - hole.position.x))
		if hole.end.x > TARGET_OUTLINE.end.x:
			over.append("东越 %.1f" % (hole.end.x - TARGET_OUTLINE.end.x))
		if hole.position.y < TARGET_OUTLINE.position.y:
			over.append("北越 %.1f" % (TARGET_OUTLINE.position.y - hole.position.y))
		if hole.end.y > TARGET_OUTLINE.end.y:
			over.append("南越 %.1f" % (hole.end.y - TARGET_OUTLINE.end.y))
		print("  %-5s x[%6.1f,%6.1f] z[%6.1f,%6.1f]  %s" % [
			side, hole.position.x, hole.end.x, hole.position.y, hole.end.y,
			"在内" if over.is_empty() else "、".join(over),
		])

	print("\nPROBE_ENVELOPE_DONE")
	get_tree().quit(0)


func _report(floor_number: int, physical_index: int, plan: Dictionary, source: String) -> void:
	var rooms := plan.get("rooms", []) as Array
	if rooms.is_empty():
		print("%dF (idx=%d) %s：无房间" % [floor_number, physical_index, source])
		return
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for value in rooms:
		var room := value as Dictionary
		var pos: Vector2 = room.get("position", Vector2.ZERO)
		var dims: Vector2 = room.get("dimensions", Vector2.ZERO)
		min_x = minf(min_x, pos.x - dims.x * 0.5)
		max_x = maxf(max_x, pos.x + dims.x * 0.5)
		min_z = minf(min_z, pos.y - dims.y * 0.5)
		max_z = maxf(max_z, pos.y + dims.y * 0.5)
	var span_x := max_x - min_x
	var span_z := max_z - min_z
	var fits := (
		min_x >= TARGET_OUTLINE.position.x and max_x <= TARGET_OUTLINE.end.x
		and min_z >= TARGET_OUTLINE.position.y and max_z <= TARGET_OUTLINE.end.y
	)
	print("%dF (idx=%d) %s：%d 房  包络 x[%.1f, %.1f] z[%.1f, %.1f]  跨 %.1f × %.1f m" % [
		floor_number, physical_index, source, rooms.size(), min_x, max_x, min_z, max_z, span_x, span_z,
	])
	print("        对 90×80 目标：%s" % (
		"装得下" if fits else "**装不下**（需 %.1f × %.1f）" % [span_x, span_z]
	))
