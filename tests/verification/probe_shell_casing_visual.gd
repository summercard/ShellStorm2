extends Node
## 弹壳「模拟弹出 / 抛物掉落 / 模拟碰撞 / 躺平静止」的**画面**核对（非 headless，真渲染器）。
##
## 为什么数值门禁不够：verify_combat_vfx_toon_v002 已经覆盖了运动学（触地次数、逐帧不穿地、
## 静止躺平、尺寸落到几何、无物理 API）。但它答不了「这动画看起来对不对」：
##   阶段缺失（一落地就躺下、没有弹跳过程）、
##   姿态错（弹壳尖头插进地里 / 立着不倒）、
##   缩小没生效或缩过头（数值只证明 scale=0.8，不证明画面上真的小了一圈）。
## 这些只有真渲染一张图才看得出来。
##
## 本探针刻意**不依赖任何物理碰撞体**（弹壳本来就是程序化模拟落地）：
## 场景里只有一块无碰撞的地板 MeshInstance3D，弹壳按 context.floor_y 自行落地。
## 万一有人把物理碰撞塞回脚本 —— 这张图里弹壳会直接穿过地板掉下去，一眼可见。
##
## 四张机位：
##   1) shell_phases.png：四个**同一门炮、不同时刻**的弹壳并排（侧视）。
##      每枚从各自起点出发，被手动步进到 t = 0.15 / 0.42 / 0.67 / 2.00 s，
##      分别对应「上升中 / 抛物下落中 / 刚触地挤压 / 已躺平静止」四个阶段。
##   2) shell_size_ab.png：0.8（业主定档）与 1.0（旧基准）两枚**静止躺平**的弹壳同框特写。
##      判据之一是把两者的世界包络经**真相机投影**成屏幕像素高度，比值必须 ≈ 0.8。
##   3) shell_deep_floor.png：98F（世界 y ≈ -1176）深度上「飞行中 / 已静止」两枚。
##      2026-09-22 实机缺陷「弹壳特效没了」的可视回归。
##   4) shell_casing_spread.png：连发 8 发的落点俯视图 —— 业主「不然太整齐了」的画面证据。
##      走**真实调用方**路径（WeaponModel3D._spawn_shell_casing），并复刻业主截图里的连发摆头；
##      判据是「落点离最远两点连线的最大垂直偏差」必须显著大于 0（纯弧线排列时该值 ≈ 8mm）。
##
## 图落 res://outputs/verification/。

const SHELL_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_shell_casing_root_top3d.tscn")

const OUTPUT_DIR := "res://outputs/verification"
const PHASES_PATH := OUTPUT_DIR + "/shell_casing_phases.png"
const SIZE_AB_PATH := OUTPUT_DIR + "/shell_casing_size_ab.png"
const DEEP_FLOOR_PATH := OUTPUT_DIR + "/shell_casing_deep_floor.png"

## 塔楼 98F 的世界 y（`TowerGeometry3D.FLOOR_HEIGHT_M(12.0) × 98`，楼层向下建 ⇒ 负值）。
## 2026-09-22 实机缺陷「弹壳特效没了」就出在这个深度上：floor_y 被兜底成 0 ⇒
## 弹壳出生即"低于地面"、第一帧被夹到世界原点附近 ⇒ 玩家什么都看不见。
const DEEP_FLOOR_Y := -1176.0

const SHELL_COLOR := Color(0.92, 0.56, 0.16)
## 与 WeaponModel3D 一致的出厂抛壳参数（探针独立硬编码，不读调用方常量以免自证）。
const EJECTION_VELOCITY := Vector3(2.1, 1.55, 0.0)
const SPAWN_HEIGHT := 1.2
const SPIN_AXIS := Vector3(0.72, 1.0, 0.0)
const SPIN_SPEED := 20.0

## 弹壳径向半展（外部真源）：三件里最大者 = 底缘 TorusMesh outer_radius 0.058。
const SHELL_BASE_RADIUS := 0.058

## 业主 2026-09-22 定档：弹壳缩到原基准的 80%。
const SMALL_SIZE := 0.8
const LEGACY_SIZE := 1.0

## 阶段切片：每枚弹壳被步进到的模拟时刻（秒）与它在场景里的 X 起点。
## 起点间距 2.4m > 最大弹道水平位移（2.1×2.0 ≈ 4.2m 中的前 2 枚不会互相压住）——
## 因此把时刻自小到大排列、X 起点也自小到大，画面里不会有遮挡。
const PHASES := [
	{"seconds": 0.15, "origin_x": 0.0, "label": "0.15s 上升"},
	{"seconds": 0.42, "origin_x": 1.7, "label": "0.42s 下落"},
	{"seconds": 0.67, "origin_x": 3.4, "label": "0.67s 触地"},
	{"seconds": 2.00, "origin_x": 5.1, "label": "2.00s 静止"},
]
const PHASE_MAX_DRIFT := 2.2
## 尺寸 A/B 特写：两枚躺平静止弹壳的 X 位置（间距 = 弹壳长度 + 余量，不粘连）。
const SIZE_AB_SMALL_X := -0.30
const SIZE_AB_LEGACY_X := 0.30

