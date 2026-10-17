extends Node

## 出厂枪契约门禁。
##
## 「新档出生 / 死亡返城白送哪把枪」由 `BlueprintRegistry.DEFAULT_STARTING_GUN_ID`
## 这一个常量决定，但同一个武器的身份、数值与命运槽容量分散写在三个文件里：
##   `ItemRegistry._register_weapon_drops()`      —— 内容 ID / 装配 ID / 价格 / 命运槽容量
##   `BlueprintRegistry._build_registry()`        —— 装配节点名 / 工厂 / base_stats
##   `BlueprintRegistry.ASSEMBLY_NODE_ITEM_IDS`   —— 节点名 -> 内容 ID 反查
## 任何一处漏改都不会报错，只会静默地少一把枪、少一个槽位、或者把默认枪偷偷换回去。
## 本场景把这三处钉在一起，并为原型枪（步枪）、原出厂枪（花洒机枪）各留一条
## 「没被顺手改坏」的回归哨兵。
##
## ⚠️ 新档首局的**地面初始枪**不由本契约覆盖 —— 它是剧本
## `nar_tower_opening_01_wake` 的 `scene.spawn_item`（`item_id` 必须与本文件的
## EXPECTED_CONTENT_ID 同值），由 `verify_opening_script_runtime` / `verify_new_save_handoff` 盯着。
##
## `_probe_completed` 是防假绿哨兵：脚本中途出错会静默中断本函数并留下空失败表。

const EXPECTED_CONTENT_ID := "weapon_starter_rifle"
const EXPECTED_ASSEMBLY_ID := "bp_starter_rifle"
const EXPECTED_NODE_NAME := "GunBody_StarterRifle"
const EXPECTED_DISPLAY_NAME := "初始步枪"
const EXPECTED_PRICE := 120
const EXPECTED_FATE_SLOTS := 4
const EXPECTED_DAMAGE := 50
const EXPECTED_FIRE_RATE := 5.0
const EXPECTED_MAGAZINE := 30
## 出厂树挂的子弹必须是标准弹。
##
## ⚠️ 2026-10-17 修的真 bug：`build_default_weapon_tree()` 旧实现「挑第一个不是标准弹的子弹」，
## tier0 可用列表 [standard, sticky, bounce] ⇒ 出厂初始步枪一直挂 `Bullet_Sticky`，
## 命中后走 `apply_damage_over_time(max(2, damage/3), 2.4)`，56 弹伤 ⇒ 18 DOT ⇒ 每 0.5s 掉 4 点。
## 玩家看到的是「打中怪物还在持续掉 4 点血」，实际是白送的特殊弹。这条断言就是防它复发。
const EXPECTED_STARTING_BULLET := "Bullet_Standard"

## 初始步枪以步枪为原型：配件槽位与步枪同套；步枪本体不得被顺手改坏。
const RIFLE_ASSEMBLY_ID := "bp_rifle"
const RIFLE_DAMAGE := 60
const RIFLE_MAGAZINE := 30

## 蜂窝机枪：既有内容，出厂枪不该顶掉它。
const MACHINEGUN_ASSEMBLY_ID := "bp_machinegun"
const MACHINEGUN_DAMAGE := 15
const MACHINEGUN_MAGAZINE := 60

## 花洒机枪是**前一任**出厂枪，仍是正式内容；换出厂枪不得把它删掉或改数值。
const SPRINKLER_ASSEMBLY_ID := "bp_sprinkler"
const SPRINKLER_DAMAGE := 12
const SPRINKLER_MAGAZINE := 100

## 逐枪射程（米）。业主 2026-10-14 定值；`range` 与 `bullet_speed` 已解耦，
## 弹速只决定飞行时间，射程决定弹体最远飞多远（爆炸弹到点自动引爆）。
## 这里同时钉两层：① 数值本身；② 每把远程枪身都必须声明（漏声明会退回旧口径飞过头）。
const EXPECTED_RANGES := {
	"bp_pistol": 15.0,
	"bp_shotgun": 7.0,
	"bp_rifle": 20.0,
	"bp_launcher": 18.0,
	"bp_starter_rifle": 20.0,
}

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
	_check_retired_factory_guns(failures)
	_check_weapon_ranges(failures)
	_check_range_plumbing(failures)
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


