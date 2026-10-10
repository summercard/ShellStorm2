extends Node

# FateCardGameBridge.gd — 命运卡片游戏桥接器
# 串联 FateCard 系统与 WeaponAssemblyTree 系统
# Autoload 单例

## 信号
signal card_applied(card: FateCard, success: bool, message: String)
signal card_list_changed()
signal scope_state_changed(scope: String, stable_card_id: String)

## 玩家已应用的卡片列表
var applied_cards: Array[FateCard] = []
var character_card_ids: Array[String] = []
var world_card_ids: Array[String] = []

## 玩家武器装配树（由 Player 初始化后注入）
var _player_weapon_tree: WeaponAssemblyTree = null
var _player: Node = null

func _ready() -> void:
	add_to_group("fate_cards")
	call_deferred("_connect_to_player")

func _connect_to_player() -> void:
	# Player3D 通过稳定组名注册；不要再依赖已退役的 2D 场景层级。
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("get_weapon_tree"):
		set_player(player)
		if _player_weapon_tree == null:
			push_warning("[FateCardGameBridge] Player found but weapon tree is null (weapon may not be initialized yet)")

func set_player(player: Node) -> void:
	if player == null or not player.has_method("get_weapon_tree"):
		return
	_player = player
	var weapon_tree: WeaponAssemblyTree = player.get_weapon_tree()
	if weapon_tree == null:
		return
	if is_instance_valid(_player_weapon_tree) and _player_weapon_tree.tree_changed.is_connected(_on_tree_changed):
		_player_weapon_tree.tree_changed.disconnect(_on_tree_changed)
	_player_weapon_tree = weapon_tree
	if not _player_weapon_tree.tree_changed.is_connected(_on_tree_changed):
		_player_weapon_tree.tree_changed.connect(_on_tree_changed)


func reset_run_state() -> void:
	if is_instance_valid(_player) and _player.has_method("reset_character_fate_state"):
		_player.call("reset_character_fate_state")
	applied_cards.clear()
	character_card_ids.clear()
	world_card_ids.clear()
	_pending_character_rewards.clear()
	_clear_source_trees()
	if is_instance_valid(_reward_status):
		_reward_status.text = ""
	card_list_changed.emit()

## 实例方法：实际应用卡片
func apply_card_instance(card: FateCard, source: AssemblyNode = null) -> Dictionary:
	if card == null:
		return {"success": false, "message": "Card is null"}

	if _player == null or not is_instance_valid(_player):
		_connect_to_player()
	if _player != null and is_instance_valid(_player):
		set_player(_player)
	if card.get_stable_card_id().is_empty():
		return {"success": false, "message": "命运卡缺少正式身份；未应用"}
	if card.scope == FateCard.Scope.CHARACTER:
		return _apply_character_card(card)
	if card.scope == FateCard.Scope.WORLD:
		var result := FateCardEngine.apply_world_card(card)
		result["scope"] = FateCard.scope_name(card.scope)
		result["scope_special_name"] = FateCard.scope_special_name(card.scope)
		result["scope_display_name"] = FateCard.scope_display_name(card.scope)
		if bool(result.get("success", false)):
			world_card_ids.append(card.get_stable_card_id())
			applied_cards.append(card)
			scope_state_changed.emit(result["scope"], card.get_stable_card_id())
			card_list_changed.emit()
		card_applied.emit(card, bool(result.get("success", false)), str(result.get("message", "")))
		return result
	if _player_weapon_tree == null:
		return {"success": false, "message": "Player weapon tree not initialized"}

	var scope_name := FateCard.scope_name(card.scope)
	var target_snapshot: Dictionary = {}
	if card.scope == FateCard.Scope.WEAPON:
		if _player == null or not _player.has_method("get_weapon_presentation_snapshot"):
			return {"success": false, "message": "当前枪械实例不可用", "scope": scope_name}
		target_snapshot = _player.call("get_weapon_presentation_snapshot") as Dictionary
		if target_snapshot.is_empty():
			return {"success": false, "message": "当前没有装备枪械", "scope": scope_name}
		var used := int(target_snapshot.get("fate_slot_used", 0))
		var capacity := int(target_snapshot.get("fate_slot_capacity", 0))
		if used >= capacity:
			return {
				"success": false,
				"message": "枪械命运槽已满 %d/%d；卡片未消耗" % [used, capacity],
				"scope": scope_name,
				"weapon_instance_id": target_snapshot.get("weapon_instance_id", ""),
				"slot_used": used,
				"slot_capacity": capacity,
			}

	# 委托给 FateCardEngine 执行完整效果（支持所有 EffectAction）
	# 使用 GDScript preload 避免 class_name 加载顺序问题
	var engine_script: GDScript = preload("res://src/weapons/FateCardEngine.gd") as GDScript
	var engine_class: Variant = engine_script
	var targets: Array[AssemblyNode] = []
	if card.get_stable_card_id() in ["fate_gun_on_gun", "fate_bullet_carry_gun", "fate_attachment_parasite"]:
		var source_result := _resolve_source_targets(card, source)
		if not bool(source_result.get("success", false)):
			card_applied.emit(card, false, str(source_result["message"]))
			return source_result
		targets.assign(source_result["targets"])
	var execution_tree := _player_weapon_tree
	if card.scope == FateCard.Scope.WEAPON:
		execution_tree = (_player.call("get_equipped_weapon_instance") as WeaponInstance).build_runtime_tree()
		if execution_tree == null:
			return {"success": false, "message": "无法建立命运事务预览"}
		if not targets.is_empty():
			targets[0] = execution_tree.root if targets[0] == _player_weapon_tree.root else execution_tree.root.slots.get(AssemblyNode.SlotType.BULLET) as AssemblyNode
	var engine_result: Object = engine_class.apply_card(card, execution_tree, targets)

	var result_dict: Dictionary = {
		"success": engine_result.success,
		"message": engine_result.message,
		"scope": scope_name,
		"scope_special_name": FateCard.scope_special_name(card.scope),
		"scope_display_name": FateCard.scope_display_name(card.scope),
	}
	if engine_result.success:
		if card.scope == FateCard.Scope.WEAPON:
			var transaction_id := "fate:%s:%02d:%s" % [
				target_snapshot.get("weapon_instance_id", ""), int(target_snapshot.get("fate_slot_used", 0)) + 1, card.get_stable_card_id(),
			]
			var slot_result := _player.call(
				"commit_fate_weapon_upgrade", card, execution_tree, transaction_id
			) as Dictionary
			execution_tree.free()
			if not bool(slot_result.get("success", false)):
				result_dict["success"] = false
				result_dict["message"] = str(slot_result.get("reason", "命运槽提交失败"))
				card_applied.emit(card, false, result_dict["message"])
				return result_dict
			var record := slot_result.get("record", {}) as Dictionary
			result_dict["weapon_instance_id"] = target_snapshot.get("weapon_instance_id", "")
			result_dict["slot_index"] = record.get("slot_index", 0)
			result_dict["slot_capacity"] = target_snapshot.get("fate_slot_capacity", 0)
		else:
			world_card_ids.append(card.get_stable_card_id())
		applied_cards.append(card)
		if card.scope != FateCard.Scope.WEAPON:
			scope_state_changed.emit(scope_name, card.get_stable_card_id())
		card_applied.emit(card, true, engine_result.message)
		card_list_changed.emit()
	else:
		if execution_tree != _player_weapon_tree:
			execution_tree.free()
		card_applied.emit(card, false, engine_result.message)

	return result_dict


func _apply_character_card(card: FateCard) -> Dictionary:
	if not is_instance_valid(_player) or not _player.has_method("apply_character_fate_modifier"):
		return {"success": false, "message": "角色命运所有者不可用；卡片未消耗"}
	var result: Dictionary = _player.call("apply_character_fate_modifier", card.effect)
	result["scope"] = FateCard.scope_name(card.scope)
	result["scope_special_name"] = FateCard.scope_special_name(card.scope)
	result["scope_display_name"] = FateCard.scope_display_name(card.scope)
	if bool(result.get("success", false)):
		character_card_ids.append(card.get_stable_card_id())
		applied_cards.append(card)
		scope_state_changed.emit(result["scope"], card.get_stable_card_id())
		card_list_changed.emit()
	card_applied.emit(card, bool(result.get("success", false)), str(result.get("message", "")))
	return result


func _resolve_source_targets(card: FateCard, source: AssemblyNode) -> Dictionary:
	var root := _player_weapon_tree.get_root()
	if root == null:
		return {"success": false, "message": "当前没有目标枪械"}
	var attachment_card := card.get_stable_card_id() == "fate_attachment_parasite"
	var candidates: Array[AssemblyNode] = []
	for node: AssemblyNode in root.get_all_descendants():
		if node.node_type == AssemblyNode.NodeType.ATTACHMENT and not bool(node.base_stats.get("fate_trigger_attachment", false)):
			candidates.append(node)
	# 现有选卡UI只有目标枪，没有第二把来源枪或背包来源选择契约；不能暗选副槽或复制目标枪。
	if source == null:
		if attachment_card and candidates.size() == 1:
			source = candidates[0]
		else:
			return {"success": false, "reason": "source_selection_required", "message": "需要明确选择真实来源%s；请打开来源选择，卡片未消耗" % ("配件" if attachment_card else "枪械")}
	var expected_type := AssemblyNode.NodeType.ATTACHMENT if attachment_card else AssemblyNode.NodeType.GUN_BODY
	if not is_instance_valid(source) or source.node_type != expected_type:
		return {"success": false, "message": "所选来源类型无效；卡片未消耗"}
	var owned := source == root or source in root.get_all_descendants()
	# 显式来源仅接受玩家实际持有的运行节点，不接受临时伪造属性节点。
	if not owned and _player.has_method("owns_fate_source_node"):
		owned = bool(_player.call("owns_fate_source_node", source))
	if not owned:
		for entry: Dictionary in _owned_source_trees.values():
			var tree := entry["tree"] as WeaponAssemblyTree
			if not is_instance_valid(tree) or tree.root == null:
				continue
			if source != tree.root and source not in tree.root.get_all_descendants():
				continue
			var current: WeaponInstance = _player.call("get_equipped_weapon_instance_for_slot", entry["slot"])
			owned = current == entry["instance"] and current.assembly_snapshot == entry["snapshot"]
			break
	if not owned:
		return {"success": false, "message": "来源已离开当前装备或装配已改变；卡片未消耗"}
	var target := root if card.get_stable_card_id() == "fate_gun_on_gun" else root.slots.get(AssemblyNode.SlotType.BULLET) as AssemblyNode
	if target == null:
		return {"success": false, "message": "目标没有子弹模块"}
	return {"success": true, "targets": [target, source]}


const SOURCE_PANEL := preload("res://src/ui/FateSourceSelectionPanel.gd")
var _source_selection_busy := false
var _reward_button: Button
var _reward_status: Label
var _owned_source_trees: Dictionary = {}


func _clear_source_trees() -> void:
	for entry: Dictionary in _owned_source_trees.values():
		var tree := entry["tree"] as WeaponAssemblyTree
		if is_instance_valid(tree):
			tree.free()
	_owned_source_trees.clear()


func _exit_tree() -> void:
	_clear_source_trees()


func requires_source_selection(card: FateCard) -> bool:
	return card != null and card.get_stable_card_id() in ["fate_gun_on_gun", "fate_bullet_carry_gun", "fate_attachment_parasite"]


## 来源选择的正文说明。旧版只把标题重复了一遍，玩家看不出「为什么要选、选了会怎样」。
## 这里按具体卡解释用途，并统一交代只读语义 —— 这是取消时「卡片保留」承诺的另一半。
func _source_selection_hint(card: FateCard) -> String:
	var read_only := "来源只被读取一次，不会被消耗、不会被移走，你现在的装备也不变。"
	match card.get_stable_card_id():
		"fate_bullet_carry_gun":
			return (
				"这张命运把一把枪装到子弹上，子弹命中时才开火。"
				+ "选中的枪按它此刻的装配与命运改装复刻。" + read_only
			)
		"fate_gun_on_gun":
			return (
				"这张命运把一把枪挂到主枪上作为副枪。"
				+ "选中的枪按它此刻的装配与命运改装复刻。" + read_only
			)
		"fate_attachment_parasite":
			return "这张命运把一个配件的效果寄生到子弹上。" + read_only
	return read_only


func get_source_candidates(card: FateCard) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not requires_source_selection(card) or not is_instance_valid(_player):
		return entries
	set_player(_player)
	var attachment := card.get_stable_card_id() == "fate_attachment_parasite"
	_clear_source_trees()
	var roots: Array[AssemblyNode] = []
	# 每个来源根随身带着「它属于哪把枪的物品数据」与来源位置。图标卡片要画的是玩家
	# 真正持有的那把枪（含装配与命运改装），所以直接复用 WeaponInstance.to_item_dictionary()，
	# 不在 UI 侧另造一套模型数据 —— 名字与图标因此永远同源，不会出现「写的是这把、画的是那把」。
	var root_items: Dictionary = {}
	var root_origins: Dictionary = {}
	# 未激活过的副槽没有运行树；只从真实持有实例水合只读来源，提交前重验实例与装配。
	if _player.has_method("get_equipped_weapon_instance_for_slot"):
		for slot in range(2):
			var instance: WeaponInstance = _player.call("get_equipped_weapon_instance_for_slot", slot)
			if instance == null or instance == _player.call("get_equipped_weapon_instance"):
				continue
			var tree := instance.build_runtime_tree()
			if tree != null:
				_owned_source_trees[instance.weapon_instance_id] = {"tree": tree, "slot": slot, "instance": instance, "snapshot": instance.assembly_snapshot.duplicate(true)}
				roots.append(tree.root)
				root_items[tree.root] = instance.to_item_dictionary()
				root_origins[tree.root] = "副武器槽 %d" % (slot + 1)
	if is_instance_valid(_player_weapon_tree) and _player_weapon_tree.root != null and _player_weapon_tree.root not in roots:
		roots.append(_player_weapon_tree.root)
		root_items[_player_weapon_tree.root] = _equipped_weapon_item()
		root_origins[_player_weapon_tree.root] = "当前装备"
	for root in roots:
		var nodes: Array[AssemblyNode] = []
		if attachment:
			nodes.assign(root.get_all_descendants())
		else:
			nodes.append(root)
		for source in nodes:
			if source.node_type != (AssemblyNode.NodeType.ATTACHMENT if attachment else AssemblyNode.NodeType.GUN_BODY):
				continue
			if bool(source.base_stats.get("fate_trigger_attachment", false)):
				continue
			if not bool(_resolve_source_targets(card, source).get("success", false)):
				continue
			var stats := source.get_computed_stats()
			var supported := not attachment or stats.has("pull_strength") or stats.has("bullet_count") or stats.has("copy_chance")
			entries.append(
				_build_source_entry(
					source,
					root_items.get(root, {}) as Dictionary,
					str(root_origins.get(root, "")),
					attachment,
					supported
				)
			)
	return entries


## 单个来源候选。文字与图标共用同一份物品数据，避免「名字对、图标不对」这类分叉。
## 返回字典**保留旧契约字段**（source / supported / label），另行附加面板展示字段：
##   icon_item  交给 ItemModelIcon3D 直接投影的 item 字典（与背包/商人同口径）
##   title      主标题（中文武器名；旧版显示的是 GunBody_* 这种内部节点名）
##   subtitle   来源位置 + 实例短号
##   badge      命运槽占用或可用性提示
##   accent     按稀有度取的强调色（与 ItemModelIcon3D._item_tint 同色）
func _build_source_entry(
	source: AssemblyNode,
	owner_item: Dictionary,
	origin: String,
	attachment: bool,
	supported: bool
) -> Dictionary:
	var icon_item := _source_icon_item(source, owner_item, attachment)
	var display_name := str(icon_item.get("name", source.node_name))
	var short_id := source.node_id.right(6).to_upper()
	var note := "仅静态属性，不能触发；选择后保留卡片" if not supported else ""
	var label := "%s · #%s" % [display_name, short_id]
	if not note.is_empty():
		label += "（%s）" % note
	return {
		"source": source,
		"supported": supported,
		"label": label,
		"icon_item": icon_item,
		"title": display_name,
		"subtitle": "%s · 实例 #%s" % [
			origin if not origin.is_empty() else "已装备来源",
			short_id,
		],
		"badge": note if not note.is_empty() else _fate_slot_badge(icon_item),
		"accent": _rarity_accent(str(icon_item.get("rarity", "common"))),
	}


## 来源图标数据：与地面拾取 / 背包 / 商人的 item 字典同口径，ItemModelFactory3D 直接消费。
## 武器优先用所属实例的完整物品数据（含装配快照与命运改装）；实例不可得时退回
## 「枪身名 → gun_id」的权威映射，保证任何路径下都有正确机型可画。
func _source_icon_item(node: AssemblyNode, owner_item: Dictionary, attachment: bool) -> Dictionary:
	if attachment:
		return {
			"id": "fate_source_attachment",
			"type": "attachment",
			"name": node.node_name,
			"rarity": "common",
		}
	var item := owner_item.duplicate(true)
	if str(item.get("type", "")) != "weapon":
		# 内容注册表返回的条目必须再复制一份：下面要就地改写 name/type/assembly_id，
		# 直接改注册表内部字典会污染全局物品定义。
		item = _content_item_for(node).duplicate(true)
	item["type"] = "weapon"
	item["stack_max"] = 1
	var display_name := str(item.get("name", ""))
	if display_name.is_empty() or display_name == node.node_name:
		item["name"] = _content_display_name(node)
	if str(item.get("assembly_id", "")).is_empty():
		item["assembly_id"] = _gun_id_for_node(node)
	if str(item.get("rarity", "")).is_empty():
		item["rarity"] = "common"
	return item


## 枪身节点 → 内容物品条目。ItemRegistry 是稳定内容 ID 的唯一来源。
func _content_item_for(node: AssemblyNode) -> Dictionary:
	var registry := ItemRegistry.get_instance()
	if registry == null or node == null:
		return {}
	var content_id := WeaponInstance.content_id_for_root(node)
	if content_id.is_empty():
		return {}
	return registry.get_item(content_id)


func _content_display_name(node: AssemblyNode) -> String:
	var entry := _content_item_for(node)
	return str(entry.get("name", node.node_name if node != null else ""))


## 枪身节点名 → gun_id。唯一来源是内容注册表链（BlueprintRegistry → ItemRegistry），
## 与世界表现层同一份映射，UI 侧不另抄表。
## ⛔ 不要在这里静态引用 `WeaponModel3D.GUN_NAME_TO_ID`：本脚本是启动期 autoload，
## 编译期把表现层脚本（进而 autoload `BlueprintRegistry`）拉进来会让整条图标链加载失败
## —— 2026-10-10 实测：启动报 `Failed to instantiate scene state ... node count is 0`，
## 连带 Dungeon3D 的 HUD 武器图标一起变空。
func _gun_id_for_node(node: AssemblyNode) -> String:
	if node == null:
		return ""
	# 注册表不可用时留空，由 ItemModelFactory3D 的默认机型兜底。
	if ItemRegistry.get_instance() == null:
		return ""
	return WeaponInstance.assembly_id_for_root(node)


## 命运槽占用提示。物品没有槽位信息（非枪械）时返回空串，面板不显示该行。
func _fate_slot_badge(item: Dictionary) -> String:
	var capacity := int(item.get("fate_slot_capacity", 0))
	if capacity <= 0:
		return ""
	var upgrades: Variant = item.get("fate_upgrades", [])
	var used: int = 0
	if upgrades is Array:
		used = (upgrades as Array).size()
	return "命运槽 %d/%d" % [used, capacity]


## 稀有度 → 强调色，与 ItemModelIcon3D._item_tint 同色，保证图标与卡片描边同源。
func _rarity_accent(rarity: String) -> Color:
	match rarity:
		"legendary":
			return Color(1.0, 0.54, 0.12)
		"epic":
			return Color(0.72, 0.38, 1.0)
		"rare":
			return Color(0.28, 0.68, 1.0)
		"uncommon":
			return Color(0.34, 0.92, 0.56)
		_:
			return Color(0.72, 0.80, 0.84)


## 当前装备枪的物品数据。玩家侧没有实例时返回空字典，由节点名映射兜底。
func _equipped_weapon_item() -> Dictionary:
	if not is_instance_valid(_player) or not _player.has_method("get_equipped_weapon_item"):
		return {}
	var item: Variant = _player.call("get_equipped_weapon_item")
	return item if item is Dictionary else {}


func _choose_entry(heading: String, entries: Array[Dictionary], host: Node, hint := "") -> Dictionary:
	if _source_selection_busy:
		return {"success": false, "message": "已有命运选择正在处理；卡片保留"}
	_source_selection_busy = true
	var panel := SOURCE_PANEL.new()
	add_child(panel)
	var cancel := Callable(panel, "cancel")
	if is_instance_valid(host):
		host.tree_exiting.connect(cancel, CONNECT_ONE_SHOT)
	var was_paused := get_tree().paused
	get_tree().paused = true
	panel.open_choices(heading, entries, hint)
	var selection: Dictionary = await panel.completed
	# Window 的 completed 信号可能还有其他监听者。不要在同一轮信号分发中
	# 立即 remove_child；再等一帧，让所有监听者和 Window 自己的 deferred 完成路径收口。
	await get_tree().process_frame
	if is_instance_valid(host) and host.tree_exiting.is_connected(cancel):
		host.tree_exiting.disconnect(cancel)
	if is_instance_valid(panel):
		if panel.is_inside_tree():
			remove_child(panel)
		panel.queue_free()
	get_tree().paused = was_paused
	_source_selection_busy = false
	return selection


func select_card_source(card: FateCard, host: Node) -> Dictionary:
	if not requires_source_selection(card):
		return {"success": true, "source": null}
	var candidates := get_source_candidates(card)
	if candidates.is_empty():
		return {"success": false, "reason": "source_selection_required", "message": "没有可选的真实已装备来源；请先装备枪械或配件，卡片保留"}
	var target_id := str(get_target_summary(card).get("weapon_instance_id", ""))
	var result := await _choose_entry(
		"%s · 选择来源" % card.card_name, candidates, host, _source_selection_hint(card)
	)
	if not bool(result.get("success", false)):
		return result
	if target_id != str(get_target_summary(card).get("weapon_instance_id", "")):
		return {"success": false, "message": "目标枪已改变；卡片保留，请重新选择"}
	var source := (result["entry"] as Dictionary).get("source") as AssemblyNode
	if not is_instance_valid(source):
		return {"success": false, "message": "来源已失效；卡片保留"}
	return {"success": true, "source": source}


func apply_card_with_source_selection(card: FateCard, host: Node) -> Dictionary:
	if _source_selection_busy:
		return {"success": false, "message": "请先完成当前来源选择"}
	var selection := await select_card_source(card, host)
	if not bool(selection.get("success", false)):
		return selection
	return apply_card_instance(card, selection.get("source") as AssemblyNode)


func _process(_delta: float) -> void:
	if _pending_character_rewards.is_empty() and not is_instance_valid(_reward_button):
		return
	if not is_instance_valid(_reward_button):
		var layer := CanvasLayer.new()
		layer.name = "FatePendingRewards"
		layer.layer = 80
		add_child(layer)
		_reward_button = Button.new()
		_reward_button.position = Vector2(16, 260)
		_reward_button.pressed.connect(_open_pending_rewards)
		layer.add_child(_reward_button)
		_reward_status = Label.new()
		_reward_status.position = Vector2(16, 304)
		_reward_status.add_theme_color_override("font_color", Color.WHITE)
		_reward_status.add_theme_color_override("font_outline_color", Color.BLACK)
		_reward_status.add_theme_constant_override("outline_size", 5)
		layer.add_child(_reward_status)
	_reward_button.visible = not _pending_character_rewards.is_empty() and is_instance_valid(_player)
	_reward_button.text = "待领命运（%d）· 点击领取" % _pending_character_rewards.size()
	_reward_button.disabled = _source_selection_busy


func _open_pending_rewards() -> void:
	var entries: Array[Dictionary] = []
	for reward in _pending_character_rewards:
		var card: FateCard = reward["card"]
		entries.append({"reward": reward, "label": "%s · %s · %d魂" % [card.card_name, card.orientation_name(), int(reward["currency_cost"])]})
	var choice := await _choose_entry("待领命运：失败与取消均保留原牌、原方位", entries, _player)
	if not bool(choice.get("success", false)):
		return
	var reward: Dictionary = choice["entry"]["reward"]
	var card: FateCard = reward["card"]
	var selection := await select_card_source(card, _player)
	if not bool(selection.get("success", false)):
		_reward_status.text = str(selection.get("message", "未领取"))
		return
	var index := _pending_character_rewards.find(reward)
	var result := retry_pending_character_reward(index, selection.get("source") as AssemblyNode)
	_reward_status.text = str(result.get("message", ""))


func get_target_summary(card: FateCard = null) -> Dictionary:
	if card == null:
		return {}
	var result := {
		"scope": FateCard.scope_name(card.scope),
		"scope_special_name": FateCard.scope_special_name(card.scope),
		"scope_display_name": FateCard.scope_display_name(card.scope),
		"occupies_weapon_slot": card.occupies_weapon_slot(),
		"stable_card_id": card.get_stable_card_id(),
	}
	if card.scope == FateCard.Scope.WEAPON and _player != null and _player.has_method(
		"get_weapon_presentation_snapshot"
	):
		var snapshot := _player.call("get_weapon_presentation_snapshot") as Dictionary
		result.merge(snapshot, true)
		result["next_slot_index"] = int(snapshot.get("fate_slot_used", 0)) + 1
	return result

## 应用一张命运卡片（静态方法，供外部调用）
static func apply_card(card: FateCard, source: AssemblyNode = null) -> Dictionary:
	if card == null:
		return {"success": false, "message": "Card is null"}

	var instance: Node = _get_instance()
	if instance == null:
		return {"success": false, "message": "FateCardGameBridge instance not found"}

	return instance.apply_card_instance(card, source)

## 供 MapFateTriggers 环境自动层调用。
## 战斗类命运必须由玩家抽卡后经 apply_card() 生效；即使未来误把这些 ID 重新塞回
## MapFateTriggers 配置，本桥也必须拒绝，避免恢复「卡没抽却自动生效」的旁路。
static func apply_fate_card_from_trigger(fate_card_id: String) -> Dictionary:
	match fate_card_id:
		"fate_reinforce", "fate_curse_map", "fate_bless_dead", "fate_mark_enemy":
			return {
				"success": false,
				"message": "Combat fate requires a drawn card: " + fate_card_id,
			}

	var card: FateCard = null
	match fate_card_id:
		"fate_mark_enemy": card = FateCardPresets.fate_mark_enemy()
		"fate_lucky_chest": card = FateCardPresets.fate_lucky_chest()
		"fate_extra_loot": card = FateCardPresets.fate_extra_loot()
	if card == null:
		return {"success": false, "message": "Unknown fate_card_id: " + fate_card_id}
	return apply_card(card)


## 获取单例实例（通过组查找，比节点路径更稳定）
static func _get_instance() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group("fate_cards")

func get_weapon_tree() -> WeaponAssemblyTree:
	return _player_weapon_tree

func get_card_count() -> int:
	return applied_cards.size()

func get_cards() -> Array[FateCard]:
	return applied_cards.duplicate()


func get_scope_cards(scope: FateCard.Scope) -> Array[FateCard]:
	var cards: Array[FateCard] = []
	for card in applied_cards:
		if card != null and card.scope == scope:
			cards.append(card)
	return cards


func get_scope_state_snapshot() -> Dictionary:
	var character_cards: Array[Dictionary] = []
	var world_cards: Array[Dictionary] = []
	for card in applied_cards:
		if card == null or card.scope == FateCard.Scope.WEAPON:
			continue
		var entry := {
			"stable_card_id": card.get_stable_card_id(),
			"name": card.card_name,
			"short_description": card.short_description,
			"scope": FateCard.scope_name(card.scope),
			"scope_display_name": FateCard.scope_display_name(card.scope),
			"orientation": card.orientation_name(),
			"orientation_symbol": card.orientation_symbol(),
		}
		if card.scope == FateCard.Scope.CHARACTER:
			character_cards.append(entry)
		else:
			world_cards.append(entry)
	return {"character": character_cards, "world": world_cards}


func get_latest_applied_card(stable_card_id: String) -> FateCard:
	for index in range(applied_cards.size() - 1, -1, -1):
		var card := applied_cards[index]
		if card != null and card.get_stable_card_id() == stable_card_id:
			return card
	return null

var _pending_character_rewards: Array[Dictionary] = []


func grant_random_card_from_character(currency_cost: int = 0) -> Dictionary:
	var offer := FateCardPresets.draw_offer(1)
	if offer.is_empty():
		return {"success": false, "message": "运行牌池为空"}
	_pending_character_rewards.append({"card": offer[0], "currency_cost": maxi(0, currency_cost)})
	return retry_pending_character_reward(_pending_character_rewards.size() - 1)


func retry_pending_character_reward(index: int = 0, source: AssemblyNode = null) -> Dictionary:
	if index < 0 or index >= _pending_character_rewards.size():
		return {"success": false, "message": "没有该待领取角色命运奖励"}
	var reward: Dictionary = _pending_character_rewards[index]
	var cost := int(reward["currency_cost"])
	if cost > 0 and not GameManager.spend_currency(cost):
		return {"success": false, "pending": true, "message": "魂不足；保留已抽定的命运奖励"}
	var result := apply_card_instance(reward["card"] as FateCard, source)
	if bool(result.get("success", false)):
		_pending_character_rewards.remove_at(index)
	else:
		if cost > 0:
			GameManager.add_currency(cost)
		result["pending"] = true
	return result


func get_pending_character_rewards() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for reward: Dictionary in _pending_character_rewards:
		var card: FateCard = reward["card"]
		result.append({"stable_card_id": card.get_stable_card_id(), "orientation": card.orientation_name(), "currency_cost": reward["currency_cost"]})
	return result


func grant_random_card_from_trigger() -> void:
	push_warning("随机角色命运必须由已抽取的愚者击杀规则触发")


func record_applied_card(_card: FateCard) -> void:
	push_warning("拒绝绕过作用域/槽位事务直接记录命运卡")

func _on_tree_changed() -> void:
	pass

## 只序列化已提交记录与固定待领奖励；不保存 Node、来源选择或 UI 会话。
func export_fate_snapshot() -> Dictionary:
	var cards: Array = []
	var pending: Array = []
	for card in applied_cards:
		var entry := card.get_orientation_snapshot()
		entry["stable_card_id"] = card.get_stable_card_id()
		cards.append(entry)
	for reward in _pending_character_rewards:
		var card: FateCard = reward["card"]
		var entry := card.get_orientation_snapshot()
		entry["stable_card_id"] = card.get_stable_card_id()
		pending.append({"card": entry, "currency_cost": reward["currency_cost"]})
	return {"version": 1, "cards": cards, "pending": pending}


## 直接替换记录，绝不调用 apply/roll/扣魂；重复导入不重复登记。
func import_fate_snapshot(value: Variant) -> bool:
	applied_cards.clear()
	character_card_ids.clear()
	world_card_ids.clear()
	_pending_character_rewards.clear()
	_clear_source_trees()
	if not value is Dictionary or value.get("version", 0) != 1:
		card_list_changed.emit()
		return false
	var restored_cards: Array[FateCard] = []
	var restored_pending: Array[Dictionary] = []
	for field in ["cards", "pending"]:
		if not value.get(field) is Array:
			card_list_changed.emit()
			return false
		for row in value[field]:
			if not row is Dictionary:
				return false
			var entry: Variant = row.get("card") if field == "pending" else row
			if not entry is Dictionary or not entry.get("stable_card_id") is String:
				return false
			var card := FateCardPresets.get_by_card_id(entry["stable_card_id"])
			if card == null or entry.get("orientation", "") not in ["UPRIGHT", "REVERSED"]:
				return false
			var roll: Variant = entry.get("orientation_roll")
			if not Player3D.is_fate_snapshot_number(roll, 0.0, 1.0):
				return false
			card.set_orientation(FateCard.Orientation.REVERSED if entry["orientation"] == "REVERSED" else FateCard.Orientation.UPRIGHT, float(roll))
			# 效果参数只作完整性字段；执行参数永远从稳定ID的正式预设重建，
			# 因而损坏/过期参数不会注入运行时，也不会重放即时效果。
			if not entry.get("effect_params_snapshot") is Dictionary:
				push_warning("[FateCardGameBridge] 拒绝缺失命运效果参数：%s" % entry["stable_card_id"])
				return false
			if field == "cards":
				restored_cards.append(card)
			else:
				if not Player3D.is_fate_snapshot_number(row.get("currency_cost"), 0, 2147483647, true):
					return false
				restored_pending.append({"card": card, "currency_cost": int(row["currency_cost"])})
	applied_cards.assign(restored_cards)
	_pending_character_rewards.assign(restored_pending)
	for card in applied_cards:
		if card.scope == FateCard.Scope.CHARACTER:
			character_card_ids.append(card.get_stable_card_id())
		elif card.scope == FateCard.Scope.WORLD:
			world_card_ids.append(card.get_stable_card_id())
	card_list_changed.emit()
	return true


func _to_string() -> String:
	return "[FateCardGameBridge: cards=%d]" % applied_cards.size()