## 判据容差：投影像素高度比必须落在 0.8 × (1 ± 0.12) 内。
const SIZE_RATIO_EXPECTED := 0.8
const SIZE_RATIO_TOLERANCE := 0.12
## 防假绿：画面亮度分层少于该值说明根本没渲出内容。
const MIN_LUMA_BUCKETS := 3

# ---------------------------------------------------------------- 机位 4：连发散布

## 业主 2026-09-22：「飞出去的弹壳，方向、高度、初始旋转位置、落地后的范围、旋转等数值
## 都需要做一个随机。不然太整齐了。」——本机位是这条要求的**画面证据**。
const SPREAD_PATH := OUTPUT_DIR + "/shell_casing_spread.png"
## 连发发数与每发的枪械偏航（模拟后坐摆头）。
## 摆头正是业主截图里「整齐弧线」的来源：枪转了、弹壳口径却没变 ⇒ 弹壳沿一条弧排开。
## 8 发 × 1.7° 覆盖 ±6°：落点弧长 ≈ 1.5m × 12° ≈ 0.31m —— 弧不短，但仍在**同一条线附近**。
const SPREAD_SHOTS := 8
const SPREAD_YAW_START_DEG := -6.0
const SPREAD_YAW_STEP_DEG := 1.7
## 枪的握持高度（米）。弹壳从枪上抛出、落到脚底地面（floor_y = 射击者站立面 = 0）。
const SPREAD_GUN_HEIGHT := 1.1
## 相机：在落点形心上方 1.8m、向后 1.1m 俯视（俯角 ≈ 59°）⇒ 镜头距 ≈ 2.1m，fov 50 覆盖约 2.0m 宽。
## 这个距离是量出来的：弹壳长 0.15m，在 2.1m 处约占 55px（1280 宽画幅），姿态一眼可辨；
## 而 8 发落点的最大间距实测 0.45 ~ 1.15m，仍完整落在画幅内。
## ⛔ 不能正上方 90° 俯视：`look_at` 的 up 向量与视线平行会直接报错；
##    而且垂直俯视下躺平的弹壳只剩一个小圆点，姿态全被压掉。
const SPREAD_CAM_HEIGHT := 1.8
const SPREAD_CAM_BACK := 1.1
## 「不再是一条整齐弧线」的门槛（米）= 落点到「最远两点连线」的最大垂直偏差。
## 纯摆头（无随机）时 8 个落点几乎同弧 ⇒ 偏差 ≈ 8mm 量级（半径 1.5m、±6° 的弧偏离其弦的量级）；
## 随机化生效后方向/高度/前送各自抖 ⇒ 偏差在 0.1 ~ 0.4m 量级。门槛取 0.10m 居中。
const SPREAD_MIN_RESIDUAL := 0.10

var _failures: Array[String] = []
var _captured := 0
var _skipped_headless := 0
var _step_seconds := 1.0 / 60.0
## 连发散布机位用的装配树（Node，不会自动回收）：探针结束时显式 free，避免退出时报孤节点。
var _spread_tree: Node = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var environment_setting := _install_environment()
	_install_ground()
	await get_tree().process_frame

	var camera := _install_camera()
	await _settle()

	await _shoot_phases(camera)
	camera.queue_free()
	await get_tree().process_frame

	var ab_camera := _install_size_ab_camera()
	await _settle()
	await _shoot_size_ab(ab_camera)
	ab_camera.queue_free()
	await get_tree().process_frame

	var deep_camera := _install_deep_camera()
	await _settle()
	await _shoot_deep_floor(deep_camera)
	deep_camera.queue_free()

	var spread_camera := _install_camera()
	spread_camera.name = "ShellProbeSpreadCamera"
	spread_camera.fov = 50.0
	await _settle()
	await _shoot_spread(spread_camera)
	spread_camera.queue_free()

	if environment_setting != null and is_instance_valid(environment_setting):
		environment_setting.queue_free()
	await get_tree().process_frame
	_report()


# ---------------------------------------------------------------- 机位 1：阶段切片

