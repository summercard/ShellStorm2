#!/usr/bin/env python3
"""取证：13 房设备注入是否为「纯插入」，且数值/行尾/位置全对。

比对 pre（_scratch/_dev_move_pre/）与 post（真实资产）：
  A. post 去掉设备区 = pre 逐行完全相同  -> 证明「只多不多不少、没动其它任何一行」
  B. 插入行数 = 26（5 注释+1 node+10 prop 的灯块 + 空行 + 1 注释+1 node+2 prop 的开关块 + 2 ext + 1 根 meta）
     —— 实际用「pre 行数 vs post 行数」差核算
  C. 设备节点是根节点之后的前两个 [node ...]
  D. 行尾：post 的 EOL 与 pre 一致（boss=CRLF，其余=LF），且无裸 CR / 无混合
  E. 关键值（enabled / energy / range / seed / transform）与预期待写值一致
  F. room_01/room_02：pre 与 post 字节完全相同（幂等，MOVED 不产生任何变化）
"""
from __future__ import annotations

import hashlib
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[1]
ASSET = REPO / "assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01"
PRE = REPO / "_scratch/_dev_move_pre"

LIGHT_HEAD = "; 房间中央顶灯"
SWITCH_HEAD = "; 墙面灯开关"
SWITCH_NODE = '[node name="RoomLightSwitch3D"'
EXT_LIGHT = '[ext_resource type="Script" path="res://src/world3d/WastelandLight3D.gd" id="900_authored_light"]'
EXT_SWITCH = '[ext_resource type="Script" path="res://src/world3d/RoomLightSwitch3D.gd" id="901_authored_switch"]'
ROOT_META = "metadata/authored_room_devices = true"
EXPECTED_ADDED = 27   # 2 ext + 1 根 meta + (空+16+1=18 灯) + (空+5=6 开关)

EXPECTED = {
    "start": ("true", "4.995000000000001", "14.62", "77001199",
              "Transform3D(1.1924881e-08, 0, 1, 0, 1, 0, -1, 0, 1.1924881e-08, 0, 9.28, 0)",
              "Transform3D(-1, 0, -3.1786506e-08, 0, 1, 0, 3.1786506e-08, 0, -1, -3.2999997, 0, -7.16)"),
    "room_01": ("false", "4.995", "37.6", "77105928",
                "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 5.357143, 9.28, 5.357143)",
                "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 12.5, 0, -22.16)"),
    "room_02": ("false", "4.995", "28.2", "77210657",
                "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
                "Transform3D(-1, 0, -8.742278e-08, 0, 1, 0, 8.742278e-08, 0, -1, -4.2, 0, 14.66)"),
    "room_03": ("false", "4.995000000000001", "28.2", "77315386",
                "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
                "Transform3D(-4.371139e-08, 0, -1, 0, 1, 0, 1, 0, -4.371139e-08, -14.660004, 0, 4.200001)"),
    "room_04": ("false", "4.995000000000001", "37.599999999999994", "77420115",
                "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, -7.5)",
                "Transform3D(-4.371139e-08, 0, 1, 0, 1, 0, -1, 0, -4.371139e-08, 22.160004, 0, -7.500002)"),
    "room_05": ("false", "4.995000000000001", "28.2", "77524844",
                "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
                "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 4.199997, 0, -29.66)"),
    "room_06": ("false", "4.995000000000001", "28.2", "77629573",
                "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
                "Transform3D(-1, 0, -8.742278e-08, 0, 1, 0, 8.742278e-08, 0, -1, -4.199997, 0, 19.66)"),
    "room_07": ("false", "4.995000000000001", "23.5", "77734302",
                "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
                "Transform3D(-4.371139e-08, 0, -1, 0, 1, 0, 1, 0, -4.371139e-08, -12.160004, 0, 4.199997)"),
    "room_08": ("false", "4.995000000000001", "37.599999999999994", "77839031",
                "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -5.357147, 9.28, -5.357147)",
                "Transform3D(-4.371139e-08, 0, 1, 0, 1, 0, -1, 0, -4.371139e-08, 19.660004, 0, -15)"),
    "room_09": ("false", "4.995000000000001", "28.2", "77943760",
                "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
                "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 4.199997, 0, -19.660004)"),
    "room_10": ("false", "4.995000000000001", "28.2", "78048489",
                "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
                "Transform3D(-1, 0, -8.742278e-08, 0, 1, 0, 8.742278e-08, 0, -1, -4.200001, 0, 14.660004)"),
    "boss": ("true", "4.995000000000001", "37.599999999999994", "78153218",
             "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
             "Transform3D(-4.371139e-08, 0, -1, 0, 1, 0, 1, 0, -4.371139e-08, -24.66, 0, 4.199997)"),
    "extraction": ("false", "4.995000000000001", "23.5", "78257947",
                   "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 9.28, 0)",
                   "Transform3D(-4.371139e-08, 0, 1, 0, 1, 0, -1, 0, -4.371139e-08, 12.16, 0, -4.199997)"),
}

IDEMPOTENT = ("room_01", "room_02")   # 本轮应原字节不变


