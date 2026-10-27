#!/usr/bin/env python3
"""远征关卡03 房间 / 通道 / 门 三类白盒布局门禁（数据驱动）。

## 为什么重写

旧版把 **9 条文件名 + 端口数**硬编码在脚本里。后果有三个，都是实际踩过的：

1. **加一份壳要改门禁。** 门禁本该是"检查产物是否符合数据"，结果变成了"记录我知道哪些文件"。
2. **不校验外轮廓。** 旧版 9 份全是矩形壳，而 `corridor_45x40` 的 `l_turn` 缺东南角
   30×15、`u_turn` 有 30×10 内岛、`db_70x50` 两变体各缺角 —— 门禁照过。
   这是"门禁绿了、东西是错的"最典型的形态。
3. **不校验门位是否真在轮廓上。** 门开在缺角处等于开了个通向室外的洞。

本版所有期望值都从数据源算：

| 校验项 | 真源 |
|---|---|
| 该有哪些壳 | `room_templates/*.json` 的 `variants`（有变体就一模板多壳） |
| 每壳端口数 | 六张 `flows/*.json` 的节点度数（`NORMAL` 取 `template_pool` 并集的最大值） |
| 房型外轮廓 | `variant_footprints` |
| 门位合法性 | 轮廓边 ∩ `wall_lane_table`（整套门洞必须落在同一条外墙段上） |
| 门套件齐全 | `door_catalog.json` 的 5 种门，且门扇 TSCN 存在 |
| 通道套件齐全 | `corridor_catalog.json` 的 9 份壳，且 TSCN 存在 |

## 不做的判断

不看材质、不看陈设好不好、不看渲染。**几何是不是真的对，要真跑 Godot 加载 + 出图**，
文本门禁只能保证"契约字段与几何描述自洽"。这一条写在 `--limit` 输出里，避免被误当验收。

运行：
    python3 scripts/check_expedition03_room_layouts.py            # 判定
    python3 scripts/check_expedition03_room_layouts.py --report   # 只看不判
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLAN_DIR = ROOT / "data/level_plans/expedition_03"
TEMPLATE_DIR = PLAN_DIR / "room_templates"
FLOW_DIR = PLAN_DIR / "flows"
DOOR_CATALOG = PLAN_DIR / "door_catalog.json"
CORRIDOR_CATALOG = PLAN_DIR / "corridor_catalog.json"
LAYOUT_DIR = (
    ROOT / "assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03"
)
DOOR_DIR = (
    ROOT / "assets/art/environments/tower_zones/expedition/runtime/common_components/whitebox_doors"
)

GRID = 5.0
# 入口安全屋除常规门前之外还有一扇弃局门（设计页 §2）。与生成器同源。
EXTRA_PORTS = {"safe_15x15": 1}
# 哪些侧允许开门：bridge 模板 note 写死「东西长边一律不许连」。与生成器同源。
SIDE_OVERRIDES = {"bridge_60x50": ["north", "south"]}

NODE_RE = re.compile(r'^\[node name="(?P<name>[^"]*)"(?P<rest>[^\]]*)\]', re.M)
PORT_RE = re.compile(r'^\[node name="(?P<name>Port_[A-Z])"(?P<rest>[^\]]*)\]', re.M)
META_RE = re.compile(r'^metadata/(?P<key>[A-Za-z0-9_]+) = (?P<value>.+)$', re.M)


# ── 与 RoomDoorLane.gd / 生成器同源的槽位算法 ────────────────────────────────
def lane_offsets(length_m: float) -> list[float]:
    count = max(1, int(round(length_m / GRID)))
    first = 1 if count >= 3 else 0
    last = count - 2 if count >= 3 else count - 1
    return [-length_m * 0.5 + GRID * (i + 0.5) for i in range(first, last + 1)]


def load_templates() -> dict[str, dict]:
    out: dict[str, dict] = {}
    for path in sorted(TEMPLATE_DIR.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        out[str(data["template_id"])] = data
    return out


def port_budget(templates: dict[str, dict]) -> tuple[dict[str, int], list[str]]:
    budget: dict[str, int] = {}
    errors: list[str] = []
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
            targets.extend(str(t) for t in node.get("template_pool", []) if t)
            for tid in targets:
                if tid not in templates:
                    errors.append(f"{path.name}: 引用不存在的模板 {tid}")
                    continue
                budget[tid] = max(budget.get(tid, 0), needs)
    for tid, extra in EXTRA_PORTS.items():
        if tid in budget:
            budget[tid] += extra
    budget.setdefault("bridge_60x50", 2)
    return budget, errors


def footprint(tpl: dict, variant: str) -> list[tuple[float, float]]:
    fps = tpl.get("variant_footprints") or {}
    if variant and variant in fps:
        return [(float(p[0]), float(p[1])) for p in fps[variant]["vertices_m"]]
    w, d = (float(v) for v in tpl["size_m"])
    return [(0.0, 0.0), (w, 0.0), (w, d), (0.0, d)]


def variants_of(tpl: dict) -> list[str]:
    vs = [str(v) for v in tpl.get("variants", [])]
    return vs if vs else [""]


def signed_area(poly: list[tuple[float, float]]) -> float:
    s = 0.0
    for i, (x0, y0) in enumerate(poly):
        x1, y1 = poly[(i + 1) % len(poly)]
        s += x0 * y1 - x1 * y0
    return s * 0.5


def boundary_edges(poly, w: float, d: float) -> list[dict]:
    edges: list[dict] = []
    eps = 1e-6
    for i, p0 in enumerate(poly):
        p1 = poly[(i + 1) % len(poly)]
        horizontal = abs(p0[1] - p1[1]) < eps
        vertical = abs(p0[0] - p1[0]) < eps
        if not (horizontal or vertical):
            continue
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
        edges.append({"side": side, "lo": lo, "hi": hi})
    return edges


def valid_lanes(tpl: dict, variant: str, side: str) -> list[float]:
    w, d = (float(v) for v in tpl["size_m"])
    poly = footprint(tpl, variant)
    edges = boundary_edges(poly, w, d)
    door_w = float(tpl["door_contract"]["width_m"])
    length = w if side in ("north", "south") else d
    axis = w / 2.0 if side in ("north", "south") else d / 2.0
    out: list[float] = []
    for lane in lane_offsets(length):
        c = axis + lane
        g0, g1 = c - door_w / 2.0, c + door_w / 2.0
        for edge in edges:
            if edge["side"] == side and edge["lo"] - 1e-6 <= g0 and g1 <= edge["hi"] + 1e-6:
                out.append(float(lane))
                break
    return out


# ── TSCN 解析 ───────────────────────────────────────────────────────────────
def parse_tscn(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    metas = {m["key"]: m["value"].strip() for m in META_RE.finditer(text)}
    nodes = NODE_RE.findall(text)
    ports = PORT_RE.findall(text)
    return {"text": text, "metas": metas, "node_count": len(nodes), "ports": len(ports)}


def check_room_shell(path: Path, tpl: dict, variant: str, want_ports: int) -> list[str]:
    errs: list[str] = []
    p = parse_tscn(path)
    metas = p["metas"]
    tid = str(tpl["template_id"])
    label = f"{path.name}"

    if "room_id" in metas:
        errs.append(f"{label}: 根节点写了 metadata/room_id —— 共享壳不得绑定具体房间")
    if str(metas.get("template_id", "")).strip('"') != tid:
        errs.append(f"{label}: template_id = {metas.get('template_id')} != {tid}")
    if str(metas.get("variant", "")).strip('"') != variant:
        errs.append(f"{label}: variant = {metas.get('variant')} != {variant or '(base)'}")

    # 外轮廓：TSCN 里声明的必须与模板真源逐点一致
    want_poly = footprint(tpl, variant)
    raw = metas.get("footprint_polygon_m", "")
    try:
        got_poly = [(float(a), float(b)) for a, b in json.loads(raw.strip())]
    except (ValueError, TypeError, json.JSONDecodeError):
        errs.append(f"{label}: footprint_polygon_m 解析失败：{raw[:60]}")
        got_poly = []
    if got_poly and got_poly != want_poly:
        errs.append(f"{label}: 轮廓与模板真源不一致 {got_poly} != {want_poly}")

    want_area = abs(signed_area(want_poly))
    try:
        got_area = float(metas.get("footprint_area_m2", "nan"))
    except ValueError:
        got_area = float("nan")
    if abs(got_area - want_area) > 1e-6:
        errs.append(f"{label}: footprint_area_m2 = {got_area} != {want_area}")

    w, d = (float(v) for v in tpl["size_m"])
    is_rect = abs(want_area - w * d) < 1e-6
    if str(metas.get("footprint_is_rect", "")).strip('"') != ("true" if is_rect else "false"):
        errs.append(f"{label}: footprint_is_rect 与轮廓不符（面积 {want_area} vs 包围盒 {w * d}）")

    if p["ports"] < want_ports:
        errs.append(f"{label}: 端口 {p['ports']} < 需要 {want_ports}（骨架最多 {want_ports} 门）")

    raw_total = metas.get("layout_instance_total", "")
    if not raw_total:
        errs.append(f"{label}: 缺 metadata/layout_instance_total")
    else:
        try:
            declared = int(raw_total)
        except ValueError:
            errs.append(f"{label}: layout_instance_total 不是整数：{raw_total}")
        else:
            non_component = 4 + p["ports"]
            actual = max(0, p["node_count"] - non_component)
            if declared != actual:
                errs.append(
                    f"{label}: layout_instance_total = {declared} != 实际组件 {actual}"
                )

    if "walkable_navigation_polygons" not in metas:
        errs.append(f"{label}: 缺 walkable_navigation_polygons")

    # 门位必须落在轮廓外墙上 —— 这是旧版完全没有的检查
    sides_allowed = SIDE_OVERRIDES.get(tid, ["north", "south", "east", "west"])
    for m in re.finditer(
        r'metadata/side = "(?P<side>[a-z]+)"\s*\n\s*metadata/lane_m = (?P<lane>-?[0-9.]+)',
        p["text"],
    ):
        side = m.group("side")
        lane = float(m.group("lane"))
        if side not in sides_allowed:
            errs.append(f"{label}: 门开在 {side}，而该模板禁止 {side} 侧开门")
            continue
        if not any(abs(lane - v) < 1e-6 for v in valid_lanes(tpl, variant, side)):
            errs.append(
                f"{label}: 门位 {side}@{lane} 不在轮廓外墙的合法槽位上 "
                f"（合法 {valid_lanes(tpl, variant, side)}）"
            )
    return errs


def check_corridor(path: Path, spec: dict) -> list[str]:
    errs: list[str] = []
    p = parse_tscn(path)
    metas = p["metas"]
    label = path.name
    if "room_id" in metas:
        errs.append(f"{label}: 通道壳不得绑定具体房间（写了 metadata/room_id）")
    if str(metas.get("shell_id", "")).strip('"') != spec["shell_id"]:
        errs.append(f"{label}: shell_id 与清单不符")
    if p["ports"] != len(spec["ports"]):
        errs.append(f"{label}: 端口 {p['ports']} != 清单 {len(spec['ports'])}")
    raw = metas.get("layout_instance_total", "")
    if raw:
        non_component = 4 + p["ports"]
        actual = max(0, p["node_count"] - non_component)
        if int(raw) != actual:
            errs.append(f"{label}: layout_instance_total = {raw} != 实际组件 {actual}")
    if "walkable_navigation_polygons" not in metas:
        errs.append(f"{label}: 缺 walkable_navigation_polygons")
    return errs


def check_door_catalog() -> tuple[list[str], int]:
    errs: list[str] = []
    if not DOOR_CATALOG.is_file():
        return [f"缺门策略表 {DOOR_CATALOG.relative_to(ROOT)}"], 0
    cat = json.loads(DOOR_CATALOG.read_text(encoding="utf-8"))
    kinds = cat.get("kinds", {})
    required = {"normal", "locked", "boss", "secret", "cell"}
    missing = required - set(kinds)
    if missing:
        errs.append(f"门策略表缺门型：{sorted(missing)}")

    policy_keys = {"requires_key", "requires_clear", "triggers_fate"}
    for kind, entry in kinds.items():
        scene = str(entry.get("panel_scene", ""))
        if not scene:
            errs.append(f"门 {kind}: 缺 panel_scene")
            continue
        rel = scene.replace("res://", "")
        path = ROOT / rel
        if not path.is_file():
            errs.append(f"门 {kind}: 门扇 TSCN 不存在 {rel}")
            continue
        p = parse_tscn(path)
        if str(p["metas"].get("door_kind", "")).strip('"') != kind:
            errs.append(f"门 {kind}: 门扇内 door_kind 不符")
        policy = entry.get("access_policy")
        if entry.get("runtime_class") == "RoomDoor3D":
            if not isinstance(policy, dict):
                errs.append(f"门 {kind}: RoomDoor3D 型门缺 access_policy")
            else:
                if set(policy) != policy_keys:
                    errs.append(
                        f"门 {kind}: access_policy 字段 {sorted(policy)} 必须恰好是 "
                        f"{sorted(policy_keys)}（对齐 RoomDoor3D.set_access_policy）"
                    )
        elif entry.get("runtime_class") == "SecretDoor3D":
            if policy is not None:
                errs.append(f"门 {kind}: SecretDoor3D 型门不该有 access_policy（它没有开关语义）")
        else:
            errs.append(f"门 {kind}: runtime_class 只能是 RoomDoor3D 或 SecretDoor3D")
    return errs, len(kinds)


def main(argv: list[str]) -> int:
    report_only = "--report" in argv
    issues: list[str] = []
    missing: list[str] = []
    present: list[str] = []

    if not LAYOUT_DIR.is_dir():
        issues.append(f"缺少目录 {LAYOUT_DIR.relative_to(ROOT)}")
        templates: dict[str, dict] = {}
    else:
        templates = load_templates()

    budget, budget_errors = port_budget(templates)
    issues.extend(budget_errors)

    # ── 房间壳：期望集合从模板 variants 派生 ────────────────────────────────
    expected_rooms: dict[str, tuple[dict, str, int]] = {}
    for tid, tpl in templates.items():
        for variant in variants_of(tpl):
            shell = f"rt_{tid}_{variant}" if variant else f"rt_{tid}"
            expected_rooms[f"{shell}_static_layout.tscn"] = (tpl, variant, int(budget.get(tid, 1)))

    for name, (tpl, variant, want_ports) in expected_rooms.items():
        path = LAYOUT_DIR / name
        if not path.is_file():
            missing.append(name)
            continue
        present.append(name)
        issues.extend(check_room_shell(path, tpl, variant, want_ports))

    # ── 通道壳 ──────────────────────────────────────────────────────────────
    corridor_specs: list[dict] = []
    if CORRIDOR_CATALOG.is_file():
        cat = json.loads(CORRIDOR_CATALOG.read_text(encoding="utf-8"))
        corridor_specs = list(cat.get("shells", []))
    else:
        issues.append(f"缺通道清单 {CORRIDOR_CATALOG.relative_to(ROOT)}")
    for spec in corridor_specs:
        name = f"{spec['shell_id']}_static_layout.tscn"
        path = LAYOUT_DIR / name
        if not path.is_file():
            missing.append(name)
            continue
        present.append(name)
        issues.extend(check_corridor(path, spec))

    # ── 门套件 ──────────────────────────────────────────────────────────────
    door_errors, door_count = check_door_catalog()
    issues.extend(door_errors)

    # ── 多余产物：目录里存在但没有任何清单认领的 rt_/cr_ 壳 ──────────────────
    known = set(expected_rooms) | {f"{s['shell_id']}_static_layout.tscn" for s in corridor_specs}
    if LAYOUT_DIR.is_dir():
        for path in LAYOUT_DIR.glob("rt_*_static_layout.tscn"):
            if path.name not in known:
                issues.append(f"{path.name}: 目录里有但清单没认领（旧版残留或改名未清理）")
        for path in LAYOUT_DIR.glob("cr_*_static_layout.tscn"):
            if path.name not in known:
                issues.append(f"{path.name}: 目录里有但清单没认领")

    result = {
        "ok": (not issues and not missing) if not report_only else not issues,
        "room_shells": {"required": len(expected_rooms), "present": len(present) - len(corridor_specs)},
        "corridor_shells": {"required": len(corridor_specs)},
        "door_kinds": door_count,
        "missing": missing,
        "issues": issues,
        "limit": (
            "只校验契约字段与几何描述的自洽（轮廓、端口数、门位合法性、实例计数）。"
            "不判断几何是否真的对 —— 那要真跑 Godot 加载与出图，文本门禁证明不了。"
        ),
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if report_only:
        return 0
    return 1 if (issues or missing) else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
