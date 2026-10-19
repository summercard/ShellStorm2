class_name TrainingRange3D
extends Node3D
## 3D 测试靶场：只读 BlueprintRegistry 取出全部枪身与弹药，在军械库里自由取用
## （不限次数、不消耗）、在刷怪台上打实战、在命运卡组装台上把任意卡装到当前武器。
##
## 隔离契约（本场景存在的全部意义）：**只改运行时内存，从不写 BaseManager**。
## 进入时 player.clear_all_equipped_weapons() 清空全部武器槽，场内配的枪/弹/命运卡、
## 捡到的物资、刷出的敌人，全都只活在本场景里；离场随场景释放，基地存档因此原样不变
## —— 出来就回到进去前的状态与物品。这条契约由
## tests/verification/verify_training_range_isolation.gd 的快照对比与
## verify_training_range_3d_flow.gd 的 is_base_data_unchanged() 盯着，不靠注释。
##
## 测试用物资规则（刻意的简化，不是正式经济）：击杀敌人与开启补给箱会把物品放进
## 本场背包。正式掉落走 Dungeon3D 的奖励协调器与房间奖励计划，靶场不接入它 ——
## 这里只需要让"有背包"这件事成立，好让依赖背包/宝箱的命运卡能看到落点。

const SERVICE_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_service_station_root_top3d.tscn")

## 军械库阵列：枪身一排、弹药一排，货架正面统一朝北（场地中心方向）。
const ARMORY_BAY_PITCH := 2.5
const ARMORY_ROW_X0 := -13.0
const GUN_ROW_Z := 13.5
const BULLET_ROW_Z := 17.0
const ARMORY_FACING_YAW := PI
## 刷怪台：三个台子点名三种怪，盖住近战/远程/肉盾三类行为。
const SPAWN_PAD_DEFINITIONS := [
	{"type": "melee_chaser", "count": 3, "position": Vector3(18.0, 0.0, -14.0)},
	{"type": "ranged_caster", "count": 2, "position": Vector3(18.0, 0.0, -4.0)},
	{"type": "fat_zombie03", "count": 2, "position": Vector3(18.0, 0.0, 6.0)},
]
const RESET_STATION_NAME := "重置靶标与弹药"
const FATE_BENCH_NAME := "命运卡组装台"
const SUPPLY_CRATE_NAME := "补给箱"
## 装备界面（武器装配树）：外面的快捷键是 Tab，靶场沿用同一套。
const WEAPON_PANEL_SCENE: PackedScene = preload("res://scenes/WeaponAssemblyTreePanel.tscn")
## 地面掉落物脚本：背包里"丢到世界"复用外面同一条链路。
const GROUND_LOOT_SCRIPT := preload("res://src/world3d/GroundLootPickup3D.gd")
## 本场背包容量：**与外面局内一致**（Dungeon3D.BASE_INVENTORY_CAPACITY = 40）。
## 测试环境的意义就在于手感和布局与实战相同，容量不一致会让背包排版失真。
const TEST_BACKPACK_CAPACITY := 40
const TEST_INSURANCE_CAPACITY := 16
const TEST_SUPPLY_ITEM_ID := "item_health_potion"
const TEST_QUALITY_ITEM_ID := "item_battery_l"
## 补给箱每次开箱发放的物资：让背包界面一开就有内容可看、可拖。
const TEST_SUPPLY_BATCH := [
	{"item_id": "item_health_potion", "count": 3},
	{"item_id": "item_battery_l", "count": 2},
]

## 进入靶场时的来源场景路径，由入口在切场景前登记，退出时原路返回。
## 必须是 static：它要跨场景切换存活，而切场景后登记它的旧节点已被释放。
static var _origin_scene_path := ""

@export var test_mode := false

@onready var player: Player3D = $Player3D
@onready var environment_kit: TrainingRangeEnvironment3D = $EnvironmentKit
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var key_light: DirectionalLight3D = $DirectionalLight3D
@onready var loadout_label: Label = $HUD/TopBar/Margin/HBox/LoadoutLabel
@onready var ammo_label: Label = $HUD/TopBar/Margin/HBox/AmmoLabel
@onready var stats_label: Label = $HUD/TopBar/Margin/HBox/StatsLabel
@onready var bag_label: Label = $HUD/TopBar/Margin/HBox/BagLabel
@onready var status_label: Label = $HUD/StatusPanel/Margin/StatusLabel

