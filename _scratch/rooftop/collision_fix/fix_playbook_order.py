# -*- coding: utf-8 -*-
p = r"I:\工作项目\shellstrom2\.workbuddy\memory\MEMORY-playbooks.md"
d = open(p, "rb").read().decode("utf-8")

LANE_H = "### Blender 布局源摆放 · lane 归属摆位模型"
MY_H = "### 运行时装配 · 天台装饰实例级碰撞策略 `collision_policy`（2026-09-21 四次修正）"

bad = "\r\n\r\n" + LANE_H + "\r\n" + MY_H
assert d.count(bad) == 1, d.count(bad)
d = d.replace(bad, "\r\n\r\n" + MY_H, 1)

tail = "blocking slug）。\r\n\r\n- **lane 归属摆位模型**"
assert d.count(tail) == 1, d.count(tail)
d = d.replace(tail, "blocking slug）。\r\n\r\n" + LANE_H + "\r\n- **lane 归属摆位模型**", 1)

raw = d.encode("utf-8")
open(p, "wb").write(raw)
print("repaired crlf=%d lone_lf=%d crcrlf=%d" % (
    raw.count(b"\r\n"), raw.count(b"\n") - raw.count(b"\r\n"), raw.count(b"\r\r\n")))

d = raw.decode("utf-8")
i = d.find(MY_H)
print("MY 段前 :", repr(d[i - 60:i + 40]))
j = d.find(LANE_H, i)
print("LANE 段前:", repr(d[j - 30:j + 40]))
