extends Node
## 八个弹种专属弹体视觉（VFX-BULLET-<TYPE>-3D）专项验收（2026-10-13）。
##
## 背景：特效账本新增「子弹特效」大类，登记 8 条弹种专属弹体特效排产入口；
##       本轮按内容库《武器》S11–S18 逐条落地独立 Prefab，并接上 Projectile3D 的 visual_id 路由。
##
## 覆盖：Prefab 可加载 + AssetID/版本 meta、灯光真相（名 / 无阴影 / 范围 / 出生能量 /
##       回收归零 / 复借复亮）、八弹种视觉彼此可区分（含设计原文的可测特征）、
##       尾迹落在弹体身后、纯视觉不得含碰撞体、visual_id 路由（登记 / 未登记回落 / 换种）、
##       端到端接线（真装配真开火）、effect_size 线性缩放、防假绿哨兵。
## 只构建 mesh/material，不读 viewport 纹理 ⇒ 可安全 headless 运行。
## 判据：`BULLET_VFX_PROFILES_OK` 行 + ERROR 计数（不看裸退出码）。

const STANDARD_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_bullet_standard_root_top3d.tscn")
const STICKY_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_bullet_sticky_root_top3d.tscn")
const BOUNCE_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_bullet_bounce_root_top3d.tscn")
const PIERCING_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_bullet_piercing_root_top3d.tscn")
const EXPLOSIVE_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_bullet_explosive_root_top3d.tscn")
const HOMING_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_bullet_homing_root_top3d.tscn")
const BLACKHOLE_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_bullet_blackhole_root_top3d.tscn")
const BALLOON_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_bullet_balloon_root_top3d.tscn")
const SHARED_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_bullet_visual_root_top3d.tscn")
const WEAPON_MODEL_SCENE: PackedScene = preload("res://assets/art/weapons/weapon_3d/wpn_gun_kit_root_top3d_v001.tscn")

const SHARED_ASSET_ID := "VFX-BULLET-VISUAL-3D"
const EXPECTED_VERSION := "v001"
const UNKNOWN_BULLET_ID := "mod_bullet_not_a_real_thing"

## 八个弹种（外部真源 = 特效账本《资产主表》r27–r34 的 visual_id/asset_id + 内容库《武器》S 列）。
const PROFILES := [
	{"visual_id": "mod_bullet_standard", "asset_id": "VFX-BULLET-STANDARD-3D", "key": "standard", "scene": STANDARD_SCENE},
	{"visual_id": "mod_bullet_sticky", "asset_id": "VFX-BULLET-STICKY-3D", "key": "sticky", "scene": STICKY_SCENE},
	{"visual_id": "mod_bullet_bounce", "asset_id": "VFX-BULLET-BOUNCE-3D", "key": "bounce", "scene": BOUNCE_SCENE},
	{"visual_id": "mod_bullet_piercing", "asset_id": "VFX-BULLET-PIERCING-3D", "key": "piercing", "scene": PIERCING_SCENE},
	{"visual_id": "mod_bullet_explosive", "asset_id": "VFX-BULLET-EXPLOSIVE-3D", "key": "explosive", "scene": EXPLOSIVE_SCENE},
	{"visual_id": "mod_bullet_homing", "asset_id": "VFX-BULLET-HOMING-3D", "key": "homing", "scene": HOMING_SCENE},
	{"visual_id": "mod_bullet_blackhole", "asset_id": "VFX-BULLET-BLACKHOLE-3D", "key": "blackhole", "scene": BLACKHOLE_SCENE},
	{"visual_id": "mod_bullet_balloon", "asset_id": "VFX-BULLET-BALLOON-3D", "key": "balloon", "scene": BALLOON_SCENE},
]

## 八弹种尾迹段数（外部真源：各子类 profile 的构图声明；硬编码于此以防被顺手改坏）。
## standard / balloon = 单锥；piercing = 2 段针形；bounce / homing / blackhole = 3 段；
## sticky = 1 锥 + 3 滴珠 = 4；explosive = 1 锥 + 3 火星 = 4。
const EXPECTED_TRAIL_PARTS := {
	"standard": 1,
	"sticky": 4,
	"bounce": 3,
	"piercing": 2,
	"explosive": 4,
	"homing": 3,
	"blackhole": 3,
	"balloon": 1,
}

