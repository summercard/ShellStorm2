# -*- coding: utf-8 -*-
"""2026-09-20 收尾验证：wall_floor_facility_kit 碰撞一致性断言

做四件事：
  基线  – 修复后 4 个相关场景应全绿
  对照A – 把 kit 的「设施纯视觉」声明改回 true → 断言必须变红（证明守卫活着）
  对照B – 把 north_server_00 的碰撞形 disabled=true（声明仍=1）→ 必须报 MISMATCH
          （证明断言读的是真实启用的形，而不只是回读元数据）
  复验  – 两次还原后必须重新全绿
探针进程可能不自行退出（autoload 常驻），统一用 subprocess 超时兜住；
只要日志里出现 marker 即视为该场景通过。
"""
import os
import re
import subprocess
import sys

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
GODOT = r"I:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe"
OUT = os.path.join(ROOT, "_scratch", "facility_kit_rc")

KIT = os.path.join(ROOT, "assets/art/environments/tower_zones/battle/runtime/"
                         "wall_floor_facility_kit/wall_floor_facility_kit_root_top3d.tscn")
SRV = os.path.join(ROOT, "assets/art/environments/tower_zones/battle/runtime/"
                         "entry_safe_room/north_server_00/north_server_00_root_top3d.tscn")

MARKER_RE = re.compile(r"[A-Z0-9_]+_(?:OK|PASS)")
FAIL_RE = re.compile(r"FACILITY_[A-Z_]+(?::[A-Za-z0-9_]+)?(?: declared=\d+ actual=\d+)?")
ERR_RE = re.compile(r"^ERROR|SCRIPT ERROR", re.M)

results = []


def run_scene(scene, tag, timeout=300):
    os.makedirs(OUT, exist_ok=True)
    log = os.path.join(OUT, "%s.log" % tag)
    cmd = [GODOT, "--headless", "--path", ".", "res://tests/verification/%s.tscn" % scene]
    status = "ok"
    try:
        with open(log, "wb") as fh:
            rc = subprocess.call(cmd, cwd=ROOT, stdout=fh, stderr=subprocess.STDOUT,
                                 timeout=timeout)
    except subprocess.TimeoutExpired:
        status = "timeout"
        rc = None
    with open(log, "rb") as fh:
        text = fh.read().decode("utf-8", "replace")
    markers = sorted(set(MARKER_RE.findall(text)))
    fails = sorted(set(FAIL_RE.findall(text)))
    nerr = len(ERR_RE.findall(text))
    row = dict(scene=scene, tag=tag, rc=rc, status=status,
               markers=markers, fails=fails, nerr=nerr, log=log)
    results.append(row)
    print("  %-14s exit=%-5s err=%-3s status=%-7s marker=%s fail=%s"
          % (tag, rc, nerr, status, markers or "-", fails or "-"))
    sys.stdout.flush()
    return row


def read_bytes(path):
    with open(path, "rb") as fh:
        return fh.read()


def swap(path, old, new, backup_suffix):
    data = read_bytes(path)
    old_b = old.encode("utf-8")
    if data.count(old_b) != 1:
        raise SystemExit("!! %s 命中 %d 次: %r" % (path, data.count(old_b), old))
    with open(path + backup_suffix, "wb") as fh:
        fh.write(data)
    with open(path, "wb") as fh:
        fh.write(data.replace(old_b, new.encode("utf-8")))


def restore(path, backup_suffix):
    bak = path + backup_suffix
    if not os.path.exists(bak):
        raise SystemExit("!! 备份不存在: %s" % bak)
    os.replace(bak, path)


print("=== 1) 基线：修复后应全绿 ===")
run_scene("verify_battle_wall_floor_facility_kit", "base_kit")
run_scene("probe_safe_room_facility_collision", "base_collision_probe")
run_scene("verify_expedition_level01_flow", "base_expedition")
run_scene("probe_safe_room_v007_integration", "base_integration")

print("\n=== 2) 对照A：kit 声明改回「设施纯视觉」 → 必须变红 ===")
swap(KIT, "metadata/visual_only = false", "metadata/visual_only = true", ".rcA")
run_scene("verify_battle_wall_floor_facility_kit", "rcA_visual_only")
restore(KIT, ".rcA")
print("  已还原 kit 声明")
run_scene("verify_battle_wall_floor_facility_kit", "rcA_restored")

print("\n=== 3) 对照B：north_server_00 碰撞形 disabled=true（声明仍=1）→ 必须报 MISMATCH ===")
srv = read_bytes(SRV).decode("utf-8", "replace")
m = re.search(r'\[node name="CollisionShape3D"[^\]]*\]\r?\n((?:[^\r\n]*\r?\n)*?)', srv)
if not m:
    raise SystemExit("!! 未找到 north_server_00 的 CollisionShape3D 节点")
block = m.group(0)
eol = "\r\n" if "\r\n" in srv else "\n"
swap(SRV, block, block.rstrip("\r\n") + eol + "disabled = true" + eol, ".rcB")
run_scene("verify_battle_wall_floor_facility_kit", "rcB_shape_disabled")
restore(SRV, ".rcB")
print("  已还原 north_server_00")
run_scene("verify_battle_wall_floor_facility_kit", "rcB_restored")

print("\n=== 判定 ===")
def find(tag):
    for r in results:
        if r["tag"] == tag:
            return r
    return None

ok = True
for tag in ("base_kit", "rcA_restored", "rcB_restored", "base_collision_probe",
            "base_expedition", "base_integration"):
    r = find(tag)
    passed = bool(r["markers"]) and r["nerr"] == 0
    print("  [%s] %-22s marker=%s err=%d" % ("PASS" if passed else "FAIL", tag,
                                             r["markers"] or "-", r["nerr"]))
    ok = ok and passed

rA = find("rcA_visual_only")
a_ok = "FACILITY_VISUAL_ONLY_STILL_TRUE" in rA["fails"]
print("  [%s] 对照A 必须报 FACILITY_VISUAL_ONLY_STILL_TRUE -> %s"
      % ("PASS" if a_ok else "FAIL", rA["fails"]))
ok = ok and a_ok

rB = find("rcB_shape_disabled")
b_ok = any(f.startswith("FACILITY_COLLISION_MISMATCH") for f in rB["fails"])
print("  [%s] 对照B 必须报 FACILITY_COLLISION_MISMATCH -> %s"
      % ("PASS" if b_ok else "FAIL", rB["fails"]))
ok = ok and b_ok

print("\nRESULT: %s" % ("ALL_OK" if ok else "PROBLEM"))
sys.exit(0 if ok else 1)
