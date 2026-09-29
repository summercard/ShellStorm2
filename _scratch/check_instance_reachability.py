"""只读：检查某个组件在房间里的实例摆位，判断它的碰撞盒是否真的落在玩家可达高度带。

只有「碰撞盒世界 y 区间与玩家带 [0, PLAYER_TOP] 相交」时，盒内的空洞才是真的空阻挡；
摆在墙顶 / 屋顶 / 吊顶上方的件，AABB 再大也不影响玩家。

用法：
  python _scratch/check_instance_reachability.py                # 全部有问题的件
  python _scratch/check_instance_reachability.py slug1 slug2    # 只看指定 slug
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAYOUT_DIR = ROOT / "assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01"
PLAYER_TOP = 2.2   # 玩家胶囊上方（含少量余量）
NUM = r"(-?\d+(?:\.\d+)?(?:e-?\d+)?)"


def boxes_of_prefab(tscn: Path):
    text = tscn.read_text(encoding="utf-8")
    sizes = {
        m.group(1): [float(v) for v in re.findall(NUM, m.group(2))]
        for m in re.finditer(
            r'\[sub_resource type="BoxShape3D" id="([^"]+)"\]\s*\r?\nsize = Vector3\(([^)]*)\)', text)
    }
    out = []
    for m in re.finditer(
        r'\[node name="([^"]+)" type="CollisionShape3D"[^\]]*\]\s*\r?\n((?:[^\[]*\r?\n)*?)(?=\[|$)', text):
        name, body = m.group(1), m.group(2)
        pm = re.search(r"position = Vector3\(([^)]*)\)", body)
        sm = re.search(r'shape = SubResource\("([^"]+)"\)', body)
        if not sm or sm.group(1) not in sizes:
            continue
        pos = [float(v) for v in re.findall(NUM, pm.group(1))] if pm else [0.0, 0.0, 0.0]
        size = sizes[sm.group(1)]
        if len(pos) < 3 or len(size) < 3:
            continue
        out.append((name, pos, size))
    return out


def instances_of(slug: str):
    """从 13 个房间静态布局里找出该 prefab 的所有实例（节点名 = slug）。"""
    hits = []
    for lay in sorted(LAYOUT_DIR.glob("f00_*_static_layout.tscn")):
        text = lay.read_text(encoding="utf-8")
        # 该布局里 slug 的 ExtResource id
        ids = [m.group(2) for m in re.finditer(
            r'\[ext_resource type="PackedScene" path="([^"]*/%s/%s_root_top3d\.tscn)" id="([^"]+)"\]' % (slug, slug),
            text)]
        if not ids:
            # 也匹配 path 里含 slug 目录的任意情形
            ids = [m.group(2) for m in re.finditer(
                r'\[ext_resource type="PackedScene" path="(res://[^"]*)" id="([^"]+)"\]', text)
                if "/%s/" % slug in m.group(1)]
        if not ids:
            continue
        for eid in set(ids):
            for m in re.finditer(
                r'\[node name="([^"]*)"[^\]]*instance=ExtResource\("%s"\)\]\s*\r?\n((?:[^\[]*\r?\n)*?)(?=\[|$)'
                % re.escape(eid), text):
                body = m.group(2)
                tm = re.search(r"transform = Transform3D\(([^)]*)\)", body)
                vals = [float(v) for v in re.findall(NUM, tm.group(1))] if tm else []
                if len(vals) == 12:
                    basis = [vals[0:3], vals[3:6], vals[6:9]]
                    origin = vals[9:12]
                else:
                    basis = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
                    tm2 = re.search(r"position = Vector3\(([^)]*)\)", body)
                    origin = [float(v) for v in re.findall(NUM, tm2.group(1))] if tm2 else [0.0, 0.0, 0.0]
                hits.append((lay.name, m.group(1), basis, origin))
    return hits


def world_y_range(boxes, basis, origin):
    lo, hi = 1e9, -1e9
    for _, pos, size in boxes:
        for sx in (pos[0] - size[0] / 2, pos[0] + size[0] / 2):
            for sy in (pos[1] - size[1] / 2, pos[1] + size[1] / 2):
                for sz in (pos[2] - size[2] / 2, pos[2] + size[2] / 2):
                    y = (basis[0][1] * sx + basis[1][1] * sy + basis[2][1] * sz) + origin[1]
                    lo, hi = min(lo, y), max(hi, y)
    return lo, hi


def main():
    args = sys.argv[1:]
    any_policy = "--any-policy" in args
    targets = [a for a in args if not a.startswith("--")] or None
    prefab_root = ROOT / "assets/art/environments/tower_zones/expedition/runtime/room_type_components"
    rows = []
    for tscn in sorted(prefab_root.rglob("*_root_top3d.tscn")):
        slug = tscn.parent.name
        if targets and slug not in targets:
            continue
        text = tscn.read_text(encoding="utf-8")
        policy = re.search(r'metadata/collision_policy = "([^"]*)"', text)
        policy = policy.group(1) if policy else ""
        if not any_policy and policy not in {"safe_box_proxy", "structural_box_proxy"}:
            continue
        boxes = boxes_of_prefab(tscn)
        if not boxes:
            continue
        inst = instances_of(slug)
        if not inst:
            rows.append((slug, tscn.parent.parent.name, 0, None, None, "无实例", policy))
            continue
        ys = [world_y_range(boxes, b, o) for _, _, b, o in inst]
        rows.append((slug, tscn.parent.parent.name, len(inst),
                     min(y[0] for y in ys), max(y[1] for y in ys), "", policy))

    print("%-32s %-16s %5s %10s %10s %-22s %s" % ("slug", "房型", "实例", "世界y_lo", "世界y_hi", "与玩家带相交", "policy"))
    print("-" * 122)
    for slug, rt, n, ylo, yhi, note, policy in rows:
        if note:
            print("%-32s %-16s %5d %10s %10s %-22s %s" % (slug, rt, n, "-", "-", note, policy))
            continue
        reach = ylo < PLAYER_TOP
        print("%-32s %-16s %5d %10.3f %10.3f %-22s %s"
              % (slug, rt, n, ylo, yhi, "★相交（需处理）" if reach else "否（高处，无害）", policy))
    print("\n共 %d 件有碰撞盒；其中与玩家带相交 %d 件"
          % (len(rows), sum(1 for r in rows if r[3] is not None and r[3] < PLAYER_TOP)))


if __name__ == "__main__":
    main()
