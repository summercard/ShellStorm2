extends Node
## 头顶对话气泡验收：气泡本体 + 文案目录 + 角色挂载 + 灯开关接线。
## 不加载剧情系统、不加载关卡，纯组件级验证。
##
## 判据说明（"全程对着摄像机、不随角色转动"怎么被机器验证）：
##   ① 朝向：底板材质与 Label3D 的 billboard 都必须是 BILLBOARD_ENABLED ——
##      朝向由渲染层按摄像机求解，不依赖父节点旋转；
##   ② 位置：挂载偏移只含垂直分量 —— 角色绕 Y 轴转身后气泡世界坐标不得变化。
##   两条都断言，不使用"节点存在"这类假绿判据。

const BARK_LAMP_ON := BarkCatalog.BARK_LAMP_ON
const BUBBLE_NODE_NAME := "SpeechBubble"
const BARK_NODE_NAME := "CharacterBark3D"

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	var stage := Node3D.new()
	stage.name = "Stage"
	add_child(stage)

	_check_bubble_basics(stage)
	_check_text_scaling(stage)
	_check_typewriter(stage)
	await _check_facing_camera(stage)
	await _check_vertical_offset_only(stage)
	await _check_follows_parent_motion(stage)
	_check_catalog()
	_check_character_bark(stage)
	_check_light_switch_wiring()
	_finish()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _make_bubble(stage: Node3D, name_suffix: String) -> SpeechBubble3D:
	var bubble := SpeechBubble3D.new()
	bubble.name = "Bubble" + name_suffix
	stage.add_child(bubble)
	return bubble


func _check_bubble_basics(stage: Node3D) -> void:
	var bubble := _make_bubble(stage, "Basics")
	_expect(bubble.get_node_or_null("Panel") != null, "气泡缺少 Panel 节点")
	_expect(bubble.get_node_or_null("Text") != null, "气泡缺少 Text 节点")
	_expect(not bubble.is_bubble_active(), "新建气泡默认不应处于激活态")

	bubble.say("灯亮了。", 30.0)
	_expect(bubble.is_bubble_active(), "say() 之后气泡未进入激活态")
	_expect(bubble.get_bubble_text() == "灯亮了。", "气泡文本与传入不一致")
	_expect(bubble.visible, "说话时气泡节点不可见")

	bubble.say("   ", 30.0)
	_expect(not bubble.is_bubble_active(), "空白文本不应驱动气泡（应被忽略）")

	bubble.hide_bubble()
	_expect(not bubble.is_bubble_active(), "hide_bubble() 之后仍处于激活态")


