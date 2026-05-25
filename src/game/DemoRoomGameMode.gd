class_name DemoRoomGameMode
## 8房间线性链 Demo 游戏模式
## 演示房间组件化系统的完整搜打撤流程
## 房间布局：R1-R2(战斗) → R3(搜刮) → R4(商人) → R5(改造) → R6(BOSS) → R7(精英) → R8(撤离)
## 门规则：清怪开门，E键交互，钥匙消耗

extends Node2D

## 撤离模块（直接实例化，ExtractionModule extends RefCounted 不能作为 Node child）
var _extraction_module: ExtractionModule = null

func _get_extraction_module() -> ExtractionModule:
	if _extraction_module == null:
		_extraction_module = ExtractionModule.new()
	return _extraction_module

## 背包模块（直接实例化，InventoryModule extends RefCounted 不能作为 Node child）
var _inventory_module: InventoryModule = null

func _get_inventory_module() -> InventoryModule:
	if _inventory_module == null:
		_inventory_module = InventoryModule.new()
	return _inventory_module

## 背包UI（standalone模式，Tab切换显示）
var _inventory_ui: Control = null

func _get_inventory_ui() -> Control:
	if _inventory_ui == null:
		var inv_ui := preload("res://src/ui/InventoryUI.gd").new() as Control
		inv_ui.name = "InventoryUI"
		inv_ui.set_inventory_module(_get_inventory_module())
		add_child(inv_ui)
		_inventory_ui = inv_ui
	return _inventory_ui

## 武器装配树可视化面板（Tab切换，绑定Player的weapon_tree）
var _weapon_panel: Control = null

func _get_weapon_panel() -> Control:
	if _weapon_panel == null:
		var panel_scene := preload("res://scenes/WeaponAssemblyTreePanel.tscn") as PackedScene
		var panel := panel_scene.instantiate() as Control
		panel.name = "WeaponAssemblyTreePanel"
		# 立即绑定 Player 的 weapon_tree（Player 已在 _spawn_player 中实例化）
		if _player != null and _player.has_method("get_weapon_tree"):
			var wt = _player.get_weapon_tree()
			if wt:
				(panel as WeaponAssemblyTreePanel).set_weapon_tree(wt)
		add_child(panel)
		_weapon_panel = panel
	return _weapon_panel

## 状态
var _current_room_id: int = 0
var _room_key_count: int = 1
var _player: Node2D = null
var _room_instances: Dictionary = {}
var _enemies_remaining: int = 0
var _rooms_cleared: Array[int] = []
var _extraction_started: bool = false

## 门交互状态（修复：改用 _process 轮询检测，避免帧同步问题）
var _near_door: Dictionary = {}  # door_area → {from_id, to_id, label}

## 房间切换淡入淡出
var _transition_canvas: CanvasLayer = null
var _transition_overlay: ColorRect = null
var _is_transitioning: bool = false
const FADE_DURATION: float = 0.25  # 每次淡入/淡出时长（秒）

## 房间节点数据（7房间线性链：4战斗+1搜刮+1商人+1改造+1精英+1撤离）
## node_id: {type, position, enemy_count, is_cleared, is_extraction}
const DEMO_ROOMS: Array[Dictionary] = [
	{
		"node_id": 0,
		"type": RoomData.RoomType.COMBAT,
		"position": Vector2(0, 0),
		"enemy_count": 3,
		"enemy_types": ["melee_chaser", "melee_chaser", "melee_chaser"],
		"is_extraction": false,
	},
	{
		"node_id": 1,
		"type": RoomData.RoomType.COMBAT,
		"position": Vector2(1000, 0),
		"enemy_count": 3,
		"enemy_types": ["melee_chaser", "melee_chaser", "ranged_caster"],
		"is_extraction": false,
	},
	{
		"node_id": 2,
		"type": RoomData.RoomType.STORAGE,
		"position": Vector2(2000, 0),
		"enemy_count": 2,
		"enemy_types": ["melee_chaser", "melee_chaser"],
		"is_extraction": false,
	},
	{
		"node_id": 3,
		"type": RoomData.RoomType.MERCHANT,
		"position": Vector2(3000, 0),
		"enemy_count": 0,
		"enemy_types": [],
		"is_extraction": false,
	},
	{
		"node_id": 4,
		"type": RoomData.RoomType.UPGRADE,
		"position": Vector2(4000, 0),
		"enemy_count": 0,
		"enemy_types": [],
		"is_extraction": false,
	},
	{
		"node_id": 5,
		"type": RoomData.RoomType.BOSS,
		"position": Vector2(5000, 0),
		"enemy_count": 0,
		"enemy_types": [],
		"is_extraction": false,
	},
	{
		"node_id": 6,
		"type": RoomData.RoomType.ELITE,
		"position": Vector2(6000, 0),
		"enemy_count": 1,
		"enemy_types": ["elite"],
		"is_extraction": false,
	},
	{
		"node_id": 7,
		"type": RoomData.RoomType.EXTRACTION,
		"position": Vector2(7000, 0),
		"enemy_count": 0,
		"enemy_types": [],
		"is_extraction": true,
	},
]