func _shoot_phases(camera: Camera3D) -> void:
	var shells: Array[VfxShellCasing3D] = []
	var origins: Array[Vector3] = []
	for entry in PHASES:
		var origin := Vector3(float(entry["origin_x"]), SPAWN_HEIGHT, 0.0)
		var shell := _spawn_shell(origin, SMALL_SIZE)
		if shell == null:
			return
		_advance(shell, float(entry["seconds"]))
		shells.append(shell)
		origins.append(origin)
	# 判据 1：每枚都必须朝 +X 飞出去（与出厂抛壳方向一致），否则就是弹道/朝向坏了。
	for index in shells.size():
		var drift := shells[index].global_position.x - origins[index].x
		if drift <= 0.05:
			_failures.append(
				"阶段 %s：弹壳未向 +X 抛出（位移 %.3f m）" % [str(PHASES[index]["label"]), drift]
			)
		# 判据 2：水平位移不得超过总飞行预算 —— 超过说明积分把累计时间当 dt 重复算了。
		if drift > PHASE_MAX_DRIFT:
			_failures.append(
				"阶段 %s：水平位移 %.3f m 超出预算 %.1f m（疑似重复积分）"
				% [str(PHASES[index]["label"]), drift, PHASE_MAX_DRIFT]
			)
	# 判据 3：前三个阶段必须还在空中/贴地附近，最后一个必须已躺平静止 —— 阶段不能塌缩成同一状态。
	var heights := PackedFloat32Array()
	for shell in shells:
		heights.append(shell.global_position.y)
	if heights[0] <= heights[1] or heights[1] <= heights[3] + 0.05:
		_failures.append(
			"阶段高度序列不合预期（应 上升 > 下落 > 静止）：%s" % str(heights)
		)
	var last_snapshot: Dictionary = shells[3].call("get_presentation_snapshot")
	if not bool(last_snapshot.get("settled", false)):
		_failures.append("2.00s 的弹壳仍未静止（phase=%d）" % int(last_snapshot.get("phase", -1)))
	# 判据 4：静止的弹壳必须躺平（长轴水平）。
	if absf(shells[3].global_transform.basis.y.y) > 0.001:
		_failures.append(
			"静止弹壳未躺平（长轴 Y 分量 %.4f）" % shells[3].global_transform.basis.y.y
		)
	# 判据 5：整段过程中没有任何一枚低于地板 —— 画面里不该出现"弹壳陷进地里/掉下去"。
	var ground_floor := SHELL_BASE_RADIUS * SMALL_SIZE
	for index in shells.size():
		if shells[index].global_position.y < ground_floor - 0.001:
			_failures.append(
				"阶段 %s：弹壳低于地面（y=%.4f < %.4f）"
				% [str(PHASES[index]["label"]), shells[index].global_position.y, ground_floor]
			)
	print("[shell_probe] phase heights=%s" % str(heights))
	for index in shells.size():
		print(
			"[shell_probe] phase[%d] %s pos=%s"
			% [index, str(PHASES[index]["label"]), str(shells[index].global_position)]
		)

	# ⚠️ 机位必须在运动平面（X-Y，z=0）的**正侧方、近水平**：把相机架到斜上方会让
	# 世界高度差被透视压扁 —— 实测 0.856m 的高度差在斜视机位下只剩 1.4px（读图读不出来），
	# 而正侧方机位下同一差值有 118px。判据 6 就是盯这件事的。
	_aim(camera, Vector3(3.6, 0.95, 5.0), Vector3(3.6, 0.55, 0.0))
	await _settle()
	# 判据 6：屏幕纵序必须与世界高度一致 —— 保证出图时三个阶段从高到低确实分开，
	# 而不是挤成一条线（首版 2.4m 间距 + 远机位就把它们压到几乎同高，肉眼读不出来）。
	var screen_y := PackedFloat32Array()
	for shell in shells:
		screen_y.append(camera.unproject_position(shell.global_position).y)
	print("[shell_probe] phase screen_y=%s" % str(screen_y))
	if screen_y[1] - screen_y[0] < 5.0:
		_failures.append(
			"阶段投影未拉开：上升(%.1f) 与 下落(%.1f) 屏幕高度差不足 5px" % [screen_y[0], screen_y[1]]
		)
	if screen_y[2] - screen_y[1] < 5.0:
		_failures.append(
			"阶段投影未拉开：下落(%.1f) 与 触地(%.1f) 屏幕高度差不足 5px" % [screen_y[1], screen_y[2]]
		)
	_capture(PHASES_PATH, "弹壳阶段切片采样失败")
	for shell in shells:
		shell.queue_free()


# ---------------------------------------------------------------- 机位 2：尺寸 A/B

