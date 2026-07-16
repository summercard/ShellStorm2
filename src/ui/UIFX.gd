class_name UIFX
## UIFX — UI 交互动效工具（hover/pressed 缩放、淡入、抖动等）
## 用途：把所有按钮/面板的微交互集中管理，让 UI 有"弹性"
## 所有方法都是静态工具，不持有状态

extends RefCounted


## 给按钮挂上 hover/pressed 缩放反馈
## 1.05x on hover (0.08s), 0.95x on pressed (0.05s), 1.0x on exit/disabled
## 必须在 Button 已经添加到场景树后调用（_ready 之后）
static func attach_button_press(btn: Button, hover_scale: float = 1.05, pressed_scale: float = 0.95) -> void:
	if btn == null:
		return
	# pivot 居中（让缩放看起来自然）
	btn.pivot_offset = btn.size * 0.5
	# 用 meta 标记是否已挂载，避免重复挂
	if btn.has_meta("_uifx_attached"):
		return
	btn.set_meta("_uifx_attached", true)
	# 用 signal 连接代替 mouse_enter/exit 以避免与按钮自身的 focus 冲突
	btn.mouse_entered.connect(_on_btn_mouse_entered.bind(btn, hover_scale))
	btn.mouse_exited.connect(_on_btn_mouse_exited.bind(btn))
	btn.button_down.connect(_on_btn_button_down.bind(btn, pressed_scale))
	btn.button_up.connect(_on_btn_button_up.bind(btn, hover_scale))


static func _on_btn_mouse_entered(btn: Button, hover_scale: float) -> void:
	if btn.disabled:
		return
	_kill_btn_tween(btn)
	btn.pivot_offset = btn.size * 0.5
	var t := btn.create_tween()
	btn.set_meta("_uifx_tween", t)
	t.tween_property(btn, "scale", Vector2.ONE * hover_scale, 0.08)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func _on_btn_mouse_exited(btn: Button) -> void:
	_kill_btn_tween(btn)
	btn.pivot_offset = btn.size * 0.5
	var t := btn.create_tween()
	btn.set_meta("_uifx_tween", t)
	t.tween_property(btn, "scale", Vector2.ONE, 0.10)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func _on_btn_button_down(btn: Button, pressed_scale: float) -> void:
	if btn.disabled:
		return
	_kill_btn_tween(btn)
	btn.pivot_offset = btn.size * 0.5
	var t := btn.create_tween()
	btn.set_meta("_uifx_tween", t)
	t.tween_property(btn, "scale", Vector2.ONE * pressed_scale, 0.05)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


static func _on_btn_button_up(btn: Button, hover_scale: float) -> void:
	if btn.disabled:
		return
	_kill_btn_tween(btn)
	btn.pivot_offset = btn.size * 0.5
	var t := btn.create_tween()
	btn.set_meta("_uifx_tween", t)
	# 如果鼠标还在按钮上，回到 hover 缩放；否则回到 1.0
	var target: float = hover_scale if btn.is_hovered() else 1.0
	t.tween_property(btn, "scale", Vector2.ONE * target, 0.10)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func _kill_btn_tween(btn: Button) -> void:
	if btn.has_meta("_uifx_tween"):
		var old: Tween = btn.get_meta("_uifx_tween")
		if old != null and is_instance_valid(old):
			old.kill()
		btn.remove_meta("_uifx_tween")


## 通用淡入（0.2s）
static func fade_in(node: CanvasItem, duration: float = 0.2) -> void:
	node.modulate.a = 0.0
	var t := node.create_tween()
	t.tween_property(node, "modulate:a", 1.0, duration)


## 通用淡出后 queue_free
static func fade_out_and_free(node: Node, duration: float = 0.2) -> void:
	if node is CanvasItem:
		var t := (node as CanvasItem).create_tween()
		t.tween_property(node, "modulate:a", 0.0, duration)
		t.tween_callback(node.queue_free)
	else:
		node.queue_free()


## 抖动（用于"获得"反馈：金币 +N、拾取物品等）
static func shake(node: CanvasItem, intensity: float = 4.0, duration: float = 0.18) -> void:
	if node == null:
		return
	var origin: Vector2 = node.position
	var t := node.create_tween()
	for i in 6:
		var offset: Vector2 = Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity)
		)
		t.tween_property(node, "position", origin + offset, duration / 6.0)
	t.tween_property(node, "position", origin, 0.01)
