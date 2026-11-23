class_name VfxDeathBlast3D
extends VfxEffectBase3D
## FX01-17: preserve all authored layers. Enemy3D owns the warning clock and damage.
const SOURCE_CHARGE_SEC := 1.75
const SOURCE_CORE_RADIUS_M := 9.0
const COLOR_CORE := Color(0.80, 0.99, 0.29)
const COLOR_HOT := Color(1.0, 0.97, 0.60)
static var _variants: Dictionary = {}

@onready var _library_burst: Node3D = $LibraryBurst
@onready var _audio: AudioStreamPlayer = $LibraryBurst/UnityAudioSource
var _materials: Array[ShaderMaterial] = []
var _manual_charge := false
var _clip_time := 0.0
var _bounds := Vector4(0.0, 0.0, 0.0, 5.0)

func _ready() -> void:
	_library_burst.hide()
	for layer in _library_burst.get_children():
		# The library adds the ribbon lazily on its first visible frame.
		layer.child_entered_tree.connect(_adapt_draw)
	for node in _library_burst.find_children("*", "GeometryInstance3D", true, false):
		_adapt_draw(node)

func _adapt_draw(node: Node) -> void:
	if not node is GeometryInstance3D:
		return
	var material := (node as GeometryInstance3D).material_override as ShaderMaterial
	if material == null or _materials.has(material):
		return
	var original := material.shader
	if not _variants.has(original):
		var adapted := Shader.new()
		adapted.code = original.code.replace("varying flat float frame_slot;", """varying flat float frame_slot;
			varying vec3 blast_world;
			uniform vec4 blast_center_radius;
			uniform vec4 blast_core : source_color;
			uniform vec4 blast_hot : source_color;""").replace("\n}\n\nvoid fragment()", """
			blast_world = (INV_VIEW_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		}
		void fragment()""").replace("ALBEDO = result.rgb;", """
			float r = length(blast_world.xz - blast_center_radius.xz) / blast_center_radius.w;
			if (r >= 1.0) { discard; }
			result.a *= 1.0 - smoothstep(0.94, 1.0, r);
			float value = max(result.r, max(result.g, result.b));
			ALBEDO = mix(blast_core.rgb, blast_hot.rgb, smoothstep(0.48, 1.0, value)) * value;""")
		_variants[original] = adapted
	material.shader = _variants[original]
	material.set_shader_parameter("blast_core", COLOR_CORE)
	material.set_shader_parameter("blast_hot", COLOR_HOT)
	material.set_shader_parameter("blast_center_radius", _bounds)
	_materials.append(material)

func _on_activate(world_pos: Vector3, _color: Color, _size: float, context: Dictionary) -> void:
	_manual_charge = false
	_clip_time = 0.0
	if bool(context.get("prewarm", false)):
		return
	global_position.y = float(context.get("floor_y", world_pos.y))
	var radius := maxf(0.01, float(context.get("blast_visual_radius_m", 5.0)))
	_library_burst.scale = Vector3.ONE * (radius / SOURCE_CORE_RADIUS_M)
	var origin := _library_burst.global_position
	_bounds = Vector4(origin.x, origin.y, origin.z, radius)
	for material in _materials:
		material.set_shader_parameter("blast_center_radius", _bounds)
	var warning := float(context.get("blast_warning_sec", 0.0))
	_manual_charge = true
	_library_burst.show()
	_library_burst.call("play_exact")
	_library_burst.set_physics_process(false)
	if warning > 0.0:
		var progressed := float(context.get("blast_warning_elapsed_sec", 0.0))
		sync_charge(progressed)
		if progressed > 0.0:
			_audio.play(_clip_time)
	else:
		# No-warning variants jump to the authored impact cue and play its tail.
		detonate()
		_audio.play(SOURCE_CHARGE_SEC)

func sync_charge(elapsed: float) -> void:
	if _manual_charge:
		_audio.stream_paused = false
		# Follow the same clock as the shake at original speed. Hold at the
		# authored cue until gameplay commits, including after a save restore.
		var goal := clampf(elapsed, 1.0 / 60.0, SOURCE_CHARGE_SEC - 0.0001)
		_advance_charge(goal)

func pause_charge_audio() -> void:
	if _manual_charge:
		_audio.stream_paused = true

func detonate() -> void:
	if not _manual_charge:
		return
	_advance_charge(SOURCE_CHARGE_SEC + 0.0001)
	_manual_charge = false
	_audio.stream_paused = false
	_audio.pitch_scale = 1.0
	_library_burst.set_physics_process(true)

func _advance_charge(goal: float) -> void:
	if goal > _clip_time:
		_library_burst.call("advance_exact", goal - _clip_time)
		_clip_time = goal

func _process(_delta: float) -> void:
	if _active and not _manual_charge and not _library_burst.is_physics_processing() and not _audio.playing:
		finish()

func _on_lifetime_expired() -> void:
	_manual_charge = false
	_library_burst.call("stop_exact", true)
	_audio.stream_paused = false
	_audio.pitch_scale = 1.0
	_library_burst.hide()