func _shoot_size_ab(camera: Camera3D) -> void:
	# ⚠️ 两枚必须是**原地落下**再量：首版沿用了出厂抛壳初速度，结果两枚各自横向飞走
	#    （落在 x≈2.1 / 2.9），相机在 x=0 朝 -Z 看就把它俩甩出了画面 ——
	#    而 unproject_position 对屏幕外的点照样返回数字，投影比 0.798 依旧"通过"，
	#    出图却是一张空图。故此处给零水平初速度（只保留下落），并靠判据 9 看住取景。
	var small := _spawn_shell(Vector3(SIZE_AB_SMALL_X, SPAWN_HEIGHT, 0.0), SMALL_SIZE, Vector3(0.0, 0.8, 0.0))
	var legacy := _spawn_shell(Vector3(SIZE_AB_LEGACY_X, SPAWN_HEIGHT, 0.0), LEGACY_SIZE, Vector3(0.0, 0.8, 0.0))
	if small == null or legacy == null:
		return
	# 两枚都跑到静止躺平，再同框比较 —— 只有在同一姿态下量尺寸才有意义。
	# 两枚共用同一 spin_axis/spin_speed 与同一固定步长序列 ⇒ 终态朝向完全一致，
	# 画面里不会出现「一枚正对镜头被透视缩短」的假差异。
	_advance(small, 2.4)
	_advance(legacy, 2.4)
	# 判据 6：两枚都必须已静止躺平，否则量的是飞行姿态，比值无意义。
	for pair in [[small, "0.8"], [legacy, "1.0"]]:
		var shell := pair[0] as VfxShellCasing3D
		var snapshot: Dictionary = shell.call("get_presentation_snapshot")
		if not bool(snapshot.get("settled", false)):
			_failures.append("尺寸 A/B：%s 弹壳未静止，无法比较尺寸" % str(pair[1]))
	# 零水平初速度 ⇒ 必须原地落下，横向漂移应为 0（否则上面那句"原地"就不成立）。
	var small_drift := absf(small.global_position.x - SIZE_AB_SMALL_X)
	var legacy_drift := absf(legacy.global_position.x - SIZE_AB_LEGACY_X)
	print("[shell_probe] size_ab drift small=%.4f legacy=%.4f" % [small_drift, legacy_drift])
	if small_drift > 0.02 or legacy_drift > 0.02:
		_failures.append(
			"尺寸 A/B：弹壳未原地落下（横向漂移 %.4f / %.4f）" % [small_drift, legacy_drift]
		)

	# 特写机位按两枚的**实际**位置取中，避免用硬编码机位（它们一旦被改就又被甩出画面）。
	# 机位压到弹壳高度附近（仅高出 ~0.1m）⇒ 近处地面进入画面下缘，才能看出「贴地」而不是悬空。
	var focus := (small.global_position + legacy.global_position) * 0.5
	_aim(camera, Vector3(focus.x, focus.y + 0.10, 0.78), Vector3(focus.x, focus.y * 0.78, focus.z))
	await _settle()
	_capture(SIZE_AB_PATH, "弹壳尺寸 A/B 采样失败")
	_assert_grounded(camera, small, "尺寸 A/B 0.8 弹壳")
	_assert_grounded(camera, legacy, "尺寸 A/B 1.0 弹壳")

	# 判据 7（本探针的核心）：把两枚弹壳的**世界包络**经真相机投影成屏幕像素高度，
	# 比值必须 ≈ 0.8。这一条把"缩小到 80%"从脚本常量一路钉到渲染投影上：
	# 只改常量不改几何、或几何没跟着 scale 走，比值都会偏离。
	# 注意：每枚都在**自身中心**处取投影高度，故两枚的距离差不会污染比值。
	var small_px := _projected_height_px(camera, small)
	var legacy_px := _projected_height_px(camera, legacy)
	# 判据 9：两枚弹壳必须**真在取景框内**。unproject_position 对屏幕外的点照样返回数字，
	# 所以比值能"通过"而画面里根本没有弹壳（本探针首版就踩了：出图是空的，比值却 0.798）。
	var view := get_viewport().get_visible_rect().size
	for pair in [[small, "0.8"], [legacy, "1.0"]]:
		var shell := pair[0] as VfxShellCasing3D
		var center_px := camera.unproject_position(shell.global_position)
		print("[shell_probe] size_ab %s center_px=%s viewport=%s" % [str(pair[1]), str(center_px), str(view)])
		var inside := (
			center_px.x >= view.x * 0.12 and center_px.x <= view.x * 0.88
			and center_px.y >= view.y * 0.12 and center_px.y <= view.y * 0.88
		)
		if not inside:
			_failures.append(
				"尺寸 A/B：%s 弹壳不在取景框内 %s（视口 %s），出图会看不到它" % [str(pair[1]), str(center_px), str(view)]
			)
	print(
		"[shell_probe] size_ab small_px=%.2f legacy_px=%.2f ratio=%.4f"
		% [small_px, legacy_px, small_px / maxf(legacy_px, 0.0001)]
	)
	if legacy_px <= 1.0:
		_failures.append("尺寸 A/B：1.0 基准弹壳投影高度退化（%.2f px），判据失效" % legacy_px)
	else:
		var ratio := small_px / legacy_px
		if absf(ratio - SIZE_RATIO_EXPECTED) > SIZE_RATIO_TOLERANCE * SIZE_RATIO_EXPECTED:
			_failures.append(
				"尺寸 A/B：投影高度比 %.4f 偏离 %.2f ±%.0f%%（0.8 弹壳 %.2f px / 1.0 弹壳 %.2f px）"
				% [ratio, SIZE_RATIO_EXPECTED, SIZE_RATIO_TOLERANCE * 100.0, small_px, legacy_px]
			)
	small.queue_free()
	legacy.queue_free()


