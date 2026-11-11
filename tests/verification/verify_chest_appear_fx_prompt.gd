extends Node
## 宝箱「出现」特效 + 头顶提示牌让位 专项验收（2026-11-09）。
##
## 业主两条口径：
##   ① 「我的救援宝箱，不是有个消失特效嘛？帮我改个颜色，放在关卡宝箱出现的时候，
##      适当放大一点。这样我宝箱出来的时候不会很突兀。」
##   ② 「宝箱上面的 E 开启宝箱去掉，和靠近后的文字重复了。或者靠近后出现开启宝箱的
##      白字后，这个消失。」
##
## 只验表现契约：不解析奖励、不写房间账、不建房间。
##
## 为什么断言的是 `mode == "in"` 而不是「asset_id 是 TELEPORT-OUT」：
## 业主要的是「那件特效」，但 OUT 的环**向内收拢**，播在"凭空出现"上读作「被吸走」。
## 同一脚本的另一支 IN（环向外炸开 + 竖丝向上冒出）才是出现语义。这条断言就是
## 防止后人"照字面"把 OUT 搬过来 —— 那时画面不会报错，只会读起来别扭。

const _APPEAR_ASSET := &"VFX-TELEPORT-IN-3D"
## 期望值写成字面量，不读被测常量：否则把常量改小，验收跟着改小，断言永远绿。
const _EXPECTED_SIZE := 2.0
const _EXPECTED_COLOR := Color(1.00, 0.78, 0.32)
const _EXPECTED_LIFT := 0.05
## 灯的三档期望值同样写字面量（不读被测常量），理由同上。
const _EXPECTED_LIGHT_RANGE := 3.0
const _EXPECTED_LIGHT_ENERGY := 1.1
const _EXPECTED_LIGHT_LIFT := 0.45

var _failures: Array[String] = []


