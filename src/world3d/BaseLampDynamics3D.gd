extends Node3D
## 99F 基地「活着的灯」：
##   A 霓虹标识间歇抽动 · B 床头灯呼吸 · C 贩卖机屏幕眯眼 · D 配电柜三灯自检流水
##   E1 走廊应急灯双跳（红） · E2 主门警示灯待机呼吸（黄） · F 二楼电脑屏 CRT 频闪
##
## 三条硬约束（不写下来后来人一定会踩）：
##
## 1. **不能直接写 emission_energy_multiplier 的绝对值。**
##    `BaseFixtureGlow3D` 已经是这些材质的唯一所有者：墙面开关写 0 / 原值，
##    4.2s 启动序列写 0 / 0.16 / 1.0，谁后写谁赢。这里只在它「静止」的时段
##    （lighting_enabled 且 not presentation_starting）写 `base × motion_factor`，
##    并在它重新接管时把当时的能量当 baseline 读回。
##
## 2. **启动序列期间 motion_factor 必须保持 1。** 否则分批闪烁会被呼吸项叠成
##    「忽明忽暗的抖动」，把业主 2026-09-24 定的启动节奏搅乱。
##
## 3. **事件必须错开。** 六个对象各闪各的就是夜店。所有事件型通道共用一道闸门：
##    全场同时最多 MAX_CONCURRENT_EVENTS 个事件、相邻两次事件起始至少间隔
##    MIN_EVENT_GAP_SECONDS；被挡住的不是丢弃，而是顺延 0.5~1.2s 重试。

## 相邻两次「事件」起始的最小间隔。业主 2026-10-18：「节奏不要太快 时间错开」。
const MIN_EVENT_GAP_SECONDS := 2.9
## 同时处于事件中的通道上限（D 的自检流水是背景节拍，不计入）。
const MAX_CONCURRENT_EVENTS := 2

## A 霓虹：业主原话「偶尔间歇性闪烁，8-15 秒一次」⇒ 保留这个区间，不再放慢。
const NEON_INTERVAL_MIN := 8.0
const NEON_INTERVAL_MAX := 15.0
const NEON_EVENT_MIN := 0.62
const NEON_EVENT_MAX := 0.96
## 只降到 0.72：招牌仍完整可读，不读成「断电」。
const NEON_DIP := 0.28

## B 床头灯：缓慢呼吸。
##
## ⚠️ 方向必须是**向下**沉，不能向上抬。这盏灯的 energ 已经到 13.97、灯罩在 filmic 下
## 是完全过曝的纯白（实测 255,255,255）；往上加能量在画面上是 0 变化。真渲染量过梯度：
## ×1.00 → ×0.90 就有 32614 个像素变化，×1.00 → 往上一档则几乎为 0。
## 所以呼吸做成「暗下去再回来」，周期 5.4s、最深 -13%，读作缓慢呼吸而不是接触不良。
const LAMP_PERIOD := 5.4
const LAMP_DIP := 0.10
const LAMP_BREATH := 0.03

## C 贩卖机：常态轻微起伏 + 偶发「眯眼」暗脉冲（眼睛是几何浮雕，做不了真眨眼）。
const VENDING_IDLE_PERIOD := 3.4
const VENDING_IDLE_DEPTH := 0.03
const VENDING_BLINK_MIN := 9.0
const VENDING_BLINK_MAX := 14.0
const VENDING_BLINK_DURATION := 0.26
const VENDING_BLINK_DIPTH := 0.38

## D 配电柜三灯：自检流水。
const STATUS_DIM := 0.18
const STATUS_PEAK := 1.85
const STATUS_ON := 0.70
const STATUS_STAGGER := 0.32
const STATUS_ROUND_TOTAL := STATUS_ON + 2.0 * STATUS_STAGGER
const STATUS_GAP_MIN := 2.8
const STATUS_GAP_MAX := 4.2

