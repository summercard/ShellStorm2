extends Node3D

## 门禁：远征03 的**敌弹观感**。
##
## 历史：
##   2026-10-30 业主「怪物的子弹大小也放大一倍」⇒ 关卡级统一 ×2.0。
##   2026-11-02 业主「子弹模型改成大小非统一的，按体型和发射速率和伤害自行判断，
##              改成 1.3-1.8 倍，不是原来的 2 倍」⇒ 改为**逐只**倍率，关卡值降级为缺省档。
##
## 这条链路是**跨四层**的隐形契约，任何一层断掉都不会报错，只会「改了没效果」：
##   `PROFILES[kind].projectile_visual_scale`（逐只，第一优先）
##     → `Enemy3D._effective_projectile_visual_scale()`（逐只 → 关卡缺省 → 1.0）
##     → 每发 `Projectile3D.visual_scale`
##     → 弹体视觉 `VfxBulletVisual3D` 的 `_base_scale`。
## 所以这里逐层断言，而不是只验最后一格。
##
## 同时钉住两条边界：
##   ① 「**只放大视觉**」：判定半径必须仍是 0.12 m 基准球；
##   ② 「**不是统一值**」：33 只里必须出现足够多的不同倍率 —— 全部等于同一个数
##      就等于退回上一版那个被业主否掉的方案（这条断言是本轮改动的存在理由）。

const LEVEL_PLAN_PATH := "res://data/level_plans/expedition_03/level_plan.json"
const OTHER_LEVEL_PLAN_PATH := "res://data/level_plans/expedition_01/level_plan.json"
const ENEMY_SCRIPT_PATH := "res://src/enemy3d/Enemy3D.gd"

## 业主给定的区间（闭区间）。逐只值越界即失败 —— 不是"参考范围"，是裁定。
const MIN_VISUAL_SCALE := 1.30
const MAX_VISUAL_SCALE := 1.80
## 「非统一」的量化判据：33 只至少要有这么多档不同倍率。
## 实测 19 档；取 10 是留足调整余地的下限，不是目标值。
const MIN_DISTINCT_SCALES := 10
## 关卡缺省档（`monster_rules.projectile.visual_scale`）。= 逐只推导公式的基准项。
const EXPECTED_LEVEL_DEFAULT := 1.52
const EXPECTED_COLLISION_RADIUS := 0.12

## 抽样硬编码期望（不引用被测常量，否则改坏时期望跟着变、断言永远绿）。
## 选取原则：区间两端 + 三个中间档，覆盖「体型项」「密度项」各自的主导区间。
const EXPECTED_PER_KIND := {
	"egt_hollowpoint": 1.35,   # 最小体型 + 高射速 ⇒ 区间下沿
	"egt_gun_nut": 1.77,       # 最大体型 + 低频 ⇒ 区间上沿
	"egt_bullet_kin": 1.45,
	"egt_blue_shotgun": 1.50,
	"egt_mimic": 1.71,
}

var _failures: Array[String] = []
## 实测的不同倍率档数（`_check_per_kind_table` 写入，只用于 OK 行报数，不参与判定）。
var _distinct_scales := 0


func _ready() -> void:
	await get_tree().process_frame
	_check_level_data()
	_check_per_kind_table()
	await _check_wiring()
	if _failures.is_empty():
		print(
			(
				"EGT_PROJECTILE_LOOK_PROBE_OK 远征03 敌弹视觉逐只 %.2f~%.2f（%d 档不同值）已贯通"
				+ "「怪种表→解析→弹」三层，判定半径仍 %.2f m；其余关卡保持中性档"
			) % [MIN_VISUAL_SCALE, MAX_VISUAL_SCALE, _distinct_scales, EXPECTED_COLLISION_RADIUS]
		)
	else:
		print("EGT_PROJECTILE_LOOK_PROBE_FAIL count=%d" % _failures.size())
		for item in _failures:
			print("  - ", item)
	get_tree().quit(0 if _failures.is_empty() else 1)