## 防假绿哨兵：用例样本数下限（8 Prefab + 8 profile 特征行 + 8 路由 + 8 尺寸 + 端到端
##                  + 枪身差异化 + 面数预算）。
const EXPECTED_MIN_SAMPLES := 65

## 单弹三角面预算（业主 2026-10-14 口述：「减面，减到 100 个面以下先」）。
## 上限 = 业主给定的外部需求；逐弹种实测值**硬编码**在此（值取自探针
## `_scratch/probe_bullet_mesh_stats`），不引用被测代码的任何常量 —— 否则改坏分段参数时
## 期望跟着变、断言永远绿（skill §6.9 的自印证反例）。
const EXPECTED_MAX_TRIS_PER_BULLET := 100
const EXPECTED_TRIS := {
	"shared": 44,
	"standard": 44,
	"sticky": 80,
	"bounce": 68,
	"piercing": 56,
	"explosive": 80,
	"homing": 68,
	"blackhole": 68,
	"balloon": 44,
}

## 枪身弹体几何档位的期望值（2026-10-14 业主：「每把枪的子弹大小要做出区分」）。
## 外部真源 = WeaponModel3D.BULLET_GEOMETRY_BY_GUN_TAG；此处**硬编码**期望值，
## 不引用被测常量 —— 否则常量改坏时期望跟着变，断言永远绿（同 skill §6.9 的自印证反例）。
## 语义：scale = 各向同性尺寸倍率；axial = 沿飞行轴拉长倍率；
##       grow_from / grow_duration = 出生尺寸比例与长满所需秒数。
## 三条诉求：霰弹枪由小变大且整体 ×2（scale 2.00 / grow_from 0.42 / 0.30s）、
##           榴弹枪更大（scale 1.55）、狙击枪更长（axial 2.0 且横向收到 0.95），其余枪一律中性。
## 弹体视觉基准尺寸以 `WeaponModel3D.BULLET_GEOMETRY_NEUTRAL` 的 1.00 为标尺。
##
## ⚠ 2026-10-30 起**手枪不再等于中性档**：业主「子弹出去那个特效大小，就那个模型帮我放大一倍」
## ⇒ `pistol` 档 = 2.00。下面所有「相对判据」因此改为与中性 1.00 比，而不是与手枪比
## —— 拿手枪当分母会让霰弹/榴弹/狙击三条判据一起失去意义（手枪变 2 倍后，榴弹 1.55 反而"更小"）。
const NEUTRAL_SCALE := 1.00
const EXPECTED_GUN_GEOMETRY := {
	"bp_shotgun": {"scale": 2.00, "axial": 1.0, "grow_from": 0.42, "grow_duration": 0.30},
	"bp_launcher": {"scale": 1.55, "axial": 1.0, "grow_from": 1.00, "grow_duration": 0.00},
	"bp_sniper": {"scale": 0.95, "axial": 2.0, "grow_from": 1.00, "grow_duration": 0.00},
	"bp_pistol": {"scale": 2.00, "axial": 1.0, "grow_from": 1.00, "grow_duration": 0.00},
	"bp_rifle": {"scale": 1.00, "axial": 1.0, "grow_from": 1.00, "grow_duration": 0.00},
	"bp_machinegun": {"scale": 1.00, "axial": 1.0, "grow_from": 1.00, "grow_duration": 0.00},
	"bp_starter_rifle": {"scale": 1.00, "axial": 1.0, "grow_from": 1.00, "grow_duration": 0.00},
	"bp_sprinkler": {"scale": 1.00, "axial": 1.0, "grow_from": 1.00, "grow_duration": 0.00},
	"bp_charge": {"scale": 1.00, "axial": 1.0, "grow_from": 1.00, "grow_duration": 0.00},
}

var _failures: Array[String] = []
var _samples := 0


