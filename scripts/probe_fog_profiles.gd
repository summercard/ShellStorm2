extends Node
## 探针：把「雾气」在四个语境下的**实际运行时数值**打出来（距离雾 + 体积雾 + 颜色）。
##
## 业主问：「体积雾的数值 boss 和外面的差距是多少？主塔的是多少」
## 答数不能靠读常量推断 —— 体积雾的最终值经过三层：TowerAtmosphere3D 常量 →
## 基地室内插值 → 房间 `fog_profile` 覆盖，且被 GraphicsSettingsManager 按画质重放。
## 所以实例化各场景、**等收敛后**读 `Environment.volumetric_fog_density` 与
## 自己写的 `presentation_volumetric_fog_density` meta（后者是重放源，两者必须一致）。
##
## 四个语境：
##   ① 主塔（TowerDescent3D，塔内非基地）        —— 主塔基准
##   ② 远征01 普通区域（start 房，无雾档）        —— 远征普通
##   ③ 远征99 Boss 房（有 `metadata/fog_profile`）—— Boss 房
##   ④ 主塔 · 99F 基地壳体内                     —— 把玩家放进基地，让**真判定**驱动
##
## ⚠️ 三个坑（本次全踩过）：
##   (a) **必须等雾过渡跑完再读**。房间档是 2 秒 tween、基地档是 0.55 s 响应指数；
##       没等就得到夹在中间的数（实测 0.008753 / 0.003823），看起来像「改没生效」。
##   (b) **进房后要调 `_refresh_physical_location_authority` + `_update_base_fog_transition`**，
##       只 `_on_room_entered` 不会把雾档推给大气（实测原地不动 0.030/0.009）。
##   (c) **手感强制 `update_base_interior_fog(true, 0, true)` 会被逐帧逻辑覆盖回去**
##       （玩家不在基地里 ⇒ 下一帧就往 0 衰减）。要么同一帧内读，要么把玩家放进基地。
##
## 运行：
##   export APPDATA='C:\tmp\ss2_appdata_fogprof'
##   "<godot-console>" --headless --path "<project>" \
##     --scene res://scripts/probe_fog_profiles.tscn

const TOWER_SCENE: PackedScene = preload("res://scenes/TowerDescent3D.tscn")
const EXP01_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const EXP99_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel99_3D.tscn")
## 房间雾 tween 2 s、基地雾响应 0.55 s（1.65 s 到 95%）；留余量。
const SETTLE_SECONDS := 3.0

var _root: Window


func _ready() -> void:
	_root = get_tree().root
	call_deferred("probe")


func probe() -> void:
	await _measure(TOWER_SCENE, "main_tower_outdoor", "", false)
	await _measure(EXP01_SCENE, "expedition_01_ordinary", "start", false)
	await _measure(EXP99_SCENE, "expedition_99_boss_room", "boss", false)
	await _measure(TOWER_SCENE, "main_tower_base99_interior", "facility", true)
	print("FOG_PROFILES_DONE")
	get_tree().quit(0)


func _measure(scene: PackedScene, label: String, room_id: String, interior: bool) -> void:
	var tower: TowerDescent3D = scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 20260919
	_root.add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var env: Environment = tower.world_environment.environment
	if tower._atmosphere == null:
		print("FOGPROF %-26s <无 atmosphere>" % label)
		tower.free()
		await get_tree().process_frame
		return
	var room_profile: Dictionary = {}
	if not room_id.is_empty():
		var room: DungeonRoom3D = tower._room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			print("FOGPROF %-26s <无房间 %s>" % [label, room_id])
			tower.free()
			await get_tree().process_frame
			return
		room.ensure_shell_built()
		room.ensure_detail_built()
		# 落点必须在该房**实有走面**上，否则 `_refresh_physical_location_authority` 会把
		# `_current_room_id` 判到别处，逐帧逻辑随即用空档把雾恢复成普通值（实测症状：
		# 明明读到 profile 有值、等 3 秒后却回到 0.030/0.009）。Boss 房心是深井空洞，
		# 站不住 —— 用高位平台 (0,12.2,45)，与 `probe_boss_room02_level99` 同一落点。
		var stand_local := Vector3(0.0, 12.2, 45.0) if room_id == "boss" else Vector3(0.0, 0.2, 0.0)
		tower.player.global_position = room.to_global(stand_local)
		tower._refresh_physical_location_authority(true)
		if room_id == "boss":
			tower._on_room_entered(room)
		tower._update_base_fog_transition(0.0, false)
		room_profile = room.get_meta("fog_profile", {}) as Dictionary
		print("FOGPROF %-26s current_room=%s inside_facility=%s" % [
			label, str(tower._current_room_id), str(tower.is_player_inside_facility()),
		])
	# 等雾过渡收敛。
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	print("FOGPROF %-26s distance=%.6f volumetric=%.6f meta_volumetric=%.6f color=%s profile=%s" % [
		label,
		env.fog_density,
		float(env.get("volumetric_fog_density")),
		float(env.get_meta("presentation_volumetric_fog_density", -1.0)),
		var_to_str(env.fog_light_color),
		"有" if not room_profile.is_empty() else "无",
	])
	if not room_profile.is_empty():
		print("FOGPROF %-26s profile=%s" % [label, str(room_profile)])
	tower.free()
	await get_tree().process_frame
	await get_tree().process_frame