## 判据 8：静止躺平的弹壳必须**真的贴在地板面上**（不悬空、不陷入）。
## 做法：把弹壳包络底面与其正下方的地板点一起投影到屏幕，像素差换算回米。
## 换算率由相机自身推出（同一位置上下 1m 的投影像素差），故不依赖任何硬编码常量。
## 几何期望：躺平圆柱的包络底面 = 中心 y − 半径 = (floor_y + 半径) − 半径 = floor_y = 0
## ⇒ 接触时差值应为 0。悬空会显著为正，陷入为负。
func _assert_grounded(
	camera: Camera3D,
	shell: VfxShellCasing3D,
	label: String,
	floor_y: float = 0.0,
) -> void:
	var bounds := _world_bounds(shell)
	if bounds.size.y <= 0.0:
		_failures.append("%s：包络退化，无法判定落地接触" % label)
		return
	var probe := Vector3(shell.global_position.x, floor_y, shell.global_position.z)
	var floor_px := camera.unproject_position(probe).y
	var one_meter_px := absf(camera.unproject_position(probe + Vector3.UP).y - floor_px)
	if one_meter_px <= 1.0:
		_failures.append("%s：地面投影换算率退化（%.2f px/m），判据失效" % [label, one_meter_px])
		return
	var bottom_px := camera.unproject_position(
		Vector3(probe.x, bounds.position.y, probe.z)
	).y
	var gap_m := (floor_px - bottom_px) / one_meter_px
	print("[shell_probe] %s gap_m=%.4f bounds_y=%.4f" % [label, gap_m, bounds.position.y])
	if absf(gap_m) > 0.01:
		_failures.append(
			"%s：静止弹壳与地板接触面差 %.4f m（应 ≈0；正=悬空，负=陷入）" % [label, gap_m]
		)


# ---------------------------------------------------------------- 机位 3：深层楼（98F）

## 实机缺陷回归的可视证据。塔楼楼层向下建，98F 在世界 y ≈ -1176 m。
## 旧缺陷把弹壳的地面高度兜底成 0：弹壳出生那一帧就已经"低于地面"，
## 于是被夹到世界原点附近（y≈0.05）、离玩家一千多米 ⇒ 实机什么都看不见。
## 本例把弹壳**放在 98F 深度**、并按该层给地面，渲染「飞行中 / 已静止」两枚：
## ① 两枚都必须留在这一层（不跑到 y≈0）；② 静止那枚精确贴在该层地面上（gap ≈ 0）。
func _shoot_deep_floor(camera: Camera3D) -> void:
	var anchor_x := -0.55
	var flying := _spawn_shell(
		Vector3(anchor_x, DEEP_FLOOR_Y + SPAWN_HEIGHT, 0.0),
		SMALL_SIZE,
		Vector3(0.9, 1.2, 0.0),
		DEEP_FLOOR_Y,
	)
	var settled := _spawn_shell(
		Vector3(anchor_x + 1.1, DEEP_FLOOR_Y + SPAWN_HEIGHT, 0.0),
		SMALL_SIZE,
		Vector3(0.0, 0.8, 0.0),
		DEEP_FLOOR_Y,
	)
	if flying == null or settled == null:
		return
	_advance(flying, 0.25)
	_advance(settled, 2.4)

	var radius := SHELL_BASE_RADIUS * SMALL_SIZE
	for pair in [[flying, "飞行中"], [settled, "静止"]]:
		var shell := pair[0] as VfxShellCasing3D
		var dy := shell.global_position.y - DEEP_FLOOR_Y
		print("[shell_probe] deep %s y=%.3f dy=%.3f" % [str(pair[1]), shell.global_position.y, dy])
		if dy < -0.05 or dy > SPAWN_HEIGHT + 0.5:
			_failures.append(
				"深层楼：%s 弹壳没留在 98F 这一层（y=%.3f，该层地面 y=%.1f）"
				% [str(pair[1]), shell.global_position.y, DEEP_FLOOR_Y]
			)
	if absf(settled.global_position.y - (DEEP_FLOOR_Y + radius)) > 0.01:
		_failures.append(
			"深层楼：静止弹壳未贴 98F 地面（y=%.3f 期望 %.3f）"
			% [settled.global_position.y, DEEP_FLOOR_Y + radius]
		)
	# 终极判据：绝不允许出现在世界原点附近 —— 那正是旧缺陷的症状。
	for pair in [[flying, "飞行中"], [settled, "静止"]]:
		var shell := pair[0] as VfxShellCasing3D
		if absf(shell.global_position.y) < 100.0:
			_failures.append(
				"深层楼：%s 弹壳出现在世界原点附近（y=%.3f，floor_y 被兜底成 0 的回归）"
				% [str(pair[1]), shell.global_position.y]
			)

	var focus := (flying.global_position + settled.global_position) * 0.5
	_aim(camera, Vector3(focus.x, focus.y, 2.2), Vector3(focus.x, focus.y - 0.25, 0.0))
	await _settle()
	_capture(DEEP_FLOOR_PATH, "弹壳深层楼采样失败")
	_assert_grounded(camera, settled, "深层楼 98F 弹壳", DEEP_FLOOR_Y)
	# 取景判据：unproject_position 对屏幕外的点照样返回数字 ⇒ 必须显式看住框内。
	var view := get_viewport().get_visible_rect().size
	var settled_px := camera.unproject_position(settled.global_position)
	print("[shell_probe] deep settled center_px=%s viewport=%s" % [str(settled_px), str(view)])
	var outside := (
		settled_px.x < view.x * 0.12 or settled_px.x > view.x * 0.88
		or settled_px.y < view.y * 0.12 or settled_px.y > view.y * 0.88
	)
	if outside:
		_failures.append("深层楼：静止弹壳不在取景框内 %s" % str(settled_px))


