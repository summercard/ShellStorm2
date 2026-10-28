extends Node3D
## 探针：核对「情报室 → 关卡」这条链上的**每一道判定**，逐项打印。
##
## 链上有三处可能把人挡住，而它们的失败表现完全不同：
##   ① 牌面文案 —— 由 `RogueMapSelectMenu._entry_hint_text()` 决定（玩家先看到它）；
##   ② 点击判定 —— `entry_state()`：场景在不在 + 解没解锁；
##   ③ 真正出发 —— `select_expedition_level()` 是否接受这个 id。
## 只验①会得到"牌面说能进"，只验②会得到"能进但按钮没反应"，都不算数。
##
## 为什么用 tscn 场景而不是 `--script`：后者不加载 autoload，`BaseManager` 不可用。

const MENU_SCRIPT := preload("res://scenes/RogueMapSelectMenu.gd")

func _ready() -> void:
	await get_tree().process_frame
	var menu := MENU_SCRIPT.new()
	var failed: Array[String] = []
	for level_id in GameDesignConfig.expedition_level_ids():
		var path := GameDesignConfig.expedition_level_scene(level_id)
		var scene_ok := ResourceLoader.exists(path)
		var unlocked := BaseManager.is_expedition_level_unlocked(level_id)
		var state: String = menu.entry_state(level_id)
		var hint: String = menu._entry_hint_text(level_id)
		var selectable := GameDesignConfig.select_expedition_level(level_id)
		GameDesignConfig.pending_expedition_level_id = ""
		var passable := bool(scene_ok) and unlocked and state == "open" \
			and hint.begins_with("点击进入") and selectable
		if not passable:
			failed.append(level_id)
		print("UNLOCK_PROBE %-16s scene=%-5s unlocked=%-5s state=%-11s select=%-5s hint=%-18s %s" % [
			level_id, str(scene_ok), str(unlocked), state, str(selectable), hint,
			"可进" if passable else "★进不去"])
	print("UNLOCK_PROBE %s" % ("OK" if failed.is_empty() else "FAIL:" + str(failed)))
	menu.free()
	get_tree().quit(0 if failed.is_empty() else 1)
