extends Node

const DUNGEON: PackedScene = preload("res://scenes/Dungeon3D.tscn")
var observations: Array[Dictionary] = []

func record(label: String, values: Dictionary) -> void:
	observations.append({"check": label, "values": values})
	print("FATE_AUDIT_OBSERVATION ", label, " ", JSON.stringify(values))

func card(id: String, reversed := true) -> FateCard:
	var value := FateCardPresets.get_by_card_id(id)
	value.set_orientation(FateCard.Orientation.REVERSED if reversed else FateCard.Orientation.UPRIGHT)
	return value

func _ready() -> void:
	var dungeon := DUNGEON.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 8052026
	add_child(dungeon)
	await get_tree().process_frame
	await get_tree().physics_frame
	dungeon.set_process(false)
	dungeon.player.set_physics_process(false)
	var player := dungeon.player
	player.current_hp = 50
	var hp_before := player.max_hp
	var result := FateCardGameBridge.apply_card(card("fate_moon_vitality"))
	record("女祭司逆位", {"success": result.get("success"), "max_hp_before": hp_before, "max_hp_after": player.max_hp, "hp_after": player.current_hp})
	var damage_before := player.weapon.damage
	result = FateCardGameBridge.apply_card(card("fate_moon_power"))
	record("恋人逆位", {"success": result.get("success"), "damage_before": damage_before, "damage_after": player.weapon.damage, "actual_multiplier": player.weapon.damage_multiplier, "stored_multiplier": player.get_character_fate_snapshot().get("weapon_damage_multiplier")})
	for id in ["fate_sun_currency", "fate_sun_trial", "fate_sun_extraction"]:
		var before := dungeon.get_world_fate_snapshot()
		result = FateCardGameBridge.apply_card(card(id))
		record(card(id).card_name + "逆位", {"success": result.get("success"), "before": before, "after": dungeon.get_world_fate_snapshot()})
	var before_damage := player.weapon.damage
	var before_speed := player.weapon.bullet_speed
	result = FateCardGameBridge.apply_card(card("fate_scale_node"))
	record("权杖王牌逆位", {"success": result.get("success"), "damage_before": before_damage, "damage_after": player.weapon.damage, "speed_before": before_speed, "speed_after": player.weapon.bullet_speed, "fate_visual_multiplier": player.get_weapon_snapshot().get("fate_visual_multiplier")})
	FateCardGameBridge.apply_card(card("fate_moon_room_heal", false))
	FateCardGameBridge.apply_card(card("fate_moon_ammo", false))
	var rooms: Dictionary = dungeon.get("_room_by_id")
	var chosen: DungeonRoom3D = null
	for value in rooms.values():
		var room := value as DungeonRoom3D
		if room.room_type in GameDesignConfig.ROOM_TYPES_WITH_HOSTILES and not (dungeon.get("_spawned_rooms") as Dictionary).has(room.room_id):
			chosen = room
			break
	if chosen != null:
		player.global_position = chosen.global_position + Vector3(0, 0.05, 0)
		player.current_hp = 50
		player.weapon.current_ammo = 0
		dungeon.call("_on_room_entered", chosen)
		record("新敌对房进房回血补弹", {"room": chosen.room_id, "hp_before": 50, "hp_after": player.current_hp, "ammo_before": 0, "ammo_after": player.weapon.current_ammo, "magazine": player.weapon.magazine_size, "room_marked_spawned": (dungeon.get("_spawned_rooms") as Dictionary).has(chosen.room_id)})
		var direct: Dictionary = player.on_fate_room_entered()
		record("进房消费者直接调用对照", {"result": direct, "hp_after": player.current_hp, "ammo_after": player.weapon.current_ammo})
		chosen.cleared = true
		var queued_before: int = (dungeon.get("_room_fate_wave_queued") as Dictionary).size()
		result = FateCardGameBridge.apply_card(card("fate_reinforce", false))
		record("清房抽到星币王牌", {"success": result.get("success"), "queued_before": queued_before, "queued_after": (dungeon.get("_room_fate_wave_queued") as Dictionary).size()})
	else:
		record("新敌对房进房回血补弹", {"not_executed": "no unspawned hostile room"})
	result = FateCardGameBridge.apply_card(card("fate_bless_dead"))
	player.current_hp = int(player.max_hp * 0.9)
	dungeon.call("_tick_bless_dead", 31.0)
	var high_triggered: bool = dungeon.get("_bless_dead_triggered")
	player.current_hp = int(player.max_hp * 0.5)
	dungeon.call("_tick_bless_dead", 31.0)
	record("圣杯五逆位血线方向", {"success": result.get("success"), "90_percent_hp_triggered": high_triggered, "50_percent_hp_triggered": dungeon.get("_bless_dead_triggered"), "damage_multiplier": player.weapon.damage_multiplier})
	var catalog: Array[Dictionary] = []
	for value in FateCardPresets.playable_presets():
		var c := value as FateCard
		c.set_orientation(FateCard.Orientation.UPRIGHT)
		var upright_description := c.description
		var upright_effect := c.effect.duplicate(true)
		c.set_orientation(FateCard.Orientation.REVERSED)
		catalog.append({"id": c.get_stable_card_id(), "name": c.card_name, "scope": FateCard.scope_name(c.scope), "upright_description": upright_description, "upright_effect": upright_effect, "reversed_description": c.description, "reversed_effect": c.effect.duplicate(true)})
	var output := FileAccess.open("res://outputs/fate_effect_audit_20261008/runtime_observations.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"evidence_kind": "targeted consumer probe, not full gameplay acceptance", "observations": observations, "catalog": catalog}, "\t"))
	output.close()
	dungeon.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("FATE_EFFECT_AUDIT_PROBE_DONE: observations recorded; this is not a design-conformance pass")
	get_tree().quit(0)
