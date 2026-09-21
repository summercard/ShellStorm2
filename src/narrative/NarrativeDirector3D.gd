extends Node
## 剧情导演（autoload）。系统编号 6，契约见 docs/v0.1/08_技术施工_剧情触发.md。
##
## 它做三件事，且只做这三件：
##   1. **判断该不该演** —— 三种触发源（数据驱动的 event / point，代码驱动的 arm() 手动判定）；
##   2. **按时刻喊人干活** —— 时间轴按绝对秒数派发 cue，全部经 NarrativeAdapter3D 转发；
##   3. **收口** —— 声明式占用清单 + 四条时机（duration / flow.end / 被打断 / abort）
##      无条件强制归还。权限给得越大，收口越不能靠作者自觉。
##
## 它**不**实现任何表现（动画归角色系统、特效归 VfxPool、文字归 DialogueUI），
## 也**不**抓任何节点路径（唯一耦合点是适配器）。
##
## 为什么是 autoload：触发脚本要能在任意场景登记，`arm()` 的注册表必须跨场景存活；
## 与 DialogueUI 同为跨场景系统。⛔ 依 AGENTS.md 存档隔离约定，本节点在 _ready 不碰 user://。

signal narrative_started(narrative_id: String)
signal narrative_finished(narrative_id: String, reason: String)

## 位置触发的轮询间隔。见 08 文档 §4.2：不用 Area3D（性能门禁 total 余量仅 11 个节点），
## 改成距离轮询 —— 零新增常驻节点。代价是理论漏触发，由 radius >= 1.0 下限兜住。
const POINT_POLL_INTERVAL := 0.1
## 手动判定（arm 的 check）的轮询间隔。
const MANUAL_CHECK_INTERVAL := 0.2

## 归还优先级：数字越小越先归还。输入与相机不还 = 卡死玩家，必须最先行（08 文档 §6.2）。
const RELEASE_PRIORITY := {
	"player.input": 0,
	"camera": 1,
	"player.combat": 2,
	"player.invulnerable": 3,
	"music": 4,
}

var _adapter := NarrativeAdapter3D.new()
var _scripts: Dictionary = {}
var _armed: Dictionary = {}
var _active: Dictionary = {}
var _flags: Dictionary = {}
var _diagnostics: Array[String] = []
var _dispatch_log: Array[String] = []
var _dungeon: Node = null
var _poll_accumulator := 0.0
var _check_accumulator := 0.0
var _paused_dialogue_synced := false


func _ready() -> void:
	# PAUSABLE（Godot 默认）：树一暂停，_process 不再被调用，时间轴自动冻住 ——
	# 不需要额外代码。与 DialogueUI 的 ALWAYS 不同，后者要显式同步（见 _sync_dialogue_pause）。
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_adapter.bind(get_tree())
	get_tree().node_added.connect(_on_node_added)
	_arm_catalog_triggers()


# =========================================================================
# 登记表与触发源
# =========================================================================

## 登记一条触发。触发脚本在 _ready 里调用即可，本身不新增任何节点。
func arm(narrative_id: String, params: Dictionary = {}) -> bool:
	var script := _script_for(narrative_id)
	if script == null:
		return false
	var declared: Dictionary = script.trigger.duplicate(true)
	for key: String in params:
		declared[key] = params[key]
	declared["narrative_id"] = narrative_id
	declared["fired_count"] = int(_armed.get(narrative_id, {}).get("fired_count", 0))
	declared["last_fired_msec"] = int(_armed.get(narrative_id, {}).get("last_fired_msec", -10_000_000))
	_armed[narrative_id] = declared
	return true


func disarm(narrative_id: String) -> void:
	_armed.erase(narrative_id)


func is_armed(narrative_id: String) -> bool:
	return _armed.has(narrative_id)


## 把目录里所有**数据驱动**（event / point）的剧本登记进来。手动触发的不自动登记。
func _arm_catalog_triggers() -> void:
	for missing in NarrativeCatalog.missing_files():
		_diagnose("剧本文件缺失：%s" % missing)
	for narrative_id: String in NarrativeCatalog.all_ids():
		var script := _script_for(narrative_id)
		if script == null:
			continue
		var kind := str(script.trigger.get("kind", NarrativeScript3D.TRIGGER_KIND_MANUAL))
		if kind == NarrativeScript3D.TRIGGER_KIND_MANUAL:
			continue
		arm(narrative_id)


# =========================================================================
# 解析与缓存
# =========================================================================

