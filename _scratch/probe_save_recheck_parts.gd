extends "res://_scratch/probe_stutter_recheck_20261004.gd"

func _run() -> void:
	GameTimeManager.set_process(false)
	var results: Array[Dictionary] = []
	for source: String in ["user://base_save.json", "user://old_report_copy.json"]:
		var raw: Variant = AtomicJsonStore.load_dictionary(source)
		var unpacked := ProfileSaveService.unpack(raw)
		BaseManager.data = BaseData.from_dict(unpacked["payload"])
		BaseManager.save_path = "user://parts_%s.json" % source.get_file()
		var rows: Array[Dictionary] = []
		for i in range(20):
			rows.append(_measure_save_parts())
		results.append({"source": source, "measurements": rows})
	var f := FileAccess.open("res://outputs/stutter_save_parts_20261004.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("SAVE_PARTS_COMPLETE ", OS.get_user_data_dir())
	get_tree().quit()
