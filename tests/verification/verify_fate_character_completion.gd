extends Node3D

const PLAYER := preload("res://scenes/Player3D.tscn")
const ENEMY := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
var player: Player3D
var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func card(id: String, reversed := false) -> FateCard:
	var value := FateCardPresets.get_by_card_id(id)
	value.set_orientation(FateCard.Orientation.REVERSED if reversed else FateCard.Orientation.UPRIGHT, 0.75 if reversed else 0.25)
	return value

func apply(id: String, reversed := false) -> void:
	var result := FateCardGameBridge.apply_card_instance(card(id, reversed))
	check(bool(result.get("success", false)), "应用 " + id + str(reversed) + str(result))

func reset() -> void:
	FateCardGameBridge.reset_run_state()
	player.current_hp = 100
	player.is_invincible = false
	player._invincible_remaining = 0.0
	player._state_machine.stop()
	player._state_machine.start("idle")
	GameManager.currency = 200

func hit(amount: int) -> int:
	player.is_invincible = false
	var before := player.current_hp
	player.take_damage(amount)
	return before - player.current_hp

func _run() -> void:
	check(OS.get_environment("APPDATA").contains("fate_completion_20261008"), "启动前隔离APPDATA")
	check(OS.get_environment("LOCALAPPDATA").contains("fate_completion_20261008"), "启动前隔离LOCALAPPDATA")
	player = PLAYER.instantiate() as Player3D
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	FateCardGameBridge.set_player(player)
	for reversed in [false, true]:
		reset()
		player.current_hp = 40
		apply("fate_moon_vitality", reversed)
		check(player.max_hp == (90 if reversed else 120) and player.current_hp == (90 if reversed else 60), "女祭司真实生命" + str(reversed))
		reset()
		apply("fate_moon_power", reversed)
		player.set_damage_multiplier("verification", 1.1)
		check(is_equal_approx(player.weapon.get("damage_multiplier"), (0.92 if reversed else 1.12) * 1.1), "恋人乘法" + str(reversed))
		check(is_equal_approx(player.get_fate_critical_chance_bonus(), 0.15 if reversed else 0.0), "恋人暴击接口")
		player.remove_damage_buff("verification")
		reset()
		apply("fate_moon_stride", reversed)
		# 默认出厂枪为 bp_sprinkler（机枪族），持枪移速惩罚 1.5m/s；移速 =（4.5 - 1.5）× 命运倍率。
		check(player.get_active_weapon_gun_id() == "bp_sprinkler", "隐者移速前置：默认持出厂机枪")
		check(is_equal_approx(player.get_move_speed(), (Player3D.SPEED - Player3D.WEAPON_FAMILY_MOVE_PENALTY["machinegun"]) * (0.92 if reversed else 1.12)), "隐者移速")
		player.begin_fate_dash_invulnerability()
		check(is_equal_approx(player._invincible_remaining, Player3D.DASH_DURATION + (0.12 if reversed else 0.0)), "隐者无敌")
		reset()
		apply("fate_moon_dash", reversed)
		check(is_equal_approx(player.get_dash_cooldown_duration(), Player3D.DASH_COOLDOWN * (1.2 if reversed else 0.8)), "冲刺冷却")
		check(is_equal_approx(player.get_dash_speed() * player.get_dash_duration(), Player3D.DASH_SPEED * Player3D.DASH_DURATION * (1.4 if reversed else 1.0)), "冲刺距离")
		player._state_machine.transition_to("dashing", true)
		check(is_equal_approx(player._invincible_remaining, Player3D.DASH_DURATION * (1.4 if reversed else 1.0)), "冲刺状态实际无敌 reversed=%s actual=%s state=%s" % [reversed, player._invincible_remaining, player.get_state_machine_state()])
		player._state_machine.transition_to("idle", true)
		player._update_invincibility(Player3D.DASH_DURATION + 0.001)
		check(player.is_invincible == reversed, "冲刺结束后的剩余无敌")
		reset()
		apply("fate_moon_guard", reversed)
		var enemy := ENEMY.instantiate() as Enemy3D
		add_child(enemy)
		enemy.set_physics_process(false)
		enemy.max_hp = 1000
		enemy.current_hp = 1000
		player.notify_attacked_by(enemy)
		check(hit(50) == (54 if reversed else 44), "倒吊人受伤倍率")
		check(enemy.current_hp == (992 if reversed else 1000), "反射真实来源HP")
		player.current_hp = 100
		hit(10)
		check(enemy.current_hp == (992 if reversed else 1000), "无来源不误反射上次敌人")
		enemy.queue_free()
		reset()
		apply("fate_moon_first_hit", reversed)
		player.on_fate_room_entered("moon")
		for index in range(5):
			player.current_hp = 100
			var expected := (8 if index in [1, 2, 3] else 10) if reversed else (5 if index == 0 else 10)
			check(hit(10) == expected, "月亮真实第%d击 %s" % [index + 1, reversed])
		reset()
		apply("fate_moon_last_stand", reversed)
		player.current_hp = 10
		hit(100)
		check(player.current_hp == (25 if reversed else 1), "审判回血/保命")
		check(GameManager.currency == (150 if reversed else 200), "审判扣魂")
		check(int(player.get_character_fate_snapshot()["last_stand_charges"]) == 0, "审判一次消费")
		reset()
		apply("fate_moon_room_heal", reversed)
		player.current_hp = 50
		player.is_invincible = true
		player.on_fate_room_entered("heal")
		check(player.current_hp == (47 if reversed else 56), "进房真实回血/失血")
		player.on_fate_room_entered("heal")
		check(player.current_hp == (47 if reversed else 56), "进房幂等")
		player.on_fate_room_cleared("heal")
		check(player.current_hp == (59 if reversed else 56), "清房真实回血")
		check(player.on_fate_room_cleared("heal") == 0, "清房幂等")
		reset()
		apply("fate_moon_elite_heal", reversed)
		player.current_hp = 50
		player.on_fate_elite_combat_started("elite")
		check(player.on_fate_elite_combat_started("elite") == 0, "精英进战幂等")
		check(hit(25) == (5 if reversed else 25), "护盾实际吸伤")
		player.on_fate_elite_killed()
		check(player.current_hp == 45, "精英击杀正回血逆不回血")
		reset()
		apply("fate_moon_ammo", reversed)
		player.weapon.current_ammo = 0
		player.on_fate_room_entered("ammo")
		check(player.weapon.current_ammo == (0 if reversed else ceili(player.weapon.magazine_size * 0.2)), "进房弹匣")
		var duration := player.weapon.reload_time
		check(player.weapon.request_reload(), "真实换弹开始")
		check(is_equal_approx(float(player.weapon.get_reload_snapshot()["duration"]), duration / (1.25 if reversed else 1.0)), "首次换弹时长")
		player.weapon._process(duration)
		check(player.weapon.current_ammo == player.weapon.magazine_size, "真实换弹完成")
		player.weapon.current_ammo = 0
		player.weapon.request_reload()
		check(is_equal_approx(float(player.weapon.get_reload_snapshot()["duration"]), duration), "第二次不再快换弹")
		player.weapon.cancel_reload()
		reset()
		apply("fate_bless_dead", reversed)
		player.current_hp = 90 if reversed else 20
		player.update_fate_survival(20.0)
		player.current_hp = 50
		player.update_fate_survival(1.0)
		player.current_hp = 90 if reversed else 20
		player.update_fate_survival(29.0)
		check(is_equal_approx(player.weapon.get("damage_multiplier"), 1.0), "祝福脱离血线重置连续时间")
		player.update_fate_survival(1.0)
		check(is_equal_approx(player.weapon.get("damage_multiplier"), 1.08 if reversed else 1.1), "祝福正确血线消费者")
		player.update_fate_survival(30.0)
		check(is_equal_approx(player.weapon.get("damage_multiplier"), 1.16 if reversed else 1.2), "祝福叠层")
	reset()
	apply("fate_moon_last_stand", true)
	GameManager.currency = 49
	player.current_hp = 10
	hit(100)
	check(player.current_hp == 0 and GameManager.currency == 49 and player.get_character_fate_snapshot()["last_stand_charges"] == 1, "不足魂不白送救助不消费牌")
	reset()
	var trigger := MapFateTriggers.new()
	add_child(trigger)
	for index in range(20):
		trigger._on_kill_recorded()
	check(FateCardGameBridge.get_card_count() == 0, "没有愚者不白送命运")
	apply("fate_mark_enemy", true)
	check(FateCardGameBridge.get_card_count() == 1, "愚者应用不立即发牌")
	for index in range(9):
		trigger._on_kill_recorded()
	check(FateCardGameBridge.get_card_count() == 1, "愚者从抽卡后计数")
	# 固定已抽定卡验证正式身份/刻印/记录事务，随后仍由十杀正式消费者驱动随机奖励。
	FateCardGameBridge._pending_character_rewards.append({"card": card("fate_armor_pierce", true), "currency_cost": 30})
	var slots_before := player.get_equipped_weapon_instance().fate_upgrades.size()
	var money_before := GameManager.currency
	var granted := FateCardGameBridge.retry_pending_character_reward()
	check(bool(granted.get("success", false)), "愚者奖励正式Bridge成功")
	check(player.get_equipped_weapon_instance().fate_upgrades.size() == slots_before + 1 and GameManager.currency == money_before - 30, "愚者真实占槽扣魂")
	for index in range(11):
		trigger._on_kill_recorded()
	check(int((player.get_character_fate_snapshot()["kill_rules"] as Array)[0]["kills"]) == 20, "愚者每十杀持续计数")
	check(FateCardGameBridge.get_card_count() + FateCardGameBridge.get_pending_character_rewards().size() >= 4, "两轮十杀真实应用或明确待领取")
	reset()
	apply("fate_mark_enemy")
	check(is_equal_approx(float(player.get_character_fate_snapshot()["kill_rules"][0]["grant_probability"]), 0.5), "愚者正位50%规则")
	var missing_source := FateCardGameBridge.apply_card_instance(card("fate_gun_on_gun"))
	check(not bool(missing_source["success"]), "无来源枪明确拒绝")
	var source_slots := player.get_equipped_weapon_instance().fate_upgrades.size()
	var sourced := FateCardGameBridge.apply_card_instance(card("fate_gun_on_gun"), player.weapon_tree.root)
	check(bool(sourced.get("success", false)) and player.get_equipped_weapon_instance().fate_upgrades.size() == source_slots + 1, "显式真实来源传Engine并提交槽")
	var blocked := FateCardGameBridge.apply_card_instance(card("fate_gun_on_gun"), player.weapon_tree.root)
	check(not bool(blocked.get("success", false)) and player.get_equipped_weapon_instance().fate_upgrades.size() == source_slots + 1, "失败不消耗命运槽")
	var previous_currency := GameManager.currency
	FateCardGameBridge._pending_character_rewards.append({"card": card("fate_gun_on_gun"), "currency_cost": 30})
	var failed_reward := FateCardGameBridge.retry_pending_character_reward()
	check(not bool(failed_reward["success"]) and GameManager.currency == previous_currency and FateCardGameBridge.get_pending_character_rewards().size() == 1, "愚者来源缺失保留固定牌且退魂")
	reset()
	apply("fate_moon_power", true)
	var first_tree := player.weapon_tree
	first_tree.growth_stacks = 3
	first_tree.set("_overheat_shots", 4)
	first_tree.set("_crit_damage_shots", 2)
	player.weapon.set("_reload_first_shot", true)
	var item := WeaponInstance.from_item(ItemRegistry.get_instance().get_item("weapon_rifle")).to_item_dictionary()
	check(bool(player.equip_weapon_item_to_slot(item, 1)["success"]), "装备第二枪")
	check(bool(player.switch_weapon_slot(1)["success"]), "切到第二枪")
	check(player.weapon_tree != first_tree and first_tree.growth_stacks == 3, "旧弹来源树不转为新枪")
	check(is_equal_approx(player.weapon.get("damage_multiplier"), 0.92), "切枪保留角色倍率")
	check(bool(player.switch_weapon_slot(0)["success"]), "切回第一枪")
	check(player.weapon_tree == first_tree and first_tree.growth_stacks == 3 and first_tree.get("_overheat_shots") == 4 and first_tree.get("_crit_damage_shots") == 2, "切枪保留成长热与王后奖励")
	check(bool(player.weapon.get("_reload_first_shot")), "切枪保留换弹首发")
	for index in range(6):
		apply("fate_moon_power", true)
	var shots: Array[Projectile3D] = []
	player.weapon.projectile_spawned.connect(func(projectile: Projectile3D):
		shots.append(projectile)
		projectile.set_physics_process(false))
	player.weapon.current_ammo = player.weapon.magazine_size
	player.weapon._cooldown = 0.0
	player.weapon.try_fire(Vector3.FORWARD, player)
	check(not shots.is_empty() and shots[0].critical, "恋人暴击真实投射物消费者")
	for shot in shots:
		shot.queue_free()
	reset()
	check(first_tree.growth_stacks == 0 and first_tree.get("_overheat_shots") == 0 and first_tree.get("_crit_damage_shots") == 0, "新局清理武器临时命运状态")
	check(player.max_hp == 100 and player.get_fate_critical_chance_bonus() == 0.0 and player.get_character_fate_snapshot()["kill_rules"].is_empty(), "新局重置角色状态")
	trigger.queue_free()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("FATE_CHARACTER_COMPLETION_", "OK" if failures.is_empty() else "FAILED", " checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
