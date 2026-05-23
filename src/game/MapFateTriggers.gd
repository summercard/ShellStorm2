class_name MapFateTriggers
extends Node

# MapFateTriggers.gd — 地图环境命运触发器
# 监听游戏事件（击杀/开箱/进入房间），触发阈值后应用命运效果
# 接入 FateCardEngine 的效果执行能力，但不修改武器树

## 信号
signal trigger_activated(trigger_type: String, threshold: int, fate_card_id: String, effect_preview: String)
signal counter_updated(trigger_type: String, current: int, threshold: int)

## 触发器类型
enum TriggerType {
	KILL_COUNT,       # 累计击杀N个敌人
	OPEN_CHEST,       # 累计开启N个容器
	ENTER_ROOM,       # 累计进入N个房间
	CURRENCY_SUM,     # 累计拾取N次货币
	ELITE_KILL,       # 击杀精英怪
	TIME_SURVIVAL,    # 局内存活时间（秒）
}

## 一个触发器配置
class TriggerConfig:
	var trigger_type: TriggerType
	var threshold: int          # 触发阈值
	var fate_card_id: String    # 触发的命运卡片ID
	var cooldown: float = 30.0  # 冷却时间（秒）
	var once_per_run: bool = true  # 是否每局只触发一次
	var enabled: bool = true

## 状态
var _triggers: Array[TriggerConfig] = []
var _counters: Dictionary = {}     # trigger_type → current count
var _last_trigger_time: Dictionary = {}  # trigger_type → last trigger timestamp
var _triggered_this_run: Dictionary = {}  # trigger_type → bool (for once_per_run)
var _fate_card_bridge: Node = null
var _room_game_mode: Node = null
var _connected: bool = false

## 默认触发器配置
const DEFAULT_TRIGGERS: Array[Dictionary] = [
	# 击杀触发：连续击杀3个敌人 → 敌增援
	{"trigger_type": TriggerType.KILL_COUNT, "threshold": 3, "fate_card_id": "fate_reinforce", "cooldown": 15.0, "once_per_run": false},
	# 击杀触发：击杀第10个敌人 → 获得一张随机命运卡片
	{"trigger_type": TriggerType.KILL_COUNT, "threshold": 10, "fate_card_id": "fate_mark_enemy", "cooldown": 60.0, "once_per_run": true},
	# 开箱触发：开第5个箱子 → 箱子物品品质提升
	{"trigger_type": TriggerType.OPEN_CHEST, "threshold": 5, "fate_card_id": "fate_lucky_chest", "cooldown": 30.0, "once_per_run": false},
	# 开箱触发：开第10个箱子 → 额外掉落
	{"trigger_type": TriggerType.OPEN_CHEST, "threshold": 10, "fate_card_id": "fate_extra_loot", "cooldown": 30.0, "once_per_run": true},
	# 进入房间触发：进入第7个房间 → 诅咒降临（怪物伤害+15%）
	{"trigger_type": TriggerType.ENTER_ROOM, "threshold": 7, "fate_card_id": "fate_curse_map", "cooldown": 45.0, "once_per_run": true},
	# 精英击杀：击杀精英后 → 亡者祝福
	{"trigger_type": TriggerType.ELITE_KILL, "threshold": 1, "fate_card_id": "fate_bless_dead", "cooldown": 30.0, "once_per_run": false},
]

func _ready() -> void:
	_initialize_triggers()
	_connect_signals()
	_reset_counters()

## 初始化触发器配置
func _initialize_triggers() -> void:
	for cfg_dict in DEFAULT_TRIGGERS:
		var cfg := TriggerConfig.new()
		cfg.trigger_type = cfg_dict["trigger_type"]
		cfg.threshold = cfg_dict["threshold"]
		cfg.fate_card_id = cfg_dict["fate_card_id"]
		cfg.cooldown = cfg_dict.get("cooldown", 30.0)
		cfg.once_per_run = cfg_dict.get("once_per_run", true)
		cfg.enabled = true
		_triggers.append(cfg)

## 连接到 RoomGameMode 信号
func _connect_signals() -> void:
	# 延迟连接，等场景树完全加载
	await get_tree().process_frame
	_room_game_mode = get_tree().get_first_node_in_group("room_game_mode")
	if _room_game_mode == null:
		_room_game_mode = get_node_or_null("/root/Main/RoomGameMode")
	if _room_game_mode == null:
		_room_game_mode = get_node_or_null("/root/RoomGameMode")
	
	if _room_game_mode != null:
		var ok: bool = false
		ok = _room_game_mode.kill_recorded.connect(_on_kill_recorded) == OK
		ok = _room_game_mode.room_cleared.connect(_on_room_cleared) == OK
		_room_game_mode.room_entered.connect(_on_room_entered)
		_connected = true
		print("[MapFateTriggers] 已连接到 RoomGameMode")
	else:
		print("[MapFateTriggers] 警告：未找到 RoomGameMode，触发器仅被动计数")

