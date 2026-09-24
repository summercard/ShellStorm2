extends SceneTree
## 验收探针：通用壳体组件注册表 -> 运行时 PackedScene 的解析链。
##
## 覆盖的是 DungeonRoom3D._authored_component_prefab() 从「硬编码 match 表」改为
## 「注册表驱动」之后的**行为等价性**，以及注册表本身的自洽性：
##
##   A. 注册表自身：schema / component_count / ID 唯一（主 ID 与 alias 不许撞）；
##   B. **既有 5 个 ID 行为逐字不变**：战区摆位源用的批次号仍解析到原来那个 prefab
##      （逐个比对 resource_path，而不是「能加载就行」）；
##   C. 通用件名（ENV-SHARED-GENERIC-*）与批次号（alias）解析到**同一个** prefab；
##   D. 共享通用件源目录（shared/source/.../component_catalog.json）里每一件的
##      component_id 与 source_package_id 都在注册表里、都可解析 —— 即「挂进共享库
##      就等于挂进运行时」，不许出现只登记源、运行时解析不到的孤儿件；
##   E. 每件解析出的 prefab 根节点 metadata/asset_id == 注册表声明的 prefab_asset_id；
##   F. 反向对照：未登记的 ID 一律返回 null（不许悄悄回退成别的组件）；
##   G. **6 件 Boss 专属件**（ENV-EXPEDITION-BOSSROOM-*，kind=exclusive）：逐件可解析到
##      expedition/runtime/common_components/<slug>/ 下那个 prefab，且根节点 asset_id 相符。
##      它们与通用件共用本注册表（同一解析入口），但**不设 alias** —— 只属一个房间种类。
##
## 打印 SHELL_COMPONENT_CATALOG_OK pass=N fail=0 表示全过；任一失败打印 FAILED。
## 运行：godot --headless --path . --script res://<本文件>
##
## 反向对照（改坏会变红）：
##   · 把注册表 components[].prefab_path 指向一个不存在的路径 -> E/加载报错并有 fail；
##   · 把某个 alias 删掉（例如 ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02）-> B/D 红；
##   · 把 schema 字符串改一位 -> A 红（且 _authored_component_prefab 全返回 null）；
##   · 给两件组件登记同一个 ID -> A 红（重复登记）；
##   · 把某件专属件的 component_id 或 prefab_path 改错 -> G 红。

const RUNTIME_CATALOG_PATH := (
	"res://assets/art/environments/tower_zones/shared/runtime/shell_component_catalog.json"
)
const RUNTIME_CATALOG_SCHEMA := "shellstorm2.runtime_shell_component_catalog.v001"
const SHARED_SOURCE_CATALOG_PATH := (
	"res://assets/art/environments/tower_zones/shared/source/common_components"
	+ "/v001/component_catalog.json"
)

## 既有 5 个 ID → 改动前那个 prefab（逐字不变），逐条比对 resource_path。
## 另加 ENV-BATTLE-COMMON-DOOR-5M：旧表里没有（返回 null），本次是**有意新增**
## （解析到塔楼 A 套门扇），单独分开断言，避免与「行为不变」混为一谈。
const LEGACY_ID_TO_PREFAB: Dictionary = {
	"ENV-BATTLE-COMMON-WALL-STANDARD-5M":
		"res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_standard_5m/wall_standard_5m_root_top3d.tscn",
	"ENV-BATTLE-COMMON-WALL-DOOR-5M":
		"res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_door_5m/wall_door_5m_root_top3d.tscn",
	"ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01":
		"res://assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c01_root_top3d.tscn",
	"ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02":
		"res://assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c02_root_top3d.tscn",
	"ENV-TOWER-CORNER-L-5M": "res://assets/art/props/dungeon_3d/prp_corner_l_5m.tscn",
}
const NEWLY_ADDED_ID_TO_PREFAB: Dictionary = {
	"ENV-BATTLE-COMMON-DOOR-5M": "res://assets/art/props/dungeon_3d/prp_tower_door_leaf_5m.tscn",
}
## 6 件 Boss 专属件（Task #40/#42）：只属远征 Boss 竞技场，不设 alias。
## 逐件比对运行时路径 —— 比「能加载就行」强：换错件会直接红。
const EXCLUSIVE_ID_TO_PREFAB: Dictionary = {
	"ENV-EXPEDITION-BOSSROOM-BASE-FLOOR-BASE":
		"res://assets/art/environments/tower_zones/expedition/runtime/common_components/base_floor_base/base_floor_base_root_top3d.tscn",
	"ENV-EXPEDITION-BOSSROOM-MAIN-FAULT-SCREEN":
		"res://assets/art/environments/tower_zones/expedition/runtime/common_components/main_fault_screen/main_fault_screen_root_top3d.tscn",
	"ENV-EXPEDITION-BOSSROOM-HEAVY-CONDUITS":
		"res://assets/art/environments/tower_zones/expedition/runtime/common_components/heavy_conduits/heavy_conduits_root_top3d.tscn",
	"ENV-EXPEDITION-BOSSROOM-NORTH-WALL-TYPOGRAPHY":
		"res://assets/art/environments/tower_zones/expedition/runtime/common_components/north_wall_typography/north_wall_typography_root_top3d.tscn",
	"ENV-EXPEDITION-BOSSROOM-SOUTH-FLOOR-MARKING":
		"res://assets/art/environments/tower_zones/expedition/runtime/common_components/south_floor_marking/south_floor_marking_root_top3d.tscn",
	"ENV-EXPEDITION-BOSSROOM-DEBRIS-00":
		"res://assets/art/environments/tower_zones/expedition/runtime/common_components/debris_00/debris_00_root_top3d.tscn",
}
## 注册表总件数 = 6 通用 + 6 Boss 专属。
const EXPECTED_COMPONENT_TOTAL := 12

