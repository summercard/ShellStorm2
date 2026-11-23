class_name PlatformSentinelDeck3D
extends Node3D

const BRIDGE_METAL := preload("res://assets/art/enemies/bosses/enm_boss_platform_sentinel/runtime/materials/machined_metal.tres")
const BRIDGE_LAMP := preload("res://assets/art/enemies/bosses/enm_boss_platform_sentinel/runtime/materials/soft_emission.tres")
const MATTE := preload("res://assets/art/enemies/bosses/enm_boss_platform_sentinel/runtime/materials/matte.tres")
const CLEARCOAT := preload("res://assets/art/enemies/bosses/enm_boss_platform_sentinel/runtime/materials/clearcoat.tres")
const DECK_CLIP := "res://assets/art/enemies/bosses/enm_boss_platform_sentinel/runtime/deck_clips.json"
const REMOVED := [
	"deck_armor_5m", "deck_emblem_5m", "rim_girder_5m", "deck_barrier_5m", "corner_pylon", "underframe_beam_5m",
]
const DECK_PROPS := ["equipment_cluster", "damaged_cabinet_open", "damaged_cabinet_crushed"]
const OUTER_START := 3.8
const OUTER_FALL_DURATION := 4.1
const FINISH := OUTER_START + OUTER_FALL_DURATION
const BRIDGE_TRAVEL := 3.6
const FEED_COLOR_SECONDS := 3.6
const FEED_TEAR_SECONDS := 0.24
const FEED_COLOR_COUNT := 3
const BRIDGE_SLUGS := [
	"bridge_deck_5m", "bridge_rail_5m", "bridge_truss_5m", "bridge_belly_5m",
]

enum SignalPicture { LEGACY, MONITOR, LINK_LOST, RISING, ONLINE, OUTER_WARNING, OUTER_RELEASE, SAFE }

@export var red_black := true
@export var rear_screen_travel := 0.0
@export var rear_screen_parts: Array[NodePath] = []
@export var rear_screen_chassis: Array[NodePath] = []

var tiles: Array[Node3D] = []
var stairs: Array[Node3D] = []
var _stair_surfaces: Array[StaticBody3D] = []
var _walk: Node3D
@onready var _exit_bridge: AnimatableBody3D = $EastBridgeExtension
var _extension_rails: Array[StaticBody3D] = []
var _tile_mounts: Dictionary[StringName, Node3D] = {}
var _side_bridges: Array[StaticBody3D] = []
var _bridge_visuals: Array[Node3D] = []
var _collapse: Dictionary
var _rear_rest: Dictionary[Node3D, Vector3] = {}
var _rear_tween: Tween
var _rear_displays: Array[Node3D] = []
var _feed_faces: Array[MeshInstance3D] = []
var _feed := Vector2.ZERO
var _lift_fascias: Dictionary[Node3D, Vector3] = {}
var _gun_alert := 0.0
var _arm_tile_clocks: Dictionary[StringName, float] = {}
const ARM_TILE_WARNING_SECONDS := 0.85
const ARM_TILE_FALL_SECONDS := 0.92
const ARM_TILE_FINISH := ARM_TILE_WARNING_SECONDS + ARM_TILE_FALL_SECONDS

func _enter_tree() -> void:
	var arena := get_parent().get_parent().get_node("BossRoom02")
	arena.get_node("WalkSurfaceCollision/BossRoom02WalkSurface").collision_layer = 0
	for piece in arena.get_node("Components").get_children():
		var slug := str(piece.get_meta("slug", ""))
		var on_deck: bool = absf(piece.position.x) <= 12.5 and piece.position.z >= -35.0 and piece.position.z <= -10.0
		if slug in REMOVED or (on_deck and slug in DECK_PROPS):
			piece.free()
		elif slug == "hanging_power_bundle":
			piece.position.x = signf(piece.position.x) * (absf(piece.position.x) + 14.0)
		elif slug in ["stair_flight_5m", "stair_chase_light", "stair_pillar_light"] and piece.position.z < 0.0:
			stairs.append(piece)
		elif absf(piece.position.z + 22.5) < 3.0 and _is_moving_bridge_piece(piece, slug):
			_bridge_visuals.append(piece)


func _is_moving_bridge_piece(piece: Node3D, slug: String) -> bool:
	var x := absf(piece.position.x)
	return (slug in BRIDGE_SLUGS and x > 12.49) or (slug == "bridge_threshold" and absf(x - 12.5) < 0.05)


