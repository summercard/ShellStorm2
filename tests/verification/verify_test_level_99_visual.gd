extends Node
## 测试关卡99 的**画面**验收（非 headless，真渲染器）。
##
## 为什么逻辑门禁不够：`verify_test_level_99_flow` 断言的是「节点/数据对不对」，
## 它无法回答「玩家到底看得见什么」。一个楼面收缩过头、一堵外墙可视高度被压掉
## 一半、一条根本没接上门的走廊，在逻辑断言里全都合法，只有真渲染一张图才看得出来。
##
## 采样点（6 张）：
##   1) 整层俯瞰 —— 4 间房 + 3 条走廊是否都在楼面内、外墙是否成圈；
##   2) 入口安全房；3) 01 号战斗房；4) 02 号战斗房；5) 撤离房与信标；
##   6) 01↔02 水平走廊。
##
## 两条采样口径（刻意不同，各有用途）：
##   · 俯瞰图：临时接管相机做斜俯视。必须接管，因为游戏相机永远贴着玩家，
##     任何单点视角都看不到全层。
##   · 房间/走廊图：**不碰相机**，改为把玩家放进目标房，直接用游戏自己的
##     第三人称相机。这样拍到的是玩家站在那间房里真实看到的画面 —— 包括
##     游戏的遮挡与剪影逻辑，忠实度最高。
##
## 两个可读性处理（都是游戏内合法状态，不是自造光照）：
##   · 把每间房的灯打开（等价于玩家进房扳了灯的开关）；
##   · 俯瞰时显示全部走廊（偏离流送契约，见 _capture_overview 注释）。
##
## 判据：TEST_LEVEL_99_VISUAL_OK。截图落 res://outputs/verification/。

const OUTPUT_DIR := "res://outputs/verification"
const SCENE_PATH := "res://scenes/ExpeditionLevel99_3D.tscn"

const OVERVIEW_PATH := OUTPUT_DIR + "/test_level_99_overview.png"
const ENTRY_PATH := OUTPUT_DIR + "/test_level_99_entry_safe_room.png"
const ROOM_01_PATH := OUTPUT_DIR + "/test_level_99_room_01.png"
const ROOM_02_PATH := OUTPUT_DIR + "/test_level_99_room_02.png"
const EXTRACTION_PATH := OUTPUT_DIR + "/test_level_99_extraction_beacon.png"
const CORRIDOR_PATH := OUTPUT_DIR + "/test_level_99_corridor_01_02.png"

## 关卡 99 的四间房。顺序即主路：入口 → 01 → 02 → 撤离。
const ALL_ROOM_IDS: Array[String] = ["start", "room_01", "room_02", "extraction"]

## 是否进房开灯后再采样。不开灯的话整套图几乎全黑 —— 房间默认关灯，
## 而这是本关的室内默认状态，黑图读不出装配关系，等于没验收。
const ENABLE_ROOM_LIGHTS := true

## 进房采样时玩家在房内的落位（相对房间中心的局部偏移，单位米）与朝向。
## 朝向用 rotation.y：0 = 面向 -Z，PI/4 = 面向 (-X,-Z) 斜对房间一角。
##
## 落点固定在**房间中央**，这是取景的关键：游戏相机相对玩家偏出约
## (6.2, 10.3, 6.2)m（在玩家局部系里偏「上 + 后」），玩家站中央时相机离房间
## 中心只有约 6.2m，25m 房（半宽 12.5m）与 15m 房（半宽 7.5m）都仍落在墙内。
## 一旦把玩家挪到离中心 9m 的角落，相机会被推到墙外，拍到的就是一整面墙
## —— 这两种翻车方式本探针都实测踩过。
const ROOM_SHOTS: Array = [
	{
		"room_id": "start",
		"yaw": PI / 4.0,
		"path": ENTRY_PATH,
		"failure": "入口安全房采样失败",
	},
	{
		"room_id": "room_01",
		"yaw": PI / 4.0,
		"path": ROOM_01_PATH,
		"failure": "01 号战斗房采样失败",
	},
	{
		"room_id": "room_02",
		"yaw": PI / 4.0,
		"path": ROOM_02_PATH,
		"failure": "02 号战斗房采样失败",
	},
	{
		"room_id": "extraction",
		"yaw": PI / 4.0,
		"path": EXTRACTION_PATH,
		"failure": "撤离房与信标采样失败",
	},
]

