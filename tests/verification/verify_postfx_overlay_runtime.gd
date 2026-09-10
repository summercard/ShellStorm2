extends Node
## 最小自检：PostfxOverlay autoload 启动后能否通过公开 API 调出可见效果。
## 启动主场景 -> 等 overlay ready -> 切 grain=true / strength=0.5 ->
## 读取 overlay 状态 + ShaderMaterial uniform，断言一致。
## 失败时 process_mode=always 下 quit(code=1)，verify harness 报 fail。

const POSTFX_AUTOLOAD := "PostfxOverlay"

func _ready() -> void:
	var overlay: Node = _resolve_overlay()
	if overlay == null:
		push_error("PostfxOverlay autoload not found")
		get_tree().quit(1)
		return

	overlay.set_grain_enabled(true)
	overlay.set_grain_strength(0.5)
	overlay.set_grain_size(1.5)
	overlay.set_hue_shift(0.25)

	var ok := true
	ok = ok and overlay.is_grain_enabled()
	ok = ok and is_equal_approx(overlay.get_grain_strength(), 0.5)
	ok = ok and is_equal_approx(overlay.get_grain_size(), 1.5)
	ok = ok and is_equal_approx(overlay.get_hue_shift(), 0.25)
	ok = ok and overlay.has_any_effect()

	# 验证 ShaderMaterial uniform 真落到了 shader 端。
	var layer: Node = overlay.get_node_or_null("PostfxOverlayLayer")
	var rect: ColorRect = null
	if layer != null:
		rect = layer.get_node_or_null("PostfxColorRect") as ColorRect
	if rect != null and rect.material != null:
		var mat := rect.material as ShaderMaterial
		ok = ok and is_equal_approx(mat.get_shader_parameter("grain_strength"), 0.5)
		ok = ok and is_equal_approx(mat.get_shader_parameter("grain_size"), 1.5)
		ok = ok and is_equal_approx(mat.get_shader_parameter("hue_shift"), 0.25)
		ok = ok and layer.visible
	else:
		ok = false

	# reset 后应该全部清掉、visible 关闭。
	overlay.reset_to_defaults()
	ok = ok and not overlay.is_grain_enabled()
	ok = ok and is_equal_approx(overlay.get_grain_strength(), 0.0)
	ok = ok and is_equal_approx(overlay.get_hue_shift(), 0.0)
	ok = ok and not overlay.has_any_effect()
	if layer != null:
		ok = ok and not layer.visible

	# “总开关 off → 强度应被强制 0”。这条验证主人反馈的“控制不是分开的”
	# bug：开关关掉时不该还有颗粒。
	overlay.set_grain_strength(0.6)
	overlay.set_grain_enabled(true)
	ok = ok and overlay.has_any_effect()
	overlay.set_grain_enabled(false)
	ok = ok and is_equal_approx(overlay.get_grain_strength(), 0.0)
	ok = ok and not overlay.has_any_effect()
	if layer != null:
		ok = ok and not layer.visible

	# 相反路径：强度 0、开关 off → 开启后强度仍为 0 → 画面无颗粒。
	overlay.set_grain_enabled(true)
	ok = ok and overlay.is_grain_enabled()
	ok = ok and not overlay.has_any_effect() # strength=0

	# 色相与噪点解耦：色相滑动不依赖“启用噪点”。
	overlay.reset_to_defaults()
	overlay.set_hue_shift(0.3)
	ok = ok and overlay.has_any_effect()
	overlay.set_grain_enabled(false) # 不影响 hue
	ok = ok and overlay.has_any_effect()
	overlay.set_hue_shift(0.0)
	ok = ok and not overlay.has_any_effect()

	if ok:
		print("POSTFX_OVERLAY_RUNTIME_OK")
		get_tree().quit(0)
	else:
		push_error("PostfxOverlay state assertions failed")
		get_tree().quit(1)


func _resolve_overlay() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var root := tree.root
	if root == null:
		return null
	return root.get_node_or_null(POSTFX_AUTOLOAD)