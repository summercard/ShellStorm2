class_name MainStoryPedestal3D
extends Node3D
## 永久进度的只读表现：四孔钥匙嵌件嵌在 99F 主门下方低矮设备柜的台面上。
##
## 本节点**只做表现**：装嵌件、按永久快照换槽灯、显示已安装的钥匙。
## 领取 / 安装 / 解锁事务一律归 `BaseManager.main_story`，这里不写任何存档。
##
## 为什么不再自己搭一块立式台座：业主明确要求「不要在这里新作一个模型，
## 放到后面这个台子上，斜着往里头插，有四个插孔，直接做一个新模型嵌在上面，
## 不用改原模型」。所以台柜本体（`main_door_low_storage_cabinet`）一毫米没动，
## 嵌件是**独立**资产 `PRP-BASE99-MAIN-STORY-KEY-INSERT`，直接摆在台面空位上。

const SLOT_COUNT := 4
const INSERT_SCENE := "res://assets/art/props/main_story/runtime/key_insert/prp_base99_main_story_key_insert_root_top3d.tscn"
const KEY_PATH := "res://assets/art/props/main_story/runtime/rare_earth_key.tscn"
const KEY_IDS := ["mq_key_rare_earth", "mq_key_manor", "mq_key_hotel", "mq_key_sector_04"]
const KEY_COLORS := [Color(0.96, 0.62, 0.12), Color(0.2, 0.78, 0.95), Color(0.72, 0.35, 0.95), Color(0.92, 0.24, 0.3)]

## 以下三组数值来自嵌件制作清单 `art_source/props/main_story/key_insert/asset_manifest.json`，
## 不是按截图估的：孔心在嵌件局部坐标、孔轴 20° 朝台面里侧（-Z）下插。
const SOCKET_LOCAL := [
	Vector3(-0.69, 0.12844863, 0.0),
	Vector3(-0.23, 0.12844863, 0.0),
	Vector3(0.23, 0.12844863, 0.0),
	Vector3(0.69, 0.12844863, 0.0),
]
const SOCKET_AXIS_LOCAL := Vector3(0.0, -0.93969262, -0.34202014)
## 钥匙局部最远端（含齿）约 z=-0.525；缩放到 0.72 后约 0.378 m。
const KEY_TIP_LOCAL_Z := -0.525
const KEY_SCALE := 0.72
## 轴身坐进孔里，孔外只露握把与锁环 —— 台阶式“斜着插进去”。
## 深度取 0.10 m：孔口在嵌件侧面 0.128 m 处，滑槽只有 60 mm，再深就会从嵌件底面穿出去。
const KEY_TIP_DEPTH_M := 0.10
## 台面 = 主门下方低矮设备柜项面（碰撞盒顶 1.38 m，已实测）。
## 绿苔身高约 1.2 m、手部静止高度约 0.55 m，所以要站到台边抬高手臂，不能站远。
const STAND_LOCAL_Z := 0.80
## 四分一环平铺在台面上，包围嵌件（嵌件 2.28 × 0.58，台面深 0.86）：
## 旧版竖直圆环会悬在台面外、看着像空中水圈，已改为平铺扁环。
const RING_HEIGHT_M := 0.008
const RING_HALF_WIDTH_M := 1.30
const RING_HALF_DEPTH_M := 0.40
const PULSE_SECONDS := 1.25

var _host: Node
var _insert: Node3D
var _slot_lights: Array[OmniLight3D] = []
var _glows: Array[MeshInstance3D] = []
var _keys: Array[Node3D] = []
var _ring: Array[MeshInstance3D] = []
var _pulse: MeshInstance3D
var _pulse_tween: Tween
var _installed_count := 0
var _floor_y := 0.0
var _poll := 0.0
var _built := false


func _ready() -> void:
	_build()
	refresh_main_story_key_visuals()


func setup(host: Node) -> void:
	_host = host
	_apply_placement()
	_build()
	refresh_main_story_key_visuals()

## 台面承载点由关卡装配器给出（它才知道美术布置层的真实世界变换），
## 叙事表现层不写死世界坐标，也不猜节点路径。
func _apply_placement() -> void:
	if _host == null or not _host.has_method("get_main_story_insert_transform"):
		push_warning("[MainStoryPedestal3D] 装配器未提供台面承载点，嵌件不摆放。")
		return
	var placement: Variant = _host.call("get_main_story_insert_transform")
	if placement is Transform3D:
		global_transform = placement as Transform3D
	if _host.has_method("get_main_story_floor_y"):
		_floor_y = float(_host.call("get_main_story_floor_y"))


