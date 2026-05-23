class_name RoomEventHandler
extends Node2D
## 事件房事件处理器 — 接管 EVENT 房间的随机事件逻辑
## 
## 事件类型：
## - CURSE: 诅咒降临（怪物伤害+15%，持续当前房间）
## - BLESSING: 祝福降临（玩家伤害+10%，持续60秒）
## - TRADE: 命运交易（用命运卡片交换资源）
## - GAMBLE: 赌局（投入魂，有概率获得高额回报）
## - REVEAL: 地图揭示（显示周围3格房间类型）
## - SUMMON: 亡者召唤（触发额外一波怪物）
## 
## 每个事件有进入触发、处理、结果三个阶段

## 信号
signal event_started(event_type: String, event_name: String)
signal event_completed(event_type: String, result: String, reward: Dictionary)
signal event_interrupted()

enum EventType {
	CURSE,      # 诅咒降临
	BLESSING,   # 祝福降临
	TRADE,      # 命运交易
	GAMBLE,     # 赌局
	REVEAL,     # 地图揭示
	SUMMON,     # 亡者召唤
}

enum EventPhase {
	IDLE,
	ACTIVE,
	RESOLVED,
}

## 事件配置
class GameEvent:
	var event_type: EventType
	var event_name: String
	var description: String
	var risk_level: int  # 1-3，1低风险/3高风险
	var min_floor: int = 1
	var reward_preview: String = ""
	
	func _init(type: EventType, name: String, desc: String, risk: int, min_f: int = 1) -> void:
		event_type = type
		event_name = name
		description = desc
		risk_level = risk
		min_floor = min_f

## 状态
var _current_event: GameEvent = null
var _phase: EventPhase = EventPhase.IDLE
var _player_ref: Node = null
var _room_data: RoomData = null
var _fate_card_engine: Node = null
var _ui_layer: CanvasLayer = null
var _event_active: bool = false

## 事件配置库
var _event_library: Array[GameEvent] = []

func _ready() -> void:
	_initialize_event_library()

## 初始化事件库（根据 PH11 设计配置）
func _initialize_event_library() -> void:
	_event_library.clear()
	
	# 诅咒降临：全局怪物伤害+15%，持续当前房间
	var curse := GameEvent.new(
		EventType.CURSE,
		"诅咒降临",
		"黑暗力量侵蚀这个房间，所有怪物获得伤害加成",
		3, 1
	)
	curse.reward_preview = "怪物伤害+15% (当前房间)"
	_event_library.append(curse)
	
	# 祝福降临：玩家伤害+10%，持续60秒
	var blessing := GameEvent.new(
		EventType.BLESSING,
		"祝福降临",
		"神秘力量注入你的武器，伤害临时提升",
		1, 1
	)
	blessing.reward_preview = "玩家伤害+10% (60秒)"
	_event_library.append(blessing)
	
	# 命运交易：消耗一张命运卡片，获得魂或道具
	var trade := GameEvent.new(
		EventType.TRADE,
		"命运交易",
		"与命运之灵交易，用你的命运卡片换取资源",
		2, 1
	)
	trade.reward_preview = "消耗命运卡片 → 获得魂或道具"
	_event_library.append(trade)
	
	# 赌局：投入魂，有概率获得2-5倍回报
	var gamble := GameEvent.new(
		EventType.GAMBLE,
		"赌局",
		"神秘商人发起赌局，投入魂可获得加倍回报",
		3, 2
	)
	gamble.reward_preview = "投入魂 ×2~5 倍概率回报"
	_event_library.append(gamble)
	
	# 地图揭示：显示周围3格房间类型
	var reveal := GameEvent.new(
		EventType.REVEAL,
		"地图揭示",
		"地图上的迷雾散去，你看到了周围的房间布局",
		1, 1
	)
	reveal.reward_preview = "小地图显示周围3格房间类型"
	_event_library.append(reveal)
	
	# 亡者召唤：触发额外一波怪物
	var summon := GameEvent.new(
		EventType.SUMMON,
		"亡者召唤",
		"亡灵响应召唤，额外一波敌人出现",
		2, 2
	)
	summon.reward_preview = "额外一波怪物 (击杀后掉落)"
	_event_library.append(summon)

## 设置玩家引用和房间数据
func setup(player: Node, room_data: RoomData) -> void:
	_player_ref = player
	_room_data = room_data
	_phase = EventPhase.IDLE

## 获取当前房间数据
func get_room_data() -> RoomData:
	return _room_data

