class_name MonsterDropTable
extends RefCounted
## 关卡级「地图 × 怪物」掉落表编译器。
##
## 作者编辑 CSV；导出器把当前关卡的行写进 L1 `monster_drop_table.rows`。
## 本类只负责把行编译成 RewardSpec，不抽奖、不生成实体、不持有全局当前关卡。

const SPEC := preload("res://src/rewards/RewardSpec.gd")
const TABLE_SCHEMA := "shellstorm2.monster_drop_table"
const TABLE_VERSION := 1
const CURRENCY_PREFIX := "@currency:"
const POOL_PREFIX := "@pool:"


## 返回 `{ok, specs, errors, row_count, monster_count}`。
## specs 的形态为 `{monster_id: RewardSpec}`；任一错误都会拒绝整张表，绝不半表生效。
static func compile(level_id: String, table: Dictionary) -> Dictionary:
	var errors: Array[Dictionary] = []
	var rows_value: Variant = table.get("rows", null)
	if str(table.get("schema", "")) != TABLE_SCHEMA:
		errors.append(_err("MONSTER_DROP_TABLE_BAD_SCHEMA", "monster_drop_table.schema", "schema 必须为 %s" % TABLE_SCHEMA))
	if int(table.get("schema_version", 0)) != TABLE_VERSION:
		errors.append(_err("MONSTER_DROP_TABLE_BAD_VERSION", "monster_drop_table.schema_version", "schema_version 必须为 %d" % TABLE_VERSION))
	if not (rows_value is Array):
		errors.append(_err("MONSTER_DROP_TABLE_ROWS_NOT_ARRAY", "monster_drop_table.rows", "rows 必须是数组"))
		return _report({}, errors, 0)
	var rows := rows_value as Array
	if rows.is_empty():
		errors.append(_err("MONSTER_DROP_TABLE_ROWS_EMPTY", "monster_drop_table.rows", "rows 不得为空"))
		return _report({}, errors, 0)

	var grouped: Dictionary = {}
	for index in range(rows.size()):
		var path := "monster_drop_table.rows[%d]" % index
		var value: Variant = rows[index]
		if not (value is Dictionary):
			errors.append(_err("MONSTER_DROP_TABLE_ROW_NOT_OBJECT", path, "行必须是对象"))
			continue
		var row := value as Dictionary
		var monster_id := str(row.get("monster_id", ""))
		if not SPEC.is_known_monster(monster_id) or monster_id == "boss":
			errors.append(_err("MONSTER_DROP_TABLE_UNKNOWN_MONSTER", "%s.monster_id" % path, "普通怪 ID 无效：%s" % monster_id))
			continue
		if bool(row.get("is_elite", false)):
			errors.append(_err("MONSTER_DROP_TABLE_ELITE_NOT_SUPPORTED", path, "本表只处理普通怪，精英走独立结算"))
			continue
		var normalized := _normalize_row(row, path, errors)
		if normalized.is_empty():
			continue
		if not grouped.has(monster_id):
			grouped[monster_id] = []
		(grouped[monster_id] as Array).append(normalized)

	var specs: Dictionary = {}
	for monster_id_value in grouped.keys():
		var monster_id := str(monster_id_value)
		var compiled := _compile_monster(level_id, monster_id, grouped[monster_id] as Array, errors)
		if not compiled.is_empty():
			specs[monster_id] = compiled
	if not errors.is_empty():
		return _report({}, errors, rows.size())
	return _report(specs, errors, rows.size())


static func spec_for(compiled: Dictionary, monster_id: String) -> Dictionary:
	if not compiled.has(monster_id):
		return {}
	return (compiled[monster_id] as Dictionary).duplicate(true)


static func _normalize_row(row: Dictionary, path: String, errors: Array[Dictionary]) -> Dictionary:
	var item_id := str(row.get("item_id", ""))
	if item_id.is_empty():
		errors.append(_err("MONSTER_DROP_TABLE_ITEM_EMPTY", "%s.item_id" % path, "item_id 不得为空"))
		return {}
	var chance := float(row.get("chance", 1.0))
	if chance < 0.0 or chance > 1.0:
		errors.append(_err("INVALID_CHANCE", "%s.chance" % path, "chance 必须在 0..1"))
		return {}
	var quantity: Variant = _parse_quantity(row.get("quantity", 1), "%s.quantity" % path, errors)
	if quantity == null:
		return {}
	var out := {
		"item_id": item_id,
		"chance": chance,
		"quantity": quantity,
		"note": str(row.get("note", "")),
		"path": path,
	}
	if row.has("weight"):
		var weight_value: Variant = row["weight"]
		if not (weight_value is int or weight_value is float):
			errors.append(_err("MONSTER_DROP_TABLE_WEIGHT_NOT_NUMBER", "%s.weight" % path, "weight 必须是数值"))
			return {}
		var weight := float(weight_value)
		if weight < 0.0:
			errors.append(_err("MONSTER_DROP_TABLE_WEIGHT_NEGATIVE", "%s.weight" % path, "weight 不得为负"))
			return {}
		out["weight"] = weight
	return out


