extends Node
## 音乐系统验收：Catalog + MusicManager 切曲 + 总线音量。

const Catalog = preload("res://src/audio/MusicCatalog.gd")

func _ready() -> void:
	var failures: Array[String] = []

	# 1. 4 个 music_id 必须注册
	var expected_ids := ["base_passion", "rooftop_relax", "descent_suspense", "boss_intense"]
	for music_id in expected_ids:
		if not Catalog.has_music_id(music_id):
			failures.append("music_id 未注册: %s" % music_id)
		else:
			var entry := Catalog.get_entry(music_id)
			var tracks: Array = entry.get("tracks", [])
			if tracks.size() < 2:
				failures.append("%s 必须有 ≥2 个版本（A/B 随机）" % music_id)

	# 2. 所有音频文件存在
	for music_id in expected_ids:
		var entry := Catalog.get_entry(music_id)
		for track_path in entry.get("tracks", []):
			if not ResourceLoader.exists(track_path):
				failures.append("音频缺失: %s" % track_path)

	# 3. MusicManager autoload 必须可访问 + Music 总线存在
	var mgr := get_node_or_null("/root/MusicManager")
	if mgr == null:
		failures.append("MusicManager autoload 未注册")
	else:
		var bus_idx := AudioServer.get_bus_index("Music")
		if bus_idx < 0:
			failures.append("Music 总线不存在")

		# 4. 重复 play() 不应中断音频
		mgr.play("base_passion")
		await get_tree().process_frame
		var v1 = mgr.get_current_music_id()
		await get_tree().process_frame
		mgr.play("base_passion")
		await get_tree().process_frame
		var v2 = mgr.get_current_music_id()
		if v1 != "base_passion" or v2 != "base_passion":
			failures.append("play() 重复调用应保持同一曲目")

		# 5. push_and_play() 后 restore() 应回到上一首
		mgr.hard_reset()
		mgr.play("descent_suspense")
		await get_tree().process_frame
		mgr.push_and_play("boss_intense")
		await get_tree().process_frame
		if mgr.get_current_music_id() != "boss_intense":
			failures.append("push_and_play(boss_intense) 应切换到 boss_intense")
		mgr.restore()
		await get_tree().process_frame
		if mgr.get_current_music_id() != "descent_suspense":
			failures.append("restore() 后应回到 descent_suspense（实际: %s）" % mgr.get_current_music_id())

		# 6. 未知 music_id 应报错不崩
		mgr.hard_reset()
		mgr.play("base_passion")
		await get_tree().process_frame
		var before: String = mgr.get_current_music_id()
		mgr.play("__nonexistent__")
		await get_tree().process_frame
		if mgr.get_current_music_id() != before:
			failures.append("未知 music_id 不应改变当前曲目")

		# 7. stop() 后栈应清空，restore() 应 stop() 而非回到已清栈
		mgr.hard_reset()
		mgr.play("descent_suspense")
		mgr.push_and_play("boss_intense")
		mgr.stop()
		# stop() 后栈清空 → restore() 内部调 stop() → 仍 stop()，不报错
		var restore_ok = mgr.restore()
		if restore_ok:
			failures.append("栈清空后 restore() 应返回 false")

	if failures.is_empty():
		print("MUSIC_SYSTEM_OK: catalog ok, autoload ok, A/B loaded, repeat-play stable, push/restore works, unknown-id rejected")
		get_tree().quit(0)
		return
	for f in failures:
		push_error(f)
	get_tree().quit(1)