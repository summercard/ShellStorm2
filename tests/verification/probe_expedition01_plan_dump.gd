extends Node
## 临时探针：打印数据驱动路径（generate_from_level_plan）在指定种子下的真实产出。
## 本轮 Task #35 的取证工具，用完即删。

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")

const LEVEL := "expedition_01"
const SEEDS: Array[int] = [77001199, 1001, 1002, 1003, 1004]


func _ready() -> void:
	for seed_value in SEEDS:
		var plan := GENERATOR.generate_from_level_plan(LEVEL, 0, seed_value)
		print("\n=== seed=%d ===" % seed_value)
		print("valid=%s trigger=%s mode=%s fallback=%s" % [
			str(plan.get("valid", false)), str(plan.get("trigger", "")),
			str(plan.get("mode", "")), str(plan.get("used_fallback", false)),
		])
		if not bool(plan.get("valid", false)):
			print("errors=%s" % str(plan.get("validation_errors", [])))
			continue
		print("main_path_keys=%s" % str(plan.get("main_path_keys", [])))
		print("content_room_count=%d branch_count=%d branch_room_count=%d" % [
			int(plan.get("content_room_count", -1)), int(plan.get("branch_count", -1)),
			int(plan.get("branch_room_count", -1)),
		])
		var ids: Array[String] = []
		var content_types: Array[String] = []
		for value in plan.get("rooms", []):
			var room := value as Dictionary
			var role := str(room.get("role", ""))
			var dimensions := room.get("dimensions", Vector2.ZERO) as Vector2
			ids.append(str(room.get("id", "")))
			if role not in ["stair_entry", "stair_exit", "extraction", "boss", "boss_prep"]:
				content_types.append(str(room.get("type", "")))
			print("  key=%-11s id=%-11s role=%-11s type=%-9s dim=%s parent=%s" % [
				str(room.get("key", "")), str(room.get("id", "")), role,
				str(room.get("type", "")), str(dimensions), str(room.get("parent_key", "")),
			])
		print("  ids(order)=%s" % str(ids))
		var sorted_ids := ids.duplicate()
		sorted_ids.sort()
		print("  ids(sorted)=%s" % str(sorted_ids))
		var sorted_types := content_types.duplicate()
		sorted_types.sort()
		print("  content_types=%d sorted=%s" % [content_types.size(), str(sorted_types)])
	print("\nPROBE_DONE")
	get_tree().quit(0)