func _ready() -> void:
	var arena := get_parent().get_parent().get_node("BossRoom02")
	(arena.get_node("ArenaGate") as BossRoom02ArenaGate3D).set_platform_barriers_enabled(false)
	for path in rear_screen_parts + rear_screen_chassis:
		var node := arena.get_node(path) as Node3D
		_rear_rest[node] = node.position
		if node.has_method("set_signal_picture") and node.get("screen_material") != null:
			_rear_displays.append(node)
	set_rear_signal(SignalPicture.MONITOR)
	for path in rear_screen_chassis:
		# The v027 screen shells were visual-only; keep their new physical backing
		# attached to the same transform as the visual (including the authored tilt).
		var chassis := arena.get_node(path) as Node3D
		var body := StaticBody3D.new()
		body.name = "MovingScreenBacking"
		body.collision_mask = 0
		var bounds := BoxShape3D.new()
		bounds.size = Vector3(11.0, 7.0, 1.68)
		var shape := CollisionShape3D.new()
		shape.position = Vector3(0, 3.5, 0)
		shape.shape = bounds
		body.add_child(shape)
		chassis.add_child(body)
	# One palette selection for this boss's four shared resources. The slot is
	# changed only when its arena is loaded, and keeps the source meshes shared.
	for material in [BRIDGE_METAL, MATTE, CLEARCOAT, BRIDGE_LAMP]:
		material.set_shader_parameter("red_black", 1.0 if red_black else 0.0)
	_walk = Node3D.new()
	_walk.name = "SegmentedWalkSurface"
	add_child(_walk)
	# Coordinates here are platform-local. The original hall's entry was z=-10.
	_side_bridges.append(_ramp(-32.6, -12.49, -2.5, 2.5, 0.0, 0.0, true))
	_side_bridges.append(_ramp(12.49, 32.6, -2.5, 2.5, 0.0, 0.0, true))
	_ramp(-40.0, -32.5, -2.5, 2.5, 0.0, 0.0)
	_ramp(32.5, 40.0, -2.5, 2.5, 0.0, 0.0)
	for piece in _bridge_visuals:
		piece.reparent(_side_bridges[0 if to_local(piece.global_position).x < 0.0 else 1], true)
	_exit_bridge.reparent(_side_bridges[1], true)
	# The room can reactivate imported shapes during streaming. This extension
	# already has its own walk surface, so discard the inherited duplicate.
	_exit_bridge.get_node("Grating/CollisionBody").free()
	for name in ["RailNorth", "RailSouth"]:
		var rail := _exit_bridge.get_node(name + "/CollisionBody") as StaticBody3D
		rail.collision_layer = 0
		_extension_rails.append(rail)
	_stair_surfaces.append(_ramp(-2.5, 2.5, 12.06, 12.5, 0.0, 0.105))
	_stair_surfaces.append(_ramp(-2.5, 2.5, 12.5, 17.5, 0.105, 1.305))
	_stair_surfaces.append(_ramp(-2.5, 2.5, 17.5, 22.5, 1.305, 2.505))
	_ramp(-2.5, 2.5, 22.5, 62.5, 2.505, 12.105)
	_ramp(-2.5, 2.5, 62.5, 63.5, 12.105, 11.965)
	_ramp(-2.5, 2.5, 63.5, 72.5, 11.965, 11.965)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DECK_CLIP))
	if parsed is Dictionary:
		_collapse = parsed.get("tiles", {})
	for tile: Node3D in $PlatformSentinel.get_children():
		tiles.append(tile)
		_tile_mounts[tile.name] = tile
		tile.set_meta("rest", tile.transform)
		var floor := _ramp(tile.position.x - 2.5, tile.position.x + 2.5, tile.position.z - 2.5, tile.position.z + 2.5, 0.0, 0.0)
		tile.set_meta("floor", floor)
		var sectors: Array[Node3D] = []
		for i in range(4):
			var sector := Node3D.new()
			sector.name = "Underframe_%02d" % (i + 1)
			tile.add_child(sector)
			sectors.append(sector)
		tile.set_meta("sectors", sectors)
		for part: Node3D in tile.get_children():
			if part.name.begins_with("Fascia_"):
				_lift_fascias[part] = part.position
			for value in part.find_children("*", "MeshInstance3D", true, false):
				var mesh := value as MeshInstance3D
				if mesh.name.contains("Corner") and mesh.name.ends_with("_Emissive"):
					if tile.name == &"Tile_03_03":
						mesh.hide()
					else:
						# Adjacent indicators also meet at the four center seams.
						mesh.position.y += 0.006
				if mesh.name.ends_with("Screen_Emissive"):
					mesh.set_instance_shader_parameter("canvas_center", Vector2(tile.position.x, tile.position.z) / 25.0 + Vector2(0.5, 0.5))
					tile.set_meta("screen", mesh)
					_feed_faces.append(mesh)
				if mesh.name.contains("Sector_"):
					var id := int(str(mesh.name).get_slice("Sector_", 1).left(2)) - 1
					if id >= 0 and id < 4:
						id = posmod(id + roundi(part.rotation.y / (PI * 0.5)), 4)
						mesh.reparent(sectors[id])
	sample_launch_lift(0.0)


