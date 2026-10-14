class_name BossRoom02ArenaGate3D
extends Node3D
## Boss房02 专属的**竞技场门控 + 过场镜头**。业主 2026-10-13 指定，只服务这一间房。
##
## 三件事，一条时间线：
##   ① **过场镜头**：玩家进楼梯后下坡 3 m 起，镜头慢慢下拉到工程调好的那一帧构图
##      （俯仰 −30° / 前后 +1.2 m / 平移 0，见 `CAMERA_TARGET_*`）；
##   ② **封场**：下到平台约 2 m 处有一条**横贯平台宽度**的激活线，越过它 → 三个出口
##      （北侧楼梯口、东桥口、西桥口）各升起一道护栏，玩家出不去；
##   ③ **开闸**：**首领一死**即开闸（业主 2026-10-14 裁定）——
##      判据是 `Dungeon3D.is_room_boss_defeated()`，**不是** `room.cleared`。
##      二者刻意分开：`room.cleared` 还要等增援与波次全清，那样护栏会拖到
##      「小怪也清光」才落，与业主口径不符。Boss 倒下即视为这场仗打完，
##      **残留增援不拦人**。
##      玩家离开房间 → 镜头复位并重新武装（下次进来重演一遍）。
##
## 三处缺口是**实测**出来的，不是我摆的：平台周边原本就有 17 段 `deck_barrier_5m`
## 连成围栏，恰好空出这三格（各 5 m，正对楼梯与两座桥）。本节点只是把这三格补上。
##
## 🔴 护栏实例挂在**本节点**下，不进房间的 `Components` 组 —— 房间的
##    `layout_instance_total`（652）与组件逐件断言因此完全不受影响。
##
## 🔴 与摄像头的绑定：镜头姿态走 `Player3D.animate_camera_pose_offsets()`，
##    它和调试面板共用同一组偏移量 ⇒ 面板里对出来的构图能被剧本 1:1 复现。

signal camera_descent_started()
signal arena_sealed()
signal arena_released()

const GATE_PREFAB: PackedScene = preload(
	"res://assets/art/environments/tower_zones/expedition/runtime/room_type_components"
	+ "/boss_room_02/deck_barrier_5m/env_boss_room02_deck_barrier_5m_root_top3d.tscn"
)
## 护栏槽位在房间 TSCN 里以 Marker3D 子节点声明；本脚本按名字取，不猜坐标。
const GATE_SLOT_PREFIX := "Gate_"

# ── 几何基准（全部来自 `scripts/probe_boss_room02_walk_surface.gd` 的实测）────
## 楼梯：可见坡面 `y = 0.24z + 2.505`，占 `z ∈ [-10, 40]`、`x ∈ [-2.5, 2.5]`。
const STAIR_HEAD_LOCAL_Z := 40.0
const STAIR_FOOT_LOCAL_Z := -10.0
const STAIR_HALF_WIDTH_M := 2.5
## 「进楼梯后 3 m」= 梯顶往下 3 m ⇒ 触发线 z = 37。
const CAMERA_TRIGGER_INTO_STAIR_M := 3.0
## 平台走面：`x ∈ [-12.5, 12.5]`、`z ∈ [-35, -10]`，面高 y = 0。
const PLATFORM_NORTH_EDGE_LOCAL_Z := -10.0
const PLATFORM_FAR_EDGE_LOCAL_Z := -35.0
const PLATFORM_HALF_WIDTH_M := 12.5
## 「进平台后约 2 m」⇒ 激活线 z = -12。
const ARENA_TRIGGER_INTO_PLATFORM_M := 2.0

# ── 过场镜头目标姿态（业主用调试面板对出来的那一帧）──────────────────────────
## 俯仰 −30° = 镜头压低并后拉成更宽的俯视；前后 +1.2 m 在同一方向上再退一点。
## 改构图就改这四个数：调试面板里调到满意，把面板读数抄进来即可。
const CAMERA_TARGET_PITCH_DEG := -30.0
const CAMERA_TARGET_TRAILING_M := 1.2
const CAMERA_TARGET_PAN := Vector3.ZERO
const CAMERA_TARGET_YAW_DEG := 0.0
## 「慢慢下拉」：过渡时长。6 s ≈ 走完半段楼梯，全程不打断操作。
const CAMERA_DESCENT_SECONDS := 6.0
## 复位（离开房间时）比下拉快，避免离开瞬间镜头还在慢慢飘。
const CAMERA_RESTORE_SECONDS := 1.2