## 房间场景预制件映射
const ROOM_SCENES: Dictionary = {
	RoomData.RoomType.COMBAT: "res://scenes/RoomCombat.tscn",
	RoomData.RoomType.STORAGE: "res://scenes/RoomStorage.tscn",
	RoomData.RoomType.ELITE: "res://scenes/RoomElite.tscn",
	RoomData.RoomType.BOSS: "res://scenes/RoomBoss.tscn",
	RoomData.RoomType.EXTRACTION: "res://scenes/RoomExtraction.tscn",
	RoomData.RoomType.MERCHANT: "res://scenes/RoomMerchant.tscn",
	RoomData.RoomType.UPGRADE: "res://scenes/RoomUpgrade.tscn",
}

## 门碰撞尺寸
const DOOR_HALF_WIDTH: float = 48.0
const DOOR_HALF_HEIGHT: float = 38.0
const KEY_COST: int = 1

## UI 引用
var _ui_label: Label = null

func _ready() -> void:
	_setup_ui()
	_spawn_player()
	_instantiate_demo_rooms()
	_enter_room(0)
	_setup_key_input()

func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "DemoUI"
	add_child(canvas)
	
	var label := Label.new()
	label.name = "InfoLabel"
	label.position = Vector2(20, 20)
	label.add_theme_font_size_override("font_size", 18)
	label.text = "DemoRoomChain 演示：8房间搜打撤链\nR1-R2(战斗) → R3(搜刮) → R4(商人) → R5(改造) → R6(BOSS) → R7(精英) → R8(撤离)\n按 [WASD] 移动，靠近门按 [E] 开门"
	canvas.add_child(label)
	_ui_label = label
	
	_setup_transition_canvas()

## 创建房间切换淡入淡出遮罩
func _setup_transition_canvas() -> void:
	_transition_canvas = CanvasLayer.new()
	_transition_canvas.name = "TransitionCanvas"
	_transition_canvas.layer = 100  # 最顶层
	add_child(_transition_canvas)
	
	_transition_overlay = ColorRect.new()
	_transition_overlay.name = "TransitionOverlay"
	_transition_overlay.custom_minimum_size = Vector2(1920, 1080)  # 足够覆盖屏幕
	_transition_overlay.size = Vector2(1920, 1080)
	_transition_overlay.position = -Vector2(960, 540)
	_transition_overlay.color = Color.BLACK
	_transition_overlay.modulate.a = 0.0
	_transition_canvas.add_child(_transition_overlay)

## 淡出→切换房间→淡入（非阻塞，协程）
func _fade_out_in(room_id: int) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	
	# 淡出（屏幕变黑）
	await _fade_to_black()
	
	# 执行房间切换
	_do_enter_room(room_id)
	
	# 淡入（屏幕恢复）
	await _fade_to_clear()
	
	_is_transitioning = false

