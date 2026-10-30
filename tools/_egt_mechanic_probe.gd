extends Node
## 远征03 全量怪物机制自检（2026-10-30）。
##
## 起因：业主报「这只怪瞬移后打不中它、它的子弹也打不中玩家」，并要「检查每只怪」。
## 那次的根因是**随机落点没有房内约束**（`_is_point_inside_room_hint` 用圆形近似判矩形房，
## 且半径随当前位置自增 ⇒ 怪一路飘出房，实测 84% 落点在房外、最远 99.84m）。
## 这类 bug 的共同特征是：**不报错、不崩、只是行为悄悄失效**。
##
## 所以本探针不测"代码跑不跑得起来"（那有别的探针），只测**机制参数是否自洽**，
## 逐只怪套同一组判据：
##
##   ① `attack_style` 必须是已知枚举 —— 拼错一个字母，整只怪退化成默认行为且无报错。
##   ② **随机落点半径必须装得进它实际出现的房间** —— `blink.radius_m` / `wander.radius_m`
##      超过房间半边长时，落点必然出界（blink 是直接改 transform，出界就是穿墙）。
##   ③ 会开火的怪：`projectile_range` 必须 > `range` —— 否则子弹在射程内就自毁，
##      表现为"怪在射程边缘开火、子弹在玩家面前消失"。
##   ④ 会开火的怪：`projectile_speed` > 0。
##   ⑤ `damage` 与攻击方式自洽：不攻击的（枪歌者 / 抓握大师）必须为 0，
##      其余必须 > 0 —— 两者反过来都是静默失效。
##   ⑥ 行为键与骨架配对：`attack_style = grab` 必须有 `grab` 键，`orbit` 必须有 `orbit`…
##
## 用法：godot --headless --path . --scene res://tools/_egt_mechanic_probe.tscn

const LEVEL_ID := "expedition_03"
const PLAN_PATH := "res://data/level_plans/expedition_03/level_plan.json"
const BOX_DIR := "res://data/spawn_boxes"
const FLOW_DIR := "res://data/level_plans/expedition_03/flows"

## `attack_style` 的合法值。漏列会让「新骨架没登记」被误报成 OK，所以与 `_perform_attack` 同源。
const ATTACK_STYLES := [
	"volley", "contact", "explode", "rush", "support", "grab", "orbit", "chance", "flee",
]
## 骨架 → 必须存在的 profile 键。缺了就是"骨架认得、参数没给"。
const STYLE_REQUIRED_KEYS := {
	"grab": "grab",
	"orbit": "orbit",
	"flee": "flee",
	"support": "support_buff",
}
## 声明了这些键的怪一定有"选点"行为，落点半径必须装得进房间。
const PLACEMENT_KEYS := ["blink", "wander"]

var _failures: Array[String] = []


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _ready() -> void:
	print("=== EGT_MECHANIC_PROBE 远征03 全量机制自检 ===")
	var room_by_kind := _rooms_by_kind()
	var injector := preload("res://src/map/MonsterInjector.gd").new()
	var kinds: Array[String] = []
	for kind in injector.BASE_ENEMY_TYPES.keys():
		if str(kind).begins_with("egt_"):
			kinds.append(str(kind))
	kinds.sort()
	print("待检 %d 只，编成覆盖 %d 只（有 %d 只不在任何刷怪盒里）"
		% [kinds.size(), room_by_kind.size(), kinds.size() - room_by_kind.size()])

	var header := "%-24s %-9s %5s %5s %6s %s"
	print("\n" + header % ["怪", "骨架", "damage", "射程", "弹程", "落点/备注"])
	for kind in kinds:
		_check_kind(kind, room_by_kind.get(kind, []))

	_finish()


func _check_kind(kind: String, rooms: Array) -> void:
	var profile: Dictionary = Enemy3D.profile_for(kind)
	if profile.is_empty():
		_check(false, "%s 没有 profile（PROFILES 漏登记）" % kind)
		return
	var style := str(profile.get("attack_style", ""))
	var damage := int(profile.get("damage", 0))
	var attack_range := float(profile.get("range", 0.0))
	var proj_range := float(profile.get("projectile_range", 0.0))
	var proj_speed := float(profile.get("projectile_speed", 0.0))
	var notes: Array[String] = []

	# ① 骨架合法
	if not ATTACK_STYLES.has(style):
		_check(false, "%s 的 attack_style=[%s] 不在已知枚举内（拼错即静默退化）" % [kind, style])

	# ⑥ 骨架 ↔ 行为键配对
	var required := str(STYLE_REQUIRED_KEYS.get(style, ""))
	if not required.is_empty() and not profile.has(required):
		_check(false, "%s 是 %s 骨架，但 profile 缺 `%s` 键（骨架认得、参数没给）"
			% [kind, style, required])

	# ② 落点半径 vs 实际房间
	for key in PLACEMENT_KEYS:
		if not profile.has(key):
			continue
		var spec: Dictionary = profile.get(key, {})
		var radius := float(spec.get("radius_m", 0.0))
		# `on_attack` 的 blink（枪法师）是出手后换位，同样会出界，一并检。
		if radius <= 0.0:
			continue
		if rooms.is_empty():
			notes.append("%s r=%.1f（不在编成里，无法对照房间）" % [key, radius])
			continue
		var smallest := 1e9
		var smallest_room := ""
		for value in rooms:
			var room := value as Dictionary
			var size := room.get("size", Vector2.ZERO) as Vector2
			var half := minf(size.x, size.y) * 0.5
			if half < smallest:
				smallest = half
				smallest_room = str(room.get("id", "?"))
		notes.append("%s r=%.1f / 最紧房 %.1fm" % [key, radius, smallest])
		# 留 1.5m（墙厚 + 怪半径量级）。超了就是"落点必然出界"。
		if radius > smallest - 1.5:
			_check(false,
				"%s 的 %s.radius_m=%.1f 超过它所在最紧房间（%s）的半边长 %.1fm —— 落点会穿墙"
				% [kind, key, radius, smallest_room, smallest])

	# ③④ 会开火的怪：弹程与弹速
	var shoots := profile.has("volley") or profile.has("volley_alt") or style == "volley" \
		or profile.has("orbit")
	if shoots:
		if proj_range <= 0.0:
			_check(false, "%s 会开火但没有 projectile_range（子弹只有 1 秒寿命、飞几米就自毁）" % kind)
		elif proj_range <= attack_range:
			_check(false,
				"%s 的 projectile_range=%.1f ≤ range=%.1f —— 子弹在射程内自毁，玩家看到的是「空射」"
				% [kind, proj_range, attack_range])
		if proj_speed <= 0.0:
			_check(false, "%s 会开火但 projectile_speed=0" % kind)

	# ⑤ damage 自洽
	var no_attack := kind in ["egt_gunsinger", "egt_gripmaster"]
	if no_attack and damage != 0:
		_check(false, "%s 不造成伤害，但 damage=%d（会被当成攻击怪处理）" % [kind, damage])
	if not no_attack and damage <= 0:
		_check(false, "%s 是攻击怪，但 damage=%d（打了不掉血）" % [kind, damage])

	print("%-24s %-9s %5d %5.1f %6.1f %s"
		% [kind, style, damage, attack_range, proj_range, "；".join(notes)])


