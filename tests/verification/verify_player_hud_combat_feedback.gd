extends Node
## 玩家主界面血条 / 翻滚冷却环的战斗反馈验收（2026-11-10）。
##
## 对应业主当天四条要求，逐条一个判据组：
## ① `HudDashCooldownRing` —— 翻滚冷却环：比例只来自 `Player3D.dash_cooldown_changed`，
##    环上填的是「已恢复量」，满圈 = 可翻滚（不写一个字）；
## ② 受击震动 —— `_tick_player_status_shake` 的位移衰减，以及**精确复位**；
## ③ `HudHealthBarTrack` —— 血条空槽底纹（斜杆 + 横向位移），并把"空槽真源"钉在它身上；
## ④ `HudHealthBarHeal` —— 回血补条：白色前沿从旧血量推到新血量后淡出，且**不改真值**。
##
## 时间一律手动步进（`set_process(false)` + 固定 delta 调 tick）：靠
## `await process_frame` 取样会随机器帧时间浮动，把判据变成飘忽用例 ——
## 与 `verify_reference_hud_fate_visual` 里血条白段那一段同一处理。
##
## 只验逻辑与结构。像素级"看起来对不对"（斜纹够不够暗、震动够不够显眼）必须真渲染另证，
## 本用例不做替代。

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")

## 手动步进的固定步长。换算见各断言：冷却环 `tick` 只衰减就绪闪光，
## 血条三类反馈的时长都在 0.34～0.42 s 量级，0.02 一档足够细。
const STEP := 0.02