## E1 应急灯：间歇双跳（亮-暗-亮-暗-亮），比 A 更「故障」。
const EMERGENCY_INTERVAL_MIN := 6.5
const EMERGENCY_INTERVAL_MAX := 12.0
const EMERGENCY_EVENT_MIN := 0.95
const EMERGENCY_EVENT_MAX := 1.40
const EMERGENCY_LOW := 0.15

## E2 主门警示灯：慢呼吸，与 E1 的故障语义区分开，相位错开。
## 幅度校准：7% 在真渲染里只有 max 6/255 的差（灯小、又在过曝区），
## 提到 13% 才在暗环境里读得出「它在轻轻起伏」，仍远低于 E1 的故障跳（1.00→0.15）。
const DOOR_PERIOD := 8.6
const DOOR_PHASE := 2.2
const DOOR_LIFT := 0.125
const DOOR_BREATH := 0.032

## F 二楼电脑屏：常态 CRT 扫描起伏 + 偶发快速频闪。
## 屏幕面原本 emission_enabled=false（它是 03_清漆反光，靠反光显色），
## 由本脚本 duplicate 一份并自己开自发光，基准能量见 SCREEN_ENERGY。
## 频闪时的屏幕亮度（=「点亮」那一档）。常态倍率是 0，即屏幕完全不发光、
## 保持与改动前逐像素一致的原外观 —— 只在事件里亮起来抖。
## 这一点很关键：屏幕原本是 03_清漆反光 面、靠反光显色，
## 若常态就给它光，等于把美术的深蓝屏改成亮蓝屏，是「改外观」而不是「加动态」。
const SCREEN_ENERGY := 1.35
## 屏幕光色（冷蓝）。
const SCREEN_COLOR := Color(0.13, 0.38, 0.62)
const PC_EVENT_MIN := 10.0
const PC_EVENT_MAX := 16.5
const PC_EVENT_DURATION_MIN := 0.26
const PC_EVENT_DURATION_MAX := 0.46
## 事件内的亮度基线（0.78）、抖动半幅（0.34）、夹紧区间 [0.30, 1.15]。
const PC_EVENT_LEVEL := 0.78
const PC_EVENT_SWING := 0.34
const PC_LOW_CLAMP := 0.30
const PC_HIGH_CLAMP := 1.15

## 登记表：节点名 → 网格名 → surface。全部由 _scratch 探针实测得出，
## 不是猜的：名字对不上会打印 BASE_LAMP_TARGET_MISSING 并在验收里失败。
const TARGETS := [
	{"channel": "neon", "node": "BASE_CAMP霓虹标识",
		"mesh": "ENV_BASE99_WALL_CONTENT_BASE_CAMP_NEON_SIGN_V021", "surface": 0, "spill": true},
	{"channel": "lamp", "node": "33_暖橙床头灯_资产包",
		"mesh": "33_柔和自发光_v019", "surface": 0, "spill": true},
	{"channel": "vending", "node": "72_SUPPLY24H自动补给机",
		"mesh": "ENV_BASE99_REMAINING_EAST_SUPPLY_24H_STATION_V021", "surface": 2},
	{"channel": "status", "node": "东墙工业配电",
		"mesh": "东墙POWER配电柜_状态灯_01_自发光", "surface": 0},
	{"channel": "status", "node": "东墙工业配电",
		"mesh": "东墙POWER配电柜_状态灯_02_自发光", "surface": 0},
	{"channel": "status", "node": "东墙工业配电",
		"mesh": "东墙POWER配电柜_状态灯_03_自发光", "surface": 0},
	{"channel": "emergency", "node": "62_主通道应急灯组",
		"mesh": "主通道应急灯_13_8_自发光", "surface": 0},
	{"channel": "door", "node": "BASE主门_橙色警示灯",
		"mesh": "BASE主门_橙色警示灯_自发光_001", "surface": 0},
	# ⚠️ 屏幕是 `42_主体` 的 surface 2（03_清漆反光），不是 `42_柔和自发光_v019_001`
	#    —— 后者逐面染色实测是**台灯发光头**（4 组色里最大一组只有 2.46×0.05m 的灯条）。
	#    这面原本 emission_enabled=false，所以要由本脚本自己开自发光（self_owned）。
	{"channel": "loft_pc", "node": "42_双屏电脑完整工位",
		"mesh": "42_主体_v019_001", "surface": 2, "self_owned": true},
]