## kind → 该怪可能出现的房间列表（从 `spawn_roster` + 刷怪盒 + flow 节点尺寸反查）。
##
## 为什么必须按"实际房间"而不是全局最紧：`gun_fairy` 的 `wander.radius_m = 8`，
## 若拿全层最小的 15×15 入口房（半边长 7.5）当判据就会误报；
## 而它实际只出现在 25×25 以上的房间。判据要跟着编成走。
func _rooms_by_kind() -> Dictionary:
	var plan := _load_json(PLAN_PATH)
	var roster: Dictionary = plan.get("spawn_roster", {}) as Dictionary
	var by_node: Dictionary = roster.get("by_node", {}) as Dictionary
	var by_kind: Dictionary = roster.get("by_kind", {}) as Dictionary
	# box_id → [kind...]
	var box_kinds := {}
	var box_dir := DirAccess.open(BOX_DIR)
	if box_dir == null:
		return {}
	for file_name in box_dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var box := _load_json("%s/%s" % [BOX_DIR, file_name])
		var kinds: Array[String] = []
		for spawn_value in box.get("spawns", []):
			kinds.append(str((spawn_value as Dictionary).get("type", "")))
		box_kinds[file_name.trim_suffix(".json")] = kinds

	# node_id/kind → [房间尺寸...]
	var node_rooms := {}
	var flow_dir := DirAccess.open(FLOW_DIR)
	if flow_dir == null:
		return {}
	for file_name in flow_dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var flow := _load_json("%s/%s" % [FLOW_DIR, file_name])
		for node_value in flow.get("nodes", []):
			var node := node_value as Dictionary
			var node_id := str(node.get("node_id", ""))
			var node_kind := str(node.get("kind", ""))
			var size_value: Variant = node.get("size_m", [])
			var size := Vector2.ZERO
			if size_value is Array and (size_value as Array).size() >= 2:
				size = Vector2(float((size_value as Array)[0]), float((size_value as Array)[1]))
			if size == Vector2.ZERO:
				continue
			var record := {"id": node_id, "size": size}
			if not node_rooms.has(node_id):
				node_rooms[node_id] = []
			(node_rooms[node_id] as Array).append(record)
			var kind_key := "kind:%s" % node_kind
			if not node_rooms.has(kind_key):
				node_rooms[kind_key] = []
			# 同 kind 的兜底要覆盖所有该 kind 节点里最紧的那个。
			(node_rooms[kind_key] as Array).append(record)

	var result := {}
	for table in [[by_node, ""], [by_kind, "kind:"]]:
		var source: Dictionary = table[0] as Dictionary
		var prefix := str(table[1])
		for key in source.keys():
			var record: Dictionary = source[key] as Dictionary
			var rooms_for_node: Array = node_rooms.get(prefix + str(key), []) as Array
			if rooms_for_node.is_empty():
				continue
			for box_value in record.get("boxes", []):
				var kinds: Array = box_kinds.get(str(box_value), []) as Array
				for kind_value in kinds:
					var monster_kind := str(kind_value)
					if not result.has(monster_kind):
						result[monster_kind] = []
					# 去重：同一个 kind 在多张 flow 里可能重复出现同一尺寸。
					for room_value in rooms_for_node:
						var room := room_value as Dictionary
						var size := room.get("size", Vector2.ZERO) as Vector2
						var key_text := "%s@%s" % [str(room.get("id", "")), str(size)]
						var bucket: Array = result[monster_kind]
						var seen := false
						for existing in bucket:
							if "%s@%s" % [
								str((existing as Dictionary).get("id", "")),
								str((existing as Dictionary).get("size", Vector2.ZERO))
							] == key_text:
								seen = true
								break
						if not seen:
							bucket.append(room)
	return result


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _finish() -> void:
	if _failures.is_empty():
		print("\nEGT_MECHANIC_PROBE_OK 33 只怪的机制参数全部自洽")
		get_tree().quit(0)
		return
	print("\nEGT_MECHANIC_PROBE_FAIL 共 %d 项：" % _failures.size())
	for line in _failures:
		print("  - %s" % line)
	get_tree().quit(1)
