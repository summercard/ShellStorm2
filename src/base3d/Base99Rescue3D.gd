class_name Base99Rescue3D
extends Node3D
## 战败归航救援：**远征阵亡回 99F 的那一小段演出 + 一只浅灰救援箱**。
##
## 业主口径（2026-11-08）：
##   ① 回基地时是趴着的，绿苔站在边上说两句（原话见 `NpcCatalog.RESCUE_LINES`）；
##   ② 说完玩家跳起来，可以操作；
##   ③ 边上放着一只浅灰色宝箱（用现在的宝箱模型改色）；
##   ④ 开箱掉落 1–2 件上一局携带物（背包 + 装备，**不含保险格**）＋ 1–2 件补给；
##   ⑤ 开箱 10 秒后箱子消失，消失用收租人的离场特效。
##
## 分工（谁拥有什么）：
##   | 项 | 所有者 |
##   |---|---|
##   | 抽哪几件、随机多少件、落档 | `Dungeon3D._plan_rescue_items()` + `BaseManager.rescue_cache` |
##   | 台词 | `NpcCatalog.RESCUE_LINES` |
##   | 站位/开口/停巡 | `NpcCharacter3D.begin_scripted_appearance()`（演出方只给点） |
##   | 趴下/起身的动画 | `PlayerAvatar3D.set_narrative_pose()`（本文件只推相位） |
##   | 开箱链（认领 → 砰 → 落地 → 房间账） | `Dungeon3D._on_chest_open_requested()` |
##   | 消失特效 | `VfxPool3D.FX01_TELEPORT_OUT`（= 收租人撤退同一个 `VFX-TELEPORT-OUT-3D`） |
##
## 本文件**不写台词、不抽奖励、不碰存档字段** —— 它只负责把它们按时间排好。
## 这样验收可以在不开箱的情况下单独验证"趴着/说了两句/起身"，
## 也可以在不开演出的情况下单独验证"箱子内容 = 暂存清单"。

signal cutscene_finished()

## 演出阶段。字符串给快照用，别在断言里比 int。
enum Phase { IDLE, CUTSCENE, CHEST_WAITING, CHEST_OPENED, VANISHED, SKIPPED }

const PHASE_NAMES := ["idle", "cutscene", "chest_waiting", "chest_opened", "vanished", "skipped"]

## 对白推进的公开查询入口所在的组。
##
## 这段台词**不经过 NarrativeDirector 的时间轴**（它由本协程按固定停留时间铺开），
## 所以导演找不到载体；玩家按空格/点左键时由导演按这个组发现本节点，再调本类的
## `can_advance_rescue_line()` / `advance_rescue_line()`。用组而不是节点路径，
## 与 `base_npc_3d` 同一口径：塔楼场景换层级也不用改导演。
const ADVANCE_GROUP := "rescue_cutscene_3d"

## 宝箱稳定 ID。同一局里重复装配时按它判重（`spawn_transient_chest` 不做幂等，
## 判重在这里做：演出是装配期一次性动作，不该由房间账来决定它算不算数）。
const CHEST_ID := "rescue_chest_99f"

## —— 站位（相对归航点 `FACILITY_LOGOUT_SPAWN` 的世界偏移）——
#
# 为什么写成"相对归航点"而不是再加两个作者锚点：
# 这个点位是**归航点旁边 1.5m**，语义上属于"玩家在哪醒来，绿苔就站哪边"。
# 加锚点会在美术场景里多出两个几乎重合的点，还要改场景账本的 SHA；
# 而归航点本身已经是代码持有的常量（`TowerDescent3D.FACILITY_LOGOUT_SPAWN`），
# 它一动，这两个偏移自动跟着走。
#
# 净空依据：归航点 → 迎宾锚点（西侧 3.2m 走道）这一段是空的（见 20 号文档 §10），
# 两个点都落在这条走道上，且离最近设施（西侧 MEDICAL/TOOLS 设备墙）> 1m。
const NPC_RESCUE_OFFSET := Vector3(-1.55, 0.0, -0.55)
const CHEST_RESCUE_OFFSET := Vector3(-2.45, 0.0, 0.15)
const CHEST_ROTATION_DEG := 18.0

