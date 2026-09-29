extends SceneTree
## 临时探针：同一 level plan 下不同 run_seed 是否产出不同几何。

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const FPG := preload("res://src/map/FloorPlanGenerator.gd")
const LOADER := preload("res://src/map/LevelPlanLoader.gd")

const LEVEL := "expedition_01"
const SEEDS := [1, 2, 3, 12345, 999999]


func _sig(plan: Dictionary) -> String:
	var lines: Array[String] = []
	for value in plan.get("rooms", []):
		var room := value as Dictionary
		var pos := room.get("position", Vector2.ZERO) as Vector2
		var dim := room.get("dimensions", Vector2.ZERO) as Vector2
		lines.append("%s|%.1f,%.1f|%.1fx%.1f|rot=%.0f" % [
			str(room.get("key", "")), pos.x, pos.y, dim.x, dim.y,
			float(room.get("rotation_deg", 0.0)),
		])
	return "\n".join(lines)


func _initialize() -> void:
	var level_plan := LOADER.load_level_plan(LEVEL)
	var policy := level_plan.get("generation_policy", {}) as Dictionary
	var templates := LOADER.load_room_templates(LEVEL)
	var normalized := LOADER.normalize_floor(LEVEL, 0)
	print("pin_content_templates=%s  authored_layout_shell=%s" % [
		str(policy.get("pin_content_templates", false)),
		str(policy.get("authored_layout_shell", false)),
	])
	var sigs := {}
	for seed_value in SEEDS:
		# 同时打印「约束生成」直接结果（带 template_id）
		var raw := FPG._generate_constrained_floor(LEVEL, 0, int(seed_value), normalized, policy, templates)
		var tmpl_line: Array[String] = []
		for value in raw.get("rooms", []):
			var r := value as Dictionary
			var dim := r.get("size", Vector2.ZERO) as Vector2
			tmpl_line.append("%s:%s(%dx%d)" % [str(r.get("key", "")), str(r.get("template_id", "")), int(dim.x), int(dim.y)])
		var plan: Dictionary = GENERATOR.generate_from_level_plan(LEVEL, 0, int(seed_value))
		sigs[int(seed_value)] = _sig(plan)
		print("\nseed=%d layout_id=%s" % [int(seed_value), str(plan.get("layout_id", ""))])
		print("  房型序列: %s" % ", ".join(tmpl_line))
		if int(seed_value) == int(SEEDS[0]):
			print("  --- 几何明细（seed=%d）---" % int(seed_value))
			for line in _sig(plan).split("\n"):
				print("    %s" % line)
	var first: String = str(sigs[int(SEEDS[0])])
	for key in sigs.keys():
		print("seed=%d 几何与 seed=%d 相同? %s" % [int(key), int(SEEDS[0]), str(str(sigs[key]) == first)])
	print("PROBE_DONE")
	quit(0)
