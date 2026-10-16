class_name StrongVariantEyeGlow3D
extends Node3D
## 强化怪（普通怪变种）的**红色发光眼**表现。
##
## 一对自发光眼球 + 一盏很弱的溢光灯，挂在 `Head` 骨的 `BoneAttachment3D` 下，
## 因此**随头部动画一起走**（这是本节点存在的全部意义：不能是固定世界坐标）。
##
## 设计口径（业主 2026-10-16）：「红色发光特效，放在眼睛的位置，专门给强化怪用」。
## 三只变种（小僵尸 / 胖子僵尸 / 保安僵尸-强化怪）共用这一套，眼位差异由
## `MonsterVariants.EYE_SOCKETS` 的配方给出，不在本文件写死任何一只怪的坐标。
##
## **纯表现，零玩法**：没有碰撞体、不参与受光判定、不写 `current_hp`。
## 验证据此正面断言（`_check_no_gameplay_impact`）——
## 发光眼不该让怪变得更好打或更难打。

## 眼球自发光颜色（业主指定的红）。
const GLOW_COLOR := Color(1.0, 0.055, 0.075, 1.0)
## 自发光强度。取值刻意不追求「刺眼」：变种怪是常规敌人，不是 Boss 特效。
const EMISSION_ENERGY := 2.6
## 呼吸脉冲：周期（秒）与强度摆幅（±）。
## 给一点脉动是为了让「这是活物在盯着你」被读出来 —— 完全静止的红点会像贴图瑕疵。
const PULSE_PERIOD_SEC := 1.9
const PULSE_AMPLITUDE := 0.34
## 溢光半径与能量。**刻意很弱**：一盏灯要照亮周围才能叫「发光」，
## 但能量给大就会把整只怪的脸染红、变成一个移动红灯笼 —— 这不是眼睛发光，
## 是把怪泡在红灯里（实测第一版 0.85 就是这样，脸全红了）。
##
## 现在的取值让溢光只够在眼球周围形成一小圈「红光晕」，脸的本色仍是原色。
const LIGHT_RANGE_M := 0.85
const LIGHT_ENERGY := 0.22

## 每个眼球节点名（验收按名取节点，不用位置猜）。
const LEFT_EYE_NAME := "EyeGlowL"
const RIGHT_EYE_NAME := "EyeGlowR"
const GLOW_LIGHT_NAME := "EyeGlowLight"

## 挂载后由 `EnemyAvatar3D` 写入：本节点所属的怪种（变种 ID）。仅用于快照。
var variant_id := ""
## 眼球半径（模型根空间，米）。由配方给出。
var eye_radius := 0.030

var _elapsed := 0.0


## 建好两只眼 + 一盏灯。`local_positions` 是本节点空间（= 骨空间）里的左右眼位置。
##
## 用**位置参数**而不是让本节点自己算：眼位必须先由 `EnemyAvatar3D` 从模型顶点
## 反算成骨空间偏移，本节点只负责「把光放在给定位置」。这样单测可以直接喂坐标。
func build(local_positions: Array, color: Color = GLOW_COLOR) -> void:
	_clear()
	for index in range(local_positions.size()):
		var name := LEFT_EYE_NAME if index == 0 else RIGHT_EYE_NAME
		_add_eye(name, local_positions[index] as Vector3, color)
	_add_light(color)


## 取一对眼球节点（按名字，顺序 = 左、右）。缺则返回空数组。
func get_eyes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node_name in [LEFT_EYE_NAME, RIGHT_EYE_NAME]:
		var node := get_node_or_null(node_name)
		if node is MeshInstance3D:
			out.append(node as MeshInstance3D)
	return out


## 提前撤掉（死亡 / 硬直 / 房间停用）。幂等：重复调用不报错。
##
## 必须能提前撤 —— 一只已经躺下的怪还在「瞪着你」是假信息，
## 与头顶吼叫图标 `dismiss()` 是同一条纪律。
func dismiss() -> void:
	visible = false
	set_process(false)


## 供验收与调试读取的快照。数值**从实际节点读**，不重复一份真相。
func get_presentation_snapshot() -> Dictionary:
	var eyes := get_eyes()
	var positions: Array = []
	var emissive := true
	var emissive_color := Color.BLACK
	var energy := 0.0
	for eye in eyes:
		positions.append(eye.position)
		var material := eye.get_active_material(0) as StandardMaterial3D
		if material == null or not material.emission_enabled:
			emissive = false
		elif material != null:
			emissive_color = material.emission
			energy = material.emission_energy_multiplier
	var light := get_node_or_null(GLOW_LIGHT_NAME)
	return {
		"variant_id": variant_id,
		"eye_count": eyes.size(),
		"eye_positions": positions,
		"eye_radius": eye_radius,
		"emission_enabled": emissive,
		"emission_color": emissive_color,
		"emission_energy": energy,
		"has_light": light != null,
		"light_range": (light as OmniLight3D).omni_range if light is OmniLight3D else 0.0,
		"light_energy": (light as OmniLight3D).light_energy if light is OmniLight3D else 0.0,
		"visible": visible,
		"pulse_period": PULSE_PERIOD_SEC,
		"pulse_amplitude": PULSE_AMPLITUDE,
	}


func _process(delta: float) -> void:
	_elapsed += delta
	# 呼吸脉动：只改 emission 强度，不改尺寸/位置 —— 改尺寸会让眼球在脸上「跳」。
	var phase := sin(_elapsed * TAU / PULSE_PERIOD_SEC)
	var energy := EMISSION_ENERGY * (1.0 + PULSE_AMPLITUDE * phase)
	for eye in get_eyes():
		var material := eye.get_active_material(0) as StandardMaterial3D
		if material != null:
			material.emission_energy_multiplier = energy
	var light := get_node_or_null(GLOW_LIGHT_NAME) as OmniLight3D
	if light != null:
		light.light_energy = LIGHT_ENERGY * (1.0 + PULSE_AMPLITUDE * phase)


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _add_eye(node_name: String, position: Vector3, color: Color) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = eye_radius
	sphere.height = eye_radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 8
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = EMISSION_ENERGY
	# 不受光：眼球要恒定亮，不能因为怪走进阴影就变暗（那会让「强化怪的红眼」忽明忽暗）。
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = material
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = sphere
	node.position = position
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.layers = 1
	add_child(node)


func _add_light(color: Color) -> void:
	var light := OmniLight3D.new()
	light.name = GLOW_LIGHT_NAME
	light.light_color = color
	light.omni_range = LIGHT_RANGE_M
	light.light_energy = LIGHT_ENERGY
	light.shadow_enabled = false
	# 放在两眼中间稍前，让溢光均匀盖住脸部而不是偏向一侧。
	var positions := get_eyes()
	if positions.size() == 2:
		light.position = (positions[0].position + positions[1].position) * 0.5
	elif positions.size() == 1:
		light.position = positions[0].position
	add_child(light)
