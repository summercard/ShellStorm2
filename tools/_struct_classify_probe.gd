extends SceneTree
## 「哪一件是玩法几何、哪一件是美术」的判定体检。
##
## 这份判据现在是**单点**（`RuntimeRoomArtSource.is_structure_prefab()`），被三处消费：
## `DungeonRoom3D._strip_art_layer_geometry()`、`capture_runtime.gd`、`test_runtime_source.gd`。
## 判错任一方向的后果都不是报错，而是**静默错位**：
##
##   · 该剥的没剥（判成装饰）⇒ 墙跟着美术走，换一局门位不同就「图上有门、走过去撞墙」；
##   · 不该剥的剥了（判成结构）⇒ 沙发、吊灯、货架凭空消失，而且没人知道少了什么。
##
## 所以两个方向都断言，并且**重点覆盖"以后才加进来的资产"** —— 那是本次改动的目的。
##
## 用法：
##   godot --headless --path . --script res://tools/_struct_classify_probe.gd
##   godot --headless --path . --script res://tools/_struct_classify_probe.gd -- --report

const ART := preload("res://src/world3d/RuntimeRoomArtSource.gd")

const EXPEDITION_RUNTIME := "res://assets/art/environments/tower_zones/expedition/runtime"

## 回归基线：2026-10-31 之前那 5 个精确文件名，**不能因为换了判据就漏判**。
const BASELINE_STRUCTURE: Array[String] = [
	"res://assets/art/props/dungeon_3d/prp_room_floor.tscn",
	"res://assets/art/props/dungeon_3d/prp_room_wall_segment.tscn",
	"res://assets/art/props/dungeon_3d/prp_room_wall_door_segment.tscn",
	"res://assets/art/props/dungeon_3d/prp_room_door_lintel.tscn",
	"res://assets/art/props/dungeon_3d/prp_room_corner_post.tscn",
]

## 目录级不变量：这些目录下的资产**一律**是结构件（目录名即语义）。
## 以后往这些目录里加新墙、新地砖，不需要改任何代码，这条自动覆盖。
const STRUCTURE_DIRS: Array[String] = [
	"common_components/wall_standard_5m_h3",
	"common_components/wall_door_5m_h3",
	"common_components/floor_tile_5m",
	"common_components/floor_base_5m",
	"common_components/base_floor_base",
	"common_components/ceiling_deck_5m",
	"common_components/manor_wall_standard",
	"common_components/manor_wall_window",
	"common_components/manor_wall_door",
	"common_components/manor_floor_wood",
	"common_components/manor_floor_stone",
	"common_components/manor_floor_bath",
	"room_type_components/boss_room/floor_tile_5m_a",
	"room_type_components/boss_room/floor_tile_5m_b",
	"room_type_components/boss_room/floor_tile_5m_c",
	"room_type_components/boss_room/floor_base",
]

## 真实装修件：**必须**判成美术。取各房型代表件 + 复古公馆套件。
const DECOR_MUST_STAY: Array[String] = [
	"room_type_components/office_room/shelving",
	"room_type_components/bridge_room/bank_crate",
	"room_type_components/l_corridor/crate",
	"room_type_components/office_room/totem_column",
	"room_type_components/boss_room/server_rack",
	"room_type_components/boss_room/plant_a",
	"room_type_components/boss_room/chair",
	"room_type_components/db_room/equipment_rack",
	"common_components/manor_sofa",
	"common_components/manor_bed",
	"common_components/manor_painting",
	"common_components/manor_rug_lounge",
	"common_components/manor_table_lamp",
	"common_components/manor_wall_lamp",
	"common_components/manor_bookcase",
	"common_components/manor_bathtub",
]

## **以后才加进来的资产**：这批以前不在任何名单里，正是本次要覆盖的情形。
const FUTURE_MUST_STRIP: Array[String] = [
	"common_components/wall_standard_5m_h12",
	"common_components/wall_collapse_5m_h12",
]

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures.append(reason)
		printerr("STRUCT_FAIL ", reason)


