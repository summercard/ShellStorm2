class_name TreasureChest3D
extends Area3D
## 宝箱（《挺进地牢》风格）。玩家靠近按 E 开启。
##
## **本类只做表现与交互协议，绝不自己发奖励。**
## 开箱后发 `open_requested` 信号，由 `Dungeon3D._on_chest_open_requested()` 统一处理
## 宝箱只提供开箱表现与配置；奖励由 `ChestRewardService` 解析，命运卡掉落物由
## 后续统一拾取交互处理。箱子本身不直接发放奖励，也不直接弹出购买界面：
##   · 奖励解析与命运卡事务保持在各自的单一所有者内；
##   · 探针可以在不建整个地牢的前提下验证开箱配置与结果。
##
## 与 `RoomFurniture3D`（搜索容器）的区别：
##   · 家具是「搜索」，可以搜索多次无关紧要；宝箱是「开启」，**只能开一次**；
##   · 家具掉落走 `scavenge_*` 池，宝箱走品质池且必定多件；
##   · 宝箱开箱会生成由统一掉落链处理的物品与命运卡掉落物，家具不会。
## 因此不复用家具类，避免给它塞一堆 `if is_chest` 分支。
##
## **宝箱不再需要房间钥匙**（业主 2026-11-05：「开启方式是直接开启，不需要使用钥匙」）。
## 曾有 `requires_key` 字段与 `treasure_chests.requires_key` 配置，两者已一并删除 ——
## 不要为了兼容旧存档把字段加回来。若将来某个关卡真的要恢复锁箱，必须
## 「关卡数据 + 生成器 + 本类 + 交互文案」四处一起加，并留下会失败的断言；
## 只在本类塞一个字段会得到「提示要钥匙、开箱却不扣」的假锁。

## 开箱成功时发。`Dungeon3D` 接这个信号做表现与结算；命运卡掉落物由拾取交互认领。
signal open_requested(chest: TreasureChest3D)

## 箱子被**认领**（状态已开、已记进房间账）时发，**不是**动画播完时。
## 与 `open_animation_finished` 分开的理由见 `commit_opened()`：记账必须早于动画，
## 否则动画途中退出/切房会让这只箱子「没开过」，读档回来可以再开一次白嫖。
signal opened(chest: TreasureChest3D)

## 「砰」那一帧发。掉落物落地与弹窗的时机以它为锚，视觉上才和盖子弹开同步。
signal burst(chest: TreasureChest3D)

## 整套开箱动画（抖动 → 蓄力 → 砰 → 余韵）播完时发。
## 探针与真实渲染验收用它判断「视觉上真的开了」，不要用 `opened`。
signal open_animation_finished(chest: TreasureChest3D)

## 开箱动画阶段。**不要用一串布尔拼状态** —— 布尔拼状态没法回答「现在到哪一段了」，
## 探针也就只能验证"开没开"，验证不了"有没有前置过渡"。
enum OpenPhase { CLOSED, SHAKING, CHARGING, BURSTING, SETTLING, OPENED }

const CHEST_DIMENSIONS := Vector3(1.28, 1.02, 0.92)