class Slot:
	extends RefCounted
	var material: BaseMaterial3D
	var base_energy := 1.0
	var factor := 1.0
	var spill: OmniLight3D
	var spill_base := 0.0
	## true = 这面原本不自发光，由本脚本自己开 emission（显示器屏幕）。
	## 它不在 BaseFixtureGlow3D 的受控表里，所以关灯时必须自己负责熄灭。
	var self_owned := false


class Channel:
	extends RefCounted
	var key := ""
	var slots: Array[Slot] = []
	var next_at := 0.0
	var event_start := -1.0
	var event_end := -1.0
	var event_frequency := 11.0
	var round_start := -100.0

	func is_event_running() -> bool:
		return event_start >= 0.0


var _channels: Dictionary = {}
var _slot_count := 0
var _clock := 0.0
var _events_active := 0
var _last_event_start := -1000.0
var _needs_resync := true
var _was_active := false
var _missing: Array[String] = []
## 自带随机源，不用全局 randf()。
## 理由：全局 RNG 会被别的系统消耗，导致「同一时刻进基地」的节奏每次都不同，
## 真渲染对照无法重现（第一次截图验收就栽在这里：规划时刻与实际亮暗对不上）。
var _rng := RandomNumberGenerator.new()
const DEFAULT_SEED := 20261018

## 验收用：打开后记录事件窗口（生产默认关闭，避免无界增长）。
var capture_event_log := false
var _event_log: Array[Dictionary] = []


func _ready() -> void:
	_rng.seed = DEFAULT_SEED
	# 子节点的 _ready 早于父节点（Art），而材质 duplicate 发生在 Art._ready 里。
	# 等两帧再登记，否则拿到的还是未 duplicate 的资产材质（改了会污染所有实例）。
	#
	# ⚠️ 等帧期间必须**自己能活下来**：`await get_tree().process_frame` 里的
	#    `get_tree()` 是每帧现取的 —— 节点一旦被摘出场景树就返回 null，
	#    随后 `null.process_frame` 直接抛错并**中断协程**（登记永远不执行）。
	#    实测踩到的正是这条：带「进行中行动」的存档冷启动时，先加载 99F 主场景
	#    （本节点 _ready 开始等帧），紧接着 `TowerDescent3D._ready` 判断要转场到
	#    独立副本、`call_deferred(change_scene_to_file)`，主场景在同一帧内被
	#    `change_scene` 摘出根节点 ⇒ 报
	#    `Parameter "data.tree" is null` + `Invalid access to property ... 'process_frame'`。
	#    所以：先把 SceneTree 抓成局部变量，每等一帧再确认自己还挂在树上。
	var tree := get_tree()
	if tree == null:
		return
	for _frame in 2:
		await tree.process_frame
		if not is_inside_tree():
			# 整棵场景已被换掉，本节点随它一起销毁，没有素材可登记。
			return
	_register_targets()


func _process(delta: float) -> void:
	if _missing.size() > 0:
		return
	var enabled := true
	var starting := false
	var glow := _find_glow_owner()
	if glow != null:
		var snapshot: Dictionary = glow.get_presentation_snapshot()
		enabled = bool(snapshot.get("presentation_lighting_enabled", true))
		starting = bool(snapshot.get("presentation_starting", false))
	var active := enabled and not starting
	if not active:
		# 关灯 / 启动序列期间一律不写，交还给 BaseFixtureGlow3D 独占。
		# 例外：self_owned 的面（显示器屏幕）不在它的受控表里，必须自己熄灭，
		# 否则「关灯后二楼屏幕还亮着」—— 正是 BaseFixtureGlow3D 头注释里那条老毛病的翻版。
		_set_self_owned_emission(false)
		if _was_active:
			_was_active = false
			_needs_resync = true
			_reset_channels()
		return
	_set_self_owned_emission(true)
	if _needs_resync:
		_resync_baseline()
		_needs_resync = false
	_was_active = true
	_advance(delta)
	_apply()