func _script_for(narrative_id: String) -> NarrativeScript3D:
	if _scripts.has(narrative_id):
		return _scripts[narrative_id] as NarrativeScript3D
	var script := NarrativeScript3D.load_from_id(narrative_id)
	for error in script.errors:
		_diagnose("剧情『%s』校验失败：%s" % [narrative_id, error])
	if not script.is_valid():
		return null
	_scripts[narrative_id] = script
	return script


func script_of(narrative_id: String) -> NarrativeScript3D:
	return _scripts.get(narrative_id, null) as NarrativeScript3D


func arm_all_from_catalog() -> void:
	_arm_catalog_triggers()


func diagnostics() -> Array[String]:
	return _diagnostics.duplicate()


func dispatch_log() -> Array[String]:
	return _dispatch_log.duplicate()


func _diagnose(message: String) -> void:
	_diagnostics.append(message)
	push_error("[NarrativeDirector] %s" % message)


func _warn(message: String) -> void:
	_diagnostics.append(message)
	push_warning("[NarrativeDirector] %s" % message)


# =========================================================================
# 触发评估
# =========================================================================

func _on_node_added(node: Node) -> void:
	# 场景根进入树 **早于** 它的 _ready（孩子先就位、_ready 后发），
	# 所以这里接得上「新游戏开场」这一发 room_entered —— 那一发就发生在
	# TowerDescent3D._ready 里，等第一帧 _process 就已经错过了。
	if node.has_signal("room_entered") and node != _dungeon:
		_bind_dungeon(node)


func _bind_dungeon(node: Node) -> void:
	_dungeon = node
	if not node.room_entered.is_connected(_on_dungeon_room_entered):
		node.room_entered.connect(_on_dungeon_room_entered)
	if node.has_signal("room_cleared") and not node.room_cleared.is_connected(_on_dungeon_room_cleared):
		node.room_cleared.connect(_on_dungeon_room_cleared)
	if node.has_signal("run_completed") and not node.run_completed.is_connected(_on_dungeon_run_completed):
		node.run_completed.connect(_on_dungeon_run_completed)
	if node.has_signal("gameplay_started") and not node.gameplay_started.is_connected(_on_dungeon_gameplay_started):
		node.gameplay_started.connect(_on_dungeon_gameplay_started)


func _on_dungeon_room_entered(room: Variant) -> void:
	var room_id := str((room as Object).get("room_id")) if room is Object else ""
	_evaluate_event("room_entered", room_id)


func _on_dungeon_room_cleared(room: Variant) -> void:
	var room_id := str((room as Object).get("room_id")) if room is Object else ""
	_evaluate_event("room_cleared", room_id)


func _on_dungeon_run_completed(success: bool, _summary: Dictionary) -> void:
	# 终止路径必须在剧情演到一半时切场景之前先把现场还回去（08 文档 §8.8）。
	abort("run_completed:%s" % ("success" if success else "failure"))


## 玩法正式开始（开场页动画播完 / 没有开场页时 = 本帧末）。
## 开场类剧情必须挂这一发，不能挂 room_entered —— room_entered 在场景 `_ready` 里就发了，
## 那一刻开场页还在接管相机与输入，剧情会在菜单背后空跑、并与开场页互相顶：
## 相机被钉在近景、输入锁被开场页还原、玩家的鼠标还能把剧本摆好的朝向顶掉。
func _on_dungeon_gameplay_started(room_id: String) -> void:
	_evaluate_event("gameplay_started", room_id)


func _evaluate_event(event_name: String, room_id: String) -> void:
	for narrative_id: String in _armed.keys():
		var entry: Dictionary = _armed[narrative_id]
		if str(entry.get("kind", "")) != NarrativeScript3D.TRIGGER_KIND_EVENT:
			continue
		if str(entry.get("on", "")) != event_name:
			continue
		var filter: Dictionary = entry.get("filter", {})
		var wanted_room := str(filter.get("room_id", ""))
		if not wanted_room.is_empty() and wanted_room != room_id:
			continue
		_try_fire(narrative_id, entry, {"event": event_name, "room_id": room_id})