# ── 护栏起落 ────────────────────────────────────────────────────────────────
## 收起时沉到平台走面以下这么多 —— 藏在深井里，玩家看不见也碰不到。
##
## 🔴 1.6 m **不够**：护栏自身高 1.12 m，沉 1.6 m 后顶面还在 −0.48 m，而玩家胶囊
##    向下延伸约 0.9 m（原点脚下 −0.87）⇒ 横向移动仍会被它挡住。实测封场前就被
##    拦在 z=−10.85 / x=∓11.68（正是三处护栏的位置）。故取 2.6 m，并把形状一并停用。
const GATE_HIDDEN_DEPTH_M := 2.6
const GATE_RISE_SECONDS := 1.4
const GATE_LOWER_SECONDS := 1.1
## 护栏自身碰撞层（与既有构件一致）；收起时清零，避免沉在井里的残留碰撞体。
const GATE_COLLISION_LAYER := 1

var _room: DungeonRoom3D
var _tower: Dungeon3D
var _player: Player3D
var _gates: Array[Node3D] = []

var _camera_armed := true
var _camera_started := false
var _arena_sealed := false


func _ready() -> void:
	_room = _find_room()
	_tower = _find_tower()
	if _room == null or _tower == null:
		# 独立预览场景（`scenes/Expedition01BossRoom02_3D.tscn`）直接实例化房型场景，
		# 没有房间/塔这两级 —— 那里只该看美术，门控整体停摆即可，不是错误。
		push_warning("BossRoom02ArenaGate3D 未接在 DungeonRoom3D 下：门控与过场镜头停用")
		set_physics_process(false)
		return
	_build_gates()


func _physics_process(_delta: float) -> void:
	if _room == null or _tower == null:
		return
	var player := _resolve_player()
	if player == null:
		return
	# 判定一律在**本节点的局部帧（= 美术帧）**里做，不用房间帧。
	# 本脚本的常量（楼梯 z∈[−10,40]、平台 z∈[−35,−10]、两处触发线）是照 Boss房02
	# **烘焙坐标**写的；绑定壳可能把整房转过 180°（远征01 的全局北向修正就是这么做的），
	# 此时房间帧与美术帧相差 180°，用房间帧会把触发线算到房间另一头 ——
	# 症状是玩家还在楼梯上就被封场、或走到平台却不触发。
	# 本节点与三个槽位都是美术的子节点，故 `affine_inverse() * 世界点` 恒得美术帧坐标。
	var local := global_transform.affine_inverse() * player.global_position
	var inside := _room.contains_world_position(player.global_position)
	_tick_camera(player, local, inside)
	_tick_arena(local, inside)


