class_name RoomFactory
extends RefCounted
## 房间工厂 — 将 RoomData 实例化为游戏场景节点

## 场景预制件映射（未来会从外部配置加载）
## 目前先用占位符场景名称
const SCENE_MAP := {
	RoomData.RoomType.PLAYER_SPAWN: "res://scenes/RoomSpawn.tscn",
	RoomData.RoomType.COMBAT: "res://scenes/RoomCombat.tscn",
	RoomData.RoomType.ELITE: "res://scenes/RoomElite.tscn",
	RoomData.RoomType.SCAVENGE: "res://scenes/RoomScavenge.tscn",
	RoomData.RoomType.MERCHANT: "res://scenes/RoomMerchant.tscn",
	RoomData.RoomType.UPGRADE: "res://scenes/RoomUpgrade.tscn",
	RoomData.RoomType.EVENT: "res://scenes/RoomEvent.tscn",
	RoomData.RoomType.EXTRACTION: "res://scenes/RoomExtraction.tscn",
	RoomData.RoomType.BOSS: "res://scenes/RoomBoss.tscn",
	RoomData.RoomType.STORAGE: "res://scenes/RoomStorage.tscn",
	RoomData.RoomType.TRAP: "res://scenes/RoomTrap.tscn",
}

var _scene_cache: Dictionary = {}


## 创建房间实例
func create_room(
	room_data: RoomData, parent: Node = null, inventory: InventoryModule = null
) -> Node2D:
	var scene_path: String = SCENE_MAP.get(room_data.room_type, SCENE_MAP[RoomData.RoomType.COMBAT])
	var room_instance: Node2D

	# 尝试加载场景
	var scene: PackedScene = _scene_cache.get(scene_path)
	if scene == null:
		if ResourceLoader.exists(scene_path):
			scene = load(scene_path) as PackedScene
			_scene_cache[scene_path] = scene

	if scene != null:
		room_instance = scene.instantiate() as Node2D
	else:
		# 场景不存在，创建占位符节点
		room_instance = _create_placeholder_room(room_data)

	room_instance.name = (
		"Room_%s_%d" % [RoomData.get_type_name(room_data.room_type), room_data.floor]
	)
	room_instance.position = room_data.position

	if parent != null:
		parent.add_child(room_instance)

	# 在主要探索房间中生成可搜索容器；战斗房清完后仍可回来搜刮。
	if (
		room_data.room_type
		in [
			RoomData.RoomType.PLAYER_SPAWN,
			RoomData.RoomType.COMBAT,
			RoomData.RoomType.ELITE,
			RoomData.RoomType.SCAVENGE,
			RoomData.RoomType.STORAGE,
			RoomData.RoomType.TRAP,
			RoomData.RoomType.BOSS,
			RoomData.RoomType.EXTRACTION,
		]
	):
		_spawn_containers_for_room(room_instance, room_data, inventory)

	# 改造房：生成工作台
	if room_data.room_type == RoomData.RoomType.UPGRADE:
		_spawn_workbench_for_room(room_instance, room_data, inventory)

	# 商人房：绑定商人NPC的 MerchantInteraction 到背包和商品
	if room_data.room_type == RoomData.RoomType.MERCHANT:
		_bind_merchant_npc(room_instance, room_data, inventory)

	_bind_existing_interactables(room_instance, inventory)

	return room_instance


func _bind_existing_interactables(root: Node, inventory: InventoryModule) -> void:
	if root == null:
		return
	if root.has_method("set_inventory"):
		root.call("set_inventory", inventory)
	for child in root.get_children():
		_bind_existing_interactables(child, inventory)