# —— 开箱动画时间轴（业主 2026-11-05：要前置与后置，不许突然打开）——
#
#   0.00 ─ 0.42  抖动两下（±3.8°，四个半周期）
#   0.42 ─ 0.47  回正 0.05s（`SHAKE_RECENTER_SECONDS`）
#   0.47 ─ 0.59  蓄力：箱体下压、盖子反压 +3°，场子静下来
#   0.59         砰：盖子过冲到 -122° 再回 -104°、箱体上跳、内部光爆、音效
#               （= `OPEN_BURST_DELAY_SECONDS` 0.42+0.05+0.12；**别再写 0.54**，
#                 漏算回正那 0.05s 会让掉落比爆点早一帧出现）
#   0.59 ─ 0.97  余韵：落回、光回落、箱体压暗（`BURST_SECONDS + SETTLE_SECONDS` = 0.38）
#
# 抖动 0.42s 的取值理由：一个半周期 0.105s ≈ 人的「抖」觉阈值上限，
# 再快就成了高频嗡嗡（像在发信号），再慢就像在摇晃而不是被按住。
const SHAKE_SECONDS := 0.42
const SHAKE_CYCLES := 2
const SHAKE_DEGREES := 3.8
## 抖完回正的 0.05s。**必须单列成常量并计入 `OPEN_BURST_DELAY_SECONDS`**：
## 2026-11-05 首版就是把它写成魔法数字 0.05 留在序列里、常量只算 `SHAKE + CHARGE`，
## 于是 `Dungeon3D` 以为 0.54s 就该「砰」，箱子实际到 0.59s 才弹盖 ——
## 掉落比爆点早 0.05s，肉眼正好能看出"东西先出来、盖子后开"。
const SHAKE_RECENTER_SECONDS := 0.05
## 蓄力 0.12s 是**对比量**：没有这段「按住」，后面的弹开只是"快"，不是"砰"。
const CHARGE_SECONDS := 0.12
const CHARGE_LID_DEGREES := 3.0
## 「砰」本身的时长。0.14s 足够让盖子走过 120°，又短到读成一记弹开而不是一次开盖。
const BURST_SECONDS := 0.14
## 余韵：盖子回落、箱体落地、内部光从爆亮降回常亮。
const SETTLE_SECONDS := 0.24
const LID_OPEN_DEGREES := 104.0
const LID_BURST_OVERSHOOT_DEGREES := 18.0
## 箱体在爆点弹起的高度（米）。0.055 是「看得见的跳」，再高会穿到头顶的交互点。
const BURST_HOP_M := 0.055
## 内部发光面在爆点的亮度峰值（常亮时 3.2）。
const GLOW_BURST_ENERGY := 7.0
const GLOW_IDLE_ENERGY := 3.2
## 「砰」距按下 E 的秒数。`Dungeon3D` 用它把掉落与弹窗对齐到爆点（见 `get_open_burst_delay()`）。
## 三段相加，**任何一段改了这里都会自动跟着走** —— 不要再手工写魔法数字。
const OPEN_BURST_DELAY_SECONDS := SHAKE_SECONDS + SHAKE_RECENTER_SECONDS + CHARGE_SECONDS

## 拟态的抖动时长。0.4s 是刻意的**预警窗口**：够玩家后撤半步，
## 又短到不会让人在箱子前面站着等它变。
const MIMIC_SHAKE_SECONDS := 0.40
## 品质 → 描边色。与 `Dungeon3D.FATE_RARITIES` 同序（common/uncommon/rare/epic/legendary），
## 但只用到前四档：宝箱品质在原作里是「棕/蓝/绿/红/黑」，不是五档品质。
const QUALITY_COLORS := {
	"common": Color(0.96, 0.28, 0.12),
	"uncommon": Color(0.98, 0.34, 0.10),
	"rare": Color(0.82, 0.20, 0.86),
	"epic": Color(1.00, 0.48, 0.08),
}
const NORMAL_VISUAL_SCENE: PackedScene = preload(
	"res://assets/art/items_weapons/props/reward_chests/runtime/prp_reward_chest_normal_root_top3d.tscn"
)
const ADVANCED_VISUAL_SCENE: PackedScene = preload(
	"res://assets/art/items_weapons/props/reward_chests/runtime/prp_reward_chest_advanced_root_top3d.tscn"
)

var chest_id := ""
var quality := "common"
## 奖励档位由生成器从 `treasure_chests` 配置逐箱抄下；品质只用于视觉和品质加成。
var chest_tier := "normal"
var reward_pool_id := "loot_floor_1_2"
var drop_count := 1
## 旧 Dungeon3D 读取该属性仅作为兼容探针；新奖励链不再使用它，也不会从配置读取。
var fate_card_per_open: int:
	get:
		return 0
## 这只箱子是不是**拟态**（开箱变怪）。由生成器掷骰后写进 `chest_placements`。
## **箱子自己不知道也管不着结算** —— 它只负责「开箱时表现成被咬了一口再消失」，
## 刷什么怪、掉什么全在 `Dungeon3D`。
var mimic := false
## 拟态变什么怪。同 `chest_placements.mimic_monster_kind`，缺省 `egt_mimic`。
var mimic_monster_kind := "egt_mimic"

