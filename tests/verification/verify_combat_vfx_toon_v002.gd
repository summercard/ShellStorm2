extends Node
## 战斗三类特效（枪口花火 / 命中爆点 / 飞行子弹）卡通 v002 专项验收。
## 覆盖：AssetID+版本元数据、灯光真相（OmniLight3D 名称/无阴影/范围/能量包络归零）、
##       前向与法线对齐（附反向对照证明断言有辨别力）、纯视觉不得含碰撞体、子弹拖尾落在弹体后方、
##       枪口花火挂点跟随（角色移动/转身时不得残留）与 effect_size 线性缩放。
## 只构建 mesh/material，不读 viewport 纹理 ⇒ 可安全 headless 运行。

const MUZZLE_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_muzzle_flash_root_top3d.tscn")
const IMPACT_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_impact_root_top3d.tscn")
const BULLET_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_bullet_visual_root_top3d.tscn")
const SHELL_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_shell_casing_root_top3d.tscn")

const MUZZLE_ASSET_ID := "VFX-MUZZLE-FLASH-3D"
const IMPACT_ASSET_ID := "VFX-IMPACT-3D"
const BULLET_ASSET_ID := "VFX-BULLET-VISUAL-3D"
const SHELL_ASSET_ID := "VFX-SHELL-CASING-3D"
const EXPECTED_VERSION := "v002"
const SHELL_VERSION := "v001"
## 弹壳 PBR 定档值（业主 2026-09-22 指定）：外部真源，刻意与脚本常量分离硬编码。
const EXPECTED_SHELL_METALLIC := 0.8
const EXPECTED_SHELL_ROUGHNESS := 0.6
## 弹壳尺寸定档（业主 2026-09-22 指定：缩到原基准的 80%）。外部真源。
const EXPECTED_SHELL_SIZE := 0.8
## 弹壳贴地半径基准（size = 1.0 时）。外部真源：三件几何里的**最大**径向半展
## = 底缘 TorusMesh outer_radius 0.058（壳体仅 0.046、底火 0.025）。
## ⚠️ 曾误取壳体值 0.045 ⇒ 底缘多出 0.013，弹壳躺下时整圈陷入地板 1.3cm。
const EXPECTED_SHELL_BASE_RADIUS := 0.058
## 弹壳三件在 Prefab 里的**基准装配偏移**（size = 1.0 时）：
## 底缘贴壳体上端面（+0.12 = 壳体半高 0.24/2）、底火贴下端面（-0.12）。外部真源。
## ⚠️ 缩放时这两个偏移必须**同步按 size 缩放**，否则壳体缩了而底缘/底火原地不动 ⇒ 三件裂开。
const EXPECTED_RIM_LOCAL_OFFSET := 0.12
const EXPECTED_PRIMER_LOCAL_OFFSET := -0.12
## 塔楼 98F 的世界 y（外部真源 = `TowerGeometry3D.FLOOR_HEIGHT_M(12.0) × 98`，向下建 ⇒ 负值）。
## 用于「非零楼层」回归：floor_y 若被兜底成 0，弹壳会在这一层被瞬移到世界原点。
const DEEP_FLOOR_Y := -1176.0
## 弹壳「模拟碰撞」落地次数（含首次落地 + MAX_BOUNCES 次弹跳）。
## 推导：从 y=1.2、v0y=1.6 抛出 ⇒ 首次落地 |v_y|≈5.10 ⇒ 弹跳后 1.63 ⇒ 再弹跳后 0.52 ⇒ 低于 REST_SPEED 转滚动。
## ⇒ 3 次触地。硬编码于此以独立于被测常量。
const EXPECTED_SHELL_IMPACTS := 3
## —— 抛壳随机化（业主 2026-09-22：「不然太整齐了」）——
## 基准速度 = 上一版固定值（手感中心不变）；抖动幅度为 ±比例（前送量太小，改用 ±绝对值）。
## ⚠️ 全部硬编码于此、刻意**不引用** WeaponModel3D 的常量：引用被测常量会自我印证，
##    把常量改坏时期望值跟着变，断言就抓不到了。
const EXPECTED_SHELL_EJECT_RIGHT_SPEED := 2.1
const EXPECTED_SHELL_EJECT_UP_SPEED := 1.55
const EXPECTED_SHELL_EJECT_SPIN_SPEED := 20.0
const EXPECTED_SHELL_EJECT_RIGHT_SPREAD := 0.35
const EXPECTED_SHELL_EJECT_UP_SPREAD := 0.45
const EXPECTED_SHELL_EJECT_FORWARD_JITTER := 0.30
const EXPECTED_SHELL_EJECT_SPIN_SPREAD := 0.50
const EXPECTED_SHELL_INITIAL_TILT_DEG := 45.0
## —— 弹壳停留时长（业主 2026-09-22 追加：「弹壳的停留时长加 1.5 秒」）——
## 口径：寿命 = 飞行 + 弹跳 + 滚动 + **落地后的停留**；前三段由物理常量与初速度决定、
## 不随寿命变化 ⇒ 「停留 +1.5s」= 寿命 3.2 → 4.7。
## ⚠️ 三个数**刻意各自硬编码、不写成派生式**（4.7 = 3.2 + 1.5）：若写成
##    `PREVIOUS + DELTA`，改坏一处会让三处一起跟随，自我印证就抓不到了。
const EXPECTED_SHELL_LIFETIME_PREVIOUS := 3.2
const EXPECTED_SHELL_SETTLED_HOLD_DELTA := 1.5
const EXPECTED_SHELL_LIFETIME := 4.7
## 连发抽样发数。24 发是「能稳定量出散布、又不拖慢验收」的折中：
## 对均匀分布，n 个样本的极差不足理论极差一半的概率 ≈ 2×0.5ⁿ ⇒ n=24 时 ≈ 1e-7，不会假红。
const EJECTION_SAMPLE_SHOTS := 24
## 判据比例：要求观测到的极差 > 理论极差（= 基准 × 幅度 × 2）的一半。
const EJECTION_SPAN_RATIO := 0.5
## 随机化用例要真开合一枪，需要一份可装配的武器模型（与枪口接线用例同一份场景）。
const SHELL_EJECT_WEAPON_SCENE: PackedScene = preload(
	"res://assets/art/weapons/weapon_3d/wpn_gun_kit_root_top3d_v001.tscn"
)
## 弹壳脚本源码路径：静态门禁读它，确保「不接物理引擎」这条契约不被悄悄改回去。
const SHELL_SCRIPT_PATH := "res://src/vfx/VfxShellCasing3D.gd"
## 弹壳脚本内**禁止出现**的物理 API / 节点类型符号（业主 2026-09-22：不要真实物理碰撞）。
const SHELL_FORBIDDEN_PHYSICS_SYMBOLS := [
	"intersect_ray",
	"PhysicsRayQueryParameters3D",
	"PhysicsDirectSpaceState3D",
	"direct_space_state",
	"move_and_collide",
	"move_and_slide",
	"RigidBody3D",
	"CharacterBody3D",
	"StaticBody3D",
	"Area3D",
	"CollisionShape3D",
	"CollisionObject3D",
]
const MIN_SAMPLES := 12

var _failures: Array[String] = []
var _samples := 0


func _ready() -> void:
	_check_muzzle()
	_check_muzzle_follow()
	_check_muzzle_size_linear()
	_check_muzzle_caller_wiring()
	_check_impact()
	_check_bullet()
	_check_shell_casing()
	_check_shell_ejection_randomized()
	_check_collision_free()
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


