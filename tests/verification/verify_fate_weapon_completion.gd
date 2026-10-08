extends Node3D

const ENEMY := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
class CriticalShooter extends Node3D:
	func get_fate_critical_chance_bonus() -> float:
		return 1.0

var failures: Array[String] = []
var shots: Array[Projectile3D] = []
var trees: Array[WeaponAssemblyTree] = []
var shooter: Node3D

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		print("FAIL: ", message)

func _tree() -> WeaponAssemblyTree:
	var tree := BlueprintRegistry.build_weapon_tree("bp_rifle")
	trees.append(tree)
	return tree

func _card(tree: WeaponAssemblyTree, id: String, reversed := false) -> void:
	for card in FateCardPresets.playable_presets():
		if card.get_stable_card_id() == id:
			card.set_orientation(FateCard.Orientation.REVERSED if reversed else FateCard.Orientation.UPRIGHT, 0.75 if reversed else 0.25)
			var result := FateCardEngine.apply_card(card, tree)
			_check(result.success, id + "应用失败: " + result.message)
			return
	_check(false, "未找到卡 " + id)

func _weapon(tree: WeaponAssemblyTree) -> WeaponModel3D:
	var weapon := WeaponModel3D.new()
	add_child(weapon)
	weapon.configure_from_tree(tree)
	weapon._critical_chance = 0.0
	weapon.projectile_spawned.connect(func(projectile: Projectile3D):
		shots.append(projectile)
		projectile.set_physics_process(false))
	return weapon

func _fire(weapon: WeaponModel3D) -> Projectile3D:
	shots.clear()
	weapon._cooldown = 0.0
	weapon.try_fire(Vector3.FORWARD, shooter)
	return shots[0] if not shots.is_empty() else null

func _enemy(pos := Vector3(0, 0, -5)) -> Enemy3D:
	var enemy := ENEMY.instantiate() as Enemy3D
	add_child(enemy)
	enemy.position = pos
	enemy.max_hp = 10000
	enemy.current_hp = 10000
	enemy.set_physics_process(false)
	return enemy

func _projectile_count() -> int:
	var count := 0
	for child in get_children():
		if child is Projectile3D:
			count += 1
	return count

