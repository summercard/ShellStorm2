class_name PerformanceOverlay
extends PanelContainer
## 0 键开关的只读性能面板。4Hz刷新，避免诊断界面自身制造明显开销。

const UPDATE_INTERVAL := 0.25

var _label: Label
var _accumulator := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 2100
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_left = -350.0
	offset_top = 18.0
	offset_right = -18.0
	offset_bottom = 250.0
	custom_minimum_size = Vector2(332, 232)
	_label = Label.new()
	_label.name = "Metrics"
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.84, 0.94, 1.0))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	UIStyleFactory.apply_tactical_tree(self)


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var key := key_event.keycode if key_event.keycode != 0 else key_event.physical_keycode
	if key not in [KEY_0, KEY_KP_0]:
		return
	visible = not visible
	if visible:
		_refresh_metrics()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_accumulator += delta
	if _accumulator < UPDATE_INTERVAL:
		return
	_accumulator = fmod(_accumulator, UPDATE_INTERVAL)
	_refresh_metrics()


func _refresh_metrics() -> void:
	if _label == null:
		return
	var fps := Engine.get_frames_per_second()
	var viewport_rid := get_viewport().get_viewport_rid()
	var render_cpu := RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
	var render_gpu := RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
	var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var static_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var video_mb := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var aa := str(GraphicsSettingsManager.get_value("anti_aliasing", "off"))
	_label.text = (
		"性能监视  [0 关闭]\n"
		+ "FPS             %d   | 帧预算 %.2f ms\n" % [fps, 1000.0 / maxf(float(fps), 1.0)]
		+ "脚本 / 物理      %.2f / %.2f ms\n" % [process_ms, physics_ms]
		+ "渲染 CPU / GPU   %.2f / %s ms\n" % [render_cpu, _metric_or_na(render_gpu)]
		+ "Draw Call / 对象 %d / %d\n" % [draw_calls, objects]
		+ "节点 / 静态内存  %d / %.1f MB\n" % [nodes, static_mb]
		+ "显存             %s MB\n" % _metric_or_na(video_mb)
		+ "渲染器           %s\n" % GraphicsSettingsManager.get_renderer_summary()
		+ "画质 / 抗锯齿    %s / %s\n" % [RuntimePerformanceManager.quality_profile, aa]
		+ "动态阴影         %s（始终开启）" % GraphicsSettingsManager.get_shadow_quality()
	)
	_label.add_theme_color_override(
		"font_color",
		Color(0.52, 1.0, 0.72) if fps >= 55 else Color(1.0, 0.78, 0.30) if fps >= 40 else Color(1.0, 0.34, 0.30)
	)


func _metric_or_na(value: float) -> String:
	return "N/A" if value <= 0.0 else "%.2f" % value
