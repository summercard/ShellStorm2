extends Node
## 战斗三类特效（枪口花火 / 命中爆点 / 飞行子弹）卡通 v002 专项验收。
## 覆盖：AssetID+版本元数据、灯光真相（OmniLight3D 名称/无阴影/范围/能量包络归零）、
##       前向与法线对齐（附反向对照证明断言有辨别力）、纯视觉不得含碰撞体、子弹拖尾落在弹体后方、
##       枪口花火挂点跟随（角色移动/转身时不得残留）与 effect_size 线性缩放。
## 只构建 mesh/material，不读 viewport 纹理 ⇒ 可安全 headless 运行。

const MUZZLE_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_muzzle_flash_root_top3d.tscn")
const IMPACT_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_impact_root_top3d.tscn")
const BULLET_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_bullet_visual_root_top3d.tscn")

const MUZZLE_ASSET_ID := "VFX-MUZZLE-FLASH-3D"
const IMPACT_ASSET_ID := "VFX-IMPACT-3D"
const BULLET_ASSET_ID := "VFX-BULLET-VISUAL-3D"
const EXPECTED_VERSION := "v002"
const MIN_SAMPLES := 9

var _failures: Array[String] = []
var _samples := 0


func _ready() -> void:
	_check_muzzle()
	_check_muzzle_follow()
	_check_muzzle_size_linear()
	_check_muzzle_caller_wiring()
	_check_impact()
	_check_bullet()
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


func _check_collision_free() -> void:
	var cases := [
		["枪口花火", MUZZLE_SCENE, {"forward": Vector3.FORWARD}],
		["命中爆点", IMPACT_SCENE, {"normal": Vector3.UP}],
		["飞行子弹", BULLET_SCENE, {}],
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

	# 角色走动（武器跟着平移）⇒ 特效必须仍旧贴着 muzzle 挂点
	weapon.global_position += Vector3(0.0, 0.0, -6.0)
	effect.call("_process", 1.0 / 60.0)
	var drift := effect.global_position.distance_to(muzzle.global_position)
	_expect(drift < 0.01, "调用方接线：角色移动后枪口特效残留 %.4f m" % drift)

	effect.call("_retire")
	weapon.free()
	tree.free()


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