static func _compile_monster(
	level_id: String, monster_id: String, rows: Array, errors: Array[Dictionary]
) -> Dictionary:
	var entries: Array = []
	var weighted: Array = []
	for value in rows:
		var row := value as Dictionary
		if row.has("weight"):
			weighted.append(row)
		else:
			var entry := _row_to_entry(row, errors)
			if not entry.is_empty():
				entries.append(entry)
	if not weighted.is_empty():
		var group_entry := _weighted_entry(monster_id, weighted, errors)
		if not group_entry.is_empty():
			entries.push_front(group_entry)
	var spec := {
		"spec_id": "level:%s:monster:%s" % [level_id, monster_id],
		"entries": entries,
	}
	var check := SPEC.validate_spec(spec, spec["spec_id"])
	if not bool(check.get("ok", false)):
		for value in check.get("errors", []):
			errors.append(value as Dictionary)
		return {}
	return spec


static func _weighted_entry(
	monster_id: String, rows: Array, errors: Array[Dictionary]
) -> Dictionary:
	var first := rows[0] as Dictionary
	var chance := float(first["chance"])
	var draws_value: Variant = first["quantity"]
	if not (draws_value is int or draws_value is float):
		errors.append(_err("MONSTER_DROP_TABLE_WEIGHTED_QUANTITY_NOT_CONSTANT", str(first["path"]), "权重组数量必须是常量抽签次数"))
		return {}
	var draws := int(draws_value)
	if draws <= 0:
		errors.append(_err("MONSTER_DROP_TABLE_WEIGHTED_DRAWS_INVALID", str(first["path"]), "权重组抽签次数必须大于 0"))
		return {}
	var options: Array = []
	var total := 0.0
	for value in rows:
		var row := value as Dictionary
		if not is_equal_approx(float(row["chance"]), chance):
			errors.append(_err("MONSTER_DROP_TABLE_WEIGHTED_CHANCE_MISMATCH", str(row["path"]), "同怪权重组概率必须一致"))
		if row["quantity"] != draws_value:
			errors.append(_err("MONSTER_DROP_TABLE_WEIGHTED_QUANTITY_MISMATCH", str(row["path"]), "同怪权重组数量必须一致"))
		var weight := float(row["weight"])
		total += weight
		var option := _row_to_entry(row, errors)
		option.erase("chance")
		option["weight"] = weight
		options.append(option)
	if total <= 0.0:
		errors.append(_err("EMPTY_WEIGHT", "monster_drop_table.%s" % monster_id, "权重组总权重必须大于 0"))
		return {}
	return {
		"kind": SPEC.KIND_WEIGHTED,
		"chance": chance,
		"draws": draws,
		"options": options,
	}


static func _row_to_entry(row: Dictionary, errors: Array[Dictionary]) -> Dictionary:
	var item_id := str(row["item_id"])
	var quantity: Variant = row["quantity"]
	var entry: Dictionary
	if item_id.begins_with(CURRENCY_PREFIX):
		entry = {
			"kind": SPEC.KIND_CURRENCY,
			"currency_id": item_id.trim_prefix(CURRENCY_PREFIX),
			"amount": quantity,
		}
	elif item_id.begins_with(POOL_PREFIX):
		entry = {
			"kind": SPEC.KIND_POOL,
			"pool_id": item_id.trim_prefix(POOL_PREFIX),
			"draws": int(quantity) if quantity is int or quantity is float else 1,
		}
	else:
		entry = {"kind": SPEC.KIND_ITEM, "item_id": item_id, "count": quantity}
	var chance := float(row["chance"])
	if chance < 1.0:
		entry["chance"] = chance
	if entry.is_empty():
		errors.append(_err("MONSTER_DROP_TABLE_ENTRY_EMPTY", str(row["path"]), "无法编译该行"))
	return entry


static func _parse_quantity(raw: Variant, path: String, errors: Array[Dictionary]) -> Variant:
	if raw is int or raw is float:
		if float(raw) <= 0.0:
			errors.append(_err("MONSTER_DROP_TABLE_QUANTITY_INVALID", path, "数量必须大于 0"))
			return null
		return int(raw) if is_equal_approx(float(raw), round(float(raw))) else float(raw)
	var text := str(raw).strip_edges()
	if text.is_empty():
		return 1
	if text.contains("-"):
		var parts := text.split("-", false)
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			var lo := int(parts[0])
			var hi := int(parts[1])
			if lo > 0 and hi >= lo:
				return {"min": lo, "max": hi}
	if text.begins_with("2+floor*") and text.trim_prefix("2+floor*").is_valid_int():
		return {"base": 2, "per_floor": int(text.trim_prefix("2+floor*"))}
	errors.append(_err("MONSTER_DROP_TABLE_QUANTITY_SYNTAX", path, "数量只支持正数、a-b、2+floor*n"))
	return null


static func _report(specs: Dictionary, errors: Array[Dictionary], row_count: int) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"specs": specs,
		"errors": errors,
		"row_count": row_count,
		"monster_count": specs.size(),
	}


static func _err(code: String, path: String, detail: String) -> Dictionary:
	return {"code": code, "path": path, "detail": detail}