func _check_muzzle() -> void:
	var muzzle := MUZZLE_SCENE.instantiate() as VfxEffectBase3D
	if muzzle == null:
		_failures.append("枪口花火 Prefab 根节点不是 VfxEffectBase3D")
		return
	add_child(muzzle)
	# 取一个水平方向，使 y=0，便于用 UP 做无歧义的反向对照。
	var forward := Vector3(1.0, 0.0, -0.55).normalized()
	muzzle.activate(Vector3(2.0, 1.0, -3.0), Color(1.0, 0.6, 0.2), 1.0, {"forward": forward})
	_samples += 1

	var snapshot: Dictionary = muzzle.call("get_presentation_snapshot")
	_expect(String(snapshot.get("asset_id", "")) == MUZZLE_ASSET_ID,
		"枪口花火 AssetID 不正确：%s" % snapshot.get("asset_id", ""))
	_expect(String(snapshot.get("asset_version", "")) == EXPECTED_VERSION,
		"枪口花火版本不是 %s：%s" % [EXPECTED_VERSION, snapshot.get("asset_version", "")])
	_expect(bool(snapshot.get("has_muzzle_light", false)), "枪口花火缺少 OmniLight3D（MuzzleLight）")
	_expect(String(snapshot.get("light_name", "")) == "MuzzleLight",
		"枪口灯节点名不是 MuzzleLight：%s" % snapshot.get("light_name", ""))
	_expect(not bool(snapshot.get("light_shadows", true)), "枪口灯不应投射阴影")
	_expect(int(snapshot.get("node_count", 0)) >= 10,
		"枪口花火子节点过少，几何未构建：%d" % int(snapshot.get("node_count", 0)))

	var lifetime := float(snapshot.get("lifetime", 0.0))
	_expect(lifetime > 0.10 and lifetime < 0.25, "枪口花火寿命应在 0.10~0.25s：%.3f" % lifetime)
	var light_range := float(snapshot.get("light_range", 0.0))
	_expect(light_range >= 3.0 and light_range <= 4.5, "枪口灯范围应在 3~4.5m：%.2f" % light_range)
	var light_energy := float(snapshot.get("light_energy", 0.0))
	_expect(light_energy > 0.0, "激活瞬间枪口灯能量应为正：%.2f" % light_energy)

	# 朝向真相：local -Z 必须与 context.forward 同向。
	var actual_forward := -muzzle.global_basis.z
	_expect(actual_forward.dot(forward) > 0.999,
		"枪口花火 local -Z 未对齐 context.forward：dot=%.4f" % actual_forward.dot(forward))
	# 反向对照：同一断言若换成垂直方向必须失败，证明它有辨别力。
	_expect(absf(actual_forward.dot(Vector3.UP)) < 0.5,
		"反向对照失效：前向对齐断言对垂直方向也成立（dot=%.4f）" % actual_forward.dot(Vector3.UP))

	# 灯光能量包络：半程必须衰减但不归零，寿命结束必须归零。
	muzzle.call("_on_tick", lifetime * 0.5, lifetime)
	var half_energy := float((muzzle.call("get_presentation_snapshot") as Dictionary).get("light_energy", 0.0))
	_expect(half_energy < light_energy, "枪口灯能量未随包络衰减：%.3f -> %.3f" % [light_energy, half_energy])
	_expect(half_energy > 0.0, "枪口灯在半程就归零，包络过陡：%.3f" % half_energy)
	muzzle.call("_on_lifetime_expired")
	var end_energy := float((muzzle.call("get_presentation_snapshot") as Dictionary).get("light_energy", 0.0))
	_expect(is_zero_approx(end_energy), "寿命结束枪口灯能量必须归零：%.3f" % end_energy)
	muzzle.free()


## 挂点跟随契约：角色移动/转身时枪口特效必须贴着挂点，而不是残留在生成瞬间的世界坐标。
func _check_muzzle_follow() -> void:
	var anchor := Node3D.new()
	anchor.name = "FollowAnchor"
	add_child(anchor)
	anchor.global_position = Vector3(4.0, 2.0, 1.0)
	var offset := Vector3(0.0, 0.25, -0.8)  # 挂点本地空间的"枪口"偏移

	var followed := MUZZLE_SCENE.instantiate() as VfxEffectBase3D
	if followed == null:
		_failures.append("枪口花火 Prefab 根节点不是 VfxEffectBase3D（跟随用例）")
		anchor.free()
		return
	add_child(followed)
	followed.activate(anchor.to_global(offset), Color(1.0, 0.6, 0.2), 1.0,
		{"forward": Vector3.FORWARD, "follow": anchor, "follow_local_offset": offset})
	_samples += 1
	var spawn_err := followed.global_position.distance_to(anchor.to_global(offset))
	_expect(spawn_err < 0.001, "枪口花火生成位置未落在挂点偏移上：误差 %.4f m" % spawn_err)

	# 挂点平移 ⇒ 特效必须同步平移（"角色走动时枪口不残留"的核心契约）
	anchor.global_position += Vector3(3.0, 0.0, -2.5)
	followed.call("_process", 1.0 / 60.0)
	var drift := followed.global_position.distance_to(anchor.to_global(offset))
	_expect(drift < 0.001, "枪口花火未跟随挂点平移，残留在原地 %.4f m" % drift)

	# 挂点转身 ⇒ local -Z 必须跟着转
	anchor.global_rotation = Vector3(0.0, PI * 0.5, 0.0)
	followed.call("_process", 1.0 / 60.0)
	var turned := (-followed.global_basis.z).dot(-anchor.global_basis.z)
	_expect(turned > 0.999, "枪口花火未跟随挂点转向：dot=%.4f" % turned)

	# 反向对照：同一条"跟得上"的判据，在未绑定 follow 的实例上必须失败 ⇒ 证明断言有辨别力。
	var unbound := MUZZLE_SCENE.instantiate() as VfxEffectBase3D
	add_child(unbound)
	unbound.activate(anchor.to_global(offset), Color(1.0, 0.6, 0.2), 1.0, {"forward": Vector3.FORWARD})
	anchor.global_position += Vector3(2.0, 0.0, 0.0)
	unbound.call("_process", 1.0 / 60.0)
	var unbound_drift := unbound.global_position.distance_to(anchor.to_global(offset))
	_expect(unbound_drift > 0.5,
		"反向对照失效：未绑定 follow 的实例也跟上了挂点（漂移仅 %.4f m）" % unbound_drift)

	unbound.free()
	followed.free()
	anchor.free()


## 尺寸契约：effect_size 必须线性作用于视觉体积（业主 2026-09-21 定档 0.8 ⇒ 视觉即基准的 80%）。
func _check_muzzle_size_linear() -> void:
	var full := MUZZLE_SCENE.instantiate() as VfxEffectBase3D
	var reduced := MUZZLE_SCENE.instantiate() as VfxEffectBase3D
	if full == null or reduced == null:
		_failures.append("枪口花火 Prefab 根节点不是 VfxEffectBase3D（尺寸用例）")
		return
	add_child(full)
	add_child(reduced)
	full.activate(Vector3.ZERO, Color.WHITE, 1.0, {"forward": Vector3.FORWARD})
	reduced.activate(Vector3.ZERO, Color.WHITE, 0.8, {"forward": Vector3.FORWARD})
	full.call("_on_tick", 0.0, full.lifetime)
	reduced.call("_on_tick", 0.0, reduced.lifetime)
	_samples += 1

	var full_petal := full.get_node_or_null("PetalA") as MeshInstance3D
	var small_petal := reduced.get_node_or_null("PetalA") as MeshInstance3D
	if full_petal == null or small_petal == null:
		_failures.append("枪口花火缺少 PetalA 节点，无法校验尺寸线性")
	else:
		var ratio := full_petal.scale.x / maxf(small_petal.scale.x, 0.0001)
		_expect(absf(ratio - 1.25) < 0.02,
			"effect_size 未线性作用于视觉体积：1.0/0.8 实测比值 %.4f（期望 1.25）" % ratio)
	var range_full := float((full.call("get_presentation_snapshot") as Dictionary).get("light_range", 0.0))
	var range_small := float((reduced.call("get_presentation_snapshot") as Dictionary).get("light_range", 0.0))
	var range_ratio := range_small / maxf(range_full, 0.0001)
	_expect(absf(range_ratio - 0.8) < 0.02,
		"枪口灯范围未随 effect_size 缩到 80%%：实测比值 %.4f" % range_ratio)
	full.free()
	reduced.free()


