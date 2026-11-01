extends Node3D
## 远征03场景自持的室内光照包络。只读实际房间足迹，不拥有或修改关卡布局。
## 顶盖与外侧四壁仅投影；layer1静态盒同时阻断怪物日照射线，不遮俯视相机。

@export var ceiling_height_m := 6.0
@export var thickness_m := 1.0
@export var perimeter_margin_m := 3.0

var _bounds := AABB()
var _room_count := 0
var _built := false
var _room_bounces: Array[OmniLight3D] = []


func _ready() -> void:
	var level := get_parent() as TowerDescent3D
	if level == null:
		push_error("IndoorLightEnvelope requires a TowerDescent3D scene parent")
		return
	level.gameplay_started.connect(_on_gameplay_started, CONNECT_ONE_SHOT)
	# detail顶灯可能在进房后才创建；只处理本关子树的顶灯几何。
	get_tree().node_added.connect(_on_node_added)
	for node in level.find_children("*", "Node3D", true, false):
		_hide_ceiling_fixture(node)


func _on_node_added(node: Node) -> void:
	if node is WastelandLight3D and get_parent().is_ancestor_of(node):
		_hide_ceiling_fixture.call_deferred(node)
	elif node is Light3D and not node is DirectionalLight3D and get_parent().is_ancestor_of(node):
		_register_room_light.call_deferred(node)


func _hide_ceiling_fixture(node: Node) -> void:
	if not is_instance_valid(node) or not node is WastelandLight3D:
		return
	if node.fixture_style != "ceiling":
		return
	for label in ["CeilingMount", "Fixture", "Lens"]:
		var visual := node.get_node_or_null(NodePath(label)) as GeometryInstance3D
		if visual != null:
			visual.visible = false
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _on_gameplay_started(_room_id: String) -> void:
	var level := get_parent() as TowerDescent3D
	var found := false
	for node in level.find_children("*", "Node3D", true, false):
		var room := node as DungeonRoom3D
		if room == null:
			continue
		var dimensions := room.get_dimensions()
		var local_box := AABB(
			Vector3(-dimensions.x / 2.0, -1.0, -dimensions.y / 2.0),
			Vector3(dimensions.x, ceiling_height_m + 1.0, dimensions.y)
		)
		var box: AABB = global_transform.affine_inverse() * room.global_transform * local_box
		_bounds = _bounds.merge(box) if found else box
		found = true
		_room_count += 1
		_add_room_bounce(room)
		_register_authored_lights(room)
	if not found:
		push_error("IndoorLightEnvelope: no committed room footprints")
		return
	_bounds.position.x -= perimeter_margin_m
	_bounds.position.z -= perimeter_margin_m
	_bounds.size.x += perimeter_margin_m * 2.0
	_bounds.size.z += perimeter_margin_m * 2.0
	var center := _bounds.get_center()
	var top := _bounds.end.y
	_add_blocker("Ceiling", Vector3(_bounds.size.x + thickness_m * 2.0, thickness_m, _bounds.size.z + thickness_m * 2.0), Vector3(center.x, top + thickness_m / 2.0, center.z))
	for side in [-1, 1]:
		_add_blocker("West" if side < 0 else "East", Vector3(thickness_m, _bounds.size.y, _bounds.size.z + thickness_m * 2.0), Vector3(center.x + side * (_bounds.size.x + thickness_m) / 2.0, center.y, center.z))
		_add_blocker("North" if side < 0 else "South", Vector3(_bounds.size.x, _bounds.size.y, thickness_m), Vector3(center.x, center.y, center.z + side * (_bounds.size.z + thickness_m) / 2.0))
	# 天台无影补光不能被实体投影遮挡。复用既有表现接口，限定在当前场景实例。
	var atmosphere := level.get_node_or_null("TowerAtmosphere3D")
	if atmosphere != null:
		atmosphere.call("set_expedition_dark_distant", true)
	_built = true


func _add_blocker(label: String, size_m: Vector3, center: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.BLACK
	material.roughness = 1.0
	material.disable_fog = true
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.position = center
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	visual.layers = GameDesignConfig.RENDER_LAYER_WORLD
	visual.set_meta("top_cover_occluder", label == "Ceiling")
	add_child(visual)
	# 巨型单Mesh在方向光级联阴影中会丢失覆盖；分块使每块独立进入阴影裁剪。
	# 覆盖完整地图（包括房间之间空隙），四壁一起分块，低角度太阳仍被封闭。
	var counts := Vector3i(ceili(size_m.x / 20.0), ceili(size_m.y / 20.0), ceili(size_m.z / 20.0))
	var patch_size := size_m / Vector3(counts)
	for x in counts.x:
		for y in counts.y:
			for z in counts.z:
				var mesh := BoxMesh.new()
				mesh.size = patch_size
				mesh.material = material
				var patch := MeshInstance3D.new()
				patch.mesh = mesh
				patch.position = -size_m / 2.0 + patch_size * (Vector3(x, y, z) + Vector3.ONE * 0.5)
				patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				patch.layers = GameDesignConfig.RENDER_LAYER_WORLD
				visual.add_child(patch)
	# 与远征01封顶模块相同：渲染阴影不参与EnemyIllumination的物理查询。
	var body := StaticBody3D.new()
	body.name = "SunOcclusionBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("runtime_owner", "IndoorLightEnvelope")
	visual.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = size_m
	var collider := CollisionShape3D.new()
	collider.name = "SunOcclusionShape"
	collider.shape = shape
	body.add_child(collider)


func _add_room_bounce(room: DungeonRoom3D) -> void:
	# 顶部挡掉直射之后，用室内漫反射维持读图；作者重点灯仍归正式房间TSCN。
	# 放在房间下以继承其流送可见性，保留房间文件无需重存。
	var fill := OmniLight3D.new()
	fill.name = "IndoorEnvelopeBounce"
	fill.position = Vector3(0, 4.0, 0)
	fill.light_color = Color(1.0, 0.86, 0.72)
	var dimensions := room.get_dimensions()
	var extent := maxf(dimensions.x, dimensions.y)
	fill.light_energy = 12.0 if extent >= 40.0 else 6.0 if extent >= 25.0 else 2.0
	fill.omni_range = extent * 1.3
	fill.omni_attenuation = 0.6
	# 顶盖已遮掉太阳，室内主光必须自己投影，否则家具会失去落地阴影。
	fill.shadow_enabled = true
	fill.light_cull_mask = GameDesignConfig.LIGHT_MASK_WORLD_AND_PLAYER
	fill.set_meta("runtime_owner", "IndoorLightEnvelope")
	room.add_child(fill)
	_room_bounces.append(fill)
	room.register_supplemental_room_light(fill)


func _register_authored_lights(room: DungeonRoom3D) -> void:
	for light in room.find_children("*", "Light3D", true, false):
		_register_room_light(light)


func _register_room_light(light: Light3D) -> void:
	if not is_instance_valid(light):
		return
	# 包含后建的FlowPassageFill；Wasteland自有登记/闪烁/品质管理。
	var cursor := light.get_parent()
	while cursor != null:
		if cursor is WastelandLight3D:
			return
		if cursor is DungeonRoom3D:
			cursor.register_supplemental_room_light(light)
			return
		cursor = cursor.get_parent()


func _exit_tree() -> void:
	for fill in _room_bounces:
		if is_instance_valid(fill):
			fill.queue_free()


func get_snapshot() -> Dictionary:
	return {"built": _built, "room_count": _room_count, "bounds": _bounds, "blockers": get_child_count(), "room_bounces": _room_bounces.size(), "ceiling_height_m": ceiling_height_m}