var selected_gun_id := ""
var selected_bullet_id := ""
var total_hits := 0
var total_damage := 0
var targets_destroyed := 0
var kills := 0
var _rack_count := {"gunbody": 0, "bullet": 0}
var _weapon_kind_count := {"ranged": 0, "melee": 0}
var _targets: Array[TrainingTarget3D] = []
var _spawn_pads: Array[TrainingSpawnPad3D] = []
var _fate_panel: TrainingFateBenchPanel = null
var _base_snapshot: Dictionary = {}
## 本场背包：让依赖背包 / 宝箱的命运卡有落点。只在内存里，从不写存档。
var _inventory: InventoryModule = null
## 保险柜模块：靶场没有撤离流程，但背包界面里保留该区（标注不可用），
## 界面布局才与外面逐块一致。给一个空的实例，不接任何写档路径。
var _insurance: InsuranceModule = null
## 世界命运宿主：14 张 WORLD 卡全都要它，缺了会一律返回 world_owner_unavailable。
var _world_game_mode: TrainingWorldGameMode3D = null
## 完整背包界面（外面按 I）：直接复用外面同一套组件，不自建精简版。
var _inventory_ui: InventoryUI = null
## 完整装备界面（外面按 Tab）：武器装配树。
var _weapon_panel: WeaponAssemblyTreePanel = null


func _ready() -> void:
	if BaseManager != null:
		_base_snapshot = _get_training_owned_base_snapshot()
	_configure_environment()
	if RuntimePerformanceManager != null:
		RuntimePerformanceManager.register_atmosphere(self)
	_inventory = InventoryModule.new(TEST_BACKPACK_CAPACITY)
	_insurance = InsuranceModule.new(TEST_INSURANCE_CAPACITY)
	_build_world_game_mode()
	_build_racks()
	_build_targets()
	_build_spawn_pads()
	_build_services()
	player.set_combat_enabled(true)
	# 必须用 clear_all_equipped_weapons() 而不是 clear_weapon()：后者只清「手上这把枪的
	# 呈现」，武器槽 equipped_weapon_slots 与实例都还留着 —— 切个枪基地的装备就回来了。
	# 靶场要求的是**一件都不带入**。被收回的武器不还给玩家、也不写回存档：
	# 它们本就在基地存档里，场景切换后自然还原。
	player.clear_all_equipped_weapons()
	# 装备/背包界面必须在清空之后建：否则注入的是进场那一刻的旧武器树。
	_build_equipment_ui()
	player.ammo_changed.connect(_on_ammo_changed)
	# 换枪会整体替换 weapon_tree（每把枪有独立 runtime tree），两个面板必须跟着换，
	# 否则装备界面会一直显示上一把枪的构筑。
	player.weapon_instance_changed.connect(_on_weapon_instance_changed)
	if _inventory != null and not _inventory.inventory_changed.is_connected(_refresh_bag_label):
		_inventory.inventory_changed.connect(_refresh_bag_label)
	_on_ammo_changed(0, 0)
	_refresh_stats()
	_refresh_bag_label()
	status_label.text = "军械库任意取用枪身与弹药，刷怪台可测实战，命运卡组装台可测任意卡；所有配置仅在本场生效，离开即还原。"


func _configure_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.026, 0.028)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.34, 0.38, 0.38)
	environment.ambient_light_energy = 0.86
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.12
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.08, 0.10, 0.10)
	environment.fog_density = 0.008
	world_environment.environment = environment
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.register_environment(environment)


func apply_performance_quality(profile: String) -> void:
	if world_environment.environment != null:
		world_environment.environment.fog_enabled = (
			profile != "low"
			and (GraphicsSettingsManager == null or GraphicsSettingsManager.is_enabled("distance_fog"))
		)
	key_light.shadow_enabled = true
	key_light.directional_shadow_max_distance = 96.0 if profile == "high" else 64.0 if profile == "balanced" else 36.0


## 世界命运宿主必须早于刷怪台建：刷怪台生成时要向它取"下一波倍率"。
func _build_world_game_mode() -> void:
	_world_game_mode = TrainingWorldGameMode3D.new()
	_world_game_mode.name = "WorldGameMode"
	add_child(_world_game_mode)
	_world_game_mode.reinforcement_requested.connect(_on_reinforcement_requested)
	_world_game_mode.world_card_applied.connect(_on_world_card_applied)


## 军械库：全部枪身与全部弹药各占一个货架格，点一次即装到玩家身上。
## 取用不限次数 —— 这里没有库存，也没有任何消耗写入。
func _build_racks() -> void:
	var guns := BlueprintRegistry.get_available_gunbodies(99)
	var bullets := BlueprintRegistry.get_available_bullets(99)
	for index in range(guns.size()):
		var tags := guns[index].get("tags", []) as Array
		var kind := "melee" if "melee" in tags else "ranged"
		_weapon_kind_count[kind] = int(_weapon_kind_count[kind]) + 1
		_add_armory_bay(
			guns[index],
			"gunbody",
			Vector3(ARMORY_ROW_X0 + float(index) * ARMORY_BAY_PITCH, 0.0, GUN_ROW_Z)
		)
	for index in range(bullets.size()):
		_add_armory_bay(
			bullets[index],
			"bullet",
			Vector3(ARMORY_ROW_X0 + float(index) * ARMORY_BAY_PITCH, 0.0, BULLET_ROW_Z)
		)