## 验收用：不依赖真实帧率，按固定步长推进模拟。
func advance_for_test(delta: float) -> void:
	_clock += delta
	for key in _channels:
		_update_channel(_channels[key] as Channel)
	_apply()


## 真渲染验收用：把时钟与随机源一起复位，让「第二次推进」逐位重现第一次。
## 不带这个，规划出的「极值时刻」在拍摄时会落到别的相位上（实测拍到同一张图两次）。
func reset_for_test(seed_value: int = DEFAULT_SEED) -> void:
	_rng.seed = seed_value
	_clock = 0.0
	_events_active = 0
	_last_event_start = -1000.0
	_reserved_start = -1000.0
	_needs_resync = false
	_was_active = true
	_event_log.clear()
	for key in _channels:
		var channel := _channels[key] as Channel
		channel.event_start = -1.0
		channel.event_end = -1.0
		channel.round_start = -100.0
		for slot in channel.slots:
			slot.factor = 1.0
	_arm_initial_schedule()
	# 复位后必须**立刻把波形算一遍**：屏幕（loft_pc）的常态倍率是 0，
	# 若只把 factor 置 1 就 _apply，屏幕会以「满亮」停在 t=0，
	# 于是「静息帧」拍到的是亮屏（实测两张图一模一样）。
	for key in _channels:
		_update_channel(_channels[key] as Channel)
	_set_self_owned_emission(true)
	_apply()


## 真渲染验收用：直接压一个倍率（梯度实验），不推进时钟。
func force_factor(channel_key: String, factor: float) -> void:
	var channel := _channels.get(channel_key) as Channel
	if channel == null:
		return
	_set_self_owned_emission(true)
	for slot in channel.slots:
		slot.factor = factor
	_apply()


func get_event_log() -> Array[Dictionary]:
	return _event_log


func get_channel_keys() -> Array:
	return _channels.keys()


func get_slot_count() -> int:
	return _slot_count


func get_missing_targets() -> Array[String]:
	return _missing


func get_factor(channel_key: String) -> float:
	var channel := _channels.get(channel_key) as Channel
	if channel == null or channel.slots.is_empty():
		return 1.0
	return channel.slots[0].factor


func get_factors(channel_key: String) -> Array[float]:
	var out: Array[float] = []
	var channel := _channels.get(channel_key) as Channel
	if channel == null:
		return out
	for slot in channel.slots:
		out.append(slot.factor)
	return out



func get_managed_energies() -> Array[float]:
	var out: Array[float] = []
	for key in _channels:
		var channel := _channels[key] as Channel
		for slot in channel.slots:
			if slot.self_owned:
				continue
			if slot.material == null or not is_instance_valid(slot.material):
				out.append(-1.0)
			else:
				out.append(slot.material.emission_energy_multiplier)
	return out


func get_managed_base_energies() -> Array[float]:
	var out: Array[float] = []
	for key in _channels:
		var channel := _channels[key] as Channel
		for slot in channel.slots:
			if slot.self_owned:
				continue
			out.append(slot.base_energy)
	return out


## self_owned 的屏幕面在关灯态必须 emission_enabled=false（否则关灯后屏幕还亮）。
func are_self_owned_lit() -> bool:
	for key in _channels:
		var channel := _channels[key] as Channel
		for slot in channel.slots:
			if not slot.self_owned:
				continue
			if slot.material == null or not is_instance_valid(slot.material):
				continue
			if slot.material.emission_enabled:
				return true
	return false