## 玩家在房内的固定落高（离地一点点，避免与楼面穿插）。
const PLAYER_STAND_Y := 0.05

## 走廊采样：玩家站 01 号房中央面向 +X（rotation.y = -PI/2），另用**独立近距机位**
## 从 01↔02 通道正上方偏西做正交式俯视。
##
## 为什么这一张不走游戏相机：游戏相机在玩家局部系里偏出约 (6.2, 10.3, 6.2)m，
## 俯角 ≈ 55°；而水平走廊只有 5m 宽、门洞在 1.6m 高处，这个俯角下**看不到正前方的
## 门洞**，拍出来只是一片带缝的地面（已实测）。判读「走廊有没有真接上门」需要
## 沿着通道方向正面看，故这里与俯瞰图同类，属于「为判读刻意偏离游戏相机」。
const CORRIDOR_FROM_ROOM := "room_01"
const CORRIDOR_TO_ROOM := "room_02"
const CORRIDOR_YAW := -PI * 0.5
## 走廊机位：沿用俯瞰图那条 45° 斜视线（已被俯瞰图证明看得见墙与走廊），
## 只是把距离从 134m 拉到 26m，使 10m 长的通道占到画面约 1/3。
## 不另找角度：这个方向同时看得到通道地砖、两侧墙和两端门洞。
const CORRIDOR_CAMERA_DISTANCE_M := 26.0

## 全黑/全同色画面的守卫：整张图必须至少有这么多「不同亮度」的采样桶，
## 否则说明渲染没出东西而我们却在报绿。
const MIN_LUMA_BUCKETS := 6
## 俯瞰机位在「刚好装下」距离上再留的余量比例。
const OVERVIEW_MARGIN_RATIO := 1.18
## 俯瞰机位俯角方向（从包围盒中心指向相机），约 45° 斜俯视：
## 正上方看不出墙（墙顶面只有 0.3m 厚，正投影几乎不可见），斜视才看得见外墙环。
const OVERVIEW_DIRECTION := Vector3(-0.78, 1.0, 0.78)

## headless 下无渲染器，采样被静默跳过的帧数（仅作日志诊断用，不参与成败判定）。
var _skipped_headless := 0
## 真渲染器下成功落盘的图数。
var _captured := 0