## 趴着的姿势 = `dead` 剪辑终点帧（与开场剧本同一口径，见 `nar_tower_opening_01_wake`）。
const PRONE_CLIP := "dead"
## 起身时长。1.1s 比开场那 1.5s 短一档：这是"跳起来"，不是"慢慢爬起来"。
const RISE_SECONDS := 1.1
## 每句台词的停留时间（**打完字之后**再留这么久）。3.2s 够读完 26 字，又不会让玩家干等。
const LINE_HOLD_SECONDS := 3.2
## 打字机最多允许额外占用的秒数（等气泡收起的兜底上限）。
## 30 字/秒打一句 26 字约 0.87s，留 4s 余量足够；超时就当气泡异常，继续往下走。
const MAX_TYPEWRITER_EXTRA_SECONDS := 4.0
## 演出期间的气泡换行宽度。默认 560px（≈11 汉字/行）会把第二句 26 字排成三行、
## 顶出画面上缘；放宽到 700px 后两句都还是两行，字号与挂高都不动。
const SCRIPTED_WRAP_PX := 700
## 开箱后多久箱子消失（业主口径 10 秒）。
const VANISH_DELAY_SECONDS := 10.0
## 消失特效的尺寸与颜色。1.6 略大于箱子本体，让环把整只箱子包住。
const VANISH_FX_SIZE := 1.6
const VANISH_FX_COLOR := Color(0.78, 0.86, 0.95)
## 浅灰箱。业主口径「拿现在的宝箱，做成浅灰色的」。
## 只给身板色，箱边由 `TreasureChest3D` 按 body 压暗 28% 自动派生。
const CHEST_TINT := Color(0.80, 0.81, 0.83)

var _tower: Node3D
var _room: DungeonRoom3D
var _player: Player3D
var _npc: NpcCharacter3D
var _chest: TreasureChest3D

var _phase: int = Phase.IDLE
var _begun := false
var _holds_input := false
var _cache: Array = []
var _grants: Array = []
var _vanish_pending := false
## 本次演出对应的连续战败次数（结算时已 +1，所以第 1 次死亡读到 1）。
var _streak := 0
## 本次要说的整段台词（固定两句 + 连败/随机变体），演出开始那一刻定格。
var _script_lines: Array[String] = []
## 演出期间玩家的钉点（世界坐标）。见 `_enforce_hold()`。
var _pinned_world := Vector3.INF


func _ready() -> void:
	add_to_group(ADVANCE_GROUP)


## 玩家现在能不能推进当前这句（空格／鼠标左键）。只在演出阶段、且气泡里真有一句时为真。
##
## 刻意不看「玩家在不在交互范围」：演出时人趴在地上、输入被锁，本来就走不到旁边去。
func can_advance_rescue_line() -> bool:
	if _phase != Phase.CUTSCENE or get_tree().paused:
		return false
	if _npc == null or not is_instance_valid(_npc):
		return false
	if not _npc.has_method("is_scripted_line_progressable"):
		return false
	return bool(_npc.call("is_scripted_line_progressable"))


## 推一下：打字中 → 立刻全显；已全显 → 只压缩这一句的停留。
##
## 台词指针、句子顺序、起身时机全都不动 —— 下一句由 `_wait_until_line_done()` 的轮询
## 发现气泡收起后自然接上。这样「快速过」既不跳句，也不会让人物提前站起来。
func advance_rescue_line() -> bool:
	if not can_advance_rescue_line():
		return false
	return bool(_npc.call("advance_scripted_line"))


## 装配。必须在 `begin()` 之前调用；四个引用缺任何一个都按"不演"处理。
func setup(	tower_node: Node3D, room: DungeonRoom3D, player_node: Player3D, npc_node: NpcCharacter3D
) -> void:
	_tower = tower_node
	_room = room
	_player = player_node
	_npc = npc_node


func begin() -> void:
	if _begun:
		return
	_begun = true
	if _room == null or not is_instance_valid(_room) or _player == null:
		# 装配不到位不是玩法错误：没有基地房（远征/工具场景）时本来就该什么都不做。
		_phase = Phase.SKIPPED
		return
	# 读**公开服务**取待开箱清单，不直接摸 BaseManager 内部数据。
	_cache = BaseManager.get_rescue_cache()
	if _cache.is_empty():
		_phase = Phase.IDLE
		return
	_grants = Dungeon3D.build_rescue_chest_grants(_cache)
	if _grants.is_empty():
		push_warning("[Base99Rescue3D] 救援暂存里有 %d 条，转成奖励后为空，本次不演。" % _cache.size())
		_phase = Phase.SKIPPED
		return
	_spawn_chest()
	if not _should_play_cutscene():
		# 没有"死亡归航"这个入口原因（例如玩家开箱前退过游戏、这次是普通启动）：
		# 只把箱子摆出来，不把人按回地上 —— 东西还他，戏不必重演。
		_phase = Phase.CHEST_WAITING
		return
	_phase = Phase.CUTSCENE
	await _play_cutscene()


