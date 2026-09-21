extends Node
## 探针：实测「塔楼可玩深度收缩」是否**连锁生效** —— 以关闭 97F 及以下（只留 98F）为例。
##
## 起因（2026-09-21）：主人要求「把 97F 及以下的关卡先关闭」。
## 判据不是「门锁了」，而是**下行门压根不存在**：被排除的层不生成 plan ⇒
## `_commit_floor_bundle()` 里 `next_plan` 为空 ⇒ `_append_next_arrival_shell()`
## 整个跳过 ⇒ `exit → 下层` 那条 `"vertical"` 边不声明。
##
## **反向对照**（防止「探针压根看不见 vertical 边」的假绿）：`facility → floor_01_entry`
## 那条 99F→98F 的 vertical 边**必须仍在**。没有这条对照，本探针全绿不代表什么。
##
## **哨兵**：`_floor_plan_snapshots` 必须非空 —— 否则整组断言会在一份空数据上通过。
##
## 用法：
##   Godot --headless --path <项目> res://tests/verification/probe_tower_deepest_floor_cutoff.tscn

const EXPECTED_PLANNED: Array[int] = [2]
const FIRST_CUT_FLOOR_INDEX := 3

var _checks := 0
var _failures := 0


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		print("PROBE_FAIL: TowerDescent3D.tscn 加载失败")
		get_tree().quit(1)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990321
	add_child(tower)
	await _settle()

	_dump_planned(tower)
	_dump_stages(tower)
	_dump_declared_vertical_edges(tower)
	_dump_cut_floor_bundle_gate(tower)
	_dump_extraction(tower)
	_dump_elevator(tower)

	print("\n=== 结果：%d 项断言，%d 项失败 ===" % [_checks, _failures])
	if _failures == 0:
		print("PROBE_CUTOFF_OK")
	else:
		print("PROBE_CUTOFF_FAIL")
	print("PROBE_DONE")
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	var suffix := "" if detail.is_empty() else (" · " + detail)
	if ok:
		print("  [OK]   %s%s" % [label, suffix])
	else:
		_failures += 1
		print("  [FAIL] %s%s" % [label, suffix])


## —— A. 规划范围 ——
func _dump_planned(tower: Node) -> void:
	print("\n=== A. 规划范围 ===")
	var snapshot: Dictionary = tower.call("get_tower_snapshot")
	var planned: Array = snapshot.get("planned_floor_indices", [])
	var plans: Dictionary = snapshot.get("floor_plan_snapshots", {})
	var planned_sorted: Array = planned.duplicate()
	planned_sorted.sort()
	print("  planned_floor_indices = %s" % str(planned_sorted))
	print("  floor_plan_snapshots keys = %s" % str(plans.keys()))

	_check("哨兵：规划快照非空", not plans.is_empty(), "size=%d" % plans.size())
	_check(
		"规划层集合 = [2]（只有 98F）",
		planned_sorted == EXPECTED_PLANNED,
		str(planned_sorted)
	)
	var cut_planned: Array = []
	for value in plans.keys():
		if int(value) >= FIRST_CUT_FLOOR_INDEX:
			cut_planned.append(int(value))
	_check(
		"被砍层（floor_index >= %d）没有任何 plan" % FIRST_CUT_FLOOR_INDEX,
		cut_planned.is_empty(),
		"意外存在 %s" % str(cut_planned)
	)


## —— B. 壳体 stage ——
func _dump_stages(tower: Node) -> void:
	print("\n=== B. 壳体 stage（_floor_stages）===")
	var stages: Dictionary = tower.get("_floor_stages")
	var keys: Array = stages.keys()
	keys.sort()
	print("  stage keys = %s" % str(keys))
	var leaked: Array = []
	for value in keys:
		if int(value) >= FIRST_CUT_FLOOR_INDEX:
			leaked.append(int(value))
	_check(
		"没有为被砍层建 stage",
		leaked.is_empty(),
		"意外存在 %s" % str(leaked)
	)
	_check("98F 的 stage 存在（floor_index=2）", stages.has(2), "keys=%s" % str(keys))


