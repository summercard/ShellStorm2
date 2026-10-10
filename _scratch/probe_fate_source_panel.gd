extends Node
## 临时探针：验证 FateSourceSelectionPanel 的图标卡片真的把 icon_item 变成了正确机型，
## 且取景不出框。headless 下 SubViewport 不产出像素，但 ItemModelIcon3D 的取景量是**几何计算**，
## 所以 mesh_count / model_kind / fit_ratio / center_error_pixels 都能在无头下读出并断言。

const PANEL_SCRIPT := "res://src/ui/FateSourceSelectionPanel.gd"

var _failed := 0


func _check(ok: bool, label: String, extra := "") -> void:
	print(("PROBE_OK   " if ok else "PROBE_FAIL "), label, (" | " + extra) if extra != "" else "")
	if not ok:
		_failed += 1


func _ready() -> void:
	await get_tree().process_frame
	var registry := ItemRegistry.get_instance()
	_check(registry != null, "ItemRegistry 可用")
	if registry == null:
		get_tree().quit(1)
		return

	# --- 用例 1：带 icon_item 的武器来源 → 应出现图标卡片 ---
	var weapon: Dictionary = registry.get_item("weapon_sprinkler").duplicate(true)
	var accent := Color(0.34, 0.92, 0.56)
	var icon_entries: Array[Dictionary] = [{
		"source": null,
		"supported": true,
		"label": "花洒机枪 · #000493",
		"icon_item": weapon,
		"title": str(weapon.get("name", "?")),
		"subtitle": "当前装备 · 实例 #000493",
		"badge": "命运槽 0/4",
		"accent": accent,
	}]
	var panel := (load(PANEL_SCRIPT) as GDScript).new() as Window
	get_tree().root.add_child(panel)
	panel.call("open_choices", "战车 · 选择来源", icon_entries, "探针说明文字")
	await get_tree().process_frame
	await get_tree().process_frame

	var icon := panel.find_child("SourceModelIcon3D", true, false)
	_check(icon != null, "图标卡片生成了 SourceModelIcon3D 节点")
	if icon != null:
		var snapshot: Dictionary = icon.call("get_snapshot")
		print("PROBE_SNAPSHOT ", JSON.stringify(snapshot))
		_check(str(snapshot.get("model_kind", "")) == "weapon",
			"model_kind == weapon", str(snapshot.get("model_kind", "")))
		_check(int(snapshot.get("mesh_count", 0)) > 0,
			"模型有网格", "mesh_count=%d" % int(snapshot.get("mesh_count", 0)))
		_check(float(snapshot.get("fit_ratio", 9.0)) <= 1.0,
			"取景不出框（fit_ratio<=1）", "fit_ratio=%.3f" % float(snapshot.get("fit_ratio", 9.0)))
		var offset: Vector2 = snapshot.get("center_error_pixels", Vector2.ZERO)
		_check(absf(offset.x) < 8.0 and absf(offset.y) < 8.0,
			"居中偏差 < 8px", "offset=%s" % str(offset))
	_check(panel.find_child("ChoiceTitle", true, false) != null, "卡片有 ChoiceTitle 文本")
	_check(panel.find_child("TextChoice", true, false) == null, "带图标时不出现纯文字行")
	panel.queue_free()
	await get_tree().process_frame

	# --- 用例 2：不带 icon_item（待领命运奖励路径）→ 应回退纯文字行 ---
	var text_entries: Array[Dictionary] = [{
		"source": null,
		"supported": true,
		"label": "愚者 · 逆位 · 30魂",
	}]
	var panel2 := (load(PANEL_SCRIPT) as GDScript).new() as Window
	get_tree().root.add_child(panel2)
	panel2.call("open_choices", "待领命运", text_entries)
	await get_tree().process_frame
	var text_choice := panel2.find_child("TextChoice", true, false)
	_check(text_choice != null, "无 icon_item 时回退 TextChoice")
	_check(panel2.find_child("SourceModelIcon3D", true, false) == null, "回退路径不生成图标占位")
	panel2.queue_free()

	print("PROBE_FATE_SOURCE_PANEL_%s failed=%d" % ["OK" if _failed == 0 else "FAILED", _failed])
	get_tree().quit(0 if _failed == 0 else 1)
