extends Node
## 实拍：玩家主界面血条的四项战斗反馈（2026-11-10）。
##
## 业主当天的四条要求都是"看起来对不对"的问题，headless 几何断言只能证明接线与
## 生命周期成立，证明不了"斜杆够不够暗、白段够不够显眼、震动看得出来"。所以必须出图：
##   ① 翻滚冷却环（不写字、环形扫描、就绪转白）
##   ② 受击震动（整个状态块被推开 + 放大）
##   ③ 血条空槽底纹（斜杆 + 横向位移；掉血后才看得到）
##   ④ 回血补条（白色前沿从旧血量推到新血量）
##
## ## 与 `capture_encounter_countdown_ring.gd` 同一口径的两条硬约束
##   · 必须等 `RenderingServer.frame_post_draw`，只等 `process_frame` 会拿到**全透明空图**；
##   · 读回的帧格式可能是浮点（`FORMAT_RGBAH`），要显式 `convert()` 再做像素比较。
##
## ## 为什么要先 `set_process(false)`
## 场景主循环会自己推进血条白段、底纹位移与震动，帧率一抖截图就落在不同相位上。
## 冻住之后每一步都由本脚本用固定 delta 手动推，四张图才可复现。
##
## 输出：`outputs/verification/player_vitals_feedback_*.png`（全屏）
##      `outputs/verification/player_vitals_feedback_*_zoom.png`（左上状态块放大 3×）
## 放大图是给业主看细部用的：全屏图里血条只有 176×21 px，斜杆看不清。

const SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
const OUT_DIR := "res://outputs/verification"
## 左上状态块在全屏图里的裁剪盒（1280×720 canvas 基准，留足四周余量）。
const ZOOM_BOX := Rect2i(8, 30, 400, 150)
const ZOOM_FACTOR := 3


func _ready() -> void:
	var dungeon := SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for _frame in 10:
		await get_tree().process_frame
	dungeon.force_enter_room_for_test("main_01")
	for _frame in 4:
		await get_tree().process_frame
	# 冻住场景主循环：此后所有视觉层只按本文件的固定 delta 走。
	dungeon.set_process(false)

	var hud := dungeon.get_node_or_null("HUD/ReferenceCombatHUD") as Control
	if hud == null:
		print("CAPTURE_PLAYER_VITALS_FEEDBACK_FAIL hud_missing")
		get_tree().quit(1)
		return
	var full_hp := int(maxf(1.0, dungeon.hp_bar.max_value))

	# —— ① 空槽底纹（掉到 55% 并把白段收干净，露出斜杆）——
	dungeon.call("_on_player_hp_changed", int(round(float(full_hp) * 0.55)), full_hp)
	# 白段按 `HUD_HEALTH_BAR_DELAY_SPEED` 追赶：多推几轮让它收完，空槽才只剩底纹。
	for _step in 60:
		dungeon.call("_tick_player_health_bar_delay", 0.05)
		dungeon.call("_tick_player_vitals_fx", 0.05)
	await get_tree().process_frame
	await _shoot("player_vitals_feedback_1_track", dungeon)

	# —— ② 受击震动（刚挨打、位移接近峰值的那一帧：白段 + 状态块被推开 + 放大 + 偏暖红）——
	dungeon.call("_on_player_hp_changed", int(round(float(full_hp) * 0.40)), full_hp)
	# 推到第一个位移峰值：频率 26 Hz ⇒ 周期 ≈ 38.5 ms，峰值在 1/4 周期 ≈ 9.6 ms 处。
	# 首版取 55 ms，正好落在 sin 的下降段，截出来的位移只有峰值的四成，"显不显眼"判不了。
	dungeon.call("_tick_player_vitals_fx", 0.011)
	await get_tree().process_frame
	await _shoot("player_vitals_feedback_2_shake", dungeon)

	# —— ④ 回血补条（前沿走到接近终点，白色那截正在把恢复量推出来）——
	# 先把震动推到结束：回血不是受伤，画面里不该同时挂着受击染色，
	# 否则"这截白是补血还是挨打"会被自己搞混（首版两张图就是这么糊在一起的）。
	for _step in 20:
		dungeon.call("_tick_player_vitals_fx", 0.05)
	dungeon.call("_on_player_hp_changed", int(round(float(full_hp) * 0.72)), full_hp)
	# 0.20 s 落在 LEAD_PHASE_RATIO(0.62) 之内 ⇒ 前沿已走完 96%，白段几乎铺满恢复区间。
	dungeon.call("_tick_player_vitals_fx", 0.20)
	await get_tree().process_frame
	await _shoot("player_vitals_feedback_3_heal", dungeon)

	# —— ③ 翻滚冷却环（冷却中 40% 已恢复：圆弧只填了一部分，颜色是天蓝）——
	# 必须写**玩家的真实计时器**再去等物理帧：HUD 那一格只是投影，
	# 下一物理帧就会被 `Player3D.dash_cooldown_changed` 用真值覆盖。
	# 首版直接调 HUD 的槽函数 ⇒ 等帧期间被覆盖回"就绪"，截出来的是一整圈白环。
	var dash_cooldown := float(dungeon.player.get_dash_cooldown_duration())
	dungeon.player.dash_cooldown_timer = dash_cooldown * 0.60
	for _frame in 3:
		await get_tree().physics_frame
	await _shoot("player_vitals_feedback_4_dash_cd", dungeon)

	# —— ③b 就绪（满圈转白 + 就绪闪光）——
	dungeon.player.dash_cooldown_timer = 0.0
	for _frame in 3:
		await get_tree().physics_frame
	await _shoot("player_vitals_feedback_5_dash_ready", dungeon)

	var gauge := dungeon.get_player_dash_gauge_snapshot()
	print(
		"CAPTURE_PLAYER_VITALS_FEEDBACK_META dash_ready=%s cooldown=%.3f ring_diameter=%.1f"
		% [
			str(gauge.get("ready", false)),
			float(gauge.get("cooldown_ratio", -1.0)),
			float(gauge.get("ring", {}).get("outer_diameter_px", -1.0)),
		]
	)
	print("CAPTURE_PLAYER_VITALS_FEEDBACK_OK")
	get_tree().quit(0)