# ── 过场镜头 ────────────────────────────────────────────────────────────────
func _tick_camera(player: Player3D, local: Vector3, inside: bool) -> void:
	if _camera_started:
		# 离开房间 ⇒ 复位并重新武装。**已了结的场**不再重演（没有仗要打）。
		if not inside:
			if player.has_camera_pose_offset():
				player.clear_camera_pose_offsets(CAMERA_RESTORE_SECONDS)
			_camera_started = false
			_camera_armed = not _arena_resolved()
		return
	if not _camera_armed:
		return
	# 场已了结（首领已阵亡）就不再起过场 —— 即便玩家上一次是**在 Boss 还活着时**
	# 离开的（那一刻 `_camera_armed` 会被置真），重进楼梯也不重演。
	# 只靠离开时那一次判定不够：Boss 可以在玩家离房之后才死。
	if _arena_resolved():
		_camera_armed = false
		return
	# 触发条件：人已在楼梯通道里（|x| ≤ 2.5）且越过「梯顶往下 3 m」那条线。
	# 下界收到梯脚：走到平台上就不再算「在楼梯上」。
	var on_stair := (
		absf(local.x) <= STAIR_HALF_WIDTH_M
		and local.z <= STAIR_HEAD_LOCAL_Z - CAMERA_TRIGGER_INTO_STAIR_M
		and local.z >= STAIR_FOOT_LOCAL_Z
	)
	if not on_stair:
		return
	_camera_started = true
	player.animate_camera_pose_offsets(
		CAMERA_TARGET_PITCH_DEG,
		CAMERA_TARGET_TRAILING_M,
		CAMERA_TARGET_PAN,
		CAMERA_TARGET_YAW_DEG,
		CAMERA_DESCENT_SECONDS
	)
	camera_descent_started.emit()
	print("[BossRoom02ArenaGate3D] 过场镜头开始：z=%.2f → pitch=%.1f° trailing=%+.1fm（%.1fs）"
		% [local.z, CAMERA_TARGET_PITCH_DEG, CAMERA_TARGET_TRAILING_M, CAMERA_DESCENT_SECONDS])


# ── 封场 / 开闸 ─────────────────────────────────────────────────────────────
## 竞技场是否**已了结** = 本房首领已阵亡（业主 2026-10-14：「Boss 一死就开闸」）。
##
## 🔴 刻意**不**用 `room.cleared`：后者还要求增援与波次全清，护栏会一直拖到
##    「残留小怪也清光」才落 —— 不是业主要的口径。Boss 倒下即视为这场仗打完，
##    **残留增援不拦人**，玩家可以带着追兵走出去。
##
## 开闸与「离开后是否重演」都判这一条，两处**不许各写一份** ——
## 否则会出现「闸已开、镜头却还在重演」这类自相矛盾。
func _arena_resolved() -> bool:
	if _room == null or _tower == null:
		return false
	return _tower.is_room_boss_defeated(_room.room_id)


func _tick_arena(local: Vector3, inside: bool) -> void:
	if _arena_sealed:
		if _arena_resolved():
			_set_gates_raised(false, GATE_LOWER_SECONDS)
		return
	if _arena_resolved() or not inside:
		return
	# 激活线：横贯平台宽度的一条带（只判 z，宽度天然覆盖整个平台 —— 业主明确要求
	# 「横着覆盖平台，不然玩家会绕过去」）。收在平台远端之内，避免站在边缘外误触发。
	var past_line := local.z <= PLATFORM_NORTH_EDGE_LOCAL_Z - ARENA_TRIGGER_INTO_PLATFORM_M
	var within_platform := (
		absf(local.x) <= PLATFORM_HALF_WIDTH_M and local.z >= PLATFORM_FAR_EDGE_LOCAL_Z
	)
	if past_line and within_platform:
		_set_gates_raised(true, GATE_RISE_SECONDS)


func _set_gates_raised(raised: bool, duration: float) -> void:
	if raised == _arena_sealed:
		return
	_arena_sealed = raised
	for gate in _gates:
		_animate_gate(gate, raised, duration)
	print("[BossRoom02ArenaGate3D] 竞技场%s：%d 道护栏，%.1fs" % [
		"封场" if raised else "开闸", _gates.size(), duration,
	])
	if raised:
		arena_sealed.emit()
	else:
		arena_released.emit()


