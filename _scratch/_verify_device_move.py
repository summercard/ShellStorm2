# -*- coding: utf-8 -*-
"""稳健复验：room_01/room_02 静态 TSCN 的「设备块搬到场景树顶部」是否等价于纯块移动。
判据：
  A. 两版文件去掉【设备相关行】后，剩余部分逐行完全相同（顺序也不能变）；
  B. 设备相关行本身，两版的多重集完全相同（内容一字不差）；
  C. live 版里设备节点是 ExpeditionRoomStaticLayout 根的前两个子节点；
  D. 两版都是纯 LF、且以换行结尾。
不使用 difflib（对大量近似的 transform 行会错误对齐）。
"""
import io
import os
import sys
from collections import Counter

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
INST = os.path.join(ROOT, "assets", "art", "environments", "tower_zones",
                    "expedition", "runtime", "room_instances", "expedition_01")
BAK = os.path.join(ROOT, "_scratch", "_before_move")

DEV_SCRIPTS = ("900_authored_light", "901_authored_switch")
DEV_NODE_NAMES = ('name="RoomCeilingLight"', 'name="RoomLightSwitch3D"')


def read_lines(path):
    with open(path, "rb") as f:
        raw = f.read()
    crlf = raw.count(b"\r\n")
    lone_lf = raw.count(b"\n") - crlf
    cr_only = raw.count(b"\r") - crlf
    ends_nl = raw.endswith(b"\n")
    text = raw.decode("utf-8")
    return text.split("\n"), dict(crlf=crlf, lone_lf=lone_lf,
                                  cr_only=cr_only, ends_nl=ends_nl,
                                  size=len(raw))


def classify(lines):
    """把每一行归为 device 或 body。device 判定沿用注入器同一套规则。"""
    dev_idx = set()
    meta_idx = set()
    ext_idx = set()
    for i, ln in enumerate(lines):
        if any(n in ln for n in DEV_NODE_NAMES):
            dev_idx.add(i)          # 节点头行
        elif ln.strip().startswith("metadata/authored_room_devices"):
            meta_idx.add(i)
        elif ln.startswith("[ext_resource") and any(s in ln for s in DEV_SCRIPTS):
            ext_idx.add(i)
    # 展开节点块：从节点头行向下，直到下一个以 '[' 开头的顶层段落
    block_idx = set()
    for i in sorted(dev_idx):
        j = i
        while j < len(lines):
            if j != i and lines[j].startswith("["):
                break
            block_idx.add(j)
            j += 1
    # 向上吸收紧邻的说明注释行（以 ';' 开头）——设备块的注释属于块的一部分
    for i in sorted(dev_idx):
        k = i - 1
        while k >= 0 and lines[k].startswith(";"):
            block_idx.add(k)
            k -= 1
    remove = block_idx | meta_idx | ext_idx
    body = [ln for i, ln in enumerate(lines) if i not in remove]
    dev = [ln for i, ln in enumerate(lines) if i in remove]
    # 设备块在 live 中的起始行号（1-based，节点头）
    starts = sorted(i for i in dev_idx)
    return body, dev, starts


def main():
    ok = True
    for room in ("room_01", "room_02"):
        name = "f00_%s_static_layout.tscn" % room
        live_p = os.path.join(INST, name)
        bak_p = os.path.join(BAK, name)
        print("##### %s #####" % room)
        for tag, p in (("live", live_p), ("before_move", bak_p)):
            if not os.path.exists(p):
                print("  MISSING %s: %s" % (tag, p)); ok = False; continue
            lines, enc = read_lines(p)
            print("  [%s] 行数=%d size=%d CRLF=%d loneLF=%d loneCR=%d ends_nl=%s"
                  % (tag, len(lines), enc["size"], enc["crlf"], enc["lone_lf"],
                     enc["cr_only"], enc["ends_nl"]))
            if enc["crlf"] or enc["cr_only"]:
                print("  !! %s 含 CR" % tag); ok = False

        l_lines, _ = read_lines(live_p)
        b_lines, _ = read_lines(bak_p)
        l_body, l_dev, l_starts = classify(l_lines)
        b_body, b_dev, b_starts = classify(b_lines)

        # A. body 逐行完全相同
        if l_body == b_body:
            print("  A. body 逐行完全相同 : OK (%d 行)" % len(l_body))
        else:
            ok = False
            print("  A. body 逐行完全相同 : FAIL (%d vs %d)" % (len(l_body), len(b_body)))
            n = min(len(l_body), len(b_body))
            cnt = 0
            for i in range(n):
                if l_body[i] != b_body[i]:
                    print("     first-diff@%d\n       live: %r\n        bak: %r"
                          % (i, l_body[i], b_body[i]))
                    cnt += 1
                    if cnt >= 5:
                        break

        # B. 设备行多重集相同
        if Counter(l_dev) == Counter(b_dev):
            print("  B. 设备行多重集相同   : OK (%d 行)" % len(l_dev))
        else:
            ok = False
            print("  B. 设备行多重集相同   : FAIL")
            only_l = Counter(l_dev) - Counter(b_dev)
            only_b = Counter(b_dev) - Counter(l_dev)
            for k, v in list(only_l.items())[:5]:
                print("     only-live x%d: %r" % (v, k))
            for k, v in list(only_b.items())[:5]:
                print("     only-bak  x%d: %r" % (v, k))

        # B2. 设备整块顺序也相同
        print("  B2. 设备块内容顺序相同: %s" % ("OK" if l_dev == b_dev else "DIFF"))

        print("  live 设备节点头行号(1-based): %s   before_move: %s"
              % ([s + 1 for s in l_starts], [s + 1 for s in b_starts]))

        # C. live 里设备是根的前两个子节点
        # 找根行
        root_i = next((i for i, ln in enumerate(l_lines) if ln.startswith("[node name=")), None)
        child_nodes = [i for i, ln in enumerate(l_lines) if ln.startswith("[node ")]
        expect_first = [i for i in child_nodes if i != root_i][:2]
        if l_starts and l_starts[:2] == expect_first:
            print("  C. 设备=根前两个子节点 : OK (根行 %d, 前两子 %s)"
                  % (root_i + 1, [i + 1 for i in expect_first]))
        else:
            ok = False
            print("  C. 设备=根前两个子节点 : FAIL 期望 %s 实际 %s"
                  % ([i + 1 for i in expect_first], [s + 1 for s in l_starts[:2]]))
        print()

    print("==== VERDICT:", "OK" if ok else "FAIL", "====")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
