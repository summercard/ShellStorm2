extends Node
## 「子弹模块 = 可装备挂件」专项验收。
##
## 背景（2026-10-17）：弹种挂件在游戏里其实**只有一条入口**——背包左键。
## 而背包悬浮卡对 module 一律落到通用 else 分支，写着「拖拽：换位或丢弃到地面」，
## 拖到武器格又没有任何反应 ⇒ 玩家试一次就放弃，最后结论是「弹种没有装备入口」。
## 本文件钉住修好之后的三件事：
##   ① 背包左键 / 拖到主武器格 / 拖到副武器格，三条路都能装进指定枪的弹药槽；
##   ② 换下的旧模块回背包，装不上时整体回滚（不许出现「背包少了、枪上也没装」）；
##   ③ 装备界面必须显示当前装的子弹模块（弹药行 + 标题 + 悬浮说明）。
##
## 判据：`BULLET_MODULE_EQUIPMENT_OK` 行，不看裸退出码。

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 10817
	add_child(dungeon)
	for _frame in 6:
		await get_tree().process_frame
	var player := dungeon.player
	var inventory := dungeon.get_inventory_module()
	var ui := dungeon.get("_inventory_ui") as InventoryUI
	if player == null or inventory == null or ui == null:
		failures.append("子弹模块验收运行态未创建")
		_finish(failures)
		return

	_check_starting_bullet(player, failures)
	await _verify_click_install(dungeon, player, inventory, ui, failures)
	_verify_drag_install_to_active(dungeon, player, inventory, ui, failures)
	_verify_drag_install_to_stowed(dungeon, player, inventory, ui, failures)
	await _verify_equipment_display(ui, failures)
	_verify_hover_and_drop_acceptance(ui, inventory, failures)
	_verify_failed_install_rolls_back(dungeon, player, inventory, failures)
	_verify_swap_when_bag_otherwise_full(dungeon, player, inventory, failures)

	dungeon.queue_free()
	await get_tree().process_frame
	_finish(failures)


## 出厂枪必须是标准弹（与 verify_starting_weapon_contract 同一口径，这里只看运行态）。
func _check_starting_bullet(player: Player3D, failures: Array[String]) -> void:
	var item := player.get_equipped_bullet_item_for_slot(player.get_active_weapon_slot())
	_check(
		str(item.get("id", "")) == "mod_bullet_standard",
		"出厂武器的弹药槽不是标准弹（实际 %s）" % str(item.get("id", "<空>")),
		failures
	)


## 入口一：背包左键（`Dungeon3D._on_inventory_item_clicked` → module/bullet 事务）。
func _verify_click_install(
	dungeon: Dungeon3D, player: Player3D, inventory: InventoryModule, ui: InventoryUI,
	failures: Array[String]
) -> void:
	var slot := _seed(inventory, "mod_bullet_sticky")
	if slot < 0:
		failures.append("背包无法放入黏黏弹模块，无法验证左键装配")
		return
	dungeon.call("_on_inventory_item_clicked", slot, {})
	var active := player.get_active_weapon_slot()
	var installed := player.get_equipped_bullet_item_for_slot(active)
	_check(
		str(installed.get("id", "")) == "mod_bullet_sticky",
		"背包装甲左键没有把黏黏弹装进弹药槽（实际 %s）" % str(installed.get("id", "<空>")),
		failures
	)
	_check(
		_count_item(inventory, "mod_bullet_sticky") == 0,
		"左键装配后背包里仍留着黏黏弹模块",
		failures
	)
	_check(
		_count_item(inventory, "mod_bullet_standard") >= 1,
		"换下的标准弹没有回到背包",
		failures
	)
	# 弹种确实生效：运行树子弹节点带 sticky/dot 标签。
	var tree := player.get_weapon_tree()
	var bullet := tree.root.slots.get(AssemblyNode.SlotType.BULLET) as AssemblyNode
	_check(
		bullet != null and "sticky" in bullet.tags and "dot" in bullet.tags,
		"装上的子弹在运行树里没有 sticky/dot 标签",
		failures
	)
	# 左键装配后装备界面要当场反映，不能等下次开关背包才刷新。
	ui.set_inventory_panel_open(true)
	await get_tree().process_frame
	_check(
		ui.equipment_bullet_labels.size() > active
		and ui.equipment_bullet_labels[active].text == "黏黏弹模块",
		"左键装配后装备界面弹药行没有刷新（显示「%s」）" % (
			ui.equipment_bullet_labels[active].text if ui.equipment_bullet_labels.size() > active else "<无控件>"
		),
		failures
	)


## 入口二：拖到主武器格（装备界面的 weapon_0）。
func _verify_drag_install_to_active(
	dungeon: Dungeon3D, player: Player3D, inventory: InventoryModule, ui: InventoryUI,
	failures: Array[String]
) -> void:
	player.switch_weapon_slot(0)
	var slot := _seed(inventory, "mod_bullet_bounce")
	if slot < 0:
		failures.append("背包无法放入回旋镖弹模块")
		return
	ui.call("_on_slot_drop_received", slot, 0, "inventory", "weapon_0")
	var installed := player.get_equipped_bullet_item_for_slot(0)
	_check(
		str(installed.get("id", "")) == "mod_bullet_bounce",
		"拖到主武器格没有换装弹药槽（实际 %s）" % str(installed.get("id", "<空>")),
		failures
	)
	_check(
		_count_item(inventory, "mod_bullet_sticky") >= 1,
		"拖拽换弹后换下的黏黏弹没有回背包",
		failures
	)


## 入口三：拖到备用的副武器格（weapon_1），且不得顺带切换当前武器。
func _verify_drag_install_to_stowed(
	dungeon: Dungeon3D, player: Player3D, inventory: InventoryModule, ui: InventoryUI,
	failures: Array[String]
) -> void:
	var equipped := player.equip_weapon_item_to_slot(
		ItemRegistry.get_instance().get_item("weapon_shotgun"), 1
	)
	if not bool(equipped.get("success", false)):
		failures.append("副武器槽装不上散弹枪，无法验证备用武器换弹")
		return
	player.switch_weapon_slot(0)
	var slot := _seed(inventory, "mod_bullet_piercing")
	if slot < 0:
		failures.append("背包无法放入穿甲弹模块")
		return
	ui.call("_on_slot_drop_received", slot, 1, "inventory", "weapon_1")
	var installed := player.get_equipped_bullet_item_for_slot(1)
	_check(
		str(installed.get("id", "")) == "mod_bullet_piercing",
		"拖到副武器格没有换装弹药槽（实际 %s）" % str(installed.get("id", "<空>")),
		failures
	)
	_check(
		player.get_active_weapon_slot() == 0,
		"给副武器换弹却切换了当前武器",
		failures
	)


## 装备界面必须看得见：弹药标签文字 = 模块名，空槽显示「未装填」。
func _verify_equipment_display(ui: InventoryUI, failures: Array[String]) -> void:
	ui.set_inventory_panel_open(true)
	await get_tree().process_frame
	_check(ui.equipment_bullet_labels.size() == 2, "装备界面没有为两把武器各建一个弹药显示位", failures)
	if ui.equipment_bullet_labels.size() < 2:
		return
	_check(
		ui.equipment_bullet_labels[0].text == "回旋镖弹模块",
		"主武器弹药行显示的是「%s」，期望「回旋镖弹模块」" % ui.equipment_bullet_labels[0].text,
		failures
	)
	_check(
		ui.equipment_bullet_labels[1].text == "穿甲弹模块",
		"副武器弹药行显示的是「%s」，期望「穿甲弹模块」" % ui.equipment_bullet_labels[1].text,
		failures
	)
	for index in range(2):
		var slot := ui.equipment_bullet_slots[index]
		var item := slot.get_meta("slot_item", {}) as Dictionary
		_check(
			not item.is_empty(),
			"第 %d 把武器的弹药格没有填上图标（slot_item 为空）" % index,
			failures
		)
		_check(
			bool(slot.get_meta("drag_disabled", false)),
			"弹药展示格可以被拖出，会把玩家背包里的展示物当真实物品",
			failures
		)


## 悬浮卡必须告诉玩家「怎么装」；武器格只吃枪和子弹模块，不吃瞄具。
func _verify_hover_and_drop_acceptance(
	ui: InventoryUI, inventory: InventoryModule, failures: Array[String]
) -> void:
	var bullet := ItemRegistry.get_instance().get_item("mod_bullet_sticky")
	var text := str(ui.call("_bullet_module_hover_text", bullet))
	_check(text.contains("左键"), "子弹模块悬浮卡没有说明左键装配", failures)
	_check(text.contains("拖到主/副武器格"), "子弹模块悬浮卡没有说明可以拖到武器格", failures)
	_check(
		not text.contains("丢弃到地面"),
		"子弹模块悬浮卡仍在沿用通用「丢弃到地面」文案",
		failures
	)

	var weapon_slot := ui.equipment_weapon_slots[0]
	var bullet_payload := {
		"inventory_drag": true, "source_kind": "inventory", "source_index": 0,
		"item": bullet,
	}
	_check(
		bool(weapon_slot.call("_can_drop_data", Vector2.ZERO, bullet_payload)),
		"武器格拒绝接收子弹模块的拖放",
		failures
	)
	var attachment_payload := {
		"inventory_drag": true, "source_kind": "inventory", "source_index": 0,
		"item": ItemRegistry.get_instance().get_item("attach_scope"),
	}
	_check(
		not bool(weapon_slot.call("_can_drop_data", Vector2.ZERO, attachment_payload)),
		"武器格错误地接收了瞄具配件（配件只能进配件槽）",
		failures
	)


## 装不上时必须整体回滚：近战武器没有弹药槽，模块要完完整整退回背包。
func _verify_failed_install_rolls_back(
	dungeon: Dungeon3D, player: Player3D, inventory: InventoryModule, failures: Array[String]
) -> void:
	var bat := player.equip_weapon_item_to_slot(
		ItemRegistry.get_instance().get_item("weapon_baseball_bat"), 1
	)
	if not bool(bat.get("success", false)):
		failures.append("副武器槽装不上棒球棍，无法验证失败回滚")
		return
	var slot := _seed(inventory, "mod_bullet_homing")
	if slot < 0:
		failures.append("背包无法放入蜂卵弹模块")
		return
	var before := _count_item(inventory, "mod_bullet_homing")
	player.switch_weapon_slot(0)
	var ok := bool(
		dungeon.call(
			"_install_bullet_module_from_inventory",
			slot, inventory.get_slot(slot).get("item", {}), 1
		)
	)
	_check(not ok, "近战武器没有弹药槽，却报告子弹模块装配成功", failures)
	_check(
		_count_item(inventory, "mod_bullet_homing") == before,
		"装配失败后蜂卵弹模块没有退回背包（%d → %d）" % [
			before, _count_item(inventory, "mod_bullet_homing"),
		],
		failures
	)
	_check(
		player.get_equipped_bullet_item_for_slot(1).is_empty(),
		"近战武器的弹药槽被写入了子弹模块",
		failures
	)


## 背包其余格塞满时，1 换 1 仍应成功（先空出本格、旧弹再回填同一格），且不吞物品。
func _verify_swap_when_bag_otherwise_full(
	dungeon: Dungeon3D, player: Player3D, inventory: InventoryModule, failures: Array[String]
) -> void:
	player.equip_weapon_item_to_slot(ItemRegistry.get_instance().get_item("weapon_shotgun"), 1)
	player.switch_weapon_slot(0)
	var slot := _seed(inventory, "mod_bullet_balloon")
	if slot < 0:
		failures.append("背包无法放入气球弹模块")
		return
	var before_id := str(player.get_equipped_bullet_item_for_slot(0).get("id", ""))
	var before_old := _count_item(inventory, before_id)
	var filler := ItemRegistry.get_instance().get_item("item_ammo_pack")
	for index in inventory.get_capacity():
		if index != slot:
			inventory.put_item_in_empty_slot(index, filler, 1)
	var ok := bool(
		dungeon.call(
			"_install_bullet_module_from_inventory",
			slot, inventory.get_slot(slot).get("item", {}), 0
		)
	)
	_check(ok, "背包其余格塞满时 1 换 1 换弹失败（应先把本格空出来再回填旧弹）", failures)
	_check(
		str(player.get_equipped_bullet_item_for_slot(0).get("id", "")) == "mod_bullet_balloon",
		"塞满背包后换弹，弹药槽没有换成气球弹",
		failures
	)
	_check(_count_item(inventory, "mod_bullet_balloon") == 0, "气球弹已装上却还留在背包", failures)
	_check(
		_count_item(inventory, before_id) == before_old + 1,
		"换下的%s没有回到背包（%d → %d）" % [
			before_id, before_old, _count_item(inventory, before_id),
		],
		failures
	)


func _seed(inventory: InventoryModule, item_id: String) -> int:
	var item := ItemRegistry.get_instance().get_item(item_id)
	if item.is_empty():
		return -1
	inventory.add_item(item, 1)
	for index in inventory.get_capacity():
		var slot := inventory.get_slot(index)
		if slot.is_empty():
			continue
		if str((slot.get("item", {}) as Dictionary).get("id", "")) == item_id:
			return index
	return -1


func _count_item(inventory: InventoryModule, item_id: String) -> int:
	var total := 0
	for index in inventory.get_capacity():
		var slot := inventory.get_slot(index)
		if slot.is_empty():
			continue
		if str((slot.get("item", {}) as Dictionary).get("id", "")) == item_id:
			total += int(slot.get("count", 0))
	return total


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("BULLET_MODULE_EQUIPMENT_OK: 子弹模块三条装配入口（左键 / 拖主武器 / 拖副武器）、旧模块回流、满包回滚与装备界面弹药显示全部通过")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