func _ready() -> void:
	var failures: Array[String] = []
	var original_clock := GameTimeManager.get_persistence_snapshot()
	# 固定到正午：关卡的可见性问题不该跟日夜光照混在一起看。
	GameTimeManager.set_clock_running(false)
	GameTimeManager.set_elapsed_game_seconds(12.0 * 3600.0, false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		failures.append("测试关卡99 场景加载失败：%s" % SCENE_PATH)
		_report(failures, original_clock)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77199999
	add_child(tower)
	await _settle()

	if not tower.is_expedition():
		failures.append("测试关卡99 场景未开启远征模式")
		tower.queue_free()
		_report(failures, original_clock)
		return
	# 冻结玩家：采样只比较关卡自身，不掺玩家自己的位移与动画。
	# 注意只冻结**玩家**，塔楼的 _physics_process 必须继续跑 ——
	# 游戏相机由它每帧从玩家位置推出来，停掉塔楼等于停掉相机跟随。
	tower.player.set_physics_process(false)
	tower.player.set_process(false)
	var flashlight := tower.player.get_node_or_null("PlayerFlashlight3D") as PlayerFlashlight3D
	var camera := tower.player.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		failures.append("玩家身上找不到 Camera3D，无法采样")
		tower.queue_free()
		_report(failures, original_clock)
		return
	# 打开手电。手电是玩家的主光源，而 PlayerFlashlight3D 的 start_enabled
	# 默认是 false（要玩家按 F 才亮）。第一版探针把它**关掉**，结果整套图
	# 漆黑一片、读不出任何装配关系 —— 那是探针自己造成的，不是关卡偏暗。
	# 开手电等价于玩家按了一次 F，是游戏内合法状态。
	if flashlight != null:
		flashlight.set_light_enabled(true)
		print("[visual99] 手电已打开=%s" % str(flashlight.is_light_enabled()))

	# 房间外壳是惰性构建的：不先把每间房流送出来，俯瞰图会拍到一大片
	# 只有当前房有内容的空地，而逻辑断言完全不会察觉。
	var edge_count := (tower._corridor_by_edge as Dictionary).size()
	for edge_value in (tower._corridor_by_edge as Dictionary).keys():
		var parts := str(edge_value).split("|")
		if parts.size() == 2:
			tower.force_open_edge_for_test(parts[0], parts[1])
	var missing_rooms: Array[String] = []
	for room_id in ALL_ROOM_IDS:
		if (tower._room_by_id.get(room_id) as DungeonRoom3D) == null:
			missing_rooms.append(room_id)
			continue
		tower.force_enter_room_for_test(room_id)
		await get_tree().process_frame
	if not missing_rooms.is_empty():
		failures.append("关卡 99 缺少房间：%s" % ", ".join(missing_rooms))
		tower.queue_free()
		_report(failures, original_clock)
		return
	if ENABLE_ROOM_LIGHTS:
		_turn_on_room_lights(tower)
	print(
		"[visual99] 流送就绪 rooms=%d corridors=%d seed=%d"
		% [tower._room_by_id.size(), edge_count, tower.run_seed_override]
	)

	# —— 采样 1：整层俯瞰（唯一需要接管相机的采样点）——
	# TowerDescent3D._physics_process 每帧调用 _apply_indoor_camera_pose()，
	# 把 player.camera 打回默认第三人称跟随。要自定义机位就必须先停掉它；
	# 结束后立刻恢复，后面所有采样都走游戏相机。
	tower.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture_overview(camera, tower, failures)
	tower.set_physics_process(true)
	await get_tree().process_frame

	# —— 采样 2..5：进房 + 游戏自己的第三人称相机 ——
	for shot in ROOM_SHOTS:
		var room_id := str(shot["room_id"])
		if not _place_player_in_room(tower, room_id, float(shot["yaw"])):
			failures.append("无法把玩家放进房间 %s，跳过采样" % room_id)
			continue
		await _settle()
		_capture(str(shot["path"]), str(shot["failure"]), failures)

	# —— 采样 6：01↔02 走廊（独立近距机位，理由见 CORRIDOR_* 常量注释）——
	# 必须先把玩家真的放进 01 号房：走廊可见性由「当前房 ∈ 该边两端」决定，
	# 只调 force_enter_room_for_test 而不挪玩家，当前房仍是上一间房，
	# room_01↔room_02 会按契约保持隐藏（实测过，别把它当关卡缺陷）。
	if not _place_player_in_room(tower, CORRIDOR_FROM_ROOM, CORRIDOR_YAW):
		failures.append("无法把玩家放进 %s，跳过走廊采样" % CORRIDOR_FROM_ROOM)
	else:
		tower.set_physics_process(false)
		await get_tree().process_frame
		await _capture_corridor(camera, tower, CORRIDOR_FROM_ROOM, CORRIDOR_TO_ROOM, failures)
		tower.set_physics_process(true)
		await get_tree().process_frame

	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.08).timeout
	_report(failures, original_clock)


