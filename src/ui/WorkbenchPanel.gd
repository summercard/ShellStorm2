class_name WorkbenchPanel
extends Control
## 武器改造台 — 6×6 炼金盘（炼金抽卡）。
##
## 业主口径（2026-10-18）：把武器与弹药模块投进 6×6 的格子里熔炼，
## 产出**品质（蓝/紫/金）与弹药模块重新掷骰**的新枪。规则真源见 `WeaponForge`。
##
## 本文件只负责三件事：**盘面存放与拖拽、投入解析的可视化、熔炼事务**。
## 品质概率、熔炼值、产出构建一律调 `WeaponForge`，不在这里复写任何数值。
##
## 事务边界（与工坊同一条纪律）：
##   快照 → 销毁投入 → 写入产出 → 任一失败则盘面与背包逐字节回滚。
## 关闭面板时盘内物品必须退回背包；放不下就留在盘里并拒绝关闭，不允许直接销毁。

signal forge_completed(result: Dictionary)
signal closed

## 两个页签。`熔炼` 是默认页（玩家进改造台的第一意图是"投东西进去"），
## `合成目录` 是查阅页，回答"我该攒什么"。
const PAGE_FORGE := "forge"
const PAGE_CATALOG := "catalog"

const TRAY_KIND := "alchemy"
const BAG_KIND := "inventory"
const TRAY_COLUMNS := 5
const TRAY_ROWS := 5
const TRAY_CAPACITY := TRAY_COLUMNS * TRAY_ROWS
## 背包列数**必须**等于 `InventoryModule.GRID_COLUMNS`（8）。
##
## 物品的槽位索引是按那个列数算出来的；这里若擅自改成 6 列，同一个索引会
## 落到不同行列上，4×2 的枪就会画出棋盘右边界（截图能直接看到溢出）。
## 想让背包变窄只能改格边长，不能改列数。
const BAG_COLUMNS := 8
## 炼金盘格边长。
##
## 上限由**可用高度**决定，不是审美：1280×720 下 Pages 区只有 444px，
## 扣掉 `ALCHEMY GRID` 标签、底部说明、间距与括号内边距后剩 364，
## 5 行 ⇒ 每格 ≤ 72.8。取 70 留一点余量 —— 取 80 会把第五列/行裁掉
## （`VBoxContainer` 会压缩超尺寸的子节点，且不报错，只能靠截图发现）。
const TRAY_CELL_SIZE := 70.0
## 背包格边长：8 列 × 46 = 368 宽。再大就会顶到居中的炼炉上（1280 基准只剩 ~60px 间距）。
const BAG_CELL_SIZE := 46.0
## 炼炉与背包之间的最小空隙。两者都用绝对锚点定位，这个值只在夹紧时兜底。
const TRAY_BAG_GAP := 48.0
## 页脚状态栏的空白态文案：三条配方速记。
##
## 必须压在一行内：状态栏左侧可用宽度约 760px、字号 12，超过约 60 字就会换行，
## 换行后的第二行会顶到底部边框上（720p 基准尤其明显）。
const HINT_TEXT := "任意物品可作材料　·　材料越稀有品质越高　·　单枪＝重铸 / 两把＝融合 / 纯材料满 6＝合成"

## 盘内一格：anchor 为锚点线性下标，rotation 为 90° 转数。
const TRAY_ENTRY_ANCHOR := "anchor"
const TRAY_ENTRY_ITEM := "item"
const TRAY_ENTRY_COUNT := "count"
const TRAY_ENTRY_ROTATION := "rotation"

var _player: Player3D = null
var _workbench_ref: Node = null
var _inventory: InventoryModule = null
var _tray: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _busy := false
var _pending_plan: Dictionary = {}

var _tray_board: GridInventoryBoard = null
var _bag_board: GridInventoryBoard = null
var _bag_title: Label = null
var _body_tray_column: Control = null
var _body_bag_column: Control = null
var _active_page := PAGE_FORGE
var _forge_page: Control = null
var _catalog_page: Control = null
var _catalog_list: VBoxContainer = null
var _tabs: Dictionary = {}
## 已完成的配方集合（按 `created_recipe_id` 统计）。
##
## 存在面板实例上而不是存档里：改造台是局内设施，图鉴完成度跟随本局。
## 待做永久图鉴时，再把它挪到 `BaseData`。
var _completed_recipes: Dictionary = {}
var _stat_payload: Label = null
var _stat_melt: Label = null
var _stat_rarity: Label = null
var _stat_recipe: Label = null
var _stat_blueprint: Label = null
var _stat_grades: Label = null
var _stat_cost: Label = null
var _coins_label: Label = null
var _status: Label = null
var _forge_button: Button = null
var _footer_readout: Control = null
var _footer_actions: Control = null
var _confirm_layer: Control = null
var _confirm_text: Label = null
## 合成表现层：兔子闸门。只负责"看起来发生了什么"，事务仍在上面的 `_execute_forge` 里。
var _gate_veil: SynthesisGateVeil = null
## 闸门播放期间暂存的收尾报告（刷新 + 文案 + 信号）。播完或中途收掉时消费一次。
var _pending_forge_report: Dictionary = {}
## 闸门期间盖住背包的封条（避免产物提前剧透）。
var _bag_seal: Control = null


func set_player(player: Player3D) -> void:
	_player = player


func set_workbench_ref(ref: Node) -> void:
	_workbench_ref = ref


func _ready() -> void:
	# 面板被 add_child 到 CanvasLayer / 普通 Node 下时，Control 的锚点算不出尺寸
	# （父节点不是 Control，没有可参照的矩形），必须显式按视口铺满。
	_fit_to_viewport()
	if not get_viewport().size_changed.is_connected(_fit_to_viewport):
		get_viewport().size_changed.connect(_fit_to_viewport)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_inventory = _resolve_inventory()
	_rng.randomize()
	_build_ui()
	_refresh_all()
	if _player != null and is_instance_valid(_player):
		_player.set_input_locked(true)
	if _inventory != null and not _inventory.inventory_changed.is_connected(_on_inventory_changed):
		_inventory.inventory_changed.connect(_on_inventory_changed)
	# 金币变动要立刻反映到费用栏（不足时红字 + 按钮禁用），否则玩家得反复开关面板。
	if GameManager != null and not GameManager.currency_changed.is_connected(_on_currency_changed):
		GameManager.currency_changed.connect(_on_currency_changed)


## 铺满视口。父节点是 Control 时用父矩形，否则用视口矩形。
func _fit_to_viewport() -> void:
	var parent_control := get_parent() as Control
	var rect := get_viewport().get_visible_rect()
	var target := rect.size if parent_control == null else parent_control.size
	if target.x <= 0.0 or target.y <= 0.0:
		target = rect.size
	position = Vector2.ZERO
	size = target


func _exit_tree() -> void:
	if _inventory != null and _inventory.inventory_changed.is_connected(_on_inventory_changed):
		_inventory.inventory_changed.disconnect(_on_inventory_changed)
	if GameManager != null and GameManager.currency_changed.is_connected(_on_currency_changed):
		GameManager.currency_changed.disconnect(_on_currency_changed)
	if _player != null and is_instance_valid(_player):
		_player.set_input_locked(false)


func _on_currency_changed(_amount: int) -> void:
	_refresh_readout()


func _resolve_inventory() -> InventoryModule:
	if _workbench_ref != null and _workbench_ref.has_method("get_inventory_module"):
		return _workbench_ref.call("get_inventory_module") as InventoryModule
	return null


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or _is_key_just_pressed(event, KEY_ESCAPE):
		if _confirm_layer != null and _confirm_layer.visible:
			_cancel_confirm()
		else:
			_close()
		get_viewport().set_input_as_handled()


func _is_key_just_pressed(event: InputEvent, key: Key) -> bool:
	var key_event := event as InputEventKey
	if key_event == null:
		return false
	return (
		key_event.pressed
		and not key_event.echo
		and (key_event.keycode == key or key_event.physical_keycode == key)
	)


