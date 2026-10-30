@tool
extends RefCounted
## Read-only presentation tags projected from the authoritative component catalog.

static func kit(row: Dictionary) -> String:
	if not str(row.get("kit_tag", "")).is_empty():
		return str(row["kit_tag"])
	var path := str(row.get("prefab_path", ""))
	var prefix := "远征01 / " if path.contains("/expedition/") else "共享 / "
	# 易碎陈设单独成组：它们不是建筑构件，玩家要打碎、房间要记账，
	# 与墙体/地砖混在同一套件里会被当成"结构件"随手刷在走道中间。
	if str(row.get("slot_role", "")) == "breakable_clutter":
		return prefix + "易碎陈设"
	for pair in [["boss_room_02", "Boss房02"], ["boss_room", "Boss房01"], ["office_room", "办公室"],
		["db_room", "数据库"], ["l_corridor", "拐角走廊"], ["bridge_room", "通道桥"]]:
		if path.contains(pair[0]):
			return prefix + pair[1] + "套件"
	return prefix + "通用建筑套件"

static func type_tag(row: Dictionary) -> String:
	if not str(row.get("type_tag", "")).is_empty():
		return str(row["type_tag"])
	var role := str(row.get("slot_role", ""))
	if role == "breakable_clutter":
		return "易碎陈设"
	if role == "solid_wall":
		return "墙体"
	if role in ["door_wall", "door_leaf_preview"]:
		return "门与门框"
	if role == "floor_tile":
		return "地板与平台"
	var text := (str(row.get("slug", "")) + " " + str(row.get("category", ""))).to_lower()
	for pair in [["门与门框", ["door", "门框", "门墙", "门扇"]], ["标识与贴花", ["marking", "decal", "typography", "标识", "贴花", "文字"]],
		["楼梯", ["stair", "楼梯"]], ["栏杆", ["rail", "栏杆", "护栏"]], ["灯具", ["light", "lamp", "灯"]],
		["绿植", ["plant", "绿植"]], ["管线", ["pipe", "conduit", "cable", "管", "线缆"]],
		["地板与平台", ["floor", "platform", "地板", "地面", "地砖", "平台"]], ["墙体", ["wall", "partition", "墙", "隔断"]],
		["吊顶", ["ceiling", "吊顶"]], ["梁柱结构", ["column", "pillar", "beam", "梁", "柱"]],
		["碎屑", ["debris", "rubble", "碎屑", "残骸"]], ["设备", ["server", "screen", "terminal", "cabinet", "机柜", "屏", "终端", "设备"]]]:
		for word in pair[1]:
			if text.contains(word):
				return pair[0]
	return "陈设与构件"

static func caption(row: Dictionary) -> String:
	var text := str(row.get("display_name", row.get("category", row.get("slug", "组件"))))
	if text.ends_with("组件"):
		text = str(row.get("slug", text)).replace("_", " ")
	var regex := RegEx.new()
	regex.compile("\\s*[0-9]+[.][0-9]+.*$")
	text = regex.sub(text, "")
	return text.strip_edges().left(22)