## 排本次要说的整段台词。**演出与验收共用这一份实现** —— 验收若直连
## `NpcCatalog.get_rescue_script()` 就测不到"演出方到底是不是随机抽的"：
## 把这里改成永远取第 0 段，验收必须跟着红。
##
## `pick_index >= 0` 是验收用的确定性入口；缺省 -1 = 真随机。
func plan_script_lines(streak: int, pick_index := -1) -> Array[String]:
	return NpcCatalog.get_rescue_script(NpcCatalog.NPC_BASE99_GREEN, streak, pick_index)


func _should_play_cutscene() -> bool:
	if _tower == null or not _tower.has_method("get_entry_context_snapshot"):
		return false
	var context: Dictionary = _tower.call("get_entry_context_snapshot") as Dictionary
	return str(context.get("reason", "")) == GameEntryFlow.REASON_DEATH_RETURN_99F


func _play_cutscene() -> void:
	_place_player_prone()
	_place_npc()
	# 台词**整段随机**：命中连败档就是专属段，否则从候选池随机挑一段
	# （见 `NpcCatalog.RESCUE_SCRIPTS`）。没有必说的开场白。
	# 台词为空就跳过说话、直接起身交还操作（内容缺失不该把人钉死）。
	_streak = BaseManager.get_rescue_defeat_streak()
	# 一段**整段随机**：命中连败档就是专属段，否则从候选池随机挑一段。
	# 没有"必说的开场白"——业主 2026-11-08 明确那句也是随机项之一。
	var lines := plan_script_lines(_streak)
	_script_lines.assign(lines)
	if _npc != null:
		_npc.set_bubble_wrap_width(SCRIPTED_WRAP_PX)
	if lines.is_empty():
		push_warning("[Base99Rescue3D] 救援台词为空，跳过对话直接起身。")
	else:
		for line in lines:
			if not _is_alive():
				# 玩家被释放但本节点还活着（换场景的中间帧）⇒ 必须自己交还两个锁：
				# 这时不会走 `_exit_tree()`，锁一旦留着，下一个场景的玩家会动不了。
				_release_player_input()
				return
			if _npc != null:
				_npc.say_scripted_line(line, LINE_HOLD_SECONDS)
			await _wait_until_line_done()
	if _npc != null:
		_npc.set_bubble_wrap_width(0)
	if not _is_alive():
		_release_player_input()
		return
	await _rise_player()
	if _npc != null:
		_npc.end_scripted_appearance()
	_phase = Phase.CHEST_WAITING
	cutscene_finished.emit()


## 趴下：钉回归航点、锁玩法输入与鼠标朝向、把表现钉在 `dead` 终点帧。
func _place_player_prone() -> void:
	if not _is_alive():
		return
	var spawn := _spawn_world_point()
	_player.global_position = spawn
	_player.velocity = Vector3.ZERO
	# 钉点留一份：锁只拦输入，残留速度与物理求解仍会把人推走几厘米；
	# `_enforce_hold()` 每帧按这一份把水平位置拉回来。
	_pinned_world = spawn
	if _tower != null and _tower.has_method("set_scripted_input_hold"):
		_tower.call("set_scripted_input_hold", true)
		_holds_input = true
	var avatar: Variant = _player.get("avatar")
	if avatar is Object and (avatar as Object).has_method("set_narrative_pose"):
		(avatar as Object).call("set_narrative_pose", PRONE_CLIP, 1.0, true)


## 演出期间**逐帧**兜底（业主 2026-11-08：「这个时候需要玩家无法操作，鼠标旋转也不行」）。
##
## 三件事每帧都做，缺一条就有一条真实可走通的漏洞：
##   ① 锁掉了就重新锁 —— `Player3D.set_input_locked()` 在 `current_hp <= 0` 时会静默
##      不生效，而血量回填发生在锁之后；只靠开演那一发，运气不好就是"人能动"。
##   ② 鼠标朝向归演出方 —— `set_scripted_input_hold(true)` 已经把 `aim_locked` 置上，
##      这里再确认一次（别处若把它清掉，鼠标晃一下就能把趴着的人转过来）。
##   ③ 水平位置钉死、竖直速度清零 —— 锁不拦重力与残余冲量。
##
## 只在 `_holds_input` 为真时跑，起身后立刻停，不会影响正常操作。
func _process(_delta: float) -> void:
	if not _holds_input:
		return
	_enforce_hold()