## 深层楼机位需要一块**同深度的地面**才有"贴地"参考：主地面在 y=0，比 98F 高一公里多，
## 在深机位里根本不会入画。此处按主地面的同一约定（盒厚 0.4、顶面 = 地面 y）再加一块。
func _install_deep_ground() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(14.0, 0.4, 8.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.30, 0.32, 0.36)
	material.roughness = 0.85
	mesh.material = material
	var ground := MeshInstance3D.new()
	ground.name = "ShellProbeDeepGround"
	ground.mesh = mesh
	ground.position = Vector3(0.0, DEEP_FLOOR_Y - 0.2, 0.0)
	add_child(ground)


func _install_deep_camera() -> Camera3D:
	_install_deep_ground()
	var camera := _install_camera()
	camera.name = "ShellProbeDeepCamera"
	camera.fov = 50.0
	return camera


# ---------------------------------------------------------------- 机位 4：连发散布

## 业主 2026-09-22：「不然太整齐了」的画面证据。
##
## 刻意走**真实调用方**路径（`WeaponModel3D._spawn_shell_casing`），不在探针里另抄一套随机口径 ——
## 否则这张图只证明「探针会摆散布」，证明不了实机弹壳真的散了。
##
## 同时复刻业主截图里的连发场景：每发之间让枪身摆一点头（后坐摆头），
## 于是「枪转了 + 弹壳口径不变」就会把 8 发弹壳沿一条**整齐弧线**排开 —— 那正是被投诉的画面。
func _shoot_spread(camera: Camera3D) -> void:
	var pool := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	if pool == null:
		_failures.append("连发散布：场景里找不到 vfx_pool_3d 池")
		return
	var weapon := _install_spread_weapon()
	if weapon == null:
		return
	var shooter := Node3D.new()
	shooter.name = "ShellProbeShooter"
	add_child(shooter)
	# 枪握在腰胸高度、脚站在地面 ⇒ floor_y = 0（与实机同构：地面真源取射击者站立面）。
	weapon.global_position = Vector3(0.0, SPREAD_GUN_HEIGHT, 0.0)
	shooter.global_position = Vector3(0.0, 0.0, 0.0)

	var before := pool.active_count(VfxPool3D.FX01_SHELL_CASING)
	for shot in range(SPREAD_SHOTS):
		var yaw := deg_to_rad(SPREAD_YAW_START_DEG + float(shot) * SPREAD_YAW_STEP_DEG)
		weapon.global_rotation = Vector3(0.0, yaw, 0.0)
		weapon.call("_spawn_shell_casing", shooter)
	var bucket: Array = pool._active.get(VfxPool3D.FX01_SHELL_CASING, [])
	if bucket.size() != before + SPREAD_SHOTS:
		_failures.append(
			"连发散布：连打 %d 发只进了 %d 发 VfxPool（%d -> %d）"
			% [SPREAD_SHOTS, bucket.size() - before, before, bucket.size()]
		)
	var shells: Array[VfxShellCasing3D] = []
	for entry in bucket:
		var shell := entry as VfxShellCasing3D
		if shell != null:
			shells.append(shell)
	if shells.size() != SPREAD_SHOTS:
		_failures.append("连发散布：弹壳实例数 %d 不等于发数 %d" % [shells.size(), SPREAD_SHOTS])
		weapon.free()
		shooter.free()
		return
	# 全部推到静止：只有躺平静止的落点才能量「落地后的范围」。
	for shell in shells:
		_advance(shell, 2.6)

	var landed := PackedVector2Array()
	for index in shells.size():
		var shell := shells[index]
		var snapshot: Dictionary = shell.call("get_presentation_snapshot")
		var radius := float(snapshot.get("radius", 0.0))
		var height := shell.global_position.y
		if not bool(snapshot.get("settled", false)):
			_failures.append(
				"连发散布：第 %d 发未在寿命内静止（phase=%d）" % [index + 1, int(snapshot.get("phase", -1))]
			)
		if absf(height - radius) > 0.01:
			_failures.append(
				"连发散布：第 %d 发未贴地（y=%.4f 期望 %.4f）" % [index + 1, height, radius]
			)
		landed.append(Vector2(shell.global_position.x, shell.global_position.z))
	var max_pair := _max_pair_distance(landed)
	var residual := _max_off_line_residual(landed)
	print("[shell_probe] spread landings=%s" % str(landed))
	print(
		"[shell_probe] spread shots=%d max_pair=%.4f off_line_residual=%.4f"
		% [SPREAD_SHOTS, max_pair, residual]
	)
	# 防假绿：散布若为 0，上面的"偏差"判据退化 ⇒ 说明这一枪根本没打出去。
	if max_pair <= 0.0001:
		_failures.append("连发散布：8 个落点完全重合，判据退化（弹壳没真的抛出去？）")
	elif residual < SPREAD_MIN_RESIDUAL:
		_failures.append(
			"连发散布：落点离最远两点连线的最大垂直偏差仅 %.4f m（< %.2f m）⇒ 弹壳仍排在一条整齐弧线上"
			% [residual, SPREAD_MIN_RESIDUAL]
		)

	var centroid := Vector2.ZERO
	for point in landed:
		centroid += point
	centroid /= float(landed.size())
	var focus := Vector3(centroid.x, 0.0, centroid.y)
	_aim(camera, focus + Vector3(0.0, SPREAD_CAM_HEIGHT, SPREAD_CAM_BACK), focus)
	await _settle()
	# 取景判据：unproject_position 对屏幕外的点照样返回数字 ⇒ 必须显式看住框内。
	var view := get_viewport().get_visible_rect().size
	for index in shells.size():
		var pixel := camera.unproject_position(shells[index].global_position)
		var inside := (
			pixel.x >= view.x * 0.05 and pixel.x <= view.x * 0.95
			and pixel.y >= view.y * 0.05 and pixel.y <= view.y * 0.95
		)
		if not inside:
			_failures.append(
				"连发散布：第 %d 发不在取景框内 %s（视口 %s），出图会看不到它"
				% [index + 1, str(pixel), str(view)]
			)
	_capture(SPREAD_PATH, "弹壳连发散布采样失败")
	for shell in shells:
		# 归还池（不是 queue_free）：池的 _active 里还挂着它，直接释放会留下悬空引用。
		shell.call("_retire")
	_release_spread_tree()
	weapon.free()
	shooter.free()


