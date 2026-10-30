#!/usr/bin/env python3
"""房间白盒 TSCN 生成器 v2（按外轮廓多边形出几何，不再按包围盒矩形近似）。

## v1 错在哪

v1 把每份 TSCN 都做成 **矩形房间**。但 `room_templates/*.json` 里的
`variant_footprints` 明确写着：`corridor_45x40` 的 `l_turn` 缺东南角 30×15、
`u_turn` 西侧中部有 30×10 实心内岛、`db_70x50` 的 `db_01`/`db_02` 各缺角。
按包围盒做出来的"L 形"其实是个 L 形房间外面套了个完整方盒子 —— 缺角处多出了
不存在的地面和墙，玩家能走进本该是实体/室外的区域。

**轮廓是真源，包围盒只是它的外接矩形。** 本版逐条读 `variant_footprints`。

## 它生成什么

一个 (模板 × 轮廓变体) 一份 `rt_*_static_layout.tscn`：

- 地面：只铺**完整落在轮廓内**的 5m 格
- 墙：沿**每一条轮廓边**建，向内表面压轮廓线，厚度在外侧
- 门洞：只在**该侧轮廓边真实覆盖到的槽位**上开挖（槽位合法性由
  `scripts/check_expedition_room_footprints.py` 用同一份轮廓算出，本脚本复算一遍并断言一致）
- 端口：`ConnectionPorts/Port_*`，数量来自骨架实际需求（见 `port_budget()`）

**不含**：地砖/墙板模型、陈设、陷阱、刷点、灯、门扇、美术材质 —— 全部 `BoxMesh`。

## 端口数怎么来的（不硬编码）

`port_budget()` 从六张骨架反推：每个房间位的门数 = 它在 `tree_edges`+`loop_edges`
里的度数；`NORMAL` 的模板是四选一池（`template_pool`），池里每个模板都要能承受
该房间位的门数。再对入口安全屋 +1（弃局门，设计页 §2）。**改骨架，端口预算自动跟着变。**

运行：
    python3 scripts/build_whitebox_room_tscn.py            # 生成全部
    python3 scripts/build_whitebox_room_tscn.py --preview  # 另出俯视预览 PNG
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE_DIR = ROOT / "data/level_plans/expedition_03/room_templates"
FLOW_DIR = ROOT / "data/level_plans/expedition_03/flows"
OUT_DIR = (
    ROOT / "assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03"
)
PREVIEW_DIR = ROOT / "docs/art/expedition03_room_whitebox"

# ── 白盒几何参数 ────────────────────────────────────────────────────────────
GRID = 5.0              # 一格 5 米（主人指定：以通道为 5 米为单位）
WALK_Y = 0.08           # 行走面高度，与既有 static_layout 一致
FLOOR_THICKNESS = 0.10
WALL_THICKNESS = 0.30
CORNER_EXTEND = WALL_THICKNESS / 2.0

# 哪些侧允许开门：bridge_60x50 的模板 note 写死「短边（南/北墙）开门，东西长边一律不许连」。
# 这是设计约束，不是几何推导 —— 放在这里显式列出，由门禁复查。
SIDE_OVERRIDES: dict[str, list[str]] = {"bridge_60x50": ["north", "south"]}

# 入口安全屋除常规门前之外还有一扇弃局门（设计页 §2「入口安全屋 → 弃局门」）。
EXTRA_PORTS: dict[str, tuple[int, str]] = {
    "safe_15x15": (1, "入口安全屋的弃局门：设计页 §2，一进一出之外还要能原地弃局"),
}


# ── 与 RoomDoorLane.gd 同源的槽位算法（两边各有断言，禁止静默分叉）────────────
def module_count(length_m: float) -> int:
    return max(1, int(round(length_m / GRID)))


def lane_offsets(length_m: float) -> list[float]:
    count = module_count(length_m)
    first = 1 if count >= 3 else 0
    last = count - 2 if count >= 3 else count - 1
    return [-length_m * 0.5 + GRID * (i + 0.5) for i in range(first, last + 1)]


# ── 数据加载 ────────────────────────────────────────────────────────────────
def load_templates() -> dict[str, dict]:
    out: dict[str, dict] = {}
    for path in sorted(TEMPLATE_DIR.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        out[str(data["template_id"])] = data
    return out


def port_budget(templates: dict[str, dict]) -> dict[str, int]:
    """从骨架反推每个模板的端口预算。返回 template_id -> 端口数。"""
    budget: dict[str, int] = {}
    for path in sorted(FLOW_DIR.glob("flow_*.json")):
        flow = json.loads(path.read_text(encoding="utf-8"))
        degree: dict[str, int] = {}
        for edge in list(flow.get("tree_edges", [])) + list(flow.get("loop_edges", [])):
            a = str(edge.get("from", edge.get("a", "")))
            b = str(edge.get("to", edge.get("b", "")))
            degree[a] = degree.get(a, 0) + 1
            degree[b] = degree.get(b, 0) + 1
        for node in flow.get("nodes", []):
            needs = degree.get(str(node.get("node_id", "")), 0)
            targets: list[str] = []
            if node.get("template_id"):
                targets.append(str(node["template_id"]))
            # NORMAL 是池：池里每个模板都可能被选中，都要能承受这个门数
            targets.extend(str(t) for t in node.get("template_pool", []) if t)
            for tid in targets:
                budget[tid] = max(budget.get(tid, 0), needs)
    for tid, (extra, _reason) in EXTRA_PORTS.items():
        budget[tid] = budget.get(tid, 0) + extra
    # bridge 本关不使用（设计页 §10），但仍按设计约束给 2 个同轴端口
    budget.setdefault("bridge_60x50", 2)
    for tid in list(budget):
        if tid not in templates:
            raise SystemExit(f"骨架引用了不存在的模板 {tid}")
    return budget


def footprint(tpl: dict, variant: str) -> list[tuple[float, float]]:
    """轮廓顶点（footprint 坐标：原点在包围盒西北角，x 东、y 南）。"""
    fps = tpl.get("variant_footprints") or {}
    if variant and variant in fps:
        return [(float(p[0]), float(p[1])) for p in fps[variant]["vertices_m"]]
    w, d = (float(v) for v in tpl["size_m"])
    return [(0.0, 0.0), (w, 0.0), (w, d), (0.0, d)]


def variants_of(tpl: dict) -> list[str]:
    vs = [str(v) for v in tpl.get("variants", [])]
    return vs if vs else [""]


# ── 几何工具 ────────────────────────────────────────────────────────────────
def signed_area(poly: list[tuple[float, float]]) -> float:
    s = 0.0
    for i, (x0, y0) in enumerate(poly):
        x1, y1 = poly[(i + 1) % len(poly)]
        s += x0 * y1 - x1 * y0
    return s * 0.5


def point_in_poly(pt: tuple[float, float], poly: list[tuple[float, float]]) -> bool:
    x, y = pt
    inside = False
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        if (y0 > y) != (y1 > y):
            xin = (x1 - x0) * (y - y0) / (y1 - y0) + x0
            if x < xin:
                inside = not inside
    return inside


def boundary_edges(poly: list[tuple[float, float]], w: float, d: float) -> list[dict]:
    """轮廓边 + 它所在的外墙侧（不在包围盒边界上的边 side=None，不可开门）。"""
    edges: list[dict] = []
    eps = 1e-6
    for i, p0 in enumerate(poly):
        p1 = poly[(i + 1) % len(poly)]
        horizontal = abs(p0[1] - p1[1]) < eps
        vertical = abs(p0[0] - p1[0]) < eps
        if not (horizontal or vertical):
            raise SystemExit(f"轮廓边不是轴对齐：{p0} -> {p1}")
        side = None
        if horizontal:
            if abs(p0[1]) < eps:
                side = "north"
            elif abs(p0[1] - d) < eps:
                side = "south"
        else:
            if abs(p0[0]) < eps:
                side = "west"
            elif abs(p0[0] - w) < eps:
                side = "east"
        lo, hi = (min(p0[0], p1[0]), max(p0[0], p1[0])) if horizontal \
            else (min(p0[1], p1[1]), max(p0[1], p1[1]))
        edges.append({"p0": p0, "p1": p1, "horizontal": horizontal,
                      "side": side, "lo": lo, "hi": hi})
    return edges


def outward_normal(edge: dict, poly: list[tuple[float, float]]) -> tuple[float, float]:
    """沿边方向的右侧即外侧（轮廓面积符号已归一为逆时针）。"""
    dx = edge["p1"][0] - edge["p0"][0]
    dy = edge["p1"][1] - edge["p0"][1]
    length = (dx * dx + dy * dy) ** 0.5
    nx, ny = dy / length, -dx / length
    if signed_area(poly) < 0:
        nx, ny = -nx, -ny
    return nx, ny


def solid_spans(lo: float, hi: float, gaps: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """区间减法：整段减去门洞后剩下的实体段（绝对坐标）。"""
    spans = [(lo, hi)]
    for g0, g1 in sorted(gaps):
        nxt: list[tuple[float, float]] = []
        for a, b in spans:
            if g1 <= a or g0 >= b:
                nxt.append((a, b))
                continue
            if g0 > a:
                nxt.append((a, min(g0, b)))
            if g1 < b:
                nxt.append((max(g1, a), b))
        spans = nxt
    return [(a, b) for a, b in spans if b - a > 0.001]


def valid_lanes(tpl: dict, variant: str, side: str) -> list[float]:
    """该侧**真实**可开门的槽位：整个门洞必须落在同一条轮廓外墙上。"""
    w, d = (float(v) for v in tpl["size_m"])
    poly = footprint(tpl, variant)
    edges = boundary_edges(poly, w, d)
    door_w = float(tpl["door_contract"]["width_m"])
    length = w if side in ("north", "south") else d
    axis_center = w * 0.5 if side in ("north", "south") else d * 0.5
    out: list[float] = []
    for lane in lane_offsets(length):
        c = axis_center + lane
        g0, g1 = c - door_w / 2.0, c + door_w / 2.0
        for edge in edges:
            if edge["side"] != side:
                continue
            if edge["lo"] - 1e-6 <= g0 and g1 <= edge["hi"] + 1e-6:
                out.append(float(lane))
                break
    return out


def choose_ports(tpl: dict, variant: str, want: int) -> list[tuple[str, float]]:
    """按 north/south/east/west 顺序取离中心最近的合法槽，不够再往同侧加第二个。

    窄长房（长宽比 ≥ 2.5）例外：门要开在**长轴两端**，否则穿堂变成横穿。
    这是《挺进地牢》"long, thin rooms … sensible orientation" 的落地 ——
    `connector_10x30` 的门在南北，`connector_30x10` 的门在东西。
    """
    tid = str(tpl["template_id"])
    w, d = (float(v) for v in tpl["size_m"])
    if tid in SIDE_OVERRIDES:
        sides = SIDE_OVERRIDES[tid]
    elif max(w, d) / max(1e-6, min(w, d)) >= 2.5:
        # 长轴沿 y（南北）⇒ 门在南北两面；长轴沿 x（东西）⇒ 门在东西两面
        sides = ["north", "south", "east", "west"] if d > w else ["east", "west", "north", "south"]
    else:
        sides = ["north", "south", "east", "west"]
    door_w = float(tpl["door_contract"]["width_m"])
    picked: list[tuple[str, float]] = []
    for side in sides:
        if len(picked) >= want:
            break
        lanes = valid_lanes(tpl, variant, side)
        if lanes:
            picked.append((side, min(lanes, key=abs)))
    # 还不够：在同一侧加第二个槽（必须与已有槽拉开一个门洞以上）
    for side in sides:
        if len(picked) >= want:
            break
        lanes = valid_lanes(tpl, variant, side)
        used = [lane for s, lane in picked if s == side]
        for lane in sorted(lanes, key=abs):
            if len(picked) >= want:
                break
            if any(abs(lane - u) < door_w + 0.5 for u in used):
                continue
            picked.append((side, lane))
            used.append(lane)
    if len(picked) < want:
        raise SystemExit(
            f"{tid}/{variant or 'base'}: 轮廓只容得下 {len(picked)} 个合法门位，骨架需要 {want}"
        )
    return picked


# ── TSCN 生成 ───────────────────────────────────────────────────────────────
def build_layout(tpl: dict, variant: str, ports: list[tuple[str, float]]) -> tuple[str, dict]:
    tid = str(tpl["template_id"])
    w, d = (float(v) for v in tpl["size_m"])
    wall_h = float(tpl["wall_height_m"])
    contract = tpl["door_contract"]
    door_w = float(contract["width_m"])
    door_h = float(contract["height_m"])
    lintel_z = float(contract["lintel_bottom_z_m"])
    clear_h = min(lintel_z, wall_h)

    # 模板自带的 lane 表必须与本脚本复算的槽位一致 —— 两套算法互为断言
    for side in ("north", "south", "east", "west"):
        declared = [float(v) for v in tpl["wall_lane_table"].get(side, [])]
        length = w if side in ("north", "south") else d
        computed = lane_offsets(length)
        if declared != computed:
            raise SystemExit(
                f"{tid}: {side} 墙 {length}m 的 lane 表 {declared} 与 RoomDoorLane 算法 {computed} 不一致"
            )

    poly = footprint(tpl, variant)
    edges = boundary_edges(poly, w, d)
    if signed_area(poly) < 0:
        poly = list(reversed(poly))

    half_w, half_d = w / 2.0, d / 2.0
    subresources: list[str] = []
    nodes: list[str] = []
    count = 0

    def to_local(x: float, y: float) -> tuple[float, float]:
        return x - half_w, y - half_d

    subresources.append(
        '[sub_resource type="BoxMesh" id="BoxMesh_floor"]\n'
        f"size = Vector3({GRID:g}, {FLOOR_THICKNESS:g}, {GRID:g})\n"
    )
    subresources.append(
        '[sub_resource type="StandardMaterial3D" id="Mat_whitebox"]\n'
        "albedo_color = Color(0.76, 0.78, 0.8, 1)\nroughness = 0.9\n"
    )
    subresources.append(
        '[sub_resource type="StandardMaterial3D" id="Mat_whitebox_wall"]\n'
        "albedo_color = Color(0.52, 0.55, 0.6, 1)\nroughness = 0.9\n"
    )
    subresources.append(
        '[sub_resource type="StandardMaterial3D" id="Mat_whitebox_pit"]\n'
        "albedo_color = Color(0.30, 0.33, 0.36, 1)\nroughness = 1.0\n"
    )

    def add_box(mesh_id: str, size: tuple[float, float, float]) -> None:
        subresources.append(
            f'[sub_resource type="BoxMesh" id="{mesh_id}"]\n'
            f"size = Vector3({size[0]:g}, {size[1]:g}, {size[2]:g})\n"
        )

    # ── 下沉坑（仅 bridge_60x50）────────────────────────────────────────────
    pit = tpl.get("sunken_pit") or {}
    bridge = tpl.get("bridge_span") or {}
    pit_rect = pit.get("rect_m") or {}
    bridge_rect = bridge.get("rect_m") or {}

    def in_rect(x: float, y: float, rect: dict) -> bool:
        if not rect:
            return False
        xr = [float(v) for v in rect["x"]]
        yr = [float(v) for v in rect["y"]]
        return xr[0] <= x <= xr[1] and yr[0] <= y <= yr[1]

    # ── 地面：只铺完整落在轮廓内的 5m 格 ────────────────────────────────────
    cols, rows = int(round(w / GRID)), int(round(d / GRID))
    if abs(cols * GRID - w) > 1e-6 or abs(rows * GRID - d) > 1e-6:
        raise SystemExit(f"{tid}: 尺寸 {w}×{d} 不是 {GRID}m 的整数倍")

    holes: list[tuple[float, float, float, float]] = []
    for r in range(rows):
        for c in range(cols):
            x0, y0 = c * GRID, r * GRID
            corners = [(x0, y0), (x0 + GRID, y0), (x0, y0 + GRID), (x0 + GRID, y0 + GRID)]
            if not all(point_in_poly(p, poly) for p in corners):
                continue
            cx, cy = x0 + GRID / 2.0, y0 + GRID / 2.0
            lx, lz = to_local(cx, cy)
            if in_rect(cx, cy, pit_rect) and not in_rect(cx, cy, bridge_rect):
                holes.append((x0, y0, x0 + GRID, y0 + GRID))
                continue
            nodes.append(
                f'[node name="Floor_R{r:02d}_C{c:02d}" type="MeshInstance3D" parent="."]\n'
                f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {lx:g}, "
                f"{WALK_Y - FLOOR_THICKNESS / 2:g}, {lz:g})\n"
                'mesh = SubResource("BoxMesh_floor")\n'
                'material_override = SubResource("Mat_whitebox")\n'
                f"metadata/walk_plane_snap_y = {WALK_Y:g}\n"
            )
            count += 1

    # ── 墙：沿每一条轮廓边段；门洞只在轮廓边真实覆盖处开 ────────────────────
    for edge in edges:
        gaps: list[tuple[float, float]] = []
        if edge["side"] is not None:
            axis_center = half_w if edge["side"] in ("north", "south") else half_d
            for side, lane in ports:
                if side != edge["side"]:
                    continue
                c = axis_center + lane
                g0, g1 = c - door_w / 2.0, c + door_w / 2.0
                if edge["lo"] - 1e-6 <= g0 and g1 <= edge["hi"] + 1e-6:
                    gaps.append((g0, g1))
        nx, ny = outward_normal(edge, poly)
        for i, (a, b) in enumerate(solid_spans(edge["lo"], edge["hi"], gaps)):
            ext_a = CORNER_EXTEND if abs(a - edge["lo"]) < 1e-6 else 0.0
            ext_b = CORNER_EXTEND if abs(b - edge["hi"]) < 1e-6 else 0.0
            a -= ext_a
            b += ext_b
            seg_len = b - a
            center = (a + b) / 2.0
            if edge["horizontal"]:
                lx, lz = to_local(center, edge["p0"][1])
                size = (seg_len, wall_h, WALL_THICKNESS)
            else:
                lx, lz = to_local(edge["p0"][0], center)
                size = (WALL_THICKNESS, wall_h, seg_len)
            px = lx + nx * WALL_THICKNESS / 2.0
            pz = lz + ny * WALL_THICKNESS / 2.0
            mesh_id = f"BoxMesh_wall_{len(subresources)}"
            add_box(mesh_id, size)
            nodes.append(
                f'[node name="Wall_{len(nodes):03d}" type="MeshInstance3D" parent="."]\n'
                f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {px:g}, {wall_h / 2.0:g}, {pz:g})\n"
                f'mesh = SubResource("{mesh_id}")\n'
                'material_override = SubResource("Mat_whitebox_wall")\n'
                f'metadata/tower_wall_direction = "{edge["side"] or "inner"}"\n'
                f"metadata/grid_unit_m = {GRID:g}\n"
            )
            count += 1

    # ── 门洞过梁 ────────────────────────────────────────────────────────────
    lintel_h = wall_h - clear_h
    for side, lane in ports:
        if lintel_h <= 1e-6:
            continue
        axis_center = half_w if side in ("north", "south") else half_d
        c = axis_center + lane
        # 找到承载这个门洞的那条轮廓边，取其外法线
        host = None
        for edge in edges:
            if edge["side"] != side:
                continue
            if edge["lo"] - 1e-6 <= c - door_w / 2.0 and c + door_w / 2.0 <= edge["hi"] + 1e-6:
                host = edge
                break
        if host is None:
            raise SystemExit(f"{tid}: 门位 {side}@{lane} 没有对应的轮廓边")
        nx, ny = outward_normal(host, poly)
        if host["horizontal"]:
            lx, lz = to_local(c, host["p0"][1])
            size = (door_w, lintel_h, WALL_THICKNESS)
        else:
            lx, lz = to_local(host["p0"][0], c)
            size = (WALL_THICKNESS, lintel_h, door_w)
        mesh_id = f"BoxMesh_lintel_{len(subresources)}"
        add_box(mesh_id, size)
        lane_tag = f"{lane:+.1f}".replace(".", "_").replace("+", "p").replace("-", "m")
        nodes.append(
            f'[node name="Lintel_{side}_{lane_tag}" type="MeshInstance3D" parent="."]\n'
            f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, "
            f"{lx + nx * WALL_THICKNESS / 2.0:g}, {clear_h + lintel_h / 2.0:g}, "
            f"{lz + ny * WALL_THICKNESS / 2.0:g})\n"
            f'mesh = SubResource("{mesh_id}")\n'
            'material_override = SubResource("Mat_whitebox_wall")\n'
        )
        count += 1

    # ── 下沉坑：坑壁下延 + 坑底 + 桥两侧护栏 ────────────────────────────────
    if pit_rect:
        depth = float(pit.get("depth_m", 0.0))
        xr = [float(v) for v in pit_rect["x"]]
        yr = [float(v) for v in pit_rect["y"]]
        bx = [float(v) for v in bridge_rect["x"]] if bridge_rect else []
        wall_hole = (bx[0], bx[1]) if bx else None
        wall_h_drop = depth
        # 坑底满铺（下层纯装饰，不可达）
        for r in range(int(round((yr[1] - yr[0]) / GRID))):
            for c in range(int(round((xr[1] - xr[0]) / GRID))):
                cx = xr[0] + GRID * (c + 0.5)
                cy = yr[0] + GRID * (r + 0.5)
                lx, lz = to_local(cx, cy)
                nodes.append(
                    f'[node name="PitFloor_R{r:02d}_C{c:02d}" type="MeshInstance3D" parent="."]\n'
                    f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {lx:g}, "
                    f"{WALK_Y - wall_h_drop - FLOOR_THICKNESS / 2:g}, {lz:g})\n"
                    'mesh = SubResource("BoxMesh_floor")\n'
                    'material_override = SubResource("Mat_whitebox_pit")\n'
                )
                count += 1
        # 坑壁：南北沿在桥口留空；东西沿即桥的两侧护栏（做到墙顶）
        for tag, horizontal, fixed, lo, hi, hole in (
            ("north", True, yr[0], xr[0], xr[1], wall_hole),
            ("south", True, yr[1], xr[0], xr[1], wall_hole),
            ("west", False, xr[0], yr[0], yr[1], None),
            ("east", False, xr[1], yr[0], yr[1], None),
        ):
            if horizontal:
                spans = solid_spans(lo, hi, [hole] if hole else [])
            else:
                spans = [(lo, hi)]
            for i, (a, b) in enumerate(spans):
                seg = b - a
                center = (a + b) / 2.0
                if horizontal:
                    lx, lz = to_local(center, fixed)
                    size = (seg, wall_h_drop, WALL_THICKNESS)
                else:
                    lx, lz = to_local(fixed, center)
                    size = (WALL_THICKNESS, wall_h_drop, seg)
                mesh_id = f"BoxMesh_pit_{len(subresources)}"
                add_box(mesh_id, size)
                nodes.append(
                    f'[node name="PitWall_{tag}_{i}" type="MeshInstance3D" parent="."]\n'
                    f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {lx:g}, "
                    f"{WALK_Y - wall_h_drop / 2:g}, {lz:g})\n"
                    f'mesh = SubResource("{mesh_id}")\n'
                    'material_override = SubResource("Mat_whitebox_pit")\n'
                )
                count += 1
        # 桥两侧护栏：沿桥长轴做到墙顶，让「工」字在俯视图里读得出来
        for tag, fixed in (("west", bx[0]), ("east", bx[1])):
            seg = yr[1] - yr[0]
            center = (yr[0] + yr[1]) / 2.0
            lx, lz = to_local(fixed, center)
            mesh_id = f"BoxMesh_rail_{len(subresources)}"
            add_box(mesh_id, (WALL_THICKNESS, wall_h, seg))
            nodes.append(
                f'[node name="BridgeRail_{tag}" type="MeshInstance3D" parent="."]\n'
                f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {lx:g}, {wall_h / 2.0:g}, {lz:g})\n"
                f'mesh = SubResource("{mesh_id}")\n'
                'material_override = SubResource("Mat_whitebox_wall")\n'
            )
            count += 1

    # ── 端口 ────────────────────────────────────────────────────────────────
    port_basis = {
        "north": "-1, 0, 0, 0, 1, 0, 0, 0, -1",
        "south": "1, 0, 0, 0, 1, 0, 0, 0, 1",
        "west": "0, 0, 1, 0, 1, 0, -1, 0, 0",
        "east": "0, 0, -1, 0, 1, 0, 1, 0, 0",
    }
    outward = {"north": "(0, -1)", "south": "(0, 1)", "west": "(-1, 0)", "east": "(1, 0)"}
    port_lines: list[str] = [
        f'[node name="ConnectionPorts" type="Node3D" parent="."]\n'
        f"metadata/connection_port_count = {len(ports)}\n"
    ]
    for i, (side, lane) in enumerate(ports):
        if side in ("north", "south"):
            px, pz = lane, (-half_d if side == "north" else half_d)
        else:
            px, pz = (-half_w if side == "west" else half_w), lane
        port_lines.append(
            f'[node name="Port_{chr(ord("A") + i)}" type="Marker3D" parent="ConnectionPorts"]\n'
            f"transform = Transform3D({port_basis[side]}, {px:g}, 0, {pz:g})\n"
            f'metadata/port_id = "{chr(ord("A") + i)}"\n'
            f'metadata/side = "{side}"\n'
            f"metadata/lane_m = {lane:g}\n"
            f"metadata/outward = Vector2{outward[side]}\n"
            "metadata/connected = false\n"
            f'metadata/door_opening_m = [{door_w:g}, {clear_h:g}]\n'
        )

    # ── 可走导航多边形：轮廓本身 + 每个门洞外扩一小块 ────────────────────────
    nav: list[list[list[float]]] = [[[to_local(x, y)[0], WALK_Y, to_local(x, y)[1]] for x, y in poly]]
    for side, lane in ports:
        h = door_w / 2.0
        if side in ("north", "south"):
            z0 = -half_d - 0.6 if side == "north" else half_d - 0.6
            nav.append([[lane - h, WALK_Y, z0], [lane + h, WALK_Y, z0],
                        [lane + h, WALK_Y, z0 + 1.2], [lane - h, WALK_Y, z0 + 1.2]])
        else:
            x0 = -half_w - 0.6 if side == "west" else half_w - 0.6
            nav.append([[x0, WALK_Y, lane - h], [x0 + 1.2, WALK_Y, lane - h],
                        [x0 + 1.2, WALK_Y, lane + h], [x0, WALK_Y, lane + h]])

    area = abs(signed_area(footprint(tpl, variant)))
    shell_id = f"rt_{tid}_{variant}" if variant else f"rt_{tid}"
    header = (
        '[node name="ExpeditionRoomStaticLayout" type="Node3D"]\n'
        'metadata/schema = "shellstorm2.expedition.room_whitebox.v002"\n'
        f'metadata/shell_id = "{shell_id}"\n'
        f'metadata/template_id = "{tid}"\n'
        f'metadata/variant = "{variant}"\n'
        f"metadata/size_m = [{w:g}, {d:g}]\n"
        f"metadata/grid_unit_m = {GRID:g}\n"
        f"metadata/wall_height_m = {wall_h:g}\n"
        f"metadata/door_width_m = {door_w:g}\n"
        f"metadata/door_clear_height_m = {clear_h:g}\n"
        f"metadata/footprint_area_m2 = {area:g}\n"
        f"metadata/footprint_is_rect = {'true' if area == w * d else 'false'}\n"
        f"metadata/footprint_polygon_m = {json.dumps([[x, y] for x, y in footprint(tpl, variant)])}\n"
        f"metadata/layout_instance_total = {count}\n"
        f"metadata/connection_port_count = {len(ports)}\n"
        "metadata/whitebox = true\n"
        'metadata/whitebox_excludes = ["floor_art","wall_art","props","traps","spawn_points","lights","doors"]\n'
        f"metadata/walkable_navigation_polygons = {json.dumps(nav)}\n"
        'metadata/source = "scripts/build_whitebox_room_tscn.py"\n'
        '\n[node name="RoomCeilingLight" type="Node3D" parent="."]\n'
        f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {wall_h - 1.5:g}, 0)\n"
        'metadata/pending = "whitebox 不含灯；建美术时替换为 WastelandLight3D"\n'
        '\n[node name="RoomLightSwitch3D" type="Area3D" parent="."]\n'
        'metadata/pending = "whitebox 不含开关；建美术时替换为 RoomLightSwitch3D"\n'
    )

    text = '[gd_scene format=3]\n\n' + "\n".join(subresources) + "\n" + header + "\n".join(nodes) \
        + "\n" + "\n".join(port_lines)
    meta = {
        "shell_id": shell_id, "template_id": tid, "variant": variant,
        "size_m": [w, d], "ports": ports, "area_m2": area, "instances": count,
        "polygon": footprint(tpl, variant),
        "pit_rect": pit_rect, "bridge_rect": bridge_rect,
    }
    return text, meta


# ── 预览 ────────────────────────────────────────────────────────────────────
def preview(meta: dict, out: Path) -> None:
    from PIL import Image, ImageDraw
    S = 12
    pad = 40
    w, d = meta["size_m"]
    poly = meta["polygon"]
    W, H = int(w * S) + pad * 2, int(d * S) + pad * 2
    im = Image.new("RGB", (W, H), (247, 248, 249))
    dr = ImageDraw.Draw(im)

    def X(x): return pad + x * S
    def Y(y): return pad + y * S

    dr.polygon([(X(x), Y(y)) for x, y in poly], fill=(206, 210, 214), outline=(90, 96, 102))
    # 下沉坑与跨桥：桥房不看这个就看不出「工」字，等于预览失效
    pit_rect = meta.get("pit_rect") or {}
    bridge_rect = meta.get("bridge_rect") or {}
    if pit_rect:
        pxr = [float(v) for v in pit_rect["x"]]
        pyr = [float(v) for v in pit_rect["y"]]
        dr.rectangle([X(pxr[0]), Y(pyr[0]), X(pxr[1]), Y(pyr[1])], fill=(62, 68, 74))
        if bridge_rect:
            bxr = [float(v) for v in bridge_rect["x"]]
            dr.rectangle([X(bxr[0]), Y(pyr[0]), X(bxr[1]), Y(pyr[1])], fill=(150, 156, 162))
            dr.text((X(bxr[0]) + 4, Y(pyr[0]) + 4), "BRIDGE 10m", fill=(250, 250, 250))
        dr.text((X(pxr[0]) + 4, Y(pyr[1]) - 14), "SUNKEN PIT 12m", fill=(240, 240, 240))
    for i in range(1, int(w // GRID)):
        dr.line([X(i * GRID), pad, X(i * GRID), pad + d * S], fill=(186, 190, 195))
    for i in range(1, int(d // GRID)):
        dr.line([pad, Y(i * GRID), pad + w * S, Y(i * GRID)], fill=(186, 190, 195))
    h = 1.1
    for side, lane in meta["ports"]:
        if side in ("north", "south"):
            c = w / 2 + lane
            y = 0 if side == "north" else d
            dr.rectangle([X(c - h), Y(y) - 4, X(c + h), Y(y) + 4], fill=(230, 168, 40))
        else:
            c = d / 2 + lane
            x = 0 if side == "west" else w
            dr.rectangle([X(x) - 4, Y(c - h), X(x) + 4, Y(c + h)], fill=(230, 168, 40))
    for side, lane in meta["ports"]:
        px = (w / 2 + lane) if side in ("north", "south") else (0 if side == "west" else w)
        py = (0 if side == "north" else d) if side in ("north", "south") else (d / 2 + lane)
        r = 5
        dr.ellipse([X(px) - r, Y(py) - r, X(px) + r, Y(py) + r], fill=(30, 90, 190))
    label = f"{meta['shell_id']}  {w:g}x{d:g}m  area={meta['area_m2']:g}m2  ports={len(meta['ports'])}"
    dr.text((pad, 12), label, fill=(40, 44, 48))
    out.parent.mkdir(parents=True, exist_ok=True)
    im.save(out)


def main(argv: list[str]) -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    want_preview = "--preview" in argv
    templates = load_templates()
    budget = port_budget(templates)

    written: list[dict] = []
    for tid in sorted(templates):
        tpl = templates[tid]
        want = int(budget.get(tid, 1))
        for variant in variants_of(tpl):
            ports = choose_ports(tpl, variant, want)
            text, meta = build_layout(tpl, variant, ports)
            name = f"{meta['shell_id']}_static_layout.tscn"
            (OUT_DIR / name).write_text(text + "\n", encoding="utf-8")
            written.append(meta)
            print(f"written {name:52s} ports={len(ports)} area={meta['area_m2']:g} "
                  f"instances={meta['instances']}")
            if want_preview:
                preview(meta, PREVIEW_DIR / name.replace(".tscn", ".png"))

    # 清掉上一版遗留的旧壳（v1 是矩形近似，同名但不是同一份几何）
    keep = {f"{m['shell_id']}_static_layout.tscn" for m in written}
    for stale in OUT_DIR.glob("rt_*_static_layout.tscn"):
        if stale.name not in keep:
            stale.unlink()
            print(f"removed stale {stale.name}")

    print(f"\n{len(written)} 份布局 -> {OUT_DIR.relative_to(ROOT)}")
    for m in written:
        print(f"  {m['shell_id']:34s} ports={m['ports']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
