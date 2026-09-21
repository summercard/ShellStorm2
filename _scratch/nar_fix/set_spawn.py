# -*- coding: utf-8 -*-
"""设置剧本 02 的 scene.spawn 参数：python set_spawn.py <forward_m> <distance>（CRLF 保留）。"""
import re
import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\data\narrative\nar_tower_opening_02_zombies.json"

fwd = sys.argv[1]
dist = sys.argv[2]

raw = open(P, "rb").read()
assert raw.count(b"\r\n") == raw.count(b"\n"), "行尾不纯"
t = raw.decode("utf-8").replace("\r\n", "\n")

t2 = re.sub(r'"forward_m":\s*[0-9.]+', '"forward_m": %s' % fwd, t)
t2 = re.sub(r'"distance":\s*[0-9.]+', '"distance": %s' % dist, t2)
assert t2.count('"forward_m"') == 1, "forward_m 缺失/重复"
assert t2.count('"distance"') == 1, "distance 缺失/重复"

data = t2.replace("\n", "\r\n").encode("utf-8")
assert data.count(b"\r") == data.count(b"\n")
open(P, "wb").write(data)
print("set forward_m=%s distance=%s" % (fwd, dist))