func _add_armory_bay(entry: Dictionary, category: String, position: Vector3) -> void:
	var bay := TrainingArmoryBay3D.new()
	bay.configure(entry, category)
	bay.position = position
	bay.rotation.y = ARMORY_FACING_YAW
	$Racks.add_child(bay)
	bay.selected.connect(_on_rack_selected)
	_rack_count[category] = int(_rack_count[category]) + 1


func _build_targets() -> void:
	var definitions := [
		{"type": "standard", "position": Vector3(-8, 0, -18)},
		{"type": "armored", "position": Vector3(0, 0, -20)},
		{"type": "runner", "position": Vector3(8, 0, -18)},
	]
	for definition in definitions:
		var target := TrainingTarget3D.new()
		target.configure(definition["type"])
		target.position = definition["position"]
		$Targets.add_child(target)
		target.damaged.connect(_on_target_damaged)
		target.destroyed.connect(_on_target_destroyed)
		_targets.append(target)


func _build_spawn_pads() -> void:
	for definition in SPAWN_PAD_DEFINITIONS:
		var pad := TrainingSpawnPad3D.new()
		pad.configure(str(definition["type"]), int(definition["count"]))
		pad.position = definition["position"]
		pad.enemy_container = $Enemies
		pad.world_game_mode = _world_game_mode
		$SpawnPads.add_child(pad)
		pad.wave_spawned.connect(_on_wave_spawned)
		pad.enemy_killed.connect(_on_enemy_killed)
		_spawn_pads.append(pad)


func _build_services() -> void:
	var reset_station := SERVICE_SCENE.instantiate() as ServiceStation3D
	reset_station.configure("reset", RESET_STATION_NAME, Color(0.94, 0.55, 0.18))
	reset_station.position = Vector3(14.0, 0, 16.0)
	$Services.add_child(reset_station)
	reset_station.activated.connect(_on_reset_station)
	var fate_bench := SERVICE_SCENE.instantiate() as ServiceStation3D
	fate_bench.configure("event", FATE_BENCH_NAME, Color(0.72, 0.36, 0.86))
	fate_bench.position = Vector3(7.0, 0, 20.5)
	$Services.add_child(fate_bench)
	fate_bench.activated.connect(_on_fate_bench_activated)
	var crate := SERVICE_SCENE.instantiate() as ServiceStation3D
	crate.configure("event", SUPPLY_CRATE_NAME, Color(0.46, 0.80, 0.34))
	crate.position = Vector3(18.0, 0, 15.0)
	$Services.add_child(crate)
	crate.activated.connect(_on_supply_crate_activated)
	var exit := TrainingExit3D.new()
	exit.position = Vector3(21.0, 0, 21.0)
	$Services.add_child(exit)
	exit.exit_requested.connect(_on_exit_requested)


## 建完整的装备界面（Tab）与背包界面（I）—— **直接复用外面局内同一套组件**，
## 不自建精简版。测试环境的价值就在于布局、操作与实战逐块一致。
##
## 按键分区与外面相同：Tab = 武器装配树，I = 背包。因此背包的 accept_tab_shortcut
## 必须关掉，否则两个面板会抢同一个键。
func _build_equipment_ui() -> void:
	_inventory_ui = InventoryUI.new()
	_inventory_ui.name = "InventoryUI3D"
	_inventory_ui.standalone_mode = true
	_inventory_ui.accept_tab_shortcut = false
	_inventory_ui.shortcut_enabled = true
	$HUD.add_child(_inventory_ui)
	_inventory_ui.set_inventory_module(_inventory)
	_inventory_ui.set_insurance_module(_insurance)
	_inventory_ui.set_weapon_tree(player.get_weapon_tree())
	_inventory_ui.set_weapon_owner(player)
	# 背包栏直接用玩家当 owner：Player3D 自带 backpack_equipment_changed 信号与
	# get_equipped_backpack_item()，本场景不必再代理一层。
	_inventory_ui.set_backpack_owner(player)
	_inventory_ui.set_world_drop_handler(_discard_inventory_item)
	# 所有槽位事务都落到 Player3D 的公共 API 上，与本场景「只改运行时内存」的契约
	# 一致：这些 API 不写 BaseManager，离场随场景释放。
	_inventory_ui.weapon_slot_equip_requested.connect(_on_weapon_slot_equip_requested)
	_inventory_ui.equipped_weapon_to_inventory_requested.connect(_on_equipped_weapon_to_inventory_requested)
	_inventory_ui.equipped_weapon_drop_requested.connect(_on_equipped_weapon_drop_requested)
	_inventory_ui.attachment_slot_install_requested.connect(_on_attachment_slot_install_requested)
	_inventory_ui.attachment_slot_remove_requested.connect(_on_attachment_slot_remove_requested)
	_inventory_ui.attachment_slot_drop_requested.connect(_on_attachment_slot_drop_requested)
	_inventory_ui.bullet_module_install_requested.connect(_on_bullet_module_install_requested)
	_inventory_ui.backpack_slot_equip_requested.connect(_on_backpack_slot_equip_requested)
	_inventory_ui.equipped_backpack_to_inventory_requested.connect(_on_equipped_backpack_to_inventory_requested)
	_inventory_ui.equipped_backpack_drop_requested.connect(_on_equipped_backpack_drop_requested)
	_inventory_ui.inventory_open_changed.connect(_on_inventory_open_changed)
	_inventory_ui.inventory_changed.connect(_refresh_bag_label)
	_weapon_panel = WEAPON_PANEL_SCENE.instantiate() as WeaponAssemblyTreePanel
	if _weapon_panel == null:
		return
	_weapon_panel.name = "WeaponAssemblyTreePanel3D"
	$HUD.add_child(_weapon_panel)
	_weapon_panel.set_weapon_tree(player.get_weapon_tree())
	_weapon_panel.set_weapon_owner(player)