## 激活事件房：选择随机事件并触发
func activate() -> bool:
	if _event_active:
		return false
	
	if _event_library.is_empty():
		push_warning("[RoomEventHandler] Event library empty, cannot activate")
		return false
	
	# 过滤可用事件（按楼层）
	var floor_level: int = 1
	if _room_data != null:
		floor_level = _room_data.floor
	
	var available_events: Array[GameEvent] = []
	for ev in _event_library:
		if ev.min_floor <= floor_level:
			available_events.append(ev)
	
	if available_events.is_empty():
		push_warning("[RoomEventHandler] No events available for floor %d" % floor_level)
		return false
	
	# 随机选一个事件
	available_events.shuffle()
	_current_event = available_events[0]
	_event_active = true
	_phase = EventPhase.ACTIVE
	
	print("[RoomEventHandler] 事件房激活: [%s] %s — %s" % [
		EventType.keys()[_current_event.event_type],
		_current_event.event_name,
		_current_event.description
	])
	
	event_started.emit(
		EventType.keys()[_current_event.event_type],
		_current_event.event_name
	)
	
	# 触发事件效果
	_apply_event_effect()
	return true

## 应用事件效果
func _apply_event_effect() -> void:
	if _current_event == null:
		return
	
	match _current_event.event_type:
		EventType.CURSE:
			_apply_curse()
		EventType.BLESSING:
			_apply_blessing()
		EventType.TRADE:
			_apply_trade()
		EventType.GAMBLE:
			_apply_gamble()
		EventType.REVEAL:
			_apply_reveal()
		EventType.SUMMON:
			_apply_summon()
	
	_phase = EventPhase.RESOLVED

## 诅咒降临：怪物伤害+15%
func _apply_curse() -> void:
	print("[RoomEventHandler] 诅咒降临: 怪物伤害+15%，持续当前房间")
	# 通过 FateCardEngine 应用全局效果
	# 在 _on_room_exited 时撤销
	_show_event_notification("诅咒降临！怪物伤害+15%", Color(0.7, 0.1, 0.1))
	
	# 设置房间级别的怪物伤害加成标记
	if _room_data != null:
		_room_data.set_meta("curse_active", true)
		_room_data.set_meta("curse_bonus", 0.15)

## 祝福降临：玩家伤害+10%，持续60秒
func _apply_blessing() -> void:
	print("[RoomEventHandler] 祝福降临: 玩家伤害+10%，持续60秒")
	_show_event_notification("祝福降临！伤害+10% (60秒)", Color(0.2, 0.9, 0.2))
	
	# 通过 Player 应用临时伤害加成
	if _player_ref != null and _player_ref.has_method("apply_damage_buff"):
		var timer: SceneTreeTimer = get_tree().create_timer(60.0)
		timer.timeout.connect(_on_blessing_expired)
		_player_ref.apply_damage_buff("blessing", 0.10)
	else:
		# 直接设置 Player 的伤害倍率
		if _player_ref != null and _player_ref.has_method("set_damage_multiplier"):
			_player_ref.set_damage_multiplier("blessing", 1.10)

func _on_blessing_expired() -> void:
	print("[RoomEventHandler] 祝福效果结束")
	if _player_ref != null and _player_ref.has_method("remove_damage_buff"):
		_player_ref.remove_damage_buff("blessing")

## 命运交易：消耗命运卡片获取资源
func _apply_trade() -> void:
	print("[RoomEventHandler] 命运交易事件触发")
	_show_trade_ui()

func _show_trade_ui() -> void:
	# 显示交易UI（使用现有的 DivinationMenu 或新建）
	# 检查 FateCardGameBridge 中是否有已应用的卡片
	var bridge: Node = get_node_or_null("/root/FateCardGameBridge")
	var has_cards: bool = false
	if bridge != null and bridge.has_method("get_card_count"):
		has_cards = bridge.get_card_count() > 0
	
	if has_cards:
		_show_event_notification("命运交易: 选择一张卡片换取资源", Color(0.9, 0.9, 0.3))
		# 这里简化处理：直接给奖励而不需要玩家交互选择
		# 完整实现需要 UI 层，这里用控制台输出+效果模拟
		_grant_trade_reward()
	else:
		_show_event_notification("命运交易: 无卡片可交易，事件取消", Color(0.5, 0.5, 0.5))

func _grant_trade_reward() -> void:
	# 给玩家魂作为交易奖励
	var currency_to_add: int = randi() % 50 + 30  # 30-80魂
	if _player_ref != null and _player_ref.has_method("add_currency"):
		_player_ref.add_currency(currency_to_add)
	elif GameManager != null:
		GameManager.add_currency(currency_to_add)
	print("[RoomEventHandler] 命运交易奖励: +%d 魂" % currency_to_add)
	event_completed.emit(EventType.keys()[EventType.TRADE], "success", {"currency": currency_to_add})