func _run() -> void:
	var report := "--report" in OS.get_cmdline_user_args()
	# 触发一次目录加载。**必须确认它读到了东西** —— 读不到时判据会静默退化成
	# "只靠名字族"，新资产不再自动被认，而界面上什么都不会提示。
	ART.is_structure_prefab("res://probe.tscn")
	print("STRUCT_CATALOG loaded=%s structure_slugs=%d"
		% [ART._catalog_loaded, ART._structure_slugs.size()])
	check(ART._catalog_loaded, "组件目录没有加载")
	check(ART._structure_slugs.size() >= 30,
		"组件目录里读出的结构类 slug 只有 %d 个（预期 ≥30，目录可能改了结构）"
		% ART._structure_slugs.size())
	# 墙的判定必须比"结构"窄 —— 否则量墙高会把角柱/门楣算进去
	check(ART.is_wall_prefab("res://assets/art/props/dungeon_3d/prp_room_wall_segment.tscn"),
		"墙判据漏了 prp_room_wall_segment")
	check(not ART.is_wall_prefab("res://assets/art/props/dungeon_3d/prp_room_corner_post.tscn"),
		"角柱被判成墙（墙高会量成 2.9m）")
	check(not ART.is_wall_prefab("res://assets/art/props/dungeon_3d/prp_room_door_lintel.tscn"),
		"门楣被判成墙（墙高会量到过梁顶）")
	check(not ART.is_wall_prefab("res://assets/art/props/dungeon_3d/prp_room_floor.tscn"),
		"地板被判成墙")

	# ── 方向一：回归基线 + 目录级不变量 ─────────────────────────────────────
	for prefab in BASELINE_STRUCTURE:
		if not ResourceLoader.exists(prefab):
			continue
		check(ART.is_structure_prefab(prefab),
			"回归基线判错（旧名单里的几何件现在被判成美术）：%s" % prefab.get_file())

	var dir_prefabs := 0
	for folder in STRUCTURE_DIRS:
		for path in _tscn_under(EXPEDITION_RUNTIME.path_join(folder)):
			dir_prefabs += 1
			check(ART.is_structure_prefab(path),
				"结构目录里的资产被判成美术（换上去墙会跟着美术走）：%s"
				% path.get_file())
			if report:
				print("  STRUCT %s" % path.get_file())
	check(dir_prefabs > 0, "结构目录里一份 .tscn 都没扫到（目录结构变了？）")
	print("STRUCT_DIR_PREFABS %d" % dir_prefabs)

	# ── 方向二：装修件不许被剥 ──────────────────────────────────────────────
	var decor_prefabs := 0
	for folder in DECOR_MUST_STAY:
		var files := _tscn_under(EXPEDITION_RUNTIME.path_join(folder))
		check(not files.is_empty(), "装修件目录里没找到 .tscn：%s" % folder)
		for path in files:
			decor_prefabs += 1
			check(not ART.is_structure_prefab(path),
				"装修件被判成结构件（会被凭空剥掉）：%s" % path.get_file())
			if report:
				print("  DECOR  %s" % path.get_file())
	print("STRUCT_DECOR_PREFABS %d" % decor_prefabs)

	# ── 方向三：以后加的结构资产自动进网 ────────────────────────────────────
	for folder in FUTURE_MUST_STRIP:
		for path in _tscn_under(EXPEDITION_RUNTIME.path_join(folder)):
			check(ART.is_structure_prefab(path),
				"新增结构资产没被判成结构件：%s" % path.get_file())
			if report:
				print("  FUTURE %s" % path.get_file())

	# ── 方向三之二：**只靠目录角色**才认得出的资产 ──────────────────────────
	# 这几个名字不在任何名字族里，只有 `shell_component_catalog.json` 的
	# `slot_role` 能认。它们过了，才证明"新资产改目录就行、不用改代码"这条真的成立。
	for pair in [["tile_upper", ART.TAG_FLOOR], ["base_corner_l_5m", ART.TAG_CORNER]]:
		var catalog_only := str(pair[0])
		var want_tag := str(pair[1])
		var family_hit := false
		for family in ART.STRUCTURE_FAMILIES.keys():
			if ART._matches_family(catalog_only, str(family)):
				family_hit = true
				break
		check(not family_hit,
			"%s 居然被名字族匹配到了 —— 这条断言就失去意义了（它不是纯目录驱动样本）"
			% catalog_only)
		var tag := ART.structure_tag("res://probe/%s.tscn" % catalog_only)
		check(tag == want_tag,
			"纯目录驱动的资产没被认成结构件：%s 期望 %s 实得 [%s]"
			% [catalog_only, want_tag, tag])
		if report:
			print("  CATALOG_ONLY %s → %s" % [catalog_only, tag])

	# ── 方向四：名字族边界不能吃掉字母续接的装饰 ────────────────────────────
	for pair in [
		["wall_tapestry", false], ["wall_t_900", true],
		["wall_xylophone", false], ["wall_x670", true],
		["floor_basement_prop", false], ["floor_base_5m", true],
		["my_wall_standard_panel", true], ["env_manor_wall_standard", true],
		["env_manor_sofa", false], ["shelf_wall_mount", false],
	]:
		var slug := str(pair[0])
		var want := bool(pair[1])
		var actual := ART.is_structure_prefab("res://probe/%s.tscn" % slug)
		check(actual == want, "名字族边界错判：%s 期望 %s 实得 %s" % [slug, want, actual])

	print("STRUCT_%s checks=%d failures=%d"
		% ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _tscn_under(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file_name in DirAccess.get_files_at(dir_path):
		if file_name.ends_with(".tscn"):
			out.append(dir_path.path_join(file_name))
	for sub in DirAccess.get_directories_at(dir_path):
		out.append_array(_tscn_under(dir_path.path_join(sub)))
	out.sort()
	return out