## 释放连发散布机位的装配树（Node 不会随武器一起回收，不释放会在退出时报孤节点）。
func _release_spread_tree() -> void:
	if _spread_tree != null and is_instance_valid(_spread_tree):
		_spread_tree.free()
	_spread_tree = null


## 连发散布机位要真开火，故需要一份装配好的枪（出厂枪 + 标准子弹）。
func _install_spread_weapon() -> WeaponModel3D:
	const WEAPON_SCENE: PackedScene = preload(
		"res://assets/art/weapons/weapon_3d/wpn_gun_kit_root_top3d_v001.tscn"
	)
	var weapon := WEAPON_SCENE.instantiate() as WeaponModel3D
	if weapon == null:
		_failures.append("连发散布：武器模型场景根节点不是 WeaponModel3D")
		return null
	add_child(weapon)
	var tree := BlueprintRegistry.build_weapon_tree(
		BlueprintRegistry.DEFAULT_STARTING_GUN_ID, "mod_bullet_standard"
	)
	if tree == null or not weapon.configure_from_tree(tree):
		_failures.append("连发散布：出厂枪装配失败，无法验证抛壳散布")
		if tree != null:
			tree.free()
		weapon.free()
		return null
	# tree 归 WeaponModel3D 使用，探针结束时由 _shoot_spread 显式释放（Node 不会自动回收）。
	_spread_tree = tree
	return weapon


## 落点两两最大距离（XZ 平面，米）。
func _max_pair_distance(points: PackedVector2Array) -> float:
	var worst := 0.0
	for i in points.size():
		for j in range(i + 1, points.size()):
			worst = maxf(worst, points[i].distance_to(points[j]))
	return worst