## 为商人房绑定商人NPC（MerchantInteraction -> inventory + goods）
func _bind_merchant_npc(
	room_instance: Node2D, room_data: RoomData, inventory: InventoryModule
) -> void:
	# 从 RoomMerchant.tscn 场景中查找挂有 MerchantInteraction 的节点
	# MerchantInteraction 脚本挂在 Area2D "MerchantArea" 上
	var merchant_area: Area2D = room_instance.get_node_or_null("MerchantArea") as Area2D
	if merchant_area == null:
		push_warning("[RoomFactory] RoomMerchant has no MerchantArea child")
		return

	var merchant_interaction: MerchantInteraction = merchant_area as MerchantInteraction
	if merchant_interaction == null or not merchant_interaction.has_method("set_inventory"):
		push_warning("[RoomFactory] MerchantArea has no MerchantInteraction script")
		return

	# 绑定背包
	merchant_interaction.set_inventory(inventory)

	# 预生成商品（如果尚未预生成）
	if merchant_interaction._goods.is_empty():
		var loot := LootModule.get_instance()
		if loot != null:
			var goods: Array[Dictionary] = loot.generate_merchant_goods(room_data.floor, 6)
			merchant_interaction.prepare_goods(goods)


## 在房间中生成可交互容器（宝箱/补给箱等）
## 仅用于占位符房间；真实房间场景应在场景编辑器中预置 Container 节点
func _spawn_containers_for_room(
	room_instance: Node2D, room_data: RoomData, inventory: InventoryModule
) -> void:
	# 获取房间内的容器配置（来自 ContentInjector 的 inject() 结果）
	var content_config: Dictionary = room_data.get_content_config()
	var interactables: Array[Dictionary] = []
	for item in content_config.get("interactables", []):
		if item is Dictionary:
			interactables.append(item)

	# 如果没有配置，根据房间类型生成默认容器
	if interactables.is_empty():
		interactables = _get_default_containers_for_room(room_data)

	# 实例化每个容器
	for config in interactables:
		if str(config.get("type", "")) == "extraction_point":
			continue
		var container: Node2D = _create_container_from_config(config, room_data.floor)
		if container != null:
			container.position = config.get("position", Vector2.ZERO)
			room_instance.add_child(container)

			# 绑定背包引用（用于掉落入背包）
			var ci: ContainerInteraction = container as ContainerInteraction
			if ci != null and ci.has_method("set_inventory"):
				ci.set_inventory(inventory)


## 从配置创建容器节点
func _create_container_from_config(config: Dictionary, floor: int) -> Node2D:
	var container_scene_path := "res://scenes/Container.tscn"

	if not ResourceLoader.exists(container_scene_path):
		return null

	var scene: PackedScene = load(container_scene_path) as PackedScene
	if scene == null:
		return null

	var container: Node2D = scene.instantiate() as Node2D
	if container == null:
		return null

	# 配置容器属性
	var ci: ContainerInteraction = null
	if container.has_node("Container"):
		ci = container.get_node("Container") as ContainerInteraction
	elif container.has_method("set_inventory"):
		ci = container as ContainerInteraction

	if ci != null:
		ci.container_type = config.get("type", "crate")
		ci.loot_table = config.get("loot_table", "scavenge_floor_1")
		ci.floor = floor
		ci.guaranteed_items.clear()
		for item_id in config.get("guaranteed_items", []):
			ci.guaranteed_items.append(str(item_id))

	return container


