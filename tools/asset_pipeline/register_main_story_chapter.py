"""主线3.1—3.3账本定点登记；只写分账本、基线和资产清单。

依次执行 --phase audit / assets / prefabs / verify。
每个写事务先生成当前快照，检测并发变化；不接受其他资产或分页的摘要漂移。
"""
from __future__ import annotations

import argparse
from collections import Counter
from copy import copy, deepcopy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from ledger_registry import LedgerIndex
from workspace_paths import work_path
from split_asset_ledger import (
    ASSET_SHEET, HEADER_ROW, FIRST_DATA_ROW, COLUMN_COUNT, CONTENT_COLUMNS,
    _row_digest, col_digest, read_source_rows, sheet_digest,
    dedupe_key_formula, dedupe_result_formula,
)
from openpyxl import load_workbook
from openpyxl.utils import get_column_letter

INDEX = LedgerIndex.load(ROOT)
SESSION = work_path("sessions/2026-11-10_main_story_ledger/session.json").parent
BASELINE = ROOT / "assets/registry/ledger_split_baseline.json"
MANIFEST = ROOT / "assets/art/props/main_story/asset_manifest.json"
DESIGN = "docs/v0.1/design/主线剧情3.1至3.3与四钥匙设计.md"
KEY = "ITM-MAIN-STORY-RARE-EARTH-KEY"
PEDESTAL = "PRP-BASE99-MAIN-STORY-KEY-PEDESTAL"
NPC = "CHR-PLY-BUNNY01-NPC-GREEN"
BOSS = "ENM-BOSS-MONITOR002-3D"
UI = "UI-SCREEN-LEVEL-SELECT"
TOUCHED = {KEY, PEDESTAL, NPC, BOSS, UI}
DOMAINS = ("props", "scenes", "characters", "enemies", "ui")
CONTENT = ROOT / INDEX.raw["content_ledgers"]["inventory_items"]["path"]
KEY_PATH = "assets/art/props/main_story/runtime/rare_earth_key.tscn"
PEDESTAL_PATH = "assets/art/props/main_story/runtime/main_story_pedestal.tscn"
KEY_SCRIPT = "src/narrative/MainStoryKeyVisual3D.gd"
PEDESTAL_SCRIPT = "src/narrative/MainStoryPedestal3D.gd"
MARKER = "2026-11-10 主线3.1—3.3"


def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=1, default=str) + "\n", encoding="utf-8")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def registry_files():
    return [ROOT / "assets/registry/ledger_index.json", INDEX.master_path, BASELINE,
            *INDEX.ledger_paths(), CONTENT]


def source_files():
    files = set()
    for folder in ("src", "scenes", "data"):
        files.update(p for p in (ROOT / folder).rglob("*") if p.is_file())
    files.update((ROOT / KEY_PATH, ROOT / PEDESTAL_PATH))
    return sorted(files)


def hashes(paths):
    return {p.relative_to(ROOT).as_posix(): sha(p) for p in paths}


def snapshot(label):
    stamp = datetime.now().strftime("%Y-%m-%d_%H%M%S_%f")
    parent = ROOT.parent / "ShellStorm2-backup"
    assert parent.is_dir()
    target = parent / f"{stamp}_main_story_ledger_{label}" / "before_edits"
    target.mkdir(parents=True)
    before = hashes(registry_files())
    for path in registry_files():
        dest = target / path.relative_to(ROOT)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest)
        assert sha(dest) == before[path.relative_to(ROOT).as_posix()]
    assert hashes(registry_files()) == before, "快照期间发生并发修改，停止"
    record = {"snapshot": str(target), "registry_hashes": before,
              "source_hashes": hashes(source_files()),
              "git_status": subprocess.check_output(["git", "status", "--porcelain", "-uall"], cwd=ROOT).decode("utf-8")}
    dump(SESSION / f"snapshot_{label}.json", record)
    return record


def state():
    return json.loads((SESSION / "session.json").read_text(encoding="utf-8"))


def guard(expected):
    actual = hashes(registry_files())
    assert actual == expected, "登记文件存在并发修改；停止，禁止用旧副本覆盖当前事务"