func _ready() -> void:
	_check_prefabs()
	_check_profile_features()
	_check_visual_id_routing()
	_check_size_linear()
	_check_end_to_end()
	_check_gun_size_differentiation()
	_check_shotgun_growth_envelope()
	_check_face_budget()
	_check_collision_free()
	_purge_transients()
	_expect(_samples >= EXPECTED_MIN_SAMPLES,
		"防假绿哨兵：样本数 %d 少于下限 %d" % [_samples, EXPECTED_MIN_SAMPLES])
	_report()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _count_collision_nodes(node: Node) -> int:
	var total := 0
	if node is CollisionObject3D or node is CollisionShape3D:
		total += 1
	for child in node.get_children():
		total += _count_collision_nodes(child)
	return total


func _instantiate(packed: PackedScene) -> VfxEffectBase3D:
	return packed.instantiate() as VfxEffectBase3D


## ① Prefab 可加载 + AssetID/版本 meta + 灯光真相 + 尾迹在身后 + 回收归零 + 复借复亮。
func _check_prefabs() -> void:
	for entry in PROFILES:
		var label := String(entry["key"])
		var packed: PackedScene = entry["scene"]
		var effect := _instantiate(packed)
		if effect == null:
			_failures.append("弹种 %s：Prefab 根节点不是 VfxEffectBase3D" % label)
			continue
		if not (effect is VfxBulletBody3D):
			_failures.append("弹种 %s：根节点未继承 VfxBulletBody3D" % label)
		add_child(effect)
		effect.activate(Vector3.ZERO, Color(1.0, 0.5, 0.2), 1.0, {})
		_samples += 1

		var snap: Dictionary = effect.call("get_presentation_snapshot")
		_expect(String(snap.get("asset_id", "")) == String(entry["asset_id"]),
			"弹种 %s：AssetID 不正确：%s" % [label, snap.get("asset_id", "")])
		_expect(String(snap.get("asset_version", "")) == EXPECTED_VERSION,
			"弹种 %s：版本不是 %s：%s" % [label, EXPECTED_VERSION, snap.get("asset_version", "")])
		_expect(String(snap.get("bullet_profile", "")) == label,
			"弹种 %s：profile 键不匹配：%s" % [label, snap.get("bullet_profile", "")])
		_expect(String(snap.get("light_name", "")) == "ProjectileLight",
			"弹种 %s：灯节点名不是 ProjectileLight：%s" % [label, snap.get("light_name", "")])
		_expect(not bool(snap.get("light_shadows", true)), "弹种 %s：灯不应投射阴影" % label)
		var light_energy := float(snap.get("light_energy", 0.0))
		_expect(light_energy > 0.0, "弹种 %s：激活后灯能量应为正：%.2f" % [label, light_energy])
		var light_range := float(snap.get("light_range", 0.0))
		_expect(light_range > 1.0 and light_range < 3.0, "弹种 %s：灯范围应在 1~3m：%.2f" % [label, light_range])
		_expect(bool(snap.get("trail_is_behind", false)),
			"弹种 %s：尾迹未落在弹体身后：%.3f" % [label, float(snap.get("trail_local_z", 0.0))])
		_expect(int(snap.get("trail_parts", 0)) >= 1, "弹种 %s：尾迹段数为 0" % label)

		# 回收必须把灯能量归零且不可见（否则池化复借会留下长明灯）。
		effect.call("deactivate")
		var off: Dictionary = effect.call("get_presentation_snapshot")
		_expect(is_zero_approx(float(off.get("light_energy", 1.0))),
			"弹种 %s：回收后灯能量必须归零：%.3f" % [label, float(off.get("light_energy", 1.0))])
		_expect(not bool(off.get("light_visible", true)), "弹种 %s：回收后灯必须不可见" % label)
		# 复借必须重新点亮。
		effect.activate(Vector3.ZERO, Color(0.3, 0.9, 1.0), 1.0, {})
		var on: Dictionary = effect.call("get_presentation_snapshot")
		_expect(float(on.get("light_energy", 0.0)) > 0.0, "弹种 %s：复借后灯未重新点亮" % label)
		_expect(bool(on.get("light_visible", false)), "弹种 %s：复借后灯未重新可见" % label)
		effect.free()


