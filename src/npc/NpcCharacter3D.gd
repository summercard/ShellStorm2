class_name NpcCharacter3D
extends Node3D
## 基地 NPC 实体：**一块可复用的"会走路、会说话的场景角色"**。
##
## 职责（与 [ThemedNPC3D] 的分工见 [20 号文档](../../docs/v0.1/20_技术施工_基地NPC.md) §2）：
##   - 拥有：自己的模型挂载与皮肤、巡逻路径、朝向、待机/步行动画、头顶交互提示、
##     对话推进、交互候选协议（[PlayerInteractionController3D] 的 provider 之一）。
##   - 不拥有：该不该说这句话（内容在 [NpcCatalog]）、玩家状态、存档、场景切换。
##     本节点**不写 `user://`**，`_ready()` 也不碰存档 —— 自动测试会在 Autoload 启动前
##     污染正式档，见 AGENTS.md。
##
## 模型口径：复用玩家 `bunny01` 运行时几何（2026-11-02 主人指定"用主角的模型"），
## **剥离 `PlayerAvatar3D` 脚本**只借几何 —— 玩家的换装/换弹/受击/瞄准全不该跟着长到 NPC 上。
## 皮肤是运行时 `material_override` 覆盖本体几何，不新增美术资产、不改源模型。
##
## 表现动画全部由本脚本驱动关节（模型没有骨骼动画，玩家也是这么做的）：
## 待机 = 呼吸起伏 + 耳朵轻摆；步行 = 双脚交替前后 + 重心上下 + 头部反向点头。
##
## 头顶表现（2026-11-02 业主口径，三轮改动后的终态）：
##   - **不挂名字牌/身份牌**：头顶只允许出现"交互提示"和"台词气泡"，且两者互斥。
##   - **不挂交互圆点**：白点与提示挤在同一处，视觉噪音大；提示本身改成黄色文字，
##     与基地设施（`BaseFacility3D.PromptLabel`）同一套观感。
##   - 提示只在**被聚焦**（玩家站进交互范围）时出现，不再常驻。

signal interaction_changed(visible: bool, text: String)
signal configured(npc_id: String)
## 每推进一步对话发一次。当前无订阅者，留给剧情/任务系统接"NPC 听过什么"。
signal npc_spoke(npc_id: String, line_index: int, text: String, finished_cycle: bool)
## 一次性剧情节拍：第一句出口。
signal story_beat_started(npc_id: String, beat_id: String, first_line: String)
## 一次性剧情节拍：整段说完并已落盘。（半路被打断不会发，见 `_finish_story_beat`。）
signal story_beat_finished(npc_id: String, beat_id: String)

## 模型来源：**玩家角色场景本身**（`scenes/Player3D.tscn`），不是硬编码的
## `..._v021.tscn` 版本路径。两条理由：
##   1. 运行资产命名门禁（`scripts/check_asset_runtime_naming.py`）禁止 `src/**/*.gd`
##      新增对 `*_vNNN.*` 的引用 —— 直接写版本路径会让「带版本引用计数」上升，
##      门禁 fail，而那张债务表只允许缩小。
##   2. 语义上更对：NPC 要的就是"主角那份模型"。玩家模型升级时 NPC 自动跟随，
##      不会出现两个人长得不一样的漂移。
##
## 代价是实例化一次完整玩家场景再扔掉外壳（见 `_build_visual`）。基地里玩家本来
## 就加载着同一个 PackedScene，实例化只是复制节点树，代价可忽略。
const PLAYER_SCENE_PATH := "res://scenes/Player3D.tscn"
const PLAYER_AVATAR_NODE := "Avatar3D"

## 体型倍率：**必须与玩家同一口径**。
##
## `Player3D` 在 `_initialize_debug_scale_contract()` 里把资产原始尺寸乘
## `DEFAULT_BASE_SIZE_MULTIPLIER`（0.80，注释写的是"旧资产尺寸的 80% 现在定义为
## 角色的新 100% 基础尺寸"）。NPC 不跑 `Player3D`，第一版没做这一步 ⇒ 比玩家大 25%，
## 头顶那一圈尤其显眼（2026-11-02 业主指出「头要和角色一样大，现在大了很多」）。
##
## 这里**引用同一个常量**而不是再抄一个 0.8：玩家调整基础体型时 NPC 自动跟随。
const PLAYER_BASE_SIZE_MULTIPLIER := Player3D.DEFAULT_BASE_SIZE_MULTIPLIER

## 主角的默认面饰（电子面具：深色面板 + 蓝色发光眼）。
##
## 为什么必须挂：bunny01 的头部几何**本身没有眼睛** —— 主角的脸全是这件面饰给的
## （`PlayerAvatar3D` 在 `_ready()` 里把它实例化到 `HeadJoint/FaceAccessorySocket`）。
## NPC 只摘 `VisualRoot`、不跑 `PlayerAvatar3D._ready()`，不补这一件就是一个**没有脸的绿球**
## （2026-11-02 实拍确认）。
##
## 为什么不染绿：面饰不是皮肤。染色会把蓝色发光眼一起吃掉，NPC 又变回无脸。
## "全绿皮肤"指的是头壳/躯干/耳/手/脚这些本体几何，面饰保留自己的材质。
const FACE_MASK_SCENE: PackedScene = preload(
	"res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/runtime/chr_bunny01_electronic_mask_root.tscn"
)
const FACE_MASK_NODE := "ElectronicMask"

const INTERACTION_GROUP := "base_npc_3d"
## 交互半径。2026-11-02 业主「e 交谈这个提示要接近才出来」：从 2.4m 收到 1.5m，
## 玩家基本要贴到脸前才会出提示。球形热区中心取角色半高，不埋进地板。
const INTERACTION_RADIUS := 1.5
const INTERACTION_CENTER_HEIGHT := 0.6
const PROVIDER_PRIORITY := 60
const PROMPT_TEXT := "[E] 交谈"

## 巡逻。速度取"基地里不赶时间的散步"，玩家正常移速远高于它。
const WALK_SPEED := 1.05
const TURN_SPEED := 7.0
## 搭话时的转身速度：比巡逻快一倍，玩家按下 E 的瞬间就该看到它转过来。
const TALK_TURN_SPEED := 14.0
const ARRIVE_EPSILON := 0.08
const DWELL_SECONDS := 1.6

## 一句台词的停留时间：够读完一句 20 字左右的中文，期间按 E 可提前推进。
const BUBBLE_HOLD_SECONDS := 6.0

## 迎宾招呼的判定半径。**比交互半径大**：节拍是"迎上来提醒你"，不该要求玩家先贴脸。
## 4.0m ≈ 3.3 个角色身高，玩家从归航点走两步就进圈；仍小于一个房间的尺度，
## 不会出现"刚进基地、人在对面墙角就被隔空喊话"。
const HAIL_RADIUS := 4.0

