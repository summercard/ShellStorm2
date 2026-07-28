class_name ThemedNPC3D
extends Area3D
## 3D 预览与基地复用的主题 NPC 适配层。
## 保持 2D ThemedNPC 的配置和交互语义，视觉仍是可替换的程序化占位表现。

signal interaction_changed(visible: bool, text: String)
signal configured(npc_id: String)

@export var npc_id := "npc_signal"
@export var display_name := "荒野信使"
@export var role := "情报提供者"
@export_multiline var interaction_text := "风向变了。别在没有照明的走廊停太久。"
@export var accent_color := Color(0.28, 0.78, 0.88, 1.0)

var _player_in_range := false
var _dialogue_visible := false
var _visual_root: Node3D
var _name_label: Label3D
var _role_label: Label3D
var _prompt_label: Label3D
var _dialogue_label: Label3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = true
	add_to_group("themed_npc_3d")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visuals()
	_refresh_presentation()


func configure(config: Dictionary) -> void:
	npc_id = str(config.get("id", npc_id))
	display_name = str(config.get("name", display_name))
	role = str(config.get("role", role))
	interaction_text = str(config.get("text", interaction_text))
	accent_color = config.get("color", accent_color) as Color
	if is_node_ready():
		_refresh_presentation()
	configured.emit(npc_id)


func interact() -> bool:
	_dialogue_visible = not _dialogue_visible
	_refresh_presentation()
	interaction_changed.emit(_dialogue_visible, interaction_text)
	return _dialogue_visible


func hide_dialogue() -> void:
	if not _dialogue_visible:
		return
	_dialogue_visible = false
	_refresh_presentation()
	interaction_changed.emit(false, interaction_text)


func get_snapshot() -> Dictionary:
	return {
		"npc_id": npc_id,
		"display_name": display_name,
		"role": role,
		"text": interaction_text,
		"in_range": _player_in_range,
		"dialogue_visible": _dialogue_visible,
		"is_3d": true,
	}


func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and event.is_action_pressed("interact"):
		interact()
		get_viewport().set_input_as_handled()


func _build_visuals() -> void:
	var collision := CollisionShape3D.new()
	collision.name = "InteractionRange"
	var shape := SphereShape3D.new()
	shape.radius = 2.25
	collision.shape = shape
	collision.position.y = 0.9
	add_child(collision)

	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)
	_add_mesh("Body", _capsule_mesh(0.48, 1.28), Vector3(0, 0.78, 0), accent_color)
	_add_mesh("Helmet", _sphere_mesh(0.47), Vector3(0, 1.56, -0.03), accent_color.lightened(0.18))
	_add_mesh("Visor", _box_mesh(Vector3(0.50, 0.14, 0.10)), Vector3(0, 1.57, -0.43), Color(0.06, 0.14, 0.17))
	_add_mesh("Pack", _box_mesh(Vector3(0.42, 0.58, 0.20)), Vector3(0, 0.86, 0.42), accent_color.darkened(0.22))

	_name_label = _make_label("NameLabel", Vector3(0, 2.55, 0), 46, Color(0.90, 0.96, 1.0))
	_role_label = _make_label("RoleLabel", Vector3(0, 2.26, 0), 31, accent_color.lightened(0.2))
	_prompt_label = _make_label("PromptLabel", Vector3(0, 2.00, 0), 27, Color(1.0, 0.82, 0.32))
	_dialogue_label = _make_label("DialogueLabel", Vector3(0, 3.08, 0), 30, Color(0.92, 0.96, 0.98))


func _refresh_presentation() -> void:
	if _visual_root != null:
		var body := _visual_root.get_node_or_null("Body") as MeshInstance3D
		if body != null and body.material_override is StandardMaterial3D:
			(body.material_override as StandardMaterial3D).albedo_color = accent_color
	if _name_label != null:
		_name_label.text = display_name
	if _role_label != null:
		_role_label.text = role
		_role_label.modulate = accent_color.lightened(0.2)
	if _prompt_label != null:
		_prompt_label.text = "[E] 交谈" if _player_in_range else "预览实体"
	if _dialogue_label != null:
		_dialogue_label.text = interaction_text
		_dialogue_label.visible = _dialogue_visible


func _add_mesh(node_name: String, mesh: Mesh, position: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.18
	material.roughness = 0.62
	instance.material_override = material
	_visual_root.add_child(instance)


func _make_label(node_name: String, position: Vector3, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.position = position
	label.font_size = font_size
	label.outline_size = 6
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.pixel_size = 0.006
	add_child(label)
	return label


func _capsule_mesh(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


func _sphere_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player_3d"):
		_player_in_range = true
		_refresh_presentation()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player_3d"):
		_player_in_range = false
		hide_dialogue()
		_refresh_presentation()