## ② 八弹种视觉必须彼此可区分，并各自满足设计原文的可测特征（外部真源硬编码）。
func _check_profile_features() -> void:
	var snaps := {}
	for entry in PROFILES:
		var effect := _instantiate(entry["scene"])
		if effect == null:
			continue
		add_child(effect)
		effect.activate(Vector3.ZERO, Color.WHITE, 1.0, {})
		snaps[String(entry["key"])] = effect.call("get_presentation_snapshot")
		_samples += 1
		effect.free()

	var std_snap: Dictionary = snaps.get("standard", {})
	var std_core := float(std_snap.get("core_radius", -1.0))
	var std_light := float(std_snap.get("light_range", -1.0))
	_expect(std_core > 0.0 and std_light > 0.0, "standard 基准快照缺失，无法做相对判据")

	for key in EXPECTED_TRAIL_PARTS.keys():
		var snap: Dictionary = snaps.get(key, {})
		var got := int(snap.get("trail_parts", -1))
		_expect(got == int(EXPECTED_TRAIL_PARTS[key]),
			"弹种 %s：尾迹段数应为 %d，实测 %d" % [key, int(EXPECTED_TRAIL_PARTS[key]), got])

	# —— 各弹种设计原文的可测特征（S 列逐条映射，期望值硬编码）——
	# 穿甲（S16「连续贯穿线」）：弹芯比基准更细、尾迹更长。
	_expect(float(snaps.get("piercing", {}).get("core_radius", 9.0)) < std_core,
		"piercing 弹芯（%.4f）应细于 standard 基准（%.4f）" % [
			float(snaps.get("piercing", {}).get("core_radius", 0.0)), std_core])
	# 气球（S11「膨胀弹体」）：弹芯比基准更大，且是球形。
	_expect(float(snaps.get("balloon", {}).get("core_radius", 0.0)) > std_core,
		"balloon 弹芯（%.4f）应大于 standard 基准（%.4f）" % [
			float(snaps.get("balloon", {}).get("core_radius", 0.0)), std_core])
	_expect(String(snaps.get("balloon", {}).get("core_shape", "")) == "sphere",
		"balloon 弹体应为球形（膨胀感）：%s" % snaps.get("balloon", {}).get("core_shape", ""))
	# 黑洞（S12「黑洞核心」）：球形暗核。
	_expect(String(snaps.get("blackhole", {}).get("core_shape", "")) == "sphere",
		"blackhole 弹体应为球形暗核：%s" % snaps.get("blackhole", {}).get("core_shape", ""))
	# 爆炸（S14「爆炸半径与伤害时点同步」）：灯范围大于基准（体积感更强）。
	_expect(float(snaps.get("explosive", {}).get("light_range", 0.0)) > std_light,
		"explosive 灯范围（%.2f）应大于 standard 基准（%.2f）" % [
			float(snaps.get("explosive", {}).get("light_range", 0.0)), std_light])
	# 八条 profile 键必须两两不同（防止复制粘贴成同一弹种）。
	var keys := {}
	for entry in PROFILES:
		keys[String(entry["key"])] = true
	_expect(keys.size() == PROFILES.size(), "八弹种 profile 键存在重复")
	var shapes := {}
	for entry in PROFILES:
		var snap: Dictionary = snaps.get(String(entry["key"]), {})
		shapes["%s|%d|%.4f" % [
			String(snap.get("trail_style", "")),
			int(snap.get("trail_parts", 0)),
			float(snap.get("core_radius", 0.0)),
		]] = true
	_expect(shapes.size() >= 6, "八弹种视觉区分度不足，仅 %d 种形态" % shapes.size())


## ③ visual_id 路由：登记弹种命中对应 Prefab；未登记 / 缺省一律回落通用弹体。
func _check_visual_id_routing() -> void:
	var probe := Projectile3D.new()
	if probe == null:
		# 编译/实例化失败会让后续断言被运行时错误短路而假绿，这里必须显式记红。
		_failures.append("路由检查：Projectile3D 无法实例化（脚本编译失败？）")
		return
	add_child(probe)
	for entry in PROFILES:
		probe.configure({"visual_id": String(entry["visual_id"])})
		var snap: Dictionary = probe.get_orientation_snapshot()
		_expect(String(snap.get("visual_asset_id", "")) == String(entry["asset_id"]),
			"路由 %s：期望 %s，实测 %s" % [
				entry["visual_id"], entry["asset_id"], snap.get("visual_asset_id", "")])
		_samples += 1
	probe.configure({"visual_id": UNKNOWN_BULLET_ID})
	var unknown_snap: Dictionary = probe.get_orientation_snapshot()
	_expect(String(unknown_snap.get("visual_asset_id", "")) == SHARED_ASSET_ID,
		"未登记 visual_id 应回落通用弹体，实测 %s" % unknown_snap.get("visual_asset_id", ""))
	probe.configure({})
	var default_snap: Dictionary = probe.get_orientation_snapshot()
	_expect(String(default_snap.get("visual_asset_id", "")) == SHARED_ASSET_ID,
		"缺省 visual_id 应回落通用弹体，实测 %s" % default_snap.get("visual_asset_id", ""))
	probe.free()


