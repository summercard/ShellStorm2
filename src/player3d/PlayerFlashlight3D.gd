class_name PlayerFlashlight3D
extends Node3D
## 与玩法视野完全解耦的真实玩家灯光。
## 前向环境主灯投影；近身溢光与角色柔光不投影。
## 三盏随身灯都不会对角色自身投影：环境灯只照 layer 1，角色柔光不启用阴影。
## 角色网格本身仍可被太阳和房间灯（layer 1|2）投射到环境上。

signal light_enabled_changed(enabled: bool)
signal charge_changed(ratio: float, tier: int)
signal reveal_multiplier_changed(multiplier: float)
signal state_changed(state_id: String, context: Dictionary)

const ENVIRONMENT_RENDER_LAYER := GameDesignConfig.RENDER_LAYER_WORLD
const AVATAR_RENDER_LAYER := GameDesignConfig.RENDER_LAYER_PLAYER

const FLASHLIGHT_CHARGE_DRAIN_PER_SECOND := 1.0 / 300.0  # 基础档满电 300s (5 分钟)
const FLASHLIGHT_DRAIN_STEP := 0.02  # 每"格"消耗 2% 电量(基础档 6 秒一格)
const FLASHLIGHT_MODULE_PROFILES := {
	"basic":     {"drain": 1.00, "reveal": 1.00, "range": 1.00, "energy": 1.00}, # 300s
	"advanced":  {"drain": 5.0 / 7.0, "reveal": 1.20, "range": 1.20, "energy": 1.10}, # 420s
	"efficient": {"drain": 0.50, "reveal": 0.85, "range": 0.85, "energy": 0.90}, # 600s
}
const FLASHLIGHT_REVEAL_BOOST_BASE := 1.7  # 开启(on 且未耗尽)时基础倍率
const FLASHLIGHT_TIER_THRESHOLDS := [0.60, 0.30, 0.10, 0.01]

@export_group("Input")
@export var toggle_action := "toggle_flashlight"
@export var start_enabled := false

@export_group("Beam")
@export var beam_color := Color(0.86, 0.96, 0.93)
@export_range(0.0, 32.0, 0.1) var beam_energy := 7.2
@export_range(4.0, 40.0, 0.5) var beam_range := 25.0
@export_range(20.0, 110.0, 1.0) var beam_angle_degrees := 66.0
@export_range(0.1, 2.0, 0.05) var beam_attenuation := 0.48
@export_range(0.1, 4.0, 0.05) var beam_edge_attenuation := 1.15
@export_group("Beam Shadow")
# Compatibility 渲染器下，远处墙面被聚光以小角度照射时，默认阴影偏移会
# 出现规则横纹（shadow acne）。只调整阴影采样，不改变能量、范围或灯光层。
@export_range(0.0, 1.0, 0.01) var beam_shadow_bias := 0.18
@export_range(0.0, 8.0, 0.1) var beam_shadow_normal_bias := 1.6
@export_range(0.1, 4.0, 0.1) var beam_shadow_blur := 1.2

@export_group("Mount")
@export_range(0.5, 4.0, 0.05) var mount_height := 1.15
@export_range(-1.0, 2.0, 0.05) var mount_forward := -0.01
@export_range(1.0, 24.0, 0.25) var target_forward := 11.0
@export_range(0.0, 2.0, 0.05) var target_height := 0.38

@export_group("Environment Spill")
@export var spill_color := Color(0.68, 0.88, 0.84)
@export_range(0.0, 8.0, 0.05) var spill_energy := 0.7
@export_range(1.0, 10.0, 0.25) var spill_range := 4.8
@export_range(0.1, 4.0, 0.05) var spill_attenuation := 2.0
@export_range(0.2, 2.0, 0.05) var spill_height := 0.65