func _enforce_hold() -> void:
	if not _is_alive():
		return
	if not bool(_player.get("input_locked")):
		if _tower != null and is_instance_valid(_tower) and _tower.has_method("set_scripted_input_hold"):
			_tower.call("set_scripted_input_hold", true, true)
	if not bool(_player.get("aim_locked")):
		if _player.has_method("set_aim_locked"):
			_player.call("set_aim_locked", true)
	var current := _player.global_position
	if not _pinned_world.is_finite():
		return
	if Vector2(current.x - _pinned_world.x, current.z - _pinned_world.z).length() > 0.0005:
		_player.global_position = Vector3(_pinned_world.x, current.y, _pinned_world.z)
	var velocity := _player.velocity
	if absf(velocity.x) > 0.0005 or absf(velocity.z) > 0.0005:
		_player.velocity = Vector3(0.0, velocity.y, 0.0)


func _place_npc() -> void:
	if _npc == null or not is_instance_valid(_npc):
		return
	var point := _spawn_world_point() + NPC_RESCUE_OFFSET
	# 朝向玩家（趴着的人），不是朝向胸口高度 —— 趴着时头在 0.2m 左右。
	_npc.begin_scripted_appearance(point, _player.global_position + Vector3.UP * 0.25)


func _rise_player() -> void:
	if not _is_alive():
		return
	var avatar: Variant = _player.get("avatar")
	if not (avatar is Object) or not (avatar as Object).has_method("set_narrative_pose"):
		_release_player_input()
		return
	# 相位 1.0 → 0.0 = 反放倒地剪辑 = 从趴着站起来。走 tween 而不是一次性写值，
	# 否则"起身"只是一帧瞬移，玩家看到的还是"趴着的人突然站着"。
	var apply_pose := func(value: float) -> void:
		if avatar is Object and is_instance_valid(avatar):
			(avatar as Object).call("set_narrative_pose", PRONE_CLIP, value, true)
	var riser := create_tween()
	riser.tween_method(apply_pose, 1.0, 0.0, RISE_SECONDS)
	await riser.finished
	if avatar is Object and is_instance_valid(avatar) and (avatar as Object).has_method("clear_narrative_pose"):
		(avatar as Object).call("clear_narrative_pose")
	_release_player_input()


func _release_player_input() -> void:
	if not _holds_input:
		return
	_holds_input = false
	if _tower != null and is_instance_valid(_tower) and _tower.has_method("set_scripted_input_hold"):
		_tower.call("set_scripted_input_hold", false)


# —— 宝箱 ——

func _spawn_chest() -> void:
	if _room == null or not is_instance_valid(_room):
		return
	var config := {
		"id": CHEST_ID,
		"chest_tier": "normal",
		"quality": "common",
		# 明确清单：开箱不再走池子解析（见 `Dungeon3D._resolve_chest_grants`）。
		"grants": _grants,
		"drop_count": maxi(1, _grants.size()),
		"body_tint": [CHEST_TINT.r, CHEST_TINT.g, CHEST_TINT.b],
	}
	var world_point := _spawn_world_point() + CHEST_RESCUE_OFFSET
	var local := _room.to_local(world_point)
	_chest = _room.spawn_transient_chest(config, Vector2(local.x, local.z), CHEST_ROTATION_DEG)
	if _chest == null:
		push_error("[Base99Rescue3D] 救援箱生成失败，暂存清单保留（下次归航再给）。")
		return
	_chest.opened.connect(_on_chest_opened)


## 开箱那一刻（`commit_opened()`）就算交付完成：清暂存、起 10 秒消失计时。
##
## 清暂存放在这里而不是"消失之后"：掉落已经记账并落地，玩家走开不捡是他自己的事；
## 拖到消失之后再清，中途退出会让暂存留着、下次再白送一箱。
func _on_chest_opened(_chest_node: TreasureChest3D) -> void:
	_phase = Phase.CHEST_OPENED
	if not BaseManager.clear_rescue_cache("rescue_chest_opened"):
		push_warning("[Base99Rescue3D] 救援暂存清空失败，重启后可能重复给一箱。")
	_start_vanish_countdown()