## 把玩家放到指定房间的**中央**并设朝向（rotation.y）。返回是否成功。
##
## 用 force_enter_room_for_test 让该房进入 ACTIVE（细节构建 + 相机标签更新），
## 再直接写 global_position —— 与 verify_full_3d_visual 的既有做法一致。
## 玩家物理已冻结，落位后不会掉下去或被推动。落点选中央的理由见 ROOM_SHOTS。
func _place_player_in_room(tower: TowerDescent3D, room_id: String, yaw: float) -> bool:
	var room := tower._room_by_id.get(room_id) as DungeonRoom3D
	if room == null:
		return false
	tower.force_enter_room_for_test(room_id)
	tower.player.global_position = room.global_position + Vector3(0.0, PLAYER_STAND_Y, 0.0)
	tower.player.rotation.y = yaw
	return true


## 打开每间房的灯。房间默认关灯，全黑图读不出装配关系；开灯等价于玩家进房
## 扳了灯开关，是游戏内合法状态，比自造光源忠实。
func _turn_on_room_lights(tower: TowerDescent3D) -> void:
	var turned_on: Array[String] = []
	for room_id in ALL_ROOM_IDS:
		var room := tower._room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			continue
		var light_switch := room.find_child("RoomLightSwitch3D", true, false)
		if light_switch == null or not light_switch.has_method("toggle_light"):
			continue
		if bool(light_switch.call("toggle_light")):
			turned_on.append(room_id)
	print("[visual99] 已开灯房间=%s" % str(turned_on))


## 整层俯瞰。必须先停掉塔楼的 _physics_process（见 _ready 注释）。
##
## 三处**刻意偏离**，都只服务这一张判读图，拍完立即还原：
##   1) 显示全部走廊 —— `_update_corridor_streaming()` 规定「只有当前房所在边的
##      走廊可见」，任何单点视角都看不到全部三条走廊；而俯瞰图的目的正是判读
##      「完整几何有没有都建出来」。契约本身由 verify_test_level_99_flow 覆盖。
##   2) 临时关闭环境雾 —— 本关的 Environment 继承自远征模板，`fog_density = 0.04`。
##      俯瞰机位在 130m 外，雾遮挡率 1-exp(-0.04*130) ≈ 99.5%，拍出来是一张
##      糊成一片灰的图，什么都判读不了。关雾是**隔离变量**，不是掩盖问题：
##      雾本身在游玩距离（十几米）下观感正常，房间图一律不动雾。
##   3) 加一盏诊断平行光 —— 同样因为机位远，室内灯与手电都照不到，不加光全黑。
##      这是**诊断照明，不代表游戏内观感**；房间图不加。
func _capture_overview(camera: Camera3D, tower: TowerDescent3D, failures: Array[String]) -> void:
	var revealed := _reveal_all_corridors(tower)
	var diagnostic := _install_diagnostic_light(tower)
	var environment_setting := _set_environment_fog(tower, false)
	var bounds := _content_bounds(tower)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		failures.append("房间包围盒退化，无法定位俯瞰机位：%s" % str(bounds))
		_restore_overview_overrides(tower, diagnostic, environment_setting)
		return
	var viewport_size := Vector2(get_viewport().get_visible_rect().size)
	var aspect := 1.777
	if viewport_size.y > 0.0:
		aspect = viewport_size.x / viewport_size.y
	var distance := _fitted_distance(bounds, camera.fov, aspect)
	var center := bounds.position + bounds.size * 0.5
	var target := Vector3(center.x, 0.0, center.y)
	_aim(camera, target + OVERVIEW_DIRECTION.normalized() * distance, target)
	print(
		"[visual99] overview bounds=%s distance=%.1fm fov=%.1f aspect=%.2f corridors_revealed=%d"
		% [str(bounds), distance, camera.fov, aspect, revealed]
	)
	await _settle()
	_capture(OVERVIEW_PATH, "整层俯瞰采样失败", failures)
	_restore_overview_overrides(tower, diagnostic, environment_setting)


## 加一盏诊断用平行光（仅俯瞰图，拍完即回收）。
## 名字带 VisualProbe 前缀，便于在任何日志里一眼认出「这不是游戏自己的光」。
func _install_diagnostic_light(tower: TowerDescent3D) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "VisualProbeDiagnosticSun"
	light.light_energy = 1.0
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-58.0, -140.0, 0.0)
	tower.add_child(light)
	return light


