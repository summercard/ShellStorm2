#!/usr/bin/env python3
"""boss 房两扇门的**可通行性**精确判定。

不同于 scan_all_doors 的「有没有碰撞盒擦到窗口」：这里按玩家胶囊直径算**剩余可通行缝宽**。

口径:
  - 门洞带 = 沿墙方向 ±1.10m(门宽 2.2);
  - 阻挡判定高度 = 玩家净空 CLEAR_TOP = 身高 1.5 + 余量 0.2 = 1.7m。
    **只数侵入 y<1.7m 的碰撞盒**; 门楣(底 2.142m)本身不挡人, 不算。
    (原先按门洞名义高 2.5m 计, 会把门楣误判为阻挡, 故此处按玩家净空判定。)
  - 通道深度 = 墙平面内外各 2.0m(玩家从邻房进来要能走到房内);
  - 玩家胶囊 radius 0.34 => 需要 >= 0.68m 连续空缝才过得去;
  - 对每一个沿通道方向的切片, 取该切片上被碰撞盒挡住的「沿墙区间」,
    求 2.2m 带内的最大空缝。**任一深度切片上最大空缝 < 0.68m 即判为堵死。**
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scan_door_clearance as sdc  # noqa: E402

REPO = sdc.REPO
TSCN = os.path.join(
    REPO, "assets", "art", "environments", "tower_zones", "expedition",
    "runtime", "room_instances", "expedition_01", "f00_boss_static_layout.tscn",
)
PLAYER_RADIUS = 0.34
NEED = 2.0 * PLAYER_RADIUS          # 0.68
LANE_HALF = 1.10
PLAYER_HEIGHT = 1.50
CLEAR_MARGIN = 0.20
CLEAR_TOP = PLAYER_HEIGHT + CLEAR_MARGIN   # 1.70: 只有侵入此高度以下的盒才挡人
WALL = 25.0                          # boss bbox 半宽 (50 x 40)
SLAB = 2.0                           # 墙平面内外各看多深


def boxes_in_room():
    text = open(TSCN, encoding="utf-8").read()
    ext = {}
    for m in __import__("re").finditer(
            r'\[ext_resource type="PackedScene" path="([^"]+)" id="([^"]+)"\]', text):
        ext[m.group(2)] = m.group(1)
    out = []
    for name, ntype, parent, rid, b in sdc.node_blocks(text):
        if not rid:
            continue
        rows, origin = sdc.local_transform(b)
        prefab = sdc.res_to_path(ext[rid])
        slug = os.path.basename(os.path.dirname(prefab))
        for sr, so, size in sdc.collect_shapes(prefab):
            lo = [1e9] * 3
            hi = [-1e9] * 3
            for sx in (-0.5, 0.5):
                for sy in (-0.5, 0.5):
                    for sz in (-0.5, 0.5):
                        p = sdc.xform(rows, origin, sdc.xform(sr, so, [sx * size[0], sy * size[1], sz * size[2]]))
                        for i in range(3):
                            lo[i] = min(lo[i], p[i])
                            hi[i] = max(hi[i], p[i])
            out.append((name, slug, lo, hi))
    return out


def analyse(boxes, side, lane_center):
    sign = -1.0 if side == "west" else 1.0
    wall_x = sign * WALL
    x_lo, x_hi = sorted((wall_x - sign * SLAB, wall_x + sign * SLAB))
    # 通道方向 = x; 沿墙方向 = z
    relevant = []
    for name, slug, lo, hi in boxes:
        if hi[2] <= lane_center - LANE_HALF or lo[2] >= lane_center + LANE_HALF:
            continue
        if hi[1] <= 0.0 or lo[1] >= CLEAR_TOP:
            continue
        if hi[0] <= x_lo or lo[0] >= x_hi:
            continue
        relevant.append((name, slug, lo, hi))

    print("\n=== boss %s 门 (局部 x=%.1f, lane z=%.1f) 通道 x[%.2f, %.2f] ===" % (
        side, wall_x, lane_center, x_lo, x_hi))
    if not relevant:
        print("   无碰撞盒进入通道 -> 通行 OK")
        return True
    for name, slug, lo, hi in sorted(relevant, key=lambda t: t[2][0]):
        print("   %-24s slug=%-30s x[%7.3f..%7.3f] y[%6.3f..%6.3f] z[%7.3f..%7.3f]" % (
            name, slug, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))

    # 逐切片(沿 x, 步长 0.02m)求沿墙最大空缝
    worst = (1e9, None)
    x = x_lo
    while x <= x_hi:
        blocked = []
        for name, slug, lo, hi in relevant:
            if lo[0] <= x <= hi[0]:
                z0 = max(lo[2], lane_center - LANE_HALF)
                z1 = min(hi[2], lane_center + LANE_HALF)
                if z1 > z0:
                    blocked.append((z0, z1, name))
        blocked.sort()
        cur = lane_center - LANE_HALF
        gap = 0.0
        gap_at = None
        for z0, z1, name in blocked:
            if z0 > cur:
                if z0 - cur > gap:
                    gap, gap_at = z0 - cur, (cur, z0, name)
            cur = max(cur, z1)
        if lane_center + LANE_HALF > cur and (lane_center + LANE_HALF - cur) > gap:
            gap, gap_at = lane_center + LANE_HALF - cur, (cur, lane_center + LANE_HALF, "带外")
        if gap < worst[0]:
            worst = (gap, (round(x, 3), gap_at))
        x += 0.02
    gap, info = worst
    print("   最窄处空缝 = %.3f m  (需 >= %.2f m)  @ x=%s 缺口=%s" % (gap, NEED, info[0], info[1]))
    print("   判定: %s" % ("堵死" if gap < NEED else "可通行"))
    return gap >= NEED


if __name__ == "__main__":
    boxes = boxes_in_room()
    print("boss 房碰撞盒总数 = %d" % len(boxes))
    ok_w = analyse(boxes, "west", -2.5)
    ok_e = analyse(boxes, "east", -2.5)
    print("\n结论: west=%s east=%s" % ("OK" if ok_w else "BLOCKED", "OK" if ok_e else "BLOCKED"))
