extends Node
## 楼层纯数据性质验收：1000个局种子 × 98—95层，不依赖渲染和场景实例化。

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const SEED_COUNT := 1000


func _ready() -> void:
	var failures: Array[String] = []
	var layout_ids: Dictionary = {}
	var layout_variants: Dictionary = {}
	var checked_plan_count := 0
	for run_seed in range(1, SEED_COUNT + 1):
		for sequence_index in range(1, 5):
			var floor_number := 99 - sequence_index
			var entry_side := "east" if sequence_index % 2 == 1 else "west"
			var request := {
				"run_seed": run_seed,
				"floor_number": floor_number,
				"floor_index": sequence_index + 1,
				"sequence_index": sequence_index,
				"entry_side": entry_side,
				"boss_floor": floor_number % 5 == 0,
			}
			var plan := GENERATOR.generate(request)
			checked_plan_count += 1
			if not bool(plan.get("valid", false)):
				failures.append("seed=%d floor=%d invalid: %s" % [
					run_seed,
					floor_number,
					str(plan.get("validation_errors", [])),
				])
				break
			if (GENERATOR.validate(plan) as Array[String]).size() > 0:
				failures.append("seed=%d floor=%d second validation failed" % [run_seed, floor_number])
				break
			if int(plan.get("main_path_content_count", 0)) < 10:
				failures.append("seed=%d floor=%d main path is shorter than 10" % [run_seed, floor_number])
				break
			if int(plan.get("branch_count", 0)) < 2:
				failures.append("seed=%d floor=%d has too few branches" % [run_seed, floor_number])
				break
			if bool(plan.get("boss_floor", false)) != (floor_number % 5 == 0):
				failures.append("seed=%d floor=%d boss cadence mismatch" % [run_seed, floor_number])
				break
			var area := plan.get("area_budget", {}) as Dictionary
			if (
				not bool(plan.get("boss_floor", false))
				and int(plan.get("content_room_count", 0))
					!= int(area.get("calculated_content_room_target", -1))
			):
				failures.append("seed=%d floor=%d room count did not follow area budget" % [run_seed, floor_number])
				break
			if float(area.get("estimated_used_area_m2", INF)) > float(area.get("target_usable_area_m2", 0.0)):
				failures.append("seed=%d floor=%d area budget exceeded" % [run_seed, floor_number])
				break
			if run_seed <= 25:
				layout_ids[str(plan.get("layout_id", ""))] = true
				if not bool(plan.get("boss_floor", false)):
					layout_variants[str(plan.get("layout_variant", ""))] = true
			var repeated := GENERATOR.generate(request)
			if str(repeated.get("layout_id", "")) != str(plan.get("layout_id", "")) or _signature(repeated) != _signature(plan):
				failures.append("seed=%d floor=%d is not deterministic" % [run_seed, floor_number])
				break
		if not failures.is_empty():
			break
	if layout_ids.size() < 50:
		failures.append("前25个种子没有产生足够的可追踪布局ID差异")
	if layout_variants.size() < 2:
		failures.append("前25个种子没有同时覆盖南/北空间排列变体")
	if failures.is_empty():
		print("FLOOR_PLAN_GENERATOR_OK seeds=%d plans=%d layout_ids=%d" % [
			SEED_COUNT,
			checked_plan_count,
			layout_ids.size(),
		])
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)


func _signature(plan: Dictionary) -> String:
	var parts: Array[String] = []
	for room_value in plan.get("rooms", []):
		var room := room_value as Dictionary
		parts.append("%s:%s:%s:%s:%s" % [
			room.get("id", ""),
			room.get("type", ""),
			room.get("parent_key", ""),
			room.get("position", Vector2.ZERO),
			room.get("dimensions", Vector2.ZERO),
		])
	return "|".join(parts)