func _animate_gate(gate: Node3D, raised: bool, duration: float) -> void:
	var rest_y := float(gate.get_meta("gate_rest_y", 0.0))
	var target_y := rest_y if raised else rest_y - GATE_HIDDEN_DEPTH_M
	# 碰撞随门体一起抬落；收起时不参与碰撞，避免井里留一圈隐形阻挡。
	_set_gate_collision(gate, raised)
	# 🔴 必须先杀掉上一段补间：升、落各建一条 tween 都写 `position:y`，
	#    两条并存时**后结束的那条赢**。若在升起动画（1.4 s）没走完时就开闸，
	#    升到 y=0 的那条会更晚结束，把已经落下的护栏**又拽回去** ——
	#    表现是「逻辑上闸已开（`sealed=false`）、护栏却还立着挡人」。
	#    Boss 一死即开闸会让这个竞态更容易撞上（击杀可以发生在封场后任意时刻），
	#    所以这里显式接管：同一道门永远只有一条在跑的补间。
	var previous := gate.get_meta("gate_tween", null) as Tween
	if previous != null and previous.is_valid():
		previous.kill()
	var tween := gate.create_tween()
	gate.set_meta("gate_tween", tween)
	tween.tween_property(gate, "position:y", target_y, maxf(duration, 0.01)).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_OUT if raised else Tween.EASE_IN)


## 收起时**双保险**停用碰撞：清碰撞层 + 停用形状。
## 只清层不够可靠（实测仍会挡人），`CollisionShape3D.disabled` 才是硬开关。
func _set_gate_collision(gate: Node3D, enabled: bool) -> void:
	var stack: Array[Node] = [gate]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is StaticBody3D:
			(node as StaticBody3D).collision_layer = GATE_COLLISION_LAYER if enabled else 0
		elif node is CollisionShape3D:
			(node as CollisionShape3D).disabled = not enabled
		for child in node.get_children():
			stack.append(child)


# ── 建门 ────────────────────────────────────────────────────────────────────
func _build_gates() -> void:
	for child in get_children():
		var slot := child as Marker3D
		if slot == null or not slot.name.begins_with(GATE_SLOT_PREFIX):
			continue
		var gate := GATE_PREFAB.instantiate() as Node3D
		if gate == null:
			push_error("Boss房02 护栏 Prefab 实例化失败：%s" % slot.name)
			continue
		gate.name = "ArenaGate_" + slot.name.trim_prefix(GATE_SLOT_PREFIX)
		gate.transform = Transform3D(slot.basis, slot.position - Vector3.UP * GATE_HIDDEN_DEPTH_M)
		gate.set_meta("gate_rest_y", slot.position.y)
		gate.set_meta("gate_slot", slot.name)
		gate.set_meta("gate_owner", "BossRoom02ArenaGate3D")
		add_child(gate)
		_set_gate_collision(gate, false)
		_gates.append(gate)
	if _gates.is_empty():
		push_error("Boss房02 门控没有找到任何 %s* 槽位（护栏无处可建）" % GATE_SLOT_PREFIX)


# ── 对外只读接口（供探针 / 剧情 / 存档校验）──────────────────────────────────
func is_arena_sealed() -> bool:
	return _arena_sealed


func gate_count() -> int:
	return _gates.size()


func gate_local_heights() -> Array[float]:
	var heights: Array[float] = []
	for gate in _gates:
		heights.append(gate.position.y)
	return heights


func camera_descent_triggered() -> bool:
	return _camera_started


func arena_gate_snapshot() -> Dictionary:
	return {
		"room_id": _room.room_id if _room != null else "",
		"gate_count": _gates.size(),
		"sealed": _arena_sealed,
		"cleared": _room.cleared if _room != null else false,
		"boss_defeated": _arena_resolved(),
		"camera_armed": _camera_armed,
		"camera_started": _camera_started,
		"camera_zone_local_z": STAIR_HEAD_LOCAL_Z - CAMERA_TRIGGER_INTO_STAIR_M,
		"arena_zone_local_z": PLATFORM_NORTH_EDGE_LOCAL_Z - ARENA_TRIGGER_INTO_PLATFORM_M,
	}


func _resolve_player() -> Player3D:
	if _player != null and is_instance_valid(_player):
		return _player
	if _tower == null:
		return null
	_player = _tower.player
	return _player


func _find_room() -> DungeonRoom3D:
	var node: Node = self
	while node != null:
		if node is DungeonRoom3D:
			return node as DungeonRoom3D
		node = node.get_parent()
	return null


func _find_tower() -> Dungeon3D:
	var node: Node = self
	while node != null:
		if node is Dungeon3D:
			return node as Dungeon3D
		node = node.get_parent()
	return null
