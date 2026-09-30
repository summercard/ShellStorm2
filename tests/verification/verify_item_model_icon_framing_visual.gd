extends Node
## 3D 图标取景验收（真实渲染器）。
##
## 背景：2026-09-30 主人反馈「图标栏中，物品如果大于图标尺寸，会被切，而且居中位置
## 不对」。ItemModelIcon3D 的取景因此从「按模型种类写死相机米数 + 调用点写死倍率 +
## 写死位移」改成「按模型实际投影自适应」。本用例就是那次改动的会失败断言：
## **换物品、换图标格几何，都必须同时满足「不出框 + 居中 + 填得满 + 视口跟随格子长宽比」**。
##
## 两层口径都查，且以不被算法自我复述的那一层为准：
##   ① 几何层（Snapshot 读数）：fit_ratio ≤ 1.0、center_error_pixels ≤ 2px。
##      这一层较弱 —— 位移就是按同一个投影算的，只能证明「位移确实执行了」。
##   ② 渲染层（真实绘制像素）：margin_min ≥ 1px（四周都不贴边 = 没被切）、已绘像素
##      包围盒中心与图标中心的偏差 ≤ 2px（居中）、较长边填充 ≥ 0.5（没缩成一颗芝麻）。
##      这一层是独立证据：算法算错、或曲面凸出外接盒，都会被它抓到。
## 另外驱动真实挂载点（Dungeon3D HUD 武器格 + InventoryUI 背包格）复核一次。
##
## 产物：outputs/verification/item_model_icon_framing_sheet.png（带标签的联系表，供人眼复核）。

const ICON_SCENE: PackedScene = preload("res://assets/art/ui/inventory_3d/ui_item_model_icon_root.tscn")
const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
const SHEET_PATH := "res://outputs/verification/item_model_icon_framing_sheet.png"

## 真实挂载点的图标格几何（控件像素尺寸）。取自调用点实测：
##   hud_weapon       Dungeon3D HUD 武器格 = _hud_size(64, 46)，HUD_UI_SCALE 0.80
##   inventory_slot   InventoryUI SLOT_SIZE 78 − 上下左右各 4px inset
##   vending_card     BaseVendingMenu 96×96
##   attachment_slot  InventoryUI 配件格 40 − 上下左右各 4px inset
const SLOT_GEOMETRIES := [
	{"label": "hud_weapon", "size": Vector2(51.2, 36.8)},
	{"label": "inventory_slot", "size": Vector2(70.0, 70.0)},
	{"label": "vending_card", "size": Vector2(96.0, 96.0)},
	{"label": "attachment_slot", "size": Vector2(32.0, 32.0)},
]

## 物品集刻意包含「大于图标尺寸」的细长件（狙击枪/巨剑/战斧/球棒）——
## 主人截图里被切的就是这类。
const ITEMS := [
	"weapon_pistol",
	"weapon_rifle",
	"weapon_shotgun",
	"weapon_sniper",
	"weapon_launcher",
	"weapon_machinegun",
	"weapon_greatblade",
	"weapon_waraxe",
	"weapon_baseball_bat",
	"item_health_potion",
	"item_room_key",
	"item_beacon",
]

const FIT_RATIO_LIMIT := 1.0
const CENTER_TOLERANCE_PIXELS := 2.0
const MIN_MARGIN_PIXELS := 1.0
const MIN_FILL_RATIO := 0.5

## 联系表版式：每格 112px 间距、图标区 96px，左侧一列写格子名、顶部一行写物品名。
const SHEET_WINDOW := Vector2i(1360, 604)
const SHEET_CELL := 112.0
const SHEET_COLUMN_HEADER := 26.0
const SHEET_ROW_HEADER := 96.0


