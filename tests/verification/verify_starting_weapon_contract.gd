extends Node

## 出厂枪契约门禁。
##
## 「新档出生 / 死亡返城白送哪把枪」由 `BlueprintRegistry.DEFAULT_STARTING_GUN_ID`
## 这一个常量决定，但同一个武器的身份、数值与命运槽容量分散写在三个文件里：
##   `ItemRegistry._register_weapon_drops()`      —— 内容 ID / 装配 ID / 价格 / 命运槽容量
##   `BlueprintRegistry._build_registry()`        —— 装配节点名 / 工厂 / base_stats
##   `BlueprintRegistry.ASSEMBLY_NODE_ITEM_IDS`   —— 节点名 -> 内容 ID 反查
## 任何一处漏改都不会报错，只会静默地少一把枪、少一个槽位、或者把默认枪偷偷换回去。
## 本场景把这三处钉在一起，并为原型枪（步枪）、历任出厂枪（初始步枪 / 花洒机枪）
## 各留一条「没被顺手改坏」的回归哨兵。
##
## ⚠️ 新档首局的**地面初始枪**不由本契约覆盖 —— 它是剧本
## `nar_tower_opening_01_wake` 的 `scene.spawn_item`（`item_id` 必须与本文件的
## EXPECTED_CONTENT_ID 同值），由 `verify_opening_script_runtime` / `verify_new_save_handoff` 盯着。
##
## `_probe_completed` 是防假绿哨兵：脚本中途出错会静默中断本函数并留下空失败表。

## 2026-10-30 业主：「初始武器从步枪改成豌豆手枪」。前一任 `bp_starter_rifle` 转入
## `_check_retired_factory_guns()` 的回归哨兵（仍是正式内容，只是不再白送）。
const EXPECTED_CONTENT_ID := "weapon_pistol"
const EXPECTED_ASSEMBLY_ID := "bp_pistol"
const EXPECTED_NODE_NAME := "GunBody_Pistol"
const EXPECTED_DISPLAY_NAME := "豌豆手枪"
const EXPECTED_PRICE := 70
## ⚠ 豌豆手枪**没有**像前任出厂枪那样把命运槽砍到 4：它同时是合成目录里的正式枪
## （`SYN-PISTOL`）与掉落池内容，用同一个 item id，砍槽会连带改掉它在掉落/合成里的价值。
## 业主这轮只点了「换枪 / 弹速 / 模型大小」，故沿用默认容量 8 —— 要收回成 4 需先拆
## 「白送实例」与「掉落实例」两套口径，属单独一项设计决定。
const EXPECTED_FATE_SLOTS := 8
const EXPECTED_DAMAGE := 25
const EXPECTED_FIRE_RATE := 3.5
const EXPECTED_MAGAZINE := 10
## 出厂树挂的子弹必须是标准弹。
##
## ⚠️ 2026-10-17 修的真 bug：`build_default_weapon_tree()` 旧实现「挑第一个不是标准弹的子弹」，
## tier0 可用列表 [standard, sticky, bounce] ⇒ 出厂初始步枪一直挂 `Bullet_Sticky`，
## 命中后走 `apply_damage_over_time(max(2, damage/3), 2.4)`，56 弹伤 ⇒ 18 DOT ⇒ 每 0.5s 掉 4 点。
## 玩家看到的是「打中怪物还在持续掉 4 点血」，实际是白送的特殊弹。这条断言就是防它复发。
const EXPECTED_STARTING_BULLET := "Bullet_Standard"

## 步枪（原型枪）本体不得被顺手改坏 —— 出厂枪从原型枪*移开*之后，它更没人盯着了。
const RIFLE_ASSEMBLY_ID := "bp_rifle"
const RIFLE_DAMAGE := 60
const RIFLE_MAGAZINE := 30

## 前一任出厂枪 = 初始步枪。换枪只能「换指针」，不得把它删掉或改数值。
const RETIRED_STARTER_ASSEMBLY_ID := "bp_starter_rifle"
const RETIRED_STARTER_DAMAGE := 50
const RETIRED_STARTER_MAGAZINE := 30

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