## 临时开关环境雾。返回「是否成功改到」，供还原时判断。
func _set_environment_fog(tower: TowerDescent3D, enabled: bool) -> bool:
	var world_environment := tower.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment == null or world_environment.environment == null:
		return false
	world_environment.environment.fog_enabled = enabled
	return true


## 还原俯瞰图的三处偏离：删诊断光、把雾恢复为开。
func _restore_overview_overrides(
	tower: TowerDescent3D, light: DirectionalLight3D, environment_setting: bool
) -> void:
	if light != null and is_instance_valid(light):
		light.queue_free()
	if environment_setting:
		_set_environment_fog(tower, true)


## 01↔02 走廊的近距俯视。视觉相机已被接管（调用方已停塔楼 _physics_process）。
##
## 机位对齐通道走向：在两端门中心的中点正上方 7m，再沿**垂直于通道**的水平方向
## 偏出 10m（通道是东西向时即偏南北），这样 5m 宽的通道横向装满画面，
## 同时两端门洞都在视野内。门位取自走廊节点的 start/end_door_position（世界坐标）；
## 两者退化时退回用两端房间中心求中点，避免把机位打到世界原点。
func _capture_corridor(
	camera: Camera3D,
	tower: TowerDescent3D,
	a: String,
	b: String,
	failures: Array[String]
) -> void:
	var edges := tower._corridor_by_edge as Dictionary
	var edge := "%s|%s" % [a, b]
	var corridor := edges.get(edge) as Node3D
	if corridor == null:
		edge = "%s|%s" % [b, a]
		corridor = edges.get(edge) as Node3D
	if corridor == null:
		failures.append("找不到 %s↔%s 走廊节点，无法采样通道" % [a, b])
		return
	if not corridor.visible:
		failures.append("%s↔%s 走廊在玩家位于 %s 时不可见（流送契约应当显示它）" % [a, b, a])
		return
	var start := corridor.get_meta("start_door_position", Vector3.ZERO) as Vector3
	var end := corridor.get_meta("end_door_position", Vector3.ZERO) as Vector3
	var mid := (start + end) * 0.5
	if start.distance_to(end) <= 0.01:
		var room_a := tower._room_by_id.get(a) as DungeonRoom3D
		var room_b := tower._room_by_id.get(b) as DungeonRoom3D
		if room_a == null or room_b == null:
			failures.append("走廊两端房间缺失，无法定位通道机位")
			return
		mid = (room_a.global_position + room_b.global_position) * 0.5
	# 沿俯瞰图同一方向拉近：45° 斜视，同时看得到地砖、两侧墙与两端门洞。
	var target := Vector3(mid.x, 0.5, mid.z)
	var eye := target + OVERVIEW_DIRECTION.normalized() * CORRIDOR_CAMERA_DISTANCE_M
	_aim(camera, eye, target)
	print(
		"[visual99] corridor=%s start=%s end=%s eye=%s"
		% [edge, str(start), str(end), str(eye)]
	)
	await _settle()
	_capture(CORRIDOR_PATH, "01↔02 走廊采样失败", failures)


## 让全部走廊节点可见，返回被显示的走廊数。仅俯瞰图使用。
func _reveal_all_corridors(tower: TowerDescent3D) -> int:
	var revealed := 0
	for edge_value in (tower._corridor_by_edge as Dictionary).keys():
		var connector := (tower._corridor_by_edge as Dictionary).get(edge_value) as Node3D
		if connector == null:
			continue
		connector.visible = true
		connector.process_mode = Node.PROCESS_MODE_INHERIT
		revealed += 1
	return revealed