def save_book(book, path, expected):
    guard(expected)
    fd, temp = tempfile.mkstemp(suffix=".xlsx", dir=path.parent)
    os.close(fd)
    try:
        book.save(temp)
        # 写后用zip层核对公式和DV，保留数组公式的既有表不作修复。
        with zipfile.ZipFile(temp) as archive:
            assert archive.testzip() is None
        guard(expected)
        os.replace(temp, path)
        expected[path.relative_to(ROOT).as_posix()] = sha(path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def save_baseline(value, expected):
    guard(expected)
    temp = SESSION / "baseline_pending.json"
    dump(temp, value)
    guard(expected)
    shutil.copyfile(temp, BASELINE)
    expected[BASELINE.relative_to(ROOT).as_posix()] = sha(BASELINE)


def find(ws, aid):
    found = [r for r, v in read_source_rows(ws) if v[0] == aid]
    assert len(found) == 1, (aid, found)
    return found[0]


def append_row(ws, values, template):
    last = max((c.row for row in ws for c in row if c.value is not None), default=HEADER_ROW)
    row = last + 1
    for c, value in enumerate(values, 1):
        ws.cell(row, c)._style = copy(ws.cell(template, c)._style)
        ws.cell(row, c).value = value
    ws.row_dimensions[row].height = ws.row_dimensions[template].height
    return row


def log(book, title, details):
    ws = book["域变更日志"]
    versions = []
    for row in ws:
        match = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", str(row[0].value or ""))
        if match:
            versions.append(tuple(map(int, match.groups())))
    version = max(versions)
    new_version = f"v{version[0]}.{version[1]}.{version[2] + 1}"
    append_row(ws, [new_version, "2026-11-10", title, "主线3.1—3.3", details,
                    "仅资产登记；游戏代码、模型与已有外观哈希不变；既有红项不批量修复", "CodeBuddy"], ws.max_row)
    return new_version


def extend(ws, overview, old, last):
    for row in range(FIRST_DATA_ROW, last + 1):
        ws.cell(row, 18).value = dedupe_key_formula(row)
        ws.cell(row, 19).value = dedupe_result_formula(row, last)
    mandatory = {"A6", "C6", "E6", "G6", "B10", "C10", "B11", "C11"}
    changed = set()
    # 场景域有三种大类，额外两行也必须随新末行延长。
    for row in overview:
        for cell in row:
            value = cell.value
            if isinstance(value, str) and value.startswith("=") and "资产主表" in value:
                cell.value = re.sub(r"(:\$?[A-Z]+\$?)\d+", lambda m: m[1] + str(last), value)
                changed.add(cell.coordinate)
    assert mandatory <= changed
    for dv in list(ws.data_validations.dataValidation):
        new_dv = deepcopy(dv)
        ranges = []
        for rng in dv.sqref.ranges:
            if rng.min_col == rng.max_col and rng.min_col in (3, 11, 12) and rng.min_row == FIRST_DATA_ROW:
                letter = get_column_letter(rng.min_col)
                ranges.append(f"{letter}{FIRST_DATA_ROW}:{letter}{last}")
            else:
                ranges.append(str(rng))
        new_dv.sqref = " ".join(ranges)
        ws.data_validations.dataValidation.remove(dv)
        ws.add_data_validation(new_dv)
    new_cf = type(ws.conditional_formatting)()
    for cf, rules in ws.conditional_formatting._cf_rules.items():
        ref = re.sub(r"(:[A-Z]+)\d+", lambda m: m[1] + str(last), str(cf.sqref))
        for rule in rules:
            new_cf.add(ref, deepcopy(rule))
    ws.conditional_formatting = new_cf
    ws.auto_filter.ref = f"A{HEADER_ROW}:Y{last}"


def check_dv(path, last):
    ns = {"x": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    with zipfile.ZipFile(path) as z:
        wb = ET.fromstring(z.read("xl/workbook.xml"))
        rel = {r.attrib["Id"]: r.attrib["Target"] for r in ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))}
        s = next(s for s in wb.find("x:sheets", ns) if s.attrib["name"] == ASSET_SHEET)
        target = rel[s.attrib["{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"]]
        target = target.lstrip("/") if target.startswith("/") else "xl/" + target
        tree = ET.fromstring(z.read(target))
        refs = [dv.attrib["sqref"] for dv in tree.findall("x:dataValidations/x:dataValidation", ns)]
        assert all(f"{c}{FIRST_DATA_ROW}:{c}{last}" in refs for c in ("C", "K", "L")), refs
    return refs