func _run() -> void:
	shooter = Node3D.new()
	add_child(shooter)
	var baseline_tree := _tree()
	var baseline := _weapon(baseline_tree)
	var base_damage := baseline.damage
	var base_speed := baseline.bullet_speed
	for id in ["fate_armor_pierce", "fate_scale_node", "fate_huge_scale", "fate_overclock", "fate_living_bullet"]:
		for reversed in [false, true]:
			var tree := _tree()
			_card(tree, id, reversed)
			var weapon := _weapon(tree)
			var scale_value := 1.0
			match id:
				"fate_armor_pierce": scale_value = 1.15 if reversed else 1.5
				"fate_scale_node": scale_value = 0.8 if reversed else 1.3
				"fate_huge_scale": scale_value = 0.8 if reversed else 1.5
				"fate_overclock": scale_value = 1.55 if reversed else 1.0
				"fate_living_bullet": scale_value = 1.25 if reversed else 1.0
			_check(weapon.damage == int(base_damage * scale_value), id + "伤害倍率")
			if id == "fate_scale_node" or id == "fate_huge_scale":
				var speed_scale := (1.25 if reversed else 0.8) if id == "fate_scale_node" else (1.6 if reversed else 0.6)
				_check(is_equal_approx(weapon.bullet_speed, base_speed * speed_scale), id + "弹速倍率")
			var p := _fire(weapon)
			_check(p != null, id + "实际发射")
			if id == "fate_armor_pierce":
				_check(bool(p.fate_behavior.get("pierce_shield", false)) != reversed, "力量穿盾方向")
	var mount_tree := _tree()
	_card(mount_tree, "fate_gun_on_gun")
	var mount := _weapon(mount_tree)
	_check(mount.damage == base_damage and mount.projectile_count == baseline.projectile_count, "副枪属性不得聚合到主枪")
	_fire(mount)
	_check(shots.size() == 2, "正位主副枪同射")
	var alternate_tree := _tree()
	_card(alternate_tree, "fate_gun_on_gun", true)
	var alternate := _weapon(alternate_tree)
	var first := _fire(alternate)
	_check(shots.size() == 1 and is_equal_approx(alternate.fire_rate, baseline.fire_rate * 0.75), "逆位交替首发和降速")
	var second := _fire(alternate)
	_check(shots.size() == 1 and first.damage > base_damage and second.damage > base_damage, "逆位交替单发强化")
	var reload_tree := _tree()
	_card(reload_tree, "fate_every_seventh", true)
	var reload := _weapon(reload_tree)
	_check(reload.magazine_size == int(baseline.magazine_size * 0.8), "逆位之轮弹匣")
	_check(_fire(reload).damage == base_damage, "未换弹不强化")
	reload._finish_reload()
	_check(_fire(reload).damage == int(base_damage * 2.5), "换弹首发强化")
	_check(_fire(reload).damage == base_damage, "强化只消费一次")
	reload.current_ammo = 2
	reload_tree.current_ammo = 2
	_card(reload_tree, "fate_scale_node")
	reload.configure_from_tree(reload_tree)
	_check(reload.current_ammo == 2, "装配不能自动满弹")
	var enemy := _enemy()
	for reversed in [false, true]:
		var queen_tree := _tree()
		_card(queen_tree, "fate_crit_kill", reversed)
		var queen := _weapon(queen_tree)
		var victim := _enemy()
		victim.current_hp = 1
		var p := _fire(queen)
		p.critical = reversed
		p._hit_target(victim)
		if reversed:
			_check(queen_tree.get_crit_on_kill_stack() == 0, "逆位王后不授予必暴")
			for index in range(4):
				var next := _fire(queen)
				_check(next.damage == (int(base_damage * 1.3) if index < 3 else base_damage), "逆位王后三发伤害 " + str(index))
		else:
			_check(_fire(queen).critical, "正位王后来源击杀后必暴")
		_check(baseline_tree.get_crit_on_kill_stack() == 0, "击杀不得污染其他枪")
	baseline_tree.add_crit_on_kill_stack()
	_check(baseline_tree.get_crit_on_kill_stack() == 0, "无来源广播不授予王后效果")
	for reversed in [false, true]:
		var growth_tree := _tree()
		_card(growth_tree, "fate_gluttony", reversed)
		var growth := _weapon(growth_tree)
		var p := _fire(growth)
		if reversed: p._retire()
		else: p._hit_target(enemy)
		var grown := _fire(growth)
		_check(grown.damage > base_damage and growth_tree.growth_stacks == 1, "成长跨弹体保留")
		if reversed:
			grown._hit_target(enemy)
			_check(growth_tree.growth_stacks == 0, "逆位命中消耗成长")
	for id in ["fate_home_on_land", "fate_bullet_return"]:
		for reversed in [false, true]:
			var tree := _tree()
			_card(tree, id, reversed)
			var weapon := _weapon(tree)
			var p := _fire(weapon)
			var before := weapon.current_ammo
			var before_hp := enemy.current_hp
			var outbound := p.damage
			p._hit_target(enemy)
			if id == "fate_bullet_return" and not reversed:
				_check(enemy.current_hp == before_hp - outbound - int(base_damage * 0.7), "正位折返再次命中同一目标")
			var return_damage := p.damage
			p._begin_return()
			_check(p.damage == return_damage and p._returning, "返航倍率只应用一次")
			if id == "fate_bullet_return" and reversed:
				_check(p.damage == 0, "返程零伤害")
				p.global_position = weapon.global_position
				p._physics_process(0.01)
				_check(weapon.current_ammo == before + 1, "返枪回填")
	var fire_tree := _tree()
	_card(fire_tree, "fate_fuse_fire")
	_card(fire_tree, "fate_fuse_frost", true)
	_card(fire_tree, "fate_fuse_poison")
	var element_weapon := _weapon(fire_tree)
	var element_projectile := _fire(element_weapon)
	element_projectile._flight_base_damage = 100
	element_projectile._apply_fate_on_hit(enemy)
	var hp := enemy.current_hp
	enemy._tick_fate_statuses(1.0)
	_check(enemy.current_hp == hp - 13, "火8%加一层毒5%，独立每秒结算")
	_check(is_equal_approx(enemy._slow_factor, 0.65), "逆位冰霜35%减速")
	var frost := _enemy()
	frost.apply_fate_element("ice", {"freeze_duration": 0.5}, 100, fire_tree, shooter)
	_check(frost._fate_freeze_remaining == 0.5, "正位冰霜冻结")
	var burst := _enemy()
	burst.apply_fate_element("poison", {"burst_delay": 3.0, "burst_damage_scale": 0.35}, 100, fire_tree, shooter)
	burst._tick_fate_statuses(2.9)
	_check(burst.current_hp == 10000, "逆毒延迟前不伤害")
	burst._tick_fate_statuses(0.1)
	_check(burst.current_hp == 9965, "逆毒三秒35%单次爆发")
	var copy_tree := _tree()
	_card(copy_tree, "fate_barrage_copy")
	var copy := _weapon(copy_tree)
	_fire(copy)
	_check(shots.size() == 1, "正位第二波不可即时发射")
	copy._process(0.11)
	_check(shots.size() == 2 and shots[1].damage == int(base_damage * 0.6), "延迟第二波末端")
	var back_tree := _tree()
	_card(back_tree, "fate_barrage_copy", true)
	var back := _weapon(back_tree)
	_fire(back)
	_check(shots.size() == 2 and shots[0].direction.dot(shots[1].direction) < -0.95, "逆位后向波")
	var mobile_tree := _tree()
	_card(mobile_tree, "fate_turret_on_land", true)
	var mobile := _fire(_weapon(mobile_tree))
	mobile.position = Vector3(6, 0, 0)
	mobile._become_turret()
	var distance := mobile.position.distance_to(shooter.position)
	mobile._tick_turret(0.1)
	_check(mobile.position.distance_to(shooter.position) < distance and mobile._turret_remaining < 4.0, "移动炮台跟随且四秒寿命")
	var attachment_tree := _tree()
	attachment_tree.mount(attachment_tree.root, AssemblyNode.SlotType.TACTICAL, BlueprintRegistry.create_assembly_node("attach_fan"))
	_card(attachment_tree, "fate_attachment_parasite", true)
	var triggers := [0]
	attachment_tree.attachment_triggered.connect(func(_event, _attachment, _target): triggers[0] += 1)
	attachment_tree.claim_attachment_trigger("hit", enemy)
	attachment_tree.claim_attachment_trigger("reload")
	attachment_tree.claim_attachment_trigger("reload")
	_check(triggers[0] == 1, "逆位配件仅换弹触发且三秒冷却")
	# 副枪、携枪、恶魔必须使用真实发射消费者，而非效果字典存在性。
	for reversed in [false, true]:
		var carry_tree := _tree()
		_card(carry_tree, "fate_bullet_carry_gun", reversed)
		var carry_weapon := _weapon(carry_tree)
		carry_weapon.set_damage_multiplier(0.92)
		var carrier := _fire(carry_weapon)
		var child_count := _projectile_count()
		carrier._tick_attached_gun(1.0)
		_check(_projectile_count() == child_count + (0 if reversed else 1), "携枪持续/命中模式隔离")
		if reversed:
			carrier._apply_fate_on_hit(enemy)
			carrier._apply_fate_on_hit(enemy)
			_check(_projectile_count() == child_count + 1, "逆位携枪只命中发射一次")
		var devil_tree := _tree()
		_card(devil_tree, "fate_gun_on_gun")
		_card(devil_tree, "fate_out_of_control", reversed)
		var devil := _weapon(devil_tree)
		devil.spread = 0.0
		var normal_main := _fire(devil)
		_check(normal_main.damage == base_damage and normal_main.direction.dot(Vector3.FORWARD) > 0.999, "恶魔不得改主弹")
		_check(shots.size() == 2 and shots[1].damage == int(int(base_damage * 0.5) * 1.3), "恶魔仅附枪增伤")
		if reversed:
			_check(shots[1].direction.dot(Vector3.FORWARD) >= cos(PI / 4.0), "逆恶魔90度锥形")
		else:
			devil._process(1.0 / devil.fire_rate)
			_check(shots.size() == 3, "恶魔附枪射速倍率")
		var bounce_tree := _tree()
		_card(bounce_tree, "fate_bounce_bullet", reversed)
		var bouncing := _fire(_weapon(bounce_tree))
		var bounce_damage := bouncing.damage
		bouncing._hit_surface(Vector3.BACK)
		_check(bouncing._bounces_left == (0 if reversed else 2) and bouncing.damage == int(bounce_damage * (1.35 if reversed else 0.85)), "墙弹次数和倍率")
		var chain_tree := _tree()
		_card(chain_tree, "fate_chain_lightning", reversed)
		var chaining := _fire(_weapon(chain_tree))
		var chain_first := _enemy(Vector3(30, 0, 0))
		var chain_next := _enemy(Vector3(32, 0, 0))
		chaining._apply_chain_lightning(chain_first)
		_check(chain_next.current_hp == 10000 - int(base_damage * (0.5 if reversed else 0.7)), "连锁末端伤害")
		chain_first.remove_from_group("enemy_3d")
		chain_next.remove_from_group("enemy_3d")
		var turret_tree := _tree()
		_card(turret_tree, "fate_turret_on_land", reversed)
		var turret := _fire(_weapon(turret_tree))
		turret._become_turret()
		_check(turret._turret_remaining == (4.0 if reversed else 8.0), "炮台正逆寿命")
		var element_tree := _tree()
		_card(element_tree, "fate_fuse_fire", reversed)
		var fire := _fire(_weapon(element_tree))
		fire._flight_base_damage = 100
		var burn := _enemy(Vector3(40, 0, 0))
		fire._apply_fate_on_hit(burn)
		burn._tick_fate_statuses(1.0)
		_check(burn.current_hp == (9996 if reversed else 9992) and burn._slow_factor == 1.0, "火焰正逆每秒伤害且不减速")
		var pierce_tree := _tree()
		_card(pierce_tree, "fate_armor_pierce", reversed)
		var piercing := _fire(_weapon(pierce_tree))
		var shield := _enemy(Vector3(45, 0, 0))
		shield.enemy_kind = "shielded"
		seed(54321)
		piercing.direction = Vector3.BACK
		piercing._hit_target(shield)
		_check(shield.current_hp == 10000 - (int(int(base_damage * 1.15) * 2 * 0.32) if reversed else int(base_damage * 1.5)), "力量盾面伤害")
	var seventh_tree := _tree()
	_card(seventh_tree, "fate_every_seventh")
	var seventh := _weapon(seventh_tree)
	seventh._fire_sequence = 6
	var seventh_bullet := _fire(seventh)
	var splash_primary := _enemy(Vector3(60, 0, 0))
	var splash_secondary := _enemy(Vector3(61, 0, 0))
	seventh_bullet.global_position = splash_primary.global_position
	seventh_bullet._hit_target(splash_primary)
	_check(splash_secondary.current_hp < 10000, "第七发命中敌人触发爆炸")
	var player := preload("res://scenes/Player3D.tscn").instantiate() as Player3D
	add_child(player)
	player.set_physics_process(false)
	player.position = Vector3(100, 0, 0)
	for reversed in [false, true]:
		var tower_tree := _tree()
		_card(tower_tree, "fate_explode_reload", reversed)
		var tower := _weapon(tower_tree)
		tower.reparent(player)
		var attracted := _enemy(Vector3(103, 0, 0))
		tower.current_ammo = 1
		tower.request_reload()
		_check(is_equal_approx(tower.reload_time, baseline.reload_time + (0.2 if reversed else 0.5)), "高塔正逆额外换弹耗时")
		_check(attracted.current_hp < 10000, "高塔换弹真实伤害")
		_check(attracted._external_velocity.x < 0.0 if reversed else attracted._external_velocity == Vector3.ZERO, "逆高塔吸引，正位不吸引")
	var source_tree := _tree()
	var source_root := BlueprintRegistry.create_assembly_node("bp_shotgun")
	source_root.mount(AssemblyNode.SlotType.BULLET, BlueprintRegistry.create_assembly_node("mod_bullet_explosive"))
	var actual_source := WeaponAssemblyTree.new(source_root)
	trees.append(actual_source)
	var magic := FateCardPresets.gun_on_gun()
	var explicit_targets: Array[AssemblyNode] = [source_tree.root, source_root]
	_check(FateCardEngine.apply_card(magic, source_tree, explicit_targets).success, "真实所选附枪应用")
	var real_secondary := _weapon(source_tree)
	_fire(real_secondary)
	_check(shots.size() == baseline.projectile_count + int(source_root.base_stats["bullet_count"]), "所选散弹枪投射物数量")
	_check("explosive" in shots[1].bullet_tags and "explosive" not in shots[0].bullet_tags, "附枪弹种不泄漏主枪")
	var overheat_tree := _tree()
	_card(overheat_tree, "fate_overclock")
	var overheated := _weapon(overheat_tree)
	_check(overheat_tree.get_overheat_penalty() == 1.0, "超频未开火不得过热")
	_fire(overheated)
	_check(overheat_tree.get_overheat_penalty() == 1.5, "首发累计过热")
	_fire(overheated)
	_check(overheat_tree.get_overheat_penalty() == 2.25, "第二发继续累计过热")
	var reload_attachment_tree := _tree()
	reload_attachment_tree.mount(reload_attachment_tree.root, AssemblyNode.SlotType.TACTICAL, BlueprintRegistry.create_assembly_node("attach_fan"))
	_card(reload_attachment_tree, "fate_attachment_parasite", true)
	var reload_attachment := _weapon(reload_attachment_tree)
	reload_attachment.reparent(player)
	var pulled := _enemy(Vector3(104, 0, 0))
	reload_attachment.current_ammo = 1
	reload_attachment._finish_reload()
	_check(pulled._external_velocity.x < 0.0, "配件换弹完成真实吸引消费者")
	pulled._external_velocity = Vector3.ZERO
	reload_attachment.current_ammo = 1
	reload_attachment._finish_reload()
	_check(pulled._external_velocity == Vector3.ZERO, "配件换弹三秒冷却阻断实际效果")
	var hit_attachment_tree := _tree()
	hit_attachment_tree.mount(hit_attachment_tree.root, AssemblyNode.SlotType.TACTICAL, BlueprintRegistry.create_assembly_node("attach_fan"))
	_card(hit_attachment_tree, "fate_attachment_parasite")
	var hit_attachment := _fire(_weapon(hit_attachment_tree))
	hit_attachment._apply_fate_on_hit(pulled)
	_check(pulled._external_velocity.x < 0.0, "配件命中真实吸引消费者")
	var reject_tree := _tree()
	_check(not FateCardEngine.apply_card(FateCardPresets.attachment_parasite(), reject_tree).success, "无真实配件必须拒绝，不能假造分裂")
	var critical_shooter := CriticalShooter.new()
	add_child(critical_shooter)
	var saved_shooter := shooter
	shooter = critical_shooter
	_fire(mount)
	_check(shots[0].critical and shots[1].critical, "角色暴击接口同时覆盖主副枪")
	shooter = saved_shooter
	var poison_target := _enemy(Vector3(70, 0, 0))
	for index in range(6):
		poison_target.apply_fate_element("poison", {"max_stacks": 5, "dot_damage_per_stack": 0.05}, 100, fire_tree, shooter)
	poison_target._tick_fate_statuses(1.0)
	_check(poison_target.current_hp == 9975, "正毒上限五层每层5%")
	var elite_frost := _enemy(Vector3(71, 0, 0))
	elite_frost.elite_modifier_id = "Elite.Test"
	elite_frost.apply_fate_element("ice", {"freeze_duration": 0.5, "freeze_duration_elite": 0.25}, 100, fire_tree, shooter)
	_check(elite_frost._fate_freeze_remaining == 0.25, "精英冻结减半")
	var far_tree := _tree()
	_card(far_tree, "fate_living_bullet", true)
	var far := _fire(_weapon(far_tree))
	far.position = Vector3(180, 0.7, 0)
	var close_target := _enemy(Vector3(180, 0, -3))
	var far_target := _enemy(Vector3(180, 0, -10))
	_check(far._nearest_target() == far_target, "逆位追踪最远目标")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 0.5)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	add_child(wall)
	wall.position = Vector3(180, 1, -6)
	for child in get_children():
		if child is Projectile3D or child is Enemy3D:
			child.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(far._nearest_target() == close_target, "最远不可见目标被墙遮挡时跳过")
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	for tree in trees:
		tree.free()
	if failures.is_empty():
		print("FATE_WEAPON_COMPLETION_OK")
	else:
		print("FATE_WEAPON_COMPLETION_FAILED ", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