## 气泡尺寸。`SpeechBubble3D` 默认按 48px 字 / `pixel_size 0.0055` 调，
## **世界字高约 0.264m、底板宽约 3.4m**。挂在一个 1.2m 高的小型角色头上会糊满半个屏幕
## （2026-11-02 实拍确认）。
##
## ⚠️ **不能只改 `bubble_scale`**：它只参与底板几何的 `unit` 换算
## （`_relayout` 里 `unit = _label.pixel_size * bubble_scale`），Label3D 的
## `pixel_size` 不变 ⇒ 底板缩小、文字不变，字直接溢出到气泡外面（实拍踩过）。
## 正确做法是缩 `pixel_size`：它同时是底板换算与文字渲染的输入，一处改、两者同步。
##
## 字号演进（都是业主口径，别再往回退）：
##   - 0.0026（r1）：字高 0.13m ⇒「对话框也太小了」。
##   - 0.0042（r2）：字高 0.20m ⇒ 仍然「还是需要大一点太小了」。
##   - **0.0084（r3）：字高 0.40m，在 r2 基础上把字整体放大一倍**（业主「大一倍先」）。
##
## ⚠️ `wrap_width_px` **不要跟着翻倍**。它是"每行多少像素"的上限：
##   翻成 1120 时那句 20 字的台词刚好塞进一行 ⇒ 气泡变成 8.27m 宽的横幅，
##   横跨整个屏幕（2026-11-02 实拍确认）。保持 560（≈ 11 个汉字一行）才有两行，
##   世界尺寸 4.7m × 1.21m，比例正常。
const BUBBLE_PIXEL_SIZE := 0.0084
const BUBBLE_WRAP_PX := 560

## 头顶分层（缩放 0.8 之后的身高口径）。
##
## 可见几何实测高 **1.519m**（缩放前），乘 0.8 后 **1.215m** —— A13 断言同一条链。
## 头顶只有两层，且**互斥**（提示在 `talk_engaged` 时收起，气泡在未搭话时不显示）：
##   - 交互提示：50 号字 × `PROMPT_PIXEL_SIZE 0.005` = 0.25m 高，以 `position.y` 为中心，
##     中心 1.44 ⇒ 底边 1.315，离头顶 0.10m。
##   - 台词气泡：以**自身中心**为原点（`SpeechBubble3D._relayout` 用 `half` 算几何）。
##     两行时高 `(2×48 + 内边距 48) × 0.0084 = 1.21m`，半高 0.605。
##
## ⚠️ **俯视角下"抬高"会被压缩**（2026-11-02 业主「对话框会遮住整个角色，往上放一些」）：
##   基地相机俯角约 53° ⇒ 世界 Y 每抬 1m，屏幕上只移动 `cos53° ≈ 0.60m`。
##   中心 2.05（底边 1.445）时气泡底边离头顶 0.23m 世界 ⇒ 屏幕仅 **0.14m**，
##   折算到 720p 只有 3~4 像素 —— 看着就是"贴在头上、把角色盖住"。
##   中心 2.80（底边 2.195）实测**仍然不够**：实拍屏幕间隙只有 **0.34 个角色高**，
##   气泡下缘压着头顶、还盖住了黄色 `[E] 交谈`（`base99_npc_talk.png` 核对）。
##   现在中心取 **3.40**（底边 2.795），世界间隙 1.58m ⇒ 屏幕约 **0.78 个角色高**。
##   经验：俯视角下要"看得出空隙"，世界间隙至少得 ≈ 1.3 倍角色身高。
##   A14b 按屏幕等效量守门（≥ 0.45 个角色屏幕高），别再只比世界米数。
const HEAD_TOP_HEIGHT := 1.215
const PROMPT_HEIGHT := 1.44
const BARK_HEIGHT := 3.40

## 对话示意框的挂高（米）。
##
## 业主 2026-11-10：「头顶对话框太挡角色了……只做成说话示意的样子」。
## `BARK_HEIGHT=3.40` 是给**两行文字气泡**（高 1.21m）定的口径；示意框只有 0.46m 高，
## 再挂 3.40 就成了飘在半空的小方块。这里按「头顶 1.215 + 间隙 0.25 + 半高 0.23」定。
const DIALOGUE_INDICATOR_HEIGHT := 1.86

const PROMPT_FONT_SIZE := 50
const PROMPT_PIXEL_SIZE := 0.005
## 与 `BaseFacility3D` 的黄色提示牌同色同字号：场上的"能按 E"只有一种长相。
const PROMPT_COLOR := Color(1.0, 0.82, 0.28)

@export var npc_id := NpcCatalog.NPC_BASE99_GREEN
## 巡逻点（相对本节点的局部偏移，y 分量不参与移动，只用于读到错误的作者数据时兜底）。
## 少于 2 个点时 NPC 原地待机。
@export var patrol_offsets: Array[Vector3] = [Vector3.ZERO, Vector3(0.0, 0.0, -3.2)]
@export var patrol_enabled := true
## 是否在玩家搭话时回头看着玩家。默认开：站着被搭话却背对着人很怪。
@export var face_player_when_talking := true

var _display_name := ""
var _role := ""
var _visual_root: Node3D
var _bark: CharacterBark3D
## 当前这句对话在底栏里的 run_id。空 = 没在说话。
##
## 文字的唯一载体是 `DialogueUI`（业主 2026-11-10），头顶气泡只出示意；
## 所以"这句说完了没"要问底栏，而不是问气泡。
var _dialogue_run := ""
var _prompt_label: Label3D
var _interaction_area: Area3D
var _collision_shape: CollisionShape3D

var _body_joint: Node3D
var _head_joint: Node3D
var _foot_l: Node3D
var _foot_r: Node3D
var _hand_l: Node3D
var _hand_r: Node3D
var _ear_l: Node3D
var _ear_r: Node3D

var _base_body := Vector3.ZERO
var _base_head := Vector3.ZERO
var _base_foot_l := Vector3.ZERO
var _base_foot_r := Vector3.ZERO
var _base_hand_l := Vector3.ZERO
var _base_hand_r := Vector3.ZERO
var _base_ear_l := Vector3.ZERO
var _base_ear_r := Vector3.ZERO

var _player_in_range := false
var _player: Node3D = null
var _line_index := -1
var _dialogue_visible := false
var _interaction_focused := false
## 已被搭话：停住 + 面向玩家，直到玩家走出交互范围才恢复巡逻。
## 用"离开范围"而不是"气泡消失"作解除条件 —— 否则气泡 6 秒后自动收起，
## NPC 会在玩家还站着的情况下自己走开。
var _talk_engaged := false
var _skin_material: StandardMaterial3D
var _painted_mesh_count := 0

var _patrol_world: Array[Vector3] = []
## 运行时用世界坐标指定的巡逻线（见 `set_patrol_world`）。非空时优先于 `patrol_offsets`。
var _patrol_world_from_anchors: Array[Vector3] = []
var _patrol_target := 0
var _dwelling := false
var _dwell_left := 0.0
var _moving := false
var _elapsed := 0.0
var _gait_phase := 0.0
## 当前朝向（弧度）。和 `rotation.y` 分开存：插值不能从"上一帧已写回的值"出发，
## 否则转身会越转越慢、永远追不上目标。
var _yaw := 0.0
var _yaw_target := 0.0

# —— 剧情节拍（一次性迎宾，见 `NpcStoryBeatService`）——
#
# 数据流向：`NpcCatalog`（说什么）→ `NpcStoryBeatService`（该不该说 / 说过没有）→
# 本节点（站在哪、什么时候开口、说完回巡逻线）。本节点**不判断游戏事实、不写存档**。

