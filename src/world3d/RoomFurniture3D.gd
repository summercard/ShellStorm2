class_name RoomFurniture3D
extends Area3D
## 统一家具与搜索容器资产。大小档位影响占地、碰撞和可读距离，造型类型只改变组件组合。

signal searched(prop: RoomFurniture3D, loot: Dictionary)

const SIZE_DIMENSIONS := {
	"small": Vector3(0.9, 0.65, 0.7),
	"medium": Vector3(1.65, 1.25, 0.85),
	"large": Vector3(2.55, 1.75, 1.25),
}

@export_enum("crate", "locker", "desk", "shelf", "generator", "tank", "console", "vat", "archive", "workbench", "toolbox") var furniture_type := "crate"
@export_enum("small", "medium", "large") var size_class := "medium"
@export var searchable := false
@export var accent_color := Color(0.34, 0.72, 0.84)
@export var base_color := Color(0.18, 0.21, 0.21)
@export_range(1, 99, 1) var loot_value := 8
@export_range(0.5, 5.0, 0.1) var search_duration := 1.8

var prop_id := ""
var _searched := false
var _player_in_range := false
var _visual_root: Node3D
var _prompt: Label3D
var _main_material: StandardMaterial3D
var _searching := false
var _search_elapsed := 0.0


func configure(config: Dictionary) -> void:
	prop_id = str(config.get("id", prop_id))
	furniture_type = str(config.get("type", furniture_type))
	size_class = str(config.get("size", size_class))
	searchable = bool(config.get("searchable", searchable))
	accent_color = config.get("accent", accent_color) as Color
	base_color = config.get("base_color", base_color) as Color
	loot_value = int(config.get("loot_value", loot_value))
	search_duration = float(config.get("search_duration", search_duration))


func _ready() -> void:
	add_to_group("room_prop_3d")
	if searchable:
		add_to_group("searchable_prop_3d")
		add_to_group(PlayerInteractionController3D.PROVIDER_GROUP)
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visual()


func _process(delta: float) -> void:
	if not _searching:
		return
	if not _player_in_range:
		_cancel_search()
		return
	_search_elapsed += maxf(0.0, delta)
	if _search_progress() >= 1.0:
		_complete_search()


## 搜索读条进度（0..1）。UI 不再自己画进度条 —— 由 InteractionDot3D 的圆环消费。
func _search_progress() -> float:
	return clampf(_search_elapsed / maxf(0.1, _effective_search_duration()), 0.0, 1.0)


## 交互圆点锚点：沿用原文字提示牌的位置，圆点出现在玩家原本看提示的地方。
func get_interaction_dot_anchor() -> Vector3:
	if _prompt != null and is_instance_valid(_prompt):
		return _prompt.global_position
	var dimensions: Vector3 = SIZE_DIMENSIONS.get(size_class, SIZE_DIMENSIONS["medium"])
	return global_position + Vector3.UP * (dimensions.y + 0.58)


## 已搜索完的容器不再可交互，圆点随之淡出。
func is_interaction_dot_visible() -> bool:
	return not _searched


## 读条期间圆点外圈画进度环，圈满即完成。
func get_interaction_progress() -> Dictionary:
	return {
		"active": _searching,
		"progress": _search_progress() if _searching else 0.0,
	}



func get_interaction_candidate(_player: Player3D) -> Dictionary:
	if not searchable or _searched or _searching or not _player_in_range:
		return {}
	return {
		"available": true,
		"interaction_id": "room_furniture:%s:%d" % [prop_id, get_instance_id()],
		"position": global_position,
		"priority": 40,
		"prompt": _prompt.text if _prompt != null else "[E] 搜索",
	}


## 文字提示牌已退役为纯文案载体（`_prompt.text` 仍被候选协议与探针读取），
## 可见反馈统一交给 InteractionDot3D 的常驻圆点，因此这里不再切换可见性。
func set_interaction_focus(_candidate: Dictionary, _focused: bool) -> void:
	pass


func perform_interaction(_player: Player3D, _candidate: Dictionary) -> bool:
	if not searchable or _searched or _searching or not _player_in_range:
		return false
	_start_search()
	return true


