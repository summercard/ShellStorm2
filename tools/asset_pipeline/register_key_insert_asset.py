"""登记 99F 四孔钥匙嵌件 PRP-BASE99-MAIN-STORY-KEY-INSERT 到场景账本。

业主 2026-11-10 追加要求：「后面这个台子上…直接做一个新模型嵌在上面」，
因此这是一件**新资产**（不是台座的子部件）：主表、3D-设施分页、域变更日志、基线都要有。
只写这一件资产；其他资产与分页的既有漂移一律不接纳、不修复。

用法：python tools/asset_pipeline/register_key_insert_asset.py
幂等：已登记则只核对、不重复追加。
"""
from __future__ import annotations

from collections import Counter
from copy import copy, deepcopy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from ledger_registry import LedgerIndex
from workspace_paths import work_path
from split_asset_ledger import (
    ASSET_SHEET, HEADER_ROW, FIRST_DATA_ROW, CONTENT_COLUMNS,
    _row_digest, col_digest, read_source_rows, sheet_digest,
    dedupe_key_formula, dedupe_result_formula,
)
from openpyxl import load_workbook

INDEX = LedgerIndex.load(ROOT)
SESSION = work_path("sessions/2026-11-10_key_inset/ledger/session.json").parent
SESSION.mkdir(parents=True, exist_ok=True)
BASELINE = ROOT / "assets/registry/ledger_split_baseline.json"
MANIFEST = ROOT / "assets/art/props/main_story/asset_manifest.json"

ASSET_ID = "PRP-BASE99-MAIN-STORY-KEY-INSERT"
NAME = "99F主线钥匙四孔斜插嵌件"
CATEGORY = "场景道具"
SUBTYPE = "facility"
LOGIC = "main_story_key_insert"
PREFAB = "assets/art/props/main_story/runtime/key_insert/prp_base99_main_story_key_insert_root_top3d.tscn"
GLB = "assets/art/props/main_story/components/key_insert/prp_base99_main_story_key_insert_visual_top3d.glb"
SOURCE = "art_source/props/main_story/key_insert/prp_base99_main_story_key_insert_source_v001.blend"
OPTIMIZED = "art_source/props/main_story/key_insert/export/v001/prp_base99_main_story_key_insert_optimized_v001.blend"
SCRIPT = "src/narrative/MainStoryPedestal3D.gd"
DESIGN = "docs/v0.1/design/主线剧情3.1至3.3与四钥匙设计.md"
DOMAIN = "scenes"
PAGE = "3D-设施"


def dump(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=1, default=str) + "\n", encoding="utf-8")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def registry_files():
    return [ROOT / "assets/registry/ledger_index.json", INDEX.master_path, BASELINE, *INDEX.ledger_paths()]


def snapshot(label: str):
    stamp = datetime.now().strftime("%Y-%m-%d_%H%M%S_%f")
    parent = ROOT.parent / "ShellStorm2-backup"
    assert parent.is_dir()
    target = parent / f"{stamp}_key_insert_ledger_{label}" / "before_edits"
    target.mkdir(parents=True)
    before = {p.relative_to(ROOT).as_posix(): sha(p) for p in registry_files()}
    for path in registry_files():
        dest = target / path.relative_to(ROOT)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest)
        assert sha(dest) == before[path.relative_to(ROOT).as_posix()]
    assert {p.relative_to(ROOT).as_posix(): sha(p) for p in registry_files()} == before
    dump(SESSION / f"snapshot_{label}.json", {"snapshot": str(target), "hashes": before})
    return before


