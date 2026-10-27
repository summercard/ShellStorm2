from pathlib import Path

p = Path("src/map/EgtFlowAssembler.gd")
s = p.read_text(encoding="utf-8")
old = '\t\t"east":\n\t\t\tb_center.x = a_center.x + (a_size.x + b_size.x) * 0.5'
new = '\t\t"east":\n\t\t\tb_center.x = a_center.x + a_size.x'
assert s.count(old) == 1, f"anchor count = {s.count(old)}"
p.write_text(s.replace(old, new), encoding="utf-8")
print("mutated: east 贴合距离少算一个房间宽")