def gates(label):
    dest = SESSION / label
    dest.mkdir(exist_ok=True)
    commands = [("structure", ["scripts/check_asset_registry.py", "--project-root", str(ROOT), "--scope", "structure", "--json-output", str(dest / "structure.json")])]
    commands += [(f"full_{d}", ["scripts/check_asset_registry.py", "--project-root", str(ROOT), "--scope", "full", "--ledger", d, "--json-output", str(dest / f"full_{d}.json")]) for d in DOMAINS]
    commands += [("verify_ledger_split", ["tools/asset_pipeline/verify_ledger_split.py", "--project-root", str(ROOT), "--json-output", str(dest / "verify_ledger_split.json")]),
                 ("naming", ["scripts/check_asset_runtime_naming.py", "--json"]),
                 ("media", ["scripts/check_media_asset_domains.py"]),
                 ("documentation", ["scripts/check_documentation_contracts.py"])]
    results = {}
    env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUTF8="1")
    for name, args in commands:
        args[0] = str(ROOT / args[0])
        process = subprocess.run([sys.executable, *args], cwd=dest, env=env, capture_output=True)
        (dest / f"{name}.stdout.log").write_bytes(process.stdout)
        (dest / f"{name}.stderr.log").write_bytes(process.stderr)
        results[name] = {"exit_code": process.returncode, "command": [sys.executable, *args]}
        print(label, name, "exit", process.returncode, flush=True)
    dump(dest / "exit_codes.json", results)
    return results


def new_asset(aid, name, category, subtype, logic, path, script, spec, note):
    return [aid, name, category, subtype, logic, "root_3d", None, "Top3D / Godot Y-up",
            "display / present / handoff / insert" if aid == KEY else "four_slots / deposited_N_of_4 / pulse",
            "主线3.2高级箱/3.3交接/99F持久插槽" if aid == KEY else "99F mission_operations附加固定设施表现",
            "原型已接入", "P1", "v001", spec, path, f"{script}；{DESIGN}",
            "稀土主线钥匙;mq_key_rare_earth;非背包" if aid == KEY else "主线台座;四插槽;N/4;纯视觉",
            None, None, sha(ROOT / path), "CodeBuddy", "2026-11-10", "项目原创程序几何；无Blender/GLB", script, note]


