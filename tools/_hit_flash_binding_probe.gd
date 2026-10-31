extends Node
## 门禁：**受击闪白材质是不是真的挂在渲染面上**。
##
## ## 为什么必须有这一条（2026-10-31 的静默失效）
##
## 闪白由表现层 `_ready()` 自己 duplicate 一份材质、逐面设 override、把副本收进
## `_materials`。而 `EnemyAvatar3D._apply_formal_tint()` 在**之后**才跑，
## 旧实现又 `duplicate()` 了一份**新的** override 盖上去 —— 表现层手里那批
## 变成没人用的孤儿，场上渲染的那份从没被闪过。
##
## 症状是「受击只有卡顿、没有任何画面反馈」，而所有既有验收都绿：
##   · `verify_strong_variant_eye_glow` 查的是**眼球**材质，不是身体；
##   · `verify_melee_zombie_presentation` 查 `visual._materials[0].emission_...`
##     ——  它查的正是那份**孤儿**，永远为真。
## ⇒ 判据必须落在「`_materials` 里的对象 id == 渲染面上 active material 的 id」上。
##    这是唯一一条能区分"写给自己看"和"写进画面"的断言。
##
## 覆盖范围：三个正式 GLB 怪种 × 每个 MeshInstance3D 的每个 surface。
## 程序化壳（无正式模型）跳过；有模型但表为空判红。
##
## 用法：godot --headless --path . --script res://tools/_hit_flash_binding_probe.gd

const PREFAB := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
## 三个有正式 GLB 的基类。远征03 的 33 只复刻怪全部借用其中之一（别名解析见
## `EnemyAvatar3D.resolve_asset_kind`），所以验这三只等于验全场。
const KINDS := ["melee_chaser", "ranged_caster", "fat_zombie03"]
## 额外各验一只实际在用的复刻怪，确认别名链路没把表现层接错。
const ALIASES := ["egt_bullet_kin", "egt_fungboar", "egt_zombie"]

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	var all: Array = []
	all.append_array(KINDS)
	all.append_array(ALIASES)
	for kind in all:
		await _check_kind(kind)
	print("FLASH_BINDING_%s checks=%d failures=%d"
		% ["OK" if _failures.is_empty() else "FAILED", _checks, _failures.size()])
	for reason in _failures:
		printerr("FLASH_BINDING_FAIL ", reason)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_kind(kind: String) -> void:
	var enemy := PREFAB.instantiate() as Enemy3D
	enemy.set("enemy_kind", kind)
	add_child(enemy)
	for _i in 4:
		await get_tree().process_frame
	var visual: Node = enemy.avatar.get("_formal_normal_root")
	if visual == null:
		print("  FLASH_BIND %-18s 无正式模型（程序化壳），跳过" % kind)
		enemy.free()
		return
	var materials: Array = visual.get("_materials")
	var baseline: Array = visual.get("_flash_baseline")
	var held := {}
	for material in materials:
		held[(material as Material).get_instance_id()] = true

	var total := 0
	var bound := 0
	for node in (visual as Node).find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			total += 1
			# 判据用 `get_active_material()`：这正是渲染器实际取用的那一份
			# （override 优先、否则回落资产材质）。查 override 专用接口会漏掉
			# "没设 override 但材质表里也只有它一份"的情形。
			var active := mesh_instance.get_active_material(surface)
			if active != null and held.has(active.get_instance_id()):
				bound += 1

	print("  FLASH_BIND %-18s surfaces=%d 材质表=%d 基线=%d 绑定=%d"
		% [kind, total, materials.size(), baseline.size(), bound])
	_check(not materials.is_empty(), "%s: 表现层没收集到任何可闪白材质" % kind)
	_check(baseline.size() == materials.size(),
		"%s: 闪白基线 %d 份与材质 %d 份不配对（漏 prepare 或重复加）" % [kind, baseline.size(), materials.size()])
	_check(bound == materials.size(),
		"%s: 只有 %d/%d 份材质真的挂在渲染面上 —— 其余是孤儿，闪白写不进画面"
		% [kind, bound, materials.size()])

	# 反向自证：翻一次闪白，确认**渲染面**的自发光能量真的被推上去。
	# 只查 `_materials[0]` 是不够的（那正是孤儿检查失效的地方），所以逐面查。
	visual.call("flash_hit")
	visual.call("_process", 0.0)
	var lit := 0
	var lit_total := 0
	for node in (visual as Node).find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var active := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if active == null:
				continue
			lit_total += 1
			if active.emission_energy_multiplier > 0.1:
				lit += 1
	_check(lit > 0, "%s: 闪白触发后没有任何渲染面亮起（共查 %d 面）" % [kind, lit_total])
	# 收尾必须回到**各自的基线**，不能一律判"不许发光"：正式模型里有本来就该常亮的件
	# （强化怪的眼球发光件），无差别判红会把它们当成 bug。
	# 所以逐条比 `_flash_baseline` 记下的 energy —— 这同时守住两件事：
	#   ① 闪白自己会收回；② 修复没把原有常亮件一起灭掉（那会是更难查的美术回归）。
	visual.call("_process", 0.5)
	var drifted := 0
	for entry in baseline:
		var record := entry as Dictionary
		var material := record.get("material") as BaseMaterial3D
		if material == null:
			drifted += 1
			continue
		if absf(material.emission_energy_multiplier - float(record.get("energy", 0.0))) > 0.01:
			drifted += 1
			printerr("  FLASH_BIND_DRIFT %s energy=%.3f base=%.3f"
				% [kind, material.emission_energy_multiplier, float(record.get("energy", 0.0))])
	_check(drifted == 0, "%s: 闪白结束后有 %d 份材质没回到基线能量" % [kind, drifted])
	enemy.free()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