func _check_impact() -> void:
	var impact := IMPACT_SCENE.instantiate() as VfxEffectBase3D
	if impact == null:
		_failures.append("命中爆点 Prefab 根节点不是 VfxEffectBase3D")
		return
	add_child(impact)
	var normal := Vector3(0.2, 0.9, -0.35).normalized()
	impact.activate(Vector3(-1.0, 0.5, 2.0), Color(1.0, 0.5, 0.15), 1.0, {"normal": normal})
	_samples += 1

	var snapshot: Dictionary = impact.call("get_presentation_snapshot")
	_expect(String(snapshot.get("asset_id", "")) == IMPACT_ASSET_ID,
		"命中爆点 AssetID 不正确：%s" % snapshot.get("asset_id", ""))
	_expect(String(snapshot.get("asset_version", "")) == EXPECTED_VERSION,
		"命中爆点版本不是 %s：%s" % [EXPECTED_VERSION, snapshot.get("asset_version", "")])
	_expect(not bool(snapshot.get("has_muzzle_light", true)), "命中爆点不应含枪口灯")
	_expect(int(snapshot.get("node_count", 0)) >= 15,
		"命中爆点星芒/碎屑数量不足：节点数 %d" % int(snapshot.get("node_count", 0)))
	var lifetime := float(snapshot.get("lifetime", 0.0))
	_expect(lifetime > 0.25 and lifetime < 0.40, "命中爆点寿命应在 0.25~0.40s：%.3f" % lifetime)

	var actual_normal: Vector3 = impact.global_basis.y
	_expect(actual_normal.dot(normal) > 0.999,
		"命中爆点 local +Y 未对齐 context.normal：dot=%.4f" % actual_normal.dot(normal))
	_expect(absf(actual_normal.dot(Vector3.RIGHT)) < 0.5,
		"反向对照失效：法线对齐断言对非对齐轴也成立（dot=%.4f）" % actual_normal.dot(Vector3.RIGHT))
	impact.free()


func _check_bullet() -> void:
	var bullet := BULLET_SCENE.instantiate() as VfxBulletVisual3D
	if bullet == null:
		_failures.append("飞行子弹 Prefab 根节点不是 VfxBulletVisual3D")
		return
	add_child(bullet)
	bullet.activate(Vector3.ZERO, Color(1.0, 0.4, 0.15), 1.0, {})
	_samples += 1

	var snapshot: Dictionary = bullet.call("get_presentation_snapshot")
	_expect(String(snapshot.get("asset_id", "")) == BULLET_ASSET_ID,
		"子弹视觉 AssetID 不正确：%s" % snapshot.get("asset_id", ""))
	_expect(String(snapshot.get("light_name", "")) == "ProjectileLight",
		"子弹灯节点名不是 ProjectileLight：%s" % snapshot.get("light_name", ""))
	_expect(not bool(snapshot.get("light_shadows", true)), "子弹灯不应投射阴影")
	var light_energy := float(snapshot.get("light_energy", 0.0))
	_expect(light_energy > 0.0, "子弹激活后灯能量应为正：%.2f" % light_energy)
	var light_range := float(snapshot.get("light_range", 0.0))
	_expect(light_range > 1.0 and light_range < 3.0, "子弹灯范围应在 1~3m：%.2f" % light_range)
	_expect(bool(snapshot.get("trail_is_behind", false)),
		"子弹拖尾未落在弹体后方：%s" % snapshot.get("trail_local_position", Vector3.ZERO))
	var trail_pos: Vector3 = snapshot.get("trail_local_position", Vector3.ZERO)
	_expect(trail_pos.z > 0.0, "子弹拖尾局部 Z 应为正（身后）：%.3f" % trail_pos.z)

	# 回收必须把灯能量归零且不可见（否则池化复借会留下长明灯）。
	bullet.deactivate()
	var off: Dictionary = bullet.call("get_presentation_snapshot")
	_expect(is_zero_approx(float(off.get("light_energy", 1.0))),
		"子弹回收后灯能量必须归零：%.3f" % float(off.get("light_energy", 1.0)))
	_expect(not bool(off.get("light_visible", true)), "子弹回收后灯必须不可见")

	# 复借必须重新点亮（池化复用的核心契约）。
	bullet.activate(Vector3.ZERO, Color(0.3, 0.9, 1.0), 1.0, {})
	var on: Dictionary = bullet.call("get_presentation_snapshot")
	_expect(float(on.get("light_energy", 0.0)) > 0.0,
		"子弹复借后灯能量未重新点亮：%.3f" % float(on.get("light_energy", 0.0)))
	_expect(bool(on.get("light_visible", false)), "子弹复借后灯未重新可见")
	bullet.free()