func _ready() -> void:
	VerificationOutput.prepare()
	DisplayServer.window_set_size(SHEET_WINDOW)
	var failures: Array[String] = []
	var sheet := _build_sheet()
	await get_tree().process_frame

	var cells: Array[Dictionary] = []
	for geometry in SLOT_GEOMETRIES:
		for item_id in ITEMS:
			var item := ItemRegistry.get_instance().get_item(item_id)
			if item.is_empty():
				failures.append("Cannot resolve item %s for icon framing acceptance" % item_id)
				continue
			var cell := await _render_icon_cell(geometry, item, item_id, sheet)
			cells.append(cell)
			_check_cell(cell, failures)

	_check_aspect_tracks_slot(cells, failures)
	await get_tree().process_frame
	_save_sheet(failures)
	await _verify_live_call_sites(failures)

	if failures.is_empty():
		print(
			(
				"ITEM_MODEL_ICON_FRAMING_VISUAL_OK: %d cells across %d slot geometries keep"
				+ " fit_ratio<=%.1f, no drawn-pixel clipping (margin>=%.0fpx), centered"
				+ " (<=%.0fpx) and filled (>=%.2f); viewport aspect follows slot aspect"
			)
			% [
				cells.size(),
				SLOT_GEOMETRIES.size(),
				FIT_RATIO_LIMIT,
				MIN_MARGIN_PIXELS,
				CENTER_TOLERANCE_PIXELS,
				MIN_FILL_RATIO,
			]
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


# --- 联系表（人眼复核用） ---------------------------------------------------


func _build_sheet() -> Control:
	var sheet := Control.new()
	sheet.name = "Sheet"
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sheet)
	var background := ColorRect.new()
	background.color = Color(0.10, 0.11, 0.13)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(background)
	for column in ITEMS.size():
		var header := _make_label(ITEMS[column], 11)
		header.position = Vector2(
			SHEET_ROW_HEADER + SHEET_CELL * float(column), 2.0
		)
		header.size = Vector2(SHEET_CELL, SHEET_COLUMN_HEADER)
		sheet.add_child(header)
	for row in SLOT_GEOMETRIES.size():
		var geometry: Dictionary = SLOT_GEOMETRIES[row]
		var label := _make_label(
			"%s\n%.0fx%.0f" % [str(geometry["label"]), (geometry["size"] as Vector2).x, (geometry["size"] as Vector2).y],
			10
		)
		label.position = Vector2(2.0, SHEET_COLUMN_HEADER + SHEET_CELL * float(row) + 30.0)
		label.size = Vector2(SHEET_ROW_HEADER - 6.0, SHEET_CELL - 30.0)
		sheet.add_child(label)
	return sheet


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.94))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _save_sheet(failures: Array[String]) -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		failures.append("Icon framing contact sheet is empty")
		return
	if image.save_png(SHEET_PATH) != OK:
		failures.append("Cannot save icon framing contact sheet to %s" % SHEET_PATH)


# --- 单格：真实渲染一个图标并量几何 + 像素 -----------------------------------


func _render_icon_cell(
	geometry: Dictionary, item: Dictionary, item_id: String, sheet: Control
) -> Dictionary:
	var index := _cell_index(geometry, item_id)
	var cell_origin := Vector2(
		SHEET_ROW_HEADER + SHEET_CELL * float(index.x), SHEET_COLUMN_HEADER + SHEET_CELL * float(index.y)
	)
	var host := Control.new()
	host.size = geometry["size"]
	host.custom_minimum_size = geometry["size"]
	host.position = cell_origin + (Vector2(SHEET_CELL, SHEET_CELL) - (geometry["size"] as Vector2)) * 0.5
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(host)
	var icon := ICON_SCENE.instantiate() as ItemModelIcon3D
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(icon)
	await get_tree().process_frame
	icon.configure(item)
	await get_tree().process_frame
	await get_tree().process_frame
	var viewport := icon.get("_viewport") as SubViewport
	var image := viewport.get_texture().get_image() if viewport != null else null
	var stats := _alpha_stats(image)
	return {
		"slot": str(geometry["label"]),
		"item_id": item_id,
		"snapshot": icon.get_snapshot(),
		"pixels": stats,
	}


func _cell_index(geometry: Dictionary, item_id: String) -> Vector2i:
	return Vector2i(ITEMS.find(item_id), _geometry_index(str(geometry["label"])))


func _geometry_index(label: String) -> int:
	for index in SLOT_GEOMETRIES.size():
		if str((SLOT_GEOMETRIES[index] as Dictionary)["label"]) == label:
			return index
	return 0


# --- 断言 -------------------------------------------------------------------


