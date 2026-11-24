class_name VfxZombieGooDeath3D
extends VfxEffectBase3D
## FX01-19: two intact library scenes; this host owns placement, lighting and timing.
const POOL_RECESSION_START_SEC := 1.35
const POOL_DELAY_SEC := 0.16
const POOL_SOURCE_SEC := 7.0
const POOL_CLOCK := POOL_SOURCE_SEC / (POOL_RECESSION_START_SEC - POOL_DELAY_SEC)
# Last opaque plateau in the imported pool; its original terminal fade is replaced by the host tail.
const POOL_HOLD_SOURCE_SEC := 6.57
const POOL_END_SCALE := 0.12
# Leave 1 mm above the floor, so the depth buffer cannot hard-cut the fade.
const POOL_SINK_M := 0.024
const SPREAD_GAIN := 1.30
const BURST_PARTICLE_GAIN := 2.0
const BODY_SCALE := 0.85 * SPREAD_GAIN
const POOL_SCALE := 1.85 * SPREAD_GAIN
const POOL_INITIAL_RATIO := 0.70
const POOL_TINT := 0.64
const FLOOR_LIFT_M := 0.025
const CALLER_LIFT_M := 0.65
const SEED := 1902
const DROPLET_EMITTER := ^"Source/Droplets/Particle_1"

@export var droplet_size_gain := 1.0
@export var droplet_lifetime_gain := 1.0
@export_range(0.0, 3.0, 0.05) var pool_recession_sec := 0.0

@onready var _burst: Node3D = $LibraryBurst
@onready var _pool: Node3D = $LibraryPool
var _pool_started := false
var _pool_source_time := 0.0
var _pool_rest_position := Vector3.ZERO
var _pool_rest_scale := 1.0
var _pool_tail_tints: Dictionary[ShaderMaterial, Color] = {}
var _pool_tail_batches: Dictionary[MultiMesh, Array] = {}
var _pool_tail_meshes: Dictionary[MeshInstance3D, Transform3D] = {}
var _pool_tail_started := false
var _prewarm := false

func _enter_tree() -> void:
	for scene in [$LibraryBurst, $LibraryPool]:
		for node in scene.find_children("*", "Node3D", true, false):
			if not node.has_method("prepare") or not node.has_method("debug_state"):
				continue
			# Only this instance is lit. Do not edit the imported scene, images or shared runtime.
			var authored: Dictionary = node.get("source")
			var instance := authored.duplicate(false)
			var renderer: Dictionary = authored.renderer.duplicate(true)
			renderer.receive_shadows = true
			for material: Dictionary in renderer.materials:
				material["_LightingEnabled"] = 1.0
				if scene == $LibraryPool:
					var tint: Array = material.get("_Color", [1.0, 1.0, 1.0, 1.0])
					material["_Color"] = [float(tint[0]) * POOL_TINT, float(tint[1]) * POOL_TINT, float(tint[2]) * POOL_TINT, tint[3]]
			instance.renderer = renderer
			if scene == $LibraryPool:
				# Remap the authored growth from [0, 1] to [0.70, 1], including tangents.
				var growth: Dictionary = authored.size_over_lifetime.duplicate(true)
				for keys: Array in [growth.size["keys"], growth.size.curve["keys"]]:
					for key: Dictionary in keys:
						key.v = lerpf(POOL_INITIAL_RATIO, 1.0, float(key.v))
						key["in"] = float(key["in"]) * (1.0 - POOL_INITIAL_RATIO)
						key.out = float(key.out) * (1.0 - POOL_INITIAL_RATIO)
				instance.size_over_lifetime = growth
			else:
				var main: Dictionary = authored.main.duplicate(false)
				var is_droplet: bool = scene.get_path_to(node) == DROPLET_EMITTER
				# The outer transform already accounts for 1.30x of the final particle size.
				var size_gain := BURST_PARTICLE_GAIN / SPREAD_GAIN
				if is_droplet:
					size_gain *= droplet_size_gain
					main.start_lifetime = _scale_curve_values(authored.main.start_lifetime, droplet_lifetime_gain)
				main.start_size = _scale_curve_values(authored.main.start_size, size_gain)
				instance.main = main
			node.set("source", instance)

static func _scale_curve_values(authored: Dictionary, gain: float) -> Dictionary:
	var scaled := authored.duplicate()
	# Imported start_size/start_lifetime use Constant or TwoConstants.
	for field in ["constant", "min", "max"]:
		if scaled.has(field):
			scaled[field] = float(scaled[field]) * gain
	return scaled