## 换枪会整体替换 weapon_tree（每把枪有独立 runtime tree）。两个面板必须跟着换，
## 否则装备界面会一直显示上一把枪的构筑 —— 在靶场里换枪是高频操作，很容易撞上。
func _on_weapon_instance_changed(_snapshot: Dictionary) -> void:
	var tree := player.get_weapon_tree()
	if _inventory_ui != null and is_instance_valid(_inventory_ui):
		_inventory_ui.set_weapon_tree(tree)
	if _weapon_panel != null and is_instance_valid(_weapon_panel):
		_weapon_panel.set_weapon_tree(tree)


func _on_inventory_open_changed(opened: bool) -> void:
	# 与外面同一条口径：背包打开时锁玩家输入（否则会边整理边移动/走火）。
	# 注意这里**不暂停世界**，与外面局内一致。
	player.set_input_locked(opened)
	if opened:
		# 必须延后：InventoryUI 在发出本信号之后还会调 _refresh_insurance_ui()，
		# 那里会把标签重置回「保险柜」，同步设置会被它覆盖。
		call_deferred("_mark_insurance_unavailable")
		status_label.text = "背包已打开 · 左键使用/装备；靶场无撤离流程，保险柜仅作展示"
	else:
		status_label.text = "背包已关闭 · 继续测试"


## 保险柜在靶场里没有对应流程（外面用来存撤离物资）。把界面标注清楚，
## 而不是让测试者点了没反应还不知道为什么。
func _mark_insurance_unavailable() -> void:
	if _inventory_ui == null or not is_instance_valid(_inventory_ui):
		return
	var label := _inventory_ui.get("insurance_label") as Label
	if label != null and not label.text.contains("不可用"):
		label.text = "保险柜（测试环境不可用）"


## 背包界面里「丢到世界」：在与外面同一条链路上生成地面掉落物，可以走回去捡回来。
## 靶场有真实地面，丢弃就该看得见、捡得回 —— 静默删除会让测试者以为东西凭空没了。
func _discard_inventory_item(item: Dictionary, count: int) -> bool:
	if item.is_empty() or count <= 0:
		return false
	var payload := item.duplicate(true)
	payload["count"] = maxi(1, count)
	var pickup := GROUND_LOOT_SCRIPT.new() as GroundLootPickup3D
	if pickup == null:
		return false
	pickup.configure(payload, ItemModelFactory3D.get_item_color(payload))
	$Drops.add_child(pickup)
	pickup.global_position = player.global_position + (-player.global_basis.z).normalized() * 1.4 + Vector3.UP * 0.2
	pickup.pickup_requested.connect(_on_ground_loot_requested)
	return true


func _on_ground_loot_requested(pickup: GroundLootPickup3D, item: Dictionary) -> void:
	if not is_instance_valid(pickup) or not pickup.is_pickup_available():
		return
	if player.global_position.distance_to(pickup.global_position) > pickup.get_pickup_distance_m():
		return
	var count := maxi(1, int(item.get("count", 1)))
	if _inventory.add_item(item, count) <= 0:
		status_label.text = "背包放不下 %s" % str(item.get("name", "物品"))
		return
	pickup.accept_pickup(player)
	status_label.text = "拾取 %s×%d · %s" % [str(item.get("name", "物品")), count, _bag_summary()]


func _on_weapon_slot_equip_requested(source_slot_index: int, weapon_slot_index: int) -> void:
	var slot := _inventory.get_slot(source_slot_index)
	if slot.is_empty():
		return
	var item := slot.get("item", {}) as Dictionary
	if str(item.get("type", "")) != "weapon":
		status_label.text = "只能把枪械放入主/副武器栏"
		return
	var result := player.equip_weapon_item_to_slot(item, weapon_slot_index)
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "装备失败"))
		return
	_inventory.remove_from_slot(source_slot_index, 1)
	status_label.text = "已装备 %s" % str(item.get("name", "枪械"))