## ————————————————————————————————
## 界面
## ————————————————————————————————

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = UIPalette.PRISM_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# 棱镜语言：不画实心卡片。面板只留 0.46 的极淡底衬 + 四角括号，
	# 结构由 1px 细线与括号界定（规范 §1.2 铁律 1）。
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40.0
	panel.offset_top = 14.0
	panel.offset_right = -40.0
	panel.offset_bottom = -14.0
	panel.add_theme_stylebox_override("panel", UIStyleFactory.make_prism_panel(true, 0.46))
	UIStyleFactory.attach_prism_bracket_frame(panel, "solid", 30.0, 2.0)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "VBox"
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	# 版面只分三段：页头 / 主体（炼炉 + 背包）/ 页脚。
	# 业主 2026-10-18 口径：按钮直接放最底下、所有信息也放底下 ——
	# 主体区不再夹任何读数或按钮，整块竖向空间全留给盘面与背包。
	column.add_child(_build_header())
	column.add_child(_build_tabs())
	column.add_child(UIStyleFactory.make_prism_rule(UIPalette.PRISM_LINE_FAINT, 1.0))
	column.add_child(_build_pages())
	column.add_child(UIStyleFactory.make_prism_rule(UIPalette.PRISM_LINE_FAINT, 1.0))
	column.add_child(_build_footer())
	add_child(_build_confirm_layer())


## 页签：`熔炼` / `合成目录`。
##
## 按棱镜规范用 **1px 下划线**标记当前页，不给按钮底色 ——
## 底色会变成"实心卡片"，那是棱镜明确禁止的（规范 §1.2 铁律 1）。
func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.name = "Tabs"
	row.add_theme_constant_override("separation", 26)
	for entry in [[PAGE_FORGE, "熔　炼"], [PAGE_CATALOG, "合成目录"]]:
		var page_id := str(entry[0])
		var column := VBoxContainer.new()
		column.name = "Tab_%s" % page_id
		column.add_theme_constant_override("separation", 4)

		var button := Button.new()
		button.name = "TabButton_%s" % page_id
		button.text = str(entry[1])
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(96, 26)
		button.pressed.connect(_switch_page.bind(page_id))
		column.add_child(button)

		var underline := ColorRect.new()
		underline.name = "TabUnderline_%s" % page_id
		underline.custom_minimum_size = Vector2(0, 1)
		underline.color = UIPalette.PRISM_LINE
		column.add_child(underline)

		column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		row.add_child(column)
		_tabs[page_id] = {"button": button, "underline": underline}

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_apply_tab_style()
	return row


func _apply_tab_style() -> void:
	for page_id in _tabs.keys():
		var entry := _tabs[page_id] as Dictionary
		var button := entry["button"] as Button
		var underline := entry["underline"] as ColorRect
		var active := str(page_id) == _active_page
		button.add_theme_color_override(
			"font_color", UIPalette.PRISM_TEXT if active else UIPalette.PRISM_TEXT_FAINT
		)
		button.add_theme_color_override(
			"font_hover_color", UIPalette.PRISM_TEXT
		)
		button.add_theme_color_override(
			"font_pressed_color", UIPalette.PRISM_TEXT
		)
		underline.visible = active


## 分页容器：两页叠在同一块矩形里，切换只改 `visible`。
##
## 不用 `TabContainer`：它自带一套主题样式（底板 + 边线），
## 那在棱镜里是"实心卡片"，且改起来比手写一层容器更绕。
func _build_pages() -> Control:
	var pages := Control.new()
	pages.name = "Pages"
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_forge_page = _build_body()
	# 保留 "Body" 名字（`_build_body` 里设的）：它是页面的主容器，
	# 验收与文档都按这个名字找它，改成 ForgePage 会让判据失效。
	_forge_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	pages.add_child(_forge_page)

	_catalog_page = _build_catalog_page()
	_catalog_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catalog_page.visible = false
	pages.add_child(_catalog_page)
	return pages


func _switch_page(page_id: String) -> void:
	if page_id == _active_page:
		return
	# 闸门还盖着的时候切页：闸门是炼炉那一栏的子层级，页一切走就没人管了。
	# 直接收掉并补上还没做的收尾，否则切回来会看到半截闸门 + 盘上还摆着已被消耗的材料。
	if _gate_veil != null and _gate_veil.is_playing():
		_gate_veil.abort()
		_busy = false
		_flush_pending_forge_report()
	_active_page = page_id
	if _forge_page != null:
		_forge_page.visible = page_id == PAGE_FORGE
	if _catalog_page != null:
		_catalog_page.visible = page_id == PAGE_CATALOG
	_apply_tab_style()
	_apply_page_footer()
	if page_id == PAGE_CATALOG:
		_refresh_catalog()
	else:
		_refresh_readout()


## 页脚随页签切换内容。
##
## 目录页上「本次熔炼的读数 + 熔炼按钮」是误导：那里没有在熔炼，
## 玩家看到「定向合成（缺燃料）」会以为要在这个页面操作。
## 目录页只留一句完成度汇总，按钮全部隐藏。
func _apply_page_footer() -> void:
	var on_catalog := _active_page == PAGE_CATALOG
	if _footer_readout != null:
		_footer_readout.visible = not on_catalog
	if _forge_button != null:
		_forge_button.visible = not on_catalog
	if not on_catalog:
		# 回到熔炼页：把状态栏还原成配方速记（`_refresh_readout` 会再覆盖它）。
		if _status != null and str(_status.get_meta("page_hint", "")) == "catalog":
			_set_status(HINT_TEXT)
			_status.remove_meta("page_hint")
		return
	if _status == null:
		return
	_status.set_meta("page_hint", "catalog")
	var done := 0
	for recipe in SynthesisCatalog.RECIPES:
		if _recipe_done(str(recipe["recipe_id"])):
			done += 1
	var ready := 0
	for recipe in SynthesisCatalog.RECIPES:
		var progress := SynthesisCatalog.key_progress(
			recipe, _tray_weapons_for_catalog(), _tray_materials_for_catalog()
		)
		if bool(progress["complete"]):
			ready += 1
	_set_status("配方 %d 条　·　已完成 %d　·　盘面钥匙已齐 %d 条" % [
		SynthesisCatalog.RECIPES.size(), done, ready,
	])


## 合成目录页：可滚动的配方清单，按曲线段分组。
func _build_catalog_page() -> Control:
	var root := Control.new()
	root.name = "CatalogPage"

	var scroll := ScrollContainer.new()
	scroll.name = "CatalogScroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	UIStyleFactory.apply_prism_scrollbar(scroll)
	root.add_child(scroll)

	var column := VBoxContainer.new()
	column.name = "CatalogList"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	scroll.add_child(column)
	_catalog_list = column
	return root


## 重绘配方清单。每次切到本页、以及背包/盘面变动时刷新（"有/需"要跟着变）。
func _refresh_catalog() -> void:
	if _catalog_list == null:
		return
	for child in _catalog_list.get_children():
		child.queue_free()
	var weapons: Array = _tray_weapons_for_catalog()
	var materials: Array = _tray_materials_for_catalog()
	for tier_info in SynthesisCatalog.CURVE_TIERS:
		_catalog_list.add_child(_build_catalog_section(tier_info, weapons, materials))


func _build_catalog_section(tier_info: Dictionary, weapons: Array, materials: Array) -> Control:
	var section := VBoxContainer.new()
	section.name = "Section_%s" % str(tier_info["code"])
	section.add_theme_constant_override("separation", 4)

	var recipes := SynthesisCatalog.recipes_of_tier(int(tier_info["tier"]))
	var done := 0
	for recipe in recipes:
		if _recipe_done(str(recipe["recipe_id"])):
			done += 1

	# 段标题：`L0 · Hook` + 进度 + 首次体验一句。左上角是曲线的锚点。
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var code := Label.new()
	code.text = "%s　%s" % [str(tier_info["code"]), str(tier_info["name"])]
	UIStyleFactory.apply_prism_label(code, "label", 4, 11)
	head.add_child(code)
	var progress := Label.new()
	progress.text = "%d / %d" % [done, recipes.size()]
	UIStyleFactory.apply_prism_label(progress, "faint", 2, 11)
	head.add_child(progress)
	var first := Label.new()
	first.text = "首次：%s" % str(tier_info["first_experience"])
	first.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	first.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UIStyleFactory.apply_prism_label(first, "faint", 1, 11)
	head.add_child(first)
	section.add_child(head)

	for recipe in recipes:
		section.add_child(_build_catalog_row(recipe, weapons, materials))
	section.add_child(UIStyleFactory.make_prism_rule(UIPalette.PRISM_LINE_FAINT, 1.0))
	return section