@export_group("Avatar Front Fill")
@export var front_fill_color := Color(0.70, 0.90, 0.86)
@export_range(0.0, 16.0, 0.05) var front_fill_energy := 2.8
@export_range(1.0, 8.0, 0.25) var front_fill_range := 4.0
@export_range(20.0, 110.0, 1.0) var front_fill_angle_degrees := 74.0
@export_range(0.1, 3.0, 0.05) var front_fill_attenuation := 1.15
@export_range(0.2, 3.0, 0.05) var front_fill_forward := 1.45
@export_range(0.5, 3.0, 0.05) var front_fill_height := 1.22
@export_range(0.2, 2.5, 0.05) var avatar_target_height := 0.82

var _player: Player3D
## 唯一对外开关：把三盏灯（主聚光 / 环境溢光 / 角色正面柔光）打成一组，
## F 键只切这一个节点的 visible，三盏灯一并显隐，不会出现"按掉一盏还在"的情况。
var _light_kit: Node3D
var _beam: SpotLight3D
var _spill: OmniLight3D
var _front_fill: SpotLight3D
var _enabled := false
var _charge_ratio := 1.0
var _module_id := "basic"
var _drain_multiplier := 1.0
var _reveal_multiplier := 1.0
var _range_multiplier := 1.0
var _energy_multiplier := 1.0
var _in_facility := false
var _tier := 0
var _drain_accumulator := 0.0
# 关灯时除了 visible=false 还要把 light_energy 临时归零，
# 否则 DirectionalLight3D 太阳 / Ambient / 房间灯的 cull_mask 全开仍会照亮角色层，
# 视觉上会觉得"还有一盏"；开启时用 _beam_energy_active 恢复，保证 +30% 调参不丢。
var _beam_energy_active := 0.0
var _spill_energy_active := 0.0
var _front_fill_energy_active := 0.0


func _ready() -> void:
	_player = get_parent() as Player3D
	_enabled = start_enabled
	_build_lights()
	_apply_configuration()
	force_sync()
	# 关闭时三盏灯均不可见，不需要每帧重写三组全局变换；开启瞬间先同步，
	# 开启期间再恢复逐帧跟随，因此按F后的方向与移动表现不变。
	set_process(_enabled)
	set_physics_process(true)
	_tier = _compute_tier(_charge_ratio)
	charge_changed.emit(_charge_ratio, _tier)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(toggle_action):
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if _player == null or _player.input_locked or _player.current_hp <= 0:
		return
	toggle_light()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	force_sync()


func force_sync() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_parent() as Player3D
	if _player == null or _beam == null or _spill == null or _front_fill == null:
		return
	var aim := _player.aim_direction
	aim.y = 0.0
	if aim.length_squared() <= 0.0001:
		aim = Vector3.FORWARD
	aim = aim.normalized()
	_beam.global_position = _player.global_position + Vector3.UP * mount_height + aim * mount_forward
	var beam_target := _player.global_position + aim * target_forward + Vector3.UP * target_height
	_beam.look_at(beam_target, Vector3.UP)
	_spill.global_position = _player.global_position + Vector3.UP * spill_height - aim * 0.12
	_front_fill.global_position = _player.global_position + aim * front_fill_forward + Vector3.UP * front_fill_height
	_front_fill.look_at(_player.global_position + Vector3.UP * avatar_target_height, Vector3.UP)


