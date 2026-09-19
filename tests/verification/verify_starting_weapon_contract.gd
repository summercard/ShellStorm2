extends Node

## 出厂枪契约门禁。
##
## 「新档出生 / 死亡返城白送哪把枪」由 `BlueprintRegistry.DEFAULT_STARTING_GUN_ID`
## 这一个常量决定，但同一个武器的身份、数值与命运槽容量分散写在三个文件里：
##   `ItemRegistry._register_weapon_drops()`      —— 内容 ID / 装配 ID / 价格 / 命运槽容量
##   `BlueprintRegistry._build_registry()`        —— 装配节点名 / 工厂 / base_stats
##   `BlueprintRegistry.ASSEMBLY_NODE_ITEM_IDS`   —— 节点名 -> 内容 ID 反查
## 任何一处漏改都不会报错，只会静默地少一把枪、少一个槽位、或者把默认枪偷偷换回去。
## 本场景把这三处钉在一起，并为蜂窝机枪留一条「没被顺手改坏」的回归哨兵。
##
## `_probe_completed` 是防假绿哨兵：脚本中途出错会静默中断本函数并留下空失败表。

const EXPECTED_CONTENT_ID := "weapon_sprinkler"
const EXPECTED_ASSEMBLY_ID := "bp_sprinkler"
const EXPECTED_NODE_NAME := "GunBody_Sprinkler"
const EXPECTED_DISPLAY_NAME := "花洒机枪"
const EXPECTED_PRICE := 90
const EXPECTED_FATE_SLOTS := 4
const EXPECTED_DAMAGE := 8
const EXPECTED_FIRE_RATE := 12.0
const EXPECTED_MAGAZINE := 100

## 蜂窝机枪的原始数值：出厂枪必须与它共用射速与散布，但不得把原枪改掉。
const MACHINEGUN_ASSEMBLY_ID := "bp_machinegun"
const MACHINEGUN_DAMAGE := 15
const MACHINEGUN_MAGAZINE := 60

var _probe_completed := false


func _ready() -> void:
	var failures: Array[String] = []
	_check_starting_gun_constant(failures)
	_check_item_definition(failures)
	_check_assembly_contract(failures)
	_check_attachment_slots(failures)
	_check_fate_slot_capacity(failures)
	_check_starting_tree(failures)
	_check_machinegun_regression(failures)
	_probe_completed = true
	_report(failures)


func _check_starting_gun_constant(failures: Array[String]) -> void:
	if BlueprintRegistry.DEFAULT_STARTING_GUN_ID != EXPECTED_ASSEMBLY_ID:
		failures.append(
			"出厂枪常量是 %s，期望 %s；改这里等于换掉所有新档和死亡返城白送的枪"
			% [BlueprintRegistry.DEFAULT_STARTING_GUN_ID, EXPECTED_ASSEMBLY_ID]
		)


func _check_item_definition(failures: Array[String]) -> void:
	var item := ItemRegistry.get_instance().get_item(EXPECTED_CONTENT_ID)
	if item.is_empty():
		failures.append("ItemRegistry 里没有 %s" % EXPECTED_CONTENT_ID)
		return
	if str(item.get("assembly_id", "")) != EXPECTED_ASSEMBLY_ID:
		failures.append(
			"%s 的 assembly_id 是 %s，期望 %s"
			% [EXPECTED_CONTENT_ID, str(item.get("assembly_id", "")), EXPECTED_ASSEMBLY_ID]
		)
	if str(item.get("name", "")) != EXPECTED_DISPLAY_NAME:
		failures.append("%s 的显示名是 %s" % [EXPECTED_CONTENT_ID, str(item.get("name", ""))])
	if int(item.get("price", -1)) != EXPECTED_PRICE:
		failures.append(
			"%s 的价格是 %d，期望 %d" % [EXPECTED_CONTENT_ID, int(item.get("price", -1)), EXPECTED_PRICE]
		)


func _check_assembly_contract(failures: Array[String]) -> void:
	var node := BlueprintRegistry.create_assembly_node(EXPECTED_ASSEMBLY_ID)
	if node == null:
		failures.append("BlueprintRegistry 无法为 %s 造出装配节点" % EXPECTED_ASSEMBLY_ID)
		return
	if node.node_name != EXPECTED_NODE_NAME:
		failures.append(
			"%s 造出节点 %s，期望 %s" % [EXPECTED_ASSEMBLY_ID, node.node_name, EXPECTED_NODE_NAME]
		)
	var back_mapped := BlueprintRegistry.get_item_id_for_assembly_node(node)
	if back_mapped != EXPECTED_CONTENT_ID:
		failures.append(
			"节点名 %s 反查内容 ID 得到 %s，期望 %s；装配树往返会丢身份"
			% [node.node_name, back_mapped, EXPECTED_CONTENT_ID]
		)
	var stats := node.get_base_stats()
	_check_int(stats, "damage", EXPECTED_DAMAGE, failures)
	_check_int(stats, "magazine_size", EXPECTED_MAGAZINE, failures)
	var rate := float(stats.get("fire_rate", -1.0))
	if not is_equal_approx(rate, EXPECTED_FIRE_RATE):
		failures.append(
			"%s 的 fire_rate 是 %.2f，期望 %.2f" % [EXPECTED_ASSEMBLY_ID, rate, EXPECTED_FIRE_RATE]
		)
	node.free()