## 迎宾站位（世界坐标）与"面朝哪里等"。由 `TowerDescent3D` 按作者锚点传入。
var _standby_world := Vector3.ZERO
var _standby_look_world := Vector3.ZERO
var _has_standby := false
## 当前待播节拍（`get_pending_beat` 的结论，含 `beat_id`）。空 = 没有要说的。
var _pending_beat: Dictionary = {}
## 正在"站在边上等玩家"。
var _story_standby := false
## 节拍已经开始播（第一句已出口）。
var _story_beat_delivered := false
## 节拍台词逐句轮播：当前句与总句数。全部播完才落盘并收工。
var _story_lines: Array[String] = []
var _story_line_index := 0
## 迎宾期间记住的玩家引用（由 `_resolve_hail_player()` 写入，见该函数注释）。
var _story_player: Node3D = null
## "装配方没给迎宾站位"的警告只打一次。
var _standby_warned := false

# —— 脚本化演出（不走时间轴剧本的短演出，2026-11-08 基地战败救援）——
#
# 与剧情节拍的区别：节拍是**一次性**的（`npc_beat:` 落盘），演出是**每次成立就播一次**
# （玩家每死一次回基地都要被捞一次）。所以不能复用节拍的历史判定，
# 但可以复用同一套表现：停巡、站定、转头看人、气泡逐句。
#
# 演出期间节拍让位（`_apply_story_state` 直接 return）：两套东西同时想摆这个人，
# 只会互相拽位置。
var _scripted_active := false
var _scripted_point := Vector3.ZERO
var _scripted_look := Vector3.ZERO
var _scripted_move_target := Vector3.ZERO
var _scripted_move_active := false
var _scripted_gesture := ""
var _scripted_facing_active := false
var _walking_speed_override := WALK_SPEED


func _ready() -> void:
	add_to_group(INTERACTION_GROUP)
	add_to_group(PlayerInteractionController3D.PROVIDER_GROUP)
	_resolve_content()
	_build_interaction_area()
	_build_visual()
	_apply_skin()
	_capture_joints()
	_build_prompt()
	_build_bark()
	_build_patrol()
	_yaw = rotation.y
	_yaw_target = _yaw
	_apply_story_state()
	if not DialogueUI.dialogue_finished.is_connected(_on_dialogue_finished):
		DialogueUI.dialogue_finished.connect(_on_dialogue_finished)


func configure(config: Dictionary) -> void:
	npc_id = str(config.get("npc_id", npc_id))
	_resolve_content()
	configured.emit(npc_id)
	refresh_story_state()


# —— 内容 ——

func _resolve_content() -> void:
	if not NpcCatalog.has_npc(npc_id):
		push_warning("[NpcCharacter3D] 未知 npc_id 『%s』，退化为节点名展示。" % npc_id)
		_display_name = name
		_role = ""
		return
	_display_name = NpcCatalog.get_display_name(npc_id)
	_role = NpcCatalog.get_role(npc_id)


## 名字与身份**不上屏**（2026-11-02 业主口径：头顶只留交互提示和台词）。
## 两者仍留在内容目录与快照里：剧情/任务/日志要认人，只是不再画在头顶。
func get_display_name() -> String:
	return _display_name


func get_role() -> String:
	return _role


func get_line_count() -> int:
	return NpcCatalog.get_line_count(npc_id)


func get_current_line() -> String:
	if _line_index < 0:
		return ""
	return NpcCatalog.get_line(npc_id, _line_index)


## 当前待播节拍（副本，含 `beat_id`）。空字典 = 没有要说的。
## 验收与调试入口；正常播放不需要外部调用。
func get_pending_story_beat() -> Dictionary:
	return _pending_beat.duplicate(true)


func get_story_beat_id() -> String:
	return str(_pending_beat.get("beat_id", ""))


## 是否正"站在边上等玩家"。
func is_story_standby() -> bool:
	return _story_standby


# —— 脚本化演出 ——

## 钉到指定世界点、面朝目标点，等演出方喂台词。**不进节拍历史、不写盘。**
##
## 调用即停巡；`end_scripted_appearance()` 之前不会自己走开，也不会被
## `refresh_story_state()` 拽去迎宾点位。
func begin_scripted_appearance(point: Vector3, look_point: Vector3) -> void:
	_scripted_active = true
	_scripted_point = point
	_scripted_look = look_point
	# 演出优先：把待播节拍让出来（不落盘、也不消耗），演出结束后重新求值。
	_pending_beat = {}
	_story_standby = false
	_story_beat_delivered = false
	_story_lines.clear()
	_story_line_index = 0
	global_position = Vector3(point.x, global_position.y, point.z)
	_moving = false
	_dwelling = false
	_dwell_left = 0.0
	_face_point_immediate(look_point)
	_refresh_prompt_visibility()


func end_scripted_appearance() -> void:
	if not _scripted_active:
		return
	_scripted_active = false
	_scripted_move_active = false
	_scripted_gesture = ""
	_scripted_facing_active = false
	hide_dialogue()
	# 演出结束后才重新求值节拍：装备好锚点、玩家已能操作，这时站过去才看得见。
	refresh_story_state()


func is_scripted_appearance() -> bool:
	return _scripted_active


## 主线演出用移动：位置和步态仍由 NPC 实体自己驱动，适配器不摆骨骼。
func scripted_move_to(target: Vector3, speed := WALK_SPEED) -> bool:
	if not _scripted_active:
		return false
	_scripted_move_target = Vector3(target.x, global_position.y, target.z)
	_scripted_move_active = true
	_moving = true
	_walking_speed_override = maxf(0.05, speed)
	return true


func scripted_gesture(name: String) -> bool:
	if not _scripted_active:
		return false
	_scripted_gesture = name
	return true


func set_scripted_facing(yaw: float) -> void:
	_scripted_facing_active = true
	_yaw = yaw
	_yaw_target = yaw
	rotation.y = yaw


func clear_scripted_facing() -> void:
	_scripted_facing_active = false


## 演出用：直接说一句（不推进循环台词、不写节拍历史）。
func say_scripted_line(text: String, hold := 3.2) -> bool:
	var clean := text.strip_edges()
	if clean.is_empty() or _bark == null:
		return false
	_dialogue_visible = true
	# 底栏没收下（例如 autoload 不在或文字为空）就当这句没说，别回假成功。
	if not _present_dialogue(clean, maxf(0.6, hold)):
		_dialogue_visible = false
		return false
	_refresh_prompt_visibility()
	interaction_changed.emit(true, clean)
	return true


## ── 对话的统一出口（业主 2026-11-10）──────────────────────────────────
##
## 「头顶对话框太挡角色了……只做成说话示意的样子，有点点点的动画。但是真实文字
##   在下方的原来系统对话的那个地方，以后所有对话和系统信息统一在那边。」
##
## 所以**对话**（剧情台词、节拍提醒、按 E 聊天、救援演出）走这里：
##   头顶 → `say_indicator()` 只跳三点，不显示文字
##   文字 → `DialogueUI.show_dialogue_line()`，署名用 NPC 显示名
##
## 为什么收口在 NPC 而不是 Adapter：节拍、自由交谈、救援三条路径都在本文件内部
## 直接调，只在 Adapter 接会漏掉两条。**自言自语（`say_bark`）不走这里** ——
## 业主明确「开灯这类自言自语要保留」原来的头顶文字气泡。
func _present_dialogue(text: String, auto_sec := -1.0) -> bool:
	var clean := text.strip_edges()
	if clean.is_empty() or _bark == null:
		return false
	var auto := auto_sec if auto_sec > 0.0 else DialogueUI.line_hold_for_text(clean)
	# 示意框自己也算一个兜底停留：底栏被顶掉时（interrupt 不发旧 run 的 aborted）
	# 至少会在预计结束时间自行收起，不会永久挂在头上。
	var typing := float(clean.length()) / DialogueUI.DEFAULT_CHARS_PER_SEC
	_bark.say_indicator(typing + auto + 0.5, DIALOGUE_INDICATOR_HEIGHT)
	_dialogue_run = DialogueUI.show_dialogue_line(clean, _display_name, auto)
	return not _dialogue_run.is_empty()