func _register_targets() -> void:
	var host := get_parent()
	for entry in TARGETS:
		var channel_key := str(entry.channel)
		var mesh_name := str(entry.mesh)
		var node := _find_node_by_name(host, str(entry.node))
		if node == null:
			_missing.append(str(entry.node))
			push_error("BASE_LAMP_TARGET_MISSING: 节点 %s" % entry.node)
			continue
		var mesh_instance := _find_mesh(node, mesh_name)
		if mesh_instance == null:
			_missing.append(mesh_name)
			push_error("BASE_LAMP_TARGET_MISSING: 网格 %s（父 %s）" % [mesh_name, entry.node])
			continue
		var surface := int(entry.surface)
		var material := mesh_instance.get_surface_override_material(surface) as BaseMaterial3D
		if material == null:
			material = mesh_instance.get_active_material(surface) as BaseMaterial3D
		if material == null:
			_missing.append(mesh_name)
			push_error("BASE_LAMP_TARGET_MISSING: 网格 %s 无材质" % mesh_name)
			continue
		var slot := Slot.new()
		slot.material = material
		slot.self_owned = bool(entry.get("self_owned", false))
		if slot.self_owned:
			# 这面原本不自发光（显示器屏幕在 03_清漆反光 面上，是靠反光显色的）。
			# 必须 duplicate：直接改资产材质会污染所有实例（同一份 GLB 材质被多台机器共用）。
			var owned := material.duplicate() as BaseMaterial3D
			owned.resource_name = material.resource_name + "_基地屏幕动态"
			owned.emission_enabled = true
			# 不能用色盘乘算：这个面的 UV 落在色盘的极暗格（实测采样 rgb≈(0,0,0)），
			# 乘出来等于没发光（第一版就这样，1.35 能量下差异只有 494 像素）。
			# 直接给屏幕蓝 + ADD 算子。
			# ⚠️ 必须显式改回 ADD：材质原本是 EMISSION_OP_MULTIPLY（乘色盘），
			#    清空贴图后 MULTIPLY 会把自发光乘成 0 —— 实测差异直接归零。
			owned.emission_texture = null
			owned.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
			owned.emission = SCREEN_COLOR
			owned.emission_energy_multiplier = SCREEN_ENERGY
			mesh_instance.set_surface_override_material(surface, owned)
			slot.material = owned
			slot.base_energy = SCREEN_ENERGY
		else:
			slot.base_energy = material.emission_energy_multiplier
		if bool(entry.get("spill", false)):
			var spill := _find_spill(node)
			if spill != null:
				slot.spill = spill
				slot.spill_base = spill.light_energy
		var channel := _channels.get(channel_key) as Channel
		if channel == null:
			channel = Channel.new()
			channel.key = channel_key
			_channels[channel_key] = channel
		channel.slots.append(slot)
		_slot_count += 1
	_arm_initial_schedule()


## 起始时刻彼此错开：绝不出现「一进场景六个一起动」。
func _arm_initial_schedule() -> void:
	_arm("neon", 7.5)
	_arm("vending", 13.5)
	_arm("emergency", 10.0)
	_arm("loft_pc", 17.0)
	var status := _channels.get("status") as Channel
	if status != null:
		status.next_at = 1.8
		status.round_start = -100.0


func _arm(channel_key: String, delay: float) -> void:
	var channel := _channels.get(channel_key) as Channel
	if channel != null:
		channel.next_at = delay
		if channel_key == "neon":
			_reserved_start = delay


func _resync_baseline() -> void:
	for key in _channels:
		var channel := _channels[key] as Channel
		for slot in channel.slots:
			if slot.material == null or not is_instance_valid(slot.material):
				continue
			slot.base_energy = slot.material.emission_energy_multiplier
			slot.factor = 1.0
			if slot.spill != null and is_instance_valid(slot.spill):
				slot.spill_base = slot.spill.light_energy


func _reset_channels() -> void:
	_events_active = 0
	for key in _channels:
		var channel := _channels[key] as Channel
		channel.event_start = -1.0
		channel.event_end = -1.0
		for slot in channel.slots:
			slot.factor = 1.0
	# 重新开始时再一次错开，避免「关灯再开」瞬间齐动。
	_arm_initial_schedule()


func _advance(delta: float) -> void:
	_clock += delta
	for key in _channels:
		_update_channel(_channels[key] as Channel)


func _apply() -> void:
	for key in _channels:
		var channel := _channels[key] as Channel
		for slot in channel.slots:
			if slot.material == null or not is_instance_valid(slot.material):
				continue
			slot.material.emission_energy_multiplier = slot.base_energy * slot.factor
			if slot.spill != null and is_instance_valid(slot.spill):
				slot.spill.light_energy = slot.spill_base * slot.factor