## 淡出到纯黑
func _fade_to_black() -> void:
	var tween := create_tween()
	tween.tween_property(_transition_overlay, "modulate:a", 1.0, FADE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished

## 淡入到透明
func _fade_to_clear() -> void:
	var tween := create_tween()
	tween.tween_property(_transition_overlay, "modulate:a", 0.0, FADE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished

## 执行实际房间切换（_enter_room 的核心逻辑，供 fade 协程调用）
func _do_enter_room(room_id: int) -> void:
	# 隐藏当前房间
	if _current_room_id >= 0 and _room_instances.has(_current_room_id):
		_room_instances[_current_room_id].visible = false
	
	_current_room_id = room_id
	
	# 显示新房间
	var room_instance: Node2D = _room_instances.get(room_id)
	if room_instance == null:
		return
	
	# 刷新容器背包注入
	_setup_room_containers(room_instance)
	
	room_instance.visible = true
	
	# 移动玩家到房间入口
	var room_data: Dictionary = DEMO_ROOMS[room_id]
	var player_entry_pos := _get_player_entry_position(room_id)
	_player.global_position = player_entry_pos
	
	# 启动波次
	var spawner: Node = room_instance.get_node_or_null("WaveSpawner") as Node
	if spawner != null and spawner.has_method("start") and room_data["enemy_count"] > 0:
		if not _rooms_cleared.has(room_id):
			spawner.start()
			_enemies_remaining = room_data["enemy_count"]
			_update_label("房间 %d：消灭 %d 个敌人！" % [room_id, _enemies_remaining])
	elif room_data.get("is_extraction", false):
		_update_label("=== 撤离房 ===\n按 [E] 开始撤离读条")
		_schedule_extraction_start()
	elif room_data["type"] == RoomData.RoomType.BOSS:
		_update_label("=== BOSS房 ===\n击败Boss即可开启撤离！")
		# BOSS房不消耗钥匙，清完Boss后自动开放（通过boss_defeated信号）
		_setup_boss_room_signals(room_instance)
	else:
		_enemies_remaining = 0
	
	_update_label("进入房间 %d [%s]" % [room_id, RoomData.get_type_name(room_data["type"])])

func _setup_key_input() -> void:
	# WASD 移动由 Player.tscn 内置处理
	pass

## 生成玩家角色
func _spawn_player() -> void:
	var player_scene := preload("res://scenes/Player.tscn")
	_player = player_scene.instantiate()
	_player.global_position = Vector2(0, 0)
	add_child(_player)
	
	# 设置相机
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.enabled = true
	add_child(camera)
	camera.make_current()
	
	# 实例化命运卡片 UI 控制器（Tab 键呼出卡片选择）
	_spawn_fate_card_ui()
	
	# 连接玩家受伤信号（用于撤离读条中断）
	if _player.has_signal("hp_changed"):
		_player.hp_changed.connect(_on_player_hp_changed)

## 实例化命运卡片 UI 控制器
func _spawn_fate_card_ui() -> void:
	var fate_ui_scene := preload("res://scenes/FateCardUIController.tscn") as PackedScene
	if fate_ui_scene != null:
		var fate_ui: Control = fate_ui_scene.instantiate() as Control
		if fate_ui != null:
			add_child(fate_ui)
			print("[DemoRoomGameMode] FateCardUIController 已实例化")

## 实例化所有Demo房间
func _instantiate_demo_rooms() -> void:
	for room_data in DEMO_ROOMS:
		var node_id: int = room_data["node_id"]
		var room_type: RoomData.RoomType = room_data["type"]
		var scene_path: String = ROOM_SCENES.get(room_type, "res://scenes/RoomCombat.tscn")
		
		var room_instance: Node2D
		if ResourceLoader.exists(scene_path):
			var scene: PackedScene = load(scene_path) as PackedScene
			room_instance = scene.instantiate() as Node2D
		else:
			room_instance = _create_placeholder_room(room_data)
		
		room_instance.name = "DemoRoom_%d" % node_id
		room_instance.global_position = room_data["position"]
		room_instance.visible = false
		add_child(room_instance)
		_room_instances[node_id] = room_instance
		
		# 初始化房间视觉（TileMap + 门边界）
		_initialize_room_visual(room_instance, room_type, room_data)
		
		# 为战斗房配置波次生成器
		if room_data["enemy_count"] > 0:
			_configure_wave_spawner(room_instance, room_data)
		
		# 为每个门创建碰撞体
		_create_doors_for_room(room_instance, node_id, room_data)
		
		# 为容器组件注入背包引用（StorageRoomLogic + 独立 ContainerInteraction）
		_setup_room_containers(room_instance)
		
		# 为商人/改造房注入背包引用
		_setup_room_interactions(room_instance)

## 初始化房间视觉（TileMap + 边界碰撞体）
func _initialize_room_visual(room_instance: Node2D, room_type: RoomData.RoomType, room_data: Dictionary) -> void:
	var room_size := Vector2(GridConstants.ROOM_PIXEL_WIDTH, GridConstants.ROOM_PIXEL_HEIGHT)
	var door_info: Array[Dictionary] = []
	
	# 优先使用 RoomVisualizer.configure() — 直接调用，确保 ELITE 房间主题色正确注入
	var room_visualizer := room_instance.get_node_or_null("Visualizer") as RoomVisualizer
	if room_visualizer != null:
		room_visualizer.configure(room_type, room_size, door_info)
	elif room_instance.has_method("configure"):
		# fallback：其他实现
		room_instance.configure(room_type, room_size, door_info)
	
	_add_boundary_collision(room_instance, room_size, door_info)

## 为容器组件注入背包引用
func _setup_room_containers(room_instance: Node2D) -> void:
	var inventory: InventoryModule = _get_inventory_module()
	
	# 方案1：StorageRoomLogic（如果有）
	var storage_logic: Node = room_instance.get_node_or_null("StorageRoomLogic")
	if storage_logic == null:
		# 尝试获取自身（如果房间根节点就是 StorageRoomLogic）
		if room_instance.has_method("set_inventory"):
			storage_logic = room_instance
	if storage_logic != null and storage_logic.has_method("set_inventory"):
		storage_logic.call("set_inventory", inventory)
	
	# 方案2：递归找所有独立 ContainerInteraction（不在 StorageRoomLogic 下）
	var container_nodes: Array[Node] = []
	_fill_container_nodes(room_instance, container_nodes)
	for cn in container_nodes:
		var ci: ContainerInteraction = cn as ContainerInteraction
		if ci != null and ci.has_method("set_inventory"):
			ci.set_inventory(inventory)

## 递归收集所有 ContainerInteraction 节点（排除已在 StorageRoomLogic 内部的）
func _fill_container_nodes(root: Node, arr: Array[Node]) -> void:
	for child in root.get_children():
		if child is ContainerInteraction:
			# 跳过已由 StorageRoomLogic 处理的（如果 StorageRoomLogic 存在）
			var parent_node: Node = child.get_parent()
			if parent_node != null and parent_node.has_method("set_inventory"):
				continue  # StorageRoomLogic 会处理这个容器
			arr.append(child)
		elif not (child is Area2D or child is Node2D and child.has_method("set_inventory")):
			# 避免递归进 StorageRoomLogic 自身（它会处理内部容器）
			_fill_container_nodes(child, arr)

## 为商人/改造房注入背包引用（供 MerchantInteraction / WorkbenchInteraction 使用）
func _setup_room_interactions(room_instance: Node2D) -> void:
	var inventory: InventoryModule = _get_inventory_module()
	
	# 找 MerchantInteraction 并注入背包
	var merchant_area: Node = room_instance.get_node_or_null("MerchantArea")
	if merchant_area != null and merchant_area.has_method("set_inventory"):
		merchant_area.set_inventory(inventory)
	
	# 找 WorkbenchInteraction 并注入背包
	var workbench_area: Node = room_instance.get_node_or_null("WorkbenchArea")
	if workbench_area != null and workbench_area.has_method("set_inventory"):
		workbench_area.set_inventory(inventory)

## 为战斗房配置波次生成器
func _configure_wave_spawner(room_instance: Node2D, room_data: Dictionary) -> void:
	var spawner: Node = room_instance.get_node_or_null("WaveSpawner") as Node
	if spawner == null or not spawner.has_method("configure"):
		return
	
	var enemy_count: int = room_data["enemy_count"]
	var wave_counts: Array[int] = [enemy_count]
	
	spawner.configure(wave_counts, room_instance, _player, 1, RoomData.FloorLevel.SHALLOW, self)
	spawner.all_waves_cleared.connect(_on_waves_cleared.bind(room_data["node_id"]))
	spawner.enemy_spawned.connect(_on_enemy_spawned)

## 为每个房间创建门碰撞体（左右各一）
func _create_doors_for_room(room_instance: Node2D, node_id: int, room_data: Dictionary) -> void:
	var room_pos: Vector2 = room_data["position"]
	var room_size := Vector2(GridConstants.ROOM_PIXEL_WIDTH, GridConstants.ROOM_PIXEL_HEIGHT)
	
	# 左门（连接上一个房间，除了node_id=0）
	if node_id > 0:
		var prev_id: int = node_id - 1
		var door_area := _create_door_area(room_instance, Vector2(-room_size.x * 0.5, 0), prev_id, node_id)
		room_instance.add_child(door_area)
	
	# 右门（连接下一个房间，除了最后一个）
	if node_id < DEMO_ROOMS.size() - 1:
		var next_id: int = node_id + 1
		var door_area := _create_door_area(room_instance, Vector2(room_size.x * 0.5, 0), node_id, next_id)
		room_instance.add_child(door_area)

## 创建门碰撞体 Area2D
func _create_door_area(parent: Node2D, local_pos: Vector2, from_id: int, to_id: int) -> Area2D:
	var area := Area2D.new()
	area.name = "Door_to_%d" % to_id
	area.position = local_pos
	area.collision_layer = 0
	area.collision_mask = 2  # Player layer
	area.body_entered.connect(_on_door_body_entered.bind(area, from_id, to_id))
	area.body_exited.connect(_on_door_body_exited.bind(area, from_id, to_id))
	
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(DOOR_HALF_WIDTH * 2.0, DOOR_HALF_HEIGHT * 2.0)
	shape.shape = rect
	area.add_child(shape)
	
	# 门视觉
	var plate := ColorRect.new()
	plate.name = "DoorPlate"
	plate.size = Vector2(DOOR_HALF_WIDTH * 2.0 - 8, 20)
	plate.position = Vector2(-DOOR_HALF_WIDTH + 4, -10)
	plate.color = Color(0.95, 0.68, 0.20, 0.82)
	plate.z_index = 170
	area.add_child(plate)
	
	var label := Label.new()
	label.name = "DoorLabel"
	label.position = Vector2(-80, -50)
	label.size = Vector2(160, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.text = "[E] 用钥匙开门"
	label.z_index = 171
	label.visible = false
	area.add_child(label)
	
	# 保存门元数据
	area.set_meta("from_id", from_id)
	area.set_meta("to_id", to_id)
	area.set_meta("door_label", label)
	
	return area

## 门交互状态
var _door_entry_time: Dictionary = {}  # door_area → timestamp when player entered

func _on_door_body_entered(body: Node2D, door_area: Area2D, from_id: int, to_id: int) -> void:
	if not body.is_in_group("player"):
		return
	
	# 记录当前靠近的门
	if door_area != null:
		var lbl: Label = door_area.get_meta("door_label") as Label
		if lbl != null:
			lbl.visible = true
			# 进入时立即刷新锁定/可开启状态
			_refresh_door_visual(door_area, from_id, to_id, lbl)
		_near_door[door_area] = {"from_id": from_id, "to_id": to_id, "label": lbl}

func _on_door_body_exited(body: Node2D, door_area: Area2D, from_id: int, to_id: int) -> void:
	if not body.is_in_group("player"):
		return
	
	if door_area != null and _near_door.has(door_area):
		var lbl: Label = _near_door[door_area].get("label") as Label
		if lbl != null:
			lbl.visible = false
		_near_door.erase(door_area)

## 刷新门视觉（标签文字+门板颜色）
## locked=true: 红色锁定状态；locked=false: 绿色可开启状态
func _refresh_door_visual(door_area: Area2D, from_id: int, to_id: int, label: Label) -> void:
	var is_cleared: bool = _rooms_cleared.has(from_id)
	var has_keys: bool = _room_key_count >= KEY_COST
	var target_cleared: bool = _rooms_cleared.has(to_id)
	
	# 门板 ColorRect
	var plate: ColorRect = door_area.get_node_or_null("DoorPlate") as ColorRect
	
	if target_cleared:
		# 目标房间已清理过（可重复进入），绿色
		label.text = "[E] 进入房间 %d" % to_id
		if plate:
			plate.color = Color(0.2, 0.7, 0.3, 0.75)
	elif is_cleared and has_keys:
		# 当前房间已清理且有钥匙，绿色可开启
		label.text = "[E] 用钥匙开门"
		if plate:
			plate.color = Color(0.2, 0.7, 0.3, 0.75)
	elif is_cleared:
		# 已清理但没钥匙，橙色提示
		label.text = "[E] 需要钥匙（剩余%d）" % _room_key_count
		if plate:
			plate.color = Color(0.9, 0.5, 0.1, 0.75)
	else:
		# 未清理，红色锁定
		label.text = "[E] 先消灭敌人"
		if plate:
			plate.color = Color(0.75, 0.1, 0.1, 0.8)

## 门交互检测（_process 轮询，解决帧同步问题）
func _process(_delta: float) -> void:
	# Tab键切换武器装配树面板显示/隐藏
	if Input.is_action_just_pressed("ui_tab"):
		var panel: Control = _get_weapon_panel()
		if panel != null:
			panel.toggle()
	# 撤离房：E键触发撤离读条
	if _current_room_id == DEMO_ROOMS.size() - 1:
		var room_data: Dictionary = DEMO_ROOMS[_current_room_id]
		if room_data.get("is_extraction", false) and _extraction_module != null and _extraction_module.get_status() == ExtractionModule.ExtractionStatus.IDLE:
			if Input.is_action_just_pressed("interact") and _extraction_started:
				_try_start_extraction()
		# 更新撤离读条进度
		if _extraction_module != null and _extraction_module.get_status() == ExtractionModule.ExtractionStatus.COUNTDOWN:
			_extraction_module.update(_delta)
			var rem: float = _extraction_module.get_remaining_time()
			var prog: float = _extraction_module.get_progress()
			_update_label("=== 撤离读条中 ===\n%.1f秒 remaining...\n[======%.0f%%==]" % [rem, prog * 100.0])
		return
	
	# 门交互：E键开门
	if _near_door.is_empty():
		return
	if Input.is_action_just_pressed("interact"):
		for door_area in _near_door.keys():
			var data: Dictionary = _near_door[door_area]
			var from_id: int = data["from_id"]
			var to_id: int = data["to_id"]
			if _try_open_door(from_id, to_id):
				break

## 尝试开门
func _try_open_door(from_id: int, to_id: int) -> bool:
	# 检查目标房间是否已清理
	if _rooms_cleared.has(to_id):
		_enter_room(to_id)
		_update_label("进入房间 %d" % to_id)
		return true
	
	if not _rooms_cleared.has(from_id):
		_update_label("先清理当前房间的敌人！")
		return false
	
	if _room_key_count <= 0:
		_update_label("没有钥匙了！")
		return false
	
	_room_key_count -= KEY_COST
	_enter_room(to_id)
	_update_label("进入房间 %d，钥匙剩余 %d" % [to_id, _room_key_count])
	# 消耗钥匙后刷新门锁定状态
	_refresh_all_doors()
	return true

## 进入指定房间
func _enter_room(room_id: int) -> void:
	# 已在切换中则跳过（防止重复触发）
	if _is_transitioning:
		return
	# 使用淡入淡出过渡（非阻塞协程）
	_fade_out_in(room_id)

func _get_player_entry_position(room_id: int) -> Vector2:
	var room_data: Dictionary = DEMO_ROOMS[room_id]
	var room_pos: Vector2 = room_data["position"]
	
	if room_id == 0:
		# 第一个房间：玩家从左边进入（房间中心偏左）
		return room_pos + Vector2(-300, 0)
	else:
		# 其他房间：从右边门外进入（面向左）
		return room_pos + Vector2(-300, 0)

## 波次清理回调
func _on_waves_cleared(room_id: int) -> void:
	if not _rooms_cleared.has(room_id):
		_rooms_cleared.append(room_id)
	_enemies_remaining = 0
	_update_label("房间 %d 已清理！\n使用 [E] 键开门进入下一个房间" % room_id)
	
	# 给一把钥匙
	_room_key_count += 1
	# 清怪后刷新所有门的锁定状态（门板颜色+标签文字）
	_refresh_all_doors()

## 刷新所有已存在门的锁定视觉
func _refresh_all_doors() -> void:
	for door_area in _near_door.keys():
		var data: Dictionary = _near_door[door_area]
		var from_id: int = data["from_id"]
		var to_id: int = data["to_id"]
		var lbl: Label = data.get("label") as Label
		if lbl != null:
			_refresh_door_visual(door_area, from_id, to_id, lbl)

func _on_enemy_spawned(count: int) -> void:
	_enemies_remaining += count

## BOSS房：连接BossRoomLogic信号
func _setup_boss_room_signals(room_instance: Node2D) -> void:
	var boss_logic: Node = room_instance.get_node_or_null("BossRoomLogic") as Node
	if boss_logic == null and room_instance.has_signal("boss_spawn_triggered"):
		boss_logic = room_instance
	if boss_logic == null:
		_update_label("BOSS房逻辑未找到！")
		return
	
	if boss_logic.has_signal("boss_spawn_triggered"):
		var spawn_signal := Signal(boss_logic, "boss_spawn_triggered")
		var spawn_callback := Callable(self, "_on_boss_spawn_triggered")
		if not spawn_signal.is_connected(spawn_callback):
			spawn_signal.connect(spawn_callback)
	if boss_logic.has_signal("boss_defeated_triggered"):
		var defeated_signal := Signal(boss_logic, "boss_defeated_triggered")
		var defeated_callback := Callable(self, "_on_boss_defeated_triggered")
		if not defeated_signal.is_connected(defeated_callback):
			defeated_signal.connect(defeated_callback)
	
	# 触发Boss生成（模拟）
	var boss_data := {
		"boss_id": "demo_boss_01",
		"boss_type": "standard",
		"floor": 1,
		"max_hp": 500,
		"damage": 15,
	}
	boss_logic.call("trigger_boss_spawn", boss_data)
	_update_label("Boss已出现！\n击败Boss开启撤离！")

## BOSS房：Boss生成回调
func _on_boss_spawn_triggered(boss_data: Dictionary) -> void:
	_update_label("Boss已出现：%s\n击败它！" % boss_data.get("boss_id", "?"))
	# 通知 GameUIManager 显示 Boss HP（通过 BossRoomLogic 的 boss_spawn_triggered 信号已经触发了，
	# 这里再次调用确保 GameUIManager 显示）
	var boss_logic: Node = _room_instances[_current_room_id].get_node_or_null("BossRoomLogic") if _room_instances.has(_current_room_id) else null
	if boss_logic != null and boss_logic.has_method("get_boss_data"):
		var bd: Dictionary = boss_logic.get_boss_data()
		var gui: Node = get_tree().root.find_child("GameUIManager", true, false)
		if gui != null and gui.has_method("on_boss_spawned"):
			gui.call("on_boss_spawned", bd)

## BOSS房：Boss击败回调 — 标记房间已清理，自动给钥匙
func _on_boss_defeated_triggered() -> void:
	var room_id: int = _current_room_id
	if not _rooms_cleared.has(room_id):
		_rooms_cleared.append(room_id)
	_enemies_remaining = 0
	_update_label("=== BOSS已击败！===\n使用 [E] 键开门进入下一个房间")
	_room_key_count += 1
	_refresh_all_doors()

## 撤离房：延迟启动撤离读条（等待玩家按E）
func _schedule_extraction_start() -> void:
	_extraction_started = false
	# 1秒后允许触发撤离（给玩家时间到达房间中央）
	await get_tree().create_timer(1.0).timeout
	_extraction_started = true

## 撤离房：E键触发撤离读条
func _try_start_extraction() -> bool:
	if _extraction_module == null or _extraction_module.get_status() != ExtractionModule.ExtractionStatus.IDLE:
		return false
	if not _extraction_started:
		_update_label("请稍候...")
		return false
	if _rooms_cleared.has(_current_room_id):
		return false  # 已清理的房间不需要撤离
	
	var ok: bool = _extraction_module.start_extraction("STANDARD", 5.0)
	if ok:
		_update_label("=== 撤离读条中 ===\n5秒后完成撤离！\n（此Demo到此结束）")
		# 连接撤离完成/中断信号
		if not _extraction_module.extraction_completed.is_connected(_on_extraction_completed):
			_extraction_module.extraction_completed.connect(_on_extraction_completed)
		if not _extraction_module.extraction_aborted.is_connected(_on_extraction_aborted):
			_extraction_module.extraction_aborted.connect(_on_extraction_aborted)
	return ok

## 撤离完成回调
func _on_extraction_completed(success: bool, loot: Array[Dictionary]) -> void:
	if success:
		# 通知 GameUIManager 显示撤离成功面板（完整战局统计 HUD）
		var gui: Node = get_tree().root.find_child("GameUIManager", true, false)
		if gui != null and gui.has_method("show_run_extraction_success"):
			# 统计本局：击杀数=已清理房间敌人数，货币=Inventory中魂总和
			var total_kills: int = 0
			for cleared_id in _rooms_cleared:
				if _room_instances.has(cleared_id):
					var spawner: Node = _room_instances[cleared_id].get_node_or_null("WaveSpawner")
					if spawner != null and spawner.has_method("get_wave_info"):
						var info: Dictionary = spawner.call("get_wave_info")
						total_kills += info.get("total", 0)
			var currency_amount: int = 0
			if _inventory_module != null and _inventory_module.has_method("get_all_items"):
				for item in _inventory_module.get_all_items():
					if item.get("id", "").begins_with("soul_"):
						currency_amount += item.get("stack", 0)
			gui.call("show_run_extraction_success", {
				"score": total_kills * 10,
				"kills": total_kills,
				"wave": _rooms_cleared.size(),
				"currency": currency_amount,
				"risk": _rooms_cleared.size(),
			})
		_update_label("=== 撤离成功！ ===\nDemo演示结束\n感谢游玩！")
	else:
		_update_label("=== 撤离失败 ===")

## 撤离中断回调（玩家在撤离读条期间受伤）
func _on_extraction_aborted() -> void:
	_update_label("=== 撤离已中断 ===\n你在读条期间受到了攻击！\n请重新按 [E] 开启撤离")

## 玩家受伤时中断撤离读条（搜打撤核心机制）
func _on_player_hp_changed(current: int, maximum: int) -> void:
	if _extraction_module == null:
		return
	# 仅在撤离读条进行中时响应（不是在IDLE或已完成状态）
	if _extraction_module.get_status() == ExtractionModule.ExtractionStatus.COUNTDOWN:
		_extraction_module.abort_extraction()
		_update_label("=== 撤离已中断 ===\n受到攻击！请重新按 [E] 撤离")

## 更新UI标签
func _update_label(text: String) -> void:
	if _ui_label != null:
		_ui_label.text = text

## 创建占位符房间（场景不存在时的回退）
func _create_placeholder_room(room_data: Dictionary) -> Node2D:
	var room := Node2D.new()
	room.name = "PlaceholderRoom_%d" % room_data["node_id"]
	
	var rect := ColorRect.new()
	rect.custom_minimum_size = Vector2(GridConstants.ROOM_PIXEL_WIDTH, GridConstants.ROOM_PIXEL_HEIGHT)
	rect.size = Vector2(GridConstants.ROOM_PIXEL_WIDTH, GridConstants.ROOM_PIXEL_HEIGHT)
	rect.position = -Vector2(GridConstants.ROOM_PIXEL_WIDTH, GridConstants.ROOM_PIXEL_HEIGHT) * 0.5
	var room_type: RoomData.RoomType = room_data["type"]
	var debug_color := _get_room_debug_color(room_type)
	rect.color = Color(debug_color.r, debug_color.g, debug_color.b, 0.3)
	room.add_child(rect)
	
	return room

func _get_room_debug_color(room_type: RoomData.RoomType) -> Color:
	match room_type:
		RoomData.RoomType.COMBAT: return Color(0.8, 0.2, 0.2)
		RoomData.RoomType.ELITE: return Color(0.9, 0.5, 0.1)
		RoomData.RoomType.STORAGE: return Color(0.5, 0.3, 0.1)
		RoomData.RoomType.EXTRACTION: return Color(0.1, 0.9, 0.5)
		_: return Color(0.5, 0.5, 0.5)

func _add_boundary_collision(room_instance: Node2D, room_size: Vector2, door_info: Array[Dictionary]) -> void:
	var body := StaticBody2D.new()
	body.name = "BoundaryCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	room_instance.add_child(body)
	
	var half := room_size * 0.5
	var thickness := 40.0
	
	_add_boundary_wall(body, "Top", Vector2(0, -half.y - thickness * 0.5), Vector2(room_size.x + thickness * 2.0, thickness))
	_add_boundary_wall(body, "Bottom", Vector2(0, half.y + thickness * 0.5), Vector2(room_size.x + thickness * 2.0, thickness))
	_add_boundary_wall(body, "Left", Vector2(-half.x - thickness * 0.5, 0), Vector2(thickness, room_size.y + thickness * 2.0))
	_add_boundary_wall(body, "Right", Vector2(half.x + thickness * 0.5, 0), Vector2(thickness, room_size.y + thickness * 2.0))

func _add_boundary_wall(parent: Node, wall_name: String, wall_position: Vector2, wall_size: Vector2) -> void:
	var shape := CollisionShape2D.new()
	shape.name = wall_name
	var rect := RectangleShape2D.new()
	rect.size = wall_size
	shape.shape = rect
	shape.position = wall_position
	parent.add_child(shape)