func _check_shell_casing() -> void:
	var shell := SHELL_SCENE.instantiate() as VfxShellCasing3D
	if shell == null:
		_failures.append("弹壳 Prefab 根节点不是 VfxShellCasing3D")
		return
	add_child(shell)
	var spawn := Vector3(2.0, 1.2, -1.0)
	shell.activate(spawn, Color(0.92, 0.56, 0.16), 1.0, {
		"velocity": Vector3(1.8, 1.6, 0.0),
		"spin_axis": Vector3(0.7, 1.0, 0.0),
		"spin_speed": 18.0,
		"floor_y": 0.0,
	})
	_samples += 1
	var snapshot: Dictionary = shell.call("get_presentation_snapshot")
	_expect(String(snapshot.get("asset_id", "")) == SHELL_ASSET_ID,
		"弹壳 AssetID 不正确：%s" % snapshot.get("asset_id", ""))
	_expect(String(snapshot.get("asset_version", "")) == SHELL_VERSION,
		"弹壳版本不是 %s：%s" % [SHELL_VERSION, snapshot.get("asset_version", "")])
	_expect(bool(snapshot.get("body_mesh", false)) and bool(snapshot.get("rim_mesh", false)),
		"弹壳主体/底缘 mesh 未构建")
	_expect(float(snapshot.get("gravity", 0.0)) > 9.0,
		"弹壳未使用真实重力：%.2f" % float(snapshot.get("gravity", 0.0)))
	_expect(int(snapshot.get("max_bounces", 0)) == 2,
		"弹壳最大弹跳次数应为 2：%d" % int(snapshot.get("max_bounces", 0)))
	# 业主 2026-09-22 口径：弹出/掉落是**程序化模拟碰撞**，不得接物理引擎。
	_expect(bool(snapshot.get("simulated_collision", false)),
		"弹壳未声明为程序化模拟碰撞")
	var radius_at_unit := float(snapshot.get("radius", -1.0))
	_expect(absf(radius_at_unit - EXPECTED_SHELL_BASE_RADIUS) < 0.0001,
		"弹壳贴地半径基准不是 %.3f：%.4f" % [EXPECTED_SHELL_BASE_RADIUS, radius_at_unit])
	# 贴地半径必须由已挂载几何实测得出（几何改了自动跟随），不得只信任常量。
	var measured_extent := float(snapshot.get("measured_radial_half_extent", -1.0))
	_expect(absf(measured_extent - EXPECTED_SHELL_BASE_RADIUS) < 0.0001,
		"弹壳实测径向半展不是 %.3f：%.4f（最大径向半展在底缘环上，不是壳体）"
		% [EXPECTED_SHELL_BASE_RADIUS, measured_extent])

	# PBR 定档（业主 2026-09-22）：金属度 0.8 / 反光度（roughness）0.6，三件统一。
	# ⚠️ 期望值硬编码于此（外部真源），不得引用 VfxShellCasing3D 的常量 —— 引用被测常量会自我印证，
	#    脚本里把常量改坏时期望值跟着变，断言就抓不到了。
	var pbr_cases := [
		["壳体", "metallic", "roughness"],
		["底缘", "rim_metallic", "rim_roughness"],
		["底火", "primer_metallic", "primer_roughness"],
	]
	for entry in pbr_cases:
		var label := String(entry[0])
		var got_metallic := float(snapshot.get(String(entry[1]), -1.0))
		var got_roughness := float(snapshot.get(String(entry[2]), -1.0))
		_expect(absf(got_metallic - EXPECTED_SHELL_METALLIC) < 0.0001,
			"弹壳%s金属度不是 %.1f：%.3f" % [label, EXPECTED_SHELL_METALLIC, got_metallic])
		_expect(absf(got_roughness - EXPECTED_SHELL_ROUGHNESS) < 0.0001,
			"弹壳%s反光度(roughness)不是 %.1f：%.3f" % [label, EXPECTED_SHELL_ROUGHNESS, got_roughness])
	# 反向对照：同一组断言对"未挂材质"的哨兵值必须失败，证明断言真在读数而非恒真。
	var sentinel := float(snapshot.get("primer_metallic", -1.0))
	_expect(sentinel > 0.0, "反向对照失效：PBR 真值断言对哨兵值也成立（%.3f）" % sentinel)
	# 同时钉住脚本常量本身等于定档值（常量被改坏时也变红）。
	_expect(absf(VfxShellCasing3D.SHELL_METALLIC - EXPECTED_SHELL_METALLIC) < 0.0001,
		"脚本常量 SHELL_METALLIC 不是 %.1f：%.3f" % [EXPECTED_SHELL_METALLIC, VfxShellCasing3D.SHELL_METALLIC])
	_expect(absf(VfxShellCasing3D.SHELL_ROUGHNESS - EXPECTED_SHELL_ROUGHNESS) < 0.0001,
		"脚本常量 SHELL_ROUGHNESS 不是 %.1f：%.3f" % [EXPECTED_SHELL_ROUGHNESS, VfxShellCasing3D.SHELL_ROUGHNESS])

	var y_before := shell.global_position.y
	shell.call("_on_tick", 0.10, shell.lifetime)
	var y_after := shell.global_position.y
	_expect(y_after > 0.0 and y_after != y_before, "弹壳未开始飞行：%.3f -> %.3f" % [y_before, y_after])
	# 逐帧采样最低点：只查终态会漏掉"弹跳过程中穿地"，而穿地在终态被静止贴地修正掉了。
	var min_y := INF
	for index in range(1, 24):
		shell.call("_on_tick", 0.10 + float(index) * 0.08, shell.lifetime)
		min_y = minf(min_y, shell.global_position.y)
	_expect(min_y >= radius_at_unit - 0.001,
		"弹壳在弹跳过程中穿地：全程最低 y=%.4f（贴地应为 %.4f）" % [min_y, radius_at_unit])
	_expect(shell.global_position.x > spawn.x, "弹壳未向枪械右侧飞出：x=%.3f" % shell.global_position.x)
	_expect(shell.global_position.y >= -0.001, "弹壳穿过地板：y=%.3f" % shell.global_position.y)
	var flight_snapshot: Dictionary = shell.call("get_presentation_snapshot")
	_expect(int(flight_snapshot.get("bounce_count", 0)) <= 2,
		"弹壳超过最大弹跳次数")
	# 模拟碰撞序列必须完整收敛：首次落地 + 2 次弹跳 = 3 次触地，且最终静止。
	# 期望值 3 由几何推出（见 EXPECTED_SHELL_IMPACTS 注释），硬编码于此以独立于被测常量。
	_expect(int(flight_snapshot.get("impact_count", 0)) == EXPECTED_SHELL_IMPACTS,
		"弹壳触地次数不是 %d：%d" % [EXPECTED_SHELL_IMPACTS, int(flight_snapshot.get("impact_count", 0))])
	_expect(bool(flight_snapshot.get("settled", false)),
		"弹壳未在寿命内进入静止（phase=%d）" % int(flight_snapshot.get("phase", -1)))
	# 静止姿态：弹壳长轴（local Y）必须放平到地面上（世界 Y 分量为 0），即"躺在地上"。
	_expect(absf(shell.global_transform.basis.y.y) < 0.001,
		"弹壳静止后未躺平（长轴 Y 分量 %.4f）" % shell.global_transform.basis.y.y)
	# 静止时贴地高度必须等于半径，不得浮空/陷入。
	_expect(absf(shell.global_position.y - radius_at_unit) < 0.001,
		"弹壳静止高度不等于半径：y=%.4f r=%.4f" % [shell.global_position.y, radius_at_unit])
	# 反向对照：无水平初速度的弹壳不能满足"已向右飞出"判据。
	var stationary := SHELL_SCENE.instantiate() as VfxShellCasing3D
	add_child(stationary)
	stationary.activate(spawn, Color.WHITE, 1.0, {"velocity": Vector3(0.0, 1.6, 0.0), "floor_y": 0.0})
	stationary.call("_on_tick", 0.10, stationary.lifetime)
	_expect(stationary.global_position.x <= spawn.x + 0.001,
		"反向对照失效：零水平初速度也向右飞出")
	stationary.free()
	shell.free()
	_check_shell_size_scale(spawn)
	_check_shell_simulation_only()
	_check_shell_nonzero_floor()
	_check_shell_settled_hold()


## 非零楼层回归钉子（2026-09-22 实机缺陷「弹壳特效没了」）：
## 塔楼楼层是**向下**建的（`stage.position.y = -12 × floor_index`），98F ≈ -1176 m。
## 若调用方把 floor_y 兜底成 0，弹壳出生点就已经"低于地面" ⇒ 第一帧判定触地 ⇒
## 被夹到 y≈0.058（世界原点附近）⇒ **掉出玩家视野**，表现就是「弹壳特效没了」。
## 该缺陷只在非零楼层暴露，而普通验收场景摆在 y≈0 ⇒ 必须专门钉一条。
func _check_shell_nonzero_floor() -> void:
	var deep := SHELL_SCENE.instantiate() as VfxShellCasing3D
	if deep == null:
		_failures.append("弹壳 Prefab 根节点不是 VfxShellCasing3D（非零楼层用例）")
		return
	add_child(deep)
	var spawn_y := DEEP_FLOOR_Y + 1.2
	deep.activate(Vector3(0.0, spawn_y, 0.0), Color(0.92, 0.56, 0.16), EXPECTED_SHELL_SIZE, {
		"velocity": Vector3(1.2, 1.6, 0.0),
		"floor_y": DEEP_FLOOR_Y,
	})
	_samples += 1
	var floor_got := float(deep.call("get_presentation_snapshot").get("floor_y", 1.0e9))
	_expect(absf(floor_got - DEEP_FLOOR_Y) < 0.0001,
		"弹壳未采用调用方给的深层地面高度：%.3f" % floor_got)
	# 第一帧不得瞬移：出生点必须仍在原处（旧缺陷会在这里就被夹到 0.058）。
	deep.call("_on_tick", 0.02, deep.lifetime)
	_expect(absf(deep.global_position.y - spawn_y) < 0.2,
		"弹壳在非零楼层第一帧被瞬移：y=%.3f 期望 ≈%.3f" % [deep.global_position.y, spawn_y])
	for index in range(1, 60):
		deep.call("_on_tick", 0.02 + float(index) * 0.05, deep.lifetime)
	var deep_radius := EXPECTED_SHELL_BASE_RADIUS * EXPECTED_SHELL_SIZE
	_expect(absf(deep.global_position.y - (DEEP_FLOOR_Y + deep_radius)) < 0.01,
		"弹壳未落在深层地面：y=%.3f 期望 ≈%.3f" % [deep.global_position.y, DEEP_FLOOR_Y + deep_radius])
	# 终极判据：绝不允许落到世界原点附近（那正是 floor_y 被兜底成 0 的症状）。
	_expect(absf(deep.global_position.y) > 100.0,
		"弹壳落到世界原点附近（y=%.3f）⇒ floor_y 被兜底成 0 的回归" % deep.global_position.y)
	deep.free()


