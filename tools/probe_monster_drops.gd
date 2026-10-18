extends SceneTree
## 一次性探针：导出「全部物品 × 掉落池权重」与「各池成员汇总」，
## 用于回答「怪物到底能掉什么、枪械从哪几个池出来」。
## 用法：godot --headless --path . --script res://tools/probe_monster_drops.gd

const POOL_REGISTRY := preload("res://src/rewards/RewardPoolRegistry.gd")


func _init() -> void:
	var registry := ItemRegistry.get_instance()
	var items: Array = []
	for item in registry.get_all_items():
		var weights: Dictionary = item.get("floor_loot_weights", {})
		var chances: Dictionary = item.get("floor_loot_chances", {})
		var tags: Array = item.get("tags", [])
		var is_weapon := false
		for tag in tags:
			if str(tag) == "weapon":
				is_weapon = true
				break
		items.append({
			"id": str(item.get("id", "")),
			"name": str(item.get("name", "")),
			"type": str(item.get("type", "")),
			"subtype": str(item.get("subtype", "")),
			"rarity": str(item.get("rarity", "")),
			"tags": tags,
			"is_weapon": is_weapon,
			"loot_table_tier": item.get("loot_table_tier", null),
			"weights": weights,
			"chances": chances,
		})
	items.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))

	var pools: Dictionary = {}
	for pool_id in POOL_REGISTRY.pool_ids():
		var members: Array = []
		for item in items:
			var weights: Dictionary = item["weights"]
			if weights.has(pool_id):
				members.append({
					"item_id": item["id"],
					"name": item["name"],
					"is_weapon": item["is_weapon"],
					"weight": float(weights[pool_id]),
					"chance": (item["chances"] as Dictionary).get(pool_id, -1.0),
				})
		var info := POOL_REGISTRY.get_pool(pool_id)
		pools[pool_id] = {
			"info": info,
			"members": members,
			"weapon_members": members.filter(func(m): return bool(m["is_weapon"])),
		}

	var payload := {"items": items, "pools": pools}
	var out_path := "res://outputs/monster_drop_census.json"
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	print("MONSTER_DROP_CENSUS_OK items=%d pools=%d -> %s" % [items.size(), pools.size(), out_path])
	quit(0)