## 打字机（业主 2026-11-08：对话文字要打字机一样顺序出现）。
##
## 手动步进 `_process(delta)` 而不是等真实时间：headless 下帧率不受控，
## 用 `create_timer` 等出来的可见字数会随机 —— 那种断言只能证明"最后会全显"，
## 证明不了"是一字一字出来的"。这里用固定 delta 精确对齐每一档字数。
func _check_typewriter(stage: Node3D) -> void:
	var bubble := _make_bubble(stage, "Typewriter")
	# 关掉引擎自动 `_process`：本段全靠手动步进，否则真实帧也在推进，
	# 每次读数都会多出"这一帧打了几个字"，分档断言变成随机红。
	bubble.set_process(false)
	bubble.chars_per_sec = 20.0
	bubble.typewriter_enabled = true
	bubble.hold_seconds = 0.4
	# 7 个字，20 字/秒 ⇒ 0.1s 一格正好 2 个字，0.4s 打完。
	const LINE := "打字机效果测试"
	_expect(LINE.length() == 7, "打字机测试句长度变了（%d），后续分档断言要同步" % LINE.length())

	bubble.say(LINE, 0.4)
	_expect(bubble.is_typing(), "say() 之后没有进入打字机状态")
	_expect(bubble.get_visible_char_count() == 0, "第一帧之前就已经显示了字")
	_expect(bubble.get_total_char_count() == LINE.length(), "总字数与句子不符")
	# 尺寸按整句算：打字过程中底板就是最终宽度（否则每打一个字都跳一下）。
	var full_width := bubble.get_bubble_width_m()

	bubble._process(0.1)
	_expect(bubble.get_visible_char_count() == 2, "0.1s @20字/秒 应显示 2 字，实际 %d" % bubble.get_visible_char_count())
	_expect(is_equal_approx(bubble.get_bubble_width_m(), full_width), "打字过程中气泡宽度变了（应一次到位）")
	bubble._process(0.1)
	var mid_count := bubble.get_visible_char_count()
	_expect(mid_count == 4, "0.2s 应显示 4 字，实际 %d" % mid_count)
	_expect(bubble.is_typing(), "打到一半就退出了打字机状态")
	# 停留计时不该在打字期间偷跑：hold 只有 0.4s，打了 0.2s 仍必须活着。
	_expect(bubble.is_bubble_active(), "打字期间停留计时提前把气泡关掉了")

	bubble._process(0.1)
	bubble._process(0.1)
	_expect(not bubble.is_typing(), "打完 7 字后仍处于打字机状态")
	_expect(bubble.get_visible_char_count() == LINE.length(), "打完后没有全显：%d/%d" % [
		bubble.get_visible_char_count(), LINE.length()
	])
	_expect(bubble.is_bubble_active(), "打字刚结束气泡就消失了（停留计时起算点不对）")

	# 跳过打字机：立刻全显。
	bubble.say(LINE, 4.0)
	_expect(bubble.is_typing(), "第二次 say() 没有重新开始打字")
	bubble.reveal_all()
	_expect(not bubble.is_typing(), "reveal_all() 之后仍在打字")
	_expect(bubble.get_visible_char_count() == LINE.length(), "reveal_all() 没有全显")

	# 关掉打字机 ⇒ 一次性全出。
	bubble.typewriter_enabled = false
	bubble.say(LINE, 4.0)
	_expect(not bubble.is_typing(), "关掉打字机后仍逐字显示")
	_expect(bubble.get_visible_char_count() == LINE.length(), "关掉打字机后没有一次全显")

	# 速度为 0 也等于关掉（避免出现"配 0 就永远打不完"的死状态）。
	bubble.typewriter_enabled = true
	bubble.chars_per_sec = 0.0
	bubble.say(LINE, 4.0)
	_expect(not bubble.is_typing(), "速度为 0 时仍进入打字机状态")
	bubble.chars_per_sec = SpeechBubble3D.DEFAULT_CHARS_PER_SEC
	bubble.hide_bubble()


func _check_text_scaling(stage: Node3D) -> void:
	var bubble := _make_bubble(stage, "Scale")
	bubble.say("短。", 30.0)
	var narrow := bubble.get_bubble_width_m()
	bubble.say("这是一个明显更长的句子，用来看气泡会不会跟着一起变宽。", 30.0)
	var wide := bubble.get_bubble_width_m()
	_expect(narrow > 0.0, "短文本气泡宽度为 0，几何未生成")
	_expect(wide > 0.0, "长文本气泡宽度为 0，几何未生成")
	_expect(wide > narrow + 0.001, "气泡未随文字变长而变宽（narrow=%.3f wide=%.3f）" % [narrow, wide])

	# 反向对照：同一句连说两次，宽度必须稳定（说明度量是确定性的，不是随机数）。
	bubble.say("这是一个明显更长的句子，用来看气泡会不会跟着一起变宽。", 30.0)
	_expect(is_equal_approx(bubble.get_bubble_width_m(), wide), "同一文本两次测量宽度不一致")


