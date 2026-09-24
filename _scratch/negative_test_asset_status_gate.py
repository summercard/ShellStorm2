# -*- coding: utf-8 -*-
"""受控负向测试：确认 check_expedition_room_asset_status.py 真的会红。
改完必定还原设计页（try/finally）。"""
import subprocess
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parents[1]
MD = ROOT / "docs/v0.1/design/远征关卡01设计.md"
PY = sys.executable
GATE = "scripts/check_expedition_room_asset_status.py"


def run():
    r = subprocess.run([PY, GATE], cwd=str(ROOT), capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def mutate(old, new, label):
    return mutate_multi([(old, new)], label)


def mutate_multi(pairs, label):
    orig = MD.read_bytes()
    t = orig.decode("utf-8")
    for old, new in pairs:
        if old not in t:
            print("  !! 找不到待改文本，跳过：%s（%r）" % (label, old[:40]))
            return None
    try:
        for old, new in pairs:
            t = t.replace(old, new, 1)
        MD.write_bytes(t.encode("utf-8"))
        code, out = run()
        tail = [l for l in out.splitlines() if l.strip().startswith("✗") or l.startswith("EXPEDITION_")]
        print("  [%s] exit=%d" % (label, code))
        for l in tail[:4]:
            print("      " + l.strip()[:130])
        return code
    finally:
        MD.write_bytes(orig)


print("=== 基线（未改动）===")
code0, out0 = run()
print("  exit=%d  %s" % (code0, "OK" if "EXPEDITION_ASSET_STATUS_OK" in out0 else "FAILED"))

print()
print("=== 负向测试 1：把走廊01 行的账本状态 emoji 从 🟦 改成 ✅（账本没改）===")
c1 = mutate("🟦 房间种类源已完成；QA PASS", "✅ 房间种类源已完成；QA PASS", "B 级别不一致")

print()
print("=== 负向测试 2：把 Boss 房那行的「未登记」标注整体抹掉（源未登记却不标注）===")
c2 = mutate_multi([
    ("② 未登记<br>③ 未登记", "② —<br>③ —"),
    ("🟨 有源·未登记（房型整体取最低级）", "🟦 已登记·未导出（房型整体取最低级）"),
], "D 未登记未标注")

print()
print("=== 负向测试 3：把文档里的 AssetID 改名（账本里不存在）===")
c3 = mutate("`ENV-EXPEDITION-L01-L-CORRIDOR` v003", "`ENV-EXPEDITION-L01-L-CORRIDOR-X` v003", "A 账本无此行")

print()
print("=== 还原后复跑 ===")
final_code, final_out = run()
print("  exit=%d  %s" % (final_code, "OK" if "EXPEDITION_ASSET_STATUS_OK" in final_out else "FAILED"))
print()
verdict = (code0 == 0 and c1 == 1 and c2 == 1 and c3 == 1 and final_code == 0)
print("负向测试结论：", "全部如预期（门禁不假绿）" if verdict else "有异常，需检查")