def save_book(book, path: Path, expected: dict) -> None:
    assert {p.relative_to(ROOT).as_posix(): sha(p) for p in registry_files()} == expected, "登记文件存在并发修改"
    fd, temp = tempfile.mkstemp(suffix=".xlsx", dir=path.parent)
    os.close(fd)
    try:
        book.save(temp)
        with zipfile.ZipFile(temp) as archive:
            assert archive.testzip() is None
        assert {p.relative_to(ROOT).as_posix(): sha(p) for p in registry_files()} == expected
        os.replace(temp, path)
        expected[path.relative_to(ROOT).as_posix()] = sha(path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def save_baseline(value, expected: dict) -> None:
    assert {p.relative_to(ROOT).as_posix(): sha(p) for p in registry_files()} == expected
    dump(BASELINE, value)
    expected[BASELINE.relative_to(ROOT).as_posix()] = sha(BASELINE)


def append_row(ws, values, template: int) -> int:
    last = max((c.row for row in ws for c in row if c.value is not None), default=HEADER_ROW)
    row = last + 1
    for column, value in enumerate(values, 1):
        ws.cell(row, column)._style = copy(ws.cell(template, column)._style)
        ws.cell(row, column).value = value
    ws.row_dimensions[row].height = ws.row_dimensions[template].height
    return row


def extend(ws, overview, last: int) -> None:
    for row in range(FIRST_DATA_ROW, last + 1):
        ws.cell(row, 18).value = dedupe_key_formula(row)
        ws.cell(row, 19).value = dedupe_result_formula(row, last)
    for row in overview:
        for cell in row:
            value = cell.value
            if isinstance(value, str) and value.startswith("=") and "资产主表" in value:
                cell.value = re.sub(r"(:\$?[A-Z]+\$?)\d+", lambda m: m[1] + str(last), value)
    ws.auto_filter.ref = f"A{HEADER_ROW}:Y{last}"


def log(book, title: str, details: str) -> str:
    ws = book["域变更日志"]
    versions = [tuple(map(int, m.groups())) for m in
                (re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", str(row[0].value or "")) for row in ws) if m]
    version = max(versions)
    new_version = f"v{version[0]}.{version[1]}.{version[2] + 1}"
    append_row(ws, [new_version, "2026-11-10", title, "主线3.1—3.3 / 99F设施",
                    details, "仅本资产登记；不改原台柜GLB/TSCN/碰撞，不接纳其他资产既有漂移", "CodeBuddy"],
               max(1, ws.max_row))
    return new_version


def main() -> int:
    path = INDEX.domain_for_key(DOMAIN).path
    book = load_workbook(path)
    ws = book[ASSET_SHEET]
    existing = [r for r, v in read_source_rows(ws) if v[0] == ASSET_ID]
    if existing:
        page = book[PAGE]
        on_page = any(c.value == ASSET_ID for row in page for c in row)
        print(json.dumps({"status": "already_registered", "row": existing[0], "on_prefab_page": on_page,
                          "asset_sha": sha(ROOT / PREFAB)}, ensure_ascii=False))
        return 0

    expected = snapshot("register")
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    frozen = deepcopy(baseline)
    assert ASSET_ID not in baseline["assets"]
    for domain in INDEX.domains:
        for _, values in read_source_rows(load_workbook(domain.path)[ASSET_SHEET]):
            assert values[4] != LOGIC, "逻辑ID已存在"
            assert values[14] != PREFAB, "Prefab路径已存在"

    prefab_sha = sha(ROOT / PREFAB)
    note = (
        "2026-11-10 主线3.1—3.3 业主追加：钥匙不再单独立一块台座，改做一件独立四孔嵌件直接嵌在"
        "主门下方低矮设备柜台面（`main_door_low_storage_cabinet`，台面碰撞盒顶 y=1.38）上，"
        "原台柜 GLB/TSCN/碰撞一毫米未动。"
        "规格 2.28×0.58×0.24 m；四个真实矩形孔（孔唇＋轴向内壁＋60 mm 暗槽）；孔距 0.46 m；"
        "孔轴 20° 朝台内下插；四个独立槽灯 SocketGlow_0..3。"
        "源=" + SOURCE + "；优化源=" + OPTIMIZED + "；稳定GLB=" + GLB + "；wrapper=" + PREFAB + "。"
        "三张共享色盘材质（紫骨架/青绿大面/紫粉点缀/自发光UI灯光），GLB 内无贴图，Nearest 后导入。"
        "碰撞 none（嵌件无碰撞，站立与行走由原台柜碰撞盒负责）。"
        "运行表现与换色由 " + SCRIPT + " 只读 BaseManager.get_main_story_snapshot() 驱动；不写存档。"
        "制作状态=原型已接入，未完成正式美术母版；面数 304 tri（优化前后 320→304，仅清理四个槽灯的共面反向片）。"
    )
    values = [
        ASSET_ID, NAME, CATEGORY, SUBTYPE, LOGIC, "root_3d", None, "Top3D / Godot Y-up",
        "default / socket_glow_0..3 / installed",
        "99F 主门下方低柜台面固定嵌件；主线四把钥匙的安装位",
        "原型已接入", "P1", "v001",
        "2.28×0.58×0.24 m；四孔孔距0.46 m；孔轴20°；304 tri",
        PREFAB, f"{SOURCE}；{DESIGN}", "四孔嵌件;斜插;钥匙孔;台面附件;main_story_key_insert",
        None, None, prefab_sha, "CodeBuddy", "2026-11-10",
        "Blender源已建；优化源独立另存后重开导出；无贴图，共享色盘Nearest",
        SCRIPT, note,
    ]
    old_row = max(r for r, _ in read_source_rows(ws))
    row = append_row(ws, values, old_row)
    extend(ws, book["总览"], row)
    version = log(book, "新增主线四孔钥匙嵌件", f"{ASSET_ID}；{NAME}；主表!A{row}；仅本资产登记。")
    save_book(book, path, expected)

    page_ws = load_workbook(path)[PAGE]
    assert page_ws.cell(HEADER_ROW - 1, 1).value == "AssetID"
    assert not any(c.value == ASSET_ID for r in page_ws for c in r)
    page_before = sheet_digest(page_ws)
    page_row = append_row(page_ws, [
        ASSET_ID, NAME, PREFAB, GLB, SOURCE,
        "四个真实矩形孔，钥匙沿 20° 孔轴斜插；四个槽灯按永久进度独立换色",
        SCRIPT, "无", "无新增碰撞", "无",
        "2.28×0.58×0.24 m；孔距0.46 m", "Godot Y-up；原点 XZ 居中、底面 Y=0；前向 +Z",
        "99F 主门下方低柜台面 (5, 1.38, -3.77)", "原型已接入", "v001",
        "嵌入件而非立式台座；原台柜模型/碰撞未改；优化源 art_source/.../export/v001/；GLB 无贴图；未完成正式美术母版",
    ], max(5, page_ws.max_row))
    log(book, "四孔嵌件Prefab分页登记", f"{PAGE}!A{page_row}={ASSET_ID}；只重建本分页 sheet digest。")
    save_book(load_workbook(path), path, expected)

    baseline["assets"][ASSET_ID] = {"v": _row_digest(values), "c": CATEGORY, "d": DOMAIN}
    collected = []
    for domain in INDEX.domains:
        collected += read_source_rows(load_workbook(domain.path)[ASSET_SHEET])
    assert all(baseline["assets"][aid] == record for aid, record in frozen["assets"].items() if aid != ASSET_ID)
    baseline["asset_count"] = len(baseline["assets"])
    baseline["column_digests"] = {str(c): col_digest(collected, c) for c in CONTENT_COLUMNS}
    baseline["category_counts"] = dict(sorted(Counter(v[2] for _, v in collected).items()))
    page_after = sheet_digest(load_workbook(path)[PAGE])
    for name, digest in frozen["sheet_digests"].items():
        if name != PAGE:
            assert baseline["sheet_digests"][name] == digest, name
    baseline["sheet_digests"][PAGE] = page_after
    baseline.setdefault("targeted_updates", []).append({
        "date": "2026-11-10",
        "asset_id": [ASSET_ID],
        "operation": "Add one new facility asset row (main table + 3D-设施 page), no other row touched",
        "sheet": PAGE,
        "previous_recorded_sheet_digest": frozen["sheet_digests"].get(PAGE),
        "actual_before_sheet_digest": page_before,
        "after_sheet_digest": page_after,
        "record": "docs/v0.1/development/2026-11-10_key_inset_and_dialogue_advance.md",
    })
    save_baseline(baseline, expected)

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    manifest["assets"] = [a for a in manifest["assets"] if a.get("asset_id") != ASSET_ID]
    manifest["assets"].append({
        "asset_id": ASSET_ID,
        "asset_ledger": INDEX.domain_for_key(DOMAIN).relative_path + "#资产主表",
        "prefab": PREFAB,
        "sha256": prefab_sha,
        "source_kind": "blender",
        "program_source": SCRIPT,
        "blender_source": SOURCE,
        "optimized_blend": OPTIMIZED,
        "glb": GLB,
        "collision": "无新增碰撞；站立由原台柜碰撞盒负责",
    })
    manifest.setdefault("embedded_visual_coverage", {})[ASSET_ID] = [
        "四个真实矩形插孔（孔唇/内壁/暗槽）",
        "SocketGlow_0..3 四槽灯按 deposited 状态独立换色",
        "20° 斜插孔轴，钥匙沿轴插入",
    ]
    manifest["production_status"] = "原型已接入"
    manifest["art_master_complete"] = False
    manifest["validation"] = (
        "本事务只登记已存在的实现；真实渲染与专项计数见 "
        "outputs/main_story_031_033/key_insert_v2/ 与 docs/v0.1/development/2026-11-10_key_inset_and_dialogue_advance.md"
    )
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    dump(SESSION / "register_result.json", {
        "asset_id": ASSET_ID, "asset_row": row, "prefab_row": page_row, "log_version": version,
        "prefab_sha": prefab_sha, "baseline_asset_count": baseline["asset_count"],
        "glb_sha": sha(ROOT / GLB), "source_sha": sha(ROOT / SOURCE), "optimized_sha": sha(ROOT / OPTIMIZED),
        "sheet_digest_before": page_before, "sheet_digest_after": page_after,
    })
    print(json.dumps({"status": "registered", "asset_row": row, "prefab_row": page_row,
                      "log_version": version, "prefab_sha": prefab_sha}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