## 停留时长定档（业主 2026-09-22 追加：「弹壳的停留时长加 1.5 秒」）。
##
## 口径：弹壳「在地上的停留」= `lifetime − 落地静止时刻`。飞行 / 弹跳 / 滚动三段的时长
## 由物理常量与初速度决定，**不随寿命变化** ⇒ 加寿命就是加停留，业主的「+1.5 秒」
## 据此落成 `VfxShellCasing3D.DEFAULT_LIFETIME: 3.2 → 4.7`。
##
## 三条断言互补：
##   ① 寿命 = 定档值（外部真源硬编码，不引用被测常量 ⇒ 改坏常量才抓得到）；
##   ② 增量 = 上一版 3.2 + 1.5（**业主诉求本身**，常量级钉子）；
##   ③ 行为级：实测静止时刻后剩余停留 ≥ 1.5s —— 挡住「有人把初速度调大到飞行段
##      吃掉这 1.5s」这类隐形退化（那时 ①② 仍绿，只有 ③ 会红）。
## ⚠️ 必须用**新实例**：主用例那枚已被推进到 1.94s 且早已 SETTLED，
##    复用它时 t_settle 会取到第一个步长（恒真），③ 就废了。
func _check_shell_settled_hold() -> void:
	const STEP := 1.0 / 60.0
	const MAX_SECONDS := 12.0
	var shell := SHELL_SCENE.instantiate() as VfxShellCasing3D
	if shell == null:
		_failures.append("弹壳 Prefab 根节点不是 VfxShellCasing3D（停留时长用例）")
		return
	add_child(shell)
	# 初速度取抛壳随机化的中心值（= 上一版固定值）⇒ 落地过程与实机一致，可复现。
	shell.activate(Vector3(0.0, 1.2, 0.0), Color(0.92, 0.56, 0.16), EXPECTED_SHELL_SIZE, {
		"velocity": Vector3(
			EXPECTED_SHELL_EJECT_RIGHT_SPEED,
			EXPECTED_SHELL_EJECT_UP_SPEED,
			0.0
		),
		"floor_y": 0.0,
	})
	_samples += 1
	var settle_elapsed := -1.0
	var elapsed := 0.0
	while elapsed < MAX_SECONDS:
		elapsed += STEP
		shell.call("_on_tick", elapsed, shell.lifetime)
		if bool(shell.call("get_presentation_snapshot").get("settled", false)):
			settle_elapsed = elapsed
			break
	# 防假绿哨兵：没测到静止时刻，③ 会退化成「拿 -1.0 参与比较」，必须先把它挡下。
	_expect(settle_elapsed > 0.0,
		"弹壳在 %.1fs 内未进入静止，停留时长无法核算（哨兵）" % MAX_SECONDS)
	var lifetime := float(VfxShellCasing3D.DEFAULT_LIFETIME)
	var hold: float = lifetime - settle_elapsed
	print("[vfx_toon_v002] shell settled_hold lifetime=%.2f settle_at=%.2f hold=%.2f"
		% [lifetime, settle_elapsed, hold])
	# ① 寿命定档（外部真源）。
	_expect(absf(lifetime - EXPECTED_SHELL_LIFETIME) < 0.0001,
		"弹壳寿命不是定档值 %.2f：%.3f" % [EXPECTED_SHELL_LIFETIME, lifetime])
	_expect(absf(shell.lifetime - EXPECTED_SHELL_LIFETIME) < 0.0001,
		"弹壳实例寿命未按 DEFAULT_LIFETIME 初始化：%.3f（检查 _ready）" % shell.lifetime)
	# ② 增量 = 上一版 + 1.5s（业主诉求本身）。
	_expect(absf(lifetime - EXPECTED_SHELL_LIFETIME_PREVIOUS - EXPECTED_SHELL_SETTLED_HOLD_DELTA) < 0.0001,
		"弹壳停留增量不是 %.1fs：寿命 %.2f − 上一版 %.2f = %.2f"
		% [
			EXPECTED_SHELL_SETTLED_HOLD_DELTA,
			lifetime,
			EXPECTED_SHELL_LIFETIME_PREVIOUS,
			lifetime - EXPECTED_SHELL_LIFETIME_PREVIOUS,
		])
	# ③ 行为级：静止后真的还能停留 ≥ 1.5s。
	_expect(hold >= EXPECTED_SHELL_SETTLED_HOLD_DELTA,
		"弹壳落地静止后停留只有 %.2fs（要求 ≥ %.1fs）：t_settle=%.2f lifetime=%.2f"
		% [hold, EXPECTED_SHELL_SETTLED_HOLD_DELTA, settle_elapsed, lifetime])
	shell.free()


## 尺寸定档（业主 2026-09-22：缩到原基准的 80%）—— 视觉缩放与贴地半径必须同步落到几何上。
func _check_shell_size_scale(spawn: Vector3) -> void:
	var small := SHELL_SCENE.instantiate() as VfxShellCasing3D
	if small == null:
		_failures.append("弹壳 Prefab 根节点不是 VfxShellCasing3D（尺寸用例）")
		return
	add_child(small)
	small.activate(spawn, Color(0.92, 0.56, 0.16), EXPECTED_SHELL_SIZE, {
		"velocity": Vector3(1.2, 1.0, 0.0),
		"floor_y": 0.0,
	})
	var snapshot: Dictionary = small.call("get_presentation_snapshot")
	_expect(absf(float(snapshot.get("visual_scale", -1.0)) - EXPECTED_SHELL_SIZE) < 0.0001,
		"弹壳视觉缩放不是 %.2f：%.3f" % [EXPECTED_SHELL_SIZE, float(snapshot.get("visual_scale", -1.0))])
	# 真值断言：读已挂载**三件子节点**的实际 scale，而不是回读入参。
	# 缩放必须落在子节点上 —— 根节点带缩放会让 basis 非正交（旋转赋值报 must be normalized）。
	var mounted_scale: Vector3 = snapshot.get("shell_scale", Vector3.ZERO)
	_expect(absf(mounted_scale.x - EXPECTED_SHELL_SIZE) < 0.0001,
		"弹壳三件实际缩放不是 %.2f：%.4f" % [EXPECTED_SHELL_SIZE, mounted_scale.x])
	# 根节点必须保持**单位缩放**（缩放只落子节点）：否则旋转赋值会刷一屏 must-be-normalized ERROR。
	var root_scale: Vector3 = snapshot.get("root_scale", Vector3.ZERO)
	_expect(absf(root_scale.x - 1.0) < 0.0001 and absf(root_scale.y - 1.0) < 0.0001
		and absf(root_scale.z - 1.0) < 0.0001,
		"弹壳根节点被施加了缩放（应单位缩放、只做旋转）：%s" % str(root_scale))
	# 装配完整性：三件子节点的 local position 必须**随尺寸同步缩放**（底缘 +0.12×size / 底火 -0.12×size）。
	# 防的是「只缩放子节点 scale、漏掉它们的偏移」⇒ 三件裂开（像素核对抓到过）。
	var rim_expected := EXPECTED_RIM_LOCAL_OFFSET * EXPECTED_SHELL_SIZE
	var primer_expected := EXPECTED_PRIMER_LOCAL_OFFSET * EXPECTED_SHELL_SIZE
	var rim_actual: float = small.get_node("Rim").position.y
	var primer_actual: float = small.get_node("Primer").position.y
	_expect(absf(rim_actual - rim_expected) < 0.0001 and absf(primer_actual - primer_expected) < 0.0001,
		"弹壳装配未随尺寸缩放（底缘应 %.4f 实 %.4f；底火应 %.4f 实 %.4f）"
		% [rim_expected, rim_actual, primer_expected, primer_actual])
	var expected_radius := EXPECTED_SHELL_BASE_RADIUS * EXPECTED_SHELL_SIZE
	var got_radius := float(snapshot.get("radius", -1.0))
	_expect(absf(got_radius - expected_radius) < 0.0001,
		"弹壳贴地半径未随尺寸缩放（应 %.4f，实 %.4f）" % [expected_radius, got_radius])
	# 该尺寸下的静止高度也必须等于缩放后的半径。
	small.call("_on_tick", 0.10, small.lifetime)
	for index in range(1, 30):
		small.call("_on_tick", 0.10 + float(index) * 0.08, small.lifetime)
	_expect(absf(small.global_position.y - expected_radius) < 0.001,
		"缩小后弹壳未精确贴地：y=%.4f 期望 %.4f" % [small.global_position.y, expected_radius])
	small.free()