func _ready() -> void:
	var failures: Array[String] = []
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for _frame in 8:
		await get_tree().process_frame
	# 冻住场景主循环：此后所有视觉层都只按本文件的 delta 走。
	dungeon.set_process(false)

	var hud := dungeon.get_node_or_null("HUD/ReferenceCombatHUD") as Control
	_check(hud != null, "参考战斗 HUD 根节点缺失", failures)
	if hud == null:
		_finish(failures)
		return

	var status_block := hud.find_child("PlayerStatusBlock", true, false) as Control
	var hp_stack := hud.find_child("PlayerHealthBarStack", true, false) as Control
	var hp_bar := hud.find_child("HPBar", true, false) as ProgressBar
	var delayed_layer := hud.find_child("PlayerHealthBarDelayed", true, false) as ProgressBar
	var track := hud.find_child("PlayerHealthBarTrack", true, false) as HudHealthBarTrack
	var heal_bar := hud.find_child("PlayerHealthBarHeal", true, false) as HudHealthBarHeal
	var dash_ring := hud.find_child("HudDashCooldownRing", true, false) as HudDashCooldownRing

	# ── 结构：三层血条 + 冷却环都在，且叠放次序正确 ──────────────────────────
	_check(status_block != null, "PlayerStatusBlock 缺失", failures)
	_check(hp_stack != null and hp_bar != null and delayed_layer != null, "玩家血条三层缺失", failures)
	_check(track != null, "血条底纹槽 PlayerHealthBarTrack 缺失（要求③）", failures)
	_check(heal_bar != null, "回血补条 PlayerHealthBarHeal 缺失（要求④）", failures)
	_check(dash_ring != null, "翻滚冷却环 HudDashCooldownRing 缺失（要求①）", failures)
	if track == null or heal_bar == null or dash_ring == null or hp_stack == null:
		_finish(failures)
		return

	# 次序：底纹最底 → 白段 → 红条 → 回血补条（补条必须压在红条之上才看得见）。
	_check(track.get_parent() == hp_stack, "血条底纹不是血条栈的子节点", failures)
	_check(track.get_index() == 0, "血条底纹不在最底层（会被空槽底衬盖住）", failures)
	_check(
		heal_bar.get_index() > hp_bar.get_index(),
		"回血补条没有压在真实红条之上（会被红色填满盖掉）",
		failures,
	)
	# 空槽真源必须唯一 = 底纹槽。此前两层 ProgressBar 各带一层近乎不透明的空槽，
	# 掉血后玩家读不出"总共多长、掉了多少" —— 正是要求③要修的那个问题。
	_check(
		_color_alpha(hp_bar.get_theme_stylebox("background")) <= 0.02,
		"真实红条又带回了不透明空槽（空槽真源应只归底纹槽）",
		failures,
	)
	_check(
		_color_alpha(delayed_layer.get_theme_stylebox("background")) <= 0.02,
		"白段层又带回了不透明空槽（会整片盖住底纹斜杆）",
		failures,
	)
	_check(
		delayed_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and heal_bar.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and track.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and dash_ring.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"HUD 视觉层接管了鼠标事件（应全部 IGNORE）",
		failures,
	)
	_check(
		track.size.is_equal_approx(hp_bar.size) and heal_bar.size.is_equal_approx(hp_bar.size),
		"底纹/补条与真实血条不等尺寸：%s / %s / %s" % [track.size, heal_bar.size, hp_bar.size],
		failures,
	)

	# ── ③ 底纹：斜纹随 delta 横向位移，不被判成常驻动画 ──────────────────────
	var track_snapshot := track.get_snapshot()
	_check(
		float(track_snapshot.get("stripe_thickness_px", 0.0)) > 0.5
		and float(track_snapshot.get("stripe_period_px", 0.0))
			> float(track_snapshot.get("stripe_thickness_px", 0.0)),
		"底纹斜杆几何不合理：%s" % track_snapshot,
		failures,
	)
	_check(
		float(Color(track_snapshot.get("stripe_color", Color.BLACK)).a) <= 0.2,
		"底纹斜杆太亮，会抢血条的注意力（要求是灰色、暗一点）",
		failures,
	)
	var scroll_before := float(track_snapshot.get("scroll_px", 0.0))
	track.tick(0.05)
	var scroll_after := float(track.get_snapshot().get("scroll_px", -1.0))
	_check(
		not is_equal_approx(scroll_after, scroll_before),
		"底纹没有横向位移（要求③的动画未生效）",
		failures,
	)
	_check(
		scroll_after < float(track.get_snapshot().get("stripe_period_px", 1.0)) + 0.001,
		"底纹位移没有按斜纹间距取模（会一直漂移）",
		failures,
	)

	# ── ① 翻滚冷却环：驱动源是真实玩家计时，不是 HUD 自己算 ──────────────────
	_check(
		dash_ring.size.is_equal_approx(
			Vector2(
				Dungeon3D.HUD_DASH_RING_DIAMETER_DESIGN,
				Dungeon3D.HUD_DASH_RING_DIAMETER_DESIGN
			) * Dungeon3D.HUD_UI_SCALE
		),
		"翻滚冷却环尺寸不是 32 设计 px × HUD_UI_SCALE：%s" % dash_ring.size,
		failures,
	)
	if status_block != null:
		_check(
			status_block.get_global_rect().encloses(dash_ring.get_global_rect()),
			"翻滚冷却环跑到角色状态块之外（会与塔楼引导卡/种子标签撞）",
			failures,
		)
	# 初始就绪：满圈、且不写字（环内没有任何 Label）。
	_check(dash_ring.is_ready(), "翻滚冷却环开局不是就绪态", failures)
	_check(
		dash_ring.find_children("*", "Label", true, false).is_empty(),
		"翻滚冷却环里出现了文字（要求：不要用文字提醒）",
		failures,
	)
	# 真跑一次冲刺：比例必须由 Player3D 推过来（这条判的是"接线"，不是"画得对不对"）。
	var player := dungeon.player
	player.dash_cooldown_timer = 0.0
	_check(bool(player.call("_begin_dash")), "玩家在空闲态无法开始冲刺，冷却环接线判据无法成立", failures)
	for _frame in 3:
		await get_tree().physics_frame
	var after_dash := dungeon.get_player_dash_gauge_snapshot()
	_check(
		float(after_dash.get("cooldown_ratio", 0.0)) > 0.5,
		"冲刺后冷却环没有读数（信号未接到 HUD）：%s" % after_dash.get("cooldown_ratio"),
		failures,
	)
	_check(not bool(after_dash.get("ready", true)), "冲刺后冷却环仍显示就绪", failures)
	# 直接写玩家计时归零（等价于冷却跑完），环必须在下一物理帧转为就绪并起闪光。
	player.dash_cooldown_timer = 0.0
	for _frame in 3:
		await get_tree().physics_frame
	var ready_snapshot := dungeon.get_player_dash_gauge_snapshot()
	_check(bool(ready_snapshot.get("ready", false)), "冷却跑完后环没有回到就绪态", failures)
	_check(
		float(ready_snapshot.get("cooldown_ratio", 1.0)) <= 0.0001,
		"冷却跑完后环仍保留冷却比例：%s" % ready_snapshot.get("cooldown_ratio"),
		failures,
	)
	var flash_before := float(ready_snapshot.get("ring", {}).get("ready_flash_sec", 0.0))
	_check(flash_before > 0.0, "就绪瞬间没有起闪光", failures)
	dash_ring.tick(0.3)
	_check(
		float(dash_ring.get_snapshot().get("ready_flash_sec", 1.0)) <= 0.0001,
		"就绪闪光没有被 tick 衰减掉（会常亮）",
		failures,
	)

	# ── ④ 回血补条 + ② 受击震动 ─────────────────────────────────────────────
	var full_hp := int(maxf(1.0, hp_bar.max_value))
	var base_position := status_block.position if status_block != null else Vector2.ZERO
	# 先掉到 60%：扣血不该触发补条。
	dungeon.call("_on_player_hp_changed", int(round(float(full_hp) * 0.6)), full_hp)
	var hurt_snapshot := dungeon.get_player_vitals_bar_snapshot()
	_check(
		not bool(hurt_snapshot.get("heal", {}).get("active", true)),
		"扣血触发了回血补条",
		failures,
	)
	_check(bool(hurt_snapshot.get("shake_active", false)), "扣血没有触发血条震动（要求②）", failures)

	# 震动：位移真的发生、随进度衰减、结束精确复位。
	dungeon.call("_tick_player_vitals_fx", STEP)
	var shaking := dungeon.get_player_vitals_bar_snapshot()
	var shake_offset := Vector2(shaking.get("shake_offset", Vector2.ZERO))
	_check(
		shake_offset.length() > 0.5,
		"震动位移为零（振幅或相位没生效）：%s" % shake_offset,
		failures,
	)
	_check(
		status_block != null and not status_block.position.is_equal_approx(base_position),
		"状态块位置没有被震动推开",
		failures,
	)
	var early_decay := float(shaking.get("shake_decay", 1.0))
	dungeon.call("_tick_player_vitals_fx", 0.12)
	var mid_decay := float(dungeon.get_player_vitals_bar_snapshot().get("shake_decay", 1.0))
	# 判的是**包络**衰减，不是瞬时位移：`sin` 随时可能过零，拿位移长度判衰减会误判
	# （首版就是这么误报的）。位移本身由上面的"推开了"和下面的"归零"两条兜住。
	_check(
		mid_decay < early_decay and mid_decay > 0.0,
		"震动包络没有随进度衰减（会一直抖）：%.4f → %.4f" % [early_decay, mid_decay],
		failures,
	)
	# 步进到整段结束：位移必须精确归零、缩放回 1，且位置回到基准（不许累加漂移）。
	for _step in 40:
		dungeon.call("_tick_player_vitals_fx", STEP)
	var settled := dungeon.get_player_vitals_bar_snapshot()
	_check(not bool(settled.get("shake_active", true)), "震动播完后没有结束", failures)
	_check(
		Vector2(settled.get("shake_offset", Vector2.ONE)).length() <= 0.0001,
		"震动结束后仍残留位移",
		failures,
	)
	if status_block != null:
		_check(
			status_block.scale.is_equal_approx(Vector2.ONE),
			"震动结束后状态块缩放没有复位：%s" % status_block.scale,
			failures,
		)

	# 回血：白色前沿从旧血量推到新血量，推完自行隐藏，且**不改真实血量**。
	dungeon.call("_on_player_hp_changed", int(round(float(full_hp) * 0.85)), full_hp)
	var heal_started := dungeon.get_player_vitals_bar_snapshot()
	var heal_layer: Dictionary = heal_started.get("heal", {})
	_check(bool(heal_layer.get("active", false)), "加血没有触发补条动画（要求④）", failures)
	_check(
		absf(float(heal_layer.get("from_ratio", -1.0)) - 0.6) <= 0.03,
		"补条起点不是治疗前的血量：%s" % heal_layer.get("from_ratio"),
		failures,
	)
	_check(
		absf(float(heal_layer.get("to_ratio", -1.0)) - 0.85) <= 0.03,
		"补条终点不是治疗后的血量：%s" % heal_layer.get("to_ratio"),
		failures,
	)
	_check(
		absf(float(heal_started.get("actual_ratio", -1.0)) - 0.85) <= 0.02,
		"补条动画让真实血条读数滞后了（视觉层不得代替真值）",
		failures,
	)
	var lead_before := float(heal_layer.get("lead_ratio", 0.0))
	heal_bar.tick(0.08)
	var lead_after := float(heal_bar.get_snapshot().get("lead_ratio", 0.0))
	_check(
		lead_after > lead_before and lead_after < 0.8501,
		"回血补条前沿没有从旧值向新值推进：%.4f → %.4f" % [lead_before, lead_after],
		failures,
	)
	heal_bar.tick(1.0)
	var heal_done := heal_bar.get_snapshot()
	_check(not bool(heal_done.get("active", true)), "回血补条播完后没有结束", failures)
	_check(not heal_bar.visible, "回血补条播完后没有隐藏（会留一条白线）", failures)

	# 无障碍降级：开了 reduce_motion 只许闪、不许位移。
	ProjectSettings.set_setting("accessibility/reduce_motion", true)
	dungeon.call("_on_player_hp_changed", int(round(float(full_hp) * 0.4)), full_hp)
	_check(
		not bool(dungeon.get_player_vitals_bar_snapshot().get("shake_active", true)),
		"reduce_motion 下仍在做位移震动",
		failures,
	)
	ProjectSettings.set_setting("accessibility/reduce_motion", false)

	_finish(failures)


func _color_alpha(style: StyleBox) -> float:
	var flat := style as StyleBoxFlat
	return flat.bg_color.a if flat != null else 1.0


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PLAYER_HUD_COMBAT_FEEDBACK_OK: 底纹槽 / 回血补条 / 受击震动 / 翻滚冷却环四项契约成立")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
