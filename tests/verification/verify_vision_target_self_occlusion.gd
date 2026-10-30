extends Node
## 回归断言：交互设施不得被**自己**的碰撞体判成「被遮挡」。
##
## 缺陷现场（2026-10-30 业主报「房间中间有个空阻挡」）：
## `ServiceStation3D` 的 `StationBody` 挂 layer 1，与墙同层、属 `occlusion_mask`；
## `_is_occluded()` 的水平射线射向目标中心，第一下打中目标自己 ⇒ 恒判被遮挡 ⇒
## 整台 `visible = false`，但碰撞照挡。玩家看到一片空地，走过去撞墙。
##
## 本探针把两条判据都钉死：
##   ① 空地 + 设施 ⇒ 必须可见（防自遮挡回退）；
##   ② 空地 + 墙 + 设施 ⇒ 必须不可见（防「排除自身」把第三方遮挡物一起放过）。
##
## godot --headless --path . res://tests/verification/verify_vision_target_self_occlusion.tscn

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
const STATION_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_service_station_root_top3d.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 20261030
	add_child(dungeon)
	await get_tree().process_frame
	await get_tree().physics_frame

	var player := dungeon.player
	var vision := player.get_node_or_null("PlayerVision3D") as PlayerVision3D
	if vision == null:
		failures.append("PlayerVision3D 缺失，无法验证遮挡判定")
		_finish(failures)
		return
	# 挪到房间空地上，避开房间自带的墙和家具。
	var origin := player.global_position

	var station := STATION_SCENE.instantiate() as ServiceStation3D
	station.configure("upgrade", "武器改造台", Color(0.4, 0.82, 0.92))
	station.position = origin + Vector3(0, 0, -6.0)
	dungeon.add_child(station)
	await get_tree().process_frame
	await get_tree().physics_frame
	vision.force_refresh()
	if not station.visible:
		failures.append("空地上的改造台被判成被遮挡（自己挡住自己）⇒ 玩家会撞上看不见的实体")

	# 决定性对照：把自身碰撞层清零后应立刻可见，证明成因确实是自遮挡而非距离/灯光。
	var station_body := station.get_node_or_null("StationBody") as StaticBody3D
	if station_body == null:
		failures.append("改造台缺少 StationBody，实体体积约定被破坏")
	elif station.visible:
		station_body.collision_layer = 0
		vision.force_refresh()
		if not station.visible:
			failures.append("清零自身碰撞层后仍不可见 ⇒ 遮挡另有来源，自遮挡诊断不成立")
		station_body.collision_layer = 1
		vision.force_refresh()

	# ② 第三方遮挡物仍须生效：在玩家与设施之间立一堵墙。
	var wall := StaticBody3D.new()
	wall.name = "SelfOcclusionAcceptanceWall"
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = origin + Vector3(0, 1.0, -3.0)
	var wall_shape_node := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(6.0, 2.0, 0.4)
	wall_shape_node.shape = wall_shape
	wall.add_child(wall_shape_node)
	dungeon.add_child(wall)
	await get_tree().physics_frame
	vision.force_refresh()
	if station.visible:
		failures.append("墙后面的改造台仍然可见 ⇒ 排除自身碰撞体时把第三方遮挡物一起放过了")

	# ③ 事件终端本来就无实体体积（`ServiceStation3D` 对 event 不建 StationBody），
	#    不能因为它「没被挡」而掩盖其它设施的问题 —— 这里顺带核对该约定。
	var event_station := STATION_SCENE.instantiate() as ServiceStation3D
	event_station.configure("event", "异常信号终端", Color(0.9, 0.6, 0.3))
	event_station.position = origin + Vector3(3.0, 0, -1.5)
	dungeon.add_child(event_station)
	await get_tree().process_frame
	if event_station.get_node_or_null("StationBody") != null:
		failures.append("事件终端不应建实体体积（会留下透明阻挡）")

	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("VISION_TARGET_SELF_OCCLUSION_OK: 设施不再被自身碰撞盒遮挡，第三方遮挡仍生效")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
