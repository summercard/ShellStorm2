extends SceneTree
## 只读探针：导出全部已注册物品（供"怪物掉落表"填表用），以及怪物种清单。
## 运行：godot --headless --path <PROJ> --script res://_scratch/lootprobe/dump_items.gd

func _init() -> void:
	var registry = load("res://src/base/ItemRegistry.gd").get_instance()
	print("##ITEMS_HEAD\tid\tname\ttype\tsubtype\trarity\tprice\tstack")
	var items: Array = registry.get_all_items()
	var sorted_items: Array = []
	for entry in items:
		sorted_items.append(entry)
	sorted_items.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	for entry in sorted_items:
		var d: Dictionary = entry
		print("##ITEM\t%s\t%s\t%s\t%s\t%s\t%s\t%s" % [
			str(d.get("id", "")), str(d.get("name", "")), str(d.get("type", "")),
			str(d.get("subtype", d.get("sub_type", ""))), str(d.get("rarity", "")),
			str(d.get("price", "")), str(d.get("max_stack", d.get("stack", ""))),
		])
	print("##ITEMS_TOTAL\t%d" % sorted_items.size())

	var injector = load("res://src/map/MonsterInjector.gd")
	print("##MONSTERS_HEAD\ttype\tname\thp_base\tdamage_base\tspeed")
	for key in injector.BASE_ENEMY_TYPES.keys():
		var m: Dictionary = injector.BASE_ENEMY_TYPES[key]
		print("##MONSTER\t%s\t%s\t%s\t%s\t%s" % [
			str(key), str(m.get("name", "")), str(m.get("hp_base", "")),
			str(m.get("damage_base", "")), str(m.get("speed", "")),
		])

	var pools = load("res://src/rewards/RewardPoolRegistry.gd")
	print("##POOLS_HEAD\tpool_id\tname\tusage\ttier\troll\tcap\tstatus")
	for key in pools.POOLS.keys():
		var p: Dictionary = pools.POOLS[key]
		print("##POOL\t%s\t%s\t%s\t%s\t%s\t%s\t%s" % [
			str(key), str(p.get("name", "")), str(p.get("usage", "")), str(p.get("tier", "")),
			str(p.get("roll", "")), str(p.get("cap", "")), str(p.get("status", "")),
		])
	print("##DONE")
	quit(0)