## 豌豆手枪的弹匣与弹速（2026-10-30 业主指令：对齐《挺进地牢》陆战队员的军用佩枪
## `Marine Sidearm`，Magazine 10 / Shot Speed 25）。
##
## 弹速在数据里是**倍率**（1.0 = 23 m/s，23 就是原作的 Shot Speed 23），所以这里
## 同时钉三样：① 枪身声明的倍率；② 乘出来的 m/s；③ 挂上标准弹之后**仍然是** 25 m/s
## —— 第三层是防回归的关键：`_combine_stats` 旧实现里子弹节点会**覆盖**枪身的
## `bullet_speed`，那时枪身写多少都会被标准弹的 1.0 冲掉，而数值检查和效果看起来都"正常"。
## ⚠ 2026-10-30 晚第二轮：上一轮把 `Marine Sidearm` 的 Shot Speed 25 **直接当 m/s** 写进
## `bullet_speed = 25/23`，业主上手仍说「偏快」——因为原作单位不是米：
## 原作玩家 6.5 单位/秒、本作玩家 4.5 m/s ⇒ **1 原作单位 = 4.5/6.5 ≈ 0.6923 m**。
## 弹速目标因此是 `25 × 0.6923 = 17.31 m/s`，倍率 = `17.31 / 23 ≈ 0.7525`。
## 本文件同时钉三层：① 枪身声明的倍率；② 乘出来的 m/s；③ 挂标准弹后仍是这个数
## （第三层防的是 `_combine_stats` 里子弹节点覆盖枪身倍率那条老坑）。
const PISTOL_ASSEMBLY_ID := "bp_pistol"
const PISTOL_MAGAZINE := 10
const BULLET_SPEED_BASE_MPS := 23.0
const EGT_UNIT_TO_METER := 4.5 / 6.5
const EGT_MARINE_SHOT_SPEED := 25.0
const PISTOL_BULLET_SPEED_MPS := EGT_MARINE_SHOT_SPEED * EGT_UNIT_TO_METER
const PISTOL_BULLET_SPEED_MULTIPLIER := PISTOL_BULLET_SPEED_MPS / BULLET_SPEED_BASE_MPS

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
	_check_pistol_egt_baseline(failures)
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


## 出厂枪的配件槽位（2026-10-30 起是手枪）。
##
## 旧版拿「初始步枪 vs 步枪」比，因为出厂枪是以步枪为原型做的；换枪之后这个比较失去意义
## （手枪本来就不该有 stock / tactical）。现在钉三件事：
##   ① 手枪必须开放它该有的 4 个槽（scope / muzzle / magazine / mutator）；
##   ② 它开放的槽必须是统一槽位框架里的合法名（步枪那套的超集校验 ⇒ 不许凭空造槽名）；
##   ③ 步枪（原型枪）自己的 6 个槽不得被顺手改坏。
func _check_attachment_slots(failures: Array[String]) -> void:
	var starter: Array = BlueprintRegistry.ROOT_ATTACHMENT_SUPPORT.get(EXPECTED_NODE_NAME, [])
	if starter.is_empty():
		failures.append("ROOT_ATTACHMENT_SUPPORT 里没有 %s" % EXPECTED_NODE_NAME)
		return
	for required in ["scope", "muzzle", "magazine", "mutator"]:
		if required not in starter:
			failures.append(
				"%s 缺少手枪应开放的槽位 %s（实得 %s）"
				% [EXPECTED_NODE_NAME, required, str(starter)]
			)
	var rifle: Array = BlueprintRegistry.ROOT_ATTACHMENT_SUPPORT.get("GunBody_Rifle", [])
	if rifle.size() != 6:
		failures.append("GunBody_Rifle 开放 %d 个槽位，期望 6：原型枪槽位表被改了" % rifle.size())
	for slot in starter:
		if slot not in rifle:
			failures.append(
				"%s 开放了非法槽位 %s（不在统一槽位框架里）" % [EXPECTED_NODE_NAME, str(slot)]
			)


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
			"出厂装配树的根是 %s，期望 %s：出厂枪又被悄悄换回去了"
			% [root.node_name, EXPECTED_NODE_NAME]
		)
	# 出厂枪只给枪、不给特殊弹：挂错弹会让「初始步枪」自带 DOT / 减速，玩家会当成 bug 报。
	var bullet := root.slots.get(AssemblyNode.SlotType.BULLET) as AssemblyNode
	if bullet == null:
		failures.append("出厂装配树没有挂子弹模块：出厂枪开不了火")
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


