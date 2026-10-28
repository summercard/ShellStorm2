extends Node
## 实拍：左下角「遭遇倒计时环」的位置、直径，以及圆心那行时间。
## 2026-10-28 业主裁定从右上挪到左下（原位置与小地图矩形拼图重叠）。
##
## 只在**窗口模式**下产出 PNG —— `--headless` 下 `RenderingServer.frame_post_draw`
## 不触发，截图会被静默跳过（这张图会变成"没有证据"，比没有更糟）。
##
## 与 `capture_run_loot_readout.gd` 同一口径：那次拍的是业主指定的**右下角金币读数**，
## 这次拍的是业主指定的**左下角倒计时环** —— 两处都是"指定的位置 + 指定的字体"，
## 都属于必须亲眼看过才算数的改动，不能用 headless 的几何断言代替。
##
## 读根视口纹理的两条硬口径（2026-10-14 记进 CHANGELOG，别重踩）：
##   · 必须等 `RenderingServer.frame_post_draw`，只等 `process_frame` 会拿到**全透明空图**；
##   · 读回的帧格式可能是浮点（`FORMAT_RGBAH`），要显式 `convert()` 再做像素比较。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_KEY := "room_03"
const SEED_VALUE := 77001199
## 两个时刻各拍一张：一张"整圈"的图证明不了环会随倒计时收缩。
## 38 s 与 55 s 之间，剩下的弧从 132° 缩到 30° —— 肉眼与像素都能判。
const SHOTS: Array[float] = [38.0, 55.0]
const OUT_DIR := "res://outputs/verification"


func _ready() -> void:
	var tower := SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	add_child(tower)
	for _frame in 12:
		await get_tree().process_frame

	var room := tower._room_by_id.get(ROOM_KEY) as DungeonRoom3D
	if room == null:
		print("CAPTURE_ENCOUNTER_COUNTDOWN_RING_FAIL room_missing")
		get_tree().quit(1)
		return

	room.ensure_shell_built()
	room.ensure_detail_built()
	tower.player.global_position = room.global_position + Vector3(0.0, 0.5, 0.0)
	tower.force_enter_room_for_test(ROOM_KEY)
	for _frame in 6:
		await get_tree().process_frame

	var elapsed := 0.0
	var index := 0
	for target_sec in SHOTS:
		# 逐步推进而不是一次跳到目标：一次跳会让 `_process` 里的世界只过一帧，
		# 而 `tick` 是幂等累加的 —— 分两次更贴近"倒计时在走"的真实过程。
		tower._encounter_event_director.tick(target_sec - elapsed)
		elapsed = target_sec
		index += 1
		# 跑够两帧把环刷到刚推进的位置再取帧：`SceneTree.process_frame` 是在
		# `_process` **之前**发出的，只等一次等于"还没刷新就读"。
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var out_path := "%s/encounter_countdown_ring_%d.png" % [OUT_DIR, index]
		var err := image.save_png(out_path)
		var ring := tower._hud_countdown_ring
		var ring_row := ring.get_snapshot() if ring != null else {}
		if err == OK:
			print(
				"CAPTURE_ENCOUNTER_COUNTDOWN_RING_OK %s %dx%d elapsed=%.0f visible=%s text=%s ratio=%.3f center=%s diameter_px=%.1f"
				% [
					out_path, image.get_width(), image.get_height(), elapsed,
					str(ring_row.get("visible", false)), str(ring_row.get("text", "")),
					float(ring_row.get("remaining_ratio", -1.0)),
					str(ring_row.get("center", Vector2.ZERO)),
					float(ring_row.get("outer_diameter_px", 0.0)),
				]
			)
		else:
			print("CAPTURE_ENCOUNTER_COUNTDOWN_RING_FAIL err=%d" % err)
	get_tree().quit(0)
