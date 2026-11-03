extends Node3D
## 远征03 场景雾验收：整关常驻基准雾值（距离雾 / 体积雾）必须落得住。
##
## 盯的是一条**隐形契约**：关卡级雾值一旦注入，就必须在本关**常驻**，
## 不允许被「进/出房间」的房型雾档重置逻辑抹回全塔基准。
##
## 历史缺陷（本用例的存在理由）：`TowerDescent3D.atmosphere_fog_density_override`
## 这个 export 早已存在，但它写入的 `_authored_*` 与「房型自带雾档」共用同一对变量，
## 而 `TowerAtmosphere3D.set_room_fog_profile({})`（空档 = 普通房）会把
## `_authored_*` 复位成 `-1`。于是关卡级值在 2 秒内消失，全项目 5 个远征场景
## 因此没有一处敢用它 —— 一条存在但从不生效的通道。
##
## 判据：
##   ① 装配完成后，画面上生效的两套雾值 == 目标值；
##   ② 经过一次「进有雾档房间 → 出房回普通」的完整往返后，仍 == 目标值；
##   ③ 体积雾的重放源 meta（`presentation_volumetric_fog_density`）与实值一致 ——
##      否则切画质会把浓度闪回全塔值。
##
## 运行：
##   godot --headless --path . --scene res://tests/verification/verify_expedition03_scene_fog.tscn

const LEVEL := preload("res://scenes/ExpeditionLevel03_3D.tscn")

## 2026-11-03 主人指定：远征03 常驻雾值。
const EXPECTED_DISTANCE := 0.0200
const EXPECTED_VOLUMETRIC := 0.0057
## 全塔基准（改前会塌回这里，作为失败情形的对照数字）。
const TOWER_FALLBACK_DISTANCE := 0.030
const TOWER_FALLBACK_VOLUMETRIC := 0.009

var failures: Array[String] = []
var checks := 0
var samples := 0


func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures.append(reason)
		printerr("SCENE_FOG_FAIL ", reason)


func settle(frames := 4) -> void:
	for i in frames:
		await get_tree().physics_frame
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	RuntimePerformanceManager.set_verification_frame_budget_override(60)
	var level := LEVEL.instantiate() as TowerDescent3D
	level.test_mode = true
	level.run_seed_override = 20261103
	add_child(level)
	for i in 24:
		await get_tree().process_frame

	var atmosphere: Node = level.get("_atmosphere")
	if atmosphere == null:
		check(false, "no TowerAtmosphere3D after assembly")
		_finish(level)
		return

	_read("after_assembly", level, atmosphere)

	# ①②「进有雾档房间 → 出房回普通」往返：模拟 Boss 房这类房间档进出。
	#    进房时房间档生效（这条只记录，不在期望值断言里）；
	#    出房后必须仍落在**本关常驻值**上，而不是全塔基准 —— 这才是本用例的核心判据。
	#    过渡时长：房间档显式给 0.2s；空档回落走 `transition_seconds` 默认 2.0s。
	atmosphere.call("set_room_fog_profile", {
		"distance_density": 0.015,
		"volumetric_density": 0.010,
		"transition_seconds": 0.2,
	})
	await get_tree().create_timer(0.5).timeout
	_read("inside_room_profile", level, atmosphere, false)
	atmosphere.call("set_room_fog_profile", {}, false)
	await get_tree().create_timer(2.6).timeout
	_read("after_leaving_room", level, atmosphere)

	# 玩家真实进一次房间，走 `_update_base_fog_transition` 的正式逐帧路径。
	var rooms: Array = level.get("_rooms")
	if rooms.is_empty():
		check(false, "level has no rooms")
	else:
		var room := rooms[0] as DungeonRoom3D
		room.ensure_shell_built()
		room.ensure_detail_built()
		level.player.global_position = room.to_global(Vector3(0.0, 0.2, 0.0))
		level.call("_refresh_physical_location_authority", true)
		level.call("_update_base_fog_transition", 0.0, true)
		await get_tree().create_timer(1.2).timeout
		_read("after_real_room_entry", level, atmosphere)

	_finish(level)


func _read(label: String, level: TowerDescent3D, atmosphere: Node, expect_level_value := true) -> void:
	var scene: Dictionary = atmosphere.call("get_scene_fog_snapshot")
	var snapshot: Dictionary = atmosphere.call("get_snapshot")
	var environment: Environment = level.world_environment.environment
	var distance := float(scene.get("distance", -1.0))
	var volumetric := float(scene.get("volumetric", -1.0))
	var meta_volumetric := float(environment.get_meta("presentation_volumetric_fog_density", -1.0))
	samples += 1
	print("SCENE_FOG %-24s distance=%.6f volumetric=%.6f meta_volumetric=%.6f base_blend=%.3f" % [
		label,
		distance,
		volumetric,
		meta_volumetric,
		float(snapshot.get("base_interior_fog_blend", -1.0)),
	])
	# 体积雾的重放源 meta 与实值必须一致 —— 否则切画质会把浓度闪回全塔值。
	# 这条对**所有**采样点成立，包括房间档生效期间。
	check(
		is_equal_approx(meta_volumetric, volumetric),
		"%s: replay meta %.6f != live %.6f" % [label, meta_volumetric, volumetric]
	)
	if not expect_level_value:
		return
	check(
		is_equal_approx(distance, EXPECTED_DISTANCE),
		"%s: distance %.4f != %.4f%s" % [
			label, distance, EXPECTED_DISTANCE,
			(" (塌回全塔基准 %.3f)" % TOWER_FALLBACK_DISTANCE)
			if is_equal_approx(distance, TOWER_FALLBACK_DISTANCE) else "",
		]
	)
	check(
		is_equal_approx(volumetric, EXPECTED_VOLUMETRIC),
		"%s: volumetric %.4f != %.4f%s" % [
			label, volumetric, EXPECTED_VOLUMETRIC,
			(" (塌回全塔基准 %.3f)" % TOWER_FALLBACK_VOLUMETRIC)
			if is_equal_approx(volumetric, TOWER_FALLBACK_VOLUMETRIC) else "",
		]
	)


func _finish(level: Node) -> void:
	level.queue_free()
	await settle()
	print("SCENE_FOG_RESULT ", JSON.stringify({
		"checks": checks,
		"failures": failures.size(),
		"samples": samples,
		"expected_distance": EXPECTED_DISTANCE,
		"expected_volumetric": EXPECTED_VOLUMETRIC,
	}))
	get_tree().quit(0 if failures.is_empty() else 1)
