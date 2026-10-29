@tool
extends SubViewport
## A private world: source instances are never attached to the edited room.

var pivot: Node3D
var camera: Camera3D
var yaw := 0.65
var pitch := 0.42
var distance := 3.8
var source_path := ""

func _init() -> void:
	size = Vector2i(256, 256)
	own_world_3d = true
	transparent_bg = false
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.12, 0.14, 0.17)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.85, 1)
	environment.ambient_light_energy = 0.65
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	for setting in [[Vector3(-45, -35, 0), 2.0], [Vector3(-25, 145, 0), 1.2]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = setting[0]
		light.light_energy = setting[1]
		add_child(light)
	pivot = Node3D.new()
	add_child(pivot)
	camera = Camera3D.new()
	camera.fov = 42
	camera.near = 0.01
	camera.far = 50
	add_child(camera)
	camera.current = true

func show_asset(path: String, source: PackedScene = null) -> bool:
	for child in pivot.get_children():
		child.free()
	source_path = path
	var packed: PackedScene = source if source != null else load(path) as PackedScene
	if packed == null:
		return false
	var instance := packed.instantiate() as Node3D
	if instance == null:
		return false
	sanitize_instance(instance)
	var boxes: Array[AABB] = []
	_bounds(instance, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		instance.free()
		return false
	var box := boxes[0]
	for next in boxes.slice(1):
		box = box.merge(next)
	var extent := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if extent < 0.00001:
		instance.free()
		return false
	var factor := 2.0 / extent
	# Normalize only this disposable instance's parent, preserving imported transforms.
	var wrapper := Node3D.new()
	wrapper.scale = Vector3.ONE * factor
	wrapper.position = -box.get_center() * factor
	preview_reset()
	pivot.add_child(wrapper)
	wrapper.add_child(instance)
	render_target_update_mode = SubViewport.UPDATE_ONCE
	return true

static func sanitize_instance(node: Node) -> void:
	node.set_script(null)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	if node is NavigationRegion3D:
		node.enabled = false
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
		node.autoplay = false
	if node is GPUParticles3D or node is CPUParticles3D:
		node.emitting = false
	if node is Light3D:
		node.visible = false
	if node is Camera3D:
		node.current = false
	for child in node.get_children():
		sanitize_instance(child)

func _bounds(node: Node, parent_transform: Transform3D, boxes: Array[AABB]) -> void:
	var transform := parent_transform
	if node is Node3D:
		transform = parent_transform * node.transform
	if node is MeshInstance3D and node.mesh != null:
		boxes.append(transform * node.mesh.get_aabb())
	elif node is MultiMeshInstance3D and node.multimesh != null:
		boxes.append(transform * node.get_aabb())
	for child in node.get_children():
		_bounds(child, transform, boxes)

func preview_reset() -> void:
	yaw = 0.65
	pitch = 0.42
	distance = 3.8
	update_camera()

func update_camera() -> void:
	camera.position = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	# look_at requires the node to be in a tree, but this local basis does not.
	camera.basis = Basis.looking_at(-camera.position, Vector3.UP)
	render_target_update_mode = SubViewport.UPDATE_ONCE
