"""把 _scratch/spawn_ramp_plan.json 的逐实例 count_bonus 外科式写入远征01刷怪数据。

约束：
- 只改 room_03 起始的 8 个房间（room_01 / room_02 不动，业主口径「从 room03 开始」）。
- 逐行改写，**保持每一行原有的行尾**（该文件混用 CRLF/LF：结构行 CRLF、紧凑行 LF）。
- 幂等：行内已有 count_bonus 则跳过。
"""
import json
import re
import sys

ROOT = r"I:/工作项目/shellstrom2/ShellStorm2"
DATA = ROOT + "/source/art/whitebox/tower_zones/expedition_01/v001/data/floors/floor_00.json"
PLAN = ROOT + "/_scratch/spawn_ramp_plan.json"

plan = json.load(open(PLAN, encoding="utf-8"))
with open(DATA, "rb") as f:
    raw = f.read()
lines = raw.decode("utf-8").splitlines(keepends=True)

before_crlf = "".join(lines).count("\r\n")


def placement_line_idxs(key: str):
    start = None
    for i, l in enumerate(lines):
        if re.search(r'"key"\s*:\s*"%s"' % re.escape(key), l):
            start = i
            break
    if start is None:
        return None
    sp = None
    for j in range(start, len(lines)):
        if '"spawn_placements"' in lines[j]:
            sp = j
            break
    if sp is None:
        return None
    out = []
    k = sp + 1
    while k < len(lines):
        s = lines[k].strip()
        if s.startswith("]"):
            break
        if s.startswith("{"):
            out.append(k)
        k += 1
    return out


changed = 0
report = []
for key in plan:
    idxs = placement_line_idxs(key)
    if idxs is None:
        print("FAIL: 未定位房间", key)
        sys.exit(1)
    bonus = plan[key]["bonus"]
    if len(idxs) != len(bonus):
        print("FAIL: 盒数不匹配", key, len(idxs), len(bonus))
        sys.exit(1)
    got = []
    for pos, bn in zip(idxs, bonus):
        line = lines[pos]
        if "count_bonus" in line:
            got.append("skip")
            continue
        # 零增量不落盘：缺省即 0，保持最小改动、避免无意义噪声。
        if int(bn) == 0:
            got.append(0)
            continue
        nl = "\r\n" if line.endswith("\r\n") else "\n"
        body = line[: len(line) - len(nl)]
        comma = body.endswith(",")
        if comma:
            body = body[:-1]
        stripped = body.rstrip()
        if not stripped.endswith("}"):
            print("FAIL: 行格式异常", key, repr(line))
            sys.exit(1)
        inner = stripped[:-1].rstrip()
        new = inner + ', "count_bonus": %d }' % bn
        if comma:
            new += ","
        lines[pos] = new + nl
        changed += 1
        got.append(bn)
    report.append((key, got))

out = "".join(lines)
after_crlf = out.count("\r\n")
if after_crlf != before_crlf:
    print("FAIL: CRLF 计数变化", before_crlf, after_crlf)
    sys.exit(1)

# 改写后必须是合法 JSON，且逐实例 bonus 与方案一致
parsed = json.loads(out)
rooms = {r["key"]: r for r in parsed["rooms"]}
for key, got in report:
    pls = rooms[key]["spawn_placements"]
    vals = [int(p.get("count_bonus", 0)) for p in pls]
    if vals != plan[key]["bonus"]:
        print("FAIL: 回读不一致", key, vals, plan[key]["bonus"])
        sys.exit(1)

with open(DATA, "wb") as f:
    f.write(out.encode("utf-8"))

print("OK 改动行数=%d  CRLF %d->%d" % (changed, before_crlf, after_crlf))
for key, got in report:
    print("  %-8s bonus=%s" % (key, got))