var _pass := 0
var _fail := 0


func _initialize() -> void:
	var catalog := _read_json(RUNTIME_CATALOG_PATH)
	if catalog.is_empty():
		_expect(false, "运行时注册表可读且可解析: %s" % RUNTIME_CATALOG_PATH)
		_report()
		return
	_expect_decode(catalog)

	var components := catalog.get("components", []) as Array
	_expect_decoded_count(catalog, components)
	_expect_unique_ids(components)
	_expect_primary_ids_resolve(components)
	_expect_legacy_ids_unchanged()
	_expect_newly_added_ids()
	_expect_exclusive_ids(components)
	_expect_source_catalog_fully_covered()
	_expect_unknown_ids_null()
	_report()


# —— A. 注册表自洽 ——

func _expect_decode(catalog: Dictionary) -> void:
	_expect(
		str(catalog.get("schema", "")) == RUNTIME_CATALOG_SCHEMA,
		"schema == %s（实得 %s）" % [RUNTIME_CATALOG_SCHEMA, str(catalog.get("schema", ""))]
	)
	_expect(str(catalog.get("scope", "")) == "shell", "scope == shell")


func _expect_decoded_count(catalog: Dictionary, components: Array) -> void:
	var declared := int(catalog.get("component_count", -1))
	_expect(declared == components.size(), "component_count %d == components.size() %d" % [declared, components.size()])
	_expect(
		components.size() == EXPECTED_COMPONENT_TOTAL,
		"注册表恰好登记 %d 件壳体件（实得 %d）" % [EXPECTED_COMPONENT_TOTAL, components.size()]
	)


func _expect_unique_ids(components: Array) -> void:
	var seen := {}
	var duplicates: Array[String] = []
	for value in components:
		var entry := value as Dictionary
		var ids: Array = [str(entry.get("component_id", ""))]
		ids.append_array(entry.get("aliases", []))
		for id_value in ids:
			var id := str(id_value)
			if seen.has(id):
				duplicates.append(id)
			seen[id] = true
	_expect(
		duplicates.is_empty(),
		"注册表 ID 唯一（重复项：%s）" % str(duplicates)
	)


# —— B/C/E. 逐件解析 ——

func _expect_primary_ids_resolve(components: Array) -> void:
	for value in components:
		var entry := value as Dictionary
		var component_id := str(entry.get("component_id", ""))
		var declared_path := str(entry.get("prefab_path", ""))
		var prefab := DungeonRoom3D._authored_component_prefab(component_id)
		_expect(prefab != null, "%s 可解析出 PackedScene" % component_id)
		if prefab == null:
			continue
		_expect(
			prefab.resource_path == declared_path,
			"%s 解析到注册表声明的路径（%s）" % [component_id, declared_path]
		)
		_expect_prefab_asset_id(prefab, str(entry.get("prefab_asset_id", "")), component_id)
		# alias 必须命中**同一个** prefab 资源（不是「另一个能加载的同名件」）。
		var alias_list: Array = entry.get("aliases", [])
		for alias_value in alias_list:
			var alias := str(alias_value)
			var alias_prefab := DungeonRoom3D._authored_component_prefab(alias)
			_expect(alias_prefab != null, "%s 的 alias %s 可解析" % [component_id, alias])
			if alias_prefab != null:
				_expect(
					alias_prefab.resource_path == prefab.resource_path,
					"%s 与 alias %s 解析到同一 prefab（%s）" % [component_id, alias, prefab.resource_path]
				)


