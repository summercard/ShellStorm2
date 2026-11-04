#!/usr/bin/env python3
"""把「首遇收租人后基地 NPC 迎宾」这一批变更登记进两本分账本（2026-11-04）。

口径
----
本批**没有新增美术源、没有新增 AssetID**：

* 角色账本 `CHR-PLY-BUNNY01-NPC-GREEN` 只做**能力扩展**（台词节拍 + 站位/开口行为），
  几何、骨架、动画库、Prefab 路径与 SHA 全部不变 —— 只补备注与域变更日志。
* 场景账本 `ENV-BASE99-ART-LAYOUT-3D` 因为 `zone_base.tscn` 新增了一个作者锚点
  `99层基地NPC迎宾锚点`，文件 SHA 变化 —— 更新 SHA、更新时间、备注与域变更日志。

不做的事
--------
不重算 `column_digests`：那张表是冻结快照的全表口径，重算会把同一工作区里其他批次
（本会话之外）的 17 处既有 SHA 漂移一起吸收进来，等于替别人的改动背书。本批只刷新
自己动过的两行在 `assets` 里的逐行指纹。

Run: python scripts/register_base_npc_greeting_ledger.py
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

from split_asset_ledger import ASSET_SHEET, _row_digest, read_source_rows  # noqa: E402

CHAR_LEDGER = ROOT / "assets/registry/ledgers/ShellStorm2_角色账本_v001.xlsx"
SCENE_LEDGER = ROOT / "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx"
BASELINE = ROOT / "assets/registry/ledger_split_baseline.json"
SCENE_PATH = ROOT / "assets/art/environments/tower_zones/base/runtime/zone_base.tscn"
TAG = "before_base_npc_greeting"
TODAY = datetime(2026, 11, 4)

CHAR_ID = "CHR-PLY-BUNNY01-NPC-GREEN"
SCENE_ID = "ENV-BASE99-ART-LAYOUT-3D"

CHAR_NOTE = (
    "\n2026-11-04 BASE-NPC r5：新增一次性剧情节拍（内容在 NpcCatalog.STORY_BEATS，"
    "判定与落盘在 NpcStoryBeatService，实体只消费结论）。首遇收租人后回 99F，NPC 站到"
    "迎宾锚点、玩家进 4m 自动逐句说出用户原话，播完回巡逻、跨存档只播一次；"
    "落盘复用 BaseData.narrative_history 的 npc_beat: 键，不新增存档字段。"
    "几何/骨架/动画/Prefab 路径与 SHA 不变；验收 verify_base_npc_story_beat。"
)

SCENE_NOTE = (
    "\n2026-11-04 BASE-NPC r5：布置层新增作者锚点『99层基地NPC迎宾锚点』"
    "（局部 (-3.2, 0, -0.2) ⇒ 世界 (-3.2, -12, 4.8)），供 99F 基地 NPC 在首遇收租人后的"
    "一次性迎宾里站定使用；离归航点 3.2m、在走道一侧、0.45m 球体物理查询重叠 0。"
    "仅新增一个 Marker3D，既有设施、灯光、结构件与巡逻锚点位置不变。"
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _backup(path: Path) -> None:
    backup = path.with_suffix(path.suffix + "." + TAG)
    if not backup.exists():
        shutil.copy2(path, backup)
        print(f"[backup] {backup.name}")


def _find_row(ws, asset_id: str) -> int:
    for row in range(6, ws.max_row + 1):
        if str(ws.cell(row, 1).value or "").strip() == asset_id:
            return row
    raise SystemExit(f"asset {asset_id} not found in {ws.title}")


def _append_log(wb, version: str, title: str, scope: str, change: str, proof: str) -> None:
    log = wb["域变更日志"]
    row = log.max_row + 1
    while row > 1 and all(log.cell(row - 1, c).value in (None, "") for c in range(1, 8)):
        row -= 1
    log.cell(row, 1, version)
    log.cell(row, 2, "2026-11-04")
    log.cell(row, 3, title)
    log.cell(row, 4, scope)
    log.cell(row, 5, change)
    log.cell(row, 6, proof)
    log.cell(row, 7, "摩斯拉")
    print(f"[log] {wb['域变更日志'].title} v{version} row {row}")


def update_character_ledger() -> None:
    _backup(CHAR_LEDGER)
    wb = load_workbook(CHAR_LEDGER, data_only=False)
    ws = wb[ASSET_SHEET]
    if str(ws.cell(5, 1).value) != "AssetID" or str(ws.cell(5, 25).value) != "备注":
        raise SystemExit("角色账本资产主表表头不是预期的 25 列，拒绝写入")
    row = _find_row(ws, CHAR_ID)
    current = str(ws.cell(row, 25).value or "")
    if "BASE-NPC r5" not in current:
        ws.cell(row, 25, current + CHAR_NOTE)
    ws.cell(row, 22, TODAY)
    _append_log(
        wb,
        "v0.1.29",
        "基地 NPC 首遇收租人迎宾",
        "角色 / Bunny01 / NPC",
        "同一 AssetID 能力扩展：新增 STORY_BEATS 台词节拍，首遇收租人后回 99F 站定迎宾并逐句提醒，"
        "整段播完落盘一次（narrative_history 的 npc_beat: 键）。",
        "几何/骨架/动画/Prefab 路径与 SHA 不变，只补备注；验收 verify_base_npc_story_beat exit 0。",
    )
    wb.save(CHAR_LEDGER)
    print(f"[ok] 角色账本 row {row} 备注已补，SHA 列未动（场景未改）")


def update_scene_ledger() -> str:
    _backup(SCENE_LEDGER)
    new_sha = _sha256(SCENE_PATH)
    wb = load_workbook(SCENE_LEDGER, data_only=False)
    ws = wb[ASSET_SHEET]
    if str(ws.cell(5, 1).value) != "AssetID" or str(ws.cell(5, 25).value) != "备注":
        raise SystemExit("场景账本资产主表表头不是预期的 25 列，拒绝写入")
    row = _find_row(ws, SCENE_ID)
    old_sha = str(ws.cell(row, 20).value or "")
    ws.cell(row, 20, new_sha)
    ws.cell(row, 22, TODAY)
    current = str(ws.cell(row, 25).value or "")
    if "BASE-NPC r5" not in current:
        ws.cell(row, 25, current + SCENE_NOTE)
    _append_log(
        wb,
        "v0.1.70",
        "99F 基地 NPC 迎宾锚点",
        SCENE_ID,
        "zone_base.tscn 新增作者锚点『99层基地NPC迎宾锚点』(局部 -3.2,0,-0.2)；"
        "供基地 NPC 首遇收租人后的迎宾站定使用。",
        "docs/v0.1/development/2026-11-04_base_npc_elite_arms_taker_greeting.md",
    )
    wb.save(SCENE_LEDGER)
    print(f"[ok] 场景账本 row {row} SHA {old_sha[:12]} → {new_sha[:12]}")
    return new_sha


def refresh_baseline() -> dict:
    """只刷新本批动过的两行的逐行指纹（不做全表重算，见文件头）。"""
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    assets = baseline["assets"]
    refreshed: list[str] = []
    for ledger_path, asset_id in ((CHAR_LEDGER, CHAR_ID), (SCENE_LEDGER, SCENE_ID)):
        wb = load_workbook(ledger_path, data_only=False)
        for _row_index, values in read_source_rows(wb[ASSET_SHEET]):
            if values[0] != asset_id:
                continue
            digest = _row_digest(values)
            if assets.get(asset_id, {}).get("v") != digest:
                entry = assets.setdefault(asset_id, {})
                entry["v"] = digest
                entry.setdefault("c", values[2])
                entry.setdefault("d", "characters" if ledger_path is CHAR_LEDGER else "scenes")
                refreshed.append(asset_id)
            break
    BASELINE.write_text(json.dumps(baseline, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"[baseline] refreshed={refreshed}")
    return {"refreshed": refreshed}


def main() -> int:
    update_character_ledger()
    update_scene_ledger()
    refresh_baseline()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
