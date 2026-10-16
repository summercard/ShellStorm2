class_name TrainingSpawnPad3D
extends Area3D
## 靶场刷怪台：玩家踏入触发区即刷出一波怪；清场后离开再进入可再次触发，
## 也可走近按 E 手动补刷。
##
## 生成的敌人走 MonsterInjector 的触发盒口径（按点名怪种生成），
## 数值与远征关卡同源，因此靶场里测到的血量/伤害与实战一致。
##
## 本节点不写任何存档：敌人只活在当前场景树里，离开靶场即随场景释放。

signal wave_spawned(pad: TrainingSpawnPad3D, count: int)
signal wave_cleared(pad: TrainingSpawnPad3D)

const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
## 可点名的普通怪种（与 MonsterInjector.is_authorable_enemy_type 的白名单一致）。
const ENEMY_OPTIONS := ["melee_chaser", "fat_zombie03", "ranged_caster", "summoner", "exploder", "ambusher"]
## 环形落点半径：怪围成一圈出现，避免全部叠在中心互相卡位。
const SPAWN_RING_RADIUS_M := 4.2
const TRIGGER_RADIUS_M := 8.0

@export_enum("melee_chaser", "fat_zombie03", "ranged_caster", "summoner", "exploder", "ambusher") var enemy_type := "melee_chaser"
@export var spawn_count := 3
## 生成后的敌人挂到哪个节点下；由 TrainingRange3D 注入，为空时退化为本节点的父节点。
var enemy_container: Node3D = null

var _enemies: Array[Enemy3D] = []
var _injector: MonsterInjector = null
var _player_in_range := false
var _prompt: Label3D = null


func configure(type_id: String, count: int) -> void:
	enemy_type = type_id
	spawn_count = maxi(1, count)


func _ready() -> void:
	add_to_group("training_spawn_pad_3d")
	add_to_group(PlayerInteractionController3D.PROVIDER_GROUP)
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_injector = MonsterInjector.new()
	_build_visual()


## 刷出一整波。返回实际生成数量；上一波若还活着会先清掉，保证不会无限累积。
func spawn_wave() -> int:
	clear_wave()
	var host := enemy_container if enemy_container != null else get_parent()
	if host == null:
		return 0
	var spawned := 0
	for index in range(spawn_count):
		var data := _injector.generate_box_enemy(enemy_type, 1, 0)
		if data.is_empty():
			break
		var enemy := ENEMY_SCENE.instantiate() as Enemy3D
		if enemy == null:
			break
		host.add_child(enemy)
		var angle := TAU * float(index) / float(maxi(1, spawn_count))
		enemy.global_position = global_position + Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RING_RADIUS_M
		enemy.room_id = "training_range"
		enemy.configure_from_enemy_data(data)
		enemy.set_runtime_active(true, true)
		enemy.killed.connect(_on_enemy_killed)
		_enemies.append(enemy)
		spawned += 1
	if spawned > 0:
		wave_spawned.emit(self, spawned)
	return spawned


## 清掉本台生成且仍存活的敌人。
func clear_wave() -> void:
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	wave_cleared.emit(self)


func alive_count() -> int:
	var alive := 0
	for enemy in _enemies:
		if is_instance_valid(enemy) and not enemy.is_dead():
			alive += 1
	return alive


func get_snapshot() -> Dictionary:
	return {
		"enemy_type": enemy_type,
		"spawn_count": spawn_count,
		"alive": alive_count(),
		"is_3d": true,
	}


func get_interaction_candidate(_player: Player3D) -> Dictionary:
	if not _player_in_range:
		return {}
	return {
		"available": true,
		"interaction_id": "training_spawn_pad:%d" % get_instance_id(),
		"position": global_position,
		"priority": 70,
		"prompt": _prompt.text if _prompt != null else "[E] 刷出 %d 只" % spawn_count,
	}


## 文字提示牌退役为纯文案载体；可见反馈由常驻圆点承担。
func set_interaction_focus(_candidate: Dictionary, _focused: bool) -> void:
	pass


func get_interaction_dot_anchor() -> Vector3:
	return global_position + Vector3.UP * 1.6


func perform_interaction(_player: Player3D, _candidate: Dictionary) -> bool:
	if not _player_in_range:
		return false
	return spawn_wave() > 0


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player_3d"):
		return
	_player_in_range = true
	# 首次踏入且场上无怪时自动触发一波；清完场后需离开再进来才会再自动刷，
	# 避免玩家在触发区里来回走动时被无休止地连续刷怪。
	if alive_count() == 0:
		spawn_wave()


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player_3d"):
		return
	_player_in_range = false
	if _prompt != null:
		_prompt.visible = false


func _on_enemy_killed(_enemy: Enemy3D, _loot: Dictionary) -> void:
	if alive_count() == 0:
		wave_cleared.emit(self)


func _build_visual() -> void:
	var accent := _type_color()
	var pad_material := _material(Color(0.10, 0.12, 0.13), 0.62, 0.54)
	var ring_material := _material(accent, 0.15, 0.30, true)
	var disc := CylinderMesh.new()
	disc.top_radius = TRIGGER_RADIUS_M
	disc.bottom_radius = TRIGGER_RADIUS_M
	disc.height = 0.06
	disc.radial_segments = 32
	disc.material = pad_material
	var base := MeshInstance3D.new()
	base.name = "PadDisc"
	base.position.y = 0.03
	base.mesh = disc
	add_child(base)
	var ring := TorusMesh.new()
	ring.inner_radius = TRIGGER_RADIUS_M - 0.18
	ring.outer_radius = TRIGGER_RADIUS_M - 0.06
	ring.rings = 40
	ring.ring_segments = 8
	ring.material = ring_material
	var ring_node := MeshInstance3D.new()
	ring_node.name = "PadRing"
	ring_node.position.y = 0.07
	ring_node.mesh = ring
	add_child(ring_node)
	# 中心柱：把怪种写成看得见的地标，避免玩家分不清每个台子出什么。
	var pillar := CylinderMesh.new()
	pillar.top_radius = 0.16
	pillar.bottom_radius = 0.22
	pillar.height = 1.5
	pillar.radial_segments = 10
	pillar.material = ring_material
	var pillar_node := MeshInstance3D.new()
	pillar_node.name = "PadPillar"
	pillar_node.position.y = 0.75
	pillar_node.mesh = pillar
	add_child(pillar_node)
	_prompt = Label3D.new()
	_prompt.name = "PadLabel"
	_prompt.position = Vector3(0, 2.05, 0)
	_prompt.text = "[E] 刷出 %d 只 · %s" % [spawn_count, enemy_type]
	_prompt.font_size = 38
	_prompt.pixel_size = 0.011
	_prompt.outline_size = 8
	_prompt.modulate = accent.lightened(0.2)
	_prompt.visible = false
	add_child(_prompt)


func _type_color() -> Color:
	return {
		"melee_chaser": Color(0.86, 0.34, 0.30),
		"fat_zombie03": Color(0.72, 0.48, 0.20),
		"ranged_caster": Color(0.42, 0.70, 0.86),
		"summoner": Color(0.62, 0.42, 0.82),
		"exploder": Color(0.90, 0.66, 0.24),
		"ambusher": Color(0.36, 0.76, 0.58),
	}.get(enemy_type, Color(0.86, 0.34, 0.30))


func _material(color: Color, metallic: float, roughness: float, emission := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.7
	return material