func _check_facing_camera(stage: Node3D) -> void:
	var bubble := _make_bubble(stage, "Facing")
	bubble.say("朝向我。", 30.0)
	var panel := bubble.get_node_or_null("Panel") as MeshInstance3D
	var label := bubble.get_node_or_null("Text") as Label3D
	_expect(panel != null and label != null, "气泡缺少 Panel / Text，无法验证朝向")
	if panel == null or label == null:
		return
	var mesh := panel.mesh
	var surface_count := mesh.get_surface_count() if mesh != null else 0
	_expect(surface_count == 2, "气泡底板应为 2 个 surface（描边 + 填充），实际 %d" % surface_count)
	for surface in range(surface_count):
		var material := panel.get_surface_override_material(surface) as StandardMaterial3D
		_expect(material != null, "底板 surface %d 未设置材质" % surface)
		if material == null:
			continue
		# ⛔ 必须**关闭** billboard：材质 billboard 与 Label3D 内置 billboard 更新时机
		#    不同步，移动时差一帧 —— 实拍表现为"走路时文字与底板重影"。
		#    朝向统一由气泡节点驱动（见本函数末尾的相机朝向断言）。
		_expect(material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED,
			"底板 surface %d 启用了 billboard（会与文字更新不同步，造成走路重影）" % surface)
		_expect(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
			"底板 surface %d 未设为 UNSHADED（会被房间灯光影响）" % surface)
		# 底板**半透明**（2026-11-02 业主「黑色背景半透明」）。
		#
		# 原来的口径是"必须不透明，防 TAA 残影"；改成半透明后，防拖影的责任
		# 转交给「位移来自父节点、速度极低」+ 文字排在底板之后（见下一条）。
		# 这里断言的是**alpha 混合确实开了、且底色确实半透**，否则业主看到的就是
		# 一块死板；同时守一条下限，太透（<0.15）字会压不住背景。
		_expect(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
			"底板 surface %d 没有开 alpha 混合（半透明背景会退化成不透明）" % surface)
		if surface == 1:
			# ⚠️ 读**配置值** `fill_color.a`，不要读材质的 `albedo_color.a`：
			# 后者 = `fill_color.a × 淡入淡出进度`，刚 pop-in 时就是 0，断言会假红。
			var fill_alpha := bubble.fill_color.a
			_expect(fill_alpha < 0.9 and fill_alpha > 0.15,
				"气泡填充 alpha=%.2f，应落在 0.15–0.9（业主口径：黑色背景半透明）" % fill_alpha)
			# ⚠️ 半透明底板必须**先于**文字渲染，否则 0.55 的黑会把白字压掉一半亮度。
			# 排序靠 render_priority：底板 0 < 文字 2。
			var text_node := bubble.get_node_or_null("Text") as Label3D
			if text_node != null:
				_expect(material.render_priority < text_node.render_priority,
					"填充 render_priority %d 不小于文字的 %d —— 半透明底板会盖在字上"
						% [material.render_priority, text_node.render_priority])
	_expect(label.billboard == BaseMaterial3D.BILLBOARD_DISABLED,
		"Label3D 启用了 billboard（会与底板更新不同步，造成走路重影）")
	# 文字**必须**走透明队列（2026-11-02 起）：不透明永远先渲染，再叠半透明底板
	# 就会把字压暗。`ALPHA_CUT_DISCARD` 会让它进不透明管线 —— 那是旧口径，
	# 现在是 `ALPHA_CUT_DISABLED`。
	_expect(label.alpha_cut == Label3D.ALPHA_CUT_DISABLED,
		"Label3D 仍用 alpha 裁剪（文字会先进不透明队列，被半透明底板压暗）")
	# 气泡是贴在角色头上的 UI，**不许在世界里投影**（2026-09-22 主人：「头上的对话框会投射投影」）。
	# 面板与文字**两件都要关**：`Label3D` 也是 `GeometryInstance3D`，默认同样投影。
	_expect(panel.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"底板仍在投影（头顶的对话框会在地面/墙上留下影子）")
	# ⛐ 不要给 Label3D 写这条：它的 `cast_shadow` **默认就是 OFF**
	# （实测 Label3D=0 / MeshInstance3D=1），断言永远为绿 = 假绿。

	# 真正的"对着相机"判据：气泡朝向必须与相机朝向一致。
	# 用真实相机而不是"材质开了 billboard"—— 后者只是配置，前者才是行为。
	var camera := Camera3D.new()
	camera.name = "ProbeCamera"
	stage.add_child(camera)
	camera.position = Vector3(3.0, 5.0, 6.0)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	var expected_basis := camera.global_transform.basis
	_expect(bubble.global_transform.basis.is_equal_approx(expected_basis),
		"气泡朝向与相机不一致（气泡=%s 相机=%s）" % [bubble.global_transform.basis, expected_basis])
	camera.queue_free()


