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
	# 2026-11-20 定价口径：售价只按稀有度取固定值，不因余额、门次、种子或卡片特判变化。
	# 旧「三张全买不起就把最低价压到余额」的保底降价已下线，这里反向钉住它不许回流。
	var fixed_prices: Array = Dungeon3D.FATE_PRICE_BY_RARITY
	var probe: Array[FateCard] = FateCardPresets.draw_offer(3, null, "expedition_01")
	dungeon.set("_door_fate_choices", probe)
	var fixed_quotes: Dictionary = {}
	for card: FateCard in probe:
		var expected := int(fixed_prices[clampi(int(card.card_rarity), 0, fixed_prices.size() - 1)])
		fixed_quotes[card.get_stable_card_id()] = expected
		check(int(dungeon.call("_fate_price", card)) == expected, "固定售价未按稀有度取值：%s" % card.get_stable_card_id())
		check(int(dungeon.call("_fate_fixed_price", card)) == expected, "固定价函数与价格表不一致：%s" % card.get_stable_card_id())
	dungeon.set("_fate_door_quote", fixed_quotes.duplicate(true))
	GameManager.currency = 0
	check(not dungeon.has_method("_ensure_affordable_fate_choice"), "保底降价入口回流了（空钱包会把最低价压成 0）")
	for card: FateCard in probe:
		check(
			int(dungeon.call("_fate_price", card)) == int(fixed_quotes[card.get_stable_card_id()]),
			"余额归零后报价发生变化：%s" % card.get_stable_card_id()
		)
	# 同稀有度必须同价：价格不随卡片身份、门序号或种子改变。
	var rarity_price: Dictionary = {}
	for card: FateCard in FateCardPresets.door_reward_presets():
		rarity_price[int(card.card_rarity)] = int(fixed_prices[clampi(int(card.card_rarity), 0, fixed_prices.size() - 1)])
	for probe_door in range(8):
		dungeon.set("_fate_door_offer_id", probe_door)
		dungeon.set("_fate_offer_price_index", probe_door)
		dungeon.set("_fate_door_quote", {})
		for card: FateCard in FateCardPresets.door_reward_presets():
			check(
				int(dungeon.call("_fate_price", card)) == int(rarity_price[int(card.card_rarity)]),
				"同稀有度跨门/种子价格漂移：%s" % card.get_stable_card_id()
			)
	dungeon.set("_fate_door_offer_id", 0)
	dungeon.set("_fate_offer_price_index", 0)
	dungeon.set("_fate_door_quote", fixed_quotes.duplicate(true))
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