var _opened := false
var _open_phase: int = OpenPhase.CLOSED
var _opened_visual_applied := false
var _player_in_range := false
var _visual_root: Node3D
var _lid_pivot: Node3D
var _prompt: Label3D
var _body_material: StandardMaterial3D
var _trim_material: StandardMaterial3D
var _glow: MeshInstance3D
var _glow_material: StandardMaterial3D
var _collision: CollisionShape3D
## `_visual_root` 的静止高度。爆点的上跳/落回都相对它算，
## 不写死 0 —— 将来给箱子加底座偏移时动画不会把它拽回地面。
var _visual_base_y := 0.0
## 蓄力段那条 tween。`_fire_burst()` 必须先把它 kill 掉再弹盖，
## 否则两条 tween 抢同一组属性（见 `_begin_charge()` 的注释）。
var _charge_tween: Tween


func configure(config: Dictionary) -> void:
	chest_id = str(config.get("id", chest_id))
	quality = str(config.get("quality", quality))
	var configured_tier := str(config.get("chest_tier", chest_tier)).to_lower()
	chest_tier = configured_tier if configured_tier in ["normal", "advanced"] else ("advanced" if quality in ["rare", "epic"] else "normal")
	reward_pool_id = str(config.get("reward_pool_id", reward_pool_id))
	drop_count = maxi(1, int(config.get("drop_count", drop_count)))
	mimic = bool(config.get("mimic", mimic))
	mimic_monster_kind = str(config.get("mimic_monster_kind", mimic_monster_kind))


## 返回给奖励调度层的最小宝箱配置；不暴露节点状态，也不直接解析奖励。
func get_reward_config() -> Dictionary:
	return {
		"id": chest_id,
		"chest_tier": chest_tier,
		"quality": quality,
		"reward_pool_id": reward_pool_id,
		"drop_count": drop_count,
		"mimic": mimic,
		"mimic_monster_kind": mimic_monster_kind,
	}


func _ready() -> void:
	add_to_group("treasure_chest_3d")
	# 交互系统靠这个组发现可交互物（`PlayerInteractionController3D._refresh_focused_candidate`）。
	add_to_group(PlayerInteractionController3D.PROVIDER_GROUP)
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visual()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player_3d"):
		_player_in_range = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player_3d"):
		_player_in_range = false


# ---------------------------------------------------------------------------
# 交互协议（`PlayerInteractionController3D` 的约定）
# ---------------------------------------------------------------------------

func get_interaction_candidate(_player: Player3D) -> Dictionary:
	if _opened or not _player_in_range:
		return {}
	return {
		"available": true,
		"interaction_id": "treasure_chest:%s:%d" % [chest_id, get_instance_id()],
		"position": global_position,
		# 60 > 家具的 40：宝箱与家具挨着时优先开箱（玩家一定是冲着箱子来的）。
		"priority": 60,
		"prompt": _prompt_text(),
	}


## 提示牌是纯文案载体（同 `RoomFurniture3D`）：可见反馈交给 InteractionDot3D。
func set_interaction_focus(_candidate: Dictionary, _focused: bool) -> void:
	pass


func perform_interaction(_player: Player3D, _candidate: Dictionary) -> bool:
	if _opened or not _player_in_range:
		return false
	# ⚠ **这里不置 `_opened`**。开箱结算由 `Dungeon3D` 负责，
	# 由它回调 `commit_opened()` 收口状态。先置位再结算，一旦结算抛错就会出现
	# 「箱子已经开了、地上什么也没有」的假成功。
	open_requested.emit(self)
	return true


func get_interaction_dot_anchor() -> Vector3:
	return global_position + Vector3.UP * (CHEST_DIMENSIONS.y + 0.62)


func is_interaction_dot_visible() -> bool:
	return not _opened


func get_interaction_progress() -> Dictionary:
	# 开箱是瞬发（不像家具要读条），不画进度环。
	return {"active": false, "progress": 0.0}


func _prompt_text() -> String:
	if _opened:
		return "已开启"
	return "[E] 开启宝箱"


# ---------------------------------------------------------------------------
# 状态收口（由 Dungeon3D 调用）
# ---------------------------------------------------------------------------