func _check_cell(cell: Dictionary, failures: Array[String]) -> void:
	var slot := str(cell["slot"])
	var item_id := str(cell["item_id"])
	var snapshot: Dictionary = cell["snapshot"]
	var pixels: Dictionary = cell["pixels"]
	var tag := "%s / %s" % [slot, item_id]

	if int(snapshot.get("mesh_count", 0)) <= 0:
		failures.append("%s rendered an empty 3D projection" % tag)
	if not bool(snapshot.get("update_once", false)):
		failures.append("%s is not a one-shot projection" % tag)

	var fit_ratio := float(snapshot.get("fit_ratio", 99.0))
	if fit_ratio > FIT_RATIO_LIMIT + 0.0001:
		failures.append(
			(
				"%s geometric projection overflows the icon frame: fit_ratio=%.3f > %.2f"
				% [tag, fit_ratio, FIT_RATIO_LIMIT]
			)
		)
	var projected: Vector2 = snapshot.get("projected_half_extents", Vector2.ZERO)
	if projected.x <= 0.0 or projected.y <= 0.0:
		failures.append("%s geometric projection has no extent" % tag)
	var center_error := float((snapshot.get("center_error_pixels", Vector2.ZERO) as Vector2).length())
	if center_error > CENTER_TOLERANCE_PIXELS:
		failures.append(
			(
				"%s geometric framing is off-center by %.2fpx > %.1fpx"
				% [tag, center_error, CENTER_TOLERANCE_PIXELS]
			)
		)

	if int(pixels.get("count", 0)) <= 0:
		failures.append("%s drew no pixels at all" % tag)
		return
	var margin := float(pixels.get("margin_min", -1.0))
	if margin < MIN_MARGIN_PIXELS:
		failures.append(
			"%s drawn pixels touch the icon border: margin_min=%.1fpx < %.1fpx (clipped)" % [
				tag, margin, MIN_MARGIN_PIXELS
			]
		)
	var drawn_center := float((pixels.get("center_error", Vector2.ZERO) as Vector2).length())
	if drawn_center > CENTER_TOLERANCE_PIXELS:
		failures.append(
			"%s drawn pixels are off-center by %.2fpx > %.1fpx" % [tag, drawn_center, CENTER_TOLERANCE_PIXELS]
		)
	var fill := float(pixels.get("fill", 0.0))
	if fill < MIN_FILL_RATIO:
		failures.append(
			"%s drawn pixels only fill %.3f of the long edge (< %.2f): model is unreadably small" % [
				tag, fill, MIN_FILL_RATIO
			]
		)


## 宽图标格必须拿宽视口：正方形视口塞进 HUD 那种 51×37 的格子，模型用不上横向空间，
## 看上去就成了「左右各空一条、其实是没居中」。
func _check_aspect_tracks_slot(cells: Array[Dictionary], failures: Array[String]) -> void:
	var checked := 0
	for cell in cells:
		var slot := str(cell["slot"])
		var geometry_size := (SLOT_GEOMETRIES[_geometry_index(slot)] as Dictionary)["size"] as Vector2
		var viewport_size: Vector2i = (cell["snapshot"] as Dictionary).get("viewport_size", Vector2i.ZERO)
		if viewport_size.x <= 0 or viewport_size.y <= 0:
			failures.append("%s has a degenerate viewport size %s" % [slot, str(viewport_size)])
			continue
		var slot_aspect := geometry_size.x / maxf(geometry_size.y, 0.0001)
		var viewport_aspect := float(viewport_size.x) / float(viewport_size.y)
		if absf(slot_aspect - viewport_aspect) > 0.05:
			failures.append(
				(
					"%s viewport aspect %.3f does not follow the slot aspect %.3f"
					% [slot, viewport_aspect, slot_aspect]
				)
			)
		if slot_aspect > 1.05 and viewport_size.y >= viewport_size.x:
			failures.append("%s wide slot still renders into a non-wide viewport %s" % [slot, str(viewport_size)])
		checked += 1
	if checked == 0:
		failures.append("No icon cell was available to check viewport aspect tracking")


# --- 真实挂载点复核 ---------------------------------------------------------