func set_light_enabled(enabled: bool) -> void:
	# 拒绝打开：如果电量耗尽，吞掉请求并发 consume_refused
	if enabled and not _enabled and _charge_ratio <= 0.0:
		state_changed.emit("consume_refused", {"reason": "depleted"})
		return
	if _enabled == enabled:
		return
	_enabled = enabled
	# 普通开关必须保留尚未累计到 2% 一格的实际耗电。
	# 否则用户只要在每次扣格前关灯再开，就会把这段耗电退回，
	# 剩余时间也会错误跳回满电。累计值只在真正补电/进入基地时清零。
	set_process(enabled)
	if enabled:
		force_sync()
	# 通过 kit 节点统一显隐：把三盏灯打包，F 一次切换整组，
	# 后续再加灯只要挂到 _light_kit 下就会自动跟随。
	if _light_kit != null:
		_light_kit.visible = enabled
	# 兜底：再单独写一次 visible，防止未来重构把灯挪出 kit 时漏掉。
	if _beam != null:
		_beam.visible = enabled
	if _spill != null:
		_spill.visible = enabled
	if _front_fill != null:
		_front_fill.visible = enabled
	# 关灯时把所有灯的 light_energy 全部归零。即便父节点的 visible 由于
	# top_level=true 在某些渲染路径上没传播到子节点，energy=0 也保证灯具
	# 不再发出任何光线；开灯时恢复 _apply_configuration 写入的能量。
	var target_energy := beam_energy * _energy_multiplier if enabled else 0.0
	var spill_target := spill_energy * _energy_multiplier if enabled else 0.0
	var fill_target := front_fill_energy * _energy_multiplier if enabled else 0.0
	if _beam != null:
		_beam.light_energy = target_energy
	if _spill != null:
		_spill.light_energy = spill_target
	if _front_fill != null:
		_front_fill.light_energy = fill_target
	# 缓存"开灯时的活跃能量"，后续 apply_configuration / toggle 可读此值
# 防止 _apply_configuration 在能量为 0 的瞬间又被覆盖写回 export 值。
	_beam_energy_active = beam_energy
	_spill_energy_active = spill_energy
	_front_fill_energy_active = front_fill_energy
	light_enabled_changed.emit(enabled)
	_notify_illumination_sensors()


func toggle_light() -> bool:
	set_light_enabled(not _enabled)
	return _enabled


## 每物理 tick 由 Player3D 推送 facility 状态。
## 基地内不消耗、且电量自动补满。基地外:每秒累计实际耗电量,
## 每达到 2% ("一格") 触发一次 consume_charge。
func _physics_process(delta: float) -> void:
	if _in_facility:
		if _charge_ratio < 1.0:
			set_charge_ratio(1.0)
		_drain_accumulator = 0.0
		return
	if _enabled and _charge_ratio > 0.0:
		_drain_accumulator += FLASHLIGHT_CHARGE_DRAIN_PER_SECOND * _drain_multiplier * delta
		while _drain_accumulator >= FLASHLIGHT_DRAIN_STEP and _charge_ratio > 0.0:
			_drain_accumulator -= FLASHLIGHT_DRAIN_STEP
			consume_charge(FLASHLIGHT_DRAIN_STEP)


## 递减电量。跨 0 时自动关闭灯具并发 depleted。
## 非耗尽分支每扣一格都广播 charge_changed,使 HUD 百分比 / 进度条随每个 2% 步进实时刷新。
func consume_charge(amount: float) -> void:
	if amount <= 0.0:
		return
	var was_enabled := _enabled
	var new_ratio := _charge_ratio - amount
	if new_ratio <= 0.0:
		_charge_ratio = 0.0
		_tier = _compute_tier(_charge_ratio)
		charge_changed.emit(_charge_ratio, _tier)
		if was_enabled:
			_enabled = false
			set_process(false)
			if _light_kit != null:
				_light_kit.visible = false
			if _beam != null:
				_beam.visible = false
				_beam.light_energy = 0.0
			if _spill != null:
				_spill.visible = false
				_spill.light_energy = 0.0
			if _front_fill != null:
				_front_fill.visible = false
				_front_fill.light_energy = 0.0
			state_changed.emit("depleted", {})
			light_enabled_changed.emit(false)
			_notify_illumination_sensors()
		return
	_charge_ratio = new_ratio
	_tier = _compute_tier(_charge_ratio)
	# 每个 2% 步进都广播,避免 HUD 百分比 / 进度条只在跨 tier 时跳一次。
	charge_changed.emit(_charge_ratio, _tier)


