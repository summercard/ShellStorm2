#!/usr/bin/env python3
"""把 99F 基地 NPC 登记进角色账本，并补录无损基线（2026-11-02）。

背景
----
`BASE-NPC` 的 NPC **不新增美术资产**：几何复用 `CHR-PLY-CAPSULE01-3D-BUNNY01`，
全绿皮肤是运行期 `material_override`。但它是一个新的、可独立加载的
`PackedScene`（`scenes/BaseNpc3D.tscn`），且必须能在账本里被查到 ——
否则下次有人改 NPC 外观时，账本里没有任何一行告诉他"这东西存在、归谁"。

所以本批登记 **一行主表资产**，制作状态 `原型已接入`（代码装配，无独立美术源），
文件路径指向 NPC 的 PackedScene，SHA 取该场景文件。

口径与既有先例一致（`scripts/register_secret_door_ledger.py`、
`refresh_ledger_baseline_teleport_vfx.py`）：
  1. 备份 xlsx 与基线
  2. 主表追加一行（**追加到末行**，不插行 —— openpyxl 不重算公式引用）
  3. 总览 8 格区间 `$6:$30` → `$6:$31`
  4. DataValidation sqref 扩到新行（重建 DV 对象，`str(sqref)` 会给出 repr）
  5. 《域变更日志》追加 v0.1.27
  6. 基线只补录新 AssetID，既有条目 `v` 逐位不动；`column_digests` /
     `category_counts` / `asset_count` 从当前账本重算；`sheet_digests` 不动
     （本批没有改任何摘要锁定的专表）

Run: python scripts/register_base_npc_ledger.py
"""

from __future__ import annotations

import hashlib
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))

from openpyxl import load_workbook  # noqa: E402
from openpyxl.worksheet.datavalidation import DataValidation  # noqa: E402

from ledger_registry import LedgerIndex  # noqa: E402
from split_asset_ledger import (  # noqa: E402
    ASSET_SHEET,
    CATEGORY_VALUES,
    CONTENT_COLUMNS,
    FIRST_DATA_ROW,
    PRIORITY_VALUES,
    STATUS_VALUES,
    _row_digest,
    col_digest,
    dedupe_key_formula,
    dedupe_result_formula,
    read_source_rows,
)

LEDGER = ROOT / "assets/registry/ledgers/ShellStorm2_角色账本_v001.xlsx"
BASELINE = ROOT / "assets/registry/ledger_split_baseline.json"
TAG = "before_base_npc"

NEW_ID = "CHR-PLY-BUNNY01-NPC-GREEN"
SCENE_REL = "scenes/BaseNpc3D.tscn"
TEMPLATE_ROW = 22  # 面饰行：正式美术已接入 + 单 Prefab 路径，形态最接近


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _row_values(row: int, sha: str) -> dict[int, object]:
    values: dict[int, object] = {
        1: NEW_ID,
        2: "99F 基地 NPC·全绿皮肤",
        3: "角色",
        4: "player_variant",
        5: "npc_base99_green",
        6: "root_npc",
        7: "CHR-PLY-CAPSULE01-3D-BUNNY01",
        8: "俯视3D",
        9: "idle / patrol / talk（程序化关节动画，无骨骼剪辑）",
        10: "99F基地NPC",
        11: "原型已接入",
        12: "P1",
        13: "v001",
        14: "复用bunny01几何，可见高1.525m；运行时material_override全量覆盖为绿色；无独立美术源",
        15: SCENE_REL,
        16: "src/npc/NpcCharacter3D.gd；docs/v0.1/20_技术施工_基地NPC.md",
        17: "基地NPC;绿皮;全绿;巡逻;对话;base_npc;npc_base99_green",
        18: dedupe_key_formula(row),
        19: dedupe_result_formula(row, row),
        20: sha,
        21: "摩斯拉",
        22: datetime(2026, 11, 2),
        23: "复用 CHR-PLY-CAPSULE01-3D-BUNNY01 几何；运行时材质覆盖，无新增美术源",
        24: "—",
        25: "用户要求：主角模型换全绿皮肤、会自己移动、可对话。不新增美术资产、不改共享材质；"
        "巡逻/对话/交互契约见 docs/v0.1/20_技术施工_基地NPC.md；验收 verify_base_npc_flow。",
    }
    return values


