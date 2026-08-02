extends Node

class DummyPlayer:
	extends CharacterBody2D
	var total_damage := 0

	func take_damage(amount: int) -> void:
		total_damage += amount


const CASES: Array[Dictionary] = [
	{"kind": "melee_chaser", "ai": "chase", "shape": EnemyShape.ShapeType.CHASER, "color": Color(0.95, 0.28, 0.24)},
	{"kind": "ranged_caster", "ai": "ranged", "shape": EnemyShape.ShapeType.RANGED, "color": Color(0.62, 0.35, 1.0)},
	{"kind": "summoner", "ai": "summoner", "shape": EnemyShape.ShapeType.SUMMONER, "color": Color(0.95, 0.70, 0.16)},
	{"kind": "shielded", "ai": "chase", "shape": EnemyShape.ShapeType.TANK, "color": Color(0.35, 0.62, 0.95)},
	{"kind": "exploder", "ai": "bomber", "shape": EnemyShape.ShapeType.BOMBER, "color": Color(1.0, 0.58, 0.14)},
	{"kind": "ambusher", "ai": "trapper", "shape": EnemyShape.ShapeType.TRAPPER, "color": Color(0.78, 0.28, 0.88)},
]


func _ready() -> void:
	var failures: Array[String] = []
	var enemy_scene := load("res://scenes/Enemy.tscn") as PackedScene
	if enemy_scene == null:
		_finish(["Enemy scene does not load"])
		return

	var dummy := DummyPlayer.new()
	dummy.name = "DummyPlayer"
	dummy.add_to_group("player")
	add_child(dummy)

	var enemies: Dictionary = {}
	var signatures: Dictionary = {}
	var collision_radii: Dictionary = {}
	var visual_extents: Dictionary = {}
	for i in range(CASES.size()):
		var case := CASES[i]
		var enemy := enemy_scene.instantiate() as CharacterBody2D
		enemy.name = str(case["kind"]).to_pascal_case()
		enemy.set("awareness_enabled", false)
		enemy.set("ai_type", str(case["ai"]))
		enemy.set("speed", 90.0 if str(case["kind"]) == "ambusher" else 60.0)
		enemy.call("set_enemy_data", {
			"enemy_type": case["kind"],
			"ai_type": case["ai"],
			"emoji": "legacy",
			"color": case["color"],
			"scale": 1.0,
		})
		add_child(enemy)
		enemy.position = Vector2(float(i) * 180.0, 0.0)
		enemy.set("player_ref", dummy)
		enemy.set_physics_process(false)
		enemies[case["kind"]] = enemy

		var expected_shape := int(case["shape"])
		if int(enemy.get("enemy_shape")) != expected_shape:
			failures.append("%s did not resolve to its tactical silhouette" % case["kind"])
		var legacy_shape := enemy.get_node_or_null("Shape") as Polygon2D
		var legacy_emoji := enemy.get_node_or_null("Emoji") as Label
		if legacy_shape == null or legacy_shape.visible or legacy_emoji == null or legacy_emoji.visible:
			failures.append("%s still renders legacy polygon/emoji presentation" % case["kind"])
		if legacy_shape != null and legacy_shape.color != case["color"]:
			failures.append("%s lost its configured biome/accent color before ready" % case["kind"])

		var renderer := enemy.get_node_or_null("AvatarRenderer") as EnemyAvatarRenderer
		if renderer == null:
			failures.append("%s has no replaceable AvatarRenderer" % case["kind"])
		else:
			var signature := renderer.get_silhouette_signature()
			if signature.is_empty() or signatures.has(signature):
				failures.append("%s does not have a unique silhouette signature" % case["kind"])
			signatures[signature] = true
			var profile := renderer.get_profile_snapshot()
			visual_extents[case["kind"]] = float(profile.get("visual_extent", 0.0))

		var collision := enemy.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collision == null or not collision.shape is CircleShape2D:
			failures.append("%s has no circular gameplay collision profile" % case["kind"])
		else:
			collision_radii[case["kind"]] = (collision.shape as CircleShape2D).radius
		var hp_bg := enemy.get_node_or_null("HPBarBG") as Control
		var expected_extent := float(EnemyShape.get_profile(expected_shape).get("visual_extent", 0.0))
		if hp_bg == null or hp_bg.offset_bottom > -(expected_extent + 4.0):
			failures.append("%s health bar overlaps its silhouette" % case["kind"])

	_check_size_order(failures, visual_extents, "visual")
	_check_size_order(failures, collision_radii, "collision")
	if signatures.size() != CASES.size():
		failures.append("Six enemy roles do not produce six visual identities")
	# 离开当前场景 _ready 的子节点搭建阶段，命中飘字才可安全挂到 SceneTree.root。
	await get_tree().process_frame

	# 命中必须驱动新渲染器，而不是只闪烁已隐藏的旧 Shape。
	var chaser: CharacterBody2D = enemies["melee_chaser"]
	var chaser_renderer := chaser.get_node("AvatarRenderer") as EnemyAvatarRenderer
	chaser.set("current_hp", 20)
	chaser.set("max_hp", 20)
	chaser.call("take_damage", 1, false, Vector2.RIGHT)
	if chaser_renderer.get_hit_phase() <= 0.0:
		failures.append("Enemy hit does not drive avatar compression feedback")
	var old_chaser_radius := float(collision_radii["melee_chaser"])
	chaser.call("add_modifier", "巨大化", 1)
	var scaled_collision := chaser.get_node("CollisionShape2D") as CollisionShape2D
	if (scaled_collision.shape as CircleShape2D).radius <= old_chaser_radius * 1.5:
		failures.append("Huge modifier does not scale the semantic collision profile")

	# Ranged：子弹生成前先进入短暂蓄力和瞄准线。
	var ranged: CharacterBody2D = enemies["ranged_caster"]
	dummy.global_position = ranged.global_position + Vector2(280, 0)
	ranged.call("_ranged_shoot", Vector2.RIGHT)
	var ranged_renderer := ranged.get_node("AvatarRenderer") as EnemyAvatarRenderer
	if not bool(ranged.call("get_attack_windup_state").get("ranged", false)):
		failures.append("Ranged enemy fires without entering windup state")
	if not ranged_renderer.is_telegraphing() or ranged_renderer.get_telegraph_kind() != "ranged_shot":
		failures.append("Ranged windup has no readable renderer telegraph")
	await get_tree().create_timer(0.25).timeout
	if bool(ranged.call("get_attack_windup_state").get("ranged", true)):
		failures.append("Ranged windup does not resolve into a shot")
	if _count_enemy_projectiles() < 1:
		failures.append("Ranged telegraph never resolves into an enemy projectile")

	# Bomber：进入半径后有 0.62s 停步膀胀，而非同帧爆炸。
	var bomber: CharacterBody2D = enemies["exploder"]
	dummy.total_damage = 0
	dummy.global_position = bomber.global_position + Vector2(50, 0)
	bomber.call("_behavior_bomber", 0.01)
	var bomber_state: Dictionary = bomber.call("get_attack_windup_state")
	if not bool(bomber_state.get("bomber", false)) or float(bomber_state.get("bomber_remaining", 0.0)) < 0.6:
		failures.append("Bomber has no full detonation warning window")
	bomber.call("_behavior_bomber", 0.30)
	if dummy.total_damage != 0:
		failures.append("Bomber deals damage before its warning window ends")
	bomber.call("_behavior_bomber", 0.33)
	if dummy.total_damage <= 0:
		failures.append("Bomber warning does not resolve into proximity damage")

	# Trapper：破土前保持静止，0.38s 后才开始扑击。
	var trapper: CharacterBody2D = enemies["ambusher"]
	dummy.global_position = trapper.global_position + Vector2(80, 0)
	trapper.call("_behavior_trapper", 0.01)
	var trapper_state: Dictionary = trapper.call("get_attack_windup_state")
	if not bool(trapper_state.get("trapper", false)) or trapper.velocity != Vector2.ZERO:
		failures.append("Trapper does not pause for its emerge telegraph")
	trapper.call("_behavior_trapper", 0.20)
	if bool(trapper.get("_triggered")):
		failures.append("Trapper activates before 0.35 seconds")
	trapper.call("_behavior_trapper", 0.19)
	trapper.call("_behavior_trapper", 0.01)
	if not bool(trapper.get("_triggered")) or trapper.velocity.length() <= 1.0:
		failures.append("Trapper does not lunge after its emerge window")

	for projectile in _enemy_projectiles():
		projectile.queue_free()
	for enemy in enemies.values():
		if is_instance_valid(enemy):
			enemy.queue_free()
	dummy.queue_free()
	var damage_layer := get_tree().root.get_node_or_null("DamageNumbersLayer")
	if damage_layer != null:
		damage_layer.queue_free()
	var synth = AudioManager.get("_synth") if AudioManager != null else null
	if synth != null:
		var stream_player = synth.get("_stream_player")
		if stream_player is AudioStreamPlayer:
			stream_player.stop()
			stream_player.stream = null
	await get_tree().process_frame
	await get_tree().process_frame
	_finish(failures)


func _check_size_order(failures: Array[String], values: Dictionary, label: String) -> void:
	var ordered := ["shielded", "summoner", "exploder", "ranged_caster", "ambusher", "melee_chaser"]
	for i in range(ordered.size() - 1):
		if float(values.get(ordered[i], 0.0)) <= float(values.get(ordered[i + 1], 0.0)):
			failures.append("Enemy %s size order is not tactically readable at %s -> %s" % [label, ordered[i], ordered[i + 1]])


func _enemy_projectiles() -> Array[Node]:
	var result: Array[Node] = []
	for child in get_children():
		var script := child.get_script() as Script
		if script != null and script.resource_path == "res://src/bullet/EnemyProjectile.gd":
			result.append(child)
	return result


func _count_enemy_projectiles() -> int:
	return _enemy_projectiles().size()


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("ENEMY_ECOLOGY_FLOW_OK: six silhouettes, ordered body/collision scale, hit response, and fair ranged/bomber/trapper windups")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