## 初始步枪与步枪共用一套配件槽位 —— 少一个槽位等于悄悄砍掉一条构筑路径。
func _check_attachment_slots(failures: Array[String]) -> void:
	var starter: Array = BlueprintRegistry.ROOT_ATTACHMENT_SUPPORT.get(EXPECTED_NODE_NAME, [])
	if starter.is_empty():
		failures.append("ROOT_ATTACHMENT_SUPPORT 里没有 %s" % EXPECTED_NODE_NAME)
		return
	var rifle: Array = BlueprintRegistry.ROOT_ATTACHMENT_SUPPORT.get("GunBody_Rifle", [])
	if starter.size() != rifle.size():
		failures.append(
			"%s 开放 %d 个槽位，步枪开放 %d 个：%s vs %s"
			% [EXPECTED_NODE_NAME, starter.size(), rifle.size(), str(starter), str(rifle)]
		)
		return
	for slot in rifle:
		if slot not in starter:
			failures.append("%s 缺少步枪开放的槽位 %s" % [EXPECTED_NODE_NAME, str(slot)])


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
	# 出厂枪只给枪、不给特殊弹：挂错弹会让「初始步枪」自带 DOT / 减速，玩家会当成 bug 报。
	var bullet := root.slots.get(AssemblyNode.SlotType.BULLET) as AssemblyNode
	if bullet == null:
		failures.append("出厂装配树没有挂子弹模块：初始步枪开不了火")
	elif bullet.node_name != EXPECTED_STARTING_BULLET:
		failures.append(
			"出厂装配树挂的子弹是 %s，期望 %s；特殊弹必须由玩家手动装配"
			% [bullet.node_name, EXPECTED_STARTING_BULLET]
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


## 换出厂枪只能「加一把新枪」，不得把原型枪或前任出厂枪顺手改坏。
func _check_retired_factory_guns(failures: Array[String]) -> void:
	_check_gun_intact(RIFLE_ASSEMBLY_ID, RIFLE_DAMAGE, RIFLE_MAGAZINE, failures)
	_check_gun_intact(SPRINKLER_ASSEMBLY_ID, SPRINKLER_DAMAGE, SPRINKLER_MAGAZINE, failures)


func _check_gun_intact(
	assembly_id: String, damage: int, magazine: int, failures: Array[String]
) -> void:
	var node := BlueprintRegistry.create_assembly_node(assembly_id)
	if node == null:
		failures.append("%s 丢失：换出厂枪不该删掉既有枪身" % assembly_id)
		return
	var stats := node.get_base_stats()
	if int(stats.get("damage", -1)) != damage:
		failures.append(
			"%s 的伤害被改成 %d，期望 %d" % [assembly_id, int(stats.get("damage", -1)), damage]
		)
	if int(stats.get("magazine_size", -1)) != magazine:
		failures.append(
			"%s 的弹匣被改成 %d，期望 %d"
			% [assembly_id, int(stats.get("magazine_size", -1)), magazine]
		)
	node.free()


## ① 数据层：每把远程枪身都必须声明 `range > 0`，且业主定值的枪逐把核对。
## 漏声明不会报错，只会让该枪的弹体退回「按存活时间」的旧口径（23 m/s ≈ 23 m）飞过头。
func _check_weapon_ranges(failures: Array[String]) -> void:
	for entry in BlueprintRegistry.get_available_gunbodies(99):
		var item_id := str(entry.get("item_id", ""))
		var tags: Array = entry.get("tags", [])
		if "melee" in tags:
			continue
		var node := BlueprintRegistry.create_assembly_node(item_id)
		if node == null:
			failures.append("%s 造不出装配节点，无法核对射程" % item_id)
			continue
		if float(node.get_base_stats().get("range", 0.0)) <= 0.0:
			failures.append(
				"%s 未声明射程 range：弹体会退回按存活时间的旧口径飞过头" % item_id
			)
		node.free()
	for item_id in EXPECTED_RANGES:
		var node := BlueprintRegistry.create_assembly_node(str(item_id))
		if node == null:
			failures.append("射程契约目标 %s 不存在" % item_id)
			continue
		var actual := float(node.get_base_stats().get("range", -1.0))
		var wanted := float(EXPECTED_RANGES[item_id])
		if not is_equal_approx(actual, wanted):
			failures.append("%s 的射程是 %.1f m，期望 %.1f m" % [item_id, actual, wanted])
		node.free()


## ② 接线层：枪身数值 → WeaponModel3D → Projectile3D 的 spawn 配置，三段都要真的带到。
## 只核数值不核接线的话，`range` 写进 base_stats 但没人读，测试照样全绿。
func _check_range_plumbing(failures: Array[String]) -> void:
	var model := WeaponModel3D.new()
	add_child(model)
	for item_id in EXPECTED_RANGES:
		if not model.configure(str(item_id), "mod_bullet_standard"):
			failures.append("%s 无法配置正式武器模型，射程接线未验证" % item_id)
			continue
		var wanted := float(EXPECTED_RANGES[item_id])
		if not is_equal_approx(model.range_m, wanted):
			failures.append(
				"%s 的 WeaponModel3D.range_m 是 %.1f，期望 %.1f（枪身射程没接到发射参数）"
				% [item_id, model.range_m, wanted]
			)
	model.queue_free()
	# Projectile3D 必须能从 spawn 配置里读出射程；读不出则射程上限形同虚设。
	var projectile := Projectile3D.new()
	add_child(projectile)
	projectile.configure({"range": 7.0, "speed": 23.0, "damage": 1})
	if not is_equal_approx(projectile.range_m, 7.0):
		failures.append(
			"Projectile3D 未从配置读取 range（实得 %.1f，期望 7.0）" % projectile.range_m
		)
	projectile.configure({"speed": 23.0, "damage": 1})
	if not is_equal_approx(projectile.range_m, 0.0):
		failures.append(
			"缺省 range 应为 0（不启用距离上限），实得 %.1f" % projectile.range_m
		)
	projectile.queue_free()


func _report(failures: Array[String]) -> void:
	var output := failures.duplicate()
	if not _probe_completed:
		output.append("验收流程中途中断（脚本错误或提前返回），结果不可信")
	if output.is_empty():
		print(
			"STARTING_WEAPON_CONTRACT_OK: 出厂枪 %s（%s / %s）身份三方一致，%d 发弹匣 / %d 伤害 / 命运槽 %d，出厂装配树根节点为 %s；逐枪射程与发射接线 %d 项核过"
			% [
				EXPECTED_DISPLAY_NAME, EXPECTED_CONTENT_ID, EXPECTED_ASSEMBLY_ID,
				EXPECTED_MAGAZINE, EXPECTED_DAMAGE, EXPECTED_FATE_SLOTS, EXPECTED_NODE_NAME,
				EXPECTED_RANGES.size(),
			]
		)
		get_tree().quit(0)
		return
	for failure in output:
		push_error(failure)
	get_tree().quit(1)
