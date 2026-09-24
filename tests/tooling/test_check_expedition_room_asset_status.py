#!/usr/bin/env python3
"""自测：check_expedition_room_asset_status.py 必须真的会对「文档 × 账本」不一致报红。

覆盖设计页 §3.1.1 的 A / B / B2 / C 四类判据 + 一个对照组。
文档用真实设计页的临时副本改坏；账本只读、不动。
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts/check_expedition_room_asset_status.py"
DESIGN_MD = ROOT / "docs/v0.1/design/远征关卡01设计.md"


def run(mutated: str) -> int:
    with tempfile.TemporaryDirectory() as temp_dir:
        doc = Path(temp_dir) / "expedition01.md"
        doc.write_text(mutated, encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(CHECKER), "--doc", str(doc)],
            capture_output=True,
        ).returncode


orig = DESIGN_MD.read_text(encoding="utf-8")

# 对照：原样必须通过
assert run(orig) == 0, "原样设计页被误判为不一致"

# A｜文档写了账本里查无此行的 AssetID
bad = orig.replace("ENV-EXPEDITION-L01-L-CORRIDOR", "ENV-EXPEDITION-L01-NOT-EXIST")
assert run(bad) == 1, "A 类（幽灵 AssetID）没有报红"

# B｜「账本制作状态」列里的级别 emoji 与账本推出的级别不符
bad = orig.replace("| 🟦 房间种类源已完成；QA PASS |", "| ✅ 房间种类源已完成；QA PASS |")
assert run(bad) == 1, "B 类（状态列级别不符）没有报红"

# B2｜「级别」列（房型整体）没按规则 3 取最低级
bad = orig.replace("| 🟦 房间种类源已完成；QA PASS | 🟦 已登记·未导出 |",
                   "| 🟦 房间种类源已完成；QA PASS | ✅ 已接入 |")
assert run(bad) == 1, "B2 类（房型整体级别未取最低）没有报红"

# C｜账本里的远征行被文档漏写
bad = re.sub(r"^\| 8 \| Boss竞技场.*$", "", orig, flags=re.M)
assert run(bad) == 1, "C 类（漏写账本已有的远征行）没有报红"

print("EXPEDITION_ASSET_STATUS_CHECKER_OK: 对照 + A/B/B2/C 四类不一致均按预期判定")