## ① 数据层：远征03 的关卡值降级为**缺省档**（不再代表每一只）；其它关卡不声明。
func _check_level_data() -> void:
	var plan := _read_json(LEVEL_PLAN_PATH)
	if plan.is_empty():
		_failures.append("%s 读不出来" % LEVEL_PLAN_PATH)
		return
	var rules: Dictionary = plan.get("monster_rules", {}) as Dictionary
	var section: Variant = rules.get("projectile", null)
	if not (section is Dictionary):
		_failures.append("远征03 的 monster_rules 缺 projectile 段：敌弹缺省档没有落点")
		return
	var declared := float((section as Dictionary).get("visual_scale", 0.0))
	if not is_equal_approx(declared, EXPECTED_LEVEL_DEFAULT):
		_failures.append(
			"远征03 projectile.visual_scale（缺省档）是 %.2f，期望 %.2f"
			% [declared, EXPECTED_LEVEL_DEFAULT]
		)
	if declared > MAX_VISUAL_SCALE or declared < MIN_VISUAL_SCALE:
		_failures.append(
			"关卡缺省档 %.2f 落在业主给定区间 [%.2f, %.2f] 之外"
			% [declared, MIN_VISUAL_SCALE, MAX_VISUAL_SCALE]
		)
	var other := _read_json(OTHER_LEVEL_PLAN_PATH)
	if other.is_empty():
		return
	var other_rules: Dictionary = other.get("monster_rules", {}) as Dictionary
	if (other_rules.get("projectile", {}) as Dictionary).has("visual_scale"):
		_failures.append("远征01 也声明了 projectile.visual_scale：业主只要求改远征03")


## ② 怪种表：33 只全部有逐只值、全部在区间内、且**不统一**。
func _check_per_kind_table() -> void:
	var script := load(ENEMY_SCRIPT_PATH) as GDScript
	var profiles: Dictionary = script.get_script_constant_map()["PROFILES"]
	var kinds: Array[String] = []
	for key in profiles.keys():
		if str(key).begins_with("egt_"):
			kinds.append(str(key))
	kinds.sort()
	if kinds.size() != 33:
		_failures.append("egt_ 怪种应为 33 只，实测 %d 只" % kinds.size())
	var seen := {}
	for kind in kinds:
		var row: Dictionary = profiles[kind]
		if not row.has("projectile_visual_scale"):
			_failures.append("%s 没有 projectile_visual_scale：会退回关卡统一档" % kind)
			continue
		var value := float(row["projectile_visual_scale"])
		seen[value] = true
		if value < MIN_VISUAL_SCALE - 0.001 or value > MAX_VISUAL_SCALE + 0.001:
			_failures.append(
				"%s 的弹体倍率 %.2f 越界（业主给定 %.2f~%.2f）"
				% [kind, value, MIN_VISUAL_SCALE, MAX_VISUAL_SCALE]
			)
		if EXPECTED_PER_KIND.has(kind):
			var want := float(EXPECTED_PER_KIND[kind])
			if absf(value - want) > 0.011:
				_failures.append("%s 的弹体倍率是 %.2f，期望 %.2f" % [kind, value, want])
	if seen.size() < MIN_DISTINCT_SCALES:
		_failures.append(
			"逐只倍率只有 %d 档不同值（下限 %d）：这退回了「统一放大」那个被否掉的方案"
			% [seen.size(), MIN_DISTINCT_SCALES]
		)
	_distinct_scales = seen.size()
	print("  逐只倍率档数：%d，覆盖 %d 只" % [seen.size(), kinds.size()])