func _start_search() -> void:
	_searching = true
	_search_elapsed = 0.0
	_prompt.text = "搜索中 · 请保持靠近"


func _cancel_search() -> void:
	if not _searching:
		return
	_searching = false
	_search_elapsed = 0.0
	if not _searched:
		_prompt.text = "[E] 搜索 · %s" % size_class.to_upper()


func _complete_search() -> void:
	if _searched:
		return
	_searching = false
	_searched = true
	_player_in_range = false
	_prompt.text = "已搜索"
	_prompt.modulate = Color(0.55, 0.61, 0.62)
	if _main_material != null:
		_main_material.albedo_color = _main_material.albedo_color.darkened(0.28)
	var tween := create_tween()
	tween.tween_property(_visual_root, "position:y", 0.18, 0.12)
	tween.tween_property(_visual_root, "position:y", 0.0, 0.18)
	if AudioManager != null:
		AudioManager.play_sfx("container_open", -3.0)
	searched.emit(self, _build_loot())


func _effective_search_duration() -> float:
	return search_duration * float({"small": 0.72, "medium": 1.0, "large": 1.34}.get(size_class, 1.0))


func is_searched() -> bool:
	return _searched


func restore_searched_state(searched_state: bool) -> void:
	_searched = searched_state
	_searching = false
	_search_elapsed = 0.0
	if _prompt != null:
		_prompt.text = "已搜索" if _searched else "[E] 搜索 · %s" % size_class.to_upper()
		_prompt.modulate = Color(0.55, 0.61, 0.62) if _searched else Color.WHITE
	if _main_material != null and _searched:
		_main_material.albedo_color = _main_material.albedo_color.darkened(0.28)


func get_asset_snapshot() -> Dictionary:
	return {
		"prop_id": prop_id,
		"type": furniture_type,
		"size_class": size_class,
		"dimensions": SIZE_DIMENSIONS.get(size_class, SIZE_DIMENSIONS["medium"]),
		"searchable": searchable,
		"searched": _searched,
		"searching": _searching,
		"search_duration_s": _effective_search_duration(),
		"search_progress": clampf(
			_search_elapsed / maxf(0.1, _effective_search_duration()), 0.0, 1.0
		),
		"is_3d": true,
	}


func _build_loot() -> Dictionary:
	var names := {
		"small": ["密封零件", "旧式药剂", "轻型弹药"],
		"medium": ["军用废料", "工业滤芯", "完整弹匣"],
		"large": ["高价值核心", "装甲组件", "污染样本"],
	}
	var choices: Array = names.get(size_class, names["medium"])
	var index: int = absi(prop_id.hash()) % choices.size() if not prop_id.is_empty() else randi() % choices.size()
	return {
		"prop_id": prop_id,
		"item_id": "loot_3d_%s_%s" % [size_class, furniture_type],
		"name": str(choices[index]),
		"count": 1,
		"value": loot_value,
		"size_class": size_class,
	}


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player_3d"):
		return
	_player_in_range = true


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player_3d"):
		return
	_player_in_range = false
	_cancel_search()