func _ready() -> void:
	# 本用例会建一个 `DungeonRoom3D` 并在里面跑几帧 tween，时间足够长到
	# `GameTimeManager._process` 每帧尝试落档一次。套件 runner 会隔离 APPDATA，
	# 但单场景直跑不会 —— 这里直接把时钟停掉：本用例不依赖世界时间推进，
	# 停掉既能防污染正式存档，也能消掉满屏 `Refusing stale save`。
	var clock := get_node_or_null("/root/GameTimeManager")
	if clock != null:
		clock.set_process(false)
	await _case_appear_effect()
	await _case_room_triggers_once()
	await _case_room_entry_wiring()
	await _case_loot_light()
	await _case_prompt_yields_on_focus()
	await _case_spotlight_unfolds()
	if _failures.is_empty():
		print(
			"CHEST_APPEAR_FX_PROMPT_OK: appear fx uses teleport-in / size / gold tint / ground lift; "
			+ "room entry plays it once; loot light binds to model without shadow; "
			+ "prompt stays hidden; both tiers unfold over 0.42s; interrupted unfold closes without jumping; restored open chest stays dark"
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


# ---------------------------------------------------------------------------
# ① 出现特效
# ---------------------------------------------------------------------------

func _case_appear_effect() -> void:
	var chest := _make_chest()
	add_child(chest)
	await get_tree().process_frame

	var before := VfxPool.active_count(_APPEAR_ASSET)
	chest.play_appear_effect()
	var after := VfxPool.active_count(_APPEAR_ASSET)
	_expect(after == before + 1, "play_appear_effect 没有向池里借出一件传送特效（%d → %d）" % [before, after])
	if after != before + 1:
		chest.queue_free()
		return

	var effect := _newest_effect(_APPEAR_ASSET)
	_expect(effect != null, "拿不到刚借出的特效实例")
	if effect != null:
		# 方向：必须是 in。out 是"收拢离开"，播在出现上语义相反。
		_expect(
			str(effect.get("mode")) == "in",
			"出现特效方向反了：mode=%s（应为 in）" % str(effect.get("mode"))
		)
		_expect(
			is_equal_approx(float(effect.get("effect_size")), _EXPECTED_SIZE),
			"出现特效尺寸应为 %.1f，实际 %.2f" % [_EXPECTED_SIZE, float(effect.get("effect_size"))]
		)
		var expected_y := chest.global_position.y + _EXPECTED_LIFT
		_expect(
			absf(effect.global_position.y - expected_y) < 0.01,
			"出现特效应贴地抬 %.2f m：期望 y≈%.3f，实际 %.3f" % [
				_EXPECTED_LIFT, expected_y, effect.global_position.y
			]
		)
		var ring := effect.get_node_or_null("TeleportRing") as MeshInstance3D
		_expect(ring != null, "传送特效缺少 TeleportRing 节点")
		if ring != null:
			var material := ring.material_override as StandardMaterial3D
			_expect(material != null, "TeleportRing 没有材质")
			if material != null:
				var actual := material.albedo_color
				var tint_ok := (
					absf(actual.r - _EXPECTED_COLOR.r) < 0.02
					and absf(actual.g - _EXPECTED_COLOR.g) < 0.02
					and absf(actual.b - _EXPECTED_COLOR.b) < 0.02
				)
				_expect(
					tint_ok,
					"出现特效颜色应为暖金 %s，实际 %s" % [str(_EXPECTED_COLOR), str(actual)]
				)
	chest.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# ①-b 房间触发：进房播一次，重进不重播
# ---------------------------------------------------------------------------

## 为什么这条必须单测：特效本身对，但**触发点**写错就会变成"每过一次门放一圈光"。
## 装配期播（`_build_treasure_chests`）会在加载页白播、且旗标一置再也补不上；
## 每次 `set_stream_state` 播会在走远回来时重播。两条都是"代码看着对、画面不对"。
func _case_room_triggers_once() -> void:
	var room := DungeonRoom3D.new()
	room.name = "ProbeRoom"
	add_child(room)
	await get_tree().process_frame
	var chest := _make_chest()
	room.add_child(chest)
	await get_tree().process_frame

	var before := VfxPool.active_count(_APPEAR_ASSET)
	room.play_chest_appear_effects()
	_expect(
		VfxPool.active_count(_APPEAR_ASSET) == before + 1,
		"进房时应在册宝箱各播一次出现特效（%d → %d）" % [before, VfxPool.active_count(_APPEAR_ASSET)]
	)
	# 走远回来 / 二次 room_entered：不许再放一遍。
	room.play_chest_appear_effects()
	_expect(
		VfxPool.active_count(_APPEAR_ASSET) == before + 1,
		"同一房间第二次进入不许重播出现特效"
	)

	# 已开的箱子永远不播：重进旧房间时它只是"还在那"，不是"刚出现"。
	var second := _make_chest()
	room.add_child(second)
	await get_tree().process_frame
	chest.commit_opened()
	second.commit_opened()
	await _wait(0.05)
	var after_open := VfxPool.active_count(_APPEAR_ASSET)
	# 手动把旗标按回去：真实场景里不可能出现"旗标已置 + 又有未播的箱子"，
	# 这里要单独考的是「已开箱过滤」这一条，不靠旗标替它挡。
	room.set("_chest_appear_fx_played", false)
	room.play_chest_appear_effects()
	_expect(
		VfxPool.active_count(_APPEAR_ASSET) == after_open,
		"已开箱不许补播出现特效"
	)

	room.queue_free()
	await get_tree().process_frame

	# 箱子自身也要挡（第二层，不是冗余的重复劳动）：房间那层挡的是"批量补播"，
	# 这层挡的是"任何调用方直接点一只已开的箱子"。少任何一层，都会有人从另一条路漏进来。
	var opened_chest := _make_chest()
	add_child(opened_chest)
	await get_tree().process_frame
	opened_chest.commit_opened()
	await _wait(0.05)
	var settled := VfxPool.active_count(_APPEAR_ASSET)
	opened_chest.play_appear_effect()
	_expect(
		VfxPool.active_count(_APPEAR_ASSET) == settled,
		"已开箱的 play_appear_effect 必须自己早退（被直接调用也不许播）"
	)
	opened_chest.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# ①-c 接线：玩家进房的那条链真的会调它
# ---------------------------------------------------------------------------

## 房间方法本身对，但没人调就等于没做 —— 这是本项目最容易漏的一类：
## 单测把 `play_chest_appear_effects()` 打绿了，正式关卡里一次都不会播。
## 因此这里钉住**调用点**本身。用源码断言而不是起一个完整 `Dungeon3D`：
## 起整关要建 27 间房 + 刷怪，成本与本用例要验的一句话不成比例。
func _case_room_entry_wiring() -> void:
	var source := FileAccess.get_file_as_string("res://src/world3d/Dungeon3D.gd")
	_expect(not source.is_empty(), "读不到 Dungeon3D.gd")
	_expect(
		source.contains("room.play_chest_appear_effects()"),
		"Dungeon3D 没有在玩家进房时触发宝箱出现特效（接线断了 ⇒ 特效永远不播）"
	)


# ---------------------------------------------------------------------------
# ①-d 宝箱自带地面光
# ---------------------------------------------------------------------------

## 业主 2026-11-09：「宝箱上方加一个灯，和宝箱模型绑定，不然宝箱在里头根本看不见。」
##
## 三条硬约束逐条钉住：
##   · **绑在模型上**（父节点是 `_visual_root`，不是场景/房间）—— 否则箱子抖动、上跳、
##     被演出 despawn 时光都不跟着走；
##   · **不投影** —— 掉落物的光不该多渲一张阴影贴图（2026-11-08 帧时归因的教训：
##     24 盏零能量灯仍每帧渲阴影，白烧 35% 帧时）；
##   · **浅灰箱不被染黄** —— 平涂箱的光跟身板色走，否则"业主点名的浅灰救援箱"又被打回彩箱。
func _case_loot_light() -> void:
	var chest := _make_chest()
	add_child(chest)
	await get_tree().process_frame

	var light := chest.find_child("ChestLootLight", true, false) as OmniLight3D
	_expect(light != null, "宝箱没有建出自带地面光 ChestLootLight")
	if light == null:
		chest.queue_free()
		return

	var visual_root := chest.get("_visual_root") as Node3D
	_expect(visual_root != null, "宝箱没有视觉根，灯无处可绑")
	if visual_root != null:
		_expect(
			light.get_parent() == visual_root,
			"地面光必须挂在宝箱模型下，实际父节点是 %s" % str(light.get_parent())
		)
	_expect(not light.shadow_enabled, "宝箱地面光必须关阴影")
	_expect(
		is_equal_approx(light.omni_range, _EXPECTED_LIGHT_RANGE),
		"地面光半径应为 %.1f，实际 %.2f" % [_EXPECTED_LIGHT_RANGE, light.omni_range]
	)
	_expect(
		is_equal_approx(light.light_energy, _EXPECTED_LIGHT_ENERGY),
		"地面光能量应为 %.1f，实际 %.2f" % [_EXPECTED_LIGHT_ENERGY, light.light_energy]
	)
	_expect(
		absf(light.position.y - (1.02 + _EXPECTED_LIGHT_LIFT)) < 0.02,
		"灯高应在箱体之上 %.2f m（≈1.47 m），实际 %.2f" % [_EXPECTED_LIGHT_LIFT, light.position.y]
	)

	# 拟态吞箱 / 演出 despawn 都只把 `_visual_root.visible` 关掉 —— 灯必须跟着灭，
	# 否则场上会剩下一团照空气的光。
	chest.commit_mimic_reveal()
	await _wait(0.85)
	_expect(not light.is_visible_in_tree(), "宝箱视觉消失后地面光必须一起灭")
	chest.queue_free()
	await get_tree().process_frame

	# 浅灰救援箱：光跟身板色走，不许变成暖黄。
	var grey := Color(0.80, 0.81, 0.83)
	var tinted := _make_chest({
		"id": "probe_grey_chest",
		"body_tint": [grey.r, grey.g, grey.b],
	})
	add_child(tinted)
	await get_tree().process_frame
	var tinted_light := tinted.find_child("ChestLootLight", true, false) as OmniLight3D
	_expect(tinted_light != null, "浅灰箱没有建出地面光")
	if tinted_light != null:
		var actual := tinted_light.light_color
		var want := grey.lightened(0.5)
		var ok := (
			absf(actual.r - want.r) < 0.02
			and absf(actual.g - want.g) < 0.02
			and absf(actual.b - want.b) < 0.02
		)
		_expect(ok, "浅灰箱的地面光应跟身板色（%s），实际 %s" % [str(want), str(actual)])
	tinted.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# ② 头顶提示牌让位
# ---------------------------------------------------------------------------

func _case_prompt_yields_on_focus() -> void:
	var chest := _make_chest()
	add_child(chest)
	await get_tree().process_frame

	var prompt := chest.get("_prompt") as Label3D
	_expect(prompt != null, "宝箱没有建出头顶提示牌")
	if prompt == null:
		chest.queue_free()
		return
	# 2026-11-10 起与椅子、灯、可搜索组件统一：头顶文字永远不承担画面反馈。
	_expect(not prompt.visible, "宝箱头顶不应显示任何开启文字，只保留交互圆点")
	_expect(prompt.text == "[E] 开启宝箱", "隐藏协议文案必须保留，供交互圆点提取动作词：%s" % prompt.text)

	chest.set_interaction_focus({}, true)
	await _wait(0.18)
	_expect(not prompt.visible, "聚焦时头顶文字必须保持隐藏")
	chest.set_interaction_focus({}, false)
	await _wait(0.18)
	_expect(not prompt.visible, "失焦后头顶文字仍必须保持隐藏")

	chest.commit_opened()
	await _wait(0.20)
	chest.set_interaction_focus({}, false)
	await _wait(0.20)
	_expect(not prompt.visible, "已开箱后头顶文字必须保持隐藏")

	chest.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

## 初帧关闭 → 中段展开 → 完整点亮；覆盖两档及开启途中收灯。
func _case_spotlight_unfolds() -> void:
	for tier in ["normal", "advanced"]:
		var chest := _make_chest({"chest_tier": tier})
		add_child(chest)
		var stage := chest.get_node_or_null("ChestSpotlightStage") as Node3D
		_expect(stage != null, "缺少聚光灯容器：%s" % tier)
		if stage == null:
			chest.queue_free()
			continue
		var spot := stage.get_node("ChestSpotlight") as SpotLight3D
		var key := stage.get_node("ChestSpotlightKeyLight") as OmniLight3D
		_expect(is_zero_approx(spot.light_energy) and is_zero_approx(key.light_energy), "聚光灯初帧不能直接全亮")
		_expect(is_equal_approx(stage.scale.x, 0.04), "聚光灯初帧应收窄至4%")
		await _wait(0.18)
		_expect(stage.scale.x > 0.04 and stage.scale.x < 1.0, "展开中段应处于初态和终态之间")
		_expect(spot.light_energy > 0.0 and spot.light_energy < 7.0, "聚光灯亮度应同步渐亮")
		await _wait(0.34)
		_expect(is_equal_approx(stage.scale.x, 1.0), "0.42秒后光束应完全展开")
		_expect(is_equal_approx(spot.light_energy, 7.0) and is_equal_approx(key.light_energy, 2.0), "开灯终态亮度不正确")
		chest.call("_dismiss_chest_spotlight")
		await _wait(0.40)
		_expect(not is_instance_valid(stage), "收灯结束必须释放全部光效")
		chest.queue_free()
		await get_tree().process_frame
	var interrupted := _make_chest()
	add_child(interrupted)
	await _wait(0.12)
	var interrupted_stage := interrupted.get_node("ChestSpotlightStage") as Node3D
	var before := interrupted_stage.scale.x
	interrupted.call("_dismiss_chest_spotlight")
	_expect(is_equal_approx(interrupted_stage.scale.x, before), "开启中被关闭不能跳到全亮")
	await _wait(0.40)
	_expect(not is_instance_valid(interrupted_stage), "中断展开后必须正常收灯")
	interrupted.queue_free()
	var restored := _make_chest()
	add_child(restored)
	restored.restore_opened_state(true)
	await _wait(0.10)
	_expect(restored.get_node_or_null("ChestSpotlightStage") == null, "读档已开箱不得闪亮")
	restored.queue_free()
	await get_tree().process_frame


func _make_chest(overrides := {}) -> TreasureChest3D:
	var config := {"id": "probe_appear_fx", "quality": "common", "chest_tier": "normal"}
	config.merge(overrides, true)
	var chest := TreasureChest3D.new()
	chest.configure(config)
	return chest


## 池按 asset_id 分桶，桶内最后一个就是刚借出的那一件（`acquire` 走 `append`）。
func _newest_effect(asset_id: StringName) -> Node:
	var buckets: Dictionary = VfxPool.get("_active")
	var bucket: Array = buckets.get(asset_id, [])
	if bucket.is_empty():
		return null
	return bucket[bucket.size() - 1] as Node


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
