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
const INNER_START := 9.0
const FINISH := 13.1
const BRIDGE_TRAVEL := 3.6
const BRIDGE_SLUGS := [
	"bridge_deck_5m", "bridge_rail_5m", "bridge_truss_5m", "bridge_belly_5m",
]

@export var red_black := true

var tiles: Array[Node3D] = []
var grapples: Array[Node3D] = []
var sentries: Array[Node3D] = []
var stairs: Array[Node3D] = []
var _stair_surfaces: Array[StaticBody3D] = []
var _walk: Node3D
var _exit_bridge: StaticBody3D
var _side_bridges: Array[StaticBody3D] = []
var _bridge_visuals: Array[Node3D] = []
var _collapse: Dictionary

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
		for part in tile.get_children():
			if part.name.begins_with("Grapple_"):
				grapples.append(part)
				play(part, "activate_grapple", 0.0, 0.0)
			elif part.name.begins_with("Sentry_"):
				sentries.append(part)
				play(part, "activate_sentry", 0.0, 0.0)
			elif part.name.begins_with("Rail_"):
				var rail := StaticBody3D.new()
				rail.collision_mask = 0
				var collider := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(4.72, 1.08, 0.16)
				collider.shape = box
				collider.position.y = 0.54
				rail.add_child(collider)
				part.add_child(rail)
			for value in part.find_children("*", "MeshInstance3D", true, false):
				var mesh := value as MeshInstance3D
				if mesh.name.ends_with("Screen_Emissive"):
					mesh.set_instance_shader_parameter("canvas_center", Vector2(tile.position.x, tile.position.z) / 25.0 + Vector2(0.5, 0.5))
					tile.set_meta("screen", mesh)
				if mesh.name.contains("Sector_"):
					var id := int(str(mesh.name).get_slice("Sector_", 1).left(2)) - 1
					if id >= 0 and id < 4:
						id = posmod(id + roundi(part.rotation.y / (PI * 0.5)), 4)
						mesh.reparent(sectors[id])
	grapples.sort_custom(func(a: Node3D, b: Node3D) -> bool: return str(a.name) < str(b.name))
	sentries.sort_custom(func(a: Node3D, b: Node3D) -> bool: return str(a.name) < str(b.name))

func play(unit: Node3D, clip: StringName, speed := 1.0, at := 0.0) -> void:
	var anim := unit.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim == null or not anim.has_animation(clip):
		push_error("Platform Sentinel missing clip %s/%s" % [unit.name, clip])
		return
	if str(clip).begins_with("idle_"):
		anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	anim.play(clip, 0.12 if speed > 0.0 else 0.0, speed)
	anim.seek(at, true)
	anim.advance(0.0)
	sync_skeleton(unit)


func skeleton_for(unit: Node3D) -> Skeleton3D:
	var found := unit.find_child("Skeleton3D", true, false) as Skeleton3D
	if found != null:
		return found
	for child in unit.find_children("*", "Skeleton3D", true, false):
		return child as Skeleton3D
	return null


func delay_animation(unit: Node3D, seconds: float) -> void:
	if seconds <= 0.0:
		return
	var anim := unit.find_child("AnimationPlayer", true, false) as AnimationPlayer
	anim.speed_scale = 0.0
	create_tween().tween_callback(func() -> void: anim.speed_scale = 1.0).set_delay(seconds)


func sync_skeleton(unit: Node3D) -> void:
	var skeleton := skeleton_for(unit)
	if skeleton == null:
		return
	skeleton.force_update_all_bone_transforms()
	for attachment in skeleton.get_children():
		if attachment is BoneAttachment3D and attachment.bone_idx >= 0:
			attachment.transform = skeleton.get_bone_global_pose(attachment.bone_idx)

func socket(unit: Node3D, key: String) -> Node3D:
	return unit.find_child("*__" + key, true, false) as Node3D

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


func sample_collapse(elapsed: float, outer_start := OUTER_START, inner_start := INNER_START) -> Array[Vector3]:
	var releases: Array[Vector3] = []
	for tile in tiles:
		var original: Transform3D = tile.get_meta("rest")
		var side := maxf(absf(original.origin.x), absf(original.origin.z))
		if side < 0.1:
			continue
		var outer := side > 7.5
		var offset := outer_start if outer else inner_start
		if elapsed < offset:
			var blink := 0.77 + 0.22 * sin(elapsed * 13.0 + side)
			var shake := smoothstep(offset - 2.1, offset - 0.12, elapsed)
			var phase := elapsed * 37.0 + original.origin.x * 1.41 + original.origin.z * 0.83
			tile.transform = original * Transform3D(Basis.from_euler(Vector3(sin(phase), 0.0, cos(phase * 1.13)) * shake * 0.019), Vector3(0.0, sin(phase * 1.76) * shake * 0.06, 0.0))
			_set_screen(tile, 1.0 if outer else 2.0, blink, 0.018 + shake * 0.06, elapsed * 0.012)
			continue
		var clip: Dictionary = _collapse.get(str(tile.name).to_lower(), {})
		var frames: Array = clip.get("frames", [])
		if frames.is_empty():
			continue
		var sample := clampf((elapsed - offset) * 15.0 + (0.0 if outer else 40.0), 0.0, frames.size() - 1.0)
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


func set_bridge_retraction(west: float, east: float) -> void:
	_side_bridges[0].position.x = -BRIDGE_TRAVEL * west
	_side_bridges[1].position.x = BRIDGE_TRAVEL * east

func _frame_transform(row: Array) -> Transform3D:
	return Transform3D(Basis(Quaternion(row[3], row[4], row[5], row[6]).normalized()), Vector3(row[0], row[1], row[2]))

func open_return_bridge() -> void:
	if is_instance_valid(_exit_bridge):
		return
	set_bridge_retraction(1.0, 0.0)
	_exit_bridge = _ramp(2.48, 12.52, -1.40, 1.40, 0.0, 0.0)
	for i in range(5):
		var mesh := MeshInstance3D.new()
		var slab := BoxMesh.new()
		slab.size = Vector3(2.025, 0.27, 2.8)
		mesh.mesh = palette_mesh(slab, Vector2(0.95, 0.85))
		mesh.material_override = BRIDGE_METAL
		mesh.position = Vector3(3.5 + 2.0 * i, -0.135, 0.0)
		_exit_bridge.add_child(mesh)
		for edge in [-1.36, 1.36]:
			var lamp := MeshInstance3D.new()
			var strip := BoxMesh.new()
			strip.size = Vector3(1.7, 0.025, 0.055)
			lamp.mesh = palette_mesh(strip, Vector2(0.45, 0.25))
			lamp.material_override = BRIDGE_LAMP
			lamp.position = Vector3(3.5 + 2.0 * i, 0.0125, edge)
			_exit_bridge.add_child(lamp)

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
