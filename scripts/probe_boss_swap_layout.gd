extends Node
## 诊断探针 2：量「80×100 的 Boss 房到底能不能挂到 room_10 北侧」。
##
## 背景：远征01 是 constrained —— 链式贴墙自避走，链的走向由种子 + 模板尺寸决定。
## 把 Boss 从 50×40 换成 80×100 并改挂北侧，等于要求链尾北面有 80×100 的空地。
## 本探针把链摆到 room_10，再单独问「Boss 槽位在这个残局里还有几个候选、都是什么」，
## 并直接测「room_10 北侧目标点」能不能放下、被谁挡住。
##
## 运行：
##   export APPDATA='C:\tmp\ss2_appdata_layout'
##   "<godot-console>" --headless --path "<project>" \
##     --scene res://scripts/probe_boss_swap_layout.tscn

const RUN_SEED := 77001199
const ROOM_IDS: Array[String] = [
	"entry", "room_01", "room_02", "room_03", "room_04", "room_05",
	"room_06", "room_07", "room_08", "room_09", "room_10",
]

var _root: Window


func _ready() -> void:
	_root = get_tree().root
	call_deferred("probe")


func probe() -> void:
	_dump()
	print("BOSS_SWAP_LAYOUT_DONE")
	get_tree().quit(0)


func _dump() -> void:
	var plan := LevelPlanLoader.load_level_plan("expedition_01")
	var policy := (plan.get("generation_policy", {}) as Dictionary).duplicate(true)
	policy["expedition_global_rotation_deg"] = 180
	var templates := LevelPlanLoader.load_room_templates("expedition_01")
	var blueprint := LevelPlanLoader.normalize_floor("expedition_01", 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = RUN_SEED ^ absi("expedition_01".hash()) ^ (0 << 17)
	var slots := FloorPlanGenerator._constrained_slots(blueprint, policy, templates, rng)
	print("=== 槽位 = %d ===" % slots.size())

	var chain: Array[Dictionary] = []
	for value in slots:
		var slot := value as Dictionary
		if str(slot.get("key", "")) in ROOM_IDS:
			chain.append(slot)
	var placed := FloorPlanGenerator._place_constrained_slots(chain, rng)
	print("链摆位成功 =", placed.size() == chain.size(),
		"（期望 %d 实得 %d）" % [chain.size(), placed.size()])
	var rects: Array[Rect2] = []
	for value in placed:
		var room := value as Dictionary
		var center := room.get("center", Vector2.ZERO) as Vector2
		var size := room.get("size", Vector2.ZERO) as Vector2
		rects.append(Rect2(center - size * 0.5, size))
		print("  %-9s center=(%8.2f,%8.2f) size=(%5.1f,%5.1f) rot=%3.0f %s" % [
			str(room.get("key", "")), center.x, center.y, size.x, size.y,
			float(room.get("rotation_deg", 0.0)), str(room.get("template_id", "")),
		])

	for value in slots:
		var slot := value as Dictionary
		if str(slot.get("key", "")) != "boss":
			continue
		print("boss 槽位 size=%s anchor=%s ports=%d" % [
			str(slot.get("size", Vector2.ZERO)), str(slot.get("anchor_policy", "")),
			(slot.get("connection_ports", []) as Array).size(),
		])
		var candidates := FloorPlanGenerator._placement_candidates(slot, placed, rng)
		print("boss 候选数 =", candidates.size())
		for candidate_value in candidates:
			var candidate := candidate_value as Dictionary
			var center := candidate.get("center", Vector2.ZERO) as Vector2
			var size := candidate.get("size", Vector2.ZERO) as Vector2
			print("  cand center=(%8.2f,%8.2f) size=(%5.1f,%5.1f) rot=%3.0f entry=%s" % [
				center.x, center.y, size.x, size.y,
				float(candidate.get("rotation_deg", 0.0)),
				str(candidate.get("entry_port_id", "")),
			])
		var room_10: Dictionary = {}
		for placed_value in placed:
			if str((placed_value as Dictionary).get("key", "")) == "room_10":
				room_10 = placed_value as Dictionary
		if room_10.is_empty():
			continue
		var c10 := room_10.get("center", Vector2.ZERO) as Vector2
		var s10 := room_10.get("size", Vector2.ZERO) as Vector2
		var want := Vector2(c10.x, c10.y - s10.y * 0.5 - 50.0)
		print("room_10 北侧目标 center=(%.2f,%.2f) 放 80x100 → fits=%s" % [
			want.x, want.y,
			str(FloorPlanGenerator._constrained_fits(want, Vector2(80.0, 100.0), rects)),
		])
		var probe_rect := Rect2(want - Vector2(40.0, 50.0), Vector2(80.0, 100.0))
		for index in range(placed.size()):
			var overlap := probe_rect.intersection(rects[index]).get_area()
			if overlap > 0.0001:
				print("  与 %s 重叠 面积=%.1f" % [
					str((placed[index] as Dictionary).get("key", "?")), overlap,
				])


func _owner_of(rect: Rect2, placed: Array[Dictionary]) -> String:
	for value in placed:
		var room := value as Dictionary
		var center := room.get("center", Vector2.ZERO) as Vector2
		var size := room.get("size", Vector2.ZERO) as Vector2
		if Rect2(center - size * 0.5, size).is_equal_approx(rect):
			return str(room.get("key", "?"))
	return "?"