## 静态门禁：弹壳脚本必须保持「程序化模拟碰撞」——源码不得出现任何物理查询 API / 物理节点类型。
## 只有这一条能看住「不要真实物理碰撞」这条业主口径：行为层无法区分射线命中与解析式越线判定。
func _check_shell_simulation_only() -> void:
	var file := FileAccess.open(SHELL_SCRIPT_PATH, FileAccess.READ)
	if file == null:
		_failures.append("弹壳脚本不可读，静态门禁失效：%s" % SHELL_SCRIPT_PATH)
		return
	var line_count := 0
	var hits := PackedStringArray()
	while not file.eof_reached():
		var raw := file.get_line()
		line_count += 1
		var code := raw.strip_edges()
		# 整行注释允许提及物理 API（文件头契约文档需要点名禁止项），行尾代码仍受检。
		if code.is_empty() or code.begins_with("#"):
			continue
		for symbol in SHELL_FORBIDDEN_PHYSICS_SYMBOLS:
			if code.contains(String(symbol)):
				hits.append("第 %d 行含 %s" % [line_count, symbol])
	file.close()
	# 防假绿哨兵：读到的行数太少说明门禁没真读到脚本。
	_expect(line_count >= 100, "弹壳脚本静态门禁样本不足（只读到 %d 行）" % line_count)
	_expect(hits.is_empty(),
		"弹壳脚本出现物理碰撞 API，业主口径要求改为程序化模拟：%s" % ", ".join(hits))


func _check_collision_free() -> void:
	var cases := [
		["枪口花火", MUZZLE_SCENE, {"forward": Vector3.FORWARD}],
		["命中爆点", IMPACT_SCENE, {"normal": Vector3.UP}],
		["飞行子弹", BULLET_SCENE, {}],
		["弹壳", SHELL_SCENE, {"floor_y": 0.0}],
	]
	for entry in cases:
		var label := String(entry[0])
		var packed: PackedScene = entry[1]
		var context: Dictionary = entry[2]
		var effect := packed.instantiate() as VfxEffectBase3D
		if effect == null:
			_failures.append("%s Prefab 根节点不是 VfxEffectBase3D" % label)
			continue
		add_child(effect)
		effect.activate(Vector3.ZERO, Color.WHITE, 1.0, context)
		_samples += 1
		var collisions := _count_collision_nodes(effect)
		_expect(collisions == 0, "%s 特效 Prefab 内不得含碰撞体，实测 %d 个" % [label, collisions])
		effect.free()


## 真实调用方接线：WeaponModel3D 必须把枪口特效交给池、绑定 muzzle 挂点、并用 80% 尺寸基准。
## 上面的 follow 用例只证明机制可用；这一条才是"游戏里真的不残留"的端到端证据。
func _check_muzzle_caller_wiring() -> void:
	const WEAPON_MODEL_SCENE: PackedScene = preload(
		"res://assets/art/weapons/weapon_3d/wpn_gun_kit_root_top3d_v001.tscn"
	)
	var pool := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	if pool == null:
		_failures.append("调用方接线：场景里找不到 vfx_pool_3d 池")
		return
	var weapon := WEAPON_MODEL_SCENE.instantiate() as WeaponModel3D
	if weapon == null:
		_failures.append("调用方接线：武器模型场景根节点不是 WeaponModel3D")
		return
	add_child(weapon)
	var tree := BlueprintRegistry.build_weapon_tree(
		BlueprintRegistry.DEFAULT_STARTING_GUN_ID, "mod_bullet_standard"
	)
	if tree == null or not weapon.configure_from_tree(tree):
		_failures.append("调用方接线：出厂枪装配失败，无法验证枪口链路")
		if tree != null:
			tree.free()
		weapon.free()
		return
	var muzzle := weapon._muzzle
	if muzzle == null:
		_failures.append("调用方接线：武器未生成 muzzle 挂点")
		weapon.free()
		return
	# 挪到非原点，避免"位置恰好正确"的假绿。
	weapon.global_position = Vector3(3.0, 1.0, 5.0)
	weapon.global_rotation = Vector3(0.0, 0.6, 0.0)

	var before := pool.active_count(VfxPool3D.FX01_MUZZLE_FLASH)
	weapon.call("_spawn_muzzle_effect", self)
	var bucket: Array = pool._active.get(VfxPool3D.FX01_MUZZLE_FLASH, [])
	_samples += 1
	if bucket.is_empty() or bucket.size() != before + 1:
		_failures.append("调用方接线：枪口特效没进 VfxPool（%d -> %d）" % [before, bucket.size()])
		weapon.free()
		return
	var effect := bucket.back() as VfxEffectBase3D
	_expect(effect.call("has_follow_target"), "调用方接线：枪口特效未绑定 follow，角色一动就会残留")
	var spawn_drift := effect.global_position.distance_to(muzzle.global_position)
	_expect(spawn_drift < 0.01, "调用方接线：枪口特效生成位置偏离 muzzle 挂点 %.4f m" % spawn_drift)
	_expect(absf(effect.effect_size - WeaponModel3D.MUZZLE_FLASH_EFFECT_SIZE) < 0.0001,
		"调用方接线：枪口特效尺寸未取调用方基准 %.2f（实测 %.2f）"
		% [WeaponModel3D.MUZZLE_FLASH_EFFECT_SIZE, effect.effect_size])
	_expect(absf(WeaponModel3D.MUZZLE_FLASH_EFFECT_SIZE - 0.8) < 0.0001,
		"枪口花火尺寸基准不是业主定档的 80%%：%.2f" % WeaponModel3D.MUZZLE_FLASH_EFFECT_SIZE)

	# 真开火调用方还必须生成一枚弹壳，且从枪械右侧获得初速度。
	# ⚠️ `_spawn_shell_casing(shooter: Node3D)` 的类型是硬约束：传 Node 会让 `call` 抛
	#    SCRIPT ERROR 并**静默中断整个接线用例**（后续断言全不执行 ⇒ 假绿）。
	var flat_shooter := Node3D.new()
	add_child(flat_shooter)
	flat_shooter.global_position = Vector3(0.0, 0.0, 0.0)
	var shell_before := pool.active_count(VfxPool3D.FX01_SHELL_CASING)
	weapon.call("_spawn_shell_casing", flat_shooter)
	var shell_bucket: Array = pool._active.get(VfxPool3D.FX01_SHELL_CASING, [])
	_samples += 1
	_expect(shell_bucket.size() == shell_before + 1,
		"调用方接线：开火未生成弹壳（%d -> %d）" % [shell_before, shell_bucket.size()])
	if not shell_bucket.is_empty():
		var shell := shell_bucket.back() as VfxShellCasing3D
		# 业主 2026-09-22 口径：弹壳必须**出现在枪上**（抛壳挂点），不是跑到世界坐标去。
		var eject_socket := weapon.get("_ejection") as Node3D
		_expect(eject_socket != null, "调用方接线：枪械缺少抛壳挂点（EjectionSocket / 兜底挂点）")
		if eject_socket != null:
			var socket_drift := shell.global_position.distance_to(eject_socket.global_position)
			_expect(socket_drift < 0.001,
				"调用方接线：弹壳未出现在枪械抛壳挂点上（偏差 %.4f m）" % socket_drift)
		var shell_snapshot: Dictionary = shell.call("get_presentation_snapshot")
		var shell_velocity: Vector3 = shell_snapshot.get("velocity", Vector3.ZERO)
		var right_velocity := shell_velocity.dot(weapon.global_basis.x)
		_expect(right_velocity > 1.0,
			"调用方接线：弹壳未从枪械右侧抛出，右向速度 %.3f" % right_velocity)
		# 业主 2026-09-22 定档：弹壳缩到原基准的 80%，且该尺寸真落到已挂载几何上。
		_expect(absf(WeaponModel3D.SHELL_CASING_SIZE - EXPECTED_SHELL_SIZE) < 0.0001,
			"调用方弹壳尺寸基准不是业主定档的 %.2f：%.2f" % [EXPECTED_SHELL_SIZE, WeaponModel3D.SHELL_CASING_SIZE])
		var wired_scale: Vector3 = shell_snapshot.get("shell_scale", Vector3.ZERO)
		_expect(absf(wired_scale.x - EXPECTED_SHELL_SIZE) < 0.0001,
			"调用方接线：弹壳三件实际缩放不是 %.2f：%.4f" % [EXPECTED_SHELL_SIZE, wired_scale.x])
		var wired_radius := float(shell_snapshot.get("radius", -1.0))
		_expect(absf(wired_radius - EXPECTED_SHELL_BASE_RADIUS * EXPECTED_SHELL_SIZE) < 0.0001,
			"调用方接线：弹壳贴地半径未随 80%% 尺寸缩放：%.4f" % wired_radius)
		shell.call("_retire")

	# 非零楼层**端到端**（2026-09-22 实机缺陷「弹壳特效没了」的正面钉子）：
	# 塔楼楼层向下建（98F ≈ -1176 m）。把**枪与射击者一起**搬到该层开火，断言三件事：
	#   ① 弹壳出生在枪的抛壳挂点上（业主口径：挂在枪上，不是世界坐标）；
	#   ② 地面高度取射击者站立面（不是兜底 0）；
	#   ③ 跑满寿命后仍留在这一层 —— 绝不被瞬移到世界原点附近（那是实机"看不见"的症状）。
	var saved_weapon_pos := weapon.global_position
	weapon.global_position = Vector3(3.0, DEEP_FLOOR_Y + 1.0, 5.0)
	var deep_shooter := Node3D.new()
	add_child(deep_shooter)
	deep_shooter.global_position = Vector3(3.0, DEEP_FLOOR_Y, 5.0)
	var deep_before := pool.active_count(VfxPool3D.FX01_SHELL_CASING)
	weapon.call("_spawn_shell_casing", deep_shooter)
	var deep_bucket: Array = pool._active.get(VfxPool3D.FX01_SHELL_CASING, [])
	_samples += 1
	_expect(deep_bucket.size() == deep_before + 1,
		"调用方接线：非零楼层开火未生成弹壳（%d -> %d）" % [deep_before, deep_bucket.size()])
	if not deep_bucket.is_empty():
		var deep_shell := deep_bucket.back() as VfxShellCasing3D
		var deep_eject := weapon.get("_ejection") as Node3D
		if deep_eject != null:
			_expect(deep_shell.global_position.distance_to(deep_eject.global_position) < 0.001,
				"调用方接线：深层弹壳未出生在枪械抛壳挂点上")
		var deep_floor := float(deep_shell.call("get_presentation_snapshot").get("floor_y", 1.0e9))
		_expect(absf(deep_floor - DEEP_FLOOR_Y) < 0.0001,
			"调用方接线：弹壳地面高度未取射击者站立面（应 %.1f 实 %.1f）" % [DEEP_FLOOR_Y, deep_floor])
		# 跑 3 秒：必须始终留在该层，且精确贴在该层地面上。
		for index in range(1, 60):
			deep_shell.call("_on_tick", 0.02 + float(index) * 0.05, deep_shell.lifetime)
		var deep_radius := EXPECTED_SHELL_BASE_RADIUS * EXPECTED_SHELL_SIZE
		_expect(absf(deep_shell.global_position.y - (DEEP_FLOOR_Y + deep_radius)) < 0.01,
			"调用方接线：深层弹壳未落在该层地面：y=%.3f 期望 ≈%.3f"
			% [deep_shell.global_position.y, DEEP_FLOOR_Y + deep_radius])
		_expect(absf(deep_shell.global_position.y) > 100.0,
			"调用方接线：深层弹壳跑到世界原点附近（y=%.3f）" % deep_shell.global_position.y)
		deep_shell.call("_retire")
	deep_shooter.free()
	flat_shooter.free()
	weapon.global_position = saved_weapon_pos

	# 角色走动（武器跟着平移）⇒ 特效必须仍旧贴着 muzzle 挂点
	weapon.global_position += Vector3(0.0, 0.0, -6.0)
	effect.call("_process", 1.0 / 60.0)
	var drift := effect.global_position.distance_to(muzzle.global_position)
	_expect(drift < 0.01, "调用方接线：角色移动后枪口特效残留 %.4f m" % drift)

	effect.call("_retire")
	weapon.free()
	tree.free()