## self_owned 的面不在 BaseFixtureGlow3D 的受控表里，开关状态要自己跟。
func _set_self_owned_emission(enabled: bool) -> void:
	for key in _channels:
		var channel := _channels[key] as Channel
		for slot in channel.slots:
			if not slot.self_owned:
				continue
			if slot.material == null or not is_instance_valid(slot.material):
				continue
			if slot.material.emission_enabled != enabled:
				slot.material.emission_enabled = enabled


func _update_channel(channel: Channel) -> void:
	match channel.key:
		"neon":
			_update_neon(channel)
		"lamp":
			_update_lamp(channel)
		"vending":
			_update_vending(channel)
		"status":
			_update_status(channel)
		"emergency":
			_update_emergency(channel)
		"door":
			_update_door(channel)
		"loft_pc":
			_update_loft_pc(channel)


## A：事件内 3~4 次轻微抖动，用 smoothstep 抹圆边沿（方波会读成断电）。
func _update_neon(channel: Channel) -> void:
	var slot := channel.slots[0]
	if not channel.is_event_running():
		slot.factor = 1.0
		if _clock >= channel.next_at and _take_event_slot(true):
			channel.event_start = _clock
			channel.event_end = _clock + _rng.randf_range(NEON_EVENT_MIN, NEON_EVENT_MAX)
			channel.event_frequency = float(_rng.randi_range(3, 4))
			# 下一次「起始」间隔必须落在 8~15s —— 不能在事件结束时再加间隔，
			# 否则 start-to-start 会变成「间隔 + 事件时长」（实测漏到 15.82s）。
			channel.next_at = _clock + _rng.randf_range(NEON_INTERVAL_MIN, NEON_INTERVAL_MAX)
			_reserved_start = channel.next_at
			_log_event("neon", "start", channel.event_start)
		return
	var span := maxf(channel.event_end - channel.event_start, 0.001)
	var t := (_clock - channel.event_start) / span
	if t >= 1.0:
		_finish_event(channel, "neon")
		slot.factor = 1.0
		return
	var envelope := sin(PI * t)
	var ripple := 0.5 - 0.5 * cos(TAU * channel.event_frequency * t)
	slot.factor = 1.0 - NEON_DIP * envelope * ripple


## B：双频正弦，向下沉再回满。灯罩呼吸必须同步乘到补光上，否则「罩子在呼吸、桌面不动」。
## 两个分量都取 (0.5+0.5·sin)、再取负 ⇒ 值域恒为 [0.87, 1.00]：
## 永远不越过原亮度，读作「在呼吸」而不是「越呼吸越亮」。
func _update_lamp(channel: Channel) -> void:
	var slot := channel.slots[0]
	slot.factor = (
		1.0
		- LAMP_DIP * (0.5 + 0.5 * sin(TAU * _clock / LAMP_PERIOD))
		- LAMP_BREATH * (0.5 + 0.5 * sin(TAU * _clock / 2.1 + 1.3))
	)


## C：整屏眯眼。眼睛是几何浮雕（UV/材质与屏面完全相同），做不了局部眨眼，
## 只能整屏压暗一档 —— 浮雕眼睛相对更不显眼，读作「眯了一下」。
func _update_vending(channel: Channel) -> void:
	var slot := channel.slots[0]
	var idle := 1.0 + VENDING_IDLE_DEPTH * sin(TAU * _clock / VENDING_IDLE_PERIOD)
	if not channel.is_event_running():
		slot.factor = idle
		if _clock >= channel.next_at and _take_event_slot():
			channel.event_start = _clock
			channel.event_end = _clock + VENDING_BLINK_DURATION
			_log_event("vending", "start", channel.event_start)
		return
	var span := maxf(channel.event_end - channel.event_start, 0.001)
	var t := (_clock - channel.event_start) / span
	if t >= 1.0:
		_finish_event(channel, "vending")
		slot.factor = idle
		channel.next_at = _clock + _rng.randf_range(VENDING_BLINK_MIN, VENDING_BLINK_MAX)
		return
	# 快落慢起：闭眼要快，睁开可以稍缓。
	var close := smoothstep(0.0, 0.28, t)
	var open := 1.0 - smoothstep(0.45, 1.0, t)
	slot.factor = idle * (1.0 - VENDING_BLINK_DIPTH * close * open)


## D：三灯自检流水。共用一个时钟，相位差 STATUS_STAGGER ⇒ 读作一台机器在自检，
## 而不是三个灯各自闪。不计入事件配额（背景节拍）。
func _update_status(channel: Channel) -> void:
	if _clock >= channel.next_at:
		channel.round_start = _clock
		channel.next_at = (
			_clock + STATUS_ROUND_TOTAL + _rng.randf_range(STATUS_GAP_MIN, STATUS_GAP_MAX)
		)
	var local := _clock - channel.round_start
	for index in range(channel.slots.size()):
		var t := local - float(index) * STATUS_STAGGER
		var rise := smoothstep(0.0, 0.12, t)
		var fall := 1.0 - smoothstep(STATUS_ON - 0.12, STATUS_ON, t)
		var on := rise * fall
		channel.slots[index].factor = lerpf(STATUS_DIM, STATUS_PEAK, on)


## E1：双跳。「连抽两下」是故障灯的典型读法，比单次闪可信，也比方波硬灭柔和。
func _update_emergency(channel: Channel) -> void:
	var slot := channel.slots[0]
	if not channel.is_event_running():
		slot.factor = 1.0
		if _clock >= channel.next_at and _take_event_slot():
			channel.event_start = _clock
			channel.event_end = _clock + _rng.randf_range(
				EMERGENCY_EVENT_MIN, EMERGENCY_EVENT_MAX
			)
			_log_event("emergency", "start", channel.event_start)
		return
	if _clock >= channel.event_end:
		_finish_event(channel, "emergency")
		slot.factor = 1.0
		channel.next_at = _clock + _rng.randf_range(
			EMERGENCY_INTERVAL_MIN, EMERGENCY_INTERVAL_MAX
		)
		return
	slot.factor = _double_tap(_clock - channel.event_start)


func _double_tap(elapsed: float) -> float:
	# 0.00 亮 → 0.11 暗 → 0.21 亮 → 0.31 暗 → 0.41 亮，之后保持在亮。
	var keys := [0.00, 0.11, 0.21, 0.31, 0.41]
	var values := [1.0, EMERGENCY_LOW, 1.0, EMERGENCY_LOW, 1.0]
	if elapsed <= 0.0:
		return 1.0
	for index in range(1, keys.size()):
		if elapsed < float(keys[index]):
			var span := float(keys[index]) - float(keys[index - 1])
			var k := smoothstep(0.0, 1.0, (elapsed - float(keys[index - 1])) / span)
			return lerpf(float(values[index - 1]), float(values[index]), k)
	return 1.0


## E2：慢呼吸，与 E1 的故障跳读区分开；相位固定偏移，峰值不与 E1 事件同步。
func _update_door(channel: Channel) -> void:
	var slot := channel.slots[0]
	slot.factor = (
		1.0
		+ DOOR_LIFT * sin(TAU * _clock / DOOR_PERIOD + DOOR_PHASE)
		+ DOOR_BREATH * sin(TAU * _clock / 3.3 + 0.7)
	)