## 一行配方。三块信息：产物 / 钥匙进度 / 门槛，右侧状态。
##
## 不显示"未解锁 = ???"：本项目的配方全是"钥匙够了就能做"，
## 没有前置解锁条件，遮起来只会让玩家以为漏了什么。
func _build_catalog_row(recipe: Dictionary, weapons: Array, materials: Array) -> Control:
	var row := HBoxContainer.new()
	row.name = "Recipe_%s" % str(recipe["recipe_id"])
	row.custom_minimum_size = Vector2(0, 30)
	row.add_theme_constant_override("separation", 16)

	var product := ItemRegistry.get_instance().get_item(str(recipe["product_id"]))
	var product_name := str(product.get("name", recipe["product_id"]))
	var rarity := str(product.get("rarity", "common"))

	var name_label := Label.new()
	name_label.text = product_name
	name_label.custom_minimum_size = Vector2(132, 0)
	UIStyleFactory.apply_prism_label(name_label, "value", 1, 13)
	row.add_child(name_label)

	var key_definition := ItemRegistry.get_instance().get_item(str(recipe["key_item_id"]))
	var progress := SynthesisCatalog.key_progress(recipe, weapons, materials)
	var key_label := Label.new()
	key_label.text = "%s　%d / %d" % [
		str(key_definition.get("name", recipe["key_item_id"])),
		int(progress["have"]),
		int(progress["need"]),
	]
	key_label.custom_minimum_size = Vector2(232, 0)
	# 够了用近白，不够用弱灰 —— 这是"还差多少"的主要视觉信号。
	UIStyleFactory.apply_prism_label(key_label, "value" if bool(progress["complete"]) else "faint", 1, 12)
	row.add_child(key_label)

	var gate := Label.new()
	gate.text = "燃料 %d · 金币 %d" % [int(recipe["fuel_min"]), int(recipe["coin_cost"])]
	gate.custom_minimum_size = Vector2(140, 0)
	UIStyleFactory.apply_prism_label(gate, "faint", 1, 12)
	row.add_child(gate)

	var effect := _catalog_effect_text(recipe, rarity)
	var pity_note := _catalog_pity_text(recipe)
	if not pity_note.is_empty():
		effect = "%s · %s" % [effect, pity_note]
	var effect_label := Label.new()
	effect_label.text = effect
	effect_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIStyleFactory.apply_prism_label(effect_label, "faint", 1, 11)
	row.add_child(effect_label)

	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.custom_minimum_size = Vector2(88, 0)
	if _recipe_done(str(recipe["recipe_id"])):
		status.text = "已完成"
		UIStyleFactory.apply_prism_label(status, "label", 3, 11)
	elif bool(progress["complete"]):
		status.text = "钥匙已齐"
		UIStyleFactory.apply_prism_label(status, "value", 3, 11)
	else:
		status.text = "缺 %d 个" % (int(progress["need"]) - int(progress["have"]))
		UIStyleFactory.apply_prism_label(status, "faint", 3, 11)
	row.add_child(status)
	return row


## 保底进度，只对被保底的那条配方（目前只有蓄力炮）显示。
##
## 必须让玩家看见"连着几次没出"。保底兜的是**绝望**，而看不见的保底
## 救不了绝望 —— 玩家只会觉得"这枪根本刷不出来"，然后不刷了。
func _catalog_pity_text(recipe: Dictionary) -> String:
	var key := str(recipe["key_item_id"])
	if not key in SynthesisCatalog.PITY_KEYS:
		return ""
	var misses := BaseManager.get_synthesis_pity_misses(key)
	return "保底 %d/%d" % [
		mini(misses, int(SynthesisCatalog.PITY_THRESHOLD)),
		int(SynthesisCatalog.PITY_THRESHOLD),
	]


## 一行小字：稀有度 + 预装弹种/配件。只在有值时才提，不写"无"。
func _catalog_effect_text(recipe: Dictionary, rarity: String) -> String:
	var parts: Array[String] = [rarity]
	var bullet := str(recipe.get("preload_bullet", ""))
	if not bullet.is_empty():
		var bullet_definition := ItemRegistry.get_instance().get_item(bullet)
		parts.append("预装%s" % str(bullet_definition.get("name", bullet)))
	var attachments := int(recipe.get("preload_attachments", 0))
	if attachments > 0:
		parts.append("附 %d 配件" % attachments)
	return " · ".join(parts)


func _recipe_done(recipe_id: String) -> bool:
	return _completed_recipes.has(recipe_id)


## 盘面上能当钥匙的武器（目录页的「有 / 需」看的是**盘面**，不是背包）。
##
## 必须走 `_tray_probe_items()` 而不是直接读 `TRAY_ENTRY_ITEM`：
## 堆叠数是单独存在 entry 里的，直接读会丢掉它 ——
## 表现是"盘面上明摆着 x2，目录却说 1 / 2"。
func _tray_weapons_for_catalog() -> Array:
	var out: Array = []
	for item in _tray_probe_items():
		if str((item as Dictionary).get("type", "")) == "weapon":
			out.append(item)
	return out


func _tray_materials_for_catalog() -> Array:
	var out: Array = []
	for item in _tray_probe_items():
		if str((item as Dictionary).get("type", "")) != "weapon":
			out.append(item)
	return out


## 页脚 = 读数行 + 操作行。读数在上、按钮压在最底，符合"信息与按钮都在底下"。
func _build_footer() -> Control:
	var footer := VBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 8)
	_footer_readout = _build_readout()
	footer.add_child(_footer_readout)
	_footer_actions = _build_actions()
	footer.add_child(_footer_actions)
	return footer


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.name = "Header"
	row.add_theme_constant_override("separation", 20)

	# 两级排印：大写宽字距弱标签 + 近白大字（规范 §4.1）。
	var title_column := VBoxContainer.new()
	title_column.name = "TitleColumn"
	title_column.add_theme_constant_override("separation", 2)
	var eyebrow := Label.new()
	eyebrow.name = "Eyebrow"
	eyebrow.text = "WEAPON FORGE　·　ALCHEMY"
	UIStyleFactory.apply_prism_label(eyebrow, "label", 5, 11)
	title_column.add_child(eyebrow)
	var title := Label.new()
	title.name = "Title"
	title.text = "武器改造台"
	UIStyleFactory.apply_prism_label(title, "value", 4, 24)
	title_column.add_child(title)
	row.add_child(title_column)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	# 金币是常驻资源，留在页头右上；"本次熔炼"的一切读数与按钮都在页脚。
	var coin_column := VBoxContainer.new()
	coin_column.name = "CoinColumn"
	coin_column.add_theme_constant_override("separation", 0)
	var coin_caption := Label.new()
	coin_caption.name = "CoinCaption"
	coin_caption.text = "COINS"
	coin_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UIStyleFactory.apply_prism_label(coin_caption, "label", 4, 10)
	coin_column.add_child(coin_caption)
	_coins_label = Label.new()
	_coins_label.name = "CoinsLabel"
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coins_label.text = "0"
	UIStyleFactory.apply_prism_label(_coins_label, "value", 2, 22)
	coin_column.add_child(_coins_label)
	row.add_child(coin_column)
	return row


func _build_body() -> Control:
	# 用**手动定位**而不是 HBox：业主口径是「中间炼炉、右边包裹」。
	# HBox 只能让"炼炉+背包"这一组整体居中 —— 那炼炉必然偏左（背包占了右半）。
	# 这里让炼炉锚在水平中心、背包锚在右边缘，两块各自贴住该待的位置。
	#
	# 不用 anchors 而用 resized 回调：窄屏下两者会重叠，只有拿到实时宽度
	# 才能把炼炉往左夹回来（`TRAY_BAG_GAP` 就是那道夹紧余量）。
	var body := Control.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_body_tray_column = _build_tray_column()
	body.add_child(_body_tray_column)
	_body_bag_column = _build_bag_column()
	body.add_child(_body_bag_column)

	# 闸门压在炼炉那一栏的正上方。加在最后 ⇒ 画在背包之上；
	# 但它的矩形只等于炼炉栏，所以视觉上盖不到背包（业主口径：闸门只在中间范围里）。
	_gate_veil = SynthesisGateVeil.new()
	_gate_veil.name = "SynthesisGateVeil"
	# 棋盘把每件物品的画布提到 z_index=4；闸门留在 0 会被枪械图标穿透。
	_gate_veil.z_index = 32
	_gate_veil.finished.connect(_on_gate_finished)
	body.add_child(_gate_veil)

	# 背包封条：闸门开着的那几秒，产物**已经真的进包了**（事务先行），
	# 不封住就等于在闸门旁边挂一块"答案是它"的牌子，3 秒等待变成空转。
	# 它不是闸门的一部分（不挡中间），只跟随闸门的时长出现与消失。
	_bag_seal = _build_bag_seal()
	body.add_child(_bag_seal)

	body.resized.connect(_layout_body)
	_layout_body()
	return body