## 获取房间默认容器配置
func _get_default_containers_for_room(room_data: RoomData) -> Array[Dictionary]:
	var containers: Array[Dictionary] = []
	var floor: int = room_data.floor

	match room_data.room_type:
		RoomData.RoomType.PLAYER_SPAWN:
			(
				containers
				. append(
					{
						"type": "chest",
						"position": Vector2(-96, 0),
						"loot_table": "spawn_starter",
						"guaranteed_items": ["weapon_shotgun"],
					}
				)
			)
		RoomData.RoomType.SCAVENGE:
			var count: int = 2 + floor
			var types: Array[String] = ["crate", "locker", "hidden_cache"]
			for i in count:
				var ctype: String = types[randi() % types.size()]
				var loot_table: String = "scavenge_floor_%d" % [min(5, floor)]
				(
					containers
					. append(
						{
							"type": ctype,
							"position": _get_scavenge_container_position(i, count),
							"loot_table": loot_table,
						}
					)
				)
		RoomData.RoomType.COMBAT:
			(
				containers
				. append(
					{
						"type": "crate",
						"position": Vector2(120, -95),
						"loot_table": "combat_floor_%d" % [min(5, floor)],
					}
				)
			)
		RoomData.RoomType.ELITE:
			(
				containers
				. append(
					{
						"type": "locker",
						"position": Vector2(-130, 80),
						"loot_table": "elite_floor_%d" % [min(5, floor)],
					}
				)
			)
		RoomData.RoomType.STORAGE:
			for i in 3:
				(
					containers
					. append(
						{
							"type": "locker",
							"position": _get_scavenge_container_position(i, 3),
							"loot_table": "storage_floor_%d" % [min(5, floor)],
						}
					)
				)
		RoomData.RoomType.TRAP:
			(
				containers
				. append(
					{
						"type": "hidden_cache",
						"position": Vector2(90, 70),
						"loot_table": "trap_floor_%d" % [min(5, floor)],
					}
				)
			)
		RoomData.RoomType.BOSS:
			(
				containers
				. append(
					{
						"type": "chest",
						"position": Vector2(0, -130),
						"loot_table": "boss_floor_%d" % [min(5, floor)],
					}
				)
			)
		RoomData.RoomType.EXTRACTION:
			(
				containers
				. append(
					{
						"type": "locker",
						"position": Vector2(120, 80),
						"loot_table": "extraction_floor_%d" % [min(5, floor)],
					}
				)
			)
	return containers


## 获取搜刮房间中容器的分布位置（螺旋分布）
func _get_scavenge_container_position(index: int, total: int) -> Vector2:
	var angle: float = index * 1.618 * PI
	var radius: float = 80 + index * 40
	return Vector2(cos(angle), sin(angle)) * radius


## 在改造房间中生成工作台
func _spawn_workbench_for_room(
	room_instance: Node2D, room_data: RoomData, inventory: InventoryModule
) -> void:
	var content_config: Dictionary = room_data.get_content_config()
	var interactables: Array[Dictionary] = []
	for item in content_config.get("interactables", []):
		if item is Dictionary:
			interactables.append(item)

	# 查找 workbench 类型配置
	var bench_config: Dictionary = {}
	for config in interactables:
		if config.get("type", "") == "workbench":
			bench_config = config
			break

	if bench_config.is_empty():
		# 生成默认配置
		bench_config = {
			"type": "workbench",
			"position": Vector2.ZERO,
			"upgrade_slots": 1 + room_data.floor / 3,
			"free_use": room_data.floor < 3,
		}

	var workbench: Node2D = _create_workbench_from_config(bench_config)
	if workbench != null:
		workbench.position = bench_config.get("position", Vector2.ZERO)
		room_instance.add_child(workbench)

		# 绑定背包引用（用于工作台改造逻辑）
		if workbench.has_method("set_inventory"):
			workbench.set_inventory(inventory)


## 从配置创建工作台节点
func _create_workbench_from_config(config: Dictionary) -> Node2D:
	var workbench_scene_path := "res://scenes/Workbench.tscn"

	if not ResourceLoader.exists(workbench_scene_path):
		push_warning("[RoomFactory] Workbench scene not found at: " + workbench_scene_path)
		return null

	var scene: PackedScene = load(workbench_scene_path) as PackedScene
	if scene == null:
		return null

	var workbench: Node2D = scene.instantiate() as Node2D
	if workbench == null:
		return null

	# 配置工作台属性
	if workbench.has_method("setup_workbench"):
		workbench.setup_workbench(config.get("upgrade_slots", 1), config.get("free_use", false))

	return workbench