## 底栏这句播完了（自然结束 / 被收起）→ 收掉头顶示意框。
## 只认自己这条 run：底栏是全局单例，别的系统也可能在上面说话。
func _on_dialogue_finished(run_id: String, _outcome: String) -> void:
	if run_id.is_empty() or run_id != _dialogue_run:
		return
	_dialogue_run = ""
	if _bark != null:
		_bark.hide_now()


## 演出用：这一句现在能不能被玩家推进（底栏在打字，或已全显还在停留）。
##
## 与 `is_free_bark_active()` 分开：那个只放行**自由交谈**，脚本演出（救援/交接）
## 一律返回 false，所以救援归航那两句原本点不动。这里只回答\"底栏里有没有我的可
## 压缩的句子\"，不判断是谁在演、也不启动任何交互。
func is_scripted_line_progressable() -> bool:
	return is_speaking()


## 演出用：玩家按空格/点左键推一下当前这句（业主 2026-11-10「死亡回到基地后，
## 绿苔的对话也要能点击快速过」）。
##
## 两段语义与自由交谈完全一致：打字中 → 立刻全显；已全显 → 收起这句停留，
## 由演出方（`Base99Rescue3D`）的等待循环接着播下一句。**不跳句、不跳演出**。
func advance_scripted_line() -> bool:
	if not is_speaking():
		return false
	if DialogueUI.is_typing():
		DialogueUI.reveal_all()
		return true
	DialogueUI.finish_current_hold()
	return true


## 演出用：临时放宽气泡换行宽度。`px <= 0` 恢复默认。
##
## 为什么需要它：挂高 3.40m 是按**两行**气泡定的口径（见 `BARK_HEIGHT` 的注释），
## 26 字的长句在默认 560px（≈11 汉字/行）下会排成三行、把气泡顶出画面上缘。
## 抬高挂点会离开视线中心，改字号会和别的台词观感不一致 ⇒ 只放宽换行。
func set_bubble_wrap_width(px: int) -> void:
	if _bark == null:
		return
	var bubble := _bark.get_bubble()
	if bubble == null:
		return
	bubble.set_wrap_width(BUBBLE_WRAP_PX if px <= 0 else px)


## 立刻朝向某点（不插值）。与 `_engage_talk()` 同一口径：这一帧就该看到脸。
func _face_point_immediate(point: Vector3) -> void:
	var to_point := point - global_position
	to_point.y = 0.0
	if to_point.length() <= 0.01:
		return
	_yaw_target = atan2(-to_point.x, -to_point.z)
	_yaw = _yaw_target
	rotation.y = _yaw


# —— 构建 ——

func _build_interaction_area() -> void:
	_interaction_area = Area3D.new()
	_interaction_area.name = "InteractionRange"
	_interaction_area.collision_layer = 0
	_interaction_area.collision_mask = 1
	_interaction_area.monitoring = true
	_interaction_area.monitorable = true
	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "Shape"
	var shape := SphereShape3D.new()
	shape.radius = INTERACTION_RADIUS
	_collision_shape.shape = shape
	_collision_shape.position = Vector3(0.0, INTERACTION_CENTER_HEIGHT, 0.0)
	_interaction_area.add_child(_collision_shape)
	add_child(_interaction_area)
	_interaction_area.body_entered.connect(_on_body_entered)
	_interaction_area.body_exited.connect(_on_body_exited)


## 只借几何：从玩家场景里摘出 `Avatar3D/VisualRoot`，然后**整只扔掉玩家外壳**
## （`CharacterBody3D` + 相机 + 手电 + 视觉代理，NPC 一个都用不上）。
##
## ⚠️ 顺序是硬要求：
##   - 必须 `avatar.remove_child(visual)` ——VisualRoot 的父 `Avatar3D` 挂着
##     `PlayerAvatar3D` 脚本，一旦它进树，`_ready()` 会跑整套玩家表现
##     （换装、状态机、换弹环），NPC 会莫名其妙开始播玩家的动作。
##   - `shell.free()` 在 `add_child(visual)` **之前** —— 先释放外壳，再把干净的
##     `VisualRoot` 挂上来，避免任何一帧里玩家外壳还挂在树上。
##   - 体型倍率取 `avatar.scale × PLAYER_BASE_SIZE_MULTIPLIER`：玩家那边是
##     `Player3D` 在运行时乘上去的，实例化出来的场景还是原始尺寸，照抄这一步
##     才能和玩家等高。
func _build_visual() -> void:
	var player_scene := load(PLAYER_SCENE_PATH) as PackedScene
	if player_scene == null:
		push_error("[NpcCharacter3D] 玩家角色场景加载失败：%s" % PLAYER_SCENE_PATH)
		return
	var shell := player_scene.instantiate()
	var avatar := shell.get_node_or_null(PLAYER_AVATAR_NODE) as Node3D
	var visual: Node3D = null
	if avatar != null:
		visual = avatar.get_node_or_null("VisualRoot") as Node3D
	if visual == null:
		push_error("[NpcCharacter3D] 玩家场景缺少 %s/VisualRoot，NPC 无模型。" % PLAYER_AVATAR_NODE)
		shell.free()
		return
	var source_scale := avatar.scale
	avatar.remove_child(visual)
	shell.free()
	visual.name = "VisualRoot"
	visual.scale = source_scale * PLAYER_BASE_SIZE_MULTIPLIER
	_visual_root = visual
	add_child(_visual_root)
	_attach_face_mask()


## 把主角的电子面具挂到头上。位置与玩家侧一致：直接挂在 `HeadJoint` 下
## （面具源按 HeadJoint 静止原点导出，自己带偏移），不额外做变换。
func _attach_face_mask() -> void:
	if _visual_root == null:
		return
	var head := _visual_root.get_node_or_null("BunnyRig/HeadJoint") as Node3D
	if head == null:
		push_warning("[NpcCharacter3D] 模型缺少 HeadJoint，NPC 无面部。")
		return
	if FACE_MASK_SCENE == null:
		push_warning("[NpcCharacter3D] 电子面具场景加载失败，NPC 无面部。")
		return
	var mask := FACE_MASK_SCENE.instantiate() as Node3D
	if mask == null:
		return
	mask.name = FACE_MASK_NODE
	head.add_child(mask)


