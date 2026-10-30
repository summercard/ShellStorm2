extends Node
## 远征03 商店商品与价格实测（2026-10-30）。
##
## 只为回答一个问题：**一层 40~60 枚金币，商店里有几件东西买得起？**
## 这个数字决定「统一金币」该给多少 —— 价格全部高于一层收入的话，
## 商店就是个看得见摸不着的摆设，"通路打通"没有意义。

const LOOT := preload("res://src/game/LootModule.gd")


func _ready() -> void:
	var loot: LootModule = LOOT.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261030
	for tier in [1, 2]:
		var goods: Array[Dictionary] = loot.generate_merchant_goods(tier, 6)
		print("\n=== merchant_tier <= %d · %d 件 ===" % [tier, goods.size()])
		var prices: Array[int] = []
		for value in goods:
			var item := value as Dictionary
			var price := int(item.get("price", 0))
			prices.append(price)
			print("  %-28s %-10s %4d 枚" % [
				str(item.get("id", "?")), str(item.get("name", "")), price
			])
		prices.sort()
		if not prices.is_empty():
			var sum := 0
			for p in prices:
				sum += p
			print("  价格区间 %d ~ %d 枚，中位 %d，均值 %.0f"
				% [prices[0], prices[prices.size() - 1],
				   prices[prices.size() / 2], float(sum) / float(prices.size())])
	get_tree().quit(0)