func _build() -> void:
	if _built:
		return
	if not ResourceLoader.exists(INSERT_SCENE):
		push_error("[MainStoryPedestal3D] 缺少四孔嵌件资产：%s" % INSERT_SCENE)
		return
	var packed := load(INSERT_SCENE) as PackedScene
	_insert = packed.instantiate() as Node3D if packed != null else null
	if _insert == null:
		push_error("[MainStoryPedestal3D] 四孔嵌件实例化失败。")
		return
	_insert.name = "KeyInsert"
	add_child(_insert)
	_built = true
	_collect_sockets()
	for index in SLOT_COUNT:
		var lamp := OmniLight3D.new()
		lamp.name = "KeySlotLight_%d" % index
		lamp.light_color = KEY_COLORS[index]
		lamp.light_energy = 0.0
		lamp.omni_range = 1.1
		lamp.position = SOCKET_LOCAL[index] + Vector3.UP * 0.22
		add_child(lamp)
		_slot_lights.append(lamp)
		# 只有第一把已制作，后三槽不假造后续钥匙资产。
		var key: Node3D = null
		if index == 0:
			var scene := load(KEY_PATH) as PackedScene
			key = scene.instantiate() as Node3D if scene != null else null
			if key != null:
				key.name = "PersistentRareEarthKey"
				add_child(key)
				key.transform = _inserted_key_transform(0)
				key.hide()
		_keys.append(key)
	for index in 32:
		var angle := TAU * float(index) / 32.0
		var segment := _box(
			"QuarterRing_%02d" % index,
			Vector3(0.10, 0.014, 0.045),
			Vector3(sin(angle) * RING_HALF_WIDTH_M, RING_HEIGHT_M, cos(angle) * RING_HALF_DEPTH_M),
			Color(0.21, 0.05, 0.09)
		)
		# 段体沿椭圆切线摆正，平贴在台面上。
		segment.rotation.y = -atan2(cos(angle) * RING_HALF_WIDTH_M, sin(angle) * RING_HALF_DEPTH_M)
		_ring.append(segment)
	_pulse = MeshInstance3D.new()
	_pulse.name = "DepositExpansionPulse"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.12
	torus.outer_radius = 0.16
	torus.rings = 24
	torus.ring_segments = 6
	_pulse.mesh = torus
	_pulse.material_override = _material(KEY_COLORS[0], KEY_COLORS[0], 1.2)
	_pulse.position = SOCKET_LOCAL[0] + Vector3.UP * 0.04
	_pulse.hide()
	add_child(_pulse)


## 嵌件的四个槽灯是独立网格 `SocketGlow_0..3`（共享同一份发光材质）。
## 要让每个孔各自换色，必须先把材质复制成本实例私有，不能去改共享材质。
func _collect_sockets() -> void:
	for index in SLOT_COUNT:
		var glow := _insert.find_child("SocketGlow_%d" % index, true, false) as MeshInstance3D
		if glow == null:
			push_error("[MainStoryPedestal3D] 嵌件缺少槽灯 SocketGlow_%d。" % index)
			continue
		var material := glow.get_active_material(0)
		if material is StandardMaterial3D:
			glow.material_override = (material as StandardMaterial3D).duplicate() as StandardMaterial3D
		_glows.append(glow)


## 钥匙最终插到位时的姿势：尖进孔 5 cm，柄留在台面上方，20° 斜插。
func _inserted_key_transform(index: int) -> Transform3D:
	var axis_out: Vector3 = -SOCKET_AXIS_LOCAL
	var tip_scale := absf(KEY_TIP_LOCAL_Z) * KEY_SCALE
	var mouth: Vector3 = SOCKET_LOCAL[index]
	var origin: Vector3 = mouth + axis_out * (tip_scale - KEY_TIP_DEPTH_M)
	return Transform3D(get_insert_basis().scaled(Vector3.ONE * KEY_SCALE), origin)


func get_anchor(anchor_id: String) -> Variant:
	match anchor_id:
		"pedestal_focus":
			return to_global(Vector3(0.0, 0.62, 0.0))
		"key_slot_rare_earth":
			return to_global(SOCKET_LOCAL[0])
		"pedestal_stand":
			# 站位是台前地面（不是台面）；测试用 y 差 > 0.7 守住这条。
			return to_global(Vector3(SOCKET_LOCAL[0].x, _floor_y - global_position.y, STAND_LOCAL_Z))
	return null