## 全绿皮肤：给**每一个本体网格**盖同一份材质。
##
## 用 `material_override` 而不是改原材质资源：原材质是共享的（玩家也在用），
## 改了会把玩家一起染绿。覆盖是实例级的，天然不影响玩家。
##
## **面饰排除在外**（见 `FACE_MASK_SCENE` 的注释）：`_is_under_face_mask` 判断沿父链
## 找面饰节点 —— 面具的网格是 GLB 内嵌的，没有稳定路径可写死，只能按祖先判定。
##
## **不做自发光**：第一版给 0.06→0.30 的自发光兜夜景可读性，结果是整只泛荧光，
## 业主 2026-11-02 明确指出「为什么是自发光的绿色？荧光感太强了」。
## 现在完全靠场景光照（99F 有日夜循环，白天/夜里都用实拍复核，见开发记录）。
func _apply_skin() -> void:
	var albedo := NpcCatalog.get_skin_albedo(npc_id)
	var emission := NpcCatalog.get_skin_emission(npc_id)
	_skin_material = StandardMaterial3D.new()
	_skin_material.resource_name = "NPC_GreenSkin"
	_skin_material.albedo_color = albedo
	_skin_material.metallic = 0.04
	_skin_material.roughness = 0.74
	if emission > 0.0:
		_skin_material.emission_enabled = true
		_skin_material.emission = albedo.darkened(0.25)
		_skin_material.emission_energy_multiplier = emission
	_painted_mesh_count = 0
	if _visual_root == null:
		return
	for node: Node in _visual_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null:
			continue
		if _is_under_face_mask(mesh_instance):
			continue
		mesh_instance.material_override = _skin_material
		_painted_mesh_count += 1


func _is_under_face_mask(node: Node) -> bool:
	var cursor := node.get_parent()
	while cursor != null:
		if cursor.name == FACE_MASK_NODE:
			return true
		cursor = cursor.get_parent()
	return false


func _capture_joints() -> void:
	if _visual_root == null:
		return
	_body_joint = _visual_root.get_node_or_null("BunnyRig/BodyJoint") as Node3D
	_head_joint = _visual_root.get_node_or_null("BunnyRig/HeadJoint") as Node3D
	_foot_l = _visual_root.get_node_or_null("BunnyRig/FeetRoot/FootJointL") as Node3D
	_foot_r = _visual_root.get_node_or_null("BunnyRig/FeetRoot/FootJointR") as Node3D
	_hand_l = _visual_root.get_node_or_null("BunnyRig/HandRoot/HandJointL") as Node3D
	_hand_r = _visual_root.get_node_or_null("BunnyRig/HandRoot/HandJointR") as Node3D
	_ear_l = _visual_root.get_node_or_null("BunnyRig/HeadJoint/Ears/EarSocketL") as Node3D
	_ear_r = _visual_root.get_node_or_null("BunnyRig/HeadJoint/Ears/EarSocketR") as Node3D
	if _body_joint != null:
		_base_body = _body_joint.position
	if _head_joint != null:
		_base_head = _head_joint.position
	if _foot_l != null:
		_base_foot_l = _foot_l.position
	if _foot_r != null:
		_base_foot_r = _foot_r.position
	if _hand_l != null:
		_base_hand_l = _hand_l.position
	if _hand_r != null:
		_base_hand_r = _hand_r.position
	if _ear_l != null:
		_base_ear_l = _ear_l.rotation
	if _ear_r != null:
		_base_ear_r = _ear_r.rotation


## 头顶交互提示。**只有被聚焦时可见**，且与台词气泡互斥。
##
## 为什么不复用交互圆点：圆点是控制器统一建的白色小件，玩家的诉求是"把上面的白点去掉"，
## 并且提示离得远就冒出来。这里连 `is_interaction_dot_visible() = false` 一起关掉，
## 改用与基地设施同款的黄色文字牌（`BaseFacility3D.PROMPT_LABEL_*`）。
func _build_prompt() -> void:
	_prompt_label = Label3D.new()
	_prompt_label.name = "PromptLabel"
	_prompt_label.position = Vector3(0.0, PROMPT_HEIGHT, 0.0)
	_prompt_label.text = PROMPT_TEXT
	_prompt_label.font_size = PROMPT_FONT_SIZE
	_prompt_label.outline_size = 8
	_prompt_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	_prompt_label.modulate = PROMPT_COLOR
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.pixel_size = PROMPT_PIXEL_SIZE
	_prompt_label.no_depth_test = false
	_prompt_label.visible = false
	add_child(_prompt_label)


func _refresh_prompt_visibility() -> void:
	if _prompt_label == null:
		return
	# 说话中不再提示"按 E 交谈"：已经谈上了，头顶让给台词气泡。
	#
	# ⚠️ 条件里同时看 `_dialogue_visible`（不只 `_talk_engaged`）：气泡可能由
	# `advance_dialogue()` 直接推进（剧情/测试），那条路径不经过 `perform_interaction`，
	# `_talk_engaged` 仍是 false。少了这一项，黄色提示会压在气泡下缘上
	# （2026-11-02 `base99_npc_talk.png` 实测）。
	var talking := _talk_engaged or _dialogue_visible
	_prompt_label.visible = _interaction_focused and _player_in_range and not talking


func _build_bark() -> void:
	_bark = CharacterBark3D.attach_to(self, BARK_HEIGHT)
	if _bark == null:
		return
	# 气泡本体由 CharacterBark3D 懒创建，`get_bubble()` 会先把它建出来（含 `_build_nodes`），
	# 之后 `_relayout` 才读得到我们改过的 `pixel_size`。
	var bubble := _bark.get_bubble()
	if bubble == null:
		push_warning("[NpcCharacter3D] 气泡未创建，NPC 台词将使用默认字号。")
		return
	bubble.wrap_width_px = BUBBLE_WRAP_PX
	var label := bubble.get_node_or_null("Text") as Label3D
	if label == null:
		push_warning("[NpcCharacter3D] 气泡缺少 Text 节点，无法调字号。")
		return
	label.pixel_size = BUBBLE_PIXEL_SIZE


# —— 巡逻 ——

## 巡逻点换算与设置。
##
## 两条入口：
##   - `patrol_offsets`（场景作者用）：**相对本节点局部坐标**。
##   - `set_patrol_world()`（运行时装配用，TowerDescent3D 走这条）：**世界坐标**。
##
## 为什么要有世界坐标版：99F 基地的布置层是运行时 reparent 进 `facility` 房间的，
## 房间自身有位置/旋转；作者在 `zone_base.tscn` 里画的两个锚点是局部值，代码若
## 自己拼 `global_transform * offset` 就会把房间旋转算两遍。直接吃世界点最省事。
func _build_patrol() -> void:
	if not _patrol_world_from_anchors.is_empty():
		_adopt_patrol_points(_patrol_world_from_anchors)
		return
	var world_points: Array[Vector3] = []
	for offset: Vector3 in patrol_offsets:
		world_points.append(global_transform * offset)
	_adopt_patrol_points(world_points)


## 用世界坐标覆盖巡逻线。必须在节点进树**之后**调用（或用 `call_deferred`），
## 否则 `global_transform` 还没算出来。少于 2 点 ⇒ 原地待机。
func set_patrol_world(points: Array[Vector3]) -> void:
	_patrol_world_from_anchors = points.duplicate()
	if is_node_ready():
		_adopt_patrol_points(_patrol_world_from_anchors)


func _adopt_patrol_points(points: Array[Vector3]) -> void:
	_patrol_world.clear()
	for point in points:
		_patrol_world.append(point)
	_patrol_target = 0
	_dwelling = false
	_dwell_left = 0.0
	# 起点就在第一个路点上，否则第一段会"先走回原点"再出发。
	if _patrol_world.size() >= 2:
		global_position = _patrol_world[0]
		_patrol_target = 1


# —— 剧情节拍（一次性迎宾）——
#
# 分工见 `NpcStoryBeatService` 的文件头：内容在 `NpcCatalog`、判定与落盘在服务、
# 这里只管"站在哪、什么时候开口、说完怎么回到巡逻线"。