## ④ effect_size 线性：size 1.0 与 0.8 的同一主体 scale 比值 ≈ 1.25（容差放宽以容纳脉动包络）。
func _check_size_linear() -> void:
	for entry in PROFILES:
		var label := String(entry["key"])
		var effect := _instantiate(entry["scene"])
		if effect == null:
			continue
		add_child(effect)
		effect.activate(Vector3.ZERO, Color.WHITE, 1.0, {})
		var big := float(effect.call("get_presentation_snapshot").get("body_scale", 0.0))
		effect.activate(Vector3.ZERO, Color.WHITE, 0.8, {})
		var small := float(effect.call("get_presentation_snapshot").get("body_scale", 0.0))
		_samples += 1
		if small <= 0.0:
			_failures.append("弹种 %s：body_scale 非法：%.4f" % [label, small])
		else:
			var ratio := big / small
			_expect(absf(ratio - 1.25) < 0.07,
				"弹种 %s：尺寸线性失效，1.0/0.8 比值 %.4f（期望 ≈1.25）" % [label, ratio])
		effect.free()


## ⑤ 端到端接线：真装配 + 真开火，池里/树上那颗投射物的弹体视觉必须是该弹种。
func _check_end_to_end() -> void:
	for entry in PROFILES:
		var label := String(entry["key"])
		var bullet_id := String(entry["visual_id"])
		var weapon := WEAPON_MODEL_SCENE.instantiate() as WeaponModel3D
		if weapon == null:
			_failures.append("端到端 %s：武器模型场景根节点不是 WeaponModel3D" % label)
			continue
		add_child(weapon)
		var tree := BlueprintRegistry.build_weapon_tree("bp_pistol", bullet_id)
		weapon.configure_from_tree(tree)
		weapon.global_position = Vector3(3.0, 1.0, 5.0)
		var spawned: Array = []
		weapon.projectile_spawned.connect(func(projectile: Projectile3D) -> void: spawned.append(projectile))
		weapon.call("_fire_now", Vector3(0.0, 0.0, -1.0), weapon, 1.0)
		_samples += 1
		if spawned.is_empty():
			_failures.append("端到端 %s：开火后没有生成投射物（装配或弹药前置条件未满足）" % label)
		for projectile in spawned:
			var snap: Dictionary = (projectile as Projectile3D).get_orientation_snapshot()
			_expect(String(snap.get("visual_asset_id", "")) == String(entry["asset_id"]),
				"端到端 %s：投射物弹体视觉期望 %s，实测 %s" % [
					label, entry["asset_id"], snap.get("visual_asset_id", "")])
			# 投射物由 current_scene 承载（无池兜底路径），验完立即回收，否则退出时判泄漏。
			(projectile as Node).free()
		weapon.free()
		# WeaponAssemblyTree / AssemblyNode 都是 Node（非 RefCounted），不显式 free 会连同
		# 其装配子节点一起被 ObjectDB 判为泄漏（套件返回 4）。与 toon v002 用例同一处置。
		if tree != null and is_instance_valid(tree):
			tree.free()