func _on_equipped_weapon_to_inventory_requested(weapon_slot_index: int, target_slot_index: int) -> void:
	if not _inventory.get_slot(target_slot_index).is_empty():
		status_label.text = "卸装失败：目标背包格已有物品"
		return
	var result := player.unequip_weapon_item_from_slot(weapon_slot_index)
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "卸装失败"))
		return
	var old_item := result.get("old_item", {}) as Dictionary
	if not _inventory.put_item_in_empty_slot(target_slot_index, old_item, 1):
		player.equip_weapon_item_to_slot(old_item, weapon_slot_index)
		status_label.text = "卸装失败：背包写入失败，已恢复原武器"
		return
	status_label.text = "已卸下 %s（完整构筑进入背包）" % str(old_item.get("name", "武器"))


func _on_equipped_weapon_drop_requested(weapon_slot_index: int) -> void:
	var result := player.unequip_weapon_item_from_slot(weapon_slot_index)
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "卸装失败"))
		return
	var old_item := result.get("old_item", {}) as Dictionary
	if not _discard_inventory_item(old_item, 1):
		player.equip_weapon_item_to_slot(old_item, weapon_slot_index)
		status_label.text = "丢弃失败，已恢复原武器"
		return
	status_label.text = "已卸下并丢在地上 %s" % str(old_item.get("name", "武器"))


func _on_attachment_slot_install_requested(
	source_slot_index: int, weapon_slot_index: int, attachment_slot_type: int
) -> void:
	var slot := _inventory.get_slot(source_slot_index)
	if slot.is_empty():
		return
	var item := slot.get("item", {}) as Dictionary
	var result := player.install_attachment_item_to_weapon_slot(item, weapon_slot_index, attachment_slot_type)
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "配件安装失败"))
		return
	_inventory.remove_from_slot(source_slot_index, 1)
	status_label.text = "已安装 %s" % str(item.get("name", "配件"))


## 子弹模块拖到武器格 ⇒ 换那把枪的弹药槽。靶场不写存档，失败只回滚内存状态。
##
## 2026-10-19：手动更换总闸关闭 —— 连靶场也不提供这条路径。靶场要试不同弹种走
## **军械库组合**（`equip_combination_for_test`，整把枪重新装配、不调用本事务）。
func _on_bullet_module_install_requested(source_slot_index: int, weapon_slot_index: int) -> void:
	if not WeaponBulletDrop.is_manual_swap_enabled():
		status_label.text = WeaponBulletDrop.manual_swap_block_reason()
		return
	var slot := _inventory.get_slot(source_slot_index)
	if slot.is_empty():
		return
	var item := slot.get("item", {}) as Dictionary
	var result := player.install_bullet_module_to_weapon_slot(item, weapon_slot_index)
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "子弹模块安装失败"))
		return
	if not _inventory.remove_from_slot(source_slot_index, 1):
		# 背包扣除失败 ⇒ 把新弹退回，避免「枪上装了、包里还留着」。
		var rollback := result.get("removed_item", {}) as Dictionary
		if not rollback.is_empty():
			player.install_bullet_module_to_weapon_slot(rollback, weapon_slot_index)
		status_label.text = "子弹模块安装失败：背包扣除失败"
		return
	var removed := result.get("removed_item", {}) as Dictionary
	if not removed.is_empty() and _inventory.add_item(removed, 1) <= 0:
		player.install_bullet_module_to_weapon_slot(removed, weapon_slot_index)
		_inventory.add_item(item, 1)
		status_label.text = "弹药槽更换失败 · 背包没有空间容纳换下的模块"
		return
	status_label.text = "已把%s装到%s" % [
		item.get("name", "子弹模块"), "主武器" if weapon_slot_index == 0 else "副武器",
	]


func _on_attachment_slot_remove_requested(
	weapon_slot_index: int, attachment_slot_type: int, target_slot_index: int
) -> void:
	if not _inventory.get_slot(target_slot_index).is_empty():
		status_label.text = "拆卸失败：目标背包格已有物品"
		return
	var result := player.remove_attachment_from_weapon_slot(weapon_slot_index, attachment_slot_type)
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "配件拆卸失败"))
		return
	var removed := result.get("removed_item", {}) as Dictionary
	if not _inventory.put_item_in_empty_slot(target_slot_index, removed, 1):
		player.install_attachment_item_to_weapon_slot(removed, weapon_slot_index, attachment_slot_type)
		status_label.text = "拆卸失败：背包写入失败，已装回原枪"
		return
	status_label.text = "已拆下 %s" % str(removed.get("name", "配件"))


func _on_attachment_slot_drop_requested(weapon_slot_index: int, attachment_slot_type: int) -> void:
	var result := player.remove_attachment_from_weapon_slot(weapon_slot_index, attachment_slot_type)
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "配件拆卸失败"))
		return
	var removed := result.get("removed_item", {}) as Dictionary
	if not _discard_inventory_item(removed, 1):
		player.install_attachment_item_to_weapon_slot(removed, weapon_slot_index, attachment_slot_type)
		status_label.text = "丢弃失败，配件已装回原枪"
		return
	status_label.text = "已拆下并丢在地上 %s" % str(removed.get("name", "配件"))


