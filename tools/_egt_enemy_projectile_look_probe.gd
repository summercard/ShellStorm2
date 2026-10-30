extends Node3D

## 门禁：远征03 的**敌弹观感**（2026-10-30 业主「怪物的子弹大小也放大一倍」）。
##
## 这条链路是**跨四层**的隐形契约，任何一层断掉都不会报错，只会「改了没效果」：
##   关卡 `level_plan.json` 的 `monster_rules.projectile.visual_scale`
##     → `MonsterInjector._projectile_look_overrides()` → 怪物 config 的 `projectile_visual_scale`
##     → `Enemy3D._projectile_visual_scale` → 每发 `Projectile3D.visual_scale`
##     → 弹体视觉 `VfxBulletVisual3D` 的 `_base_scale`。
## 所以这里逐层断言，而不是只验最后一格。
##
## 同时钉住「**只放大视觉**」这条边界：判定半径必须仍是 0.12 m 基准球。
## 放大判定会顺手把远征03 变难、把 `_egt_dodgeability_probe` 的可躲性判据一起改掉。

const LEVEL_PLAN_PATH := "res://data/level_plans/expedition_03/level_plan.json"
const OTHER_LEVEL_PLAN_PATH := "res://data/level_plans/expedition_01/level_plan.json"
const EXPECTED_VISUAL_SCALE := 2.0
const EXPECTED_COLLISION_RADIUS := 0.12
const ENEMY_SCRIPT_PATH := "res://src/enemy3d/Enemy3D.gd"

var _failures: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	_check_level_data()
	await _check_wiring()
	if _failures.is_empty():
		print(
			(
				"EGT_PROJECTILE_LOOK_PROBE_OK 远征03 敌弹视觉 ×%.1f 已贯通「关卡→注入器→怪→弹」四层，"
				+ "判定半径仍 %.2f m；其余关卡保持中性档"
			) % [EXPECTED_VISUAL_SCALE, EXPECTED_COLLISION_RADIUS]
		)
	else:
		print("EGT_PROJECTILE_LOOK_PROBE_FAIL count=%d" % _failures.size())
		for item in _failures:
			print("  - ", item)
	get_tree().quit(0 if _failures.is_empty() else 1)


## ① 数据层：远征03 声明了 2.0；其它关卡不声明（= 中性）。
func _check_level_data() -> void:
	var plan := _read_json(LEVEL_PLAN_PATH)
	if plan.is_empty():
		_failures.append("%s 读不出来" % LEVEL_PLAN_PATH)
		return
	var rules: Dictionary = plan.get("monster_rules", {}) as Dictionary
	var section: Variant = rules.get("projectile", null)
	if not (section is Dictionary):
		_failures.append("远征03 的 monster_rules 缺 projectile 段：敌弹不会放大")
		return
	var declared := float((section as Dictionary).get("visual_scale", 0.0))
	if not is_equal_approx(declared, EXPECTED_VISUAL_SCALE):
		_failures.append(
			"远征03 projectile.visual_scale 是 %.2f，期望 %.2f" % [declared, EXPECTED_VISUAL_SCALE]
		)
	var other := _read_json(OTHER_LEVEL_PLAN_PATH)
	if other.is_empty():
		return
	var other_rules: Dictionary = other.get("monster_rules", {}) as Dictionary
	if (other_rules.get("projectile", {}) as Dictionary).has("visual_scale"):
		_failures.append("远征01 也声明了 projectile.visual_scale：业主只要求改远征03")


## ② 接线层：注入器 → 怪物 config → 每发 Projectile3D。
func _check_wiring() -> void:
	# MonsterInjector 是 RefCounted（不是 Node），不要 add_child —— 直接调它的纯函数。
	var injector := MonsterInjector.new()
	injector.set_level_rules((_read_json(LEVEL_PLAN_PATH).get("monster_rules", {})) as Dictionary)
	var look := injector._projectile_look_overrides()
	if not is_equal_approx(float(look.get("projectile_visual_scale", 0.0)), EXPECTED_VISUAL_SCALE):
		_failures.append(
			"MonsterInjector._projectile_look_overrides() 返回 %s，期望 projectile_visual_scale=%.1f"
			% [str(look), EXPECTED_VISUAL_SCALE]
		)
	injector.set_level_rules({})
	if not injector._projectile_look_overrides().is_empty():
		_failures.append("未配置 projectile 段的关卡不该产出覆盖键（会污染其它关卡）")

	await _fire_and_check("egt_bullet_kin", EXPECTED_VISUAL_SCALE, "远征03 档")
	await _fire_and_check("egt_bullet_kin", 1.0, "中性档")


## 让一只怪按给定档位开一枪，断言弹体的视觉倍率与判定半径。
func _fire_and_check(kind: String, visual_scale: float, label: String) -> void:
	var enemy := (load(ENEMY_SCRIPT_PATH) as GDScript).new() as Enemy3D
	enemy.enemy_kind = kind
	add_child(enemy)
	await get_tree().physics_frame
	var data := {"projectile_visual_scale": visual_scale} if not is_equal_approx(visual_scale, 1.0) else {}
	enemy.configure_from_enemy_data(data)
	var target := Node3D.new()
	add_child(target)
	target.global_position = Vector3(0, 0, -6)
	enemy._target = target
	enemy._fire_projectile(Vector3(0, 0, -1), 17, Color.WHITE, false, {}, 6.0)
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
			"%s（%s）的 Projectile3D.visual_scale 是 %.2f，期望 %.2f：关卡档没传到弹上"
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