def assets():
    saved = state()
    assert saved["phase"] == "audit"
    guard(saved["registry_hashes"])
    snap = snapshot("assets")
    expected = snap["registry_hashes"]
    books = {d: load_workbook(INDEX.domain_for_key(d).path) for d in DOMAINS}
    all_ids = [v[0] for d in INDEX.domains for _, v in read_source_rows(load_workbook(d.path)[ASSET_SHEET])]
    assert KEY not in all_ids and PEDESTAL not in all_ids
    assert not any("MAIN-STORY" in str(a) for a in all_ids), "已有相同用途登记，须先核对"
    for domain in INDEX.domains:
        for _, existing in read_source_rows(load_workbook(domain.path)[ASSET_SHEET]):
            assert existing[4] not in {"mq_key_rare_earth", "main_story_key_pedestal"}, "逻辑ID已存在"
            assert existing[14] not in {KEY_PATH, PEDESTAL_PATH}, "路径已存在"
            assert existing[19] not in {sha(ROOT / KEY_PATH), sha(ROOT / PEDESTAL_PATH)}, "同SHA资产已存在"
    note_key = (MARKER + "：程序化硬边金色电子key；TSCN内BoxMesh与四材质，表现源=" + KEY_SCRIPT +
                "。无Blender/GLB，未完成正式美术优化。稳定key_id=mq_key_rare_earth；永久所有权唯一Owner="
                "BaseManager.main_story，领取=BaseManager.claim_main_story_key，安装=BaseManager.deposit_main_story_key。"
                "箱内升起/手持/交接/插槽为同一事实的视觉投影；非普通背包，不在ItemRegistry重复造物品。")
    note_pedestal = (MARKER + "：四插槽；安装数及N/4环来自BaseManager.get_main_story_snapshot()的deposited记录。"
                     "可独立加载的附加固定设施表现，纯视觉无新增碰撞；N/4文字在全息UI，台座以四槽与四分之一环表示。"
                     "程序源=" + PEDESTAL_SCRIPT + "；无Blender/GLB，未完成正式美术优化。"
                     "按权威场景道具/facility/PRP登记；现有Prefab metadata/asset_id=ENV-MAIN-STORY-KEY-PEDESTAL，"
                     "与账本ID不一致，本事务明确记录但不改运行场景；不得将其登记为第二件资产。")
    specs = [
        ("props", new_asset(KEY, "稀土主线钥匙", "道具", "key", "mq_key_rare_earth", KEY_PATH, KEY_SCRIPT,
                            "标称长0.65m；硬边BoxMesh；金属金/深紫/青色芯/金色线路四材质；无新碰撞", note_key)),
        ("scenes", new_asset(PEDESTAL, "99F主线钥匙台座", "场景道具", "facility", "main_story_key_pedestal", PEDESTAL_PATH, PEDESTAL_SCRIPT,
                             "底座2.65×0.14×0.72m；四槽间距0.46m；32段环；Node3D无碰撞", note_pedestal)),
    ]
    rows_added = {}
    for domain, values in specs:
        book = books[domain]
        ws = book[ASSET_SHEET]
        assert ws.cell(HEADER_ROW, 1).value == "AssetID"
        old = max(r for r, _ in read_source_rows(ws))
        row = append_row(ws, values, old)
        assert row == old + 1
        extend(ws, book["总览"], old, row)
        rows_added[domain] = row
        log(book, "新增主线原型资产", f"{values[0]}；{values[1]}；仅原型已接入；Prefab分页另开独立事务。")
    npc = books["characters"][ASSET_SHEET]
    r = find(npc, NPC)
    npc.cell(r, 9).value = str(npc.cell(r, 9).value) + "；3.1 talk / point；3.3真实run_to_player / receive_key / move_to_slot / insert_key（程序关节及手部投影）"
    npc.cell(r, 25).value = str(npc.cell(r, 25).value or "") + "\n" + MARKER + "：复用正式绿苔外观与衣柜绿色。3.1说话/指向真实mission_operations；3.3从原站位真实跑来、接同一钥匙投影、走到台座并插入；源=src/npc/NpcCharacter3D.gd + src/narrative/MainStoryChapter3D.gd + " + KEY_SCRIPT + "；不新增角色/模型/Blender动作源，AssetID及外观SHA不变。"
    npc.cell(r, 22).value = "2026-11-10"
    log(books["characters"], "绿苔主线演出复用", "补资产主表状态/动画及备注；不修改摘要锁定的动画专表。")
    boss = books["enemies"][ASSET_SHEET]
    r = find(boss, BOSS)
    boss.cell(r, 25).value = str(boss.cell(r, 25).value or "") + "\n" + MARKER + "：3.2复用Boss002，顺序=未激活门闩→对白→怒吼→原6.4秒激活；5.4秒归还输入（激活完成前1秒），4.4秒开始还镜；攻击等真实激活完成。源=src/narrative/MainStoryChapter3D.gd / src/enemy3d/Enemy3D.gd / src/enemy3d/MonitorBossCombat.gd / data/narrative/nar_main_032_monitor_audience.json；模型、动画母版、路径、版本与外观SHA不变。"
    boss.cell(r, 22).value = "2026-11-10"
    log(books["enemies"], "Boss002主线演出复用", BOSS + "仅补复用备注与更新时间，不修改既有公式、模型哈希或动画专表。")
    ui = books["ui"][ASSET_SHEET]
    r = find(ui, UI)
    ui.cell(r, 9).value = "四正式入口常显；未解锁红色几何电子锁；中心已安装N/4；解锁只读BaseManager进度"
    ui.cell(r, 14).value = "正式入口=expedition_01/03/02/04；测试99仅开发用途；第四目标未制作时保持锁定；中心已安装N/4"
    ui.cell(r, 25).value = str(ui.cell(r, 25).value or "") + "\n" + MARKER + "：替代旧三入口/02通关01后解锁口径；四正式入口按数据库→无限公馆→破败旅馆→第四目标显示，未解锁为红色几何电子锁。中心已安装N/4来自BaseManager快照，菜单只读并提交原出发事务。源=scenes/RogueMapSelectMenu.gd / src/ui/HologramCity3D.gd；代码证据哈希另记asset_manifest.json，不把脚本SHA写入主路径TSCN的T列；本行T列保持原值，既有SHA漂移不在本次消除。"
    ui.cell(r, 22).value = "2026-11-10"
    log(books["ui"], "四入口及电子锁主线导航", UI + "补四正式入口、红色电子锁及中心已安装N/4，主场景哈希不变。")
    nav = load_workbook(CONTENT)
    ws = nav["非背包与待设计"]
    assert not any(c.value == "mq_key_rare_earth" for row in ws for c in row)
    append_row(ws, ["mq_key_rare_earth", "src/base/BaseManager.gd#claim_main_story_key / deposit_main_story_key；表现源=" + KEY_SCRIPT + "；PackedScene=" + KEY_PATH + "；源AssetID=" + KEY + "；资产主表=" + INDEX.domain_for_key("props").relative_path + "#资产主表!A" + str(rows_added["props"]),
                    "稀土主线钥匙：永久主线进度，非普通背包，不在ItemRegistry注册第二物品，不可卖/丢弃/合成；领取Owner=BaseManager，安装Owner=BaseManager，查询=get_main_story_snapshot；main_story.keys.mq_key_rare_earth；高级首领箱领取，99F台座安装；无Blender/GLB，程序源如左；原型已接入，不声称正式美术优化。"], ws.max_row)
    for domain, book in books.items():
        save_book(book, INDEX.domain_for_key(domain).path, expected)
    save_book(nav, CONTENT, expected)
    for domain in rows_added:
        check_dv(INDEX.domain_for_key(domain).path, rows_added[domain])
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    frozen = deepcopy(baseline)
    collected = []
    for domain in INDEX.domains:
        for number, values in read_source_rows(load_workbook(domain.path)[ASSET_SHEET]):
            collected.append((number, values))
            if values[0] in TOUCHED:
                baseline["assets"][values[0]] = {"v": _row_digest(values), "c": values[2], "d": domain.key}
    assert all(baseline["assets"][aid] == value for aid, value in frozen["assets"].items() if aid not in TOUCHED)
    baseline["asset_count"] = len(baseline["assets"])
    baseline["column_digests"] = {str(c): col_digest(collected, c) for c in CONTENT_COLUMNS}
    baseline["category_counts"] = dict(sorted(Counter(v[2] for _, v in collected).items()))
    assert baseline["sheet_digests"] == frozen["sheet_digests"]
    save_baseline(baseline, expected)
    manifest = {
        "schema_version": 1, "registered_at": "2026-11-10", "scope": "主线3.1—3.3账本登记；非运行配置",
        "production_status": "原型已接入", "art_master_complete": False,
        "state_owner": "BaseManager.main_story", "key_id": "mq_key_rare_earth", "ordinary_inventory_item": False,
        "claim_owner": "BaseManager.claim_main_story_key", "deposit_owner": "BaseManager.deposit_main_story_key",
        "assets": [{"asset_id": v[0], "asset_ledger": INDEX.domain_for_key(d).relative_path + "#资产主表",
                    "prefab": v[14], "sha256": v[19], "source_kind": "procedural_tscn" if d == "props" else "procedural_gdscript",
                    "program_source": KEY_SCRIPT if d == "props" else PEDESTAL_SCRIPT,
                    "blender_source": None, "glb": None, "collision": "无新增碰撞"} for d, v in specs],
        "metadata_discrepancy": {"prefab": PEDESTAL_PATH, "runtime_metadata_asset_id": "ENV-MAIN-STORY-KEY-PEDESTAL", "ledger_asset_id": PEDESTAL,
                                 "reason": "权威场景道具/facility使用PRP；ENV-BASE99建议不满足前缀×大类契约；不改游戏资产元数据，不重复登记"},
        "reused_assets": [NPC, BOSS, UI], "reuse_asset_primary_sha_policy": "保留原账本T列；脚本证据不冒充scene/model哈希",
        "evidence_files": hashes([ROOT / p for p in [KEY_PATH, PEDESTAL_PATH, KEY_SCRIPT, PEDESTAL_SCRIPT,
                           "src/narrative/MainStoryChapter3D.gd", "src/base/BaseManager.gd", "src/npc/NpcCharacter3D.gd",
                           "src/ui/HologramCity3D.gd", "scenes/RogueMapSelectMenu.gd", "src/enemy3d/Enemy3D.gd", "src/enemy3d/MonitorBossCombat.gd", DESIGN]]),
        "validation": "本事务仅登记已有实现；不冒充新增Godot运行或真实渲染验收通过；门禁与差异见工程外session报告",
    }
    assert not MANIFEST.exists()
    dump(MANIFEST, manifest)
    saved.update(phase="assets", registry_hashes=expected, rows_added=rows_added)
    dump(SESSION / "session.json", saved)
    print("MAIN_STORY_ASSET_ROWS_REGISTERED", rows_added)