## 指定迎宾站位（世界坐标）与"等待时面朝哪一点"。由 `TowerDescent3D` 按作者锚点传入 ——
## 本节点不写死坐标，美术挪锚点即换位置。
func set_standby_world(point: Vector3, look_world: Vector3) -> void:
	_standby_world = point
	_standby_look_world = look_world
	_has_standby = true
	if is_node_ready():
		_apply_story_state()


## 重新求值"有没有该播的节拍"。基地房间每次被进入时由 `TowerDescent3D` 调一次：
## 它兜住"同一份塔楼场景里出去打完再回来"的路径（那条路不会重建 NPC）。
func refresh_story_state() -> void:
	_apply_story_state()


func _apply_story_state() -> void:
	# 脚本化演出期间节拍让位：位置归演出方，节拍等人走了再重新求值。
	if _scripted_active:
		return
	# 正在处理中的节拍不重算。
	#
	# 玩家走进基地会触发一次 `refresh_story_state()`，而那一刻节拍可能**刚好**已经
	# 说出口、`get_pending_beat()` 已经返回空（因为已落盘）。若照常重算，会把
	# `_pending_beat` 清空、`_story_standby` 关掉 —— 气泡还挂着、人却走回巡逻线了
	# （2026-11-04 首轮验收 S06 实测就是这个现象）。
	if not _pending_beat.is_empty() and (_story_standby or _story_beat_delivered):
		return
	_pending_beat = NpcStoryBeatService.get_pending_beat(npc_id)
	if _pending_beat.is_empty():
		_exit_story_standby()
		return
	_story_beat_delivered = false
	if not _has_standby:
		# 装配顺序问题，不是错误：`_ready()` 里求值时 `set_standby_world()` 还没被调用，
		# 真正"锚点缺失"由 `TowerDescent3D` 自己警告。这里只在**第一帧之后**还没拿到
		# 站位时才提醒一次（见 `_tick_story_beat`），避免每次开档都打一条假警告。
		_story_standby = false
		return
	_story_standby = true
	# 只改水平位置：y 沿用当前地面高度（本节点本来就贴地）。
	global_position = Vector3(_standby_world.x, global_position.y, _standby_world.z)
	_moving = false
	_dwelling = false
	_dwell_left = 0.0
	var to_look := _standby_look_world - global_position
	to_look.y = 0.0
	if to_look.length() > 0.01:
		_yaw_target = atan2(-to_look.x, -to_look.z)
		_yaw = _yaw_target
		rotation.y = _yaw
	_refresh_prompt_visibility()


## 站到边上等玩家：停巡、不动，玩家进 `HAIL_RADIUS` 就开口。
##
## ⚠️ 找玩家**不能只看 `_player`**：那个引用由 1.5m 交互热区写入，是"能不能按 E"的口径；
## 迎宾要的是"走进 4m 就招呼"，用它会变成必须贴脸才开口。这里另取场景里的
## `player_3d` 组成员（基地里只有一个玩家），两套半径各自独立。
func _tick_story_beat() -> void:
	if _pending_beat.is_empty():
		return
	if _story_beat_delivered:
		# 逐句轮播：上一句气泡放完就接下一句；全部放完才收工回巡逻线。
		if is_speaking() or _talk_engaged:
			return
		if _story_line_index + 1 < _story_lines.size():
			_story_line_index += 1
			_say_story_line(true)
			return
		_finish_story_beat()
		return
	var target := _resolve_hail_player()
	if target == null:
		return
	var to_player := target.global_position - global_position
	to_player.y = 0.0
	if to_player.length() <= HAIL_RADIUS:
		speak_pending_story_beat()


## 装配方一直没给迎宾站位时提醒一次：节拍照播，只是不站定。
## 放在这里（而不是 `_ready`）是因为 `_ready` 时 `set_standby_world()` 尚未被调用。
func _warn_missing_standby_once() -> void:
	if _has_standby or _standby_warned or _pending_beat.is_empty():
		return
	_standby_warned = true
	push_warning("[NpcCharacter3D] 未设置迎宾站位，NPC『%s』将在巡逻线上打招呼。" % npc_id)


## 迎宾判定用的玩家引用：优先交互热区里那个，否则按组取（进门前也要能读距离）。
func _resolve_hail_player() -> Node3D:
	if _player != null and is_instance_valid(_player):
		return _player
	var tree := get_tree()
	if tree == null:
		return null
	var candidate := tree.get_first_node_in_group("player_3d") as Node3D
	if candidate != null and is_instance_valid(candidate):
		_story_player = candidate
		return candidate
	return null


## 把待播节拍的第 0 句说出口。返回是否真的说了（没有待播 / 已经说过 ⇒ false）。
##
## 台词**逐句轮播**，每句一个气泡。不合并成一整段的原因见 `NpcCatalog.STORY_BEATS`
## 的注释：40 字整句会排成 4 行、把气泡顶出画面上缘，而挂高 3.40m 是按两行定的口径。
## 玩家不需要连按 E —— 上一句气泡自然放完后自动接下一句，全部说完才落盘收工。
func speak_pending_story_beat() -> bool:
	if _pending_beat.is_empty() or _story_beat_delivered:
		return false
	var beat_id := str(_pending_beat.get("beat_id", ""))
	_story_lines = NpcCatalog.get_story_beat_lines(npc_id, beat_id)
	if _story_lines.is_empty():
		push_warning("[NpcCharacter3D] 节拍『%s』没有台词，跳过。" % beat_id)
		_pending_beat = {}
		_exit_story_standby()
		return false
	_story_beat_delivered = true
	_story_line_index = 0
	_moving = false
	_dwelling = false
	_dwell_left = 0.0
	_say_story_line(true)
	return true


## 播出当前句。`announce` 只在第一句为真（`story_beat_started` 每条节拍只发一次）。
func _say_story_line(announce: bool) -> void:
	if _story_line_index < 0 or _story_line_index >= _story_lines.size():
		return
	var text := _story_lines[_story_line_index]
	var target := _resolve_hail_player()
	if target != null:
		var to_player := target.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.01:
			_yaw_target = atan2(-to_player.x, -to_player.z)
	_dialogue_visible = true
	# 对话：头顶只出示意框，文字进底栏（业主 2026-11-10）。
	_present_dialogue(text)
	_refresh_prompt_visibility()
	interaction_changed.emit(true, text)
	if announce:
		var beat_id := str(_pending_beat.get("beat_id", ""))
		story_beat_started.emit(npc_id, beat_id, text)


func _finish_story_beat() -> void:
	var beat_id := str(_pending_beat.get("beat_id", ""))
	_pending_beat = {}
	_story_beat_delivered = false
	_story_line_index = 0
	_story_lines.clear()
	# 玩家没在按 E 聊天时把气泡状态一并收掉，让黄色 `[E] 交谈` 重新可用
	# （提醒说完了，接下来想聊就聊）。
	if not _talk_engaged and _dialogue_visible:
		_dialogue_visible = false
		interaction_changed.emit(false, "")
	_exit_story_standby()
	if not beat_id.is_empty():
		# 落盘放在这里而不是第一句出口时：节拍的定义是"这段话听完了"。
		# 半路被玩家打断（走出去、按 E 聊天）不算听完 —— 下次进基地会重播一遍。
		NpcStoryBeatService.mark_beat_played(npc_id, beat_id)
		story_beat_finished.emit(npc_id, beat_id)