## 重置计数器
func _reset_counters() -> void:
	_counters.clear()
	_last_trigger_time.clear()
	_triggered_this_run.clear()
	for t in TriggerType:
		var key: int = int(t)
		_counters[key] = 0
		_last_trigger_time[key] = -999.0
		_triggered_this_run[key] = false

## ========== 事件处理 ==========

func _on_kill_recorded() -> void:
	_increment_counter(TriggerType.KILL_COUNT)
	var enemy_data = null
	if _room_game_mode != null and _room_game_mode.has_method("get_last_killed_enemy"):
		enemy_data = _room_game_mode.get("last_killed_enemy_data")
	if enemy_data != null and enemy_data.get("is_elite", false):
		_increment_counter(TriggerType.ELITE_KILL)

func _on_room_cleared(room_data) -> void:
	pass  # 房间清理不触发，当前只计数进入

func _on_room_entered(room_data) -> void:
	_increment_counter(TriggerType.ENTER_ROOM)

## 外部调用：容器开启时调用（由 ContainerInteraction 信号或 RoomGameMode 桥接）
func on_container_opened(container_type: String = "crate") -> void:
	_increment_counter(TriggerType.OPEN_CHEST)

## 外部调用：货币拾取时调用
func on_currency_collected(amount: int) -> void:
	_increment_counter(TriggerType.CURRENCY_SUM)

## 外部调用：重置（每局开始）
func reset_for_new_run() -> void:
	_reset_counters()
	_connect_signals()

## ========== 核心逻辑 ==========

func _increment_counter(trigger_type: TriggerType) -> void:
	var key: int = int(trigger_type)
	_counters[key] = _counters.get(key, 0) + 1
	var current: int = _counters[key]
	counter_updated.emit(TriggerType.keys()[trigger_type], current, 0)
	_check_triggers(trigger_type, current)

func _check_triggers(trigger_type: TriggerType, current: int) -> void:
	for cfg: TriggerConfig in _triggers:
		if cfg.trigger_type != trigger_type:
			continue
		if not cfg.enabled:
			continue
		if current < cfg.threshold:
			counter_updated.emit(TriggerType.keys()[trigger_type], current, cfg.threshold)
			_counters[int(cfg.trigger_type)] = current  # 记录进度，供下次累加
			continue
		
		# 检查 once_per_run
		var key: int = int(cfg.trigger_type)
		if cfg.once_per_run and _triggered_this_run.get(key, false):
			continue
		
		# 检查冷却
		var now: float = Time.get_ticks_msec() / 1000.0
		var last_time: float = _last_trigger_time.get(key, -999.0)
		if now - last_time < cfg.cooldown:
			continue
		
		# 触发！
		_triggered_this_run[key] = true
		_last_trigger_time[key] = now
		_fire_trigger(cfg, current)

func _fire_trigger(cfg: TriggerConfig, current: int) -> void:
	var preview: String = _get_effect_preview(cfg.fate_card_id)
	trigger_activated.emit(
		TriggerType.keys()[cfg.trigger_type],
		cfg.threshold,
		cfg.fate_card_id,
		preview
	)
	# 向 UI 发送通知（如果 GameUIManager 存在）
	var ui: Node = _find_ui_manager()
	if ui != null and ui.has_method("show_fate_trigger_notification"):
		ui.show_fate_trigger_notification(
			TriggerType.keys()[cfg.trigger_type],
			cfg.threshold,
			preview
		)
	print("[MapFateTriggers] 触发 %s ×%d → %s (%s)" % [
		TriggerType.keys()[cfg.trigger_type],
		cfg.threshold,
		cfg.fate_card_id,
		preview
	])

## 根据 fate_card_id 返回效果预览文字
func _get_effect_preview(fate_card_id: String) -> String:
	var previews: Dictionary = {
		"fate_reinforce": "敌增援触发！波次外额外刷怪",
		"fate_mark_enemy": "命运标记！击杀第10敌获得随机卡片",
		"fate_lucky_chest": "幸运发现！下一个箱子品质提升",
		"fate_extra_loot": "额外掉落！开箱获得额外物品",
		"fate_curse_map": "诅咒降临！本房间怪物伤害+15%",
		"fate_bless_dead": "亡者祝福！HP<30%后获得30秒伤害加成",
	}
	return previews.get(fate_card_id, "命运效果: %s" % fate_card_id)

func _find_ui_manager() -> Node:
	var ui: Node = get_node_or_null("/root/Main/GameUIManager")
	if ui == null:
		ui = get_node_or_null("/root/GameUIManager")
	return ui