def prefabs():
    saved = state()
    assert saved["phase"] == "assets"
    guard(saved["registry_hashes"])
    snap = snapshot("prefabs")
    expected = snap["registry_hashes"]
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    before_baseline = deepcopy(baseline)
    changes = []
    for domain, page, aid, name, path, script in [
        ("props", "3D-物品", KEY, "稀土主线钥匙", KEY_PATH, KEY_SCRIPT),
        ("scenes", "3D-设施", PEDESTAL, "99F主线钥匙台座", PEDESTAL_PATH, PEDESTAL_SCRIPT),
    ]:
        book = load_workbook(INDEX.domain_for_key(domain).path)
        ws = book[page]
        assert ws.cell(HEADER_ROW - 1, 1).value == "AssetID"
        assert not any(c.value == aid for row in ws for c in row)
        old_digest = sheet_digest(ws)
        row = append_row(ws, [aid, name, path, None, script,
                    "同一永久钥匙的箱内/手持/交接/插槽投影；非普通背包" if aid == KEY else "附加固定设施四插槽、N/4环和脉冲；BaseManager快照只读投影",
                    script, "无", "无新增碰撞", "无", "标称长0.65m；BoxMesh四材质" if aid == KEY else "底座2.65×0.14×0.72m；四槽间距0.46m",
                    "Godot Y-up；程序源实际变换", "主线3.2/3.3/99F情报室", "原型已接入", "v001",
                    "E列为程序源脚本而非Blender；无Blender/GLB；未完成正式美术优化；" +
                    ("key_id=mq_key_rare_earth；Owner=BaseManager" if aid == KEY else "运行metadata/asset_id=ENV-MAIN-STORY-KEY-PEDESTAL，与账本PRP分类ID不同，显式追踪不修改游戏资产")], max(5, ws.max_row))
        log(book, "独立事务：真实Prefab分页登记", f"{page}!A{row}={aid}；只重建本分页sheet digest，不接纳其他分页既有漂移。")
        save_book(book, INDEX.domain_for_key(domain).path, expected)
        after_digest = sheet_digest(load_workbook(INDEX.domain_for_key(domain).path)[page])
        baseline["sheet_digests"][page] = after_digest
        changes.append({"domain": domain, "sheet": page, "row": row, "recorded_before": before_baseline["sheet_digests"].get(page),
                        "actual_before": old_digest, "after": after_digest, "preexisting_drift": before_baseline["sheet_digests"].get(page) != old_digest})
    assert baseline["assets"] == before_baseline["assets"]
    assert all(baseline["sheet_digests"][s] == v for s, v in before_baseline["sheet_digests"].items() if s not in {"3D-物品", "3D-设施"})
    save_baseline(baseline, expected)
    dump(SESSION / "prefab_transactions.json", changes)
    saved.update(phase="prefabs", registry_hashes=expected)
    dump(SESSION / "session.json", saved)
    print("MAIN_STORY_PREFABS_REGISTERED", changes)


