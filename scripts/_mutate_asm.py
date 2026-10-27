"""反向对照注入器（临时用，跑完即删）。

用法：python scripts/_mutate_asm.py <case>
    loop_edge   漏掉环的闭合边 -> 应报「边 X-Y 没有落门」
    corridor    走廊长度只算一半 -> 应报「走廊盖不住门距」
    overlap     关掉重叠检查 -> 应报「A 与 B 重叠」
"""
import sys
from pathlib import Path

PATH = Path("src/map/EgtFlowAssembler.gd")
text = PATH.read_text(encoding="utf-8")
case = sys.argv[1]

if case == "loop_edge":
    old = '\t\tif str(edge.get("kind", "tree")) == "loop":\n\t\t\tloop_edges.append(edge)'
    new = '\t\tif str(edge.get("kind", "tree")) == "loop":\n\t\t\tcontinue'
    assert text.count(old) == 1, text.count(old)
    text = text.replace(old, new)
    print("注入：环的闭合边被跳过（不落门）")
elif case == "corridor":
    old = "\tvar length := clampf(ceilf(gap / 5.0) * 5.0, CORRIDOR_MIN_M, CORRIDOR_MAX_M)"
    new = "\tvar length := clampf(ceilf(gap / 5.0) * 5.0 * 0.5, CORRIDOR_MIN_M, CORRIDOR_MAX_M)"
    assert text.count(old) == 1, text.count(old)
    text = text.replace(old, new)
    print("注入：走廊长度只算一半")
elif case == "overlap":
    old = "\t\tif inter.size.x > OVERLAP_EPS and inter.size.y > OVERLAP_EPS:\n\t\t\treturn true"
    new = "\t\tif false:\n\t\t\treturn true"
    assert text.count(old) == 1, text.count(old)
    text = text.replace(old, new)
    print("注入：重叠检查被关掉")
else:
    raise SystemExit("unknown case")

PATH.write_text(text, encoding="utf-8")