## 背包封条：半透明深底 + 一行「仓门封闭中」。
##
## 只挡视觉、不锁交互 —— 玩家在闸门期间点背包格不会出问题（盘面已清空），
## 只是这段时间不该让他先看见答案。
func _build_bag_seal() -> Control:
	var seal := Control.new()
	seal.name = "BagSeal"
	seal.visible = false
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.z_index = 32

	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 不透明：0.94 时截图里还能看出底下有几件东西、什么轮廓 —— 那等于没封。
	scrim.color = UIPalette.PRISM_INK
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.add_child(center)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	center.add_child(column)

	var caption := Label.new()
	caption.name = "BagSealCaption"
	caption.text = "INVENTORY SEALED"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyleFactory.apply_prism_label(caption, "label", 4, 11)
	column.add_child(caption)

	var note := Label.new()
	note.text = "仓门封闭中" 
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyleFactory.apply_prism_label(note, "faint", 1, 12)
	column.add_child(note)
	return seal


## 把炼炉放到水平中心、背包贴右边缘；空间不够时炼炉左移，保证两者不重叠。
func _layout_body() -> void:
	if _body_tray_column == null or _body_bag_column == null:
		return
	var body_size := (_body_tray_column.get_parent() as Control).size
	if body_size.x <= 0.0 or body_size.y <= 0.0:
		return
	var tray_min := _body_tray_column.get_combined_minimum_size()
	var bag_min := _body_bag_column.get_combined_minimum_size()
	var bag_width := maxf(bag_min.x, 1.0)

	# 背包：右边缘对齐，纵向吃满主体高度。
	var bag_x := maxf(0.0, body_size.x - bag_width)
	_body_bag_column.position = Vector2(bag_x, 0.0)
	_body_bag_column.size = Vector2(bag_width, body_size.y)

	# 炼炉：水平居中；若撞到背包，就退到「背包左边 - 空隙」。
	var tray_width := tray_min.x
	var tray_x := (body_size.x - tray_width) * 0.5
	var limit := bag_x - TRAY_BAG_GAP - tray_width
	if tray_x > limit:
		tray_x = limit
	tray_x = maxf(0.0, tray_x)
	var tray_height := minf(tray_min.y, body_size.y)
	_body_tray_column.position = Vector2(tray_x, (body_size.y - tray_height) * 0.5)
	_body_tray_column.size = Vector2(tray_width, tray_height)

	# 闸门与炼炉栏逐像素对齐 —— "遮住中间的界面"就是这条矩形，
	# 宽高随手算，不在闸门里写死尺寸（换分辨率不会露边）。
	if _gate_veil != null:
		_gate_veil.position = _body_tray_column.position
		_gate_veil.size = _body_tray_column.size
	# 封条贴住背包栏，且**不越过背包左边界**，免得把闸门那栏也压暗。
	if _bag_seal != null:
		_bag_seal.position = _body_bag_column.position
		_bag_seal.size = _body_bag_column.size


## 中栏：炼炉。5×5 正方形盘面，是整个面板的主体。
func _build_tray_column() -> Control:
	var column := VBoxContainer.new()
	column.name = "TrayColumn"
	# 竖直居中：盘面比可用高度矮一点时，宁可上下都留白，也不要顶着页头。
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", 8)

	var caption := Label.new()
	caption.name = "TrayCaption"
	caption.text = "ALCHEMY GRID　%d × %d" % [TRAY_COLUMNS, TRAY_ROWS]
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyleFactory.apply_prism_label(caption, "label", 4, 11)
	column.add_child(caption)

	_tray_board = GridInventoryBoard.new()
	_tray_board.name = "TrayBoard"
	_tray_board.slot_kind = TRAY_KIND
	_tray_board.prism_mode = true
	_tray_board.configure(TRAY_CAPACITY, TRAY_COLUMNS, TRAY_CELL_SIZE)
	_tray_board.drop_validator = Callable(self, "_validate_tray_drop")

	# 括号框必须挂在**外层容器**上：棋盘重建会清空自己的全部子节点。
	var tray_frame := Control.new()
	tray_frame.name = "TrayFrame"
	tray_frame.custom_minimum_size = _tray_board.custom_minimum_size + Vector2(16, 16)
	tray_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_tray_board.position = Vector2(8, 8)
	tray_frame.add_child(_tray_board)
	UIStyleFactory.attach_prism_bracket_frame(tray_frame, "ghost", 18.0, 2.0)
	column.add_child(tray_frame)
	_connect_board(_tray_board)

	var note := Label.new()
	note.name = "TrayNote"
	note.text = "拖回右侧＝取回　·　盘内拖动＝调整位置　·　放进去的东西会被销毁"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyleFactory.apply_prism_label(note, "faint", 1, 11)
	column.add_child(note)
	return column


## 右栏：玩家背包。与 I 键同源 `InventoryModule`。
func _build_bag_column() -> Control:
	var column := VBoxContainer.new()
	column.name = "BagColumn"
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	_bag_title = Label.new()
	_bag_title.name = "BagTitle"
	_bag_title.text = "INVENTORY"
	UIStyleFactory.apply_prism_label(_bag_title, "label", 4, 11)
	column.add_child(_bag_title)

	var scroll := ScrollContainer.new()
	scroll.name = "BagScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	UIStyleFactory.apply_prism_scrollbar(scroll)
	column.add_child(scroll)

	_bag_board = GridInventoryBoard.new()
	_bag_board.name = "BagBoard"
	_bag_board.slot_kind = BAG_KIND
	_bag_board.prism_mode = true
	_bag_board.configure(
		_inventory.get_capacity() if _inventory != null else InventoryModule.DEFAULT_CAPACITY,
		BAG_COLUMNS,
		BAG_CELL_SIZE
	)
	_bag_board.drop_validator = Callable(self, "_validate_bag_drop")
	scroll.add_child(_bag_board)
	_connect_board(_bag_board)
	return column


func _build_readout() -> Control:
	var grid := GridContainer.new()
	grid.name = "Readout"
	# 一行 7 栏。视口基准 1280×720，两行读数会把操作钮挤出可视区。
	grid.columns = 7
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 6)
	grid.add_theme_constant_override("h_separation", 28)
	_stat_payload = _add_stat(grid, "PAYLOAD")
	_stat_melt = _add_stat(grid, "MELT")
	# 稀有度分必须单列：它是"材料的稀有度提升品质"这条规则的唯一可见抓手，
	# 塞进 GRADE ODDS 里玩家看不出是它把概率顶上去了。
	_stat_rarity = _add_stat(grid, "RARITY")
	_stat_recipe = _add_stat(grid, "RECIPE")
	_stat_blueprint = _add_stat(grid, "BLUEPRINT")
	_stat_grades = _add_stat(grid, "GRADE ODDS")
	_stat_cost = _add_stat(grid, "FEE")
	return grid


## 一个读数块 = 弱标签 + 强数值。中间态（中灰中等字号）按规范视为违规。
func _add_stat(grid: GridContainer, caption: String) -> Label:
	var block := VBoxContainer.new()
	block.name = "Stat_%s" % caption.replace(" ", "_")
	# 七栏等分页脚宽度：读数区要像一整条数据带，不能左边挤成一团、右边空一片。
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_constant_override("separation", 2)
	var cap := Label.new()
	cap.text = caption
	UIStyleFactory.apply_prism_label(cap, "label", 4, 10)
	block.add_child(cap)
	var value := Label.new()
	value.text = "—"
	UIStyleFactory.apply_prism_label(value, "value", 2, 17)
	block.add_child(value)
	grid.add_child(block)
	return value


## 操作行：状态栏在左，关闭与熔炼压在最右下。这是整个面板的最后一层。
func _build_actions() -> Control:
	var row := HBoxContainer.new()
	row.name = "Actions"
	row.add_theme_constant_override("separation", 16)

	_status = Label.new()
	_status.name = "Status"
	_status.text = HINT_TEXT
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 给一个最小高度：运行时消息换行时按钮不能被顶得上下跳。
	_status.custom_minimum_size = Vector2(0, 46)
	UIStyleFactory.apply_prism_label(_status, "faint", 1, 12)
	row.add_child(_status)

	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "ESC　关闭"
	close_button.custom_minimum_size = Vector2(124, 46)
	close_button.pressed.connect(_close)
	UIStyleFactory.apply_prism_button(close_button, "ghost", 2, 13, 3)
	row.add_child(close_button)

	_forge_button = Button.new()
	_forge_button.name = "ForgeButton"
	_forge_button.text = "熔　炼"
	_forge_button.custom_minimum_size = Vector2(220, 46)
	_forge_button.pressed.connect(_on_forge_pressed)
	UIStyleFactory.apply_prism_button(_forge_button, "primary", 2, 17, 5)
	row.add_child(_forge_button)
	return row