func _evaluate_point() -> void:
	var player := _adapter.player_node()
	if player == null:
		return
	var position := player.global_position
	for narrative_id: String in _armed.keys():
		var entry: Dictionary = _armed[narrative_id]
		if str(entry.get("kind", "")) != NarrativeScript3D.TRIGGER_KIND_POINT:
			continue
		var origin_value: Variant = entry.get("point", null)
		if not (origin_value is Vector3):
			continue
		var origin := origin_value as Vector3
		var radius := float(entry.get("radius", NarrativeScript3D.MIN_POINT_RADIUS_M))
		var tolerance := float(
			entry.get("height_tolerance", NarrativeScript3D.DEFAULT_HEIGHT_TOLERANCE_M)
		)
		# 水平距离 + 垂直带两个条件，而不是纯球形距离 —— 否则「在楼上走过、
		# 脚下正下方就是触发点」会误触发（08 文档 §4.2）。
		var planar := Vector2(position.x - origin.x, position.z - origin.z).length()
		if planar > radius:
			continue
		if absf(position.y - origin.y) > tolerance:
			continue
		_try_fire(narrative_id, entry, {"event": "point", "distance": planar})


func _evaluate_manual() -> void:
	for narrative_id: String in _armed.keys():
		var entry: Dictionary = _armed[narrative_id]
		if str(entry.get("kind", "")) != NarrativeScript3D.TRIGGER_KIND_MANUAL:
			continue
		var check: Variant = entry.get("check", null)
		if not (check is Callable) or not (check as Callable).is_valid():
			continue
		if bool((check as Callable).call()):
			_try_fire(narrative_id, entry, {"event": "manual"})


## `once` 与 `cooldown` 的裁决点。判定为真 ≠ 一定播 —— 这里才是"该不该真播"。
func _try_fire(narrative_id: String, entry: Dictionary, context: Dictionary) -> void:
	var once := str(entry.get("once", NarrativeScript3D.ONCE_RUN))
	var fired_count := int(entry.get("fired_count", 0))
	if once == NarrativeScript3D.ONCE_RUN and fired_count > 0:
		return
	if once == NarrativeScript3D.ONCE_NEVER:
		return
	var cooldown := float(entry.get("cooldown", 0.0))
	var now_msec := Time.get_ticks_msec()
	var last_msec := int(entry.get("last_fired_msec", -10_000_000))
	if cooldown > 0.0 and now_msec - last_msec < int(cooldown * 1000.0):
		return
	if not play(narrative_id, context):
		return
	entry["fired_count"] = fired_count + 1
	entry["last_fired_msec"] = now_msec
	_armed[narrative_id] = entry


# =========================================================================
# 播放
# =========================================================================

## 请求播放。返回 false = 没播（校验不过 / 被互斥裁决丢弃 / 被更高优先级抢占后仍失败）。
func play(narrative_id: String, context: Dictionary = {}) -> bool:
	var script := _script_for(narrative_id)
	if script == null:
		_warn("请求播放『%s』但剧本校验不过，已丢弃。" % narrative_id)
		return false
	if not _active.is_empty():
		var current_id := str(_active.get("id", ""))
		if current_id == narrative_id:
			return false
		var current_priority := int(_active.get("priority", 0))
		var incoming := int(context.get("priority", script.priority))
		if incoming <= current_priority:
			# 不排队（08 文档 §3.4）：排队的剧情会在玩家走远后才播，比不播更糟。
			_warn(
				"剧情『%s』(priority=%d) 被正在播放的『%s』(priority=%d) 丢弃。"
				% [narrative_id, incoming, current_id, current_priority]
			)
			return false
		_finish("interrupted")
	_active = {
		"id": narrative_id,
		"script": script,
		"priority": int(context.get("priority", script.priority)),
		"t": 0.0,
		"index": 0,
		"occupancy": [],
		"auto_invulnerable": not _script_declares_invulnerable(script),
	}
	_dispatch_log.clear()
	_dispatch_log.append("start:%s" % narrative_id)
	narrative_started.emit(narrative_id)
	return true


func _script_declares_invulnerable(script: NarrativeScript3D) -> bool:
	for cue in script.cues:
		if str(cue.get("do", "")) == "player.invulnerable":
			return true
	return false


func is_playing() -> bool:
	return not _active.is_empty()


## 当前演出已推进的游戏秒数（没有演出时为 0）。用于验收与运行时调试面板。
func active_time() -> float:
	return float(_active.get("t", 0.0))


## 仅供验收：把一段内存剧本塞进缓存（不落文件、不进目录、不进存档）。
## 与 reset_for_test() 同属测试面，运行时无人调用。
func register_script_for_test(narrative_id: String, script: NarrativeScript3D) -> void:
	if narrative_id.is_empty() or script == null:
		return
	_scripts[narrative_id] = script


## 仅供验收：返回当前绑定的"地牢"（场景根）。用于验证 _on_node_added 的自动绑定链
## 没断 —— 它断了只会表现为"剧情不触发"，运行时没有任何报错，所以必须能断言。
func bound_dungeon_for_test() -> Node:
	return _dungeon