## 走真实调用方路径开一枪，返回首颗投射物的视觉快照（空字典 = 没生成）。
## 与 §6.8 端到端同一路径，不另抄一套配置 —— 否则只证明「测试会配枪」，证明不了实机行为。
func _fire_once(gun_id: String) -> Dictionary:
	var weapon := WEAPON_MODEL_SCENE.instantiate() as WeaponModel3D
	if weapon == null:
		return {}
	add_child(weapon)
	var tree := BlueprintRegistry.build_weapon_tree(gun_id, "mod_bullet_standard")
	weapon.configure_from_tree(tree)
	weapon.global_position = Vector3(3.0, 1.0, 5.0)
	var spawned: Array = []
	weapon.projectile_spawned.connect(func(projectile: Projectile3D) -> void: spawned.append(projectile))
	weapon.call("_fire_now", Vector3(0.0, 0.0, -1.0), weapon, 1.0)
	var snap := {}
	if not spawned.is_empty():
		snap = (spawned[0] as Projectile3D).get_orientation_snapshot()
	for projectile in spawned:
		(projectile as Node).free()
	weapon.free()
	if tree != null and is_instance_valid(tree):
		tree.free()
	return snap


## ⑥ 枪身弹体尺寸差异化（2026-10-14 业主：「每把枪的子弹大小要做出区分」）。
## 三条诉求：霰弹枪由小变大 / 榴弹枪大一点 / 狙击枪长一点，其余枪一律不变。
func _check_gun_size_differentiation() -> void:
	var measured := {}
	for gun_id in EXPECTED_GUN_GEOMETRY.keys():
		var spec: Dictionary = EXPECTED_GUN_GEOMETRY[gun_id]
		var snap := _fire_once(String(gun_id))
		_samples += 1
		if snap.is_empty():
			_failures.append("枪身差异化 " + String(gun_id) + "：开火后没有投射物")
			continue
		var base_scale := float(snap.get("visual_base_scale", 0.0))
		var axial := float(snap.get("visual_axial_scale", 0.0))
		var grow := float(snap.get("visual_growth_factor", 0.0))
		measured[String(gun_id)] = base_scale
		_expect(absf(base_scale - float(spec["scale"])) < 0.01,
			"枪身 " + String(gun_id) + "：弹体尺寸倍率应为 " + str(spec["scale"]) + "，实测 " + str(base_scale))
		_expect(absf(axial - float(spec["axial"])) < 0.01,
			"枪身 " + String(gun_id) + "：轴向拉伸应为 " + str(spec["axial"]) + "，实测 " + str(axial))
		_expect(absf(grow - float(spec["grow_from"])) < 0.01,
			"枪身 " + String(gun_id) + "：出生生长系数应为 " + str(spec["grow_from"]) + "，实测 " + str(grow))

	# 相对判据：三条诉求的方向必须成立。绝对判据看不出的「整表被等比改坏」由这里兜住。
	# 分母一律用中性档 1.00（不再是手枪 —— 手枪自 2026-10-30 起是 2.00）。
	if not measured.has("bp_launcher") or not measured.has("bp_shotgun") or not measured.has("bp_sniper"):
		_failures.append("枪身差异化：霰弹/榴弹/狙击有一把没测到尺寸，相对判据无法成立")
	else:
		var launcher_ratio := float(measured["bp_launcher"]) / NEUTRAL_SCALE
		_expect(launcher_ratio > 1.30,
			"榴弹筒弹体应明显大于中性基准（实测 " + str(launcher_ratio) + " 倍，门槛 >1.30）")
		var shotgun_ratio := float(measured["bp_shotgun"]) / NEUTRAL_SCALE
		_expect(absf(shotgun_ratio - 2.0) < 0.02,
			"霰弹枪弹体应为中性基准的 2 倍（应 ≈2.00，实测 " + str(shotgun_ratio) + "）")
		var sniper_ratio := float(measured["bp_sniper"]) / NEUTRAL_SCALE
		_expect(sniper_ratio < 1.0,
			"狙击弹横向应细于中性基准（实测 " + str(sniper_ratio) + "）")
		# 豌豆手枪 = 中性 ×2（2026-10-30 业主「模型放大一倍」）；单独钉一条，防它被顺手改回 1.0。
		var pistol_ratio := float(measured["bp_pistol"]) / NEUTRAL_SCALE
		_expect(absf(pistol_ratio - 2.0) < 0.02,
			"豌豆手枪弹体应为中性基准的 2 倍（应 ≈2.00，实测 " + str(pistol_ratio) + "）")

	# 枪族档位是**纯视觉**：霰弹 ×2 不得把碰撞半径一起放大（18 发/秒级的命中率会被悄悄改掉）。
	# 期望值硬编码 0.12（基准球半径）—— standard 弹无 balloon tag、无命运缩放 ⇒ 倍率恒为 1.0。
	var shot_snap := _fire_once("bp_shotgun")
	_samples += 1
	if shot_snap.is_empty():
		_failures.append("纯视觉边界：霰弹枪开火后没有投射物")
	else:
		var hit_radius := float(shot_snap.get("collision_radius", -1.0))
		_expect(absf(hit_radius - 0.12) < 0.0001,
			"枪族档位不得改碰撞半径（应恒为基准球 0.12，实测 " + str(hit_radius) + "）")
		_expect(absf(float(shot_snap.get("visual_base_scale", 0.0)) - 2.0) < 0.01,
			"纯视觉边界：同一发的视觉尺寸应仍为 2.0，实测 " + str(shot_snap.get("visual_base_scale", 0.0)))

	# 轴向的几何真值：核心件的局部长轴真的被拉伸（不是只写了个字段）。
	var effect := _instantiate(STANDARD_SCENE)
	if effect == null:
		_failures.append("枪身差异化：标准弹 Prefab 无法实例化")
		return
	add_child(effect)
	effect.activate(Vector3.ZERO, Color.WHITE, 1.0, {"axial_scale": 2.0})
	var axial_snap: Dictionary = effect.call("get_presentation_snapshot")
	_samples += 1
	_expect(absf(float(axial_snap.get("core_axis_scale", 0.0)) - 2.0) < 0.01,
		"轴向拉伸未落到弹芯上，实测 " + str(axial_snap.get("core_axis_scale", 0.0)))
	_expect(absf(float(axial_snap.get("body_scale", 0.0)) - 1.0) < 0.01,
		"轴向拉伸不得改变横向 scale（应仍为 1.0，实测 " + str(axial_snap.get("body_scale", 0.0)) + "）")
	effect.free()