func _check_int(stats: Dictionary, key: String, expected: int, failures: Array[String]) -> void:
	var actual := int(stats.get(key, -1))
	if actual != expected:
		failures.append(
			"%s 的 %s 是 %d，期望 %d" % [EXPECTED_ASSEMBLY_ID, key, actual, expected]
		)


## 出厂枪与蜂窝机枪共用一套配件槽位 —— 少一个槽位等于悄悄砍掉一条构筑路径。
func _check_attachment_slots(failures: Array[String]) -> void:
	var sprinkler: Array = BlueprintRegistry.ROOT_ATTACHMENT_SUPPORT.get(EXPECTED_NODE_NAME, [])
	if sprinkler.is_empty():
		failures.append("ROOT_ATTACHMENT_SUPPORT 里没有 %s" % EXPECTED_NODE_NAME)
		return
	var machinegun: Array = BlueprintRegistry.ROOT_ATTACHMENT_SUPPORT.get("GunBody_Machinegun", [])
	if sprinkler.size() != machinegun.size():
		failures.append(
			"%s 开放 %d 个槽位，蜂窝机枪开放 %d 个：%s vs %s"
			% [EXPECTED_NODE_NAME, sprinkler.size(), machinegun.size(), str(sprinkler), str(machinegun)]
		)
		return
	for slot in machinegun:
		if slot not in sprinkler:
			failures.append("%s 缺少蜂窝机枪开放的槽位 %s" % [EXPECTED_NODE_NAME, str(slot)])


## 命运槽容量必须能从物品定义一路走到实例，并且熬过存档往返。
func _check_fate_slot_capacity(failures: Array[String]) -> void:
	var item := ItemRegistry.get_instance().get_item(EXPECTED_CONTENT_ID)
	if item.is_empty():
		return
	var instance := WeaponInstance.from_item(item)
	if instance == null:
		failures.append("WeaponInstance 拒绝了 %s" % EXPECTED_CONTENT_ID)
		return
	if instance.fate_slot_capacity != EXPECTED_FATE_SLOTS:
		failures.append(
			"%s 的命运槽容量是 %d，期望 %d；白送枪不应该有终局级别的成长空间"
			% [EXPECTED_CONTENT_ID, instance.fate_slot_capacity, EXPECTED_FATE_SLOTS]
		)
	var round_trip := WeaponInstance.from_item(instance.to_item_dictionary())
	if round_trip == null:
		failures.append("%s 存档往返失败" % EXPECTED_CONTENT_ID)
	elif round_trip.fate_slot_capacity != EXPECTED_FATE_SLOTS:
		failures.append(
			"%s 存档往返后命运槽容量变成 %d，期望 %d"
			% [EXPECTED_CONTENT_ID, round_trip.fate_slot_capacity, EXPECTED_FATE_SLOTS]
		)


## 真正的「替换豌豆手枪」判据：出厂装配树的根就是新枪。
func _check_starting_tree(failures: Array[String]) -> void:
	var tree := BlueprintRegistry.get_starting_weapon_tree()
	if tree == null or tree.get_root() == null:
		failures.append("get_starting_weapon_tree() 没有造出出厂装配树")
		return
	var root := tree.get_root()
	if root.node_name != EXPECTED_NODE_NAME:
		failures.append(
			"出厂装配树的根是 %s，期望 %s：豌豆手枪没有被替换掉"
			% [root.node_name, EXPECTED_NODE_NAME]
		)
	tree.free()


func _check_machinegun_regression(failures: Array[String]) -> void:
	var node := BlueprintRegistry.create_assembly_node(MACHINEGUN_ASSEMBLY_ID)
	if node == null:
		failures.append("%s 丢失：出厂枪不该顶掉蜂窝机枪" % MACHINEGUN_ASSEMBLY_ID)
		return
	var stats := node.get_base_stats()
	if int(stats.get("damage", -1)) != MACHINEGUN_DAMAGE:
		failures.append(
			"%s 的伤害被改成 %d，期望 %d"
			% [MACHINEGUN_ASSEMBLY_ID, int(stats.get("damage", -1)), MACHINEGUN_DAMAGE]
		)
	if int(stats.get("magazine_size", -1)) != MACHINEGUN_MAGAZINE:
		failures.append(
			"%s 的弹匣被改成 %d，期望 %d"
			% [MACHINEGUN_ASSEMBLY_ID, int(stats.get("magazine_size", -1)), MACHINEGUN_MAGAZINE]
		)
	node.free()


func _report(failures: Array[String]) -> void:
	var output := failures.duplicate()
	if not _probe_completed:
		output.append("验收流程中途中断（脚本错误或提前返回），结果不可信")
	if output.is_empty():
		print(
			"STARTING_WEAPON_CONTRACT_OK: 出厂枪 %s（%s / %s）身份三方一致，%d 发弹匣 / %d 伤害 / 命运槽 %d，出厂装配树根节点已不再是豌豆手枪"
			% [
				EXPECTED_DISPLAY_NAME, EXPECTED_CONTENT_ID, EXPECTED_ASSEMBLY_ID,
				EXPECTED_MAGAZINE, EXPECTED_DAMAGE, EXPECTED_FATE_SLOTS,
			]
		)
		get_tree().quit(0)
		return
	for failure in output:
		push_error(failure)
	get_tree().quit(1)