## 换出厂枪只能「换指针」，不得把原型枪或历任前任出厂枪顺手改坏。
## 2026-10-30 起历任出厂枪 = 初始步枪（上一任）+ 花洒机枪（再上一任）。
func _check_retired_factory_guns(failures: Array[String]) -> void:
	_check_gun_intact(RIFLE_ASSEMBLY_ID, RIFLE_DAMAGE, RIFLE_MAGAZINE, failures)
	_check_gun_intact(SPRINKLER_ASSEMBLY_ID, SPRINKLER_DAMAGE, SPRINKLER_MAGAZINE, failures)
	_check_gun_intact(
		RETIRED_STARTER_ASSEMBLY_ID, RETIRED_STARTER_DAMAGE, RETIRED_STARTER_MAGAZINE, failures
	)


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


## ③ 豌豆手枪的弹匣与弹速：数据层、装配树层、武器模型层三处都要是 10 发 / 25 m/s。
## 只核数据层会漏掉「枪身倍率被子弹节点覆盖」这种静默失效。
func _check_pistol_egt_baseline(failures: Array[String]) -> void:
	var node := BlueprintRegistry.create_assembly_node(PISTOL_ASSEMBLY_ID)
	if node == null:
		failures.append("豌豆手枪 %s 造不出装配节点" % PISTOL_ASSEMBLY_ID)
		return
	var stats := node.get_base_stats()
	if int(stats.get("magazine_size", -1)) != PISTOL_MAGAZINE:
		failures.append(
			"豌豆手枪的弹匣是 %d，期望 %d（对标《挺进地牢》军用佩枪 Magazine 10）"
			% [int(stats.get("magazine_size", -1)), PISTOL_MAGAZINE]
		)
	var multiplier := float(stats.get("bullet_speed", 1.0))
	if not is_equal_approx(multiplier, PISTOL_BULLET_SPEED_MULTIPLIER):
		failures.append(
			"豌豆手枪的枪身弹速倍率是 %.4f，期望 %.4f（= 25/23）"
			% [multiplier, PISTOL_BULLET_SPEED_MULTIPLIER]
		)
	node.free()
	# 装配树层：挂标准弹后枪身倍率必须还在（子弹节点只能乘，不能覆盖）。
	var tree := BlueprintRegistry.build_weapon_tree(PISTOL_ASSEMBLY_ID, "mod_bullet_standard")
	var combined_speed := BULLET_SPEED_BASE_MPS * float(
		tree.get_computed_stats().get("bullet_speed", 1.0)
	)
	if absf(combined_speed - PISTOL_BULLET_SPEED_MPS) > 0.05:
		failures.append(
			"豌豆手枪挂标准弹后的弹速是 %.2f m/s，期望 %.1f m/s（枪身弹速倍率被子弹节点覆盖了）"
			% [combined_speed, PISTOL_BULLET_SPEED_MPS]
		)
	# 树与节点都不是 `add_child` 进来的，得逐个释放，否则整轮退出时留 ObjectDB 泄漏。
	var tree_root := tree.get_root()
	if tree_root != null:
		for child in tree_root.get_all_descendants():
			child.free()
		tree_root.free()
	tree.free()
	# 武器模型层：真正用于开火的字段。
	var model := WeaponModel3D.new()
	add_child(model)
	if not model.configure(PISTOL_ASSEMBLY_ID, "mod_bullet_standard"):
		failures.append("豌豆手枪无法配置正式武器模型，弹速接线未验证")
	else:
		if absf(model.bullet_speed - PISTOL_BULLET_SPEED_MPS) > 0.05:
			failures.append(
				"豌豆手枪的 WeaponModel3D.bullet_speed 是 %.2f m/s，期望 %.1f m/s"
				% [model.bullet_speed, PISTOL_BULLET_SPEED_MPS]
			)
		if model.magazine_size != PISTOL_MAGAZINE:
			failures.append(
				"豌豆手枪的 WeaponModel3D.magazine_size 是 %d，期望 %d"
				% [model.magazine_size, PISTOL_MAGAZINE]
			)
	remove_child(model)
	model.free()


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
