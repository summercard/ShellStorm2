"""登记「对话底栏 + 头顶说话示意框」到 UI 账本。

业主 2026-11-10：
  「头顶对话框那个东西太挡角色了……只做成说话示意的样子，有点点点的动画。
    但是真实文字在下方的原来系统对话的那个地方，以后所有对话和系统信息统一在那边。」
  「头顶气泡的说话，还是要保留，在电灯开关这类自言自语的时候，需要保留。」

这是既有 UI 的一次形态改造（不是新增美术文件）：
  · 底栏 `UI-SCREEN-DIALOGUE-BAR` 承担**所有对话与系统信息的文字**；
  · 头顶气泡新增「示意形态」，仍归 `UI-SCREEN-DIALOGUE-BAR` 的父资产表现，不另建资产行；
  · 自言自语（开灯等 bark）仍走原文字气泡，属于同一父资产的另一形态。

只写这一行；其他资产与分页的既有漂移一律不接纳、不修复。
用法：python tools/asset_pipeline/register_dialogue_bar_asset.py
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
    ASSET_SHEET, HEADER_ROW, CONTENT_COLUMNS,
    _row_digest, col_digest, read_source_rows,
    dedupe_key_formula, dedupe_result_formula,
)
from openpyxl import load_workbook

INDEX = LedgerIndex.load(ROOT)
SESSION = work_path("sessions/2026-11-10_dialogue_bottom_bar/ledger/session.json").parent
SESSION.mkdir(parents=True, exist_ok=True)
BASELINE = ROOT / "assets/registry/ledger_split_baseline.json"

ASSET_ID = "UI-SCREEN-DIALOGUE-BAR"
NAME = "对话底栏与头顶说话示意框"
CATEGORY = "UI"
SUBTYPE = "screen"
LOGIC = "dialogue_bar"
BAR_SCRIPT = "src/ui/dialogue/DialogueUI.gd"
BUBBLE_SCRIPT = "src/ui/bubble/SpeechBubble3D.gd"
BARK_SCRIPT = "src/ui/bubble/CharacterBark3D.gd"
DESIGN = "docs/v0.1/design/对话与战斗信息呈现设计.md"
TECH = "docs/v0.1/18_技术施工_UI与对话系统.md"
DOMAIN = "ui"


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
    target = parent / f"{stamp}_dialogue_bar_ledger_{label}" / "before_edits"
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
    # 派生列（查重键/查重结果）按当前全表重算：契约要求范围覆盖到本账本最后一行。
    # 这里只重写这两列公式，不动任何内容列。
    for row in range(HEADER_ROW, last + 1):
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
    version = max(versions) if versions else (0, 1, 0)
    new_version = f"v{version[0]}.{version[1]}.{version[2] + 1}"
    columns = ["版本", "日期", "变更", "范围", "明细", "备注", "操作者"]
    row = max((c.row for r in ws for c in r if c.value is not None), default=1) + 1
    for index, value in enumerate([new_version, "2026-11-10", title, "对话与系统信息 / 全场景",
                                   details, "仅本资产登记；不接纳其他资产既有漂移", "CodeBuddy"]):
        ws.cell(row, index + 1)._style = copy(ws.cell(row - 1, index + 1)._style)
        ws.cell(row, index + 1).value = value
    assert len(columns) == 7
    return new_version


def main() -> int:
    path = INDEX.domain_for_key(DOMAIN).path
    book = load_workbook(path)
    ws = book[ASSET_SHEET]
    existing = [r for r, v in read_source_rows(ws) if v[0] == ASSET_ID]
    if existing:
        print(json.dumps({"status": "already_registered", "row": existing[0],
                          "bar_script_sha": sha(ROOT / BAR_SCRIPT)}, ensure_ascii=False))
        return 0

    expected = snapshot("register")
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    frozen = deepcopy(baseline)
    assert ASSET_ID not in baseline["assets"]
    for domain in INDEX.domains:
        for _, values in read_source_rows(load_workbook(domain.path)[ASSET_SHEET]):
            assert values[4] != LOGIC, "逻辑ID已存在"

    # 先证明「排除本行后」列摘要仍与基线一致：否则说明别的域已有漂移，
    # 这一次重算会把它洗进基线 —— 必须停下来人工核。
    current_rows = []
    for domain in INDEX.domains:
        current_rows += [item for item in read_source_rows(load_workbook(domain.path)[ASSET_SHEET])]
    pre_drift = [str(col) for col in CONTENT_COLUMNS
                 if col_digest(current_rows, col) != baseline["column_digests"].get(str(col))]
    if pre_drift:
        print(json.dumps({"status": "refused", "reason": "baseline_column_drift_before_edit",
                          "columns": pre_drift}, ensure_ascii=False))
        return 2

    script_sha = sha(ROOT / BAR_SCRIPT)
    note = (
        "2026-11-10 业主改造：头顶对话框只保留「正在说话」的示意（固定 0.86×0.46 m 小框 + 三点跳动，无文字），"
        "所有对话与系统信息的文字统一到底栏；底栏宽度改为视口 70%（左右各 15%）、贴底 24 px，字号不变。"
        "**自言自语（开灯/关灯等 bark 短句）仍用头顶文字气泡**（业主追加：「电灯开关这类自言自语的时候需要保留」）。"
        f"底栏源={BAR_SCRIPT}；示意形态源={BUBBLE_SCRIPT}；两者挂载转发={BARK_SCRIPT}。"
        "本行是程序化控件/几何，不是美术文件资产，故 T 列 SHA 取底栏入口脚本哈希，"
        "用于「实现未变」的定点核对；不冒充 TSCN/GLB 资产哈希。"
        "示意框三点与尾巴均为程序几何，无独立 Prefab，不另建道具/特效资产行。"
        "快进（空格/左键/回车）沿用既有两段语义：打字中→全显，已全显→下一句。"
        "制作状态=原型已接入，未做正式美术母版；验收见 docs/v0.1/development/2026-11-10_dialogue_bottom_bar.md。"
    )
    values = [
        ASSET_ID, NAME, CATEGORY, SUBTYPE, LOGIC, "root", None, "屏幕空间",
        "默认隐藏 / 对话逐字 / 示意框三点循环",
        "跨场景（基地、塔楼、远征）",
        "原型已接入", "P0", "v001",
        "底栏=70%视口宽、118px高、贴底24px；正文19px/署名15px/提示13px；示意框0.86×0.46m",
        f"{BAR_SCRIPT}；{BUBBLE_SCRIPT}",
        f"{DESIGN}；{TECH}",
        "对话;字幕;底栏;气泡;示意框;打字机;快进;DIALOGUE-UI",
        None, None, script_sha, "CodeBuddy", "2026-11-10",
        "项目原创程序控件与程序几何（无贴图、无自定义 shader）",
        "—", note,
    ]
    old_row = max(r for r, _ in read_source_rows(ws))
    row = append_row(ws, values, old_row)
    extend(ws, book["总览"], row)
    version = log(book, "对话文字统一底栏 + 头顶示意框",
                  f"{ASSET_ID}；{NAME}；资产主表!A{row}；仅本行登记，其余资产不动。")
    save_book(book, path, expected)

    baseline["assets"][ASSET_ID] = {"v": _row_digest(tuple(values)), "c": CATEGORY, "d": DOMAIN}
    collected = []
    for domain in INDEX.domains:
        collected += read_source_rows(load_workbook(domain.path)[ASSET_SHEET])
    assert all(baseline["assets"][aid] == record for aid, record in frozen["assets"].items() if aid != ASSET_ID)
    baseline["asset_count"] = len(baseline["assets"])
    baseline["column_digests"] = {str(c): col_digest(collected, c) for c in CONTENT_COLUMNS}
    baseline["category_counts"] = dict(sorted(Counter(v[2] for _, v in collected).items()))
    baseline["sheet_digests"] = frozen["sheet_digests"]
    baseline.setdefault("targeted_updates", []).append({
        "date": "2026-11-10",
        "asset_id": [ASSET_ID],
        "operation": "Add one UI row (dialogue bar + head indicator); no prefab page for ui domain",
        "previous_recorded_sheet_digest": None,
        "actual_before_sheet_digest": None,
        "after_sheet_digest": None,
        "record": "docs/v0.1/development/2026-11-10_dialogue_bottom_bar.md",
    })
    save_baseline(baseline, expected)

    dump(SESSION / "register_result.json", {
        "asset_id": ASSET_ID, "asset_row": row, "log_version": version,
        "bar_script_sha": script_sha, "bubble_script_sha": sha(ROOT / BUBBLE_SCRIPT),
        "bark_script_sha": sha(ROOT / BARK_SCRIPT),
        "baseline_asset_count": baseline["asset_count"],
    })
    print(json.dumps({"status": "registered", "asset_row": row, "log_version": version,
                      "bar_script_sha": script_sha}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