## 直接读真实装配点的快照：HUD 武器格装一把大件（巨剑），背包格放细长件。
## 这两处正是主人截图里被切的场景，取值不走本用例自建的控件。
func _verify_live_call_sites(failures: Array[String]) -> void:
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 240725
	add_child(dungeon)
	await get_tree().process_frame
	await get_tree().process_frame

	var greatblade := ItemRegistry.get_instance().get_item("weapon_greatblade")
	if greatblade.is_empty():
		failures.append("Cannot resolve weapon_greatblade for live HUD icon acceptance")
	else:
		var equip := dungeon.player.equip_weapon_item_to_slot(greatblade, 0)
		if not bool(equip.get("success", false)):
			failures.append("Cannot equip the greatblade for live HUD icon acceptance")
		await get_tree().process_frame
		await get_tree().process_frame
		var hud_snapshot := dungeon.get_hud_weapon_model_snapshot()
		if str(hud_snapshot.get("model_kind", "")) != "weapon":
			failures.append(
				"Live HUD weapon icon did not receive the greatblade model (kind=%s)"
				% str(hud_snapshot.get("model_kind", ""))
			)
		else:
			_check_live_snapshot("live HUD weapon icon (greatblade)", hud_snapshot, failures)

	var inventory := dungeon.get_inventory_module()
	var inventory_ui := dungeon.get_node_or_null("HUD/InventoryUI3D") as InventoryUI
	if inventory == null or inventory_ui == null:
		failures.append("Cannot resolve the live inventory for icon framing acceptance")
		return
	for item_id in ["weapon_greatblade", "weapon_waraxe", "weapon_baseball_bat"]:
		var item := ItemRegistry.get_instance().get_item(item_id)
		if item.is_empty() or inventory.add_item(item, 1) <= 0:
			failures.append("Cannot stage %s into the live inventory" % item_id)
			continue
	inventory_ui.set_inventory_panel_open(true)
	await get_tree().process_frame
	await get_tree().process_frame
	for item_id in ["weapon_greatblade", "weapon_waraxe", "weapon_baseball_bat"]:
		var slot_index := _find_slot(inventory, item_id)
		if slot_index < 0:
			failures.append("Cannot find the staged %s slot in the live inventory" % item_id)
			continue
		var slot_snapshot := inventory_ui.get_slot_model_snapshot(slot_index)
		if int(slot_snapshot.get("mesh_count", 0)) <= 0:
			failures.append("Live inventory slot for %s has an empty 3D projection" % item_id)
			continue
		_check_live_snapshot("live inventory slot (%s)" % item_id, slot_snapshot, failures)
	inventory_ui.set_inventory_panel_open(false)
	inventory.clear_all()
	dungeon.queue_free()
	await get_tree().process_frame


func _check_live_snapshot(tag: String, snapshot: Dictionary, failures: Array[String]) -> void:
	var fit_ratio := float(snapshot.get("fit_ratio", 99.0))
	if fit_ratio > FIT_RATIO_LIMIT + 0.0001:
		failures.append(
			"%s overflows its icon frame: fit_ratio=%.3f > %.2f" % [tag, fit_ratio, FIT_RATIO_LIMIT]
		)
	if float(snapshot.get("fit_ratio", 0.0)) <= 0.0:
		failures.append("%s did not measure its framing at all" % tag)
	var center_error := float((snapshot.get("center_error_pixels", Vector2.ZERO) as Vector2).length())
	if center_error > CENTER_TOLERANCE_PIXELS:
		failures.append(
			"%s is off-center by %.2fpx > %.1fpx" % [tag, center_error, CENTER_TOLERANCE_PIXELS]
		)


func _find_slot(inventory: InventoryModule, item_id: String) -> int:
	for entry in inventory.get_occupied_slots():
		if str((entry.get("item", {}) as Dictionary).get("id", "")) == item_id:
			return int(entry.get("slot", -1))
	return -1


# --- 像素统计 ---------------------------------------------------------------


## 已绘像素（alpha > 0.03）的包围盒统计。
func _alpha_stats(image: Image) -> Dictionary:
	var empty := {
		"rect": Rect2i(),
		"count": 0,
		"fill": 0.0,
		"margin_min": 0.0,
		"center_error": Vector2.ZERO,
	}
	if image == null or image.is_empty():
		return empty
	var image_size := image.get_size()
	var min_x := image_size.x
	var min_y := image_size.y
	var max_x := -1
	var max_y := -1
	var count := 0
	for y in image_size.y:
		for x in image_size.x:
			if image.get_pixel(x, y).a > 0.03:
				count += 1
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if count == 0:
		return empty
	var drawn := Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	var center := Vector2(drawn.position) + Vector2(drawn.size) * 0.5
	return {
		"rect": drawn,
		"count": count,
		# 取「较长边方向」的占比：细长件（剑/斧/球棒）本来就该顶满长边，
		# 用短边占比衡量它们会把「顶满长边」误判成「没填满」。
		"fill": maxf(float(drawn.size.x) / float(image_size.x), float(drawn.size.y) / float(image_size.y)),
		"margin_min": float(mini(mini(min_x, min_y), mini(image_size.x - 1 - max_x, image_size.y - 1 - max_y))),
		"center_error": center - Vector2(image_size) * 0.5,
	}