func _on_backpack_slot_equip_requested(source_slot_index: int) -> void:
	var slot := _inventory.get_slot(source_slot_index)
	if slot.is_empty():
		return
	var item := slot.get("item", {}) as Dictionary
	var result := player.equip_backpack_item(item)
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "背包装备失败"))
		return
	_inventory.remove_from_slot(source_slot_index, 1)
	status_label.text = "已装备 %s" % str(item.get("name", "背包"))


func _on_equipped_backpack_to_inventory_requested(target_slot_index: int) -> void:
	if not _inventory.get_slot(target_slot_index).is_empty():
		status_label.text = "卸下失败：目标背包格已有物品"
		return
	var result := player.unequip_backpack_item()
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "卸下背包失败"))
		return
	var old_item := result.get("old_item", {}) as Dictionary
	if not _inventory.put_item_in_empty_slot(target_slot_index, old_item, 1):
		player.equip_backpack_item(old_item)
		status_label.text = "卸下失败：背包写入失败，已装回"
		return
	status_label.text = "已卸下 %s" % str(old_item.get("name", "背包"))


func _on_equipped_backpack_drop_requested() -> void:
	var result := player.unequip_backpack_item()
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "卸下背包失败"))
		return
	var old_item := result.get("old_item", {}) as Dictionary
	if not _discard_inventory_item(old_item, 1):
		player.equip_backpack_item(old_item)
		status_label.text = "丢弃失败，已装回"
		return
	status_label.text = "已丢在地上 %s" % str(old_item.get("name", "背包"))


func _on_rack_selected(_rack: TrainingRack3D, item_id: String, category: String) -> void:
	if category == "gunbody":
		selected_gun_id = item_id
		if _is_melee_gunbody(selected_gun_id):
			selected_bullet_id = ""
		elif selected_bullet_id.is_empty():
			selected_bullet_id = "mod_bullet_standard"
	else:
		selected_bullet_id = item_id
		if selected_gun_id.is_empty() or _is_melee_gunbody(selected_gun_id):
			selected_gun_id = "bp_pistol"
	if player.equip_weapon(selected_gun_id, selected_bullet_id):
		var snapshot := player.get_weapon_snapshot()
		_refresh_loadout_feedback(snapshot)


func _on_target_damaged(_target: TrainingTarget3D, applied: int, critical: bool) -> void:
	total_hits += 1
	total_damage += applied
	status_label.text = "命中 %d%s" % [applied, " · 暴击" if critical else ""]
	_refresh_stats()


func _on_target_destroyed(_target: TrainingTarget3D) -> void:
	targets_destroyed += 1
	_refresh_stats()


func _on_wave_spawned(_pad: TrainingSpawnPad3D, count: int) -> void:
	status_label.text = "刷出 %d 只敌人；清场后离开触发区再踏入可再次触发。" % count


func _on_enemy_killed(_enemy: Enemy3D, _loot: Dictionary) -> void:
	kills += 1
	# 测试用简化掉落：让"击杀 → 进背包"这条链在靶场里成立，
	# 好让依赖背包 / 掉落 / 宝箱的命运卡看得到落点。正式掉落不在这里。
	var granted := _grant_test_loot(1)
	status_label.text = "击杀 +1 · 背包 +%d（%s）" % [granted, _bag_summary()]
	_refresh_stats()


func _on_reinforcement_requested(count: int, spawn_elite: bool) -> void:
	if _spawn_pads.is_empty():
		return
	# 增援落在第一个台上；精英在靶场里退化为"多加一只"，
	# 因为精英装配端需要遭遇上下文（encounter id / 楼层名册），靶场没有这套。
	var pad := _spawn_pads[0]
	var total := count + (1 if spawn_elite else 0)
	var spawned := pad.spawn_wave_with(total, pad.enemy_type)
	status_label.text = "世界命运增援：刷出 %d 只" % spawned


func _on_world_card_applied(card_id: String, detail: String) -> void:
	status_label.text = "世界命运 %s：%s" % [card_id.trim_prefix("fate_"), detail]


## 补给箱：兑现宝箱类命运卡（幸运宝箱 / 额外战利品 / 太阳品质 / 太阳额外掉落）。
## 待结状态由世界宿主持有，开箱即消费清零 —— 与正式局内"下一箱"的语义一致。
func _on_supply_crate_activated(_station: ServiceStation3D) -> void:
	var pending := _world_game_mode.consume_chest_pending() if _world_game_mode != null else {}
	var extra := maxi(0, int(pending.get("extra_count", 0)))
	var quality_boost := maxi(0, int(pending.get("quality_boost", 0)))
	# 基础补给是一小批不同物资：让背包界面一开就有内容可看、可拖、可装备。
	var granted := 0
	for entry in TEST_SUPPLY_BATCH:
		granted += _grant_item(str(entry["item_id"]), int(entry["count"]) + extra)
	if quality_boost > 0:
		granted += _grant_item(TEST_QUALITY_ITEM_ID, quality_boost)
	var detail := "基础 %d 种" % TEST_SUPPLY_BATCH.size()
	if extra > 0:
		detail += " + 额外 %d/种" % extra
	if quality_boost > 0:
		detail += " + 品质 %d 档" % quality_boost
	status_label.text = "补给箱已开启（%s）· 背包 +%d｜%s" % [detail, granted, _bag_summary()]


