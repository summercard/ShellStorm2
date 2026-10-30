extends Node
## 远征03 全量怪物「体型」实测（2026-10-30）。
##
## 起因：业主「还有只怪物太小了，好像是用了小僵尸的模型做了分裂的怪物，怪物不用这么小。
## 可以用其它模型」。
##
## 靠肉眼只能猜"哪只小"，不能回答"小到什么程度、比值多少、跟碰撞体积对不对得上"。
## 所以这里逐只量四个数：
##   ① 借用资产（`PROXY_ASSET_KIND`）—— 决定它**长得像谁**
##   ② 根节点 `scale`（含族内体型倍率）—— 决定它**多大**
##   ③ 碰撞柱半径 / 高度 —— 玩法口径（能不能被打到、能不能挤过缝）
##   ④ **视觉高度 / 玩家身高 的比值** —— 唯一能跨怪比较的尺度
##
## ④ 是最关键的判据：`scale=0.40` 本身不说明问题，但它乘上小僵尸的模型高度之后
## 得到的世界高度如果只有玩家的 1/3，玩家就会觉得"这是个虫子，不是我该认真对待的怪"。
##
## 用法：godot --headless --path . --scene res://tools/_egt_enemy_size_probe.tscn

const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const PLAN_PATH := "res://data/level_plans/expedition_03/level_plan.json"

## 玩家身高（米）。用来做"怪有多大"的参照系 —— 玩家是唯一恒定的尺度锚。
## 取自 `Player3D` 的胶囊高度（见 `verify_player3d_animation_flow` 的断言）。
const PLAYER_HEIGHT_M := 1.8

## 业主裁定「太小的下限」（2026-10-30）：
##   「怪物不用这么小」—— 一只怪不该小于玩家身高的这个比例。
## 取 0.55：低于它读起来像"小动物/虫子"，而不是"会开枪的敌人"。
## EGT 原作里 Blobin（最小分裂体）目测约为玩家的 1/2 高，所以 0.55 略高于原作最低值，
## 但那是美术口径差异（原作是圆团，占屏面积大；我们的占位是缩小的人形，缩到同样高度会显得更小）。
const MIN_HEIGHT_RATIO := 0.55

## flow 关卡的门洞净宽（与 `FloorPlanGenerator.FLOW_DOOR_OPENING_M` 同值）。
## 碰撞柱直径超过它就"看得见、走不过门"—— 比"太小"更严重，因为那是硬卡死。
const DOOR_OPENING_M := 2.2
## 直径上限留 15% 余量：门扇是双开推门、实际净宽略小，且贴边过门还要算 `safe_margin`。
const MAX_DIAMETER_RATIO := 0.85

var _rows: Array[Dictionary] = []
var _failures: Array[String] = []


func _ready() -> void:
	print("=== EGT_ENEMY_SIZE_PROBE 全量怪物体型 ===")
	var injector: MonsterInjector = preload("res://src/map/MonsterInjector.gd").new()
	var kinds: Array[String] = []
	for kind in injector.BASE_ENEMY_TYPES.keys():
		if str(kind).begins_with("egt_"):
			kinds.append(str(kind))
	kinds.sort()

	for kind in kinds:
		_measure(injector, kind)

	_print_table()
	_verify()
	_finish()


func _measure(injector: MonsterInjector, kind: String) -> void:
	var data: Dictionary = injector.generate_box_enemy(kind, 1, 1)
	if data.is_empty():
		_failures.append("%s 无法生成" % kind)
		return
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	if enemy == null:
		_failures.append("%s 预制体实例化失败" % kind)
		return
	add_child(enemy)
	enemy.configure_from_enemy_data(data)

	# 视觉高度：碰撞柱高度 × 根节点 scale。碰撞柱是按"实际模块化模型的最大横向轮廓"
	# 定过口径的（见 `FOOTPRINT_PROFILES`），所以它是视觉高度的可靠代理 ——
	# 比去量 mesh AABB 稳（模型是拼装的，AABB 会被附件撑大）。
	var profile_height := 0.0
	var profile_radius := 0.0
	if enemy.collision_shape != null and enemy.collision_shape.shape is CylinderShape3D:
		var cyl := enemy.collision_shape.shape as CylinderShape3D
		profile_height = cyl.height
		profile_radius = cyl.radius
	var world_height := profile_height * maxf(enemy.scale.y, 0.01)
	_rows.append({
		"kind": kind,
		"asset": EnemyAvatar3D.resolve_asset_kind(kind),
		"scale": float(enemy.scale.y),
		"profile_h": profile_height,
		"profile_r": profile_radius,
		"world_h": world_height,
		"ratio": world_height / PLAYER_HEIGHT_M,
		# 碰撞柱是子节点 ⇒ 世界半径 = 局部半径 × 根节点 scale。
		"world_r": profile_radius * maxf(enemy.scale.y, 0.01),
	})
	enemy.queue_free()


func _print_table() -> void:
	print("\n%-24s %-14s %6s %7s %7s %7s %7s %s"
		% ["怪", "借用资产", "scale", "碰撞高", "世界高", "玩家比", "碰撞直径", "判定"])
	for row in _rows:
		var ratio := float(row["ratio"])
		var diameter := float(row["world_r"]) * 2.0
		var verdict := ""
		if ratio < MIN_HEIGHT_RATIO:
			verdict = "**过小**"
		if diameter > DOOR_OPENING_M * MAX_DIAMETER_RATIO + 0.01:
			verdict += " **过不了门**"
		print("%-24s %-14s %6.2f %7.2f %7.2f %6.2f× %7.2f %s"
			% [str(row["kind"]), str(row["asset"]), float(row["scale"]),
			   float(row["profile_h"]), float(row["world_h"]), ratio, diameter, verdict])


func _verify() -> void:
	var door_limit := DOOR_OPENING_M * MAX_DIAMETER_RATIO
	for row in _rows:
		if float(row["ratio"]) < MIN_HEIGHT_RATIO:
			_failures.append(
				"%s 视觉高度 %.2fm = 玩家的 %.2f 倍（下限 %.2f）—— 借用 %s，scale=%.2f"
				% [str(row["kind"]), float(row["world_h"]), float(row["ratio"]),
				   MIN_HEIGHT_RATIO, str(row["asset"]), float(row["scale"])]
			)
		var diameter := float(row["world_r"]) * 2.0
		# 0.01 容差：夹到上限的怪直径恰好等于 door_limit，浮点会让 `>` 误报。
		if diameter > door_limit + 0.01:
			_failures.append(
				"%s 碰撞直径 %.2fm 超过可通行上限 %.2fm（门洞 %.1fm × %.2f）—— 会「看得见、走不过门」"
				% [str(row["kind"]), diameter, door_limit, DOOR_OPENING_M, MAX_DIAMETER_RATIO]
			)


func _finish() -> void:
	if _failures.is_empty():
		print("\nEGT_ENEMY_SIZE_PROBE_OK 全部怪物体型都在下限之上")
		get_tree().quit(0)
		return
	print("\nEGT_ENEMY_SIZE_PROBE_FAIL 共 %d 项：" % _failures.size())
	for line in _failures:
		print("  - %s" % line)
	get_tree().quit(1)
