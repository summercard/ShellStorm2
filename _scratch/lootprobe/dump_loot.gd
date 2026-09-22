extends SceneTree
## 探针：导出 ItemRegistry 指定掉落池的完整行（含蓝图 Tier 门槛），TSV 输出便于直接成表。
## 运行：godot_console.exe --headless --path <project> --script res://_scratch/lootprobe/dump_loot.gd

const ItemRegistryScript := preload("res://src/base/ItemRegistry.gd")

const POOLS := [
	"loot_floor_1_2",
	"loot_floor_3_4",
	"loot_floor_5",
	"loot_abyss",
	"scavenge_floor_1",
	"elite_floor_1",
	"boss_floor_1",
]


func _init() -> void:
	var registry: ItemRegistry = ItemRegistryScript.new()
	for pool in POOLS:
		var rows: Array = registry.get_loot_table(pool)
		var total := 0.0
		for r in rows:
			total += float(r.get("loot_weight", 0.0))
		rows.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
		for r in rows:
			var item_type := str(r.get("type", ""))
			var subtype := str(r.get("subtype", ""))
			var tier := int(r.get("loot_table_tier", 0))
			var bp_tier := int(r.get("blueprint_loot_tier", -1))
			var effective := bp_tier if (item_type == "blueprint" and bp_tier >= 0) else tier
			var category := "other"
			match subtype:
				"gun_body": category = "gunbody"
				"bullet": category = "bullet"
				"muzzle", "stock", "scope", "magazine", "external", "mutator": category = "attachment"
			var w := float(r.get("loot_weight", 0.0))
			var pct := (w / total * 100.0) if total > 0.0 else 0.0
			print("%s\t%s\t%s\t%s\t%s\t%s\t%d\t%d\t%s\t%.2f\t%.2f" % [
				pool, r.get("id", "?"), r.get("name", "?"), item_type, subtype,
				r.get("rarity", "?"), effective, int(r.get("price", 0)),
				category, w, pct,
			])
		print("##TOTAL\t%s\t%d\t%.2f" % [pool, rows.size(), total])
	quit()