func _build_confirm_layer() -> Control:
	# 根是全屏 Control：只有先铺满，内部居中容器才有可参照的矩形，
	# 括号框才能贴着真实面板画（直接给 PanelContainer 设 PRESET_CENTER 会画歪）。
	var layer := Control.new()
	layer.name = "ConfirmLayer"
	layer.visible = false
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	# 棋盘把每件物品的画布提到 z_index=4；确认层若留在 0，枪械图标会盖在弹窗上。
	layer.z_index = 64

	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 比主遮罩更重：这一步要让玩家"看不见背包"，否则会误以为还能继续拖东西。
	scrim.color = Color(
		UIPalette.PRISM_DIM.r, UIPalette.PRISM_DIM.g, UIPalette.PRISM_DIM.b, 0.90
	)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(scrim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)

	var card := PanelContainer.new()
	card.name = "ConfirmCard"
	card.custom_minimum_size = Vector2(600, 0)
	# 确认层必须"读得清"。棱镜的 0.42 底衬在这层会被下面的盘面和背包穿透，
	# 文字直接压在枪械图标上 —— 收紧到接近不透明的深墨。
	var card_style := UIStyleFactory.make_prism_panel(true, 0.96)
	card_style.bg_color = Color(
		UIPalette.PRISM_INK.r, UIPalette.PRISM_INK.g, UIPalette.PRISM_INK.b, 0.96
	)
	card_style.border_color = UIPalette.PRISM_LINE
	card_style.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 34)
	pad.add_theme_constant_override("margin_top", 26)
	pad.add_theme_constant_override("margin_right", 34)
	pad.add_theme_constant_override("margin_bottom", 26)
	card.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	pad.add_child(column)
	var warn := Label.new()
	warn.name = "ConfirmWarn"
	warn.text = "IRREVERSIBLE"
	UIStyleFactory.apply_prism_label(warn, "danger", 5, 11)
	column.add_child(warn)
	_confirm_text = Label.new()
	_confirm_text.name = "ConfirmText"
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyleFactory.apply_prism_label(_confirm_text, "value", 1, 15)
	column.add_child(_confirm_text)
	column.add_child(UIStyleFactory.make_prism_rule(UIPalette.PRISM_LINE_FAINT, 1.0))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 16)
	var cancel := Button.new()
	cancel.name = "CancelButton"
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(130, 46)
	cancel.pressed.connect(_cancel_confirm)
	UIStyleFactory.apply_prism_button(cancel, "ghost", 2, 16, 3)
	buttons.add_child(cancel)
	var ok := Button.new()
	ok.name = "ConfirmButton"
	ok.text = "确认熔炼"
	ok.custom_minimum_size = Vector2(180, 46)
	ok.pressed.connect(_confirm_plan)
	UIStyleFactory.apply_prism_button(ok, "primary", 2, 16, 3)
	buttons.add_child(ok)
	column.add_child(buttons)
	_confirm_layer = layer
	return layer


func _connect_board(board: GridInventoryBoard) -> void:
	for cell in board.cells:
		if cell.has_signal("slot_drop_received") and not cell.slot_drop_received.is_connected(_on_board_drop):
			cell.slot_drop_received.connect(_on_board_drop)


## ————————————————————————————————
## 刷新
## ————————————————————————————————

func _refresh_all() -> void:
	_refresh_tray()
	_refresh_bag()
	_refresh_readout()


func _on_inventory_changed() -> void:
	_refresh_bag()
	_refresh_readout()


func _refresh_tray() -> void:
	if _tray_board == null:
		return
	var entries: Array = []
	for entry in _tray:
		entries.append({
			"slot": int(entry[TRAY_ENTRY_ANCHOR]),
			"item": entry[TRAY_ENTRY_ITEM],
			"count": int(entry[TRAY_ENTRY_COUNT]),
			"grid_rotation": int(entry[TRAY_ENTRY_ROTATION]),
		})
	_apply_payloads(_tray_board, entries, TRAY_KIND)
	_tray_board.render_items(entries)


func _refresh_bag() -> void:
	if _bag_board == null or _inventory == null:
		return
	if _bag_board.capacity != _inventory.get_capacity():
		_bag_board.configure(_inventory.get_capacity(), BAG_COLUMNS, BAG_CELL_SIZE)
		_connect_board(_bag_board)
	var entries: Array = _inventory.get_occupied_slots()
	_apply_payloads(_bag_board, entries, BAG_KIND)
	_bag_board.render_items(entries)
	if _bag_title != null:
		_bag_title.text = "背包（%d / %d 格）" % [
			_inventory.get_used_slots(), _inventory.get_capacity(),
		]


## 把每个有物品的锚点格写成拖拽源；空格显式清掉 payload，避免拖动旧物品。
func _apply_payloads(board: GridInventoryBoard, entries: Array, kind: String) -> void:
	for cell in board.cells:
		cell.set_meta("slot_kind", kind)
		if cell.has_meta("drag_payload"):
			cell.remove_meta("drag_payload")
	for entry_variant in entries:
		if not entry_variant is Dictionary:
			continue
		var entry := entry_variant as Dictionary
		var anchor := int(entry.get("slot", -1))
		if anchor < 0 or anchor >= board.cells.size():
			continue
		board.cells[anchor].set_meta("drag_payload", {
			"item": (entry.get("item", {}) as Dictionary).duplicate(true),
			"count": int(entry.get("count", 1)),
		})


func _refresh_readout() -> void:
	if _stat_cost == null:
		return
	if _coins_label != null:
		_coins_label.text = str(_coins())
	var plan := WeaponForge.classify(_tray_probe_items())
	var recipe := str(plan["recipe"])
	# 钥匙已齐、燃料不够：这**不是**"盘面空"，必须显示产物名与还差多少。
	# 否则玩家会以为没投对东西，反复调整配方 —— 而实际上只差几点熔炼值。
	var short_spec: Dictionary = plan.get("synthesis", {}) as Dictionary
	if (
		str(plan["reason"]) == WeaponForge.REJECT_SYNTHESIS_FUEL_SHORT
		and not short_spec.is_empty()
	):
		_refresh_readout_fuel_short(plan, short_spec)
		return
	if recipe == WeaponForge.RECIPE_NONE:
		_refresh_status_hint(plan)
		_stat_payload.text = "—"
		_stat_melt.text = "—"
		_stat_rarity.text = "—"
		_stat_recipe.text = "—"
		_stat_blueprint.text = "—"
		_stat_grades.text = "—"
		_stat_cost.text = "—"
		_stat_cost.remove_theme_color_override("font_color")
		UIStyleFactory.apply_prism_label(_stat_cost, "value", 2, 17)
		_forge_button.disabled = true
		return
	var weapons := (plan["weapons"] as Array).size()
	# 材料按**个数**显示而不是条目数：投 1 组 ×3 药水，玩家要看的是 3 件材料。
	var materials := 0
	for value in plan["materials"] as Array:
		materials += maxi(1, int((value as Dictionary).get("count", 1)))
	var melt := int(plan["melt"])
	var rarity_points := int(plan["rarity_points"])
	var spec: Dictionary = plan.get("synthesis", {}) as Dictionary
	var quality_bonus := int(spec.get("quality_bonus", 0))
	var points := rarity_points + quality_bonus
	var probabilities := WeaponForge.grade_probabilities(weapons, points)
	_stat_payload.text = "%d 枪 · %d 材料" % [weapons, materials]
	_stat_melt.text = str(melt)
	# 有配方加成时写成「材料分 + 配方分」：只显示总和会让玩家以为
	# 是自己投的材料把概率顶上去了，看不出配方本体的贡献。
	_stat_rarity.text = (
		"%d + %d" % [rarity_points, quality_bonus] if quality_bonus > 0
		else str(rarity_points)
	)
	_stat_recipe.text = _recipe_text(recipe)
	# 蓝本一栏必须说清"随机"，否则玩家会以为出来的一定是某一把。
	if recipe == WeaponForge.RECIPE_DIRECTED:
		_stat_blueprint.text = str(spec.get("product_name", "—"))
	elif weapons >= 2:
		_stat_blueprint.text = "随机（%d 把之一）" % weapons
	elif weapons == 1:
		_stat_blueprint.text = "投入武器"
	else:
		_stat_blueprint.text = "随机枪身"
	_stat_grades.text = "蓝 %.0f%% · 紫 %.0f%% · 金 %.0f%%" % [
		float(probabilities.get(WeaponDropGrade.GRADE_BLUE, 0.0)) * 100.0,
		float(probabilities.get(WeaponDropGrade.GRADE_PURPLE, 0.0)) * 100.0,
		float(probabilities.get(WeaponDropGrade.GRADE_GOLD, 0.0)) * 100.0,
	]
	var cost := int(plan.get("coin_cost", 0))
	_stat_cost.text = str(cost)
	var affordable := cost <= _coins()
	UIStyleFactory.apply_prism_label(_stat_cost, "value" if affordable else "danger", 2, 17)
	_forge_button.disabled = _busy or not affordable
	_refresh_status_hint(plan)


