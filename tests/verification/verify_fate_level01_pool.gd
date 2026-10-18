extends Node3D
const Policy := preload("res://src/weapons/FateOfferPolicy.gd")
var failures: Array[String] = []
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL: ", label)
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	var seen: Dictionary = {}
	var generic_reverse := 0
	for seed_value in range(256):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var cards := FateCardPresets.draw_offer(3, rng, "expedition_01")
		check(cards.size() == 3, "full 21 pool provides three")
		var local: Dictionary = {}
		for card in cards:
			check(Policy.allows("expedition_01", card.get_stable_card_id()) and not card.is_reversed(), "01 scoped upright")
			check(not local.has(card.get_stable_card_id()), "unique offer")
			local[card.get_stable_card_id()] = true
			seen[card.get_stable_card_id()] = true
		for card in FateCardPresets.draw_offer(3, rng, "training"):
			generic_reverse += int(card.is_reversed())
	check(seen.size() == 21, "all 21 reachable")
	check(generic_reverse > 100, "non01 retains reverse")
	check(not Policy.allows("expedition_01", "fate_sword_ace"), "design-only rejected")
	check(not Policy.allows("expedition_01", "fate_mark_enemy"), "outside identity rejected")
	var dungeon := load("res://scenes/ExpeditionLevel01_3D.tscn").instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for i in range(4): await get_tree().process_frame
	FateCardGameBridge.set_player(dungeon.player)
	check(FateCardGameBridge.get_offer_level_id() == "expedition_01", "Bridge active player host")
	for i in range(16):
		dungeon.set("_fate_door_offer_id", i)
		var offer: Array = dungeon.call("_gate_expedition_fate_offer")
		check(offer.size() == 3, "full 21 pool shows three per gate, no rarity narrowing")
		for card: FateCard in offer:
			check(not card.is_reversed() and Policy.allows("expedition_01", card.get_stable_card_id()), "formal gate")
	# 门后保底：三张全买不起时，最低那张必须落到当前余额（0 也要成立）。
	if dungeon.uses_dynamic_fate_economy():
		var probe: Array[FateCard] = FateCardPresets.draw_offer(3, null, "expedition_01")
		dungeon.set("_door_fate_choices", probe)
		var quotes: Dictionary = {}
		for card: FateCard in probe:
			quotes[card.get_stable_card_id()] = 9999
		dungeon.set("_fate_door_quote", quotes)
		GameManager.currency = 0
		dungeon.call("_ensure_affordable_fate_choice")
		var lowest := 9999
		for card: FateCard in probe:
			lowest = mini(lowest, int(dungeon.call("_fate_price", card)))
		check(lowest == 0, "affordable guarantee did not drop the cheapest card to the wallet")
	dungeon.set("_door_fate_choices", FateCardPresets.draw_offer(3, null, "expedition_01"))
	var saved: Dictionary = dungeon.call("_export_door_fate_snapshot")
	check(bool(dungeon.call("_import_door_fate_snapshot", saved)), "same snapshot accepted")
	check(dungeon.call("_export_door_fate_snapshot")["cards"] == saved["cards"], "no reroll on resume")
	# Historical frozen offers are grandfathered, not silently flipped/replaced.
	saved["cards"][0]["stable_card_id"] = "fate_mark_enemy"
	saved["cards"][0]["orientation"] = "REVERSED"
	check(bool(dungeon.call("_import_door_fate_snapshot", saved)), "legacy frozen offer survives")
	var restored: Array = dungeon.get("_door_fate_choices")
	check(restored[0].is_reversed() and restored[0].get_stable_card_id() == "fate_mark_enemy", "legacy identity retained")
	dungeon.free()
	print("FATE_LEVEL01_POOL checks=%d failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