## ③ 接线层：逐只档优先于关卡缺省档；缺逐只档时回落关卡档；都缺则 1.0。
func _check_wiring() -> void:
	# MonsterInjector 是 RefCounted（不是 Node），不要 add_child —— 直接调它的纯函数。
	var injector := MonsterInjector.new()
	injector.set_level_rules((_read_json(LEVEL_PLAN_PATH).get("monster_rules", {})) as Dictionary)
	var look := injector._projectile_look_overrides()
	if not is_equal_approx(float(look.get("projectile_visual_scale", 0.0)), EXPECTED_LEVEL_DEFAULT):
		_failures.append(
			"MonsterInjector._projectile_look_overrides() 返回 %s，期望缺省档 %.2f"
			% [str(look), EXPECTED_LEVEL_DEFAULT]
		)
	injector.set_level_rules({})
	if not injector._projectile_look_overrides().is_empty():
		_failures.append("未配置 projectile 段的关卡不该产出覆盖键（会污染其它关卡）")

	# 逐只档必须压过关卡档：用同一只怪跑「有关卡档 / 无关卡档」两种配置，结果必须一致。
	var per_kind := float(EXPECTED_PER_KIND["egt_bullet_kin"])
	await _fire_and_check("egt_bullet_kin", per_kind, "无关卡档（逐只值生效）", {})
	await _fire_and_check(
		"egt_bullet_kin", per_kind, "关卡档 2.0（逐只值仍须胜出）",
		{"projectile_visual_scale": 2.0}
	)
	# 真正的「没有逐只值」的怪：远端那只老远程怪，只能吃关卡缺省档。
	await _fire_and_check(
		"ranged_caster", EXPECTED_LEVEL_DEFAULT, "无逐只值（回落关卡档）",
		{"projectile_visual_scale": EXPECTED_LEVEL_DEFAULT}
	)
	await _fire_and_check("ranged_caster", 1.0, "全无配置（中性档）", {})


## 让一只怪按给定配置开一枪，断言弹体的视觉倍率与判定半径。
func _fire_and_check(kind: String, visual_scale: float, label: String, data: Dictionary) -> void:
	var enemy := (load(ENEMY_SCRIPT_PATH) as GDScript).new() as Enemy3D
	enemy.enemy_kind = kind
	add_child(enemy)
	await get_tree().physics_frame
	enemy.configure_from_enemy_data(data)
	var target := Node3D.new()
	add_child(target)
	target.global_position = Vector3(0, 0, -6)
	enemy._target = target
	enemy._fire_projectile(Vector3(0, 0, -1), 17, Color.WHITE, false, {}, 5.0)
	await get_tree().physics_frame

	var mine: Array[Projectile3D] = []
	for node in _collect_projectiles(self):
		var proj := node as Projectile3D
		if proj != null and proj.shooter == enemy:
			mine.append(proj)
	if mine.is_empty():
		_failures.append("%s（%s）没有打出子弹，接线无法验证" % [kind, label])
		return
	var proj := mine[0]
	if not is_equal_approx(float(proj.visual_scale), visual_scale):
		_failures.append(
			"%s（%s）的 Projectile3D.visual_scale 是 %.2f，期望 %.2f：倍率没传到弹上"
			% [kind, label, float(proj.visual_scale), visual_scale]
		)
	var snap: Dictionary = proj.get_orientation_snapshot()
	var base_scale := float(snap.get("visual_base_scale", 0.0))
	if absf(base_scale - visual_scale) > 0.01:
		_failures.append(
			"%s（%s）弹体视觉倍率是 %.2f，期望 %.2f：视觉没跟着走" % [kind, label, base_scale, visual_scale]
		)
	var radius := float(snap.get("collision_radius", -1.0))
	if absf(radius - EXPECTED_COLLISION_RADIUS) > 0.0001:
		_failures.append(
			"%s（%s）的判定半径变成 %.3f，期望恒为 %.2f：观感倍率不许改判定"
			% [kind, label, radius, EXPECTED_COLLISION_RADIUS]
		)
	proj.free()
	enemy.queue_free()
	target.queue_free()
	await get_tree().process_frame


func _collect_projectiles(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		if child is Projectile3D:
			out.append(child)
		out.append_array(_collect_projectiles(child))
	return out


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}
