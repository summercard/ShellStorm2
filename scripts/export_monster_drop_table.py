#!/usr/bin/env python3
"""Export the author-facing map x monster CSV into each level_plan.json.

The CSV is the editable cross-level table. Runtime reads only the generated
L1 monster_drop_table so level loading stays JSON-native. Use --check in gates
to reject drift without modifying files.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / "docs/v0.1/data/怪物掉落表_地图x怪物.csv"
LEVEL_ROOT = ROOT / "source/art/whitebox/tower_zones"
TABLE_SCHEMA = "shellstorm2.monster_drop_table"
TABLE_VERSION = 1
SOURCE_PATH = "docs/v0.1/data/怪物掉落表_地图x怪物.csv"


def parse_chance(raw: str) -> float | None:
    value = raw.strip()
    if not value:
        return None
    if value.endswith("%"):
        return float(value[:-1]) / 100.0
    return float(value)


def parse_number(raw: str) -> int | float | None:
    value = raw.strip()
    if not value:
        return None
    number = float(value)
    return int(number) if number.is_integer() else number


def parse_quantity(raw: str) -> int | str | None:
    value = raw.strip()
    if not value:
        return None
    if value.isdigit():
        return int(value)
    return value


def canonical_hash(rows: list[dict[str, Any]]) -> str:
    encoded = json.dumps(
        rows, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def read_rows() -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    with CSV_PATH.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        required = {"关卡ID", "怪物ID", "物品ID", "概率", "权重", "数量", "备注"}
        missing = required.difference(reader.fieldnames or [])
        if missing:
            raise ValueError(f"CSV missing columns: {sorted(missing)}")
        for line_number, source in enumerate(reader, start=2):
            level_id = (source.get("关卡ID") or "").strip()
            monster_id = (source.get("怪物ID") or "").strip()
            item_id = (source.get("物品ID") or "").strip()
            if not level_id or not monster_id or not item_id:
                raise ValueError(f"line {line_number}: level/monster/item ID must not be empty")
            row: dict[str, Any] = {
                "monster_id": monster_id,
                "item_id": item_id,
            }
            chance = parse_chance(source.get("概率") or "")
            weight = parse_number(source.get("权重") or "")
            quantity = parse_quantity(source.get("数量") or "")
            note = (source.get("备注") or "").strip()
            if chance is not None:
                row["chance"] = chance
            if weight is not None:
                row["weight"] = weight
            if quantity is not None:
                row["quantity"] = quantity
            if note:
                row["note"] = note
            grouped.setdefault(level_id, []).append(row)
    return grouped


def discover_level_plans() -> dict[str, Path]:
    found: dict[str, Path] = {}
    for path in LEVEL_ROOT.glob("*/v*/data/level_plan.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError):
            continue
        level_id = str(data.get("level_id", ""))
        if not level_id:
            continue
        if level_id in found:
            raise ValueError(f"duplicate level_id {level_id}: {found[level_id]} and {path}")
        found[level_id] = path
    return found


def expected_table(rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "schema": TABLE_SCHEMA,
        "schema_version": TABLE_VERSION,
        "source_csv": SOURCE_PATH,
        "rows_sha256": canonical_hash(rows),
        "rows": rows,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="reject drift without writing")
    args = parser.parse_args()

    grouped = read_rows()
    plans = discover_level_plans()
    failures: list[str] = []
    changed = 0
    for level_id, rows in grouped.items():
        path = plans.get(level_id)
        if path is None:
            failures.append(f"unknown level_id in CSV: {level_id}")
            continue
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        expected = expected_table(rows)
        if data.get("monster_drop_table") == expected:
            continue
        if args.check:
            failures.append(f"monster_drop_table drift: {level_id} -> {path.relative_to(ROOT)}")
            continue
        data["monster_drop_table"] = expected
        text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        path.write_bytes(text.replace("\n", "\r\n").encode("utf-8"))
        changed += 1

    if failures:
        for failure in failures:
            print(f"MONSTER_DROP_TABLE_ERROR {failure}")
        return 1
    mode = "CHECK" if args.check else "EXPORT"
    row_count = sum(len(rows) for rows in grouped.values())
    print(f"MONSTER_DROP_TABLE_{mode}_OK levels={len(grouped)} rows={row_count} changed={changed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
