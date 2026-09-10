extends Node
## 全屏后处理 overlay autoload：屏幕空间颗粒 + 色相。
## 由 FlashlightColorTweaker P 键面板写入，本节点直接改 ShaderMaterial
## uniform，所有 viewport 同步生效。visible=false 时不渲染（节流）。
##
## 不走 GraphicsSettingsManager 调试钩子——Environment 在 Godot 4.6 里
## 没有 grain_*/hue 属性，本节点是真正能调出效果的途径。

const GRAIN_SHADER_PATH := "res://assets/shaders/postfx_grain.gdshader"

const DEFAULT_GRAIN_ENABLED := false
const DEFAULT_GRAIN_STRENGTH := 0.0
const DEFAULT_GRAIN_SIZE := 1.0
const DEFAULT_HUE_SHIFT := 0.0

var _layer: CanvasLayer
var _color_rect: ColorRect
var _material: ShaderMaterial

var _grain_enabled := DEFAULT_GRAIN_ENABLED
var _grain_strength := DEFAULT_GRAIN_STRENGTH
var _grain_size := DEFAULT_GRAIN_SIZE
var _hue_shift := DEFAULT_HUE_SHIFT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_tree()
	_apply_uniforms()
	_update_visibility()


func _build_tree() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "PostfxOverlayLayer"
	# layer=90 高于 WorldEnvironment，低于 FlashlightTweakerLayer(100)，
	# 这样调参 UI 永远在画面之上，噪点/色相只染色 3D 场景。
	_layer.layer = 90
	add_child(_layer)

	var shader := load(GRAIN_SHADER_PATH) as Shader
	_material = ShaderMaterial.new()
	_material.shader = shader

	_color_rect = ColorRect.new()
	_color_rect.name = "PostfxColorRect"
	_color_rect.anchor_left = 0.0
	_color_rect.anchor_top = 0.0
	_color_rect.anchor_right = 1.0
	_color_rect.anchor_bottom = 1.0
	_color_rect.offset_left = 0.0
	_color_rect.offset_top = 0.0
	_color_rect.offset_right = 0.0
	_color_rect.offset_bottom = 0.0
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color_rect.color = Color(1, 1, 1, 1)
	_color_rect.material = _material
	_layer.add_child(_color_rect)


# ---------- 公开 API ----------

func is_grain_enabled() -> bool:
	return _grain_enabled


func get_grain_strength() -> float:
	return _grain_strength


func get_grain_size() -> float:
	return _grain_size


func get_hue_shift() -> float:
	return _hue_shift


func set_grain_enabled(enabled: bool) -> void:
	_grain_enabled = enabled
	if not enabled:
		# 关掉噪点总开关时同时清零强度，避免“开关 off 但画上还有颗粒”。
		_grain_strength = 0.0
	_update_visibility()
	_apply_uniforms()


func set_grain_strength(strength: float) -> void:
	_grain_strength = clampf(strength, 0.0, 1.0)
	# 只调滑条不开总开关时画面仍然能看到颗粒：避免「开关 off 但画上还有颗粒」。
	if _grain_strength <= 0.0001 and not _grain_enabled:
		_grain_strength = 0.0
	_update_visibility()
	_apply_uniforms()


func set_grain_size(size: float) -> void:
	_grain_size = clampf(size, 0.05, 3.0)
	_apply_uniforms()


func set_hue_shift(shift: float) -> void:
	_hue_shift = clampf(shift, 0.0, 1.0)
	_apply_uniforms()


# 一次性写入所有参数，避免多次 uniform 重传。
func apply_grain(enabled: bool, strength: float, size: float, hue_shift_v: float) -> void:
	_grain_enabled = enabled
	_grain_strength = clampf(strength, 0.0, 1.0)
	_grain_size = clampf(size, 0.05, 3.0)
	_hue_shift = clampf(hue_shift_v, 0.0, 1.0)
	_update_visibility()
	_apply_uniforms()


# 一键复位：关噪点 + hue_shift=0，回到默认。
func reset_to_defaults() -> void:
	_grain_enabled = DEFAULT_GRAIN_ENABLED
	_grain_strength = DEFAULT_GRAIN_STRENGTH
	_grain_size = DEFAULT_GRAIN_SIZE
	_hue_shift = DEFAULT_HUE_SHIFT
	_update_visibility()
	_apply_uniforms()


# 当前是否有任何可见效果（决定 _layer 是否渲染）。
# 噪点必须“总开关 + 强度”同时为真，色相单独看 _hue_shift。
func has_any_effect() -> bool:
	if _grain_enabled and _grain_strength > 0.0001:
		return true
	return _hue_shift > 0.0001


# ---------- 内部 ----------

func _update_visibility() -> void:
	if _layer == null:
		return
	_layer.visible = has_any_effect()


func _apply_uniforms() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("grain_strength", _grain_strength)
	_material.set_shader_parameter("grain_size", _grain_size)
	_material.set_shader_parameter("hue_shift", _hue_shift)