func _shoot(tag: String, dungeon: Dungeon3D) -> void:
	# 两帧再等 `frame_post_draw`：`process_frame` 在 `_process` **之前**发出，
	# 只等一次等于"还没刷新就读"。
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		print("CAPTURE_PLAYER_VITALS_FEEDBACK_FAIL null_image %s" % tag)
		return
	image.convert(Image.FORMAT_RGBA8)
	var full_path := "%s/%s.png" % [OUT_DIR, tag]
	var err := image.save_png(full_path)
	# 左上状态块放大图：全屏图里血条只有 176×21 px，"斜杆够不够暗"在那上面判不了。
	var box := ZOOM_BOX.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var zoom_path := "%s/%s_zoom.png" % [OUT_DIR, tag]
	var zoom_error := -1
	if not box.has_area():
		print("CAPTURE_PLAYER_VITALS_FEEDBACK_FAIL bad_zoom_box %s" % tag)
	elif image.get_region(box) != null:
		var zoom := image.get_region(box)
		zoom.resize(box.size.x * ZOOM_FACTOR, box.size.y * ZOOM_FACTOR, Image.INTERPOLATE_NEAREST)
		zoom_error = zoom.save_png(zoom_path)
	var vitals := dungeon.get_player_vitals_bar_snapshot()
	var heal: Dictionary = vitals.get("heal", {})
	print(
		"CAPTURE_PLAYER_VITALS_FEEDBACK_SHOT %s err=%d zoom_err=%d hp=%.2f delayed=%.2f shake=%s offset=%s heal_active=%s lead=%.2f"
		% [
			tag, err, zoom_error,
			float(vitals.get("actual_ratio", -1.0)),
			float(vitals.get("delayed_ratio", -1.0)),
			str(vitals.get("shake_active", false)),
			str(vitals.get("shake_offset", Vector2.ZERO)),
			str(heal.get("active", false)),
			float(heal.get("lead_ratio", -1.0)),
		]
	)