## 仅供验收：以「事件名 + 房间 id」走一遍真实的事件评估（等价于 Dungeon3D 的
## room_entered 信号路径），绕开信号接线本身，单独验证裁决逻辑。
func evaluate_event_for_test(event_name: String, room_id: String) -> void:
	_evaluate_event(event_name, room_id)


func active_id() -> String:
	return str(_active.get("id", ""))


func is_camera_override_active() -> bool:
	return _adapter.is_camera_override_active()


## 演出是否正在独占玩家输入。Dungeon3D 每帧的 _sync_player_input_lock() 必须问这里，
## 否则演出的"停住"会被逐帧顶掉（运行时零报错，只表现为角色照常能动）。
func is_player_input_locked() -> bool:
	return _adapter.is_player_input_locked()


## 叙事是否正在接管演员朝向（actor.face 生效期间）。Player3D 的鼠标瞄准必须问这里让位，
## 否则玩家一晃鼠标就把剧本摆好的"左右张望"顶掉（运行时零报错，只表现为中间错乱）。
func is_actor_facing_overridden() -> bool:
	return _adapter.is_actor_facing_overridden()


# =========================================================================
# 时间轴
# =========================================================================

func _process(delta: float) -> void:
	if _active.is_empty():
		_tick_triggers(delta)
		return
	_adapter.tick(delta)
	var script := _active.get("script") as NarrativeScript3D
	if script == null:
		_finish("aborted")
		return
	_active["t"] = float(_active.get("t", 0.0)) + delta
	var now := float(_active["t"])
	var index := int(_active.get("index", 0))
	# 同一 at 的多条 cue 在**同一帧内连续执行**（不跨帧），与 08 文档 §3.3 一致。
	while index < script.cues.size() and float(script.cues[index]["at"]) <= now + 0.0001:
		var cue := script.cues[index]
		index += 1
		var finished_early := _dispatch_cue(cue)
		if finished_early:
			_active["index"] = index
			_finish("flow.end")
			return
	_active["index"] = index
	if now >= script.duration:
		_finish("duration")


func _tick_triggers(delta: float) -> void:
	_adapter.tick(delta)
	_poll_accumulator += delta
	if _poll_accumulator >= POINT_POLL_INTERVAL:
		_poll_accumulator = fmod(_poll_accumulator, POINT_POLL_INTERVAL)
		_evaluate_point()
	_check_accumulator += delta
	if _check_accumulator >= MANUAL_CHECK_INTERVAL:
		_check_accumulator = fmod(_check_accumulator, MANUAL_CHECK_INTERVAL)
		_evaluate_manual()


## 派发一条 cue。返回 true = 该条要求提前收场（flow.end）。
func _dispatch_cue(cue: Dictionary) -> bool:
	var verb := str(cue.get("do", ""))
	var params := cue.duplicate(true)
	params.erase("at")
	params.erase("do")
	if verb == "flow.end":
		_dispatch_log.append("%.2f flow.end" % float(cue.get("at", 0.0)))
		return true
	if verb == "flow.mark":
		_flags[str(params.get("key", ""))] = true
		_dispatch_log.append("%.2f flow.mark:%s" % [float(cue.get("at", 0.0)), str(params.get("key", ""))])
		return false
	if verb == "grant.flag":
		_flags[str(params.get("key", ""))] = params.get("value", true)
		_dispatch_log.append("%.2f grant.flag:%s" % [float(cue.get("at", 0.0)), str(params.get("key", ""))])
		return false

	var result := _adapter.call_instruction(verb, params)
	if bool(result.get("ok", false)):
		_dispatch_log.append("%.2f %s" % [float(cue.get("at", 0.0)), verb])
		var restore: Variant = result.get("restore", null)
		if restore is Callable and (restore as Callable).is_valid():
			_occupy(_occupancy_label(verb), restore as Callable)
		if verb == "player.lock_input" and bool(params.get("locked", true)):
			_apply_auto_invulnerability()
		return false
	if bool(result.get("degraded", false)):
		# 降级不停摆（08 文档 §5.3）：告警 + 跳过，时间轴照走。
		_warn("cue『%s』降级跳过：%s" % [verb, str(result.get("reason", ""))])
	else:
		_diagnose("cue『%s』执行失败：%s" % [verb, str(result.get("reason", ""))])
	return false


