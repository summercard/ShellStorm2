extends Node
## 弹药模块「手动更换关闭」专项验收。
##
## 背景（2026-10-19 业主口径）：玩家不能从背包直接替换枪的子弹模块；手动更换
## 机制整体锁掉，后续只能通过枪械工坊的特殊流程更换。**随机在枪身上的机制保留** ——
## 掉落枪仍随机自带弹种，且该弹种是这把枪的身份。
##
## 本文件钉住：
##   ① 背包左键 / 拖到主武器格 / 拖到副武器格 三条手动入口全部拒绝，且不吞物品；
##   ② 直接调用 `Player3D.install_bullet_module_to_weapon_slot` 也拒绝（不是只灰 UI）；
##   ③ 装备界面仍显示当前弹药，并明确标注「锁定 · 需枪械工坊」；
##   ④ 掉落枪的随机弹种仍然保留，且掉落枪的绑定原因优先于通用渠道原因。
##
## 判据：`BULLET_MODULE_LOCK_OK` 行，不看裸退出码。

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
const SERVICE := preload("res://src/rewards/RewardService.gd")
const BULLET := preload("res://src/weapons/WeaponBulletDrop.gd")

const STARTING_BULLET := "mod_bullet_standard"
const WORKSHOP_HINT := "枪械工坊"


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
		failures.append("弹药模块验收运行态未创建")
		_finish(failures)
		return

	_check_starting_bullet(player, failures)
	_verify_policy_flag(failures)
	_verify_click_locked(dungeon, player, inventory, failures)
	_verify_drag_locked(player, inventory, ui, failures)
	_verify_weapon_slot_rejects_bullet(ui, failures)
	_verify_hover_copy(player, ui, failures)
	_verify_direct_transaction_locked(player, failures)
	await _verify_equipment_display(ui, failures)
	_verify_dropped_gun_keeps_random_bullet(player, failures)
	_verify_source_guards(failures)

	dungeon.queue_free()
	await get_tree().process_frame
	_finish(failures)


## 出厂枪仍必须是标准弹（与 verify_starting_weapon_contract 同一口径，这里只看运行态）。
func _check_starting_bullet(player: Player3D, failures: Array[String]) -> void:
	var item := player.get_equipped_bullet_item_for_slot(player.get_active_weapon_slot())
	_check(
		str(item.get("id", "")) == STARTING_BULLET,
		"出厂武器的弹药槽不是标准弹（实际 %s）" % str(item.get("id", "<空>")),
		failures
	)


## 总闸必须真的是关的。这条失败意味着有人把常量翻回了 true。
func _verify_policy_flag(failures: Array[String]) -> void:
	_check(
		not BULLET.is_manual_swap_enabled(),
		"弹药模块手动更换总闸被打开了；2026-10-19 口径要求只能走枪械工坊",
		failures
	)
	_check(
		BULLET.manual_swap_block_reason().contains(WORKSHOP_HINT),
		"拒绝原因没有指向枪械工坊：%s" % BULLET.manual_swap_block_reason(),
		failures
	)


## 入口一：背包左键。必须拒绝，且不能出现「背包少了、枪上也没装」。
func _verify_click_locked(
	dungeon: Dungeon3D, player: Player3D, inventory: InventoryModule, failures: Array[String]
) -> void:
	var active := player.get_active_weapon_slot()
	var slot := _seed(inventory, "mod_bullet_sticky")
	if slot < 0:
		failures.append("背包无法放入黏黏弹模块，无法验证左键锁定")
		return
	var before := _count_item(inventory, "mod_bullet_sticky")
	dungeon.call("_on_inventory_item_clicked", slot, {})
	var installed := player.get_equipped_bullet_item_for_slot(active)
	_check(
		str(installed.get("id", "")) == STARTING_BULLET,
		"背包左键仍然换掉了弹药模块（实际 %s）" % str(installed.get("id", "<空>")),
		failures
	)
	_check(
		_count_item(inventory, "mod_bullet_sticky") == before,
		"左键被拒后黏黏弹模块被吞了（%d → %d）" % [
			before, _count_item(inventory, "mod_bullet_sticky"),
		],
		failures
	)
	_check(
		_status_text(dungeon).contains(WORKSHOP_HINT),
		"左键被拒后状态栏没有提示枪械工坊（显示「%s」）" % _status_text(dungeon),
		failures
	)


## 入口二/三：拖到 weapon_0 / weapon_1。两条都必须拒绝，且不动背包。
func _verify_drag_locked(
	player: Player3D, inventory: InventoryModule, ui: InventoryUI, failures: Array[String]
) -> void:
	player.switch_weapon_slot(0)
	# 先给副武器槽放一把枪，确认「拖到备用武器格」也被拦。
	var equipped := player.equip_weapon_item_to_slot(
		ItemRegistry.get_instance().get_item("weapon_shotgun"), 1
	)
	if not bool(equipped.get("success", false)):
		failures.append("副武器槽装不上散弹枪，无法验证备用武器拖放锁定")
		return
	for target in ["weapon_0", "weapon_1"]:
		var slot := _seed(inventory, "mod_bullet_bounce")
		if slot < 0:
			failures.append("背包无法放入回旋镖弹模块，无法验证拖放锁定")
			return
		var before := _count_item(inventory, "mod_bullet_bounce")
		var weapon_index := int(target.trim_prefix("weapon_"))
		var current := str(player.get_equipped_bullet_item_for_slot(weapon_index).get("id", ""))
		ui.call("_on_slot_drop_received", slot, weapon_index, "inventory", target)
		var after := str(player.get_equipped_bullet_item_for_slot(weapon_index).get("id", ""))
		_check(
			after == current,
			"拖到 %s 仍然换掉了弹药模块（%s → %s）" % [target, current, after],
			failures
		)
		_check(
			_count_item(inventory, "mod_bullet_bounce") == before,
			"拖到 %s 被拒后回旋镖弹模块被吞了（%d → %d）" % [
				target, before, _count_item(inventory, "mod_bullet_bounce"),
			],
			failures
		)
	_check(
		player.get_active_weapon_slot() == 0,
		"锁定验证过程中切换了当前武器",
		failures
	)


## 武器格必须在拖放判据层就拒绝子弹模块，而不是等落点后再回滚。
func _verify_weapon_slot_rejects_bullet(ui: InventoryUI, failures: Array[String]) -> void:
	var weapon_slot := ui.equipment_weapon_slots[0]
	var bullet_payload := {
		"inventory_drag": true, "source_kind": "inventory", "source_index": 0,
		"item": ItemRegistry.get_instance().get_item("mod_bullet_sticky"),
	}
	_check(
		not bool(weapon_slot.call("_can_drop_data", Vector2.ZERO, bullet_payload)),
		"武器格仍然接受子弹模块的拖放（手动更换没有真正锁掉）",
		failures
	)
	var weapon_payload := {
		"inventory_drag": true, "source_kind": "inventory", "source_index": 0,
		"item": ItemRegistry.get_instance().get_item("weapon_shotgun"),
	}
	_check(
		bool(weapon_slot.call("_can_drop_data", Vector2.ZERO, weapon_payload)),
		"武器格连整枪都不接受了 —— 锁定子弹模块时误伤了换枪",
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


## 悬浮卡必须告诉玩家「不能装、去哪装」，不能继续写已经不存在的操作。
func _verify_hover_copy(player: Player3D, ui: InventoryUI, failures: Array[String]) -> void:
	var bullet := ItemRegistry.get_instance().get_item("mod_bullet_sticky")
	var text := str(ui.call("_bullet_module_hover_text", bullet))
	_check(text.contains(WORKSHOP_HINT), "子弹模块悬浮卡没有指向枪械工坊", failures)
	_check(
		not text.contains("左键"),
		"子弹模块悬浮卡仍写着「左键装配」，但该入口已关闭",
		failures
	)
	_check(
		not text.contains("拖到主/副武器格"),
		"子弹模块悬浮卡仍写着「拖到主/副武器格」，但拖放已拒绝",
		failures
	)
	_check(
		not text.contains("丢弃到地面"),
		"子弹模块悬浮卡仍在沿用通用「丢弃到地面」文案",
		failures
	)

	var weapon := player.get_equipped_weapon_instance_for_slot(player.get_active_weapon_slot())
	if weapon == null:
		failures.append("读不到当前武器实例，无法验证武器悬浮卡")
		return
	var weapon_text := str(ui.call("_weapon_hover_text", weapon.to_item_dictionary()))
	_check(
		weapon_text.contains("弹药模块") and weapon_text.contains(WORKSHOP_HINT),
		"武器悬浮卡没有说明弹药模块需在枪械工坊更换",
		failures
	)


## 真正的事务入口也必须拒绝。只灰 UI 不算锁。
func _verify_direct_transaction_locked(player: Player3D, failures: Array[String]) -> void:
	var active := player.get_active_weapon_slot()
	var before := str(player.get_equipped_bullet_item_for_slot(active).get("id", ""))
	var result := player.install_bullet_module_to_weapon_slot(
		ItemRegistry.get_instance().get_item("mod_bullet_piercing"), active
	)
	_check(not bool(result.get("success", true)), "直接调用换弹事务仍然成功", failures)
	_check(
		str(result.get("reason", "")).contains(WORKSHOP_HINT),
		"直接事务的拒绝原因没有指向枪械工坊：%s" % str(result.get("reason", "")),
		failures
	)
	_check(
		str(player.get_equipped_bullet_item_for_slot(active).get("id", "")) == before,
		"事务被拒后弹药模块仍然变化（%s → %s）" % [
			before, str(player.get_equipped_bullet_item_for_slot(active).get("id", "")),
		],
		failures
	)


## 装备界面仍要显示当前弹药，标题要能一眼看出锁定。
func _verify_equipment_display(ui: InventoryUI, failures: Array[String]) -> void:
	ui.set_inventory_panel_open(true)
	await get_tree().process_frame
	_check(ui.equipment_bullet_labels.size() == 2, "装备界面没有为两把武器各建一个弹药显示位", failures)
	if ui.equipment_bullet_labels.size() < 2:
		return
	_check(
		ui.equipment_bullet_labels[0].text == "标准子弹模块",
		"主武器弹药行显示的是「%s」，期望「标准子弹模块」" % ui.equipment_bullet_labels[0].text,
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
		var caption := _bullet_caption(slot)
		_check(
			caption != null and caption.text.contains("锁定"),
			"第 %d 把武器的弹药标题没有标注「锁定」（实际「%s」）" % [
				index, caption.text if caption != null else "<无控件>",
			],
			failures
		)
	ui.set_inventory_panel_open(false)


## 「随机在枪身上」必须保留：掉落枪仍带随机弹种，且绑定原因优先于渠道原因。
func _verify_dropped_gun_keeps_random_bullet(player: Player3D, failures: Array[String]) -> void:
	var report := SERVICE.resolve({
		"spec_id": "bullet_lock:ranged",
		"entries": [{"kind": "item", "item_id": "weapon_rifle", "count": 1}],
	}, {"seed": 20261019, "floor": 1})
	_check(bool(report.get("ok", false)), "远程枪掉落规格解析失败：%s" % str(report.get("errors", [])), failures)
	var grants := report.get("grants", []) as Array
	if grants.is_empty():
		failures.append("远程枪掉落没有产出实例")
		return
	var dropped := (grants[0] as Dictionary).get("item", {}) as Dictionary
	_check(
		bool(dropped.get("bullet_module_locked", false)),
		"掉落枪没有标记弹药模块绑定锁定 —— 随机配弹机制被改坏了",
		failures
	)
	var equipped := player.equip_weapon_item_to_slot(dropped, 1)
	_check(bool(equipped.get("success", false)), "掉落枪装不上副武器槽", failures)
	if not bool(equipped.get("success", false)):
		return
	var bound_before := str(player.get_equipped_bullet_item_for_slot(1).get("id", ""))
	_check(
		BULLET.is_valid(bound_before),
		"掉落枪没有随机到合法弹药模块（实际 %s）" % bound_before,
		failures
	)
	var swap_target := "mod_bullet_blackhole" if bound_before != "mod_bullet_blackhole" else STARTING_BULLET
	var rejected := player.install_bullet_module_to_weapon_slot(
		ItemRegistry.get_instance().get_item(swap_target), 1
	)
	_check(not bool(rejected.get("success", true)), "掉落枪的弹药模块仍然换得动", failures)
	_check(
		str(rejected.get("reason", "")).contains("绑定"),
		"掉落枪应先得到「绑定」原因，实际「%s」" % str(rejected.get("reason", "")),
		failures
	)
	_check(
		str(rejected.get("reason", "")).contains(WORKSHOP_HINT),
		"掉落枪的拒绝原因没有指向枪械工坊：%s" % str(rejected.get("reason", "")),
		failures
	)
	_check(
		str(player.get_equipped_bullet_item_for_slot(1).get("id", "")) == bound_before,
		"被拒后掉落枪的弹种变了（%s → %s）" % [
			bound_before, str(player.get_equipped_bullet_item_for_slot(1).get("id", "")),
		],
		failures
	)


## 源码门禁：三条互不共用的入口都要有判据，删掉任何一处都会红。
## 行为测试只能证明「当前这条链」，门禁防的是「以后有人加一条旁路」。
func _verify_source_guards(failures: Array[String]) -> void:
	var guards := {
		"res://src/player3d/Player3D.gd": "is_manual_swap_enabled",
		"res://src/world3d/Dungeon3D.gd": "is_manual_swap_enabled",
		"res://src/ui/InventoryUI.gd": "is_manual_swap_enabled",
		"res://src/ui/ItemSlot.gd": "is_manual_swap_enabled",
		"res://src/training3d/TrainingRange3D.gd": "is_manual_swap_enabled",
	}
	for path in guards.keys():
		var source := FileAccess.get_file_as_string(str(path))
		_check(not source.is_empty(), "换弹入口源文件读取失败：%s" % path, failures)
		_check(
			source.contains(str(guards[path])),
			"%s 缺少弹药模块手动更换总闸判据 —— 该入口能绕过 2026-10-19 口径" % path,
			failures
		)
	var reward_source := FileAccess.get_file_as_string("res://src/rewards/RewardService.gd")
	_check(
		reward_source.contains("WeaponBulletDrop.roll"),
		"RewardService 不再掷随机弹种 —— 「随机在枪身上」的机制被删了",
		failures
	)


func _bullet_caption(bullet_slot: Control) -> Label:
	# 结构固定为 HBox[ 只读弹药格, VBox[「弹药（锁定）」标题, 模块名] ]。
	var row := bullet_slot.get_parent()
	if row == null or row.get_child_count() < 2:
		return null
	var text_col := row.get_child(1) as Control
	if text_col == null or text_col.get_child_count() == 0:
		return null
	return text_col.get_child(0) as Label


func _status_text(dungeon: Dungeon3D) -> String:
	var label := dungeon.get("status_label") as Label
	return label.text if label != null else ""


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
		print("BULLET_MODULE_LOCK_OK: 手动更换已锁（背包左键/拖主武器/拖副武器/直接事务全拒绝）、物品不吞、装备界面标注锁定、掉落枪随机弹种与绑定原因保留")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
