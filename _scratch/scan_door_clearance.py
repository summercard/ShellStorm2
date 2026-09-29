#!/usr/bin/env python3
"""扫描房间静态布局里「哪个组件的碰撞盒覆盖了门洞净空」。

用法:
  python scan_door_clearance.py <room_tscn> <center_x> <center_z> <door_local_x> <door_local_z>

坐标语义:
  - 远征 13 房除 start 外房间根均无旋转,故 世界 = 房间原点 + 房间局部。
  - Godot Transform3D 序列化 = basis(行优先 9) + origin(3);
    basis.xform(v) = (rows[0].dot(v), rows[1].dot(v), rows[2].dot(v))。
"""
import os
import re
import sys

NUM = r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+(?:\.\d+)?)?"

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
assert os.path.isfile(os.path.join(REPO, "project.godot")), "REPO 定位失败: %s" % REPO

IDENT = ([1, 0, 0], [0, 1, 0], [0, 0, 1])
DOOR_HALF_W = 1.10
DOOR_TOP = 2.50

_PREFAB_CACHE = {}


def res_to_path(res_path):
    assert res_path.startswith("res://")
    return os.path.join(REPO, res_path[len("res://"):].replace("/", os.sep))


def parse_transform(text):
    nums = [float(x) for x in re.findall(NUM, text)]
    assert len(nums) == 12, "Transform3D 参数数=%d: %s" % (len(nums), text)
    return [nums[0:3], nums[3:6], nums[6:9]], nums[9:12]


def xform(rows, origin, v):
    return [
        rows[0][0] * v[0] + rows[0][1] * v[1] + rows[0][2] * v[2] + origin[0],
        rows[1][0] * v[0] + rows[1][1] * v[1] + rows[1][2] * v[2] + origin[1],
        rows[2][0] * v[0] + rows[2][1] * v[1] + rows[2][2] * v[2] + origin[2],
    ]