func _expect_prefab_asset_id(prefab: PackedScene, expected_asset_id: String, label: String) -> void:
	var instance := prefab.instantiate() as Node3D
	_expect(instance != null, "%s 的 prefab 根节点是 Node3D" % label)
	if instance == null:
		return
	var actual := str(instance.get_meta("asset_id", ""))
	_expect(
		not expected_asset_id.is_empty() and actual == expected_asset_id,
		"%s prefab 根节点 asset_id == %s（实得 %s）" % [label, expected_asset_id, actual]
	)
	instance.free()


# —— B. 既有 5 个 ID 逐字不变 ——

func _expect_legacy_ids_unchanged() -> void:
	for id_value in LEGACY_ID_TO_PREFAB.keys():
		var id := str(id_value)
		var expected_path := str(LEGACY_ID_TO_PREFAB[id])
		var prefab := DungeonRoom3D._authored_component_prefab(id)
		_expect(prefab != null, "既有 ID %s 仍可解析" % id)
		if prefab == null:
			continue
		_expect(
			prefab.resource_path == expected_path,
			"既有 ID %s 行为逐字不变（期望 %s，实得 %s）" % [id, expected_path, prefab.resource_path]
		)


func _expect_newly_added_ids() -> void:
	for id_value in NEWLY_ADDED_ID_TO_PREFAB.keys():
		var id := str(id_value)
		var expected_path := str(NEWLY_ADDED_ID_TO_PREFAB[id])
		var prefab := DungeonRoom3D._authored_component_prefab(id)
		_expect(prefab != null and prefab.resource_path == expected_path, "新增可解析 ID %s -> %s" % [id, expected_path])


# —— G. 6 件 Boss 专属件（kind=exclusive、不设 alias）——

func _expect_exclusive_ids(components: Array) -> void:
	for id_value in EXCLUSIVE_ID_TO_PREFAB.keys():
		var id := str(id_value)
		var expected_path := str(EXCLUSIVE_ID_TO_PREFAB[id])
		var prefab := DungeonRoom3D._authored_component_prefab(id)
		_expect(prefab != null, "专属件 %s 可解析出 PackedScene" % id)
		if prefab == null:
			continue
		_expect(
			prefab.resource_path == expected_path,
			"专属件 %s 解析到声明的 prefab（期望 %s，实得 %s）" % [id, expected_path, prefab.resource_path]
		)
		var entry := _find_component_entry(components, id)
		_expect(not entry.is_empty(), "专属件 %s 在注册表 components[] 里有条目" % id)
		if entry.is_empty():
			continue
		_expect(str(entry.get("kind", "")) == "exclusive", "专属件 %s 的 kind == exclusive" % id)
		_expect((entry.get("aliases", []) as Array).is_empty(), "专属件 %s 不设 alias" % id)
		_expect_prefab_asset_id(prefab, str(entry.get("prefab_asset_id", "")), id)


func _find_component_entry(components: Array, component_id: String) -> Dictionary:
	for value in components:
		var entry := value as Dictionary
		if str(entry.get("component_id", "")) == component_id:
			return entry
	return {}


# —— D. 共享库无孤儿件 ——

func _expect_source_catalog_fully_covered() -> void:
	var source_catalog := _read_json(SHARED_SOURCE_CATALOG_PATH)
	_expect(not source_catalog.is_empty(), "共享通用件源目录可读: %s" % SHARED_SOURCE_CATALOG_PATH)
	if source_catalog.is_empty():
		return
	var packages := source_catalog.get("packages", []) as Array
	_expect(packages.size() == 6, "共享源目录登记 6 件（实得 %d）" % packages.size())
	for value in packages:
		var package := value as Dictionary
		for key in ["component_id", "source_package_id"]:
			var id := str(package.get(key, ""))
			_expect(not id.is_empty(), "共享源目录条目有 %s" % key)
			if id.is_empty():
				continue
			var prefab := DungeonRoom3D._authored_component_prefab(id)
			_expect(prefab != null, "共享源 ID %s（%s）在运行时注册表里可解析" % [id, key])


# —— F. 反向对照 ——

func _expect_unknown_ids_null() -> void:
	for id in [
		"ENV-BATTLE-COMMON-NOT-A-COMPONENT",
		"ENV-SHARED-GENERIC-UNKNOWN",
		"",
		"wall_standard_5m",
	]:
		_expect(
			DungeonRoom3D._authored_component_prefab(str(id)) == null,
			"未登记 ID %s 返回 null（不回退）" % ("<空串>" if str(id).is_empty() else str(id))
		)


# —— 工具 ——

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	return parsed as Dictionary


func _expect(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % label)


func _report() -> void:
	if _fail == 0:
		print("SHELL_COMPONENT_CATALOG_OK pass=%d fail=0" % _pass)
		quit(0)
	else:
		print("SHELL_COMPONENT_CATALOG_FAILED pass=%d fail=%d" % [_pass, _fail])
		quit(1)