## —— 抛壳随机化回归（业主 2026-09-22）——
## 原话：「飞出去的弹壳，方向、高度、初始旋转位置、落地后的范围、旋转等数值都需要做一个随机。
##        不然太整齐了。」
##
## 随机化只许活在**调用方**（WeaponModel3D._spawn_shell_casing）：特效脚本对同一 context 必须逐位
## 可复现，否则本文件与视觉探针的逐帧断言会全部漂。所以本用例走真实调用方路径**连打 24 发**，
## 用统计口径断言散布：
##   ① 各分量极差（右向/抬升/前送/自旋）必须显著大于 0；
##   ② 初始倾角峰值必须接近 SHELL_INITIAL_TILT_DEG；
##   ③ 契约不破：**每一发**仍从枪械右侧抛出（右向速度 > 1.0）。
## 反面证据在本函数尾部：显式 context 的速度/自旋/姿态必须逐位等于传入值 ——
## 与 _check_shell_casing 的固定 velocity 用例互补，共同证明「随机化没有污染确定路径」。
func _check_shell_ejection_randomized() -> void:
	var pool := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	if pool == null:
		_failures.append("抛壳随机化：场景里找不到 vfx_pool_3d 池")
		return
	var weapon := SHELL_EJECT_WEAPON_SCENE.instantiate() as WeaponModel3D
	if weapon == null:
		_failures.append("抛壳随机化：武器模型场景根节点不是 WeaponModel3D")
		return
	add_child(weapon)
	var tree := BlueprintRegistry.build_weapon_tree(
		BlueprintRegistry.DEFAULT_STARTING_GUN_ID, "mod_bullet_standard"
	)
	if tree == null or not weapon.configure_from_tree(tree):
		_failures.append("抛壳随机化：出厂枪装配失败，无法验证抛壳随机化")
		if tree != null:
			tree.free()
		weapon.free()
		return
	# 挪到非原点、并给一个偏航角：随机化按**枪械局部基**施加 ⇒ 换枪姿态不该改变散布口径。
	# 若有人误把扰动写到世界轴上，这里的极差会在某个分量上塌掉。
	weapon.global_position = Vector3(1.0, 0.0, 2.0)
	weapon.global_rotation = Vector3(0.0, 0.5, 0.0)
	var right_axis := weapon.global_basis.x.normalized()
	var up_axis := weapon.global_basis.y.normalized()
	var forward_axis := (-weapon.global_basis.z).normalized()

	var shooter := Node3D.new()
	add_child(shooter)
	shooter.global_position = Vector3(1.0, 0.0, 2.0)

	var right_values := PackedFloat32Array()
	var up_values := PackedFloat32Array()
	var forward_values := PackedFloat32Array()
	var spin_values := PackedFloat32Array()
	var tilt_values := PackedFloat32Array()
	var distinct := {}
	var missed := 0
	for shot in range(EJECTION_SAMPLE_SHOTS):
		var before := pool.active_count(VfxPool3D.FX01_SHELL_CASING)
		weapon.call("_spawn_shell_casing", shooter)
		var bucket: Array = pool._active.get(VfxPool3D.FX01_SHELL_CASING, [])
		if bucket.size() != before + 1:
			missed += 1
			continue
		var shell := bucket.back() as VfxShellCasing3D
		var snapshot: Dictionary = shell.call("get_presentation_snapshot")
		var velocity: Vector3 = snapshot.get("velocity", Vector3.ZERO)
		# 用归一化局部基做点积 ⇒ 枪若被父节点缩放，也不污染判据。
		right_values.append(velocity.dot(right_axis))
		up_values.append(velocity.dot(up_axis))
		forward_values.append(velocity.dot(forward_axis))
		spin_values.append(float(snapshot.get("spin_speed", 0.0)))
		var spawn_basis: Basis = snapshot.get("spawn_basis", Basis.IDENTITY)
		tilt_values.append(rad_to_deg(spawn_basis.get_rotation_quaternion().get_angle()))
		distinct["%.5f|%.5f|%.5f" % [velocity.x, velocity.y, velocity.z]] = true
		shell.call("_retire")
	_samples += 1

	if missed > 0:
		_failures.append("抛壳随机化：连打 %d 发里有 %d 发没进 VfxPool" % [EJECTION_SAMPLE_SHOTS, missed])
	if right_values.size() < EJECTION_SAMPLE_SHOTS:
		_failures.append(
			"抛壳随机化：有效样本 %d 少于 %d，统计判据不成立（防假绿）"
			% [right_values.size(), EJECTION_SAMPLE_SHOTS]
		)
		weapon.free()
		shooter.free()
		return
	# 逐发速度必须两两不同：全等 ⇒ 根本没随机（或随机被写死）。
	_expect(distinct.size() >= EJECTION_SAMPLE_SHOTS - 1,
		"抛壳随机化：%d 发里只有 %d 个不同速度 ⇒ 弹壳仍完全一致" % [EJECTION_SAMPLE_SHOTS, distinct.size()])

	# 判据 ①：各分量极差。理论极差 = 基准 × 幅度 × 2，只要求观测到其中 EJECTION_SPAN_RATIO 倍。
	var right_range := _value_range(right_values)
	var up_range := _value_range(up_values)
	var forward_range := _value_range(forward_values)
	var spin_range := _value_range(spin_values)
	var right_span_min := EXPECTED_SHELL_EJECT_RIGHT_SPEED * EXPECTED_SHELL_EJECT_RIGHT_SPREAD * 2.0 * EJECTION_SPAN_RATIO
	var up_span_min := EXPECTED_SHELL_EJECT_UP_SPEED * EXPECTED_SHELL_EJECT_UP_SPREAD * 2.0 * EJECTION_SPAN_RATIO
	var forward_span_min := EXPECTED_SHELL_EJECT_FORWARD_JITTER * 2.0 * EJECTION_SPAN_RATIO
	var spin_span_min := EXPECTED_SHELL_EJECT_SPIN_SPEED * EXPECTED_SHELL_EJECT_SPIN_SPREAD * 2.0 * EJECTION_SPAN_RATIO
	_expect(right_range.y - right_range.x > right_span_min,
		"抛壳随机化：右向速度极差 %.3f 不足 %.3f（方向没随机，仍排成一条线）"
		% [right_range.y - right_range.x, right_span_min])
	_expect(up_range.y - up_range.x > up_span_min,
		"抛壳随机化：抬升速度极差 %.3f 不足 %.3f（高度没随机）"
		% [up_range.y - up_range.x, up_span_min])
	_expect(forward_range.y - forward_range.x > forward_span_min,
		"抛壳随机化：前送速度极差 %.3f 不足 %.3f（前后向没随机）"
		% [forward_range.y - forward_range.x, forward_span_min])
	_expect(spin_range.y - spin_range.x > spin_span_min,
		"抛壳随机化：自旋速度极差 %.3f 不足 %.3f（旋转没随机）"
		% [spin_range.y - spin_range.x, spin_span_min])
	# 判据 ②：初始姿态倾角峰值。理论最大 = SHELL_INITIAL_TILT_DEG，只要求观测到一半。
	_expect(_value_range(tilt_values).y > EXPECTED_SHELL_INITIAL_TILT_DEG * EJECTION_SPAN_RATIO,
		"抛壳随机化：初始倾角峰值 %.2f° 不足 %.2f°（初始姿态没随机）"
		% [_value_range(tilt_values).y, EXPECTED_SHELL_INITIAL_TILT_DEG * EJECTION_SPAN_RATIO])
	# 判据 ③：契约不破 —— 随机化的下界也不许把弹壳甩到枪身后方。
	_expect(right_range.x > 1.0,
		"抛壳随机化：有弹壳不再从枪械右侧抛出（最小右向速度 %.3f）" % right_range.x)
	print(
		"[vfx_toon_v002] shell ejection spread right=%.3f up=%.3f fwd=%.3f spin=%.3f tilt_max=%.2f"
		% [
			right_range.y - right_range.x, up_range.y - up_range.x,
			forward_range.y - forward_range.x, spin_range.y - spin_range.x,
			_value_range(tilt_values).y,
		]
	)

	# 常量钉死：调幅度是**刻意行为**，不是顺手改数 —— 改了就同步这里的期望值。
	var constant_pairs := [
		["右向基准速度", WeaponModel3D.SHELL_EJECT_RIGHT_SPEED, EXPECTED_SHELL_EJECT_RIGHT_SPEED],
		["抬升基准速度", WeaponModel3D.SHELL_EJECT_UP_SPEED, EXPECTED_SHELL_EJECT_UP_SPEED],
		["自旋基准速度", WeaponModel3D.SHELL_EJECT_SPIN_SPEED, EXPECTED_SHELL_EJECT_SPIN_SPEED],
		["右向抖动幅度", WeaponModel3D.SHELL_EJECT_RIGHT_SPREAD, EXPECTED_SHELL_EJECT_RIGHT_SPREAD],
		["抬升抖动幅度", WeaponModel3D.SHELL_EJECT_UP_SPREAD, EXPECTED_SHELL_EJECT_UP_SPREAD],
		["前送抖动幅度", WeaponModel3D.SHELL_EJECT_FORWARD_JITTER, EXPECTED_SHELL_EJECT_FORWARD_JITTER],
		["自旋抖动幅度", WeaponModel3D.SHELL_EJECT_SPIN_SPREAD, EXPECTED_SHELL_EJECT_SPIN_SPREAD],
		["初始倾角上限", WeaponModel3D.SHELL_INITIAL_TILT_DEG, EXPECTED_SHELL_INITIAL_TILT_DEG],
	]
	for entry in constant_pairs:
		_expect(absf(float(entry[1]) - float(entry[2])) < 0.0001,
			"抛壳%s不是定档值 %.3f：%.3f" % [String(entry[0]), float(entry[2]), float(entry[1])])

	# 反向对照：显式 context 路径必须**逐位确定**（随机化只许活在调用方）。
	# 这条同时说明上面的散布真来自随机，而不是快照读取噪声。
	var fixed := SHELL_SCENE.instantiate() as VfxShellCasing3D
	add_child(fixed)
	fixed.activate(Vector3.ZERO, Color.WHITE, 1.0, {
		"velocity": Vector3(1.8, 1.6, 0.0),
		"spin_axis": Vector3(0.7, 1.0, 0.0),
		"spin_speed": 18.0,
		"floor_y": 0.0,
	})
	var fixed_snapshot: Dictionary = fixed.call("get_presentation_snapshot")
	var fixed_velocity: Vector3 = fixed_snapshot.get("velocity", Vector3.ZERO)
	_expect(fixed_velocity.distance_to(Vector3(1.8, 1.6, 0.0)) < 0.0001,
		"反向对照失效：显式 context 的速度被改写为 (%.4f, %.4f, %.4f)"
		% [fixed_velocity.x, fixed_velocity.y, fixed_velocity.z])
	_expect(absf(float(fixed_snapshot.get("spin_speed", 0.0)) - 18.0) < 0.0001,
		"反向对照失效：显式 context 的自旋速度被改写为 %.4f" % float(fixed_snapshot.get("spin_speed", 0.0)))
	var fixed_basis: Basis = fixed_snapshot.get("spawn_basis", Basis.IDENTITY)
	_expect(rad_to_deg(fixed_basis.get_rotation_quaternion().get_angle()) < 0.0001,
		"反向对照失效：未给 initial_basis 时出生姿态不是恒等（倾角 %.4f°）"
		% rad_to_deg(fixed_basis.get_rotation_quaternion().get_angle()))
	fixed.free()
	weapon.free()
	shooter.free()
	tree.free()


## 取一列浮点的 (min, max)。返回 Vector2(min, max)；空列返回 ZERO。
## 极差统计用，避免为「求最值」把 24 个样本抄三遍。
func _value_range(values: PackedFloat32Array) -> Vector2:
	if values.is_empty():
		return Vector2.ZERO
	var min_value := values[0]
	var max_value := values[0]
	for value in values:
		min_value = minf(min_value, value)
		max_value = maxf(max_value, value)
	return Vector2(min_value, max_value)


func _report() -> void:
	if _samples < MIN_SAMPLES:
		_failures.append("防假绿哨兵：实际样本数 %d 少于预期 %d，验收未真正执行" % [_samples, MIN_SAMPLES])
	if _failures.is_empty():
		print("COMBAT_VFX_TOON_V002_OK: muzzle/impact/bullet toon v002 pass (samples=%d)" % _samples)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)