## 创建占位符房间节点（场景不存在时的回退）
func _create_placeholder_room(room_data: RoomData) -> Node2D:
	var node := Node2D.new()
	node.set_meta("room_data", room_data)
	node.set_meta("room_id", room_data.room_id)

	# 根据房间类型设置不同颜色用于调试
	var color := _get_room_debug_color(room_data.room_type)

	# 添加一个低透明度调试区域。注意要以房间中心为原点，
	# 否则会出现一整块从右下角铺开的红色区域。
	var debug_sprite := ColorRect.new()
	debug_sprite.position = -room_data.size * 0.5
	debug_sprite.size = room_data.size
	debug_sprite.color = Color(color.r, color.g, color.b, min(color.a, 0.08))
	debug_sprite.name = "DebugRect"
	node.add_child(debug_sprite)

	return node


func _add_room_boundary_collision(room_node: Node2D, room_size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.name = "BoundaryCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	room_node.add_child(body)

	var half := room_size * 0.5
	var thickness := 40.0
	_add_boundary_wall(
		body,
		"Top",
		Vector2(0, -half.y - thickness * 0.5),
		Vector2(room_size.x + thickness * 2.0, thickness)
	)
	_add_boundary_wall(
		body,
		"Bottom",
		Vector2(0, half.y + thickness * 0.5),
		Vector2(room_size.x + thickness * 2.0, thickness)
	)
	_add_boundary_wall(
		body,
		"Left",
		Vector2(-half.x - thickness * 0.5, 0),
		Vector2(thickness, room_size.y + thickness * 2.0)
	)
	_add_boundary_wall(
		body,
		"Right",
		Vector2(half.x + thickness * 0.5, 0),
		Vector2(thickness, room_size.y + thickness * 2.0)
	)


func _add_boundary_wall(
	parent: Node, wall_name: String, wall_position: Vector2, wall_size: Vector2
) -> void:
	var shape := CollisionShape2D.new()
	shape.name = wall_name
	var rect := RectangleShape2D.new()
	rect.size = wall_size
	shape.shape = rect
	shape.position = wall_position
	parent.add_child(shape)


## 获取房间调试颜色
func _get_room_debug_color(room_type: RoomData.RoomType) -> Color:
	match room_type:
		RoomData.RoomType.PLAYER_SPAWN:
			return Color(0.2, 0.8, 0.2, 0.3)
		RoomData.RoomType.COMBAT:
			return Color(0.8, 0.2, 0.2, 0.3)
		RoomData.RoomType.ELITE:
			return Color(0.9, 0.5, 0.1, 0.3)
		RoomData.RoomType.SCAVENGE:
			return Color(0.3, 0.7, 0.9, 0.3)
		RoomData.RoomType.MERCHANT:
			return Color(0.9, 0.9, 0.2, 0.3)
		RoomData.RoomType.UPGRADE:
			return Color(0.6, 0.3, 0.9, 0.3)
		RoomData.RoomType.EVENT:
			return Color(0.4, 0.2, 0.6, 0.3)
		RoomData.RoomType.EXTRACTION:
			return Color(0.1, 0.9, 0.5, 0.3)
		RoomData.RoomType.BOSS:
			return Color(0.7, 0.1, 0.1, 0.5)
		RoomData.RoomType.STORAGE:
			return Color(0.5, 0.3, 0.1, 0.3)
		RoomData.RoomType.TRAP:
			return Color(0.5, 0.1, 0.1, 0.3)
		_:
			return Color(0.5, 0.5, 0.5, 0.3)


## 根据房间标签过滤场景
func get_scene_for_tags(tags: Array[String]) -> String:
	# 优先匹配标签的场景
	for tag in tags:
		# 特定标签对应的场景（可扩展）
		pass
	# 默认返回普通战斗房
	return SCENE_MAP[RoomData.RoomType.COMBAT]


## 预加载所有房间场景
func preload_scenes() -> void:
	for scene_path in SCENE_MAP.values():
		if not _scene_cache.has(scene_path) and ResourceLoader.exists(scene_path):
			var scene: PackedScene = load(scene_path) as PackedScene
			if scene != null:
				_scene_cache[scene_path] = scene
