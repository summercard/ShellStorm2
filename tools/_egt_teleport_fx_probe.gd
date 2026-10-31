extends Node3D

## 瞬移「消失 / 出现」反馈特效的验收（2026-10-31）。
##
## 业主要求：「带有瞬移还有位移的一些怪物，出现消失的那个位置需要有一些反馈特效」。
## 这个探针回答三件事，缺一件都不能算做完：
##
##   ① **资产层**：两件 Prefab 真的注册进了 `VfxPool3D`，且几何/时长/不投影符合口径；
##   ② **表现层**：两件的**时间方向真的相反** —— OUT 的环必须由大收小、
##      IN 的环必须由小炸开。只测"能实例化"是测不出这个的（两件共用同一个脚本，
##      把 `mode` 判反了照样实例化成功，但视觉上变成"消失时炸开"）；
##   ③ **链路层**：怪物真的瞬移时，**原点与落点各播一件**。
##      这里踩过的坑是"常量拼对了、Prefab 做好了，但代码里没人调用" ——
##      枪法师的 `blink.on_attack` 就静默失效过整整两天。
##
## 反向自测：把 `_play_teleport_fx` 里任一行的 AssetID 换成不存在的 id，
## ① ③ 会同时报红；把 `mode` 判反，② 报红。

const ENEMY_SCENE: PackedScene = preload(
	"res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
)
const VFX_POOL: GDScript = preload("res://src/vfx/VfxPool3D.gd")

const OUT_ID := "VFX-TELEPORT-OUT-3D"
const IN_ID := "VFX-TELEPORT-IN-3D"
## 两件的目标时长（秒）。OUT 更短：消失要"快、脆"，出现要留一点"成形"的余韵。
const EXPECTED_OUT_LIFETIME := 0.22
const EXPECTED_IN_LIFETIME := 0.26
## 瞬移的单次距离下限（`_blink_to_random(6.0)` 至少要走这么远，否则不算"位移"）。
const MIN_BLINK_DISTANCE := 0.5

var _failures: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	_build_floor()
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check_registered()
	var out_snap := _check_prefab(OUT_ID, "out", EXPECTED_OUT_LIFETIME)
	var in_snap := _check_prefab(IN_ID, "in", EXPECTED_IN_LIFETIME)
	_check_opposite_direction(out_snap, in_snap)
	await _check_blink_chain()
	await _check_vanish_chain()

	if _failures.is_empty():
		print("EGT_TELEPORT_FX_PROBE_OK  瞬移消失/出现特效已贯通「注册→预制件→怪物位移」三层")
		await _drain_pool()
		get_tree().quit(0)
	else:
		print("EGT_TELEPORT_FX_PROBE_FAIL  共 %d 项：" % _failures.size())
		for line in _failures:
			print("  - ", line)
		await _drain_pool()
		get_tree().quit(1)


## 退出前把池里的活跃特效全部收掉。
##
## 不这么做会留 `ObjectDB instances leaked at exit` + `N resources still in use`
## —— 那正是验收套件判 **exit 4（退出时资源泄漏）** 的形态。探针自己制造的泄漏
## 不该由套件去背，也不该让它把"真红"淹没在噪音里。
func _drain_pool() -> void:
	var pool := _find_pool()
	if pool == null:
		return
	var active: Dictionary = pool.get("_active") as Dictionary
	for asset_id in active.keys():
		for effect in (active[asset_id] as Array).duplicate():
			if is_instance_valid(effect):
				(effect as VfxEffectBase3D).finish()
	await get_tree().process_frame
	# 场地与测试怪也显式收掉：`queue_free` 排到帧末，而 `quit()` 不会等最后一帧，
	# 残留节点会在退出报告里变成 `ObjectDB instances leaked`。
	for child in get_children():
		if is_instance_valid(child):
			child.free()
	await get_tree().process_frame


func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	add_child(body)


# ─────────────────────────── ① 资产层 ───────────────────────────