func _on_reset_station(_station: ServiceStation3D) -> void:
	for target in _targets:
		target.reset_target()
	for pad in _spawn_pads:
		pad.clear_wave()
	if player.weapon != null:
		player.weapon.current_ammo = player.weapon.magazine_size
		player.weapon.ammo_changed.emit(player.weapon.current_ammo, player.weapon.magazine_size)
	status_label.text = "靶标、敌人与弹药已重置；统计继续累计（背包不被清空）。"


func clear_backpack() -> void:
	if _inventory == null:
		return
	_inventory.clear_all()
	_refresh_bag_label()


func _on_fate_bench_activated(_station: ServiceStation3D) -> void:
	if _fate_panel != null and is_instance_valid(_fate_panel):
		return
	var panel := TrainingFateBenchPanel.new()
	_fate_panel = panel
	panel.set_player(player)
	panel.closed.connect(_on_fate_bench_closed)
	add_child(panel)


func _on_fate_bench_closed() -> void:
	_fate_panel = null
	status_label.text = "组装台已关闭；本次装配只存在于测试武器上，离开靶场即还原。"


func _on_ammo_changed(current: int, maximum: int) -> void:
	if player != null and player.weapon != null and player.weapon.is_melee_weapon():
		ammo_label.text = "MELEE · 三段"
	else:
		ammo_label.text = "AMMO %d/%d" % [current, maximum]


func _refresh_stats() -> void:
	stats_label.text = "命中 %d · 伤害 %d · 击破 %d · 击杀 %d" % [
		total_hits, total_damage, targets_destroyed, kills
	]


## 入口切场景前调用，登记来源场景。
static func set_origin_scene_path(path: String) -> void:
	_origin_scene_path = path


func _on_exit_requested() -> void:
	if test_mode:
		status_label.text = "测试模式：已验证返回入口"
		return
	var target := _resolve_return_scene_path()
	var request_id := _register_return_entry_intent(target)
	var change_error := get_tree().change_scene_to_file(target)
	if change_error != OK:
		if request_id > 0:
			GameEntryFlow.cancel_request(request_id)
		status_label.text = "返回失败：%s" % error_string(change_error)


## 回 99F 基地营地**必须登记入口意图**：主场景同时承载启动展示、99F 基地与塔楼行动，
## 不登记就会被 consume_main_scene_entry() 当成冷启动或普通恢复，把玩家送去别处
## （或续上某个旧行动）。ABORT_RETURN_99F + SPAWN_BASE_99F 是项目既有的
## "放弃行动、回基地"口径，与远征撤退同一条路。
## 返回 request_id；0 表示本次目的地无需登记。
func _register_return_entry_intent(target: String) -> int:
	if target != GameDesignConfig.MAIN_SCENE:
		return 0
	return GameEntryFlow.request_gameplay_entry(
		GameEntryFlow.REASON_ABORT_RETURN_99F, GameEntryFlow.SPAWN_BASE_99F
	)


## 退出目的地：原路返回登记过的来源场景。
##
## 刻意**不**回落到 GameDesignConfig.BASE_SCENE_3D —— 那是历史「兼容基地」，
## 玩家不是从那出发的（TowerDescent3D._ready 里有同口径的钉死注释）。
## 未登记来源（例如在编辑器里直接 F6 跑本场景）时回主场景基地。
func _resolve_return_scene_path() -> String:
	if not _origin_scene_path.is_empty() and ResourceLoader.exists(_origin_scene_path, "PackedScene"):
		return _origin_scene_path
	return GameDesignConfig.MAIN_SCENE


func get_inventory() -> InventoryModule:
	return _inventory


func get_world_game_mode() -> TrainingWorldGameMode3D:
	return _world_game_mode


func _grant_test_loot(count: int) -> int:
	return _grant_item(TEST_SUPPLY_ITEM_ID, count)


## 往本场背包放物品。返回实际放入数（背包满时会少于请求数）。
func _grant_item(item_id: String, count: int) -> int:
	if _inventory == null or count <= 0:
		return 0
	var item := ItemRegistry.get_instance().get_item(item_id)
	if item.is_empty():
		return 0
	return _inventory.add_item(item, count)


func _bag_summary() -> String:
	if _inventory == null:
		return "背包不可用"
	return "背包 %d/%d" % [_inventory.get_used_slots(), _inventory.get_capacity()]


func _refresh_bag_label() -> void:
	if bag_label == null:
		return
	bag_label.text = _bag_summary()