## 认领这只箱子并开播动画。**幂等** —— 重复调用不会重播（`_opened` 早退）。
##
## 拆成「状态收口」与「视觉序列」两件事，顺序是刻意的：
##   ① 先置 `_opened` 与动画阶段 —— 在**同一个同步块**里落到 SHAKING，再发 `opened`。
##      任何监听方（房间记账、探针）读到的都是「已认领且正在播」这一致状态，
##      不会出现「收到了已开信号、但阶段还是闭合」的空窗；
##   ② 再播 `_play_open_sequence()` —— 抖动 → 蓄力 → 砰 → 余韵。
##
## ⚠ **不要改成「播完动画再记账」**：动画还有 0.9s，玩家在途中退出/切房/读档就会
## 让这只箱子回到未开状态，回来能再开一次白嫖。
func commit_opened() -> void:
	if _opened:
		return
	_opened = true
	_player_in_range = false
	# 状态先落盘（房间在这一刻把「已开」记进账），视觉随后开播。
	# 阶段由 `_play_open_sequence()` 推进；它内部对「无视觉根」的裸箱子有降级分支。
	_play_open_sequence()
	opened.emit(self)


## 「砰」距按下 E 的秒数。`Dungeon3D` 用它把掉落物落地对齐到盖子弹开那一帧。
## 硬编码在调用方是最容易漂的一种耦合 —— 改了抖动时长，掉落就会先于箱子出现。
##
## 减少动效时返回 0：那时箱子在 `commit_opened()` 当帧就落到终态，
## 再让掉落等 0.59s 会变成「箱子早开了、东西半天不出来」。
func get_open_burst_delay() -> float:
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		return 0.0
	return OPEN_BURST_DELAY_SECONDS


func get_open_phase() -> int:
	return _open_phase


func is_open_animation_done() -> bool:
	return _open_phase == OpenPhase.OPENED


# ---------------------------------------------------------------------------
# 开箱动画：抖动 → 蓄力 → 砰 → 余韵
# ---------------------------------------------------------------------------

func _play_open_sequence() -> void:
	if _open_phase != OpenPhase.CLOSED or _visual_root == null:
		# 视觉根不存在（探针构造的裸箱子）：直接落到终态，别留一个永远抖不完的状态。
		# `finished` 延到下一帧发：本函数由 `commit_opened()` 在 `opened` 之前调用，
		# 同步发会让监听方先收到「动画完了」、再收到「箱子开了」——顺序反了。
		_apply_opened_visual_state()
		_open_phase = OpenPhase.OPENED
		call_deferred("_emit_open_animation_finished")
		return
	# 减少动效：抖两下 + 箱体上跳属于前庭刺激，与 `_animate_fate_overlay_exit` 同一口径跳过。
	# **只跳"抖"，不跳"打开"** —— 直接不给反馈等于玩家按了 E 什么都没发生。
	# 这里不调 `_fire_burst()`：它会起一条 0.14s 的盖子 tween，
	# 而下面立刻要落终态，两条会抢 `rotation:x`（表现为盖子抖一下再定住）。
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		_open_phase = OpenPhase.BURSTING
		_apply_opened_visual_state()
		if AudioManager != null:
			AudioManager.play_sfx("container_open", -1.0)
		burst.emit(self)
		_open_phase = OpenPhase.OPENED
		call_deferred("_emit_open_animation_finished")
		return
	_open_phase = OpenPhase.SHAKING
	# 玩家已经按下 E，提示牌的任务结束了。淡出而不是直接 `visible = false`：
	# 一句字「啪」地消失和它「啪」地出现一样刺眼。
	_fade_prompt_out()

	var half_period := SHAKE_SECONDS / float(SHAKE_CYCLES * 2)
	var seq := create_tween()
	seq.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for _cycle in range(SHAKE_CYCLES):
		seq.tween_property(_visual_root, "rotation:z", deg_to_rad(SHAKE_DEGREES), half_period)
		seq.tween_property(_visual_root, "rotation:z", deg_to_rad(-SHAKE_DEGREES), half_period)
	# 回正用固定 0.05s：抖完停在斜的那一下最难看，也最容易和蓄力段抢读。
	seq.tween_property(_visual_root, "rotation:z", 0.0, SHAKE_RECENTER_SECONDS)

	seq.tween_callback(_begin_charge)
	seq.tween_interval(CHARGE_SECONDS)
	seq.tween_callback(_fire_burst)
	seq.tween_interval(BURST_SECONDS + SETTLE_SECONDS)
	seq.tween_callback(_finish_open_sequence)