func _check_registered() -> void:
	for asset_id in [OUT_ID, IN_ID]:
		if not VFX_POOL.has_effect(asset_id):
			_failures.append("%s 没有注册进 VfxPool3D._REGISTRY" % asset_id)
		var probe: Node = VFX_POOL.create_unpooled(asset_id)
		if probe == null:
			_failures.append("%s 实例化失败（Prefab 路径或根节点类型不对）" % asset_id)
		else:
			# ⚠ 试完必须立即 `free()`。只丢弃引用不会回收 —— 它是 Node，
			# 会以「Leaked instance: Node3D - Node path: (空)」的形式出现在退出报告里，
			# 连带 `resources still in use: VfxTeleport3D.gd`。本项目验收套件把
			# 退出时的资源泄漏算红（exit 4），探针自己制造的泄漏必须先自己收干净。
			probe.free()
	# 常量与字符串必须一致：账本、Prefab metadata、调用方三方靠它对齐。
	if VFX_POOL.FX01_TELEPORT_OUT != OUT_ID:
		_failures.append("VfxPool3D.FX01_TELEPORT_OUT 常量值不是 %s" % OUT_ID)
	if VFX_POOL.FX01_TELEPORT_IN != IN_ID:
		_failures.append("VfxPool3D.FX01_TELEPORT_IN 常量值不是 %s" % IN_ID)


func _check_prefab(asset_id: String, expected_mode: String, expected_lifetime: float) -> Dictionary:
	var effect: VfxEffectBase3D = VFX_POOL.create_unpooled(asset_id)
	if effect == null:
		_failures.append("%s 无法实例化，跳过预制件检查" % asset_id)
		return {}
	add_child(effect)
	effect.activate(Vector3.ZERO, Color(0.62, 0.42, 1.0, 1.0), 1.0)
	var snap: Dictionary = effect.get_presentation_snapshot()
	if str(snap.get("mode", "")) != expected_mode:
		_failures.append(
			"%s 的 mode 是 %s，期望 %s（判反会让消失时炸开）"
			% [asset_id, str(snap.get("mode", "?")), expected_mode]
		)
	if absf(float(snap.get("lifetime", 0.0)) - expected_lifetime) > 0.02:
		_failures.append(
			"%s 时长 %.3fs，期望 %.2fs" % [asset_id, float(snap.get("lifetime", 0.0)), expected_lifetime]
		)
	if int(snap.get("streak_count", 0)) < 4:
		_failures.append("%s 竖丝只有 %d 根，读不出\"能量抽离\"" % [asset_id, int(snap.get("streak_count", 0))])
	if bool(snap.get("has_light", true)):
		_failures.append("%s 挂了灯：瞬移是高频件，不该带光" % asset_id)
	if bool(snap.get("casts_shadow", true)):
		_failures.append("%s 还在投影（cast_shadow 没关）" % asset_id)
	if not bool(effect.get_meta("asset_id", "") == asset_id):
		_failures.append("%s 的 Prefab metadata/asset_id 与 AssetID 不一致" % asset_id)
	# 记下 t=0.02 与 t=0.90 两个时刻的环半径，交给方向判定
	var sample := {}
	for t_ratio in [0.02, 0.90]:
		effect._on_tick(expected_lifetime * t_ratio, expected_lifetime)
		sample[t_ratio] = float(effect._ring.scale.x)
	effect.finish()
	remove_child(effect)
	# 用 `free()` 立即销毁而不是 `queue_free()`：后者要等帧末，
	# 而本函数是同步跑完的 ⇒ 探针退出时它还在 ObjectDB 里，会打印
	# `ObjectDB instances leaked at exit`，把真正的红项淹掉。
	effect.free()
	return {"asset": asset_id, "early": sample[0.02], "late": sample[0.90]}


## ② 表现层：两件的时间方向必须相反。
func _check_opposite_direction(out_snap: Dictionary, in_snap: Dictionary) -> void:
	if out_snap.is_empty() or in_snap.is_empty():
		return
	if not (float(out_snap["early"]) > float(out_snap["late"])):
		_failures.append(
			"%s 的环在收拢？实测 %.3f → %.3f（应递减）"
			% [OUT_ID, float(out_snap["early"]), float(out_snap["late"])]
		)
	if not (float(in_snap["early"]) < float(in_snap["late"])):
		_failures.append(
			"%s 的环在炸开？实测 %.3f → %.3f（应递增）"
			% [IN_ID, float(in_snap["early"]), float(in_snap["late"])]
		)


