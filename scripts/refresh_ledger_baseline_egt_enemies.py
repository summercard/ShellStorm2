#!/usr/bin/env python3
"""把远征03《挺进地牢》第一层复刻怪（33 只）补录进无损基线。

背景
----
`tools/asset_pipeline/verify_ledger_split.py` 拿冻结于拆分之前（2026-10-28）的
`assets/registry/ledger_split_baseline.json` 作真源，断言「并集 == 基线全集」。
新增资产行必然触发 `asset_not_in_baseline`，属**预期的过期**，不是回归；
处理口径沿用既有先例（敌人账本日志 v0.1.3）：

  1. 备份基线 → `ledger_split_baseline.json.bak_before_egt_enemies`
  2. **只登记新 AssetID 的指纹**，既有条目的 `v` 逐位不动
     （故 `REFRESH_ALLOWED` 为空 —— 本批不允许改动任何既有行）
  3. `asset_count` / `category_counts` / `column_digests` 从当前账本重算
  4. `sheet_digests` 保持不动：本批未改《敌人动画与状态》《3D-敌人》
     （33 只复刻怪是表现占位，没有自己的 PackedScene，按账本口径不进 3D 分页）

Run: python scripts/refresh_ledger_baseline_egt_enemies.py
"""

from __future__ import annotations

import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))

from openpyxl import load_workbook  # noqa: E402

from ledger_registry import LedgerIndex  # noqa: E402
from split_asset_ledger import (  # noqa: E402
    ASSET_SHEET,
    CONTENT_COLUMNS,
    _row_digest,
    col_digest,
    read_source_rows,
)

BASELINE = ROOT / "assets/registry/ledger_split_baseline.json"
TAG = "before_egt_enemies"

# 本批新增的 33 个 AssetID。列全是为了让「多录/漏录」在输出里一眼可见：
# 基线是回归守卫，宁可把白名单写死，也不要静默把任何新行都当合法。
EXPECTED_NEW = {
    # 第一批 12 只（敌人账本 v0.1.20，r21~r32）
    "ENM-RANGED-BULLETKIN01", "ENM-RANGED-BANDANAKIN01", "ENM-RANGED-VETERANKIN01",
    "ENM-RANGED-REDSHOTGUN01", "ENM-RANGED-BLUESHOTGUN01",
    "ENM-MELEE-BLOBULON01", "ENM-MELEE-BLOBULOID01", "ENM-MELEE-BLOBULIN01",
    "ENM-BOMBER-PINHEAD01", "ENM-BOMBER-NITRA01", "ENM-BOMBER-BULLAT01",
    "ENM-SUMMON-GUNSINGER01",
    # 第二批 21 只（敌人账本 v0.1.21，r33~r53）
    "ENM-RANGED-CARDINAL01", "ENM-RANGED-HOLLOWPOINT01", "ENM-RANGED-VETSHOTGUN01",
    "ENM-BOMBER-KINGBULLAT01", "ENM-MELEE-CHANCEBULON01",
    "ENM-SUMMON-BOOKLLET01", "ENM-SUMMON-BLUEBOOK01", "ENM-SUMMON-GREENBOOK01",
    "ENM-SUMMON-GUNJURER01", "ENM-SUMMON-GIGI01",
    "ENM-BOMBER-SHOTGAT01", "ENM-BOMBER-GRENAT01", "ENM-BOMBER-SPIRAT01",
    "ENM-MELEE-KEYBULLET01", "ENM-MELEE-CHANCEKIN01",
    "ENM-RANGED-CONFIRMED01", "ENM-NORMAL-MIMIC01", "ENM-RANGED-GUNFAIRY01",
    "ENM-SUMMON-GRIPMASTER01", "ENM-NORMAL-GUNNUT01", "ENM-NORMAL-CHAINGUNNER01",
}

# 本批允许刷新内容指纹的既有行。
# 2026-10-29 第二轮重定标（血量 ×10、伤害 17/26）改了这 33 行的「规格」列，
# 指纹必然变 —— 这是**有意的**，故显式放行。
# ⚠ 除这 33 个 ID 之外，任何既有行的内容一变就应该让脚本失败，别把白名单当万能钥匙。
REFRESH_ALLOWED: set[str] = set(EXPECTED_NEW)


def main() -> int:
    backup = BASELINE.with_suffix(BASELINE.suffix + "." + TAG)
    if not backup.exists():
        shutil.copy2(BASELINE, backup)
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
    refreshed: list[str] = []
    for domain_key, values in rows:
        aid = values[0]
        if not aid:
            continue
        digest = _row_digest(values)
        entry = {"v": digest, "c": values[2], "d": domain_key}
        if aid not in assets:
            added.append(aid)
            assets[aid] = entry
        elif assets[aid]["v"] != digest and aid in REFRESH_ALLOWED:
            refreshed.append(aid)
            assets[aid] = entry

    # 守卫：新增集合必须**恰好**是本批声明的那 33 个。
    # 允许两种合法形态：① 首次补录（added = 33、refreshed = 0）
    # ② 重定标刷新（added = 0、refreshed = 33）。混合也行，但并集必须覆盖声明集。
    unexpected = sorted(set(added) - EXPECTED_NEW)
    uncovered = sorted(EXPECTED_NEW - set(added) - set(refreshed))
    if unexpected or uncovered:
        print(json.dumps({
            "error": "补录/刷新集合与本批声明不一致",
            "unexpected": unexpected,
            "uncovered": uncovered,
        }, ensure_ascii=False, indent=2))
        return 1

    bl["asset_count"] = len(assets)
    cats: dict[str, int] = {}
    for entry in assets.values():
        cats[entry["c"]] = cats.get(entry["c"], 0) + 1
    bl["category_counts"] = dict(sorted(cats.items()))

    for column in CONTENT_COLUMNS:
        bl["column_digests"][str(column)] = col_digest(collected, column)
    bl["captured_at"] = datetime.now().replace(microsecond=0).isoformat()

    BASELINE.write_text(json.dumps(bl, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({
        "added": len(added),
        "refreshed": refreshed,
        "asset_count": bl["asset_count"],
        "enemy_count": bl["category_counts"].get("敌人"),
        "backup": str(backup.relative_to(ROOT)),
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