func set_charge_ratio(ratio: float) -> void:
	var clamped := clampf(ratio, 0.0, 1.0)
	if is_equal_approx(_charge_ratio, clamped):
		return
	_charge_ratio = clamped
	_tier = _compute_tier(_charge_ratio)
	# 电量实际变化即广播:基地补满、存档恢复、测试设置同一 tier 内调整都要同步 HUD。
	charge_changed.emit(_charge_ratio, _tier)
	if _charge_ratio <= 0.0 and _enabled:
		set_light_enabled(false)


## 加值返回 true。已满返回 false(quick-slot 据此决定是否消耗道具)。
func restore_charge(amount: float) -> bool:
	if amount <= 0.0:
		return false
	if _charge_ratio >= 1.0:
		return false
	var new_ratio := clampf(_charge_ratio + amount, 0.0, 1.0)
	var old_tier := _tier
	_charge_ratio = new_ratio
	_tier = _compute_tier(_charge_ratio)
	_drain_accumulator = 0.0  # 补电后清零,避免补到 100% 立刻又被扣一格
	charge_changed.emit(_charge_ratio, _tier)
	state_changed.emit("restored", {"amount": amount})
	return true


## 切换模块。基地外被拒(false)，基地内接受并更新 drain/reveal 倍率。
func set_module(module_id: String) -> bool:
	if not FLASHLIGHT_MODULE_PROFILES.has(module_id):
		return false
	if not _in_facility:
		return false
	_apply_module(module_id, true)
	return true


## 仅供开局/续局从长期装备状态还原；不属于玩家在塔内换装。
func restore_module(module_id: String) -> bool:
	if not FLASHLIGHT_MODULE_PROFILES.has(module_id):
		return false
	_apply_module(module_id, false)
	return true


func _apply_module(module_id: String, announce: bool) -> void:
	_module_id = module_id
	var profile: Dictionary = FLASHLIGHT_MODULE_PROFILES[module_id]
	_drain_multiplier = float(profile.get("drain", 1.0))
	_reveal_multiplier = float(profile.get("reveal", 1.0))
	_range_multiplier = float(profile.get("range", 1.0))
	_energy_multiplier = float(profile.get("energy", 1.0))
	_apply_configuration()
	if announce:
		state_changed.emit("module_swapped", {"module_id": module_id})
		reveal_multiplier_changed.emit(_reveal_multiplier)


func set_in_facility(flag: bool) -> void:
	_in_facility = flag
	if flag and _charge_ratio < 1.0:
		set_charge_ratio(1.0)
		_drain_accumulator = 0.0
		state_changed.emit("facility_recharged", {})


func get_charge_ratio() -> float:
	return _charge_ratio


func get_tier() -> int:
	return _tier


func get_drain_multiplier() -> float:
	return _drain_multiplier


func get_reveal_multiplier() -> float:
	return _reveal_multiplier


func get_range_multiplier() -> float:
	return _range_multiplier


func is_depleted() -> bool:
	return _charge_ratio <= 0.0


func get_module_id() -> String:
	return _module_id


func is_in_facility() -> bool:
	return _in_facility


## 当前 drain 倍率下剩余时间(秒)。关闭、满电、耗尽时返回特殊值。
## - _enabled == false: 0(关闭时不消耗,但保留语义给 HUD 显示"OFF · --%")
## - _charge_ratio <= 0.0: 0
## - _in_facility == true: INF(基地内不消耗)
## - 其他: 把"已落到 _charge_ratio 的离散电量"与"物理帧间累计、尚未跨档的 _drain_accumulator"
##   一起除以每秒实际耗电率,得到真正的剩余秒数。这样 _charge_ratio 每约 6 秒才掉一格,
##   但剩余秒数会随 _drain_accumulator 在帧间连续递减,HUD 才能逐秒倒计时。
func get_estimated_remaining_seconds() -> float:
	if _in_facility:
		return INF
	if _charge_ratio <= 0.0:
		return 0.0
	if not _enabled:
		return 0.0
	var per_second := FLASHLIGHT_CHARGE_DRAIN_PER_SECOND * _drain_multiplier
	if per_second <= 0.0:
		return INF
	return maxf(_charge_ratio - _drain_accumulator, 0.0) / per_second


## 0=高、1=中、2=低、3=临界、4=耗尽。
func _compute_tier(ratio: float) -> int:
	for index in FLASHLIGHT_TIER_THRESHOLDS.size():
		if ratio >= FLASHLIGHT_TIER_THRESHOLDS[index]:
			return index
	return FLASHLIGHT_TIER_THRESHOLDS.size()


func apply_configuration() -> void:
	## 允许运行时调参面板或主题预设修改导出值后立即应用，不需要重建节点。
	_apply_configuration()
	force_sync()


func is_light_enabled() -> bool:
	return _enabled


func get_snapshot() -> Dictionary:
	var aim_alignment := 0.0
	if _player != null and _beam != null:
		var aim := _player.aim_direction.normalized()
		var beam_forward := -_beam.global_basis.z.normalized()
		aim_alignment = Vector2(aim.x, aim.z).normalized().dot(Vector2(beam_forward.x, beam_forward.z).normalized())
	return {
		"enabled": _enabled,
		"start_enabled": start_enabled,
		"manual_toggle": true,
		"toggle_action": toggle_action,
		"light_kit_path": "FlashlightKit" if _light_kit != null else "",
		"light_kit_visible": _light_kit.visible if _light_kit != null else _enabled,
		"real_light_count": 3,
		"spotlight_count": 2,
		"spill_light_count": 1,
		"front_fill_light_count": 1,
		"shadow_light_count": 1,
		"shadow_light_disabled_for_avatar": true,
		"beam_energy": beam_energy,
		"beam_range": beam_range,
		"beam_angle_degrees": beam_angle_degrees,
		"beam_shadow_bias": beam_shadow_bias,
		"beam_shadow_normal_bias": beam_shadow_normal_bias,
		"beam_shadow_blur": beam_shadow_blur,
		"spill_energy": spill_energy,
		"spill_range": spill_range,
		"front_fill_energy": front_fill_energy,
		"environment_light_cull_mask": ENVIRONMENT_RENDER_LAYER,
		"environment_shadow_caster_mask": GameDesignConfig.SHADOW_MASK_WORLD_ONLY,
		"avatar_light_cull_mask": AVATAR_RENDER_LAYER,
		"environment_spill_affects_avatar": false,
		"front_fill_affects_avatar": true,
		"aim_alignment": aim_alignment,
		"gameplay_light_dependent": false,
		"configurable": true,
		"charge_ratio": _charge_ratio,
		"drain_multiplier": _drain_multiplier,
		"reveal_multiplier": _reveal_multiplier,
		"range_multiplier": _range_multiplier,
		"energy_multiplier": _energy_multiplier,
		"module_id": _module_id,
		"tier": _tier,
		"depleted": _charge_ratio <= 0.0,
		"in_facility": _in_facility,
		"remaining_seconds": get_estimated_remaining_seconds(),
		"drain_accumulator": _drain_accumulator,
	}


func _build_lights() -> void:
	# 三盏灯打包成一个 Node3D 子树：F 键直接切 _light_kit.visible，
	# 后续要加灯只要继续挂到 _light_kit 下即可。
	_light_kit = Node3D.new()
	_light_kit.name = "FlashlightKit"
	add_child(_light_kit)
	_beam = SpotLight3D.new()
	_beam.name = "ForwardBeam"
	# top_level=true 让光的世界坐标脱离父链，每帧 force_sync 直接写入绝对位置。
	_beam.top_level = true
	_light_kit.add_child(_beam)
	_beam.add_to_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
	_beam.set_meta("gameplay_light_kind", "flashlight")
	_beam.set_meta("gameplay_light_owner_instance_id", _player.get_instance_id() if _player != null else 0)
	_spill = OmniLight3D.new()
	_spill.name = "EnvironmentSpill"
	_spill.top_level = true
	_light_kit.add_child(_spill)
	_spill.add_to_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
	_spill.set_meta("gameplay_light_kind", "flashlight")
	_spill.set_meta("gameplay_light_owner_instance_id", _player.get_instance_id() if _player != null else 0)
	_front_fill = SpotLight3D.new()
	_front_fill.name = "AvatarFrontFill"
	_front_fill.top_level = true
	_light_kit.add_child(_front_fill)