## 「钥匙差一点」的软提示。
##
## 只在不打扰的前提下写状态栏：玩家正在熔炼结果里看产出时，不能被一条提示顶掉。
## 这条提示的作用是解释"为什么没合成出指定的枪"，而不是阻止熔炼。
func _refresh_status_hint(plan: Dictionary) -> void:
	var hint: Dictionary = plan.get("synthesis_hint", {}) as Dictionary
	if hint.is_empty():
		return
	if _status == null or _status.text != HINT_TEXT:
		# 状态栏已被别的内容占用（熔炼结果 / 拒绝原因），让位给那条更重要的信息。
		return
	var key_definition := ItemRegistry.get_instance().get_item(str(hint["key_item_id"]))
	_set_status("「%s」还差 %d 个（%d/%d）· 本次将按随机合成处理" % [
		str(key_definition.get("name", hint["key_item_id"])),
		int(hint["key_count"]) - int(hint["key_have"]),
		int(hint["key_have"]),
		int(hint["key_count"]),
	])


## 「钥匙齐、燃料不够」的读数：显示产物名与缺口，费用栏转危险色、按钮禁用。
func _refresh_readout_fuel_short(plan: Dictionary, spec: Dictionary) -> void:
	var weapons := (plan["weapons"] as Array).size()
	var materials := 0
	for value in plan["materials"] as Array:
		materials += maxi(1, int((value as Dictionary).get("count", 1)))
	var rarity_points := int(plan["rarity_points"])
	var quality_bonus := int(spec.get("quality_bonus", 0))
	var probabilities := WeaponForge.grade_probabilities(
		weapons, rarity_points + quality_bonus
	)
	_stat_payload.text = "%d 枪 · %d 材料" % [weapons, materials]
	_stat_melt.text = "%d / %d" % [int(plan["melt"]), int(spec["fuel_min"])]
	_stat_rarity.text = (
		"%d + %d" % [rarity_points, quality_bonus] if quality_bonus > 0
		else str(rarity_points)
	)
	_stat_recipe.text = "定向合成（缺燃料）"
	_stat_blueprint.text = str(spec.get("product_name", "—"))
	_stat_grades.text = "蓝 %.0f%% · 紫 %.0f%% · 金 %.0f%%" % [
		float(probabilities.get(WeaponDropGrade.GRADE_BLUE, 0.0)) * 100.0,
		float(probabilities.get(WeaponDropGrade.GRADE_PURPLE, 0.0)) * 100.0,
		float(probabilities.get(WeaponDropGrade.GRADE_GOLD, 0.0)) * 100.0,
	]
	_stat_cost.text = str(int(spec.get("coin_cost", 0)))
	UIStyleFactory.apply_prism_label(_stat_cost, "danger", 2, 17)
	_forge_button.disabled = true
	_set_status("还差 %d 点熔炼值才能合成%s" % [
		int(spec.get("fuel_short", 0)), str(spec.get("product_name", "该武器")),
	])


func _recipe_text(recipe: String) -> String:
	match recipe:
		WeaponForge.RECIPE_DIRECTED:
			return "定向合成"
		WeaponForge.RECIPE_REMELT:
			return "重铸"
		WeaponForge.RECIPE_FUSION:
			return "融合"
		WeaponForge.RECIPE_SYNTHESIS:
			return "合成"
	return "—"


func _reason_text(reason: String) -> String:
	match reason:
		WeaponForge.REJECT_SINGLE_WEAPON_WITHOUT_FUEL:
			return "单把武器需要配材料当燃料"
		WeaponForge.REJECT_INSUFFICIENT_FUEL:
			return "燃料熔炼值不足 %d 点（3 件白装，或 1 件稀有材料）" % WeaponForge.FUEL_THRESHOLD
		WeaponForge.REJECT_INSUFFICIENT_MELT:
			return "材料熔炼值不足 6 点，凑不够合成门槛"
		WeaponForge.REJECT_SYNTHESIS_FUEL_SHORT:
			return "钥匙已齐，但燃料熔炼值还不够"
		WeaponForge.REJECT_BACKPACK_FULL:
			return "背包空间不足"
		WeaponForge.REJECT_INSUFFICIENT_CURRENCY:
			return "金币不足"
	return "拖入武器或任意材料开始"


## ————————————————————————————————
## 拖拽
## ————————————————————————————————

func _validate_tray_drop(data: Dictionary, anchor: int) -> bool:
	var item := data.get("item", {}) as Dictionary
	if not WeaponForge.accepts(item):
		return false
	var source_kind := str(data.get("source_kind", ""))
	var rotation := int(item.get("grid_rotation", 0))
	var ignore_anchor := -1
	if source_kind == TRAY_KIND:
		ignore_anchor = int(data.get("source_index", -1))
	elif source_kind != BAG_KIND:
		return false
	return _tray_can_place(item, anchor, rotation, ignore_anchor)


func _validate_bag_drop(data: Dictionary, _anchor: int) -> bool:
	return str(data.get("source_kind", "")) == TRAY_KIND


func _on_board_drop(
	source_index: int, target_index: int, source_kind: String, target_kind: String
) -> void:
	if _busy:
		return
	if target_kind == TRAY_KIND:
		_drop_into_tray(source_index, target_index, source_kind)
	elif target_kind == BAG_KIND and source_kind == TRAY_KIND:
		_drop_back_to_bag(source_index)


func _drop_into_tray(source_index: int, target_anchor: int, source_kind: String) -> void:
	if _inventory == null:
		return
	var item: Dictionary = {}
	var count := 1
	var rotation := 0
	var from_anchor := -1
	if source_kind == BAG_KIND:
		var slot := _inventory.get_slot(source_index)
		if slot.is_empty():
			return
		item = slot.get("item", {}) as Dictionary
		count = int(slot.get("count", 1))
	elif source_kind == TRAY_KIND:
		var entry := _tray_entry_at(source_index)
		if entry.is_empty():
			return
		item = entry[TRAY_ENTRY_ITEM] as Dictionary
		count = int(entry[TRAY_ENTRY_COUNT])
		rotation = int(entry[TRAY_ENTRY_ROTATION])
		from_anchor = source_index
	else:
		return
	if not _tray_can_place(item, target_anchor, rotation, from_anchor):
		var size := ItemRegistry.grid_size_of(item)
		_set_status("这个位置放不下：需要 %d×%d 格" % [size.x, size.y])
		return
	if from_anchor >= 0:
		_tray_entry_at(from_anchor)[TRAY_ENTRY_ANCHOR] = target_anchor
	else:
		if not _tray_append(item, count, target_anchor, rotation):
			return
		# 先入盘、成功后才从背包扣除：中途失败不会吞物品。
		if not _inventory.remove_from_slot(source_index, count):
			_tray_remove_anchor(target_anchor)
			_set_status("无法从背包取出该物品")
			return
	_refresh_all()


func _drop_back_to_bag(source_anchor: int) -> void:
	if _inventory == null:
		return
	var entry := _tray_entry_at(source_anchor)
	if entry.is_empty():
		return
	var item := entry[TRAY_ENTRY_ITEM] as Dictionary
	var count := int(entry[TRAY_ENTRY_COUNT])
	var added := _inventory.add_item(item, count)
	if added <= 0:
		_set_status("背包放不下，物品仍在盘内")
		return
	if added < count:
		entry[TRAY_ENTRY_COUNT] = count - added
		_set_status("背包只放得下一部分（%d / %d），其余仍在盘内" % [added, count])
	else:
		_tray.erase(entry)
	_refresh_all()


## ————————————————————————————————
## 盘面存储（6×6，按 grid_size 占格）
## ————————————————————————————————

func _tray_cells(anchor: int, item: Dictionary, rotation: int) -> Array[int]:
	var cells: Array[int] = []
	if anchor < 0 or anchor >= TRAY_CAPACITY:
		return cells
	var size := ItemRegistry.grid_size_of(item)
	if rotation % 2 == 1:
		size = Vector2i(size.y, size.x)
	var origin := Vector2i(anchor % TRAY_COLUMNS, anchor / TRAY_COLUMNS)
	if origin.x + size.x > TRAY_COLUMNS or origin.y + size.y > TRAY_ROWS:
		return cells
	for y in range(size.y):
		for x in range(size.x):
			cells.append((origin.y + y) * TRAY_COLUMNS + (origin.x + x))
	return cells


func _tray_can_place(item: Dictionary, anchor: int, rotation: int, ignore_anchor := -1) -> bool:
	var cells := _tray_cells(anchor, item, rotation)
	if cells.is_empty():
		return false
	for entry in _tray:
		if int(entry[TRAY_ENTRY_ANCHOR]) == ignore_anchor:
			continue
		var other_cells := _tray_cells(
			int(entry[TRAY_ENTRY_ANCHOR]),
			entry[TRAY_ENTRY_ITEM] as Dictionary,
			int(entry[TRAY_ENTRY_ROTATION])
		)
		for cell in cells:
			if cell in other_cells:
				return false
	return true


func _tray_append(item: Dictionary, count: int, anchor: int, rotation: int) -> bool:
	if not _tray_can_place(item, anchor, rotation):
		return false
	_tray.append({
		TRAY_ENTRY_ANCHOR: anchor,
		TRAY_ENTRY_ITEM: item.duplicate(true),
		TRAY_ENTRY_COUNT: count,
		TRAY_ENTRY_ROTATION: rotation,
	})
	return true


func _tray_entry_at(anchor: int) -> Dictionary:
	for entry in _tray:
		if int(entry[TRAY_ENTRY_ANCHOR]) == anchor:
			return entry
	return {}


func _tray_remove_anchor(anchor: int) -> void:
	var entry := _tray_entry_at(anchor)
	if not entry.is_empty():
		_tray.erase(entry)


## 盘内物品的探针副本：`count` 写进字典，`WeaponForge.melt_value_of` 才能按堆叠算。
func _tray_probe_items() -> Array:
	var items: Array = []
	for entry in _tray:
		var probe := (entry[TRAY_ENTRY_ITEM] as Dictionary).duplicate(true)
		probe["count"] = int(entry[TRAY_ENTRY_COUNT])
		items.append(probe)
	return items


## ————————————————————————————————
## 熔炼事务
## ————————————————————————————————

func _on_forge_pressed() -> void:
	if _busy:
		return
	var plan := WeaponForge.classify(_tray_probe_items())
	if str(plan["recipe"]) == WeaponForge.RECIPE_NONE:
		_set_status(_reason_text(str(plan["reason"])))
		return
	# R0 定向合成也要二次确认：它消耗的是**打怪攒出来的凭据**，
	# 比武器更不该误触 —— 武器丢了还能再掉，碎片数着攒了好几局。
	if (
		str(plan["recipe"]) == WeaponForge.RECIPE_DIRECTED
		or not (plan["weapons"] as Array).is_empty()
	):
		_pending_plan = plan
		_confirm_text.text = _confirm_message(plan)
		_confirm_layer.visible = true
		return
	_execute_forge(plan)


## 二次确认的正文。定向合成与随机熔炼的措辞必须不同 ——
## 前者玩家**知道**会得到什么，后者不知道，混淆会让确认失去意义。
func _confirm_message(plan: Dictionary) -> String:
	var weapon_count := (plan["weapons"] as Array).size()
	var material_count := 0
	for value in plan["materials"] as Array:
		material_count += maxi(1, int((value as Dictionary).get("count", 1)))
	var coin := int(plan.get("coin_cost", 0))
	if str(plan["recipe"]) == WeaponForge.RECIPE_DIRECTED:
		var spec: Dictionary = plan.get("synthesis", {}) as Dictionary
		var bonus := int(spec.get("quality_bonus", 0))
		var bullet := str(spec.get("preload_bullet", ""))
		var bullet_text := "随机"
		if not bullet.is_empty():
			var bullet_definition := ItemRegistry.get_instance().get_item(bullet)
			bullet_text = "预装%s（可拆换）" % str(bullet_definition.get("name", bullet))
		return (
			"销毁 %d 把武器与 %d 件材料，支付 %d 金币，产出【%s】。\n品质仍掷骰（配方加成 +%d），弹种%s，命运卡不继承。"
			% [weapon_count, material_count, coin, str(spec.get("product_name", "?")), bonus, bullet_text]
		)
	return "销毁 %d 把武器与 %d 个弹药模块，支付 %d 金币，产出一把全新枪械。\n蓝本与弹种随机，命运卡不继承，弹药不锁定。" % [
		weapon_count,
		(plan["modules"] as Array).size(),
		coin,
	]


func _confirm_plan() -> void:
	_confirm_layer.visible = false
	if _pending_plan.is_empty():
		return
	var plan := _pending_plan
	_pending_plan = {}
	_execute_forge(plan)


func _cancel_confirm() -> void:
	_pending_plan = {}
	_confirm_layer.visible = false


func _execute_forge(plan: Dictionary) -> void:
	if not BaseManager.is_base_power_on():
		_set_status("基地断电，请启动100层天台发电机")
		return
	if _inventory == null:
		_set_status("背包不可用，无法熔炼")
		return
	_busy = true
	_set_status("正在熔炼……")
	var recipe := str(plan["recipe"])
	var tier := _blueprint_tier()
	var outputs := _build_outputs(plan, recipe, tier)
	if outputs.is_empty():
		_busy = false
		_set_status("没有可用的枪身蓝图，熔炼未执行")
		return
	# 产出数量不足预演值 ⇒ 直接拒绝，不销毁任何投入。
	# 否则「合成 3 把但只构建出 2 把」会让玩家白搭进去一批模块，而且看不出为什么。
	var expected := int(plan["output_count"])
	if outputs.size() != expected:
		_busy = false
		_set_status("产出构建异常（预期 %d 把，实际 %d 把），熔炼未执行" % [expected, outputs.size()])
		return
	# 金币先校验再扣：`spend_currency` 是原子布尔返回，但把它排在写背包之前，
	# 后面的失败路径只需退钱，不必处理"钱扣了枪没进包"的中间态。
	var cost := int(plan.get("coin_cost", 0))
	if cost > 0 and not _spend_coins(cost):
		_busy = false
		_refresh_readout()
		_set_status("金币不足：需要 %d，持有 %d。投入物一件未动" % [cost, _coins()])
		return

	# 事务：先快照，再销毁投入、写产出；任一失败全量回滚（含金币）。
	var inventory_snapshot: Array = _inventory.get_slots_snapshot()
	var tray_snapshot := _clone_tray(_tray)
	_tray.clear()
	var written := 0
	for output in outputs:
		if _inventory.add_item(output, 1) <= 0:
			_inventory.restore_slots_snapshot(inventory_snapshot)
			_tray = tray_snapshot
			if cost > 0:
				_refund_coins(cost)
			_busy = false
			_refresh_all()
			_set_status("背包空间不足，熔炼已回滚：投入物与 %d 金币均已退回" % cost)
			return
		written += 1

	_busy = false
	# 记录已完成的定向配方（图鉴进度）。写在成功分支里：失败的熔炼不该打勾。
	for output in outputs:
		var done_recipe := str((output as Dictionary).get("created_recipe_id", ""))
		if not done_recipe.is_empty():
			_completed_recipes[done_recipe] = true
	var lines: Array[String] = []
	for output in outputs:
		lines.append("%s｜%s｜%s" % [
			WeaponDropGrade.display_name(str(output.get("drop_grade", ""))),
			str(output.get("name", "武器")),
			_bullet_display(output),
		])
	var report := {
		"success": true,
		"recipe": recipe,
		"count": written,
		"coin_cost": cost,
		"outputs": outputs,
		"message": "熔炼完成：%s（消耗 %d 金币）" % ["，".join(lines), cost],
	}
	_play_synthesis_gate(report)


## 闸门表现。**事务在这里已经全部落地**（钱扣了、产物进包了、盘面清了），
## 这一段只负责"让玩家看见材料被关起来、然后换成产物"。
##
## ## 为什么界面刷新要等到闸门播完
##
## 第一版在关闸前就 `_refresh_all()` 并写了结果文案，截图里一眼看穿：
## **闸门还关着，页脚已经写着"熔炼完成：蓝｜豌豆手枪"，背包里那把枪也摆在那儿了。**
## 那等于把揭晓提前剧透，3 秒的等待变成一个空转的过场。
##
## 所以这里刻意**不刷新**：盘面继续显示刚被吃掉的材料、背包不动、文案停在
## 「内容置换中」，全部在 `_finish_forge` 里一次性换掉 —— 闸门升起那一刻
## 玩家看到的才是"里头的东西被替换了"。
##
## `_busy` 全程保持 true：闸门盖着盘面时再点熔炼只会读到空盘面。
func _play_synthesis_gate(report: Dictionary) -> void:
	var outputs := report.get("outputs", []) as Array
	if _gate_veil == null or outputs.is_empty():
		_finish_forge(report)
		return
	_pending_forge_report = report
	_busy = true
	_set_status("内容置换中 · 闸门开启后揭晓")
	if _bag_seal != null:
		_bag_seal.visible = true
	_gate_veil.play(outputs)