func _on_activate(world_pos: Vector3, _color: Color, size: float, context: Dictionary) -> void:
	_prewarm = bool(context.get("prewarm", false))
	lifetime = POOL_RECESSION_START_SEC + (0.0 if _prewarm else pool_recession_sec)
	_reset_pool_tail()
	_pool_started = false
	_pool_source_time = 0.0
	_burst.hide()
	_pool.hide()
	if _prewarm:
		return
	var floor_y := float(context.get("floor_y", world_pos.y - CALLER_LIFT_M))
	_burst.scale = Vector3.ONE * maxf(0.0001, size * BODY_SCALE)
	_pool_rest_scale = maxf(0.0001, size * POOL_SCALE)
	_pool_rest_position = Vector3(world_pos.x, floor_y + FLOOR_LIFT_M, world_pos.z)
	_pool.scale = Vector3.ONE * _pool_rest_scale
	_pool.global_position = _pool_rest_position
	_burst.show()
	_burst.call("play_exact", SEED)

func _on_tick(elapsed: float, _total: float) -> void:
	if _prewarm or elapsed < POOL_DELAY_SEC:
		return
	if not _pool_started:
		_pool_started = true
		_pool.show()
		_pool.call("play_exact", SEED + 1)
		_pool.set_physics_process(false)
		_pool.call("advance_exact", 1.0 / 60.0)
		_pool_source_time = 1.0 / 60.0
		# Keep all six original particles and their curves. Suppress a second cycle only.
		_pool.call("stop_exact", false)
	var source_end := POOL_HOLD_SOURCE_SEC if pool_recession_sec > 0.0 else POOL_SOURCE_SEC
	var goal := minf(source_end, (elapsed - POOL_DELAY_SEC) * POOL_CLOCK)
	if goal > _pool_source_time:
		_pool.call("advance_exact", goal - _pool_source_time)
		_pool_source_time = goal
	if pool_recession_sec > 0.0 and elapsed >= POOL_RECESSION_START_SEC:
		_recede_pool(clampf((elapsed - POOL_RECESSION_START_SEC) / pool_recession_sec, 0.0, 1.0))

func _recede_pool(progress: float) -> void:
	# Freeze the six original draws and scale each basis without moving its own pivot.
	if not _pool_tail_started:
		_pool_tail_started = true
		for node in _pool.find_children("*", "GeometryInstance3D", true, false):
			var draw := node as GeometryInstance3D
			if not draw.visible:
				continue
			if draw is MultiMeshInstance3D:
				var batch: MultiMesh = draw.multimesh
				var transforms: Array[Transform3D] = []
				for i in batch.visible_instance_count:
					transforms.append(batch.get_instance_transform(i))
				_pool_tail_batches[batch] = transforms
			elif draw is MeshInstance3D:
				var mesh := draw as MeshInstance3D
				_pool_tail_meshes[mesh] = mesh.transform
			var material := draw.material_override as ShaderMaterial
			if material != null:
				var tint: Variant = material.get_shader_parameter("tint")
				if tint is Color:
					_pool_tail_tints[material] = tint
	var eased := smoothstep(0.0, 1.0, progress)
	var scale_factor := lerpf(1.0, POOL_END_SCALE, eased)
	for batch in _pool_tail_batches:
		var transforms: Array = _pool_tail_batches[batch]
		for i in transforms.size():
			var at: Transform3D = transforms[i]
			at.basis = at.basis.scaled(Vector3.ONE * scale_factor)
			batch.set_instance_transform(i, at)
	for draw in _pool_tail_meshes:
		var at := _pool_tail_meshes[draw]
		at.basis = at.basis.scaled(Vector3.ONE * scale_factor)
		draw.transform = at
	_pool.global_position = _pool_rest_position - Vector3.UP * (POOL_SINK_M * eased)
	for material in _pool_tail_tints:
		var tint := _pool_tail_tints[material]
		tint.a *= 1.0 - eased
		material.set_shader_parameter("tint", tint)

func _reset_pool_tail() -> void:
	for material in _pool_tail_tints:
		material.set_shader_parameter("tint", _pool_tail_tints[material])
	_pool_tail_tints.clear()
	_pool_tail_batches.clear()
	_pool_tail_meshes.clear()
	_pool_tail_started = false

func _on_lifetime_expired() -> void:
	_reset_pool_tail()
	LibraryVfxAdapter3D.stop_visual(_burst)
	LibraryVfxAdapter3D.stop_visual(_pool)
	_pool_started = false
	_pool_source_time = 0.0
