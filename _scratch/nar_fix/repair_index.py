# -*- coding: utf-8 -*-
"""修复 _INDEX.md：CRCRLF 损伤经归一后变成『每行之间夹空行』，这里按非空行重建原结构。"""
p = r"I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-21\_INDEX.md"
raw = open(p, "rb").read()
t = raw.decode("utf-8").replace("\r\n", "\n").replace("\r", "\n")
nb = [l for l in t.split("\n") if l.strip() != ""]

assert len(nb) == 26, "非空行数=%d (期望 26)" % len(nb)
assert nb[0].startswith("# 2026-09-21"), nb[0]
assert nb[1].startswith("> 约定见"), nb[1]
assert nb[2].startswith("| 时间 | 事务"), nb[2]
assert nb[3].startswith("|---"), nb[3]
assert nb[4].startswith("| 07:26 |"), nb[4]
assert nb[-1].startswith("| 17:37 |"), nb[-1]

rebuilt = [nb[0], "", nb[1], "", nb[2], nb[3]] + nb[4:] + [""]
out = "\r\n".join(rebuilt).encode("utf-8")
cr = out.count(b"\r")
lf = out.count(b"\n")
assert cr == lf, (cr, lf)
open(p, "wb").write(out)
print("REPAIRED lines=%d CR=%d LF=%d" % (len(rebuilt), cr, lf))
print("-- head --")
for l in rebuilt[:6]:
    print(repr(l[:60]))
print("-- tail --")
for l in rebuilt[-3:]:
    print(repr(l[:60]))