## —— C. 已声明边（含反向对照）——
func _dump_declared_vertical_edges(tower: Node) -> void:
	print("\n=== C. _declared_edges 里的 vertical 边 ===")
	var declared: Array = tower.get("_declared_edges")
	var room_floor: Dictionary = tower.get("_room_floor_index")
	var vertical_lines: Array = []
	var cut_touching: Array = []
	var has_facility_to_98 := false
	for value in declared:
		var declaration := value as Dictionary
		if str(declaration.get("kind", "")) != "vertical":
			continue
		var a := str(declaration.get("a", ""))
		var b := str(declaration.get("b", ""))
		var fa := int(room_floor.get(a, -1))
		var fb := int(room_floor.get(b, -1))
		vertical_lines.append("%s(pi=%d) -> %s(pi=%d) side=%s" % [
			a, fa, b, fb, str(declaration.get("side", ""))
		])
		if fa >= FIRST_CUT_FLOOR_INDEX or fb >= FIRST_CUT_FLOOR_INDEX:
			cut_touching.append("%s -> %s" % [a, b])
		if a == "facility" and b == "floor_01_entry":
			has_facility_to_98 = true
	print("  vertical 边共 %d 条：" % vertical_lines.size())
	for line in vertical_lines:
		print("    - %s" % str(line))

	_check(
		"无语义上触及被砍层的 vertical 边",
		cut_touching.is_empty(),
		"意外存在 %s" % str(cut_touching)
	)
	# 反向对照：这条边是 99F->98F，必须还在，否则说明本探针取不到 vertical 边集合
	_check(
		"反向对照：99F->98F 的 vertical 边仍在（facility -> floor_01_entry）",
		has_facility_to_98,
		"vertical 边总数=%d" % vertical_lines.size()
	)


## —— D. 下行门禁表 ——
func _dump_cut_floor_bundle_gate(tower: Node) -> void:
	print("\n=== D. 下行门禁表 ===")
	var seed_gates: Dictionary = tower.get("_floor_seed_gate_edges")
	var boss_gates: Dictionary = tower.get("_boss_descent_gate_edges")
	print("  _floor_seed_gate_edges = %s" % str(seed_gates))
	print("  _boss_descent_gate_edges = %s" % str(boss_gates))
	var leaked: Array = []
	for value in seed_gates.keys():
		var target := int(seed_gates[value])
		if target >= FIRST_CUT_FLOOR_INDEX:
			leaked.append("%s->pi%d" % [str(value), target])
	_check(
		"没有指向被砍层的层种子门",
		leaked.is_empty(),
		"意外存在 %s" % str(leaked)
	)
	_check("boss 下行门禁表为空（95/90/85F 已不在规划内）", boss_gates.is_empty())


## —— E. 撤离信标 ——
func _dump_extraction(tower: Node) -> void:
	print("\n=== E. 撤离信标 ===")
	var extraction: Variant = tower.get("_extraction")
	var conditional: Dictionary = tower.get("_conditional_extractions")
	print("  _extraction = %s" % ("null" if extraction == null else str(extraction)))
	print("  _conditional_extractions keys = %s" % str(conditional.keys()))
	# 记录事实，不做"必须为 null"的断言：98F 非 boss 层（98 %% 5 == 3），
	# 撤离信标只在 boss 房上创建 ⇒ 这里预期 null，但它是**设计后果**而非回归判据。
	print("  [NOTE] 98F 层号 98 %% 5 == 3，不是 boss 层 ⇒ 预期塔内无撤离信标；")
	print("         回基地依赖 98<->99 楼梯间那扇普通门（INITIAL_LOOP_GATE_SEAL_ENABLED=false）。")


## —— F. 电梯 ——
func _dump_elevator(tower: Node) -> void:
	print("\n=== F. 楼层电梯 ===")
	var elevators: Dictionary = tower.get("_elevator_facilities_by_floor")
	var unlocked: Dictionary = tower.get("_unlocked_elevator_floors")
	print("  _elevator_facilities_by_floor keys = %s" % str(elevators.keys()))
	print("  _unlocked_elevator_floors = %s" % str(unlocked))
	_check(
		"没有为被砍层建电梯",
		not elevators.has(95),
		"keys=%s" % str(elevators.keys())
	)


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout
