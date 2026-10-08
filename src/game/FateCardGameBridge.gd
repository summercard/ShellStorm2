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


func get_source_candidates(card: FateCard) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not requires_source_selection(card) or not is_instance_valid(_player):
		return entries
	set_player(_player)
	var attachment := card.get_stable_card_id() == "fate_attachment_parasite"
	_clear_source_trees()
	var roots: Array[AssemblyNode] = []
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
	if is_instance_valid(_player_weapon_tree) and _player_weapon_tree.root != null and _player_weapon_tree.root not in roots:
		roots.append(_player_weapon_tree.root)
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
			entries.append({"source": source, "supported": supported, "label": "%s / %s · #%s%s" % [root.node_name, source.node_name, source.node_id.right(6), "（仅静态属性，不能触发；选择后保留卡片）" if not supported else ""]})
	return entries


func _choose_entry(heading: String, entries: Array[Dictionary], host: Node) -> Dictionary:
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
	panel.open_choices(heading, entries)
	var selection: Dictionary = await panel.completed
	if is_instance_valid(host) and host.tree_exiting.is_connected(cancel):
		host.tree_exiting.disconnect(cancel)
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
	var result := await _choose_entry("%s：选择来源快照（不消耗、不转移来源物品）" % card.card_name, candidates, host)
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