def write_ledger_row() -> dict:
    backup = LEDGER.with_suffix(LEDGER.suffix + "." + TAG)
    if not backup.exists():
        shutil.copy2(LEDGER, backup)
        print(f"[backup] {backup.name}")

    wb = load_workbook(LEDGER, data_only=False)
    ws = wb[ASSET_SHEET]
    header_ok = str(ws.cell(5, 1).value) == "AssetID" and str(ws.cell(5, 25).value) == "备注"
    if not header_ok:
        raise SystemExit("资产主表表头不是预期的 25 列，拒绝写入")

    last_row = FIRST_DATA_ROW
    for row in range(FIRST_DATA_ROW, ws.max_row + 1):
        if ws.cell(row, 1).value not in (None, ""):
            last_row = row
    new_row = last_row + 1
    if ws.cell(new_row, 1).value not in (None, ""):
        raise SystemExit(f"目标行 {new_row} 已被占用，拒绝覆盖")

    existing_ids = {
        str(ws.cell(row, 1).value)
        for row in range(FIRST_DATA_ROW, last_row + 1)
        if ws.cell(row, 1).value
    }
    if NEW_ID in existing_ids:
        raise SystemExit(f"{NEW_ID} 已存在，拒绝重复登记")

    sha = _sha256(ROOT / SCENE_REL)
    values = _row_values(new_row, sha)

    from copy import copy

    for column in range(1, 26):
        cell = ws.cell(new_row, column)
        cell.value = values[column]
        cell._style = copy(ws.cell(TEMPLATE_ROW, column)._style)
    ws.row_dimensions[new_row].height = ws.row_dimensions[TEMPLATE_ROW].height

    # 总览：8 个写死区间全部从旧末行改成新末行。
    overview = wb["总览"]
    for row in overview.iter_rows(min_row=1, max_row=overview.max_row):
        for cell in row:
            if isinstance(cell.value, str) and cell.value.startswith("="):
                old = cell.value
                cell.value = old.replace(f"${last_row}", f"${new_row}")
                if cell.value != old:
                    print(f"[overview] {cell.coordinate}: {last_row} -> {new_row}")

    # DataValidation：只扩展 C/K/L 三列的下拉区间，其余原样重建。
    # ⚠ `str(dv.sqref)` 返回 `<MultiCellRange [C6:C30]>` 这种 repr，做字符串替换会拼出
    # 非法区间、赋值被静默丢弃 —— 一律清空后按列重建。
    ws.data_validations.dataValidation.clear()
    ranges_by_col = {3: CATEGORY_VALUES, 11: STATUS_VALUES, 12: PRIORITY_VALUES}
    for column, allowed in ranges_by_col.items():
        letter = chr(64 + column)
        rebuilt = DataValidation(
            type="list",
            formula1='"' + ",".join(allowed) + '"',
            allow_blank=True,
            showDropDown=False,
            showErrorMessage=False,
        )
        rebuilt.add(f"{letter}{FIRST_DATA_ROW}:{letter}{new_row}")
        ws.add_data_validation(rebuilt)

    # 域变更日志：版本号 +1。
    log = wb["域变更日志"]
    log_last = log.max_row
    last_version = ""
    for row in range(5, log_last + 1):
        version = str(log.cell(row, 1).value or "")
        if version.startswith("v"):
            last_version = version
    log_row = log_last + 1
    # 版本号形如 v0.1.26（三段）。旧日志里出现过跳号，所以按「最后一行 +1」推进，
    # 不按最大号 —— 追加式日志的语义是「接着上一行」。
    parts = last_version.lstrip("v").split(".")
    if len(parts) != 3:
        raise SystemExit(f"域变更日志末行版本格式异常：{last_version!r}")
    new_version = f"v{parts[0]}.{parts[1]}.{int(parts[2]) + 1}"
    log_values = [
        new_version,
        "2026-11-02",
        "新增 99F 基地 NPC（全绿皮肤）",
        "角色 / Bunny01 / NPC",
        "新增 CHR-PLY-BUNNY01-NPC-GREEN：复用 bunny01 几何，运行时 material_override 全绿；"
        "带巡逻、朝向、待机/步行动画与气泡对话，接统一交互协议；无新增美术源。",
        "只新增一行资产；共享材质与既有资产指纹保持，总览与下拉区间扩至新行。",
        "摩斯拉",
    ]
    for column, value in enumerate(log_values, start=1):
        cell = log.cell(log_row, column)
        cell.value = value
        cell._style = copy(log.cell(log_row - 1, column)._style)
    log.row_dimensions[log_row].height = log.row_dimensions[log_row - 1].height

    wb.save(LEDGER)
    return {
        "new_row": new_row,
        "last_row": last_row,
        "new_id": NEW_ID,
        "sha256": sha,
        "log_version": new_version,
        "backup": backup.name,
    }


def refresh_baseline() -> dict:
    backup = BASELINE.with_suffix(BASELINE.suffix + "." + TAG)
    if not backup.exists():
        shutil.copy2(BASELINE, backup)
        print(f"[backup] {backup.name}")

    bl = json.loads(BASELINE.read_text(encoding="utf-8"))
    index = LedgerIndex.load(ROOT)

    rows: list[tuple[str, tuple]] = []
    collected: list[tuple[int, tuple]] = []
    for domain in index.domains:
        wb = load_workbook(domain.path, data_only=False)
        if ASSET_SHEET not in wb.sheetnames:
            continue
        for row_index, values in read_source_rows(wb[ASSET_SHEET]):
            rows.append((domain.key, values))
            collected.append((row_index, values))

    assets = bl["assets"]
    added: list[str] = []
    for domain_key, values in rows:
        asset_id = values[0]
        if not asset_id:
            continue
        digest = _row_digest(values)
        if asset_id not in assets:
            added.append(asset_id)
            assets[asset_id] = {"v": digest, "c": values[2], "d": domain_key}

    unexpected = sorted(set(added) - {NEW_ID})
    uncovered = sorted({NEW_ID} - set(added))
    if unexpected or uncovered:
        raise SystemExit(
            "补录集合与本批声明不一致: unexpected=%s uncovered=%s" % (unexpected, uncovered)
        )

    bl["asset_count"] = len(assets)
    cats: dict[str, int] = {}
    for entry in assets.values():
        cats[entry["c"]] = cats.get(entry["c"], 0) + 1
    bl["category_counts"] = dict(sorted(cats.items()))
    for column in CONTENT_COLUMNS:
        bl["column_digests"][str(column)] = col_digest(collected, column)
    bl["captured_at"] = datetime.now().replace(microsecond=0).isoformat()

    BASELINE.write_text(json.dumps(bl, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return {"added": added, "asset_count": bl["asset_count"], "角色": cats.get("角色")}


def main() -> int:
    ledger = write_ledger_row()
    baseline = refresh_baseline()
    print(json.dumps({"ledger": ledger, "baseline": baseline}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