func _occupancy_label(verb: String) -> String:
	match verb:
		"player.lock_input":
			return "player.input"
		"player.combat":
			return "player.combat"
		"player.invulnerable":
			return "player.invulnerable"
		"fx.music", "fx.music_push":
			return "music"
	if verb.begins_with("camera."):
		return "camera"
	if verb.begins_with("actor.face"):
		return "actor.facing"
	if verb.begins_with("actor.pose"):
		return "actor.pose"
	return verb


## 声明式占用：同一标签只登记第一次，因此「还原的是接管前的原始值」天然成立。
func _occupy(label: String, restore: Callable) -> void:
	var occupancy: Array = _active.get("occupancy", [])
	for entry: Dictionary in occupancy:
		if str(entry.get("label", "")) == label:
			return
	occupancy.append({"label": label, "restore": restore})
	_active["occupancy"] = occupancy


## §5.5：演出期间玩家被锁输入 = 站着挨打，默认挂受击免疫（作者不用写）。
## 剧本若**显式**写了 player.invulnerable，以显式值为准，本默认不介入。
func _apply_auto_invulnerability() -> void:
	if not bool(_active.get("auto_invulnerable", false)):
		return
	_dispatch_log.append("auto player.invulnerable:true")
	var result := _adapter.call_instruction("player.invulnerable", {"who": "player", "enabled": true})
	var restore: Variant = result.get("restore", null)
	if restore is Callable and (restore as Callable).is_valid():
		_occupy("player.invulnerable", restore as Callable)


# =========================================================================
# 收口：四条时机，同一个归还入口
# =========================================================================

## 正常 / flow.end / 被打断 / abort 全部走这里 —— 一个都不能漏（08 文档 §6.1）。
func _finish(reason: String) -> void:
	if _active.is_empty():
		return
	var narrative_id := str(_active.get("id", ""))
	_release_all(reason)
	_active = {}
	_dispatch_log.append("finish:%s" % reason)
	narrative_finished.emit(narrative_id, reason)


## 已发生的效果不回滚（音效已响、门已开就保持），只还独占资源（08 文档 §6.4）。
func _release_all(reason: String) -> void:
	var occupancy: Array = _active.get("occupancy", []).duplicate()
	occupancy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _release_priority(str(a.get("label", ""))) < _release_priority(str(b.get("label", "")))
	)
	for entry: Dictionary in occupancy:
		var restore: Variant = entry.get("restore", null)
		if not (restore is Callable) or not (restore as Callable).is_valid():
			continue
		(restore as Callable).call()
	_active["occupancy"] = []
	if reason != "duration" and reason != "flow.end":
		_warn("剧情被『%s』收口，现场已强制归还。" % reason)


func _release_priority(label: String) -> int:
	if RELEASE_PRIORITY.has(label):
		return int(RELEASE_PRIORITY[label])
	if label.begins_with("camera"):
		return 1
	return 5


## 显式跳过：整场终止（不是逐句快进，08 文档 §6.4）。
func skip() -> void:
	if _active.is_empty():
		return
	_finish("skip")


## 立刻中止：先解锁输入、先还原相机（08 文档 §6.2），再清理其余占用。
func abort(reason: String) -> void:
	if _active.is_empty():
		return
	_finish("abort:%s" % reason)


# =========================================================================
# 本局标记（内存态，不进存档；08 文档 §9）
# =========================================================================

func set_flag(key: String, value: Variant = true) -> void:
	if key.is_empty():
		return
	_flags[key] = value


func get_flag(key: String, fallback: Variant = false) -> Variant:
	return _flags.get(key, fallback)


func has_flag(key: String) -> bool:
	return _flags.has(key)


## 仅供验收与调试：清干净一切（不动场景，场景由归还机制负责）。
func reset_for_test() -> void:
	if not _active.is_empty():
		_finish("test_reset")
	_flags.clear()
	_armed.clear()
	_scripts.clear()
	_diagnostics.clear()
	_dispatch_log.clear()


# =========================================================================
# 暂停同步：DialogueUI 是 ALWAYS，树暂停时它仍会打字并自动推进
# =========================================================================

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_sync_dialogue_pause(true)
	elif what == NOTIFICATION_UNPAUSED:
		_sync_dialogue_pause(false)


## 只在**本系统持有演出**时同步，保证对话 UI 的独立验收与既有行为一字不变（08 文档 §6.3）。
func _sync_dialogue_pause(paused: bool) -> void:
	if _active.is_empty():
		_paused_dialogue_synced = false
		return
	if _paused_dialogue_synced == paused:
		return
	_paused_dialogue_synced = paused
	if DialogueUI != null and DialogueUI.has_method("set_paused"):
		DialogueUI.set_paused(paused)
