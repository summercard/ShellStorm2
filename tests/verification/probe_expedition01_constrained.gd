extends Node
## 临时探针：远征关卡01 mode=constrained 端到端统计（生成 + 校验 + 耗时 + 形态）。
## 本轮 Task #35 的取证工具，用完即删。

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const LOADER := preload("res://src/map/LevelPlanLoader.gd")
const VALIDATOR := preload("res://src/map/LevelPlanValidator.gd")

const LEVEL := "expedition_01"
const SAMPLES := 300


func _ready() -> void:
	var level_plan := LOADER.load_level_plan(LEVEL)
	if level_plan.is_empty():
		print("PROBE_FAIL: level_plan 加载失败")
		get_tree().quit(1)
		return
	var policy := level_plan.get("generation_policy", {}) as Dictionary
	var templates := LOADER.load_room_templates(LEVEL)
	var normalized := LOADER.normalize_floor(LEVEL, 0)
	var file_errors := VALIDATOR.validate_floor(LEVEL, 0, policy, templates)
	print("mode=%s rooms=%d templates=%d" % [
		str(normalized.get("mode", "?")), (normalized.get("rooms", []) as Array).size(), templates.size()
	])
	print("validate_floor(file) errors=%d %s" % [file_errors.size(), str(file_errors)])

	var ok := 0
	var fallback := 0
	var invalid := 0
	var error_samples: Array[String] = []
	var shapes: Dictionary = {}
	var template_counts: Dictionary = {}
	var door_counts: Dictionary = {}
	var t0 := Time.get_ticks_msec()
	var worst_ms := 0
	for index in range(SAMPLES):
		var run_seed := 700000 + index * 7919
		var started := Time.get_ticks_msec()
		var generated := GENERATOR._generate_constrained_floor(
			LEVEL, 0, run_seed, normalized, policy, templates
		)
		var errors := ([] as Array)
		if not generated.is_empty():
			errors = VALIDATOR.validate_normalized(LEVEL, 0, generated, policy, templates)
		var elapsed := Time.get_ticks_msec() - started
		worst_ms = maxi(worst_ms, elapsed)
		if generated.is_empty() or not errors.is_empty():
			if generated.is_empty():
				fallback += 1
			else:
				invalid += 1
				if error_samples.size() < 3:
					error_samples.append(str(errors))
			continue
		ok += 1
		var rooms := generated.get("rooms", []) as Array
		var min_x := INF
		var min_y := INF
		var max_x := -INF
		var max_y := -INF
		var doors_total := 0
		for value in rooms:
			var room := value as Dictionary
			var center := room["center"] as Vector2
			var size := room["size"] as Vector2
			min_x = minf(min_x, center.x - size.x * 0.5)
			min_y = minf(min_y, center.y - size.y * 0.5)
			max_x = maxf(max_x, center.x + size.x * 0.5)
			max_y = maxf(max_y, center.y + size.y * 0.5)
			var template_id := str(room.get("template_id", ""))
			template_counts[template_id] = int(template_counts.get(template_id, 0)) + 1
			var doors := (room.get("derived_ports", []) as Array).size()
			doors_total += doors
			if str(room.get("role", "")) != "branch":
				door_counts[doors] = int(door_counts.get(doors, 0)) + 1
		var shape := "%dx%d" % [int(max_x - min_x), int(max_y - min_y)]
		shapes[shape] = int(shapes.get(shape, 0)) + 1
	var total_ms := Time.get_ticks_msec() - t0

	print("\n=== 端到端统计（%d 个种子，含生成 + 校验）===" % SAMPLES)
	print("成功=%d  回退=%d  校验不通过=%d" % [ok, fallback, invalid])
	print("总耗时=%d ms  平均=%.1f ms  最慢单次=%d ms" % [total_ms, float(total_ms) / SAMPLES, worst_ms])
	for sample in error_samples:
		print("  err: %s" % sample)

	print("\n=== 主路房（不含支线）门数分布 ===")
	for key in door_counts.keys():
		print("  门=%s → %d 间" % [str(key), int(door_counts[key])])

	print("\n=== 房型使用分布（%d 个种子累计）===")
	for key in template_counts.keys():
		print("  %5d x  %s" % [int(template_counts[key]), str(key)])

	print("\n=== 包围盒尺寸分布（前 10）===")
	var size_keys := shapes.keys()
	size_keys.sort_custom(func(a, b): return int(shapes[a]) > int(shapes[b]))
	for index in range(mini(10, size_keys.size())):
		print("  %4d x  %s" % [int(shapes[size_keys[index]]), str(size_keys[index])])

	print("\nPROBE_DONE")
	get_tree().quit(0)
