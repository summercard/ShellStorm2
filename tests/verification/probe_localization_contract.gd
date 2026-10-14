extends Node
## 一次性探针：武器构建链路本地化契约（GameText 独立模块，2026-10-14 建立）
##
## 钉住四件会悄悄失效的事：
##  1) 内容节点名必须都有中文条目 —— BlueprintRegistry 新增枪身/子弹/配件却不补
##     GameText.node，K 页会重新冒出内部 ID（GunBody_xxx），本断言必须红。
##  2) 槽位键 / 节点类型键不得原样输出英文枚举名。
##  3) K 键武器表现页绑定真枪后，可见文案里不得残留内部节点 ID 或英文枚举键。
##  4) 语言切换的回退语义：en 预留位（ready=false、条目留空）→ chrome 回退中文、
##     内容节点名回退内部英文 ID；未知语言 id 必须被拒绝。
## 跑法（工程内）：独享 APPDATA + --headless --path . --scene res://tests/verification/probe_localization_contract.tscn

const PANEL_SCENE := "res://scenes/WeaponAssemblyTreePanel.tscn"
const INTERNAL_ID_MARKERS := ["GunBody_", "Bullet_", "Att_", "Melee_"]
const ENUM_KEY_MARKERS := ["MUZZLE", "MAGAZINE", "GUN_BODY", "ATTACHMENT", "TACTICAL", "MUTATOR"]

var _failures: Array[String] = []


func _ready() -> void:
	_check_content_node_contract()
	_check_enum_key_contract()
	_check_locale_switch_fallback()
	await _check_panel_renders_localized()
	_report()


func _check_content_node_contract() -> void:
	# 权威显示名来源＝ItemRegistry 的物品 name（内容节点名 → weapon_* 内容 ID → 物品名）
	var item_registry := ItemRegistry.get_instance()
	var constants: Dictionary = BlueprintRegistry.get_script().get_script_constant_map()
	var node_item_ids: Dictionary = constants.get("ASSEMBLY_NODE_ITEM_IDS", {})
	if node_item_ids.is_empty():
		_fail("BlueprintRegistry.ASSEMBLY_NODE_ITEM_IDS 读不到，契约无法核对")
		return
	GameText.set_locale("zh_CN")
	for node_name in node_item_ids.keys():
		var raw := str(node_name)
		var item_id := str(node_item_ids[node_name])
		var expected := str(item_registry.get_item(item_id).get("name", ""))
		var actual := GameText.node_name(raw)
		if expected.is_empty():
			_fail("内容节点 %s 的内容 ID %s 在 ItemRegistry 里没有 name" % [raw, item_id])
		elif actual == raw:
			_fail("内容节点 %s 缺中文条目（GameText.node）" % raw)
		elif actual != expected:
			_fail("内容节点 %s 文案漂移：GameText=%s / ItemRegistry=%s" % [raw, actual, expected])


func _check_enum_key_contract() -> void:
	GameText.set_locale("zh_CN")
	for key in AssemblyNode.NodeType.keys():
		var type_key := str(key)
		if GameText.node_type_key_name(type_key) == type_key:
			_fail("节点类型键 %s 缺中文（GameText.node_type）" % type_key)
	for key in AssemblyNode.SlotType.keys():
		var slot_key := str(key)
		if GameText.slot_key_name(slot_key) == slot_key:
			_fail("槽位键 %s 缺中文（GameText.slot）" % slot_key)
	# 未知键必须回退到键本身，绝不返回空串
	if GameText.text("__no_such_key__") != "__no_such_key__":
		_fail("未知 UI 键没有回退到键本身")


func _check_locale_switch_fallback() -> void:
	var zh_title := GameText.text("panel.title")
	if bool(GameText.locale_meta("en").get("ready", false)):
		_fail("en 预留位不应标记 ready（除非真的补全了英文文案）")
	var zh_node := GameText.node_name("GunBody_Rifle")
	GameText.set_locale("en")
	if GameText.text("panel.title") != zh_title:
		_fail("en 未填条目时应回退中文，实际=%s" % GameText.text("panel.title"))
	if GameText.node_name("GunBody_Rifle") != zh_node:
		_fail("en 未填 node 条目时应回退中文，实际=%s" % GameText.node_name("GunBody_Rifle"))
	if not GameText.set_locale("__nope__"):
		pass
	else:
		_fail("未知语言 id 不应被接受")
	GameText.set_locale("zh_CN")
	if GameText.get_locale() != "zh_CN":
		_fail("语言未能切回 zh_CN")


func _check_panel_renders_localized() -> void:
	var tree := BlueprintRegistry.build_weapon_tree("bp_rifle", "mod_bullet_piercing")
	if tree == null or tree.get_root() == null:
		_fail("无法构建测试武器树")
		return
	var panel := (load(PANEL_SCENE) as PackedScene).instantiate() as WeaponAssemblyTreePanel
	if panel == null:
		_fail("无法实例化武器表现页")
		return
	add_child(panel)
	await get_tree().process_frame
	panel.set_weapon_tree(tree)
	panel.show_panel()
	await get_tree().process_frame

	var texts: Array[String] = []
	_collect_label_texts(panel, texts)
	if texts.is_empty():
		_fail("武器表现页没有渲染任何文本")
	var internal_leak := false
	for text in texts:
		for marker in INTERNAL_ID_MARKERS:
			if text.contains(marker):
				_fail("武器表现页残留内部节点 ID：%s" % text)
				internal_leak = true
				break
		if internal_leak:
			break
	internal_leak = false
	for text in texts:
		for marker in ENUM_KEY_MARKERS:
			if text.contains(marker):
				_fail("武器表现页残留英文枚举键：%s" % text)
				internal_leak = true
				break
		if internal_leak:
			break

	panel.queue_free()
	tree.free()


func _collect_label_texts(node: Node, out: Array[String]) -> void:
	if node is Label:
		var label := node as Label
		if label.text.strip_edges() != "":
			out.append(label.text)
	for child in node.get_children():
		_collect_label_texts(child, out)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[probe_localization_contract] " + message)


func _report() -> void:
	if _failures.is_empty():
		print("PROBE_LOCALIZATION_CONTRACT_OK")
		get_tree().quit(0)
		return
	print("PROBE_LOCALIZATION_CONTRACT_FAILED count=%d" % _failures.size())
	for message in _failures:
		print("  - " + message)
	get_tree().quit(1)