## ⑦ 霰弹枪「由小到大」的生长包络：线性、单调、0.30s 封顶、中性档不启用、复借复位。
func _check_shotgun_growth_envelope() -> void:
	var effect := _instantiate(STANDARD_SCENE)
	if effect == null:
		_failures.append("生长包络：标准弹 Prefab 无法实例化")
		return
	add_child(effect)
	effect.activate(Vector3.ZERO, Color.WHITE, 1.0,
		{"axial_scale": 1.0, "grow_from": 0.42, "grow_duration": 0.30})
	var t0 := float(effect.call("get_presentation_snapshot").get("growth_factor", -1.0))
	_samples += 1
	_expect(absf(t0 - 0.42) < 0.005, "生长包络：出生应为 0.42，实测 " + str(t0))
	effect.call("_process", 0.15)
	var t1 := float(effect.call("get_presentation_snapshot").get("growth_factor", -1.0))
	_expect(absf(t1 - 0.71) < 0.015, "生长包络：0.15s 半程应 ≈0.71，实测 " + str(t1))
	effect.call("_process", 0.15)
	var t2 := float(effect.call("get_presentation_snapshot").get("growth_factor", -1.0))
	_expect(absf(t2 - 1.0) < 0.005, "生长包络：0.30s 后应长满，实测 " + str(t2))
	effect.call("_process", 0.50)
	var t3 := float(effect.call("get_presentation_snapshot").get("growth_factor", -1.0))
	_expect(absf(t3 - 1.0) < 0.005, "生长包络：长满后不得继续放大，实测 " + str(t3))

	# 非霰弹档（中性 context）出生即 100%，不得出现生长过程。
	effect.activate(Vector3.ZERO, Color.WHITE, 1.0, {})
	var neutral := float(effect.call("get_presentation_snapshot").get("growth_factor", -1.0))
	_expect(absf(neutral - 1.0) < 0.005, "中性档不得有生长包络，实测 " + str(neutral))

	# 复借复位：上一发的拉伸 / 生长进度 / 飞行计时都不得残留到下一发。
	effect.activate(Vector3.ZERO, Color.WHITE, 1.0,
		{"axial_scale": 2.0, "grow_from": 0.30, "grow_duration": 0.50})
	effect.call("_process", 0.10)
	effect.call("deactivate")
	var reset: Dictionary = effect.call("get_presentation_snapshot")
	_expect(absf(float(reset.get("axial_scale", 9.0)) - 1.0) < 0.001, "复借复位：轴向拉伸残留")
	_expect(absf(float(reset.get("grow_from", 9.0)) - 1.0) < 0.001, "复借复位：生长起点残留")
	_expect(absf(float(reset.get("flight_time", 9.0))) < 0.001, "复借复位：飞行计时残留")
	effect.free()


