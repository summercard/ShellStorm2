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


## 「棱镜线框」模态面板入场（0.14s）：只做 0.985 → 1.0 的极轻缩放 + 淡入。
## 刻意不用 TRANS_BACK —— 参考图的界面是"切"出来的硬边几何，回弹会破坏它的冷静感。
## 注意：不tween position，面板处在 CenterContainer 里，位置由容器接管会被重置。
static func pop_in_modal(panel: Control, duration: float = 0.14) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var reduce_motion := bool(ProjectSettings.get_setting("accessibility/reduce_motion", false))
	if reduce_motion:
		panel.scale = Vector2.ONE
		panel.modulate.a = 1.0
		return
	panel.pivot_offset = panel.size * 0.5
	if panel.pivot_offset == Vector2.ZERO and panel.custom_minimum_size != Vector2.ZERO:
		panel.pivot_offset = panel.custom_minimum_size * 0.5
	panel.scale = Vector2(0.985, 0.985)
	panel.modulate.a = 0.0
	var t := panel.create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.set_parallel(true)
	t.tween_property(panel, "scale", Vector2.ONE, duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(panel, "modulate:a", 1.0, duration * 0.85)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 子页面切换微过渡（0.10s 纯淡入）。参考图的页间关系是"瞬间替换"，
## 这里只保留一层防闪的极短淡入，不再做上浮位移（位移会与容器布局打架）。
static func switch_page_fade(page: Control, duration: float = 0.10) -> void:
	if page == null or not is_instance_valid(page):
		return
	var reduce_motion := bool(ProjectSettings.get_setting("accessibility/reduce_motion", false))
	if reduce_motion:
		page.modulate.a = 1.0
		return
	page.modulate.a = 0.0
	var t := page.create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(page, "modulate:a", 1.0, duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 「棱镜线框」行错峰入场：一组控件依次 0.965 → 1.0 缩放淡入。
## 对应参考图里选项行自上而下"逐条落位"的观感；纯 scale + alpha，
## 不碰 position，因此放进任何 Container 都安全。
static func prism_stagger_in(rows: Array, step: float = 0.035, duration: float = 0.16) -> void:
	if rows.is_empty():
		return
	var reduce_motion := bool(ProjectSettings.get_setting("accessibility/reduce_motion", false))
	var index := 0
	for row in rows:
		var control := row as Control
		if control == null or not is_instance_valid(control):
			continue
		if reduce_motion:
			control.scale = Vector2.ONE
			control.modulate.a = 1.0
			continue
		control.pivot_offset = control.size * 0.5
		control.scale = Vector2(0.965, 0.965)
		control.modulate.a = 0.0
		var t := control.create_tween()
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		t.set_parallel(true)
		t.tween_interval(float(index) * step)
		t.tween_property(control, "scale", Vector2.ONE, duration)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(control, "modulate:a", 1.0, duration)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		index += 1


## 「棱镜线框」行错峰淡入：只动 alpha，不碰 scale / position。
## 适用于**通栏整行**（900+px 宽）——给整行做缩放会让它在水平方向"抽动"，
## 因此在左栏列表式布局里用这一版替代 prism_stagger_in。
static func prism_fade_stagger(rows: Array, step: float = 0.035, duration: float = 0.16) -> void:
	if rows.is_empty():
		return
	var reduce_motion := bool(ProjectSettings.get_setting("accessibility/reduce_motion", false))
	var index := 0
	for row in rows:
		var control := row as Control
		if control == null or not is_instance_valid(control):
			continue
		if reduce_motion:
			control.modulate.a = 1.0
			continue
		control.modulate.a = 0.0
		var t := control.create_tween()
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		t.tween_interval(float(index) * step)
		t.tween_property(control, "modulate:a", 1.0, duration)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		index += 1


## 棱镜式"线扫"强调：把一条白线从左侧扫到右侧（用于标题条刷新、状态更新确认）。
## 返回的 Tween 由调用方决定是否复用；节点自绘不了就用一个临时 ColorRect。
static func prism_sweep(node: Control, duration: float = 0.32) -> void:
	if node == null or not is_instance_valid(node):
		return
	var sweep := ColorRect.new()
	sweep.name = "PrismSweep"
	sweep.color = Color(1.0, 1.0, 1.0, 0.55)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sweep.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sweep.anchor_left = 0.0
	sweep.anchor_right = 0.0
	sweep.anchor_top = 0.0
	sweep.anchor_bottom = 1.0
	sweep.offset_left = 0.0
	sweep.offset_right = 2.0
	node.add_child(sweep)
	var t := sweep.create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(sweep, "offset_left", node.size.x, duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(sweep, "offset_right", node.size.x + 2.0, duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(sweep.queue_free)