func _apply_configuration() -> void:
	if _beam != null:
		_beam.light_color = beam_color
		# 关灯时实际能量为 0，开灯时回到 export 值：避免 _apply_configuration
		# 在灯具处于关闭状态时仍然把 export 值写回去，造成"按 F 后又有残留光"。
		_beam.light_energy = beam_energy * _energy_multiplier if _enabled else 0.0
		_beam.spot_range = beam_range * _range_multiplier
		_beam.spot_angle = beam_angle_degrees
		_beam.spot_attenuation = beam_attenuation
		_beam.spot_angle_attenuation = beam_edge_attenuation
		# 主聚光只影响环境层，因此可以投射墙体/怪物阴影，且不会让
		# 角色头、手、枪彼此自遮挡。
		_beam.shadow_enabled = true
		_beam.shadow_bias = beam_shadow_bias
		_beam.shadow_normal_bias = beam_shadow_normal_bias
		_beam.shadow_blur = beam_shadow_blur
		_beam.light_cull_mask = ENVIRONMENT_RENDER_LAYER
		# Godot 的 light_cull_mask 只隔离受光对象；阴影图有独立的
		# shadow_caster_mask。这里必须明确排除 layer 2，角色与手持枪才不会
		# 在自己前向灯的光锥里留下黑影，同时外部灯仍可使用 layer 2 投影。
		_beam.shadow_caster_mask = GameDesignConfig.SHADOW_MASK_WORLD_ONLY
	if _spill != null:
		_spill.light_color = spill_color
		_spill.light_energy = spill_energy * _energy_multiplier if _enabled else 0.0
		_spill.omni_range = spill_range * _range_multiplier
		_spill.omni_attenuation = spill_attenuation
		_spill.shadow_enabled = false
		_spill.light_cull_mask = ENVIRONMENT_RENDER_LAYER
		_spill.shadow_caster_mask = GameDesignConfig.SHADOW_MASK_WORLD_ONLY
	if _front_fill != null:
		_front_fill.light_color = front_fill_color
		_front_fill.light_energy = front_fill_energy * _energy_multiplier if _enabled else 0.0
		_front_fill.spot_range = front_fill_range * _range_multiplier
		_front_fill.spot_angle = front_fill_angle_degrees
		_front_fill.spot_attenuation = front_fill_attenuation
		_front_fill.spot_angle_attenuation = 1.35
		_front_fill.shadow_enabled = false
		_front_fill.light_cull_mask = AVATAR_RENDER_LAYER
		_front_fill.shadow_caster_mask = GameDesignConfig.RENDER_LAYER_PLAYER
	# 缓存开灯时的活跃能量：用于 set_light_enabled 反复切换时不会丢 export 值。
	_beam_energy_active = beam_energy
	_spill_energy_active = spill_energy
	_front_fill_energy_active = front_fill_energy
	# _apply_configuration 既在 _ready 阶段被调用、也会被外部"运行时调参"调用：
	# 把 kit.visible 与 _enabled 同步，确保两种入口下三盏灯一次性显隐。
	if _light_kit != null:
		_light_kit.visible = _enabled
	if _beam != null:
		_beam.visible = _enabled
	if _spill != null:
		_spill.visible = _enabled
	if _front_fill != null:
		_front_fill.visible = _enabled
	_notify_illumination_sensors()


func _notify_illumination_sensors() -> void:
	if is_inside_tree():
		get_tree().call_group(EnemyIllumination3D.RECEIVER_GROUP, "force_refresh_illumination", true)