## 赌局：投入魂，有概率获得2-5倍回报
func _apply_gamble() -> void:
	print("[RoomEventHandler] 赌局事件触发")
	
	var player_currency: int = 0
	if _player_ref != null and _player_ref.has_method("get_currency"):
		player_currency = _player_ref.get_currency()
	elif GameManager != null:
		player_currency = GameManager.currency
	
	# 需要至少20魂才能参与
	if player_currency < 20:
		_show_event_notification("赌局: 魂不足(需要20)，事件取消", Color(0.5, 0.5, 0.5))
		_phase = EventPhase.RESOLVED
		return
	
	# 计算投入量（最多投入一半）
	var bet_amount: int = mini(player_currency / 2, 100)
	bet_amount = maxi(bet_amount, 20)
	
	# 50%概率赢
	var won: bool = randi() % 2 == 0
	var multiplier: int = 2 + randi() % 4  # 2-5倍
	
	if won:
		var reward: int = bet_amount * multiplier
		if _player_ref != null and _player_ref.has_method("add_currency"):
			_player_ref.add_currency(reward)
		elif GameManager != null:
			GameManager.add_currency(reward)
		_show_event_notification("赌局胜利! +%d 魂 (×%d)" % [reward, multiplier], Color(0.2, 0.9, 0.2))
		print("[RoomEventHandler] 赌局胜利: 投入%d → 回报%d (×%d)" % [bet_amount, reward, multiplier])
		event_completed.emit(EventType.keys()[EventType.GAMBLE], "win", {"reward": reward, "bet": bet_amount, "multiplier": multiplier})
	else:
		# 输了：扣除投入的魂
		if _player_ref != null and _player_ref.has_method("spend_currency"):
			_player_ref.spend_currency(bet_amount)
		elif GameManager != null:
			var current: int = GameManager.currency
			GameManager.set_currency(current - bet_amount)
		_show_event_notification("赌局失败... -%d 魂" % bet_amount, Color(0.8, 0.2, 0.2))
		print("[RoomEventHandler] 赌局失败: -%d 魂" % bet_amount)
		event_completed.emit(EventType.keys()[EventType.GAMBLE], "lose", {"lost": bet_amount})
	
	_phase = EventPhase.RESOLVED

## 地图揭示：显示周围3格房间类型
func _apply_reveal() -> void:
	print("[RoomEventHandler] 地图揭示事件触发")
	_show_event_notification("地图揭示: 周围房间类型已显示", Color(0.3, 0.5, 0.9))
	
	# 通过 MapManager 获取周围房间并刷新小地图
	var map_manager: Node = get_node_or_null("/root/Main/MapManager")
	if map_manager == null:
		map_manager = get_node_or_null("/root/MapManager")
	
	if map_manager != null and map_manager.has_method("reveal_adjacent_rooms"):
		map_manager.reveal_adjacent_rooms(_room_data.room_id if _room_data != null else "")
	
	_phase = EventPhase.RESOLVED
	event_completed.emit(EventType.keys()[EventType.REVEAL], "success", {})

## 亡者召唤：触发额外一波怪物
func _apply_summon() -> void:
	print("[RoomEventHandler] 亡者召唤事件触发")
	_show_event_notification("亡者召唤! 一波新敌人出现...", Color(0.5, 0.1, 0.7))
	
	# 通过 RoomGameMode 触发额外波次
	var room_game_mode: Node = get_node_or_null("/root/Main/RoomGameMode")
	if room_game_mode == null:
		room_game_mode = get_node_or_null("/root/RoomGameMode")
	
	if room_game_mode != null and room_game_mode.has_method("trigger_extra_wave"):
		room_game_mode.trigger_extra_wave()
		print("[RoomEventHandler] 额外波次已触发")
	
	_phase = EventPhase.RESOLVED
	event_completed.emit(EventType.keys()[EventType.SUMMON], "success", {})

## 显示事件通知（通过 GameUIManager）
func _show_event_notification(message: String, color: Color) -> void:
	var ui: Node = get_node_or_null("/root/Main/GameUIManager")
	if ui == null:
		ui = get_node_or_null("/root/GameUIManager")
	
	if ui != null and ui.has_method("show_event_notification"):
		ui.show_event_notification(message, color)
	else:
		# 降级到控制台打印
		print("[RoomEventHandler] 事件通知: %s" % message)

## 物理进程（处理事件房内玩家交互）
func _on_physics_process(_delta: float) -> void:
	if not _event_active:
		return
	if _phase != EventPhase.ACTIVE:
		return

## 获取当前事件信息
func get_current_event() -> Dictionary:
	if _current_event == null:
		return {}
	return {
		"event_type": EventType.keys()[_current_event.event_type] if _current_event != null else "",
		"event_name": _current_event.event_name if _current_event != null else "",
		"description": _current_event.description if _current_event != null else "",
		"risk_level": _current_event.risk_level if _current_event != null else 0,
		"reward_preview": _current_event.reward_preview if _current_event != null else ""
	}

## 是否事件已激活
func is_active() -> bool:
	return _event_active

## 清理事件状态（玩家离开房间时调用）
func cleanup() -> void:
	if _current_event != null and _current_event.event_type == EventType.CURSE:
		# 离开诅咒房间时撤销效果
		if _room_data != null:
			_room_data.set_meta("curse_active", null)
			_room_data.set_meta("curse_bonus", null)
	
	_current_event = null
	_event_active = false
	_phase = EventPhase.IDLE

func _to_string() -> String:
	return "[RoomEventHandler: active=%s, event=%s]" % [
		_event_active,
		_current_event.event_name if _current_event != null else "none"
	]