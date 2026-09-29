extends SceneTree
## 临时探针：随机拼接压力测试（300 种子）——校验通过率 / 回退 / 版图去重 / 包围盒 / 耗时。

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const LOADER := preload("res://src/map/LevelPlanLoader.gd")

const LEVEL := "expedition_01"
const SAMPLES := 300


func _sig(plan: Dictionary) -> String:
	var lines: Array[String] = []
	for value in plan.get("rooms", []):
		var room := value as Dictionary
		var pos := room.get("position", Vector2.ZERO) as Vector2
		var dim := room.get("dimensions", Vector2.ZERO) as Vector2
		lines.append("%s|%.1f,%.1f|%.1fx%.1f|r%.0f" % [
			str(room.get("key", "")), pos.x, pos.y, dim.x, dim.y,
			float(room.get("rotation_deg", 0.0)),
		])
	return "|".join(lines)


func _initialize() -> void:
	var shapes: Dictionary = {}
	var ok := 0
	var fallback := 0
	var invalid := 0
	var worst_ms := 0
	var total_ms := 0
	var bbox_min := Vector2(INF, INF)
	var bbox_max := Vector2(-INF, -INF)
	var span_max := 0.0
	var span_min := INF
	var door_hist: Dictionary = {}
	var error_samples: Array[String] = []
	for index in range(SAMPLES):
		var run_seed := 1 + index * 7919
		var started := Time.get_ticks_msec()
		var plan: Dictionary = GENERATOR.generate_from_level_plan(LEVEL, 0, run_seed)
		var elapsed := Time.get_ticks_msec() - started
		total_ms += elapsed
		worst_ms = maxi(worst_ms, elapsed)
		if plan.is_empty():
			fallback += 1
			continue
		shapes[_sig(plan)] = int(shapes.get(_sig(plan), 0)) + 1
		var errors := plan.get("validation_errors", []) as Array
		if bool(plan.get("valid", false)) and errors.is_empty():
			ok += 1
		else:
			invalid += 1
			if error_samples.size() < 5:
				error_samples.append(str(errors))
		var min_x := INF
		var min_y := INF
		var max_x := -INF
		var max_y := -INF
		for value in plan.get("rooms", []):
			var room := value as Dictionary
			var pos := room.get("position", Vector2.ZERO) as Vector2
			var dim := room.get("dimensions", Vector2.ZERO) as Vector2
			min_x = minf(min_x, pos.x - dim.x * 0.5)
			min_y = minf(min_y, pos.y - dim.y * 0.5)
			max_x = maxf(max_x, pos.x + dim.x * 0.5)
			max_y = maxf(max_y, pos.y + dim.y * 0.5)
			var side := str(room.get("type", ""))
			door_hist[side] = int(door_hist.get(side, 0)) + 1
		bbox_min = Vector2(minf(bbox_min.x, min_x), minf(bbox_min.y, min_y))
		bbox_max = Vector2(maxf(bbox_max.x, max_x), maxf(bbox_max.y, max_y))
		var span := maxf(max_x - min_x, max_y - min_y)
		span_max = maxf(span_max, span)
		span_min = minf(span_min, span)

	print("\n=== 随机拼接压力测试（%d 个种子）===" % SAMPLES)
	print("校验通过=%d  生成回退=%d  校验不通过=%d" % [ok, fallback, invalid])
	print("不同几何版图=%d / %d" % [shapes.size(), SAMPLES])
	print("总耗时=%d ms  平均=%.1f ms  最慢=%d ms" % [
		total_ms, float(total_ms) / float(SAMPLES), worst_ms,
	])
	print("包围盒（全部种子并集）= x[%.1f,%.1f] y[%.1f,%.1f]" % [
		bbox_min.x, bbox_max.x, bbox_min.y, bbox_max.y,
	])
	print("单局最长边跨度: 最小=%.1f m  最大=%.1f m" % [span_min, span_max])
	var repeat_hist: Dictionary = {}
	for key in shapes.keys():
		var count := int(shapes[key])
		repeat_hist[count] = int(repeat_hist.get(count, 0)) + 1
	print("版图重复分布:")
	for count in repeat_hist.keys():
		print("  出现 %d 次 -> %d 个版图" % [int(count), int(repeat_hist[count])])
	for sample in error_samples:
		print("  err: %s" % sample)
	print("\nPROBE_DONE")
	quit(0)