## 所有落点到「最远两点连线」的最大垂直偏差（米）。
##
## 为什么不用「两两最大距离」判整不整齐：纯摆头（无随机）时弹壳沿一条弧排开，
## 两两距离可以很大（本例 ≈ 0.3m），但它们**都在同一条线附近** —— 业主投诉的正是这件
## 事："排成一条整齐的弧"。垂直偏差才对应它：弧排列 ≈ 毫米级，随机散开 ≈ 分米级。
func _max_off_line_residual(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var pair_i := 0
	var pair_j := 1
	var best_distance := -1.0
	for i in points.size():
		for j in range(i + 1, points.size()):
			var distance := points[i].distance_to(points[j])
			if distance > best_distance:
				best_distance = distance
				pair_i = i
				pair_j = j
	var origin := points[pair_i]
	var direction := points[pair_j] - origin
	if direction.length_squared() < 0.000001:
		return 0.0
	direction = direction.normalized()
	var worst := 0.0
	for point in points:
		var offset := point - origin
		var along := offset.dot(direction)
		worst = maxf(worst, (offset - direction * along).length())
	return worst


# ---------------------------------------------------------------- 弹壳驱动

func _spawn_shell(
	origin: Vector3,
	size: float,
	velocity: Vector3 = EJECTION_VELOCITY,
	floor_y: float = 0.0,
) -> VfxShellCasing3D:
	var shell := SHELL_SCENE.instantiate() as VfxShellCasing3D
	if shell == null:
		_failures.append("弹壳 Prefab 根节点不是 VfxShellCasing3D")
		return null
	add_child(shell)
	shell.activate(origin, SHELL_COLOR, size, {
		"velocity": velocity,
		"spin_axis": SPIN_AXIS,
		"spin_speed": SPIN_SPEED,
		"floor_y": floor_y,
	})
	return shell


## 以固定步长手动推进弹壳的模拟时间（不依赖引擎帧率，两次运行结果一致）。
## ⚠️ 推完必须把 `process_mode` 置为 DISABLED 冻结：弹壳已在树里且 `_active`，
##    探针随后的 `await` 会让引擎的 `_process` 继续替它往前跑 —— 实测拍照时四个阶段
##    已经多跑了 0.25s 以上（"下落中"那枚早已落地静止，与"已静止"的挤成同一高度）。
##    冻结只停逻辑，不影响渲染，弹壳仍照常出现在画面里。
func _advance(shell: VfxShellCasing3D, seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		elapsed += _step_seconds
		shell.call("_on_tick", elapsed, shell.lifetime)
	shell.process_mode = Node.PROCESS_MODE_DISABLED


# ---------------------------------------------------------------- 相机 / 环境 / 取样

func _projected_height_px(camera: Camera3D, node: Node3D) -> float:
	var bounds := _world_bounds(node)
	if bounds.size.y <= 0.0:
		return 0.0
	var center := bounds.get_center()
	var top := Vector3(center.x, bounds.position.y + bounds.size.y, center.z)
	var bottom := Vector3(center.x, bounds.position.y, center.z)
	return absf(camera.unproject_position(top).y - camera.unproject_position(bottom).y)


func _world_bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var initialized := false
	for instance in _all_mesh_instances(node):
		if instance.mesh == null:
			continue
		var local := instance.get_aabb()
		var world := instance.global_transform * local
		if not initialized:
			bounds = world
			initialized = true
		else:
			bounds = bounds.merge(world)
	return bounds


func _all_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D:
			result.append(current as MeshInstance3D)
		for child in current.get_children():
			stack.append(child)
	return result


## 只服务判读的地板参照物：**没有碰撞体** —— 弹壳落地靠自身的 floor_y 模拟，不靠它。
func _install_ground() -> void:
	var mesh := BoxMesh.new()
	# 深度只取 8（z ±4）：侧视机位在 z=5.0，太深会让相机正好贴在盒子侧面上。
	mesh.size = Vector3(30.0, 0.4, 8.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.30, 0.32, 0.36)
	material.roughness = 0.85
	mesh.material = material
	var ground := MeshInstance3D.new()
	ground.name = "ProbeGround"
	ground.mesh = mesh
	ground.position = Vector3(3.0, -0.2, 0.0)
	add_child(ground)


func _install_environment() -> WorldEnvironment:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "ShellProbeEnvironment"
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.44, 0.52, 0.64)
	sky_material.sky_horizon_color = Color(0.58, 0.62, 0.68)
	sky_material.ground_horizon_color = Color(0.40, 0.42, 0.45)
	sky_material.ground_bottom_color = Color(0.22, 0.23, 0.26)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.05
	world_environment.environment = environment
	add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.name = "ShellProbeSun"
	light.light_energy = 2.4
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-38.0, -52.0, 0.0)
	add_child(light)
	return world_environment


func _install_camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "ShellProbeCamera"
	camera.fov = 55.0
	camera.near = 0.05
	camera.far = 200.0
	add_child(camera)
	camera.make_current()
	return camera


func _install_size_ab_camera() -> Camera3D:
	var camera := _install_camera()
	camera.name = "ShellProbeSizeCamera"
	# 特写机位：窄 FOV + 贴近，让 0.8 与 1.0 的尺寸差看得见（宽视角下两者只差 6 个像素）。
	camera.fov = 38.0
	return camera


func _aim(camera: Camera3D, from: Vector3, to: Vector3) -> void:
	camera.global_position = from
	camera.look_at(to, Vector3.UP)
	camera.make_current()


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.25).timeout


func _capture(path: String, failure: String) -> Image:
	if DisplayServer.get_name() == "headless":
		_skipped_headless += 1
		print("[shell_probe] headless：跳过渲染取样 %s（只跑数值判据）" % path.get_file())
		return null
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		_failures.append(failure + "（视口纹理为空）")
		return null
	var buckets := _luma_buckets(image)
	if buckets < MIN_LUMA_BUCKETS:
		_failures.append("%s（画面只有 %d 层亮度，疑似没渲染出内容）" % [failure, buckets])
		return null
	if image.save_png(path) != OK:
		_failures.append(failure + "（PNG 写入失败）")
		return null
	_captured += 1
	print("[shell_probe] saved %s %dx%d luma_buckets=%d" % [path.get_file(), image.get_width(), image.get_height(), buckets])
	return image


func _luma_buckets(image: Image) -> int:
	var buckets := {}
	var step_x: int = maxi(image.get_width() / 48, 1)
	var step_y: int = maxi(image.get_height() / 48, 1)
	for x in range(0, image.get_width(), step_x):
		for y in range(0, image.get_height(), step_y):
			var color := image.get_pixel(x, y)
			var luma := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			buckets[int(luma * 12.0)] = true
	return buckets.size()


func _report() -> void:
	if _skipped_headless > 0 and _captured == 0:
		print("[shell_probe] headless 模式：仅完成数值判据，未产出图片")
	if _failures.is_empty():
		print("SHELL_CASING_VISUAL_OK: captured=%d skipped_headless=%d" % [_captured, _skipped_headless])
		get_tree().quit(0)
		return
	for failure in _failures:
		printerr("SHELL_CASING_VISUAL_FAIL: %s" % failure)
	get_tree().quit(1)