## 插入动作需要的三个量：朝向、钥匙柄相对孔心的偏移、手相对孔心的偏移。
## 孔心给相机和站位用；真正插进去的钥匙柄要抬到台面上方。
func get_insert_params() -> Dictionary:
	var axis_out: Vector3 = -SOCKET_AXIS_LOCAL
	var tip_scale := absf(KEY_TIP_LOCAL_Z) * KEY_SCALE
	return {
		"basis": get_insert_basis(),
		"origin_offset": axis_out * (tip_scale - KEY_TIP_DEPTH_M),
	}


## 锁孔轴向下、朝台面里侧：钥匙局部 -Z（齿那头）沿孔轴进去。
func get_insert_basis() -> Basis:
	var axis_in := (global_basis * SOCKET_AXIS_LOCAL).normalized()
	return Basis.looking_at(axis_in, Vector3.UP)


func _process(delta: float) -> void:
	_poll += delta
	if _poll >= 0.4:
		_poll = 0.0
		refresh_main_story_key_visuals()


func _snapshot() -> Dictionary:
	if not is_inside_tree():
		return {}
	# 服务按唯一公开查询能力发现，不把叙事表现绑定到节点路径。
	for service in get_tree().root.get_children():
		if service.has_method("get_main_story_snapshot"):
			return service.call("get_main_story_snapshot") as Dictionary
	return {}


func refresh_main_story_key_visuals() -> void:
	if not _built:
		return
	var keys: Dictionary = _snapshot().get("keys", {})
	_installed_count = 0
	for index in SLOT_COUNT:
		var row: Dictionary = keys.get(KEY_IDS[index], {})
		var installed := str(row.get("state", "")) == "deposited" or bool(row.get("deposited", false))
		if installed:
			_installed_count += 1
		var color: Color = KEY_COLORS[index] if installed else Color(0.19, 0.05, 0.09)
		if index < _glows.size():
			_set_color(_glows[index], color, 1.1 if installed else 0.0)
		if _pulse_tween == null or not _pulse_tween.is_running():
			_slot_lights[index].light_energy = 0.18 if installed else 0.0
		if _keys[index] != null:
			_keys[index].visible = installed
	for index in _ring.size():
		var lit := index < _installed_count * 8
		_set_color(_ring[index], KEY_COLORS[0] if lit else Color(0.22, 0.05, 0.09), 1.0 if lit else 0.08)


func apply_main_story_key_visual(key_id: String) -> void:
	refresh_main_story_key_visuals()
	var index := KEY_IDS.find(key_id)
	if index >= 0 and _installed_count > 0:
		_play_pulse(index)


func get_snapshot() -> Dictionary:
	return {
		"installed_count": _installed_count,
		"slot_count": SLOT_COUNT,
		"ring_fraction": float(_installed_count) / 4.0,
		"persistent_key_visible": _keys[0].visible if not _keys.is_empty() and _keys[0] != null else false,
		"anchor_ids": ["key_slot_rare_earth", "pedestal_stand", "pedestal_focus"],
		"insert_asset_id": "PRP-BASE99-MAIN-STORY-KEY-INSERT",
		"insert_loaded": _insert != null,
		"socket_glows": _glows.size(),
		"socket_world": SOCKET_LOCAL.map(func(point: Vector3) -> String: return str(to_global(point))),
	}


func _play_pulse(index: int) -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse.position = SOCKET_LOCAL[index] + Vector3.UP * 0.04
	_pulse.show()
	_pulse.scale = Vector3.ONE * 0.3
	_slot_lights[index].light_energy = 0.8
	_pulse_tween = create_tween().set_parallel(true)
	_pulse_tween.tween_property(_pulse, "scale", Vector3.ONE * 2.4, PULSE_SECONDS)
	_pulse_tween.tween_property(_slot_lights[index], "light_energy", 0.18, PULSE_SECONDS)
	_pulse_tween.chain().tween_callback(_pulse.hide)


func _box(node_name: String, size: Vector3, point: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _material(color, color, 0.1)
	node.position = point
	add_child(node)
	return node


func _set_color(mesh: MeshInstance3D, color: Color, energy: float) -> void:
	var material := mesh.material_override as StandardMaterial3D
	if material == null:
		material = mesh.get_active_material(0) as StandardMaterial3D
		if material != null:
			material = material.duplicate() as StandardMaterial3D
			mesh.material_override = material
	if material == null:
		return
	material.albedo_color = color
	material.emission_enabled = energy > 0.0
	material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	material.emission = color
	material.emission_energy_multiplier = energy


func _material(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.metallic = 0.8
	material.roughness = 0.3
	material.emission_enabled = true
	material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	material.emission = emission
	material.emission_energy_multiplier = energy
	return material