func _on_gate_finished() -> void:
	_busy = false
	if _bag_seal != null:
		_bag_seal.visible = false
	var report := _pending_forge_report
	_pending_forge_report = {}
	if not report.is_empty():
		_finish_forge(report)


## 真正的收尾：刷新盘面/背包/读数、写结果文案、发信号。
##
## 只在**揭晓之后**调用。闸门被中途收掉（切页 / 关闭面板）时也必须走一次，
## 否则界面会永远停在"盘上还摆着那批材料"的旧画面上 —— 那些材料其实早就销毁了。
func _finish_forge(report: Dictionary) -> void:
	_refresh_all()
	if _active_page == PAGE_CATALOG:
		_refresh_catalog()
		_apply_page_footer()
	_set_status(str(report.get("message", "")))
	forge_completed.emit(report)


## 闸门被中途收掉时的兜底：把还欠着的那次收尾补上。
func _flush_pending_forge_report() -> void:
	if _bag_seal != null:
		_bag_seal.visible = false
	if _pending_forge_report.is_empty():
		return
	var report := _pending_forge_report
	_pending_forge_report = {}
	_busy = false
	_finish_forge(report)


func _build_outputs(plan: Dictionary, recipe: String, tier: int) -> Array:
	var outputs: Array = []
	# R0 定向合成：枪身由配方**指定**，不再是掷骰结果。
	# 品质仍然掷（`quality_bonus` 把概率抬高，但不给必出），弹种与配件按配方预装。
	if recipe == WeaponForge.RECIPE_DIRECTED:
		var spec: Dictionary = plan.get("synthesis", {}) as Dictionary
		if spec.is_empty():
			return outputs
		var directed_assembly := str(spec.get("assembly_id", ""))
		if directed_assembly.is_empty():
			return outputs
		var product := ItemRegistry.get_instance().get_item(str(spec.get("product_id", "")))
		var directed_melee := WeaponForge.is_melee(product)
		var directed_bullet := ""
		if not directed_melee:
			var preload_id := str(spec.get("preload_bullet", ""))
			# 有预装就用预装（**不锁**：`build_output` 统一写 locked=false），
			# 没有才掷骰。定向的价值是"默认给一个合理的弹道"，不是"只能这样"。
			if preload_id.is_empty():
				directed_bullet = WeaponForge.roll_bullet(plan["modules"], _rng)
			else:
				directed_bullet = preload_id
		var directed_attachments: Array[String] = []
		var want_attachments := int(spec.get("preload_attachments", 0))
		if want_attachments > 0 and not directed_melee:
			directed_attachments = WeaponForge.roll_attachments(
				directed_assembly, tier, want_attachments, _rng
			)
		# 品质：n=0（没有蓝本武器参与加成）+ 稀有度分 + 配方自带的 quality_bonus。
		var directed_points := int(plan["rarity_points"]) + int(spec.get("quality_bonus", 0))
		var directed_output := WeaponForge.build_output({
			"assembly_id": directed_assembly,
			"grade": WeaponForge.roll_grade(_rng, 0, directed_points),
			"bullet_id": directed_bullet,
			"attachments": directed_attachments,
		})
		if not directed_output.is_empty():
			# 图鉴统计要靠它区分"我合成过这把"和"我捡到这把"。
			directed_output["created_recipe_id"] = str(spec.get("recipe_id", ""))
			outputs.append(directed_output)
		return outputs

	if recipe == WeaponForge.RECIPE_SYNTHESIS:
		var gunbodies := BlueprintRegistry.get_available_gunbodies(tier)
		if gunbodies.is_empty():
			return outputs
		var count := int(plan["output_count"])
		for _index in range(count):
			var entry := gunbodies[_rng.randi_range(0, gunbodies.size() - 1)] as Dictionary
			var output := WeaponForge.build_output({
				"assembly_id": str(entry.get("item_id", "")),
				"grade": WeaponForge.roll_grade_value(
					_rng.randf(), 0, int(plan["rarity_points"])
				),
				"bullet_id": WeaponForge.roll_bullet(plan["modules"], _rng),
				"attachments": [],
			})
			if not output.is_empty():
				outputs.append(output)
		return outputs

	var weapons := plan["weapons"] as Array
	var weapon_count := weapons.size()
	# R2：蓝本**随机**取一把（业主要求「两把随机」）。R1：只有一把，随机退化为取它。
	var blueprint := plan["blueprint"] as Dictionary
	if weapon_count >= 2:
		blueprint = WeaponForge.pick_blueprint(weapons, _rng).get("item", {}) as Dictionary
	var assembly_id := str(blueprint.get("assembly_id", ""))
	if assembly_id.is_empty():
		return outputs
	var melee := WeaponForge.is_melee(blueprint)
	# 弹种候选 = 投入模块（按数量计票）+ 投入武器自带弹种（各 1 票）。
	var bound := WeaponForge.collect_bound_bullets(weapons)
	var bullet_id := "" if melee else WeaponForge.roll_bullet(plan["modules"], _rng, bound)
	var attachments: Array[String] = []
	if weapon_count >= 2 and not melee:
		var wanted := int(WeaponForge.FUSION_ATTACHMENTS.get(mini(weapon_count, 3), 1))
		attachments = WeaponForge.roll_attachments(assembly_id, tier, wanted, _rng)
	var output := WeaponForge.build_output({
		"assembly_id": assembly_id,
		"grade": WeaponForge.roll_grade(_rng, weapon_count, int(plan["rarity_points"])),
		"bullet_id": bullet_id,
		"attachments": attachments,
	})
	if not output.is_empty():
		outputs.append(output)
	return outputs


## ————————————————————————————————
## 金币
## ————————————————————————————————

func _coins() -> int:
	if GameManager == null:
		return 0
	return int(GameManager.currency)


func _spend_coins(amount: int) -> bool:
	if amount <= 0:
		return true
	if GameManager == null:
		return false
	return GameManager.spend_currency(amount)


func _refund_coins(amount: int) -> void:
	if amount <= 0 or GameManager == null:
		return
	GameManager.add_currency(amount)


func _blueprint_tier() -> int:
	if BaseManager != null:
		return maxi(0, int(BaseManager.get_blueprint_tier("gunbody")))
	return 0


func _bullet_display(output: Dictionary) -> String:
	var bullet_id := str(output.get("bullet_module_id", ""))
	if bullet_id.is_empty():
		return "近战"
	var definition := ItemRegistry.get_instance().get_item(bullet_id)
	return str(definition.get("name", bullet_id))


func _clone_tray(source: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in source:
		out.append((entry as Dictionary).duplicate(true))
	return out


## ————————————————————————————————
## 关闭
## ————————————————————————————————

func _close() -> void:
	# 闸门播放中允许直接关：事务已经落盘、盘面已清空，
	# 拦着不让关只会让玩家对着一个按 ESC 没反应的界面等 3 秒。
	if _gate_veil != null and _gate_veil.is_playing():
		_gate_veil.abort()
		_busy = false
		_flush_pending_forge_report()
	if _busy:
		return
	if not _return_tray_to_inventory():
		_set_status("背包放不下盘内物品，先腾出格子再关闭")
		return
	closed.emit()
	queue_free()


## 盘内残留必须原样退回背包。放不下就整笔回滚并拒绝关闭 ——
## 关面板顺手销毁玩家的枪是这类界面最容易犯、也最不可挽回的错。
func _return_tray_to_inventory() -> bool:
	if _tray.is_empty():
		return true
	if _inventory == null:
		return false
	var snapshot: Array = _inventory.get_slots_snapshot()
	for entry in _tray:
		var added := _inventory.add_item(
			entry[TRAY_ENTRY_ITEM] as Dictionary, int(entry[TRAY_ENTRY_COUNT])
		)
		if added < int(entry[TRAY_ENTRY_COUNT]):
			_inventory.restore_slots_snapshot(snapshot)
			return false
	_tray.clear()
	return true


func _set_status(message: String) -> void:
	if _status != null:
		_status.text = message
