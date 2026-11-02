extends CanvasLayer
## A scene-owned, transient pass below HUD and settlement controls. No save/config writes.

signal finished()

const DURATION := 2.0
const START_DELAY := 2.0
const SHADER := preload("res://assets/shaders/defeat_transition.gdshader")

var elapsed := 0.0
var complete := false
var _material: ShaderMaterial


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 0 # World is on the default canvas; gameplay HUD uses CanvasLayer 1.
	visible = false # Let the character fall before the screen interference begins.
	var rect := ColorRect.new()
	rect.name = "DefeatFilter"
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	rect.material = _material
	add_child(rect)
	_update_uniforms()


func _process(delta: float) -> void:
	if complete:
		return
	elapsed = minf(START_DELAY + DURATION, elapsed + maxf(delta, 0.0))
	visible = elapsed >= START_DELAY
	_update_uniforms()
	if elapsed >= START_DELAY + DURATION:
		complete = true
		finished.emit()


func _update_uniforms() -> void:
	var effect_time := maxf(0.0, elapsed - START_DELAY)
	_material.set_shader_parameter("progress", effect_time / DURATION)
	_material.set_shader_parameter("effect_time", effect_time)