func get_training_snapshot() -> Dictionary:
	var combination_count := (
		int(_weapon_kind_count["ranged"]) * int(_rack_count["bullet"])
		+ int(_weapon_kind_count["melee"])
	)
	return {
		"gun_count": int(_rack_count["gunbody"]), "bullet_count": int(_rack_count["bullet"]),
		"ranged_weapon_count": int(_weapon_kind_count["ranged"]),
		"melee_weapon_count": int(_weapon_kind_count["melee"]),
		"combination_count": combination_count,
		"target_types": _targets.map(func(target): return target.target_type),
		"spawn_pad_count": _spawn_pads.size(),
		"spawn_pad_types": _spawn_pads.map(func(pad): return pad.enemy_type),
		"has_fate_bench": _has_service_named(FATE_BENCH_NAME),
		"has_supply_crate": _has_service_named(SUPPLY_CRATE_NAME),
		"has_reset_station": _has_service_named(RESET_STATION_NAME),
		"has_exit": _has_exit_station(),
		"has_inventory": _inventory != null,
		"backpack_capacity": _inventory.get_capacity() if _inventory != null else 0,
		"has_insurance": _insurance != null,
		"has_inventory_ui": _inventory_ui != null and is_instance_valid(_inventory_ui),
		"has_weapon_panel": _weapon_panel != null and is_instance_valid(_weapon_panel),
		"weapon_panel_tracks_tree": _weapon_panel_tracks_tree(),
		"has_world_game_mode": _world_game_mode != null,
		"base_data_unchanged": is_base_data_unchanged(), "environment": environment_kit.get_snapshot(), "is_3d": true,
	}


func _has_service_named(target_name: String) -> bool:
	for child in $Services.get_children():
		if child is ServiceStation3D and (child as ServiceStation3D).display_name == target_name:
			return true
	return false


func _has_exit_station() -> bool:
	for child in $Services.get_children():
		if child is TrainingExit3D:
			return true
	return false


## 装备界面是否挂在**玩家当前**的武器树上。换枪后为假 = 注入漏了，
## 表现为面板一直显示上一把枪的构筑（靶场换枪是高频操作，很容易撞上）。
func _weapon_panel_tracks_tree() -> bool:
	if _weapon_panel == null or not is_instance_valid(_weapon_panel):
		return false
	return _weapon_panel.get("_weapon_tree") == player.get_weapon_tree()


func is_base_data_unchanged() -> bool:
	if _base_snapshot.is_empty() or BaseManager == null:
		return true
	return _base_snapshot == _get_training_owned_base_snapshot()


func _get_training_owned_base_snapshot() -> Dictionary:
	var snapshot := BaseManager.get_profile_snapshot()
	# 世界时钟与按世界时间恢复的基地能源属于常驻全局系统；它们在任何
	# 可游玩场景中都会推进，不能被误判为靶场装备/目标写入了长期进度。
	for global_key in [
		"world_time_elapsed_game_seconds",
		"base_energy_current",
		"base_energy_capacity",
		"base_energy_last_synced_game_seconds",
	]:
		snapshot.erase(global_key)
	return snapshot


func equip_combination_for_test(gun_id: String, bullet_id: String) -> bool:
	selected_gun_id = gun_id
	selected_bullet_id = "" if _is_melee_gunbody(gun_id) else bullet_id
	var equipped := player.equip_weapon(gun_id, selected_bullet_id)
	if equipped:
		_refresh_loadout_feedback(player.get_weapon_snapshot())
	return equipped


func _is_melee_gunbody(gun_id: String) -> bool:
	for entry in BlueprintRegistry.get_available_gunbodies(99):
		if str(entry.get("item_id", "")) == gun_id:
			return "melee" in (entry.get("tags", []) as Array)
	return false


func _refresh_loadout_feedback(snapshot: Dictionary) -> void:
	var weapon_name := selected_gun_id.trim_prefix("bp_")
	if bool(snapshot.get("melee", false)):
		var profile := player.weapon.get_melee_profile()
		loadout_label.text = "%s · 近战" % weapon_name
		ammo_label.text = "MELEE · 三段"
		status_label.text = "近战已装备 · 伤害 %d · 距离 %.2fm · %d 段" % [
			int(snapshot.get("damage", 0)),
			float(profile.get("reach", 0.0)),
			int(profile.get("combo_count", 0)),
		]
		return
	loadout_label.text = "%s + %s" % [weapon_name, selected_bullet_id.trim_prefix("mod_bullet_")]
	ammo_label.text = "AMMO %d/%d" % [int(snapshot.get("current_ammo", 0)), int(snapshot.get("magazine_size", 0))]
	status_label.text = "组合已装配 · 伤害 %d · 射速 %.1f · 弹丸 %d" % [
		int(snapshot.get("damage", 0)),
		float(snapshot.get("fire_rate", 0.0)),
		int(snapshot.get("projectile_count", 0)),
	]