## F：常态不发光（= 原美术的深蓝暗屏），偶发快速频闪。
## 事件内频率每次重抽（8~14Hz），用 sin 包络起落，避免两端突然跳变。
func _update_loft_pc(channel: Channel) -> void:
	var slot := channel.slots[0]
	# 常态 0：屏幕回到改动前的样子（不发光）。CRT 的微弱起伏放在事件内的基线里，
	# 否则「暗屏还在呼吸」是矛盾的。
	var idle := 0.0
	if not channel.is_event_running():
		slot.factor = idle
		if _clock >= channel.next_at and _take_event_slot():
			channel.event_start = _clock
			channel.event_end = (
				_clock + _rng.randf_range(PC_EVENT_DURATION_MIN, PC_EVENT_DURATION_MAX)
			)
			channel.event_frequency = _rng.randf_range(8.0, 14.0)
			_log_event("loft_pc", "start", channel.event_start)
		return
	var span := maxf(channel.event_end - channel.event_start, 0.001)
	var elapsed := _clock - channel.event_start
	var t := elapsed / span
	if t >= 1.0:
		_finish_event(channel, "loft_pc")
		slot.factor = idle
		channel.next_at = _clock + _rng.randf_range(PC_EVENT_MIN, PC_EVENT_MAX)
		return
	var envelope := sin(PI * t)
	# ⚠️ 频率必须乘**秒**，不能乘归一化到 0~1 的 t。
	# 第一版写成 `sin(TAU * f * t)`，等于把 11Hz 的周期压缩进整段事件，
	# 实际频率变成 f / 事件时长 ≈ 40Hz —— 既不是设计值，也进了光敏风险区。
	# envelope 只乘一次（第一版 jitter 里乘了、外面又乘一次 ⇒ envelope²，
	# 事件两端被压平，0.27s 的窗口里凑不出一个完整周期，频闪根本起不来）。
	var jitter := PC_EVENT_SWING * sin(TAU * channel.event_frequency * elapsed)
	# 基线抬到 PC_EVENT_LEVEL：事件里屏幕「亮起来抖」，而不是「从暗屏往下抖」。
	slot.factor = clampf(
		PC_EVENT_LEVEL + jitter * envelope, PC_LOW_CLAMP, PC_HIGH_CLAMP
	)


## 霓虹是唯一有明确节拍指标的对象（业主：8~15 秒一次），所以给它「预约」特权：
## 它的下一次起始时刻一确定，其余通道在 [预约−闸门, 预约+闸门] 内一律让路。
## 否则实测有 24% 的霓虹事件被闸门顺延到 15s 以上 —— 那是在改业主给的节拍。
var _reserved_start := -1000.0


func _take_event_slot(is_priority := false) -> bool:
	if _events_active >= MAX_CONCURRENT_EVENTS:
		return false
	if not is_priority and absf(_clock - _reserved_start) < MIN_EVENT_GAP_SECONDS:
		return false
	if _clock - _last_event_start < MIN_EVENT_GAP_SECONDS:
		return false
	_events_active += 1
	_last_event_start = _clock
	return true


func _finish_event(channel: Channel, key: String) -> void:
	channel.event_start = -1.0
	channel.event_end = -1.0
	_events_active = maxi(_events_active - 1, 0)
	_log_event(key, "end", _clock)


func _log_event(key: String, phase: String, at: float) -> void:
	if not capture_event_log:
		return
	_event_log.append({"channel": key, "phase": phase, "at": at})
	if _event_log.size() > 4000:
		_event_log = _event_log.slice(_event_log.size() - 2000)


func _find_glow_owner() -> Node:
	var cursor := get_parent()
	while cursor != null:
		if cursor.has_method("get_presentation_snapshot"):
			return cursor
		cursor = cursor.get_parent()
	return null


func _find_node_by_name(root_node: Node, needle: String) -> Node:
	if root_node == null:
		return null
	# 必须做「包含」匹配：场景里的节点名带 `_资产包` 后缀
	# （`72_SUPPLY24H自动补给机_资产包`），find_child 只认精确名/通配符，会全部漏掉。
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if str(node.name).findn(needle) >= 0:
			return node
		for child in node.get_children():
			stack.append(child)
	return null


func _find_mesh(root_node: Node, mesh_name: String) -> MeshInstance3D:
	if root_node is MeshInstance3D and str(root_node.name) == mesh_name:
		return root_node as MeshInstance3D
	return root_node.find_child(mesh_name, true, false) as MeshInstance3D


func _find_spill(root_node: Node) -> OmniLight3D:
	return root_node.find_child("PaletteLightSpill", true, false) as OmniLight3D