## 结束站定并回到巡逻线。从当前位置重新选**最近**的巡逻点，不倒着走回起点。
func _exit_story_standby() -> void:
	if not _story_standby:
		_story_beat_delivered = false
		_refresh_prompt_visibility()
		return
	_story_standby = false
	_story_beat_delivered = false
	if _patrol_world.size() >= 2:
		_patrol_target = _nearest_patrol_index()
		_dwelling = false
		_dwell_left = 0.0
	_refresh_prompt_visibility()


func _nearest_patrol_index() -> int:
	var best := 0
	var best_distance := INF
	for index in _patrol_world.size():
		var distance := _patrol_world[index].distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > 0.5:
		_warn_missing_standby_once()
	_tick_story_beat()
	_tick_patrol(delta)
	_tick_pose(delta)


func _tick_patrol(delta: float) -> void:
	if _scripted_move_active:
		var scripted_offset := _scripted_move_target - global_position
		scripted_offset.y = 0.0
		if scripted_offset.length() <= ARRIVE_EPSILON:
			_scripted_move_active = false
			_moving = false
			return
		var scripted_direction := scripted_offset.normalized()
		_moving = true
		global_position += scripted_direction * _walking_speed_override * delta
		_yaw_target = atan2(-scripted_direction.x, -scripted_direction.z)
		return
	# 搭话中一律钉住：位置不动，也不消耗停留计时（谈完继续从原地走）。
	if _talk_engaged:
		_moving = false
		return
	# 迎宾站定同理：站在边上等人，不该自己走开。
	if _story_standby:
		_moving = false
		return
	# 脚本化演出（基地战败救援）：位置由演出方钉住，这里一步都不许挪。
	if _scripted_active:
		_moving = false
		return
	if not patrol_enabled or _patrol_world.size() < 2:
		_moving = false
		return
	if _dwelling:
		_moving = false
		_dwell_left -= delta
		if _dwell_left <= 0.0:
			_dwelling = false
			_patrol_target = (_patrol_target + 1) % _patrol_world.size()
		return
	var target := _patrol_world[_patrol_target]
	var to_target := target - global_position
	to_target.y = 0.0
	if to_target.length() <= ARRIVE_EPSILON:
		_dwelling = true
		_dwell_left = DWELL_SECONDS
		return
	var direction := to_target.normalized()
	_moving = true
	global_position += direction * WALK_SPEED * delta
	_yaw_target = atan2(-direction.x, -direction.z)


## 朝向插值 + 关节姿态。`_yaw` 独立保存，见字段注释。
func _tick_pose(delta: float) -> void:
	var turn_speed := TURN_SPEED
	# 搭话中、以及迎宾站定时都持续对准玩家：玩家绕着走，它跟着转。
	var facing_player := face_player_when_talking and (
		_talk_engaged or _story_standby or _scripted_active
	)
	if facing_player:
		var target := _resolve_hail_player()
		if target != null:
			var to_player := target.global_position - global_position
			to_player.y = 0.0
			if to_player.length() > 0.01:
				_yaw_target = atan2(-to_player.x, -to_player.z)
			turn_speed = TALK_TURN_SPEED
	_yaw = lerp_angle(_yaw, _yaw_target, clampf(turn_speed * delta, 0.0, 1.0))
	rotation.y = _yaw

	if _moving:
		_gait_phase += delta * 3.2
	var wave := sin(_gait_phase * TAU)
	var lift := absf(wave)

	if _body_joint != null:
		if _moving:
			# 步行：重心上下 + 轻微左右压步（顶视读感比纯上下更"在走"）。
			_body_joint.position = _base_body + Vector3(wave * 0.022, lift * 0.030, 0.0)
			_body_joint.rotation.z = wave * 0.05
		else:
			_body_joint.position = _base_body + Vector3(0.0, sin(_elapsed * 1.7) * 0.012, 0.0)
			_body_joint.rotation.z = sin(_elapsed * 0.9) * 0.012
	if _head_joint != null:
		if _moving:
			# 头部反向稳一点：上半身起伏、头保持水平读感。
			_head_joint.rotation.z = -wave * 0.035
			_head_joint.rotation.x = lift * 0.02
		else:
			_head_joint.rotation.z = -sin(_elapsed * 1.7) * 0.008
			_head_joint.rotation.x = 0.0
	if _foot_l != null:
		_foot_l.position = _base_foot_l + (Vector3(0.0, maxf(0.0, wave) * 0.055, wave * 0.115) if _moving else Vector3.ZERO)
	if _foot_r != null:
		_foot_r.position = _base_foot_r + (Vector3(0.0, maxf(0.0, -wave) * 0.055, -wave * 0.115) if _moving else Vector3.ZERO)
	var gesture_phase := clampf(sin(_elapsed * 3.2) * 0.5 + 0.5, 0.0, 1.0)
	if _hand_l != null:
		_hand_l.position = _base_hand_l
	if _hand_r != null:
		_hand_r.position = _base_hand_r
	if _scripted_gesture == "receive_key":
		if _hand_l != null:
			_hand_l.position += Vector3(0.0, 0.10 + gesture_phase * 0.04, -0.12)
		if _hand_r != null:
			_hand_r.position += Vector3(0.0, 0.10 + gesture_phase * 0.04, -0.12)
	elif _scripted_gesture == "insert_key":
		if _hand_r != null:
			_hand_r.position += Vector3(0.0, 0.18, -0.22)
		if _hand_l != null:
			_hand_l.position += Vector3(0.0, 0.12, -0.16)
	if _ear_l != null:
		_ear_l.rotation = _base_ear_l + Vector3(0.0, 0.0, sin(_elapsed * 2.2) * 0.06)
	if _ear_r != null:
		_ear_r.rotation = _base_ear_r + Vector3(0.0, 0.0, sin(_elapsed * 2.2 + 1.1) * 0.06)


# —— 交互协议（PlayerInteractionController3D）——

func get_interaction_candidate(_player: Player3D) -> Dictionary:
	if not _player_in_range:
		return {}
	return {
		"available": true,
		"interaction_id": "base_npc:%s:%d" % [npc_id, get_instance_id()],
		"position": global_position,
		"priority": PROVIDER_PRIORITY,
		"prompt": PROMPT_TEXT,
	}


func set_interaction_focus(_candidate: Dictionary, focused: bool) -> void:
	_interaction_focused = focused and _player_in_range
	_refresh_prompt_visibility()


## 头顶白点退役（2026-11-02 业主「上面的白点去掉」，随后再次明确「这个白色的交谈和白点不要了」）。
##
## 两道保险，缺一不可：
##   1. `PlayerInteractionController3D.DOT_EXCLUDED_PROVIDER_SCRIPTS` 里登记了本脚本路径
##      ⇒ 控制器**根本不创建**圆点节点，白色「(e) 交谈」压根不会出现。
##   2. 本方法返回 false 作为二次兜底：即使有人把那行路径改掉，圆点也会淡出到不可见。
##
## 提示改由本节点的 `PromptLabel`（黄色 `[E] 交谈`）承担 —— 与基地设施同款，
## 且只在被聚焦时出现。两套白色/黄色提示叠在同一处正是业主要清掉的东西。
func is_interaction_dot_visible() -> bool:
	return false


func get_interaction_dot_anchor() -> Vector3:
	# 圆点已关，保留锚点只是满足 provider 可选协议（别的调用方读它做位置参考）。
	return global_position + Vector3(0.0, PROMPT_HEIGHT, 0.0)