## 蓄力：箱体被「按住」下沉、盖子反压。这一段是纯对比量，
## 没有它，后面的弹开只是"快"，不是"砰"。
##
## 曲线用 `EASE_OUT` 而不是 `EASE_IN`：0.12s 里若前段几乎不动，
## 玩家只看到"突然开了"——实测 EASE_IN 下 40% 进度时箱体才沉 0.6%，
## 那一段等于没做（2026-11-05 首轮实拍发现）。
func _begin_charge() -> void:
	if _open_phase != OpenPhase.SHAKING:
		return
	_open_phase = OpenPhase.CHARGING
	if _visual_root == null:
		return
	# 保存引用：`_fire_burst()` 必须先把这条 tween 杀掉再弹盖。
	# 否则两条 tween 抢同一组属性（`scale` / `rotation:x`），表现为"砰"那一下盖子只挪了 2°
	# —— 谁后 process 谁赢，不是确定行为。
	if _charge_tween != null and _charge_tween.is_valid():
		_charge_tween.kill()
	_charge_tween = create_tween()
	_charge_tween.set_parallel(true)
	_charge_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_charge_tween.tween_property(
		_visual_root, "scale", Vector3(1.035, 0.94, 1.035), CHARGE_SECONDS
	)
	if _lid_pivot != null:
		_charge_tween.tween_property(
			_lid_pivot, "rotation:x", deg_to_rad(CHARGE_LID_DEGREES), CHARGE_SECONDS
		)


