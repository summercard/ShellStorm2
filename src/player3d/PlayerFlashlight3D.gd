class_name PlayerFlashlight3D
extends Node3D
## 与玩法视野完全解耦的真实玩家灯光。
## 前向环境主灯投影；近身溢光与角色柔光不投影。
## 三盏随身灯都不会对角色自身投影：环境灯只照 layer 1，角色柔光不启用阴影。
## 角色网格本身仍可被太阳和房间灯（layer 1|2）投射到环境上。

signal light_enabled_changed(enabled: bool)

const ENVIRONMENT_RENDER_LAYER := GameDesignConfig.RENDER_LAYER_WORLD
const AVATAR_RENDER_LAYER := GameDesignConfig.RENDER_LAYER_PLAYER

@export_group("Input")
@export var toggle_action := "toggle_flashlight"
@export var start_enabled := false

@export_group("Beam")
@export var beam_color := Color(0.86, 0.96, 0.93)
@export_range(0.0, 32.0, 0.1) var beam_energy := 20.15
@export_range(4.0, 40.0, 0.5) var beam_range := 25.0
@export_range(20.0, 110.0, 1.0) var beam_angle_degrees := 66.0
@export_range(0.1, 2.0, 0.05) var beam_attenuation := 0.48
@export_range(0.1, 4.0, 0.05) var beam_edge_attenuation := 1.15

@export_group("Mount")
@export_range(0.5, 4.0, 0.05) var mount_height := 1.15
@export_range(-1.0, 2.0, 0.05) var mount_forward := -0.01
@export_range(1.0, 24.0, 0.25) var target_forward := 11.0
@export_range(0.0, 2.0, 0.05) var target_height := 0.38

@export_group("Environment Spill")
@export var spill_color := Color(0.68, 0.88, 0.84)
@export_range(0.0, 8.0, 0.05) var spill_energy := 2.30
@export_range(1.0, 10.0, 0.25) var spill_range := 4.8
@export_range(0.1, 4.0, 0.05) var spill_attenuation := 2.0
@export_range(0.2, 2.0, 0.05) var spill_height := 0.65

@export_group("Avatar Front Fill")
@export var front_fill_color := Color(0.70, 0.90, 0.86)
@export_range(0.0, 16.0, 0.05) var front_fill_energy := 10.4
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
	if _enabled == enabled:
		return
	_enabled = enabled
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
	var target_energy := (
		beam_energy if enabled else 0.0
	)
	var spill_target := (
		spill_energy if enabled else 0.0
	)
	var fill_target := (
		front_fill_energy if enabled else 0.0
	)
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


func toggle_light() -> bool:
	set_light_enabled(not _enabled)
	return _enabled


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
		"spill_energy": spill_energy,
		"spill_range": spill_range,
		"front_fill_energy": front_fill_energy,
		"environment_light_cull_mask": ENVIRONMENT_RENDER_LAYER,
		"avatar_light_cull_mask": AVATAR_RENDER_LAYER,
		"environment_spill_affects_avatar": false,
		"front_fill_affects_avatar": true,
		"aim_alignment": aim_alignment,
		"gameplay_light_dependent": false,
		"configurable": true,
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
	_spill = OmniLight3D.new()
	_spill.name = "EnvironmentSpill"
	_spill.top_level = true
	_light_kit.add_child(_spill)
	_front_fill = SpotLight3D.new()
	_front_fill.name = "AvatarFrontFill"
	_front_fill.top_level = true
	_light_kit.add_child(_front_fill)


func _apply_configuration() -> void:
	if _beam != null:
		_beam.light_color = beam_color
		# 关灯时实际能量为 0，开灯时回到 export 值：避免 _apply_configuration
		# 在灯具处于关闭状态时仍然把 export 值写回去，造成"按 F 后又有残留光"。
		_beam.light_energy = beam_energy if _enabled else 0.0
		_beam.spot_range = beam_range
		_beam.spot_angle = beam_angle_degrees
		_beam.spot_attenuation = beam_attenuation
		_beam.spot_angle_attenuation = beam_edge_attenuation
		# 主聚光只影响环境层，因此可以投射墙体/怪物阴影，且不会让
		# 角色头、手、枪彼此自遮挡。
		_beam.shadow_enabled = true
		_beam.light_cull_mask = ENVIRONMENT_RENDER_LAYER
	if _spill != null:
		_spill.light_color = spill_color
		_spill.light_energy = spill_energy if _enabled else 0.0
		_spill.omni_range = spill_range
		_spill.omni_attenuation = spill_attenuation
		_spill.shadow_enabled = false
		_spill.light_cull_mask = ENVIRONMENT_RENDER_LAYER
	if _front_fill != null:
		_front_fill.light_color = front_fill_color
		_front_fill.light_energy = front_fill_energy if _enabled else 0.0
		_front_fill.spot_range = front_fill_range
		_front_fill.spot_angle = front_fill_angle_degrees
		_front_fill.spot_attenuation = front_fill_attenuation
		_front_fill.spot_angle_attenuation = 1.35
		_front_fill.shadow_enabled = false
		_front_fill.light_cull_mask = AVATAR_RENDER_LAYER
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