func _check_vertical_offset_only(stage: Node3D) -> void:
	var actor := Node3D.new()
	actor.name = "FakeActor"
	stage.add_child(actor)
	var bark := CharacterBark3D.attach_to(actor, 1.95)
	_expect(bark != null, "attach_to 返回 null")
	if bark == null:
		return
	await get_tree().process_frame

	var before := bark.global_position
	_expect(absf(before.y - 1.95) < 0.001, "气泡挂高不是 1.95m（实际 %.3f）" % before.y)
	actor.rotate_y(PI * 0.5)
	var after := bark.global_position
	_expect(before.distance_to(after) < 0.0001,
		"角色绕 Y 轴转身后气泡发生了位移（before=%s after=%s）" % [before, after])

	actor.rotate_y(-PI * 0.5)
	_expect(before.distance_to(bark.global_position) < 0.0001, "角色转回后气泡未回到原位")


## 直接针对"气泡钉在原地不跟角色走、看起来一条拖尾"的回归断言（2026-09-21 主人实测）。
##
## 为什么单独测这条：朝向对齐如果用 `global_transform = Transform3D(basis, global_position)`
## 实现，会因读 `global_position` 的时机早于父节点变换刷新，而每帧把气泡反算回旧位置 ——
## 等于自己抵消掉父节点的位移。必须在**有相机**（即 _face_camera 真的会执行）的条件下测。
func _check_follows_parent_motion(stage: Node3D) -> void:
	var camera := Camera3D.new()
	camera.name = "MotionProbeCamera"
	stage.add_child(camera)
	camera.position = Vector3(0.0, 8.0, 8.0)
	camera.look_at(Vector3.ZERO)
	camera.current = true

	var actor := Node3D.new()
	actor.name = "MovingActor"
	stage.add_child(actor)
	var bark := CharacterBark3D.attach_to(actor, 2.55)
	bark.say_text("跟着我走。", 30.0)
	await get_tree().process_frame

	var before := bark.global_position
	var step := Vector3(4.0, 0.0, -2.5)
	actor.global_position += step
	await get_tree().process_frame
	await get_tree().process_frame
	var after := bark.global_position

	var moved := before.distance_to(after)
	var expected := step.length()
	_expect(absf(moved - expected) < 0.01,
		"父节点移动 %.3f m 后气泡只移动了 %.3f m（气泡没跟随角色，会表现为原地拖尾）" % [expected, moved])
	_expect(absf(after.y - 2.55) < 0.001, "跟随移动后气泡挂高漂移（y=%.3f，应为 2.55）" % after.y)
	camera.queue_free()
	actor.queue_free()


func _check_catalog() -> void:
	var count := BarkCatalog.get_line_count(BARK_LAMP_ON)
	_expect(count == 3, "开灯文案应为 3 套，实际 %d 套" % count)

	var first := BarkCatalog.pick_at(BARK_LAMP_ON, 0)
	var second := BarkCatalog.pick_at(BARK_LAMP_ON, 1)
	var third := BarkCatalog.pick_at(BARK_LAMP_ON, 2)
	_expect(not first.is_empty() and not second.is_empty() and not third.is_empty(), "文案存在空串")
	_expect(first != second and second != third and first != third, "3 套文案之间存在重复")

	_expect(BarkCatalog.pick_at(BARK_LAMP_ON, 3) == first, "pick_at 未按 3 取模循环")
	_expect(BarkCatalog.pick_at(BARK_LAMP_ON, -1) == third, "pick_at 负数索引未按取模处理")

	# 随机抽取不得连续两次命中同一句（相同 bark_id 的去重策略）。
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260921
	var previous := -1
	var repeats := 0
	var samples := 240
	for _i in range(samples):
		var picked := BarkCatalog.pick_random(BARK_LAMP_ON, rng, previous)
		if int(picked["index"]) == previous:
			repeats += 1
		previous = int(picked["index"])
	_expect(samples > 0, "随机抽样样本数为 0（防假绿哨兵）")
	_expect(repeats == 0, "随机抽取出现 %d 次连续重复" % repeats)

	_expect(not BarkCatalog.has_bark("查无此句"), "未知 bark_id 被判为存在")
	_expect(BarkCatalog.pick_at("查无此句", 0) == "", "未知 bark_id 应返回空串")

	# 跨脚本 ID 契约：TowerDescent3D 用局部常量持有基地欢迎语的 ID，
	# 这里断言目录里确实存在该条目 —— 单方面改 ID 会让本验收变红。
	_expect(BarkCatalog.has_bark("system_base_welcome"),
		"BarkCatalog 缺少 system_base_welcome 条目，而 TowerDescent3D 依赖它")