## 「砰」：盖子过冲弹开、箱体上跳、内部光爆、音效。**掉落物在这一帧才开始落地**
## （`Dungeon3D` 用 `get_open_burst_delay()` 等这一刻），否则会看到东西从关着的箱子里冒出来。
func _fire_burst() -> void:
	if _open_phase != OpenPhase.CHARGING:
		return
	_open_phase = OpenPhase.BURSTING
	# 先掐掉蓄力那条 tween：它还在把盖子和 scale 拉回"压住"的终点，
	# 与下面几条抢同一组属性（2026-11-05 实拍实测：不掐的话砰那一帧盖子只挪了 2.5°）。
	if _charge_tween != null and _charge_tween.is_valid():
		_charge_tween.kill()
	_charge_tween = null
	if _glow != null:
		_glow.visible = true
	if _glow_material != null:
		# 光爆是"砰"的视觉重音：单帧冲到 7.0，再在余韵里落回常亮 3.2。
		var flash := create_tween()
		flash.tween_property(_glow_material, "emission_energy_multiplier", GLOW_BURST_ENERGY, 0.05)
		flash.tween_property(
			_glow_material, "emission_energy_multiplier", GLOW_IDLE_ENERGY, SETTLE_SECONDS
		)
	if _lid_pivot != null:
		# TRANS_BACK 才有那口「过头再拉回」的劲；EASE_OUT 会让它看起来像被液压杆顶开。
		var lid := create_tween()
		lid.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		lid.tween_property(
			_lid_pivot, "rotation:x",
			deg_to_rad(-(LID_OPEN_DEGREES + LID_BURST_OVERSHOOT_DEGREES)), BURST_SECONDS
		)
		lid.tween_property(
			_lid_pivot, "rotation:x", deg_to_rad(-LID_OPEN_DEGREES), SETTLE_SECONDS * 0.7
		)
	if _visual_root != null:
		var hop := create_tween()
		hop.set_parallel(true)
		hop.tween_property(
			_visual_root, "position:y", _visual_base_y + BURST_HOP_M, BURST_SECONDS * 0.55
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		hop.tween_property(_visual_root, "scale", Vector3(1.02, 0.975, 1.02), BURST_SECONDS * 0.55)
		hop.chain().tween_property(
			_visual_root, "position:y", _visual_base_y, SETTLE_SECONDS * 0.7
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		hop.tween_property(_visual_root, "scale", Vector3.ONE, SETTLE_SECONDS * 0.7)
	if AudioManager != null:
		# 比原来 -2.0 响一档：这是本层最该被听见的一下。
		AudioManager.play_sfx("container_open", -1.0)
	burst.emit(self)


func _finish_open_sequence() -> void:
	if _open_phase != OpenPhase.BURSTING:
		return
	_open_phase = OpenPhase.OPENED
	_apply_opened_visual_state()
	open_animation_finished.emit(self)


func _emit_open_animation_finished() -> void:
	if is_instance_valid(self):
		open_animation_finished.emit(self)


## 已开的**视觉终态**。三条路径共用：动画余韵收尾、读档恢复、裸箱子降级。
## 把它单独提出来的原因：这三处任何一处写法不同，就会出现「读档回来的箱子和现开的箱子长得不一样」。
func _apply_opened_visual_state() -> void:
	# 幂等：`darkened()` 连做两次会把箱子压成黑块。三条调用路径里读档恢复可能被
	# 重建流程重放一次，靠这个闸挡住。
	if _opened_visual_applied:
		return
	_opened_visual_applied = true
	if _prompt != null:
		_prompt.visible = false
	if _body_material != null:
		_body_material.albedo_color = _body_material.albedo_color.darkened(0.22)
	if _trim_material != null:
		_trim_material.emission_energy_multiplier = 0.15
	if _glow != null:
		_glow.visible = true
	if _glow_material != null:
		_glow_material.emission_energy_multiplier = GLOW_IDLE_ENERGY
	if _visual_root != null:
		_visual_root.rotation.z = 0.0
		_visual_root.position.y = _visual_base_y
		_visual_root.scale = Vector3.ONE
	if _lid_pivot != null:
		_lid_pivot.rotation.x = deg_to_rad(-LID_OPEN_DEGREES)


func _fade_prompt_out() -> void:
	if _prompt == null:
		return
	# Label3D 只能靠 `transparency` 淡出（同 GroundLootPickup3D 的口径）：描边不吃 modulate 的 alpha。
	var fade := create_tween()
	fade.tween_property(_prompt, "transparency", 1.0, 0.12)
	fade.tween_callback(func() -> void:
		if _prompt != null:
			_prompt.visible = false
	)


## 存档恢复 / 探针构造已开状态的箱子。不做动画，直接落到终态。
func restore_opened_state(opened_state: bool) -> void:
	if not opened_state:
		return
	_opened = true
	_player_in_range = false
	_open_phase = OpenPhase.OPENED
	_apply_opened_visual_state()


func is_opened() -> bool:
	return _opened


# ---------------------------------------------------------------------------
# 拟态（开箱变怪）
# ---------------------------------------------------------------------------

## 打开一只**拟态**箱子：抖动 → 咬开 → 整体消失。
##
## 为什么不复用 `commit_opened()`：那条路径的语义是「箱子开了、里面有东西」——
## 盖子缓慢上翻、内部发光面亮起、提示牌写「已开启」。拟态正相反：**箱子吞掉了箱内的东西**，
## 玩家该看到的是「这箱子不是箱子」，而不是一盏温柔的奖励灯。
##
## 本函数**不发奖励、不刷怪**：怪由 `Dungeon3D` 生成，物资也在 `Dungeon3D` 那边挂到怪身上。
## 箱子只把「我没了」这件事演完，然后消失 —— 否则怪会跟箱子叠在同一个位置互相遮挡。
func commit_mimic_reveal() -> void:
	if _opened:
		return
	_opened = true
	# 拟态不走普通箱的「抖动→蓄力→砰」序列（它自己的抖动就是那条序列的对位），
	# 但阶段仍要落到终态，否则快照会报「已开但还停在抖动段」。
	_open_phase = OpenPhase.OPENED
	_player_in_range = false
	# 提示牌直接隐藏而不是改写成「已开启」：接下来玩家要看的是那只怪，
	# 一句状态文案留在半空只会挡住它。
	if _prompt != null:
		_prompt.visible = false
	if _visual_root != null:
		var shake := create_tween()
		shake.set_loops(4)
		shake.tween_property(_visual_root, "rotation:z", deg_to_rad(4.5), 0.05)
		shake.tween_property(_visual_root, "rotation:z", deg_to_rad(-4.5), 0.05)
		shake.chain().tween_property(_visual_root, "rotation:z", 0.0, 0.02)
	if _lid_pivot != null:
		var lid := create_tween()
		lid.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		lid.tween_interval(MIMIC_SHAKE_SECONDS)
		lid.tween_property(_lid_pivot, "rotation:x", deg_to_rad(-140.0), 0.16)
	if AudioManager != null:
		AudioManager.play_sfx("container_open", -2.0)
	# 先发 `opened`：房间在这一刻就把「已开」记进账，之后无论 detail 重建多少次、
	# 玩家读档重进多少次，这只箱子都不会再是可开的箱子。
	opened.emit(self)
	# 消失走 tween 回调，不用 `await` —— `Dungeon3D` 紧接着就要在同一帧刷怪，
	# 把 `commit_*` 变成协程会让「先刷怪再消失」的顺序断在第一帧。
	var vanish := create_tween()
	vanish.tween_interval(MIMIC_SHAKE_SECONDS + 0.34)
	vanish.tween_callback(_vanish_for_mimic)


## 拟态的终态：视觉与碰撞一起收掉。
## 只藏视觉不关碰撞，会在房间里留一块看不见的挡路石头（玩家会以为是 bug）。
func _vanish_for_mimic() -> void:
	if _visual_root != null:
		_visual_root.visible = false
	if _collision != null:
		_collision.disabled = true
	monitoring = false
	if _prompt != null:
		_prompt.visible = false


## detail 重建 / 读档回灌已"咬过"的拟态箱：直接落到终态，不重播抖动。
func restore_mimic_state() -> void:
	_opened = true
	_open_phase = OpenPhase.OPENED
	_player_in_range = false
	_vanish_for_mimic()


## 品质 → 掉落品质加成档数。`Dungeon3D._apply_fate_item_quality()` 吃这个值。
## 宝箱品质在原作里是「棕/蓝/绿/红/黑」五档，我们映射到 4 档品质加成（0~3）。
func quality_tier() -> int:
	match quality:
		"uncommon":
			return 1
		"rare":
			return 2
		"epic":
			return 3
		_:
			return 0


func get_chest_snapshot() -> Dictionary:
	return {
		"chest_id": chest_id,
		"quality": quality,
		"opened": _opened,
		# 动画阶段：0 闭合 / 1 抖动 / 2 蓄力 / 3 砰 / 4 余韵 / 5 已开。
		# 快照必须带上它 —— 只报 `opened` 的话，「按下 E 后有没有前置过渡」在探针里不可见。
		"open_phase": _open_phase,
		"open_phase_name": OpenPhase.keys()[_open_phase] if _open_phase >= 0 and _open_phase < OpenPhase.size() else "",
		"open_animation_done": is_open_animation_done(),
		"burst_delay_seconds": OPEN_BURST_DELAY_SECONDS,
		"mimic": mimic,
		"visual_visible": _visual_root.visible if _visual_root != null else false,
		"collision_disabled": _collision.disabled if _collision != null else false,
		"prompt": _prompt.text if _prompt != null else "",
		"dot_visible": is_interaction_dot_visible(),
		"lid_open_deg": rad_to_deg(_lid_pivot.rotation.x) if _lid_pivot != null else 0.0,
	}


# ---------------------------------------------------------------------------
# 视觉（程序化，不依赖美术资产）
# ---------------------------------------------------------------------------

func _build_visual() -> void:
	var trim_color: Color = QUALITY_COLORS.get(quality, QUALITY_COLORS["common"])
	var visual_scene := ADVANCED_VISUAL_SCENE if quality in ["rare", "epic"] else NORMAL_VISUAL_SCENE
	var visual := visual_scene.instantiate() as RewardChestVisual3D
	if visual == null:
		push_error("奖励宝箱视觉 Prefab 实例化失败")
		return
	add_child(visual)
	visual.refresh_handles()
	_visual_root = visual.visual_root
	_lid_pivot = visual.lid_pivot
	_glow = visual.glow
	_glow_material = visual.glow_material
	_body_material = visual.body_material
	_trim_material = visual.trim_material
	if _visual_root == null:
		_visual_root = visual.get_node_or_null("ImportedModel") as Node3D
	_visual_base_y = _visual_root.position.y if _visual_root != null else 0.0
	visual.set_quality_accent(trim_color)
	if _glow != null:
		_glow.visible = false

	var dimensions := Vector3(1.45, 1.18, 1.40)
	if quality in ["rare", "epic"]:
		dimensions *= 1.2
	var shape := BoxShape3D.new()
	shape.size = dimensions + Vector3(0.30, 0.30, 0.30)
	_collision = CollisionShape3D.new()
	_collision.position.y = dimensions.y * 0.5
	_collision.shape = shape
	add_child(_collision)

	_prompt = Label3D.new()
	_prompt.name = "ChestPrompt"
	_prompt.position = Vector3(0, dimensions.y + 0.62, 0)
	_prompt.text = _prompt_text()
	_prompt.font_size = 32
	_prompt.pixel_size = 0.010
	_prompt.outline_size = 0
	_prompt.modulate = trim_color.lightened(0.3)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	add_child(_prompt)