def value(cell):
    v = cell.value
    if hasattr(v, "text"):
        return {"formula_type": type(v).__name__, "text": v.text, "ref": v.ref}
    return v


def verify():
    saved = state()
    assert saved["phase"] in {"prefabs", "verified"}
    guard(saved["registry_hashes"])
    before = json.loads((SESSION / "snapshot_audit.json").read_text(encoding="utf-8"))
    snap = Path(before["snapshot"])
    differences = []
    for path in [INDEX.master_path, *INDEX.ledger_paths(), CONTENT]:
        old = load_workbook(snap / path.relative_to(ROOT))
        new = load_workbook(path)
        assert old.sheetnames == new.sheetnames
        for name in old.sheetnames:
            a, b = old[name], new[name]
            for r in range(1, max(a.max_row, b.max_row) + 1):
                for c in range(1, max(a.max_column, b.max_column) + 1):
                    x, y = value(a.cell(r, c)), value(b.cell(r, c))
                    if x != y:
                        differences.append({"file": path.relative_to(ROOT).as_posix(), "sheet": name,
                                            "cell": b.cell(r, c).coordinate, "before": x, "after": y,
                                            "kind": "新增单元格" if x is None else "既有单元格变更"})
    dump(SESSION / "cell_differences.json", differences)
    initial_bl = json.loads((snap / BASELINE.relative_to(ROOT)).read_text(encoding="utf-8"))
    current_bl = json.loads(BASELINE.read_text(encoding="utf-8"))
    changed_assets = [aid for aid, v in current_bl["assets"].items() if initial_bl["assets"].get(aid) != v]
    assert set(changed_assets) == TOUCHED
    changed_sheets = [s for s, v in current_bl["sheet_digests"].items() if initial_bl["sheet_digests"].get(s) != v]
    assert set(changed_sheets) == {"3D-物品", "3D-设施"}
    # 除新增末行的必要派生列/范围之外，所有非目标资产内容列逐格不变。
    untouched_primary_hashes = []
    for d in INDEX.domains:
        old_rows = {v[0]: v for _, v in read_source_rows(load_workbook(snap / d.path.relative_to(ROOT))[ASSET_SHEET])}
        new_rows = {v[0]: v for _, v in read_source_rows(load_workbook(d.path)[ASSET_SHEET])}
        for aid, old in old_rows.items():
            if aid not in TOUCHED:
                assert all(old[c - 1] == new_rows[aid][c - 1] for c in CONTENT_COLUMNS), aid
            else:
                assert old[19] == new_rows[aid][19], (aid, "外观SHA被修改")
                untouched_primary_hashes.append(aid)
    actual_sources = hashes(source_files())
    source_changes = sorted(k for k in set(actual_sources) | set(before["source_hashes"]) if actual_sources.get(k) != before["source_hashes"].get(k))
    dump(SESSION / "source_file_changes.json", source_changes)
    results = gates("after")
    comparisons = {}
    for name in results:
        a_path, b_path = SESSION / "before" / f"{name}.json", SESSION / "after" / f"{name}.json"
        if not a_path.exists() or not b_path.exists():
            continue
        a = json.loads(a_path.read_text(encoding="utf-8"))
        b = json.loads(b_path.read_text(encoding="utf-8"))
        def issues(data):
            raw = data.get("issues", data.get("failures", {}))
            def stable(item):
                text = json.dumps(item, ensure_ascii=False, sort_keys=True)
                return re.sub(r"object at 0x[0-9A-Fa-f]+", "object at <进程地址>", text)
            if isinstance(raw, dict):
                return Counter(stable({"kind": k, **item}) for k, items in raw.items() for item in items)
            return Counter(stable(item) for item in raw)
        x, y = issues(a), issues(b)
        comparisons[name] = {"新增报告项": [json.loads(v) for v in (y - x).elements()],
                             "不再报告项": [json.loads(v) for v in (x - y).elements()],
                             "共有报告项数量": sum((x & y).values()),
                             "说明": "verify标准报告最多列前40条，完整既有漂移另见baseline_drift对照"}
    dump(SESSION / "gate_issue_comparison.json", comparisons)
    drifts = {}
    for label, base_root, baseline in [("before", snap, initial_bl), ("after", ROOT, current_bl)]:
        row_drift, sheet_drift = [], []
        for d in INDEX.domains:
            book = load_workbook(base_root / d.path.relative_to(ROOT))
            for r, v in read_source_rows(book[ASSET_SHEET]):
                if v[0] in baseline["assets"] and _row_digest(v) != baseline["assets"][v[0]]["v"]:
                    row_drift.append(v[0])
            for page in d.sheet_scope:
                if page in baseline["sheet_digests"] and sheet_digest(book[page]) != baseline["sheet_digests"][page]:
                    sheet_drift.append(page)
        drifts[label] = {"row_digest_drift": row_drift, "sheet_digest_drift": sheet_drift}
    dump(SESSION / "baseline_drift_comparison.json", drifts)
    assert drifts["before"] == drifts["after"], "既有资产/专表漂移集合被意外改变"
    gate_counts = {}
    for name in ("structure", "full_props", "full_scenes", "full_characters", "full_enemies", "full_ui", "verify_ledger_split"):
        pair = {}
        for label in ("before", "after"):
            report = json.loads((SESSION / label / f"{name}.json").read_text(encoding="utf-8"))
            pair[label] = report.get("issue_counts", {"failure_count": report.get("failure_count")})
        gate_counts[name] = pair
    documentation_reports = []
    for label in ("before", "after"):
        text = (SESSION / label / "documentation.stdout.log").read_text(encoding="utf-8")
        documentation_reports.append(json.JSONDecoder().raw_decode(text)[0])
    dump(SESSION / "documentation_comparison.json", {
        "新增报告项": sorted(set(documentation_reports[1]["issues"]) - set(documentation_reports[0]["issues"])),
        "不再报告项": sorted(set(documentation_reports[0]["issues"]) - set(documentation_reports[1]["issues"])),
        "改前数量": len(documentation_reports[0]["issues"]), "改后数量": len(documentation_reports[1]["issues"])})
    guard(saved["registry_hashes"])
    summary = {"added_assets": sorted(TOUCHED - set(initial_bl["assets"])), "updated_assets": sorted(TOUCHED & set(initial_bl["assets"])),
               "changed_baseline_asset_records": sorted(changed_assets), "changed_sheet_digests": changed_sheets,
               "asset_count_before": initial_bl["asset_count"], "asset_count_after": current_bl["asset_count"],
               "primary_sha_preserved": untouched_primary_hashes, "source_changes_since_snapshot": source_changes,
               "cell_changes": len(differences), "gate_issue_counts": gate_counts,
               "gate_reports_truncated": "check_asset_registry每类最多保留40条详情，verify最多前40条；真实总数用issue_counts/failure_count；逐格和完整基线漂移另行对照",
               "new_gate_issues": {k: len(v["新增报告项"]) for k, v in comparisons.items()},
               "required_formula_rescope": "新增道具末行时按权威函数重写R/S，连带移除该表44×2个既有公式红项；场景1017行S扩到1023，非批量清债",
               "preexisting_unbaselined_assets_preserved": sorted(set(a for d in INDEX.domains for _, v in read_source_rows(load_workbook(d.path)[ASSET_SHEET]) for a in [v[0]]) - set(current_bl["assets"])),
               "snapshots": {label: json.loads((SESSION / f"snapshot_{label}.json").read_text(encoding="utf-8"))["snapshot"] for label in ("audit", "assets", "prefabs")},
               "exit_codes": {k: v["exit_code"] for k, v in results.items()},
               "runtime_tests": "本次未执行Godot/真实渲染；仅运行账本、命名、媒体及文档门禁", "session": str(SESSION)}
    dump(SESSION / "summary.json", summary)
    saved.update(phase="verified")
    dump(SESSION / "session.json", saved)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--phase", choices=("audit", "assets", "prefabs", "verify"), required=True)
    args = p.parse_args()
    if args.phase == "audit":
        assert not (SESSION / "session.json").exists(), "已有会话状态，拒绝覆盖"
        snap = snapshot("audit")
        dump(SESSION / "session.json", {"phase": "audit", "registry_hashes": snap["registry_hashes"]})
        gates("before")
        guard(snap["registry_hashes"])
    elif args.phase == "assets":
        assets()
    elif args.phase == "prefabs":
        prefabs()
    else:
        verify()


if __name__ == "__main__":
    main()