func _check_character_bark(stage: Node3D) -> void:
	var actor := stage.get_node_or_null("FakeActor") as Node3D
	if actor == null:
		_expect(false, "缺少 FakeActor，无法验证挂载")
		return
	var loaded := CharacterBark3D.attach_to(actor, 1.95)
	var existing := actor.get_node_or_null(BARK_NODE_NAME) as CharacterBark3D
	_expect(existing != null, "attach_to 未在角色下建立 %s 节点" % BARK_NODE_NAME)
	_expect(loaded == existing, "attach_to 不幂等，重复挂载产生了第二个实例")
	_expect(actor.get_node_or_null(BARK_NODE_NAME) != null
		and actor.get_node(BARK_NODE_NAME).get_node_or_null(BUBBLE_NODE_NAME) != null,
		"角色下未自动创建 %s" % BUBBLE_NODE_NAME)

	_expect(loaded.say_bark(BARK_LAMP_ON), "say_bark 返回 false")
	_expect(loaded.is_speaking(), "say_bark 之后 is_speaking() 为 false")
	var lines := BarkCatalog.get_lines(BARK_LAMP_ON)
	_expect(lines.has(loaded.get_current_text()), "气泡文本不在目录内：『%s』" % loaded.get_current_text())
	_expect(not loaded.say_bark("查无此句"), "未知 bark_id 的 say_bark 应返回 false")

	var fixed := loaded.say_bark_at(BARK_LAMP_ON, 1)
	_expect(fixed, "say_bark_at 返回 false")
	_expect(loaded.get_current_text() == BarkCatalog.pick_at(BARK_LAMP_ON, 1),
		"say_bark_at 未取到指定句子")

	loaded.hide_now()
	_expect(not loaded.is_speaking(), "hide_now() 之后仍在说话")


## 防"两处少补一处"：房间侧信号 + 两条生成路径都必须接线。
## Dungeon3D 与 TowerDescent3D 各有一份房间装配代码，只补一处不会报错，
## 但那条路径上的房间会静默失去开灯说话能力。
func _check_light_switch_wiring() -> void:
	var room_source := FileAccess.get_file_as_string("res://src/world3d/DungeonRoom3D.gd")
	_expect(room_source.contains("signal light_toggled"),
		"DungeonRoom3D 未声明 light_toggled 信号")
	_expect(room_source.contains("_bind_light_switch_signal"),
		"DungeonRoom3D 未在灯开关创建路径上绑定信号")
	_expect(room_source.contains("_on_light_switch_toggled"),
		"DungeonRoom3D 缺少灯开关回调")

	var wiring := "room.light_toggled.connect(_on_room_light_toggled)"
	for path in ["res://src/world3d/Dungeon3D.gd", "res://src/world3d/TowerDescent3D.gd"]:
		var source := FileAccess.get_file_as_string(path)
		_expect(not source.is_empty(), "无法读取 %s" % path)
		_expect(source.contains(wiring), "%s 未连接 light_toggled（两处装配路径都要补）" % path)

	var dungeon_source := FileAccess.get_file_as_string("res://src/world3d/Dungeon3D.gd")
	_expect(dungeon_source.contains("say_bark(BarkCatalog.BARK_LAMP_ON"),
		"Dungeon3D 未把开灯接到玩家说话上")
	_expect(dungeon_source.contains("CharacterBark3D.attach_to"),
		"Dungeon3D 未把说话能力挂到玩家身上")


func _finish() -> void:
	if checks == 0:
		push_error("SPEECH_BUBBLE_3D_FAIL: 没有任何断言被执行（防假绿哨兵）")
		get_tree().quit(1)
		return
	print("SPEECH_BUBBLE_3D_SAMPLES: checks=%d" % checks)
	if failures.is_empty():
		print("SPEECH_BUBBLE_3D_OK: 尺寸自适应 / 面向相机 / 垂直偏移 / 3套文案 / 挂载幂等 / 两处灯开关接线 全部通过")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("SPEECH_BUBBLE_3D_FAIL: " + failure)
	get_tree().quit(1)