def matmul(a_rows, a_o, b_rows, b_o):
    rows = [[sum(a_rows[i][k] * b_rows[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return rows, xform(a_rows, a_o, b_o)


def node_blocks(text):
    """按 [node ...] 切块,返回 (name, type, parent, instance_id, block_text)。

    ⚠️ Godot 里 instance=ExtResource 的节点**不写 type 属性**,所以 type 必须可选,
    否则所有 PackedScene 实例节点会被整体跳过(实测把"有挡门盒"误报成"干净")。
    """
    out = []
    for b in re.split(r"(?m)^(?=\[node )", text):
        hm = re.match(r'\[node name="([^"]+)"([^\]]*)\]', b)
        if not hm:
            continue
        attrs = hm.group(2)
        tm = re.search(r'type="(\w+)"', attrs)
        pm = re.search(r'parent="([^"]*)"', attrs)
        im = re.search(r'instance=ExtResource\("([^"]+)"\)', attrs)
        out.append((hm.group(1), tm.group(1) if tm else "", pm.group(1) if pm else "",
                    im.group(1) if im else "", b))
    return out


def local_transform(block):
    """返回 (rows, origin)。

    ⚠️ Godot 序列化碰撞盒位置有两种写法:`transform = Transform3D(...)`,
    以及更常见的 `position = Vector3(...)`(± rotation/scale)。只认前者会把
    所有盒堆到原点、把"门垛在上方/两侧"误判成"横堵门洞"。实测踩过。
    """
    tm = re.search(r"transform = Transform3D\(([^)]*)\)", block)
    if tm:
        return parse_transform(tm.group(1))
    pm = re.search(r"position = Vector3\(([^)]*)\)", block)
    origin = [float(x) for x in re.findall(NUM, pm.group(1))] if pm else [0.0, 0.0, 0.0]
    sm = re.search(r"scale = Vector3\(([^)]*)\)", block)
    scale = [float(x) for x in re.findall(NUM, sm.group(1))] if sm else [1.0, 1.0, 1.0]
    rm = re.search(r"rotation = Vector3\(([^)]*)\)", block)
    if rm and any(abs(float(x)) > 1e-6 for x in re.findall(NUM, rm.group(1))):
        print("  [warn] 未处理 rotation: %s" % rm.group(1).strip())
    rows = [[scale[0], 0.0, 0.0], [0.0, scale[1], 0.0], [0.0, 0.0, scale[2]]]
    return rows, origin


def collect_shapes(prefab_path, depth=0):
    """返回 [(rows, origin, size)] —— 相对该 prefab 根的 BoxShape3D 碰撞盒。"""
    if prefab_path in _PREFAB_CACHE:
        return _PREFAB_CACHE[prefab_path]
    if depth > 6 or not os.path.isfile(prefab_path):
        return []
    if not prefab_path.endswith(".tscn"):
        return []          # glb / 其它二进制资源不含本文本格式碰撞声明
    text = open(prefab_path, encoding="utf-8").read()

    shapes = {}
    for m in re.finditer(r'\[sub_resource type="(\w+)" id="([^"]+)"\]', text):
        kind, sid = m.group(1), m.group(2)
        tail = text[m.end():m.end() + 200]
        sm = re.search(r"size = Vector3\(([^)]*)\)", tail)
        size = [float(x) for x in re.findall(NUM, sm.group(1))] if sm else [0.0, 0.0, 0.0]
        shapes[sid] = (kind, size)

    ext = {}
    for m in re.finditer(r'\[ext_resource type="PackedScene" path="([^"]+)" id="([^"]+)"\]', text):
        ext[m.group(2)] = m.group(1)

    abs_tf = {}
    out = []
    for name, ntype, parent, inst, b in node_blocks(text):
        # ⚠️ parent="." 必须归一为根,否则 key 变成 "./X" 而后代查 "X" 查不到,
        #    会导致整条子树丢失父级变换(实测让门垛/门楣盒粘在一起、y 区间错位)。
        pid = parent.rstrip("/")
        if pid == ".":
            pid = ""
        base = abs_tf.get(pid, (IDENT, [0.0, 0.0, 0.0]))
        rows, origin = local_transform(b)
        cur = matmul(base[0], base[1], rows, origin)
        key = (pid + "/" + name) if pid else name
        abs_tf[key] = cur

        sm = re.search(r'shape = SubResource\("([^"]+)"\)', b)
        if sm and sm.group(1) in shapes:
            kind, size = shapes[sm.group(1)]
            if kind == "BoxShape3D":
                out.append((cur[0], cur[1], size))
        if inst and inst in ext:
            for sr, so, ssize in collect_shapes(res_to_path(ext[inst]), depth + 1):
                r2, o2 = matmul(cur[0], cur[1], sr, so)
                out.append((r2, o2, ssize))
    _PREFAB_CACHE[prefab_path] = out
    return out


def scan_room(tscn_path, center, label, window):
    text = open(tscn_path, encoding="utf-8").read()
    ext = {}
    for m in re.finditer(r'\[ext_resource type="PackedScene" path="([^"]+)" id="([^"]+)"\]', text):
        ext[m.group(2)] = m.group(1)

    print("=== %s ===" % label)
    hits = []
    for name, ntype, parent, rid, b in node_blocks(text):
        if not rid:
            continue
        rows, origin = local_transform(b)
        prefab = res_to_path(ext[rid])
        slug = os.path.basename(os.path.dirname(prefab))
        for sr, so, size in collect_shapes(prefab):
            lo = [1e9] * 3
            hi = [-1e9] * 3
            for sx in (-0.5, 0.5):
                for sy in (-0.5, 0.5):
                    for sz in (-0.5, 0.5):
                        p = xform(rows, origin, xform(sr, so, [sx * size[0], sy * size[1], sz * size[2]]))
                        w = [p[0] + center[0], p[1], p[2] + center[1]]
                        for i in range(3):
                            lo[i] = min(lo[i], w[i])
                            hi[i] = max(hi[i], w[i])
            x0, y0, z0, x1, y1, z1 = window
            if hi[0] > x0 and lo[0] < x1 and hi[1] > y0 and lo[1] < y1 and hi[2] > z0 and lo[2] < z1:
                hits.append((name, slug, lo, hi, size))
    if not hits:
        print("  无碰撞盒进入窗口")
    for name, slug, lo, hi, size in hits:
        print("  ! %-50s slug=%-20s AABB[%.2f..%.2f, %.2f..%.2f, %.2f..%.2f] size=(%.2f,%.2f,%.2f)"
              % (name, slug, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], size[0], size[1], size[2]))
    return hits


if __name__ == "__main__":
    tscn, cx, cz, dx, dz = sys.argv[1], *[float(v) for v in sys.argv[2:6]]
    wx, wz = cx + dx, cz + dz
    window = (wx - 3.0, 0.0, wz - DOOR_HALF_W - 1.5, wx + 3.0, DOOR_TOP, wz + DOOR_HALF_W + 1.5)
    print("门洞世界中心 (%.2f, %.2f)  窗口 x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f]"
          % (wx, wz, *window))
    scan_room(tscn, (cx, cz), os.path.basename(tscn), window)