## 统计一棵子树里所有 MeshInstance3D 的三角面（PrimitiveMesh 用 get_faces() 展开后 ÷3）。
func _count_mesh_tris(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			total += int(mi.mesh.get_faces().size() / 3)
	for child in node.get_children():
		total += _count_mesh_tris(child)
	return total


## ⑧ 单弹面数预算（业主 2026-10-14：「减面，减到 100 个面以下先」）。
## 两层判据：① 绝对上限 100（业主需求本身）；② 逐弹种实测值（钉住分段参数，防悄悄回涨）。
func _check_face_budget() -> void:
	for entry in PROFILES:
		var label := String(entry["key"])
		var effect := _instantiate(entry["scene"])
		if effect == null:
			_failures.append("面数预算 " + label + "：Prefab 无法实例化")
			continue
		add_child(effect)
		effect.activate(Vector3.ZERO, Color.WHITE, 1.0, {})
		_samples += 1
		var tris := _count_mesh_tris(effect)
		_expect(tris < EXPECTED_MAX_TRIS_PER_BULLET,
			"面数预算 %s：实测 %d 面，超出上限 %d" % [label, tris, EXPECTED_MAX_TRIS_PER_BULLET])
		_expect(tris == int(EXPECTED_TRIS.get(label, -1)),
			"面数预算 %s：期望 %d 面，实测 %d（分段参数被改动？）" % [
				label, int(EXPECTED_TRIS.get(label, -1)), tris])
		effect.free()

	# 通用弹体（回落档，敌人子弹在用）同预算、同实测值。
	var shared := _instantiate(SHARED_SCENE)
	if shared == null:
		_failures.append("面数预算 shared：通用弹体 Prefab 无法实例化")
		return
	add_child(shared)
	shared.activate(Vector3.ZERO, Color.WHITE, 1.0, {})
	_samples += 1
	var shared_tris := _count_mesh_tris(shared)
	_expect(shared_tris < EXPECTED_MAX_TRIS_PER_BULLET,
		"面数预算 shared：实测 %d 面，超出上限 %d" % [shared_tris, EXPECTED_MAX_TRIS_PER_BULLET])
	_expect(shared_tris == int(EXPECTED_TRIS["shared"]),
		"面数预算 shared：期望 %d 面，实测 %d" % [int(EXPECTED_TRIS["shared"]), shared_tris])
	shared.free()


## ⑨ 纯视觉不得含碰撞体。
func _check_collision_free() -> void:
	for entry in PROFILES:
		var label := String(entry["key"])
		var effect := _instantiate(entry["scene"])
		if effect == null:
			continue
		add_child(effect)
		effect.activate(Vector3.ZERO, Color.WHITE, 1.0, {})
		_samples += 1
		var collisions := _count_collision_nodes(effect)
		_expect(collisions == 0, "弹种 %s：弹体视觉 Prefab 内不得含碰撞体，实测 %d 个" % [label, collisions])
		effect.free()


## 端到端开火会把投射物 / 枪口特效挂到 current_scene（=本测试根节点）。
## 这些是战局瞬态物，验完必须清掉，否则退出时被判资源/ObjectDB 泄漏（套件返回 4）。
func _purge_transients() -> void:
	for child in get_children():
		child.free()


func _report() -> void:
	if _failures.is_empty():
		print("BULLET_VFX_PROFILES_OK: 8 bullet profiles / routing / size / gun-size-differentiation / growth-envelope / face-budget / wiring pass (samples=%d)" % _samples)
	else:
		for failure in _failures:
			push_error(failure)
		print("BULLET_VFX_PROFILES_FAIL: %d failures (samples=%d)" % [_failures.size(), _samples])
	get_tree().quit(0 if _failures.is_empty() else 1)