# ─────────────────────────── ③ 链路层 ───────────────────────────

func _make_enemy(kind: String) -> Enemy3D:
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	if enemy == null:
		_failures.append("敌人 Prefab 根节点不是 Enemy3D，无法测链路")
		return null
	enemy.enemy_kind = kind
	add_child(enemy)
	enemy.global_position = Vector3(0.0, 0.05, 0.0)
	return enemy


func _check_blink_chain() -> void:
	var enemy := _make_enemy("egt_hollowpoint")
	if enemy == null:
		return
	# 贴地出生后要等它稳定：`_physics_process` 把首帧位置记成 `_home_position`。
	for _i in range(20):
		await get_tree().physics_frame
	if not is_instance_valid(enemy) or enemy.ai_state == "dead":
		_failures.append("egt_hollowpoint 没能活到瞬移测试（AI 一出生就死了）")
		return
	var origin := enemy.global_position
	var out_before: int = enemy._teleport_fx_out_count
	var in_before: int = enemy._teleport_fx_in_count
	enemy._blink_to_random(6.0)
	var landed := enemy.global_position
	var moved := Vector2(landed.x - origin.x, landed.z - origin.z).length()
	if moved < MIN_BLINK_DISTANCE:
		_failures.append("瞬移没有真的位移（%.2f m）：这条链路测不下去" % moved)
	if enemy._teleport_fx_out_count - out_before != 1:
		_failures.append("瞬移时没有播「消失」特效（计数 +%d）" % (enemy._teleport_fx_out_count - out_before))
	if enemy._teleport_fx_in_count - in_before != 1:
		_failures.append("瞬移时没有播「出现」特效（计数 +%d）" % (enemy._teleport_fx_in_count - in_before))
	# 池子里真的能看到这两件的活跃实例（而不是只有计数器在动）。
	await get_tree().process_frame
	var pool: Node = _find_pool()
	if pool != null:
		var out_live: Array = (pool.get("_active") as Dictionary).get(OUT_ID, [])
		var in_live: Array = (pool.get("_active") as Dictionary).get(IN_ID, [])
		if out_live.is_empty():
			_failures.append("VfxPool3D 的 %s 活跃桶是空的：特效被丢弃了" % OUT_ID)
		if in_live.is_empty():
			_failures.append("VfxPool3D 的 %s 活跃桶是空的：特效被丢弃了" % IN_ID)
	else:
		_failures.append("场景里没有 VfxPool3D 单例（group=vfx_pool_3d）")
	print("  链路: 位移 %.2f m，消失特效 +1、出现特效 +1" % moved)
	enemy.queue_free()
	await get_tree().process_frame


func _check_vanish_chain() -> void:
	var enemy := _make_enemy("egt_keybullet_kin")
	if enemy == null:
		return
	for _i in range(20):
		await get_tree().physics_frame
	if not is_instance_valid(enemy):
		_failures.append("egt_keybullet_kin 一出生就失效")
		return
	var out_before: int = enemy._teleport_fx_out_count
	enemy._vanish()
	if enemy._teleport_fx_out_count - out_before != 1:
		_failures.append(
			"`_vanish()` 没播「消失」特效（计数 +%d）" % (enemy._teleport_fx_out_count - out_before)
		)
	if enemy.ai_state != "dead":
		_failures.append("`_vanish()` 之后 ai_state 仍是 %s，期望 dead" % enemy.ai_state)
	print("  链路: 原地消失（`_vanish`）播了「消失」特效，且按设计判死")
	if is_instance_valid(enemy):
		enemy.queue_free()
	await get_tree().process_frame


func _find_pool() -> Node:
	var pools: Array = get_tree().get_nodes_in_group("vfx_pool_3d")
	return pools[0] if not pools.is_empty() else null
