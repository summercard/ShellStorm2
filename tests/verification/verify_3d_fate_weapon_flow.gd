extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	await _verify_behavior_card("追踪弹", FateCardPresets.living_bullet(), "homing", true, failures)
	await _verify_behavior_card("落地炮台", FateCardPresets.turret_on_land(), "spawn_turret_on_land", true, failures)
	await _verify_behavior_card("回家看看", FateCardPresets.home_on_land(), "home_on_land", true, failures)
	await _verify_behavior_card("连锁闪电", FateCardPresets.chain_lightning(), "chain_lightning", true, failures)
	await _verify_behavior_card("弹跳弹", FateCardPresets.bounce_bullet(), "bounce", true, failures)
	await _verify_behavior_card("弹幕模式", FateCardPresets.barrage_copy(), "copy_fire", true, failures)
	await _verify_behavior_card("火焰融合", FateCardPresets.fuse_fire(), "fuse_damage", true, failures)
	await _verify_behavior_card("冰霜融合", FateCardPresets.fuse_frost(), "freeze_duration", 0.5, failures)
	await _verify_behavior_card("火力暴食", FateCardPresets.gluttony(), "size_growth", true, failures)
	await _verify_behavior_card("换弹爆炸", FateCardPresets.explode_on_reload(), "explode_on_reload", true, failures)
	await _verify_behavior_card("每第七发", FateCardPresets.every_seventh(), "every_nth_fire", 7, failures)
	await _verify_secondary_gun(failures)
	await _verify_attached_gun_and_uncontrolled(failures)
	await _verify_numeric_cards(failures)
	if failures.is_empty():
		print("3D_FATE_WEAPON_FLOW_OK: homing, bounce, chain, fuse/freeze, turret, return, growth, reload explosion, copy fire and mounted guns pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_behavior_card(
	label: String,
	card: FateCard,
	key: String,
	expected: Variant,
	failures: Array[String]
) -> void:
	var player := await _make_player()
	var result := FateCardGameBridge.apply_card(card)
	await get_tree().process_frame
	if not bool(result.get("success", false)):
		failures.append("3D fate card cannot apply: %s (%s)" % [label, result.get("message", "")])
	else:
		var behavior := player.get_weapon_snapshot().get("fate_behavior", {}) as Dictionary
		if not behavior.has(key):
			failures.append("3D adapter lost %s behavior key: %s" % [label, key])
		elif expected is float and not is_equal_approx(float(behavior[key]), float(expected)):
			failures.append("3D adapter value mismatch for %s/%s" % [label, key])
		elif not expected is float and behavior[key] != expected:
			failures.append("3D adapter value mismatch for %s/%s" % [label, key])
	await _discard_player(player)


func _verify_secondary_gun(failures: Array[String]) -> void:
	var player := await _make_player()
	var result := FateCardGameBridge.apply_card(FateCardPresets.gun_on_gun())
	await get_tree().process_frame
	if not bool(result.get("success", false)) or int(player.get_weapon_snapshot().get("secondary_gun_count", 0)) < 1:
		failures.append("Gun-on-gun fate is not routed into 3D secondary fire")
	await _discard_player(player)


func _verify_attached_gun_and_uncontrolled(failures: Array[String]) -> void:
	var player := await _make_player()
	var attached := FateCardGameBridge.apply_card(FateCardPresets.bullet_carry_gun())
	var unstable := FateCardGameBridge.apply_card(FateCardPresets.out_of_control())
	await get_tree().process_frame
	var behavior := player.get_weapon_snapshot().get("fate_behavior", {}) as Dictionary
	if not bool(attached.get("success", false)) or not behavior.has("attached_gun"):
		failures.append("Bullet-carry-gun fate is not routed into flying 3D projectiles")
	if not bool(unstable.get("success", false)) or not bool(behavior.get("uncontrolled_gun", false)):
		failures.append("Out-of-control mounted gun fate is not routed into 3D aim behavior")
	await _discard_player(player)


func _verify_numeric_cards(failures: Array[String]) -> void:
	var player := await _make_player()
	var base_fire_rate := float(player.get_weapon_snapshot().get("fire_rate", 0.0))
	var overclock := FateCardGameBridge.apply_card(FateCardPresets.overclock())
	await get_tree().process_frame
	if not bool(overclock.get("success", false)) or float(player.get_weapon_snapshot().get("fire_rate", 0.0)) <= base_fire_rate:
		failures.append("Overclock fate does not increase the 3D gun fire rate")
	if player.get_weapon_tree().get_overheat_penalty() <= 1.0:
		failures.append("Overclock fate does not preserve its 3D incoming-damage penalty")
	await _discard_player(player)


func _make_player() -> Player3D:
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.position = Vector3(150, 0, 150)
	add_child(player)
	await get_tree().process_frame
	FateCardGameBridge.set_player(player)
	return player


func _discard_player(player: Player3D) -> void:
	player.queue_free()
	await get_tree().process_frame