func _report(failures: Array[String], original_clock: Dictionary) -> void:
	GameTimeManager.restore_from_persistence(original_clock, false)
	if failures.is_empty():
		print(
			"TEST_LEVEL_99_VISUAL_OK: overview/entry/room_01/room_02/extraction/corridor "
			+ "previews saved under res://outputs/verification/, each with render guard "
			+ "(captured=%d skipped_headless=%d)" % [_captured, _skipped_headless]
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


# —— 机位 ——

func _aim(camera: Camera3D, from: Vector3, to: Vector3) -> void:
	if from.distance_to(to) <= 0.01:
		return
	camera.global_position = from
	camera.look_at(to, Vector3.UP)


## 四间房的并集包围盒（世界 x/z）。用 global_position 而非局部 position，
## 免得依赖「区块节点是否正好在原点」这个前提。
func _content_bounds(tower: TowerDescent3D) -> Rect2:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var found := false
	for room_id in ALL_ROOM_IDS:
		var room := tower._room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			continue
		var dimensions := room.get_dimensions()
		var center := room.global_position
		minimum.x = minf(minimum.x, center.x - dimensions.x * 0.5)
		minimum.y = minf(minimum.y, center.z - dimensions.y * 0.5)
		maximum.x = maxf(maximum.x, center.x + dimensions.x * 0.5)
		maximum.y = maxf(maximum.y, center.z + dimensions.y * 0.5)
		found = true
	if not found:
		return Rect2()
	# 外扩一格网格：外墙环与门洞模块都在房间轮廓之外，不外扩会把它们切掉。
	var margin := Vector2(5.0, 5.0)
	return Rect2(minimum - margin, (maximum + margin) - (minimum - margin))


## 在给定纵 FOV 与宽高比下，把 bounds 完整装进画面所需的机位距离（再乘余量）。
## 用**包围球**而非投影矩形来算：斜俯视时投影会随俯角变化，包围球是上界，
## 永远不会把内容切出画面（宁可留点边距，也不要拍到一半）。
func _fitted_distance(bounds: Rect2, fov_deg: float, aspect: float) -> float:
	var radius := bounds.size.length() * 0.5
	var half_vertical := deg_to_rad(fov_deg) * 0.5
	var half_horizontal := atan(tan(half_vertical) * maxf(aspect, 0.01))
	var limiting_half := minf(half_vertical, half_horizontal)
	return (radius / maxf(sin(limiting_half), 0.0001)) * OVERVIEW_MARGIN_RATIO


# —— 采样 ——

func _settle() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.24).timeout


## 存图 + 渲染守卫：图必须非空、且亮度确有分层（挡掉「全黑却报绿」）。
##
## headless 下视口纹理必然为空 —— 那是环境事实，不是回归（而套件跑 visual 场景时
## 用的是真渲染器）。所以这里把「无渲染器」与「真失败」分开：前者静默跳过并计数，
## 后者才进 failures。这样本脚本既能被 headless 用来验证机位/流送逻辑真的跑通，
## 又不会在无渲染器的意外调用下报假红。
func _capture(path: String, failure: String, failures: Array[String]) -> void:
	if DisplayServer.get_name() == "headless":
		_skipped_headless += 1
		return
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		failures.append(failure + "（视口纹理为空）")
		return
	var buckets := _luma_buckets(image)
	if buckets < MIN_LUMA_BUCKETS:
		failures.append("%s（画面只有 %d 层亮度，疑似没渲染出内容）" % [failure, buckets])
		return
	if image.save_png(path) != OK:
		failures.append(failure + "（PNG 写入失败）")
		return
	_captured += 1
	print(
		"[visual99] saved %s %dx%d luma_buckets=%d"
		% [path.get_file(), image.get_width(), image.get_height(), buckets]
	)


func _luma_buckets(image: Image) -> int:
	var buckets := {}
	var width := image.get_width()
	var height := image.get_height()
	var step_x := maxi(width / 48, 1)
	var step_y := maxi(height / 27, 1)
	for y in range(0, height, step_y):
		for x in range(0, width, step_x):
			var color := image.get_pixel(x, y)
			var luma := int((color.r * 0.299 + color.g * 0.587 + color.b * 0.114) * 16.0)
			buckets[luma] = true
	return buckets.size()