func perform_interaction(_player: Player3D, _candidate: Dictionary) -> bool:
	if not _player_in_range:
		return false
	_engage_talk()
	# 打字机没打完时先按 E = 「跳过这一句的逐字显示」，而不是直接翻到下一句。
	# 文字在本轮改造后位于底栏（业主 2026-11-10），所以进度要问底栏。
	if DialogueUI.is_active() and _dialogue_run == DialogueUI.current_run_id() and DialogueUI.is_typing():
		DialogueUI.reveal_all()
		return true
	advance_dialogue()
	return true


## 公开当前对话在底栏里的 run_id。
##
## 文字唯一载体是 `DialogueUI`（2026-11-10），头顶气泡只剩示意；
## 导演/适配层靠这个句柄判断“我说的那句还在不在”，而不是去问气泡。
func get_dialogue_run_id() -> String:
	return _dialogue_run


## ⚠仅保留给自言自语路径（`say_bark` → 头顶文字气泡）。
## 对话已不再经气泡承载文字，导演不要再用它当对白载体。
func get_scripted_dialogue_carrier() -> CharacterBark3D:
	return _bark


## 仅已开始且仍在交互范围内的自由对白可接受鼠标；不启动交互或推进脚本演出。
func is_free_bark_active() -> bool:
	return not _scripted_active and _talk_engaged and _player_in_range and _pending_beat.is_empty() and is_speaking()


func advance_free_bark() -> bool:
	if get_tree().paused or not is_free_bark_active():
		return false
	if DialogueUI.is_typing():
		DialogueUI.reveal_all()
		return true
	# 已全显：收起这句停留，紧接着播下一句（自由交谈是循环往复，不靠底栏的“播完就关”）。
	DialogueUI.finish_current_hold()
	advance_dialogue()
	return true


## 立刻停步并转向搭话者（业主 2026-11-02「点击交谈后，角色要立刻停下来，面对角色」）。
##
## "立刻"= 朝向直接吸附到目标角，不等插值：按 E 的那一帧就该看到脸。
## 之后的持续对准交给 `_tick_pose`（玩家绕着走它也跟着转）。
func _engage_talk() -> void:
	if _talk_engaged:
		return
	_talk_engaged = true
	_moving = false
	_dwelling = false
	_dwell_left = 0.0
	if _player != null and is_instance_valid(_player):
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.01:
			_yaw_target = atan2(-to_player.x, -to_player.z)
			_yaw = _yaw_target
			rotation.y = _yaw
	_refresh_prompt_visibility()


## 推进一句。首次从第 0 句开始；走到最后一句之后再按一次回到第 0 句，
## 那一次的返回值 `finished_cycle` 为 true（停在最后一句时不报完成 ——
## 玩家应该有时间把最后一句读完，而不是话一出口就被判"讲完一轮"）。
func advance_dialogue() -> Dictionary:
	var count := get_line_count()
	if count <= 0:
		return {"spoken": false, "reason": "no_lines"}
	var finished_cycle := _line_index >= count - 1
	_line_index = 0 if _line_index < 0 or finished_cycle else _line_index + 1
	var text := NpcCatalog.get_line(npc_id, _line_index)
	_dialogue_visible = true
	# 说话即收起黄色提示（不只看 `_talk_engaged`，见 `_refresh_prompt_visibility` 的注释）。
	_refresh_prompt_visibility()
	_present_dialogue(text)
	interaction_changed.emit(true, text)
	npc_spoke.emit(npc_id, _line_index, text, finished_cycle)
	return {
		"spoken": true,
		"line_index": _line_index,
		"text": text,
		"finished_cycle": finished_cycle,
	}


func hide_dialogue() -> void:
	if _bark != null:
		_bark.hide_now()
	# 只关自己那条：底栏可能已经换成了别人的消息。
	if not _dialogue_run.is_empty():
		if DialogueUI.is_active() and DialogueUI.current_run_id() == _dialogue_run:
			DialogueUI.close()
		_dialogue_run = ""
	if not _dialogue_visible:
		return
	_dialogue_visible = false
	_line_index = -1
	_refresh_prompt_visibility()
	interaction_changed.emit(false, "")


func is_dialogue_visible() -> bool:
	return _dialogue_visible


## 正在说一句对话。
##
## 判据由“气泡还没消失”改为“底栏我这条还在播”（2026-11-10 文字改到底栏）。
## 节拍逐句轮播与救援演出的等待循环都读这里，所以必须指向真正的文字载体。
## 自言自语（`say_bark`）仍看气泡。
func is_speaking() -> bool:
	if not _dialogue_run.is_empty():
		return DialogueUI.is_active() and DialogueUI.current_run_id() == _dialogue_run
	return _bark != null and _bark.is_speaking()


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player_3d"):
		return
	_player_in_range = true
	_player = body
	_refresh_prompt_visibility()


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player_3d"):
		return
	_player_in_range = false
	_interaction_focused = false
	_player = null
	# 人走了才解除"搭话定住"，NPC 回到巡逻线上继续走。
	_talk_engaged = false
	hide_dialogue()
	_refresh_prompt_visibility()


# —— 快照（验收与调试）——

func get_snapshot() -> Dictionary:
	return {
		"npc_id": npc_id,
		"display_name": _display_name,
		"role": _role,
		"line_count": get_line_count(),
		"line_index": _line_index,
		"in_range": _player_in_range,
		"dialogue_visible": _dialogue_visible,
		"speaking": is_speaking(),
		"moving": _moving,
		"talk_engaged": _talk_engaged,
		"patrol_enabled": patrol_enabled,
		"patrol_target": _patrol_target,
		"patrol_point_count": _patrol_world.size(),
		"dwelling": _dwelling,
		"position": global_position,
		"yaw": rotation.y,
		"painted_mesh_count": _painted_mesh_count,
		"visual_scale": _visual_root.scale if _visual_root != null else Vector3.ZERO,
		"has_face_mask": _visual_root != null and _visual_root.get_node_or_null("BunnyRig/HeadJoint/" + FACE_MASK_NODE) != null,
		"skin_albedo": _skin_material.albedo_color if _skin_material != null else Color.BLACK,
		"skin_emission": _skin_material.emission_energy_multiplier if _skin_material != null and _skin_material.emission_enabled else 0.0,
		"skin_variant": NpcCatalog.get_skin_variant(npc_id),
		"skin_material_name": _skin_material.resource_name if _skin_material != null else "",
		"prompt_visible": _prompt_label != null and _prompt_label.visible,
		"has_name_label": _find_label("NameLabel") != null,
		"has_model": _visual_root != null,
		# 剧情节拍（一次性迎宾）。验收靠这些键判断"站住了 / 说过了 / 恢复巡逻了"。
		"story_beat_id": get_story_beat_id(),
		"story_beat_pending": not _pending_beat.is_empty(),
		"story_beat_delivered": _story_beat_delivered,
		"story_standby": _story_standby,
		"standby_world": _standby_world,
		"hail_radius": HAIL_RADIUS,
		# 脚本化演出（基地战败救援）。验收靠这两条判断"钉住了没有、正在说第几句"。
		"scripted_appearance": _scripted_active,
		"scripted_point": _scripted_point,
		"scripted_look": _scripted_look,
	}


## 快照里"头顶有没有名字牌"的判定：直接找同名 Label3D。
func _find_label(node_name: String) -> Node:
	for child in get_children():
		if child is Label3D and child.name == node_name:
			return child
	return null
