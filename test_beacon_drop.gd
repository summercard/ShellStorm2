## beacon_drop_test - 在项目上下文中测试信标掉落
## 用法: godot --headless --script test_beacon_drop.gd
extends SceneTree

func _init():
	# 等待 autoload 就绪
	await get_tree().process_frame
	await get_tree().process_frame
	
	var loot = LootModule.get_instance()
	var tables = ["loot_floor_1_2", "loot_floor_3_4", "loot_floor_5", "boss_floor_1", "scavenge_floor_1", "scavenge_floor_2", "scavenge_floor_3"]
	var total_rolls = 0
	var total_beacons = 0
	
	for t in tables:
		var beacons_in_table = 0
		var rolls = 50
		for i in range(rolls):
			var items = loot.generate_loot(t, 5)
			for item in items:
				if item.get("id") == "item_beacon":
					beacons_in_table += 1
					break
		total_rolls += rolls
		total_beacons += beacons_in_table
		print("Table %s: %d/%d rolls had a beacon" % [t, beacons_in_table, rolls])
	
	print("Overall: %d/%d (%s) rolls had a beacon" % [total_beacons, total_rolls, str(snapped(100.0*total_beacons/total_rolls, 0.1)) + "%"])
	quit()