def eol_of(raw: bytes) -> str | None:
    crlf = raw.count(b"\r\n")
    lone_lf = raw.count(b"\n") - crlf
    lone_cr = raw.count(b"\r") - crlf
    if lone_cr:
        return None
    if crlf and lone_lf:
        return None
    return "CRLF" if crlf else "LF"


def strip_device(lines: list[str]) -> list[str]:
    """去掉本次注入的**全部**新增行，应还原为 pre：

    · 2 条 ext_resource（灯脚本 / 开关脚本）
    · 根节点 meta `metadata/authored_room_devices = true`
    · 「空行 + 灯注释块 + 灯节点」与「空行 + 开关注释块 + 开关节点」两段
    """
    injected = {EXT_LIGHT, EXT_SWITCH, ROOT_META}
    kept = [l for l in lines if l not in injected]
    start = next(i for i, l in enumerate(kept) if l.startswith(LIGHT_HEAD))
    if start - 1 >= 0 and kept[start - 1].strip() == "":
        start -= 1
    sw = next(i for i, l in enumerate(kept) if l.startswith(SWITCH_NODE))
    end = sw + 1
    while end < len(kept) and kept[end].strip() != "" and not kept[end].startswith("["):
        end += 1
    return kept[:start] + kept[end:]


fails: list[str] = []
rows: list[tuple] = []

for room, exp in EXPECTED.items():
    name = f"f00_{room}_static_layout.tscn"
    pre_raw = (PRE / name).read_bytes()
    post_raw = (ASSET / name).read_bytes()

    pre_eol, post_eol = eol_of(pre_raw), eol_of(post_raw)
    sha_pre = hashlib.sha256(pre_raw).hexdigest()[:12]
    sha_post = hashlib.sha256(post_raw).hexdigest()[:12]

    pre_lines = pre_raw.decode("utf-8").replace("\r\n", "\n").rstrip("\n").split("\n")
    post_lines = post_raw.decode("utf-8").replace("\r\n", "\n").rstrip("\n").split("\n")

    if room in IDEMPOTENT:
        ok_idem = pre_raw == post_raw
        if not ok_idem:
            fails.append(f"{room}: 幂等失败，bytes 变了 ({sha_pre} -> {sha_post})")
        rows.append((room, "-", "幂等", "OK" if ok_idem else "FAIL", sha_pre, sha_post, post_eol))
        continue

    # A. 纯插入
    body = strip_device(post_lines)
    ok_a = body == pre_lines

    # B. 插入行数
    added = len(post_lines) - len(pre_lines)

    # C. 设备节点位置：根节点之后的前两个 [node ...]
    node_lines = [l for l in post_lines if l.startswith("[node ")]
    root_pos = next(i for i, l in enumerate(node_lines) if l.startswith('[node name="ExpeditionRoomStaticLayout'))
    ok_c = (node_lines[root_pos + 1].startswith('[node name="RoomCeilingLight"')
            and node_lines[root_pos + 2].startswith('[node name="RoomLightSwitch3D"'))

    # D. 行尾
    ok_d = (post_eol == pre_eol) and post_eol in ("LF", "CRLF")

    # E. 数值
    text = "\n".join(post_lines)
    en, energy, rng, seed, ltf, stf = exp
    checks_e = {
        "light_enabled": f"light_enabled = {en}" in text,
        "energy": f"energy = {energy}" in text,
        "light_range": f"light_range = {rng}" in text,
        "flicker_seed": f"flicker_seed = {seed}" in text,
        "light_tf": f"transform = {ltf}" in text,
        "switch_tf": f"transform = {stf}" in text,
        "root_meta": "metadata/authored_room_devices = true" in text,
    }
    ok_e = all(checks_e.values())

    for label, ok in (("A纯插入", ok_a), ("C节点位置", ok_c), ("D行尾", ok_d), ("E数值", ok_e)):
        if not ok:
            fails.append(f"{room}: {label} 失败")
    if ok_e is False:
        fails.append(f"{room}: 未通过的值 = {[k for k,v in checks_e.items() if not v]}")
    if added != EXPECTED_ADDED:
        fails.append(f"{room}: 插入行数={added}，期望 {EXPECTED_ADDED}")

    rows.append((room, added, "纯插入", "OK" if (ok_a and ok_c and ok_d and ok_e and added == EXPECTED_ADDED) else "FAIL",
                 sha_pre, sha_post, post_eol))

print(f"{'room':10s} {'+行':>4s} {'结论':6s} {'标记':6s} {'pre':12s} {'post':12s} {'eol':5s}")
for r in rows:
    print(f"{r[0]:10s} {str(r[1]):>4s} {r[2]:6s} {r[3]:6s} {r[4]:12s} {r[5]:12s} {str(r[6]):5s}")

print()
if fails:
    print("VERDICT_FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print(f"VERDICT_OK rooms={len(rows)} checks_all_pass=真 幂等={len(IDEMPOTENT)} 新插入={len(rows)-len(IDEMPOTENT)}x{EXPECTED_ADDED}行")
