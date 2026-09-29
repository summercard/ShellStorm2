"""room_01 / room_02 改为单波 + 逐盒出怪倍率 ×2（业主 2026-09-29 口径）。

约束：
- 逐行改写，保留每一行原有行尾（本文件混用 CRLF/LF）。
- 幂等：已有 count_multiplier 则覆盖为同值；stages 已合并成单波则不动。
"""
import json
import re
import sys

ROOT = r"I:/工作项目/shellstrom2/ShellStorm2"
DATA = ROOT + "/source/art/whitebox/tower_zones/expedition_01/v001/data/floors/floor_00.json"

TARGETS = {
    "room_01": [2, 2, 2],       # 3 盒：主盒 / 包夹 / 贴墙
    "room_02": [2, 2, 2, 2],    # 4 盒：包夹 / 贴墙 / 主盒 / 窄列
}

with open(DATA, "rb") as f:
    _raw = f.read().decode("utf-8")
orig_lines = _raw.splitlines(keepends=True)
lines = list(orig_lines)

before_crlf = _raw.count("\r\n")


# 房间边界：按 `"key": "<id>"` 行号切段 —— 每个房从自己的 key 行起，到下一个 key 行前止。
# 不用花括号配平：房对象里 `connection_ports` 每项都是**同行成对**的 `{ ... }`，
# 配平法会在第一行 port 就误判收尾（曾实测 span 截断、找不到 spawn_placements）。
_key_line_idx = [
    (i, m.group(1))
    for i, l in enumerate(lines)
    if (m := re.match(r'\s*"key"\s*:\s*"([^"]+)"', l))
]


def room_span(key):
    for n, (idx, name) in enumerate(_key_line_idx):
        if name != key:
            continue
        end = (
            _key_line_idx[n + 1][0] - 1
            if n + 1 < len(_key_line_idx)
            else len(lines) - 1
        )
        return (idx, end)
    return None


def set_multiplier(key, values):
    """在 spawn_placements 的每一行行尾（中括号前）插入 count_multiplier。"""
    span = room_span(key)
    if span is None:
        print("FAIL: 找不到房间", key)
        sys.exit(1)
    sp = None
    for j in range(span[0], span[1] + 1):
        if '"spawn_placements"' in lines[j]:
            sp = j
            break
    if sp is None:
        print("FAIL: 找不到 spawn_placements", key)
        sys.exit(1)
    idxs = []
    k = sp + 1
    while k <= span[1]:
        s = lines[k].strip()
        if s.startswith("]"):
            break
        if s.startswith("{"):
            idxs.append(k)
        k += 1
    if len(idxs) != len(values):
        print("FAIL: 盒数不匹配", key, len(idxs), len(values))
        sys.exit(1)
    for pos, mult in zip(idxs, values):
        line = lines[pos]
        nl = "\r\n" if line.endswith("\r\n") else "\n"
        body = line[: len(line) - len(nl)]
        comma = body.endswith(",")
        if comma:
            body = body[:-1]
        inner = body.rstrip()
        if not inner.endswith("}"):
            print("FAIL: 行格式异常", key, repr(line))
            sys.exit(1)
        inner = inner[:-1].rstrip()
        if "count_multiplier" in inner:
            inner = re.sub(r',\s*"count_multiplier"\s*:\s*\d+', "", inner)
        if mult <= 1:
            new = inner + " }"
        else:
            new = inner + ', "count_multiplier": %d }' % mult
        if comma:
            new += ","
        lines[pos] = new + nl
    return idxs


def collapse_to_single_wave(key, n_boxes):
    """把 encounter.stages 压成单波，含全部 n_boxes 个实例。"""
    span = room_span(key)
    if span is None:
        print("FAIL: 找不到房间", key)
        sys.exit(1)
    st = None
    for j in range(span[0], span[1] + 1):
        if '"stages"' in lines[j]:
            st = j
            break
    if st is None:
        print("FAIL: 找不到 stages", key)
        sys.exit(1)
    # 方括号配平求 stages 数组的收尾行。stages 行内只有 `[`/`]`，无字符串干扰。
    # 注意：不能用「该行含 `[`」当结束条件 —— 收尾行只有 `]`，那样永远找不到 end。
    depth = 0
    end = None
    for j in range(st, span[1] + 1):
        depth += lines[j].count("[") - lines[j].count("]")
        if depth == 0:
            end = j
            break
    if end is None:
        print("FAIL: 解析 stages 区间失败", key)
        sys.exit(1)
    nl = "\r\n" if lines[end].endswith("\r\n") else "\n"
    # 缩进沿用 `"stages"` 行原本的缩进；数组内项多缩进一级。
    base_indent = re.match(r"\s*", lines[st]).group(0)
    inner_indent = base_indent + "  "
    boxes = ", ".join(str(i) for i in range(n_boxes))
    if end == st:
        lines[st] = '%s"stages": [ { "boxes": [%s] } ]%s' % (base_indent, boxes, nl)
    else:
        lines[st] = '%s"stages": [%s' % (base_indent, nl)
        new_body = '%s{ "boxes": [%s] }%s' % (inner_indent, boxes, nl)
        lines[st + 1 : end + 1] = [new_body, "%s]%s" % (base_indent, nl)]
    return True


for key, mults in TARGETS.items():
    set_multiplier(key, mults)
    collapse_to_single_wave(key, len(mults))

out = "".join(lines)
# 行尾纯度：合并波次会**删掉**行，故 CRLF 总数会减少 —— 那不是问题。
# 要守的不变量是「每条保留行的行尾风格不变」，即仅-LF 的行数必须完全相同：
# 若哪条 CRLF 行被误改写成 LF，这个计数就会涨。
lf_only_before = sum(1 for l in "".join(orig_lines).splitlines(keepends=True)
                     if not l.endswith("\r\n"))
lf_only_after = sum(1 for l in out.splitlines(keepends=True) if not l.endswith("\r\n"))
if lf_only_after != lf_only_before:
    print("FAIL: 仅-LF 行数变化", lf_only_before, lf_only_after)
    sys.exit(1)

parsed = json.loads(out)
rooms = {r["key"]: r for r in parsed["rooms"]}
for key, mults in TARGETS.items():
    pls = rooms[key]["spawn_placements"]
    got = [int(p.get("count_multiplier", 1)) for p in pls]
    if got != mults:
        print("FAIL: 回读倍率不一致", key, got, mults)
        sys.exit(1)
    stages = rooms[key]["encounter"]["stages"]
    if len(stages) != 1 or len(stages[0]["boxes"]) != len(mults):
        print("FAIL: 回读波次不是单波", key, stages)
        sys.exit(1)

with open(DATA, "wb") as f:
    f.write(out.encode("utf-8"))
print("OK CRLF %d->%d  仅-LF %d->%d" % (
    before_crlf, out.count("\r\n"), lf_only_before, lf_only_after))
for key, mults in TARGETS.items():
    print("  %-8s multiplier=%s stages=%s" % (
        key, mults, rooms[key]["encounter"]["stages"]))
