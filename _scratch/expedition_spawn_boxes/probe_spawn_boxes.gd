extends Node
## 探针：远征01 触发盒迁移的**独立复算**（不复用 LevelPlanValidator 的放置判据）。
##
## 为什么另写一套：同一份代码既生产又校验 = 自证。这里用不同写法重算盒矩形与房矩形，
## 逐房比对「设计源 → 槽位 → 生成房表」的透传一致性，并统计最紧余量（排除零容差偶然通过）。

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const LOADER := preload("res://src/map/LevelPlanLoader.gd")
const CATALOG := preload("res://src/map/SpawnBoxCatalog.gd")

const LEVEL := "expedition_01"
const SAMPLES := 300


func _ready() -> void:
	var level_plan := LOADER.load_level_plan(LEVEL)
	var policy := level_plan.get("generation_policy", {}) as Dictionary
	var templates := LOADER.load_room_templates(LEVEL)
	var normalized := LOADER.normalize_floor(LEVEL, 0)
	print("floor spawn_boxes_only=%s" % str(normalized.get("spawn_boxes_only", false)))

	var source: Dictionary = {}
	for v in normalized.get("rooms", []):
		var r := v as Dictionary
		source[str(r.get("key", ""))] = r
	print("—— 设计源放置基线 ——")
	for k in source.keys():
		var rr := source[k] as Dictionary
		var p := rr.get("spawn_placements", []) as Array
		if not p.is_empty():
			print("  %-8s n=%d boxes_only=%s" % [
				str(k), p.size(), str(rr.get("spawn_boxes_only", false))])

	var failures: Array[String] = []
	var checked_rooms := 0
	var checked_boxes := 0
	var min_margin := INF
	var min_desc := ""
	var template_seen: Dictionary = {}
	for index in range(SAMPLES):
		var run_seed := 900000 + index * 6151
		var gen := GENERATOR._generate_constrained_floor(
			LEVEL, 0, run_seed, normalized, policy, templates
		)
		if gen.is_empty():
			failures.append("seed %d 生成空" % run_seed)
			continue
		for v in gen.get("rooms", []):
			var room := v as Dictionary
			var key := str(room.get("key", ""))
			var placements := room.get("spawn_placements", []) as Array
			var src := source.get(key, {}) as Dictionary
			var src_placements := src.get("spawn_placements", []) as Array
			if src_placements.size() != placements.size():
				failures.append("seed %d %s 透传条数 %d != 设计源 %d"
					% [run_seed, key, placements.size(), src_placements.size()])
				continue
			if src_placements.is_empty():
				continue
			if not bool(room.get("spawn_boxes_only", false)):
				failures.append("seed %d %s spawn_boxes_only 未下发" % [run_seed, key])
			checked_rooms += 1
			var tpl := str(room.get("template_id", ""))
			template_seen[tpl] = int(template_seen.get(tpl, 0)) + 1
			var center := room["center"] as Vector2
			var size := room["size"] as Vector2
			var room_min := center - size * 0.5
			var room_max := center + size * 0.5
			for bi in range(placements.size()):
				var pl := placements[bi] as Dictionary
				var want := src_placements[bi] as Dictionary
				if str(pl.get("box", "")) != str(want.get("box", "")):
					failures.append("seed %d %s[%d] box 被改写" % [run_seed, key, bi])
				if _v2(pl.get("center_m", [])) != _v2(want.get("center_m", [])):
					failures.append("seed %d %s[%d] center 被改写" % [run_seed, key, bi])
				var box := CATALOG.load_box(str(pl.get("box", "")))
				if box.is_empty():
					failures.append("seed %d %s[%d] 盒子加载失败" % [run_seed, key, bi])
					continue
				var bs := _v2(pl.get("size_m", box.get("size_m", [])))
				var rad := deg_to_rad(float(pl.get("rotation_deg", 0.0)))
				var ex := absf(bs.x * cos(rad)) + absf(bs.y * sin(rad))
				var ez := absf(bs.x * sin(rad)) + absf(bs.y * cos(rad))
				var bc := center + _v2(pl.get("center_m", []))
				var bmin := bc - Vector2(ex, ez) * 0.5
				var bmax := bc + Vector2(ex, ez) * 0.5
				var margin := minf(
					minf(bmin.x - room_min.x, room_max.x - bmax.x),
					minf(bmin.y - room_min.y, room_max.y - bmax.y))
				if margin < 0.0:
					failures.append("seed %d %s[%d] 盒越界 margin=%.3f room=%s box=%s"
						% [run_seed, key, bi, margin, str(size), str(bs)])
				if margin < min_margin:
					min_margin = margin
					min_desc = "%s tpl=%s room=%s box=%s off=%s" % [
						key, tpl, str(size), str(bs), str(_v2(pl.get("center_m", [])))]
				checked_boxes += 1
			var enc := room.get("encounter", {}) as Dictionary
			if not enc.is_empty():
				var stages := enc.get("stages", []) as Array
				var sched: Dictionary = {}
				for si in range(stages.size()):
					var st := stages[si] as Dictionary
					for bv in (st.get("boxes", []) as Array):
						var x := int(bv)
						if x < 0 or x >= placements.size():
							failures.append("seed %d %s stage%d 下标 %d 越界"
								% [run_seed, key, si, x])
						elif sched.has(x):
							failures.append("seed %d %s 下标 %d 重复" % [run_seed, key, x])
						else:
							sched[x] = true
				for i in range(placements.size()):
					if not sched.has(i):
						failures.append("seed %d %s 实例 %d 未被排到" % [run_seed, key, i])

	print("\n=== 独立复算（%d 种子）===" % SAMPLES)
	print("有放置的房次=%d 盒次=%d" % [checked_rooms, checked_boxes])
	print("最紧余量=%.3f m  (%s)" % [min_margin, min_desc])
	print("—— 出现放置的房型分布 ——")
	var ks := template_seen.keys()
	ks.sort()
	for k in ks:
		print("  x%-5d %s" % [int(template_seen[k]), str(k)])
	if failures.is_empty():
		print("PROBE_SPAWN_BOXES_OK")
	else:
		print("PROBE_SPAWN_BOXES_FAILED n=%d" % failures.size())
		for f in failures:
			print("  FAIL %s" % f)
	print("PROBE_DONE")
	get_tree().quit(0 if failures.is_empty() else 1)


func _v2(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