func set_rear_signal(picture: SignalPicture, burst := false) -> void:
	for slot in range(_rear_displays.size()):
		_rear_displays[slot].call("set_signal_picture", picture, slot, burst)


func set_rear_screen_retraction(retracted: bool, animate := false) -> void:
	if _rear_tween != null:
		_rear_tween.kill()
		_rear_tween = null
	if animate:
		_rear_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	for node in _rear_rest:
		var destination := _rear_rest[node] + Vector3.FORWARD * (rear_screen_travel if retracted else 0.0)
		if animate:
			_rear_tween.tween_property(node, "position", destination, 1.45)
		else:
			node.position = destination


func rear_screens_are_retracted() -> bool:
	for node in _rear_rest:
		if not node.position.is_equal_approx(_rear_rest[node] + Vector3.FORWARD * rear_screen_travel):
			return false
	return true


# Cosmetic outer lift housings follow the launch, not the walkable deck or its colliders.
func sample_launch_lift(elapsed: float) -> void:
	var lift := -1.25 * (1.0 - smoothstep(0.18, 2.65, elapsed))
	for fascia in _lift_fascias:
		fascia.position = _lift_fascias[fascia] + Vector3.UP * lift


# The existing encounter clock gates the presentation; it never reads this material back.
func sample_combat_feed(elapsed: float) -> void:
	var within := fposmod(elapsed, FEED_COLOR_SECONDS)
	var progress := clampf((within - FEED_COLOR_SECONDS + FEED_TEAR_SECONDS) / FEED_TEAR_SECONDS, 0.0, 1.0)
	var burst := smoothstep(0.0, 0.38, progress)
	var palette := posmod(floori(elapsed / FEED_COLOR_SECONDS), FEED_COLOR_COUNT)
	_set_combat_feed(Vector2(palette, burst))


func clear_combat_feed() -> void:
	_set_combat_feed(Vector2.ZERO)


func _set_combat_feed(value: Vector2) -> void:
	if _feed == value:
		return
	_feed = value
	for face in _feed_faces:
		face.set_instance_shader_parameter("deck_feed", value)


func set_screens(phase: float, power := 1.0) -> void:
	for tile in tiles:
		_set_screen(tile, phase, power, 0.0, 0.0)

func _set_screen(tile: Node3D, phase: float, power: float, tear: float, scroll: float) -> void:
	var screen := tile.get_meta("screen", null) as MeshInstance3D
	if screen != null:
		screen.set_instance_shader_parameter("phase", phase)
		screen.set_instance_shader_parameter("power", power)
		screen.set_instance_shader_parameter("tear", tear)
		screen.set_instance_shader_parameter("scroll", scroll)

func break_stairs(animated: bool) -> void:
	for floor in _stair_surfaces:
		floor.set_deferred("collision_layer", 0)
	for piece in stairs:
		for collider in piece.find_children("*", "CollisionObject3D", true, false):
			collider.set_deferred("collision_layer", 0)
		if not animated:
			piece.hide()
			continue
		var tween := create_tween().set_parallel()
		tween.tween_property(piece, "position", piece.position + Vector3(0.0, -29.0, -2.2), 1.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(piece, "rotation", piece.rotation + Vector3(0.75, 0.12, 0.18), 1.32)
		tween.chain().tween_callback(piece.hide)
	stairs.clear()

func set_center_screen(phase: float, power: float) -> void:
	for tile in tiles:
		if (tile.get_meta("rest") as Transform3D).origin.length_squared() < 0.01:
			_set_screen(tile, phase, power, 0.0, 0.0)
			return


func wake_screens(elapsed: float) -> void:
	for tile in tiles:
		var origin: Vector3 = (tile.get_meta("rest") as Transform3D).origin
		var delay := maxf(absf(origin.x), absf(origin.z)) * 0.061
		_set_screen(tile, 0.0, clampf((elapsed - delay) * 2.75, 0.0, 1.0), 0.0, 0.0)


func sample_collapse(elapsed: float, outer_start := OUTER_START) -> Array[Vector3]:
	var releases: Array[Vector3] = []
	for tile in tiles:
		var original: Transform3D = tile.get_meta("rest")
		if _arm_tile_clocks.has(tile.name):
			continue
		var side := maxf(absf(original.origin.x), absf(original.origin.z))
		if side <= 7.5:
			continue
		var offset := outer_start
		if elapsed < offset:
			var blink := 0.77 + 0.22 * sin(elapsed * 13.0 + side)
			var shake := smoothstep(offset - 2.1, offset - 0.12, elapsed)
			var phase := elapsed * 37.0 + original.origin.x * 1.41 + original.origin.z * 0.83
			tile.transform = original * Transform3D(Basis.from_euler(Vector3(sin(phase), 0.0, cos(phase * 1.13)) * shake * 0.019), Vector3(0.0, sin(phase * 1.76) * shake * 0.06, 0.0))
			_set_screen(tile, 1.0, blink, 0.018 + shake * 0.06, elapsed * 0.012)
			continue
		var clip: Dictionary = _collapse.get(str(tile.name).to_lower(), {})
		var frames: Array = clip.get("frames", [])
		if frames.is_empty():
			continue
		var sample := clampf((elapsed - offset) * 15.0, 0.0, frames.size() - 1.0)
		var i := floori(sample)
		var at: Array = frames[i]
		var next: Array = frames[mini(i + 1, frames.size() - 1)]
		var blend := sample - i
		tile.transform = original * _frame_transform(at[0][0]).interpolate_with(_frame_transform(next[0][0]), blend)
		var sectors: Array = tile.get_meta("sectors")
		for s in range(4):
			sectors[s].transform = _frame_transform(at[0][s + 1]).interpolate_with(_frame_transform(next[0][s + 1]), blend)
		_set_screen(tile, at[1][0], at[1][3], at[1][2], -float(at[1][1]))
		if tile.position.y < -0.09:
			var floor: StaticBody3D = tile.get_meta("floor")
			if floor.collision_layer != 0:
				floor.collision_layer = 0
				var seam := Vector3(-2.36 * signf(original.origin.x), 0.08, -1.9 * signf(original.origin.z))
				releases.append(to_global(original.origin + seam))
		if tile.position.y < -24.0:
			tile.hide()
	return releases


func is_outer_arm_tile(tile_name: StringName) -> bool:
	var tile := _tile_mounts.get(tile_name, null) as Node3D
	if tile == null:
		return false
	var origin: Vector3 = (tile.get_meta("rest") as Transform3D).origin
	return maxf(absf(origin.x), absf(origin.z)) > 7.5


func begin_arm_tile_drop(tile_name: StringName) -> void:
	if not _arm_tile_clocks.has(tile_name):
		_sample_arm_tile(tile_name, 0.0)


func drop_arm_tile(tile_name: StringName, delta: float) -> Vector3:
	var previous := get_arm_tile_drop_elapsed(tile_name)
	if previous >= ARM_TILE_FINISH:
		return Vector3.INF
	var elapsed := minf(ARM_TILE_FINISH, previous + delta)
	var tile := _sample_arm_tile(tile_name, elapsed)
	if previous < ARM_TILE_WARNING_SECONDS and elapsed >= ARM_TILE_WARNING_SECONDS:
		var rest: Transform3D = tile.get_meta("rest")
		return to_global(rest.origin + Vector3.UP * 0.08)
	return Vector3.INF


func get_arm_tile_drop_elapsed(tile_name: StringName) -> float:
	return _arm_tile_clocks.get(tile_name, 0.0)


func clear_arm_tile_drops() -> void:
	for tile_name in _arm_tile_clocks:
		var tile: Node3D = _tile_mounts[tile_name]
		var floor: StaticBody3D = tile.get_meta("floor")
		floor.collision_layer = 1
		tile.transform = tile.get_meta("rest")
		tile.show()
	_arm_tile_clocks.clear()


func restore_arm_tile_state(tile_name: StringName, elapsed: float) -> void:
	_sample_arm_tile(tile_name, clampf(elapsed, 0.0, ARM_TILE_FINISH))


func _sample_arm_tile(tile_name: StringName, elapsed: float) -> Node3D:
	var tile: Node3D = _tile_mounts[tile_name]
	var rest: Transform3D = tile.get_meta("rest")
	var floor: StaticBody3D = tile.get_meta("floor")
	var previous := get_arm_tile_drop_elapsed(tile_name)
	if not _arm_tile_clocks.has(tile_name) or (previous < ARM_TILE_WARNING_SECONDS and elapsed >= ARM_TILE_WARNING_SECONDS):
		floor.set_deferred("collision_layer", 1 if elapsed < ARM_TILE_WARNING_SECONDS else 0)
	_arm_tile_clocks[tile_name] = elapsed
	if elapsed < ARM_TILE_WARNING_SECONDS:
		var shake := smoothstep(0.0, ARM_TILE_WARNING_SECONDS, elapsed)
		var phase := elapsed * 42.0 + rest.origin.x * 1.41 + rest.origin.z * 0.83
		var tilt := Vector3(sin(phase), 0.0, cos(phase * 1.13)) * shake * 0.025
		tile.transform = rest * Transform3D(Basis.from_euler(tilt), Vector3.UP * sin(phase * 1.76) * shake * 0.07)
		_set_screen(tile, 1.0, 0.78 + 0.20 * sin(elapsed * 16.0), 0.08, elapsed * 0.05)
	else:
		var eased := smoothstep(ARM_TILE_WARNING_SECONDS, ARM_TILE_FINISH, elapsed)
		tile.transform = rest * Transform3D(Basis.from_euler(Vector3(0.12, -0.08, 0.18) * eased), Vector3.DOWN * 9.0 * eased)
		_set_screen(tile, 2.0, 1.0 - eased, 0.16, elapsed * 0.05)
	tile.visible = elapsed < ARM_TILE_FINISH
	return tile


func set_bridge_retraction(west: float, east: float) -> void:
	_side_bridges[0].position.x = -BRIDGE_TRAVEL * west
	_side_bridges[1].position.x = BRIDGE_TRAVEL * east

func _frame_transform(row: Array) -> Transform3D:
	return Transform3D(Basis(Quaternion(row[3], row[4], row[5], row[6]).normalized()), Vector3(row[0], row[1], row[2]))

func sample_return_bridge(amount: float) -> void:
	var progress := clampf(amount, 0.0, 1.0)
	set_bridge_retraction(1.0, 1.0 - progress)
	_exit_bridge.show()
	_exit_bridge.position = Vector3(10.0 + 5.0 * (1.0 - progress), -0.52 * (1.0 - progress), 0.0)
	var layer := 1 if progress >= 1.0 else 0
	_exit_bridge.collision_layer = layer
	for rail in _extension_rails:
		rail.collision_layer = layer


func open_return_bridge() -> void:
	sample_return_bridge(1.0)


func sample_sentry_mounts(sentries: Array[PlatformSentinelUnit3D]) -> void:
	for rack in sentries:
		var tile := _tile_mounts[rack.mount_tile]
		var rest: Transform3D = tile.get_meta("rest")
		rack.transform = tile.transform * rest.affine_inverse() * rack.installed_transform
		rack.visible = tile.visible


func set_gun_alert(strength: float) -> void:
	if is_equal_approx(_gun_alert, strength):
		return
	_gun_alert = strength
	for face in _feed_faces:
		face.set_instance_shader_parameter("gun_alert", strength)


static func palette_mesh(primitive: PrimitiveMesh, swatch: Vector2) -> ArrayMesh:
	var arrays := primitive.get_mesh_arrays()
	var palette_uv := PackedVector2Array()
	palette_uv.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	palette_uv.fill(swatch)
	arrays[Mesh.ARRAY_TEX_UV] = palette_uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _ramp(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, moving := false) -> StaticBody3D:
	var a := Vector3(x0, y0, z0)
	var b := Vector3(x1, y0, z0)
	var c := Vector3(x1, y1, z1)
	var d := Vector3(x0, y1, z1)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(PackedVector3Array([a, b, c, a, c, d]))
	var node := CollisionShape3D.new()
	node.shape = shape
	var body := AnimatableBody3D.new() if moving else StaticBody3D.new()
	if body is AnimatableBody3D:
		(body as AnimatableBody3D).sync_to_physics = false
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_child(node)
	_walk.add_child(body)
	return body