func _build_visual() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)
	var dimensions: Vector3 = SIZE_DIMENSIONS.get(size_class, SIZE_DIMENSIONS["medium"])
	_main_material = _material(base_color, 0.48, 0.66)
	var trim_material := _material(accent_color.darkened(0.22), 0.62, 0.42)
	var glow_material := _material(accent_color, 0.18, 0.28, true)

	match furniture_type:
		"locker", "archive":
			_add_box("Body", Vector3(0, dimensions.y * 0.5, 0), dimensions, _main_material)
			_add_box("DoorInset", Vector3(0, dimensions.y * 0.53, -dimensions.z * 0.51), Vector3(dimensions.x * 0.78, dimensions.y * 0.76, 0.05), trim_material)
			_add_box("Handle", Vector3(dimensions.x * 0.24, dimensions.y * 0.55, -dimensions.z * 0.57), Vector3(0.08, dimensions.y * 0.16, 0.08), glow_material)
		"desk", "workbench":
			_add_box("Top", Vector3(0, dimensions.y * 0.82, 0), Vector3(dimensions.x, dimensions.y * 0.18, dimensions.z), _main_material)
			for x in [-0.42, 0.42]:
				_add_box("Leg", Vector3(dimensions.x * x, dimensions.y * 0.38, 0), Vector3(0.13, dimensions.y * 0.76, dimensions.z * 0.72), trim_material)
			_add_box("ToolRail", Vector3(0, dimensions.y * 1.02, 0.12), Vector3(dimensions.x * 0.68, 0.08, 0.12), glow_material)
		"shelf":
			for y in [0.18, 0.52, 0.86]:
				_add_box("Shelf", Vector3(0, dimensions.y * y, 0), Vector3(dimensions.x, 0.10, dimensions.z), _main_material)
			for x in [-0.46, 0.46]:
				_add_box("Frame", Vector3(dimensions.x * x, dimensions.y * 0.52, 0), Vector3(0.10, dimensions.y, 0.10), trim_material)
		"generator", "console":
			_add_box("Body", Vector3(0, dimensions.y * 0.5, 0), dimensions, _main_material)
			_add_box("Panel", Vector3(0, dimensions.y * 0.62, -dimensions.z * 0.52), Vector3(dimensions.x * 0.72, dimensions.y * 0.38, 0.07), trim_material)
			for x in [-0.22, 0.0, 0.22]:
				_add_box("Indicator", Vector3(dimensions.x * x, dimensions.y * 0.68, -dimensions.z * 0.58), Vector3(0.07, 0.07, 0.04), glow_material)
		"tank", "vat":
			_add_cylinder("Tank", Vector3(0, dimensions.y * 0.52, 0), dimensions.x * 0.40, dimensions.y, _main_material)
			_add_cylinder("Band", Vector3(0, dimensions.y * 0.58, 0), dimensions.x * 0.43, dimensions.y * 0.10, trim_material)
			_add_box("Gauge", Vector3(0, dimensions.y * 0.72, -dimensions.x * 0.42), Vector3(0.22, 0.22, 0.08), glow_material)
		_:
			_add_box("Body", Vector3(0, dimensions.y * 0.5, 0), dimensions, _main_material)
			_add_box("Lid", Vector3(0, dimensions.y + 0.06, 0), Vector3(dimensions.x * 1.04, 0.14, dimensions.z * 1.04), trim_material)
			_add_box("Latch", Vector3(0, dimensions.y * 0.63, -dimensions.z * 0.54), Vector3(dimensions.x * 0.24, dimensions.y * 0.22, 0.06), glow_material)

	var static_body := StaticBody3D.new()
	static_body.name = "CollisionBody"
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	add_child(static_body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.position = Vector3(0, dimensions.y * 0.5, 0)
	collision.shape = shape
	static_body.add_child(collision)

	var interaction := CollisionShape3D.new()
	var interaction_shape := BoxShape3D.new()
	interaction_shape.size = dimensions + Vector3(1.4, 1.0, 1.4)
	interaction.position = Vector3(0, dimensions.y * 0.5, 0)
	interaction.shape = interaction_shape
	add_child(interaction)

	_prompt = Label3D.new()
	_prompt.name = "Prompt"
	_prompt.position = Vector3(0, dimensions.y + 0.58, 0)
	_prompt.text = "[E] 搜索 · %s" % size_class.to_upper()
	_prompt.font_size = 38
	_prompt.pixel_size = 0.012
	_prompt.modulate = accent_color.lightened(0.2)
	_prompt.outline_size = 8
	# 2026-10-02 主人要求：交互提示统一改为常驻圆点（InteractionDot3D）。
	# 这块 Label3D 退役为**纯文案载体** —— 它的 text/modulate 仍按状态更新（候选协议
	# 的 prompt 字段与多枚探针读它），但不再渲染；圆点锚点也取自它的位置。
	_prompt.visible = false
	add_child(_prompt)


func _add_box(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	_visual_root.add_child(instance)


func _add_cylinder(node_name: String, position: Vector3, radius: float, height: float, material: StandardMaterial3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	_visual_root.add_child(instance)


func _material(color: Color, metallic: float, roughness: float, emission := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.6
	return material