func _start_vanish_countdown() -> void:
	_vanish_pending = true
	await _wait(VANISH_DELAY_SECONDS)
	_vanish_pending = false
	if _phase != Phase.CHEST_OPENED:
		return
	_play_vanish()


## 消失：收租人撤退用的同一件特效 `VFX-TELEPORT-OUT-3D`。
##
## 顺序是硬顺序：先播特效、再同帧收掉视觉与碰撞 —— 反过来会看到"箱子先没了、
## 光才亮"，读起来像掉帧而不是被收走。
func _play_vanish() -> void:
	_phase = Phase.VANISHED
	if _chest == null or not is_instance_valid(_chest):
		return
	var origin := _chest.global_position + Vector3.UP * 0.55
	VfxPool.acquire(VfxPool3D.FX01_TELEPORT_OUT, origin, VANISH_FX_COLOR, VANISH_FX_SIZE)
	_chest.despawn()
	var chest_ref := _chest
	_chest = null
	await _wait(1.2)
	if chest_ref != null and is_instance_valid(chest_ref):
		chest_ref.queue_free()


# —— 查询（验收与调试）——

func get_phase() -> int:
	return _phase


func get_phase_name() -> String:
	return PHASE_NAMES[_phase] if _phase >= 0 and _phase < PHASE_NAMES.size() else ""


func get_rescue_chest() -> TreasureChest3D:
	return _chest


func get_rescue_grants() -> Array:
	return _grants.duplicate(true)


func is_holding_player_input() -> bool:
	return _holds_input


func is_vanish_pending() -> bool:
	return _vanish_pending


func get_snapshot() -> Dictionary:
	return {
		"phase": get_phase_name(),
		"holds_input": _holds_input,
		"vanish_pending": _vanish_pending,
		"cache_entries": _cache.size(),
		"grant_count": _grants.size(),
		"chest_present": _chest != null and is_instance_valid(_chest),
		"chest_id": CHEST_ID,
		"npc_point": _spawn_world_point() + NPC_RESCUE_OFFSET,
		"chest_point": _spawn_world_point() + CHEST_RESCUE_OFFSET,
		# 连续战败次数与本次要说的整段台词（固定两句 + 随机/连败变体）。
		# 验收靠 `script_lines` 逐字比对，不必去截气泡。
		"defeat_streak": _streak,
		"script_lines": _script_lines.duplicate(),
	}


## 归航点世界坐标。归塔楼持有（`TowerDescent3D.FACILITY_LOGOUT_SPAWN` 是它自己的常量），
## 这里只取同一份：`_tower.get_facility_spawn_point()` 不存在时退回节点自己的位置，
## 保证工具场景里也不会算出 NaN。
func _spawn_world_point() -> Vector3:
	if _tower != null and is_instance_valid(_tower) and _tower.has_method("get_facility_spawn_point"):
		return _tower.call("get_facility_spawn_point") as Vector3
	return global_position


## 等这一句真正说完（打字机打完 + 停留时长走完），而不是死等固定秒数。
##
## 为什么要等气泡而不是等常量：文字是**逐字冒出来**的（`SpeechBubble3D` 打字机），
## 26 字按 30 字/秒要 0.87s，固定的 `LINE_HOLD_SECONDS` 只盖住停留段 ——
## 死等的话句子会在打完之前被下一句顶掉。上限兜底防止气泡异常不消失时卡死演出。
func _wait_until_line_done() -> void:
	if _npc == null:
		await _wait(LINE_HOLD_SECONDS)
		return
	var deadline := LINE_HOLD_SECONDS + MAX_TYPEWRITER_EXTRA_SECONDS
	var elapsed := 0.0
	while elapsed < deadline:
		if not _npc.is_speaking():
			return
		await _wait(0.05)
		elapsed += 0.05


func _wait(seconds: float) -> void:
	await get_tree().create_timer(maxf(0.01, seconds)).timeout


func _is_alive() -> bool:
	return is_inside_tree() and _player != null and is_instance_valid(_player)


## 中途退出（切场景/玩家放弃）时把输入独占还回去 —— 这是唯一会把人永久钉住的路径：
## 演出协程被 `queue_free()` 打断，`_release_player_input()` 永远不会再被调用。
func _exit_tree() -> void:
	_release_player_input()
	if _npc != null and is_instance_valid(_npc):
		_npc.set_bubble_wrap_width(0)
