#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""组件拆分判断：包络候选聚类 + 房型 50 组件预算 + 同族 3–5 变体门禁。

用法:
    python plan_components.py <component_library_dir> [--write] [--out PATH] [--max 3] [--hard-max 5] [--component-limit 50] [--tol 0.10]

只读：默认仅打印报告。加 --write 才落 component_plan.json。
退出码: 0 = 无违规; 1 = 存在违规

判据来源: references/component_split_decision_contract.md
注意: 几何指纹需 Blender 侧校验（本脚本只用包络+材质+旋转做候选聚类）。
"""
import argparse
import collections
import json
import os
import re
import sys

AXIS_WORDS = {'north', 'south', 'east', 'west', 'front', 'rear', 'inner', 'outer', 'left', 'right'}
NUM_RE = re.compile(r'^-?\d+(\.\d+)?$')
SINGLE_ALPHA = re.compile(r'^[a-z]$')
FORBIDDEN = [
    (re.compile(r'(?i)(north|south|east|west|front|rear|inner|outer)'), '方位词'),
    (re.compile(r'(?i)slot[_-]?\d+'), '槽位号'),
    (re.compile(r'-?\d+\.\d+'), '坐标小数'),
    (re.compile(r'(^|[_-])\d{1,3}($|[_-])'), '纯数字段'),
]
AXIS_RE = re.compile(r'([+-])([XYZ])\b')
VALID_AXIS = {'-X', '+X', '-Y', '+Y', '-Z', '+Z'}
STRUCT_HINT = ('墙', '地', '天花', '门', '梁', '结构', 'wall', 'floor', 'tile', 'ceiling', 'door', 'beam')


def family(slug):
    """兼容旧清单：从 slug 猜族名。新清单应显式写 component_family。"""
    out = []
    for t in re.split(r'[_-]', str(slug).lower()):
        if not t or t in AXIS_WORDS or NUM_RE.match(t):
            continue
        out.append(t)
    while len(out) > 1 and SINGLE_ALPHA.match(out[-1]):
        out.pop()
    return '_'.join(out) or 'unknown'


def family_of(x):
    return str(x.get('component_family') or family(name_of(x))).strip().lower()


def cid(x):
    return x.get('component_id') or x.get('package_id') or x.get('asset_id') or '?'


def name_of(x):
    return x.get('slug') or cid(x)


def bounds_of(x):
    return tuple(round(float(t), 3) for t in (x.get('bounds_size_m') or x.get('bounds_size') or []))


def key_bounds(x):
    """族内比较键：结构件平面尺寸排序（旋转不变 —— 墙转 90° 视为同一件）。"""
    b = bounds_of(x)
    if len(b) == 3 and is_structure(x):
        return (min(b[0], b[1]), max(b[0], b[1]), b[2])
    return b


def extract_axis(v):
    if not v:
        return ''
    m = AXIS_RE.search(str(v))
    return m.group(0) if m else str(v).strip()


def is_structure(x):
    blob = ' '.join(str(x.get(k) or '') for k in ('category', 'name_zh', 'slug', 'component_id')).lower()
    return any(h in blob for h in STRUCT_HINT)


def naming_violations(text):
    return [why for pat, why in FORBIDDEN if pat.search(str(text))]


def has_variant_contract(x):
    """第 4–5 个变体必须声明可解释、可复用的状态轴。"""
    return all(str(x.get(k) or '').strip() for k in ('variant_axis', 'variant_value', 'variant_reason'))


def variant_contract_complete(members):
    axes = {str(x.get('variant_axis') or '').strip() for x in members}
    return all(has_variant_contract(x) for x in members) and len(axes) == 1


def family_limit(members, regular_max, hard_max):
    if len(members) <= regular_max:
        return regular_max, True
    contracted = variant_contract_complete(members)
    return (hard_max if contracted else regular_max), contracted


def load_packages(lib_dir):
    cat = os.path.join(lib_dir, 'component_catalog.json')
    if os.path.exists(cat):
        d = json.load(open(cat, encoding='utf-8'))
        if isinstance(d, list):
            return d
        for k in ('packages', 'components', 'items'):
            if isinstance(d.get(k), list):
                return d[k]
        return [v for v in d.values() if isinstance(v, dict)]
    root = os.path.join(lib_dir, 'component_packages')
    out = []
    for nm in (sorted(os.listdir(root)) if os.path.isdir(root) else []):
        m = os.path.join(root, nm, 'asset_manifest.json')
        if os.path.exists(m):
            out.append(json.load(open(m, encoding='utf-8')))
    return out


def size_clusters(members, tol):
    """族内按尺寸贪心聚类（相邻维差 <= tol 视为同簇）。"""
    ms = sorted(members, key=key_bounds)
    clusters = []
    for m in ms:
        for c in clusters:
            b0, b1 = key_bounds(c[0]), key_bounds(m)
            if len(b0) == len(b1) and all(abs(p - q) <= tol for p, q in zip(b0, b1)):
                c.append(m)
                break
        else:
            clusters.append([m])
    return clusters


def dist(a, b):
    ba, bb = key_bounds(a), key_bounds(b)
    if len(ba) != len(bb):
        return 9e9
    return max(abs(p - q) for p, q in zip(ba, bb))


def merge_to_max(clusters, maxn):
    """反复合并最相似的一对簇，直到簇数 <= maxn。"""
    merged = []
    while len(clusters) > maxn:
        best, bi, bj = None, -1, -1
        for i in range(len(clusters)):
            for j in range(i + 1, len(clusters)):
                d = dist(clusters[i][0], clusters[j][0])
                if best is None or d < best:
                    best, bi, bj = d, i, j
        merged.append(round(best, 4))
        clusters[bi] = clusters[bi] + clusters[bj]
        clusters.pop(bj)
    return clusters, merged


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('lib_dir')
    ap.add_argument('--write', action='store_true')
    ap.add_argument('--out', default=None)
    ap.add_argument('--max', type=int, default=3, help='无显式状态轴的常规族上限')
    ap.add_argument('--hard-max', type=int, default=5, help='带合法状态轴的绝对族上限')
    ap.add_argument('--component-limit', type=int, default=50, help='单房型唯一组件定义上限')
    ap.add_argument('--tol', type=float, default=0.10)
    a = ap.parse_args()

    pkgs = load_packages(a.lib_dir)
    if not pkgs:
        print('FAIL: 未找到组件包')
        return 2

    fams = collections.OrderedDict()
    for x in pkgs:
        fams.setdefault(family_of(x), []).append(x)

    name_v = [x for x in pkgs if naming_violations(name_of(x))]
    cid_v = [x for x in pkgs if naming_violations(cid(x))]
    axis_bad = [x for x in pkgs if str(x.get('front_axis') or '').strip() not in VALID_AXIS]
    rot_locked = [x for x in pkgs if tuple(x.get('allowed_rotations_y_deg') or []) == (0,)]

    print('库: %s' % a.lib_dir)
    print('包数 %d ｜ 族数 %d ｜ 常规上限 %d ｜ 绝对上限 %d ｜ 房型预算 %d ｜ 相似容差 %.3f m' % (
        len(pkgs), len(fams), a.max, a.hard_max, a.component_limit, a.tol))
    print()
    print('--- 违规 ---')
    print('命名违规  slug %d / component_id %d' % (len(name_v), len(cid_v)))
    print('front_axis 非枚举 %d ｜ allowed_rotations 全 [0] %d' % (len(axis_bad), len(rot_locked)))
    contract_missing = [(f, len(m)) for f, m in fams.items() if len(m) > a.max and not variant_contract_complete(m)]
    absolute_over = [(f, len(m)) for f, m in fams.items() if len(m) > a.hard_max]
    print('缺少变体契约（> %d）: %d 个 %s' % (a.max, len(contract_missing), contract_missing if contract_missing else ''))
    print('超过绝对上限（> %d）: %d 个 %s' % (a.hard_max, len(absolute_over), absolute_over if absolute_over else ''))
    print()

    total_before = 0
    total_after = 0
    plan_groups = []
    print('--- 族收敛 ---')
    print('%-22s %6s %6s %6s  %s' % ('族', '变体', '上限', '收敛后', '代表件'))
    for f, members in sorted(fams.items(), key=lambda kv: -len(kv[1])):
        before = len(members)
        total_before += before
        limit, contracted = family_limit(members, a.max, a.hard_max)
        cl = size_clusters(members, a.tol)
        merged_deltas = []
        if len(cl) > limit:
            cl, merged_deltas = merge_to_max(cl, limit)
        reps = [max(c, key=lambda x: len(x.get('objects') or [])) for c in cl]
        after = len(cl)
        total_after += after
        flag = '  << 缺变体契约' if before > a.max and not contracted else ('  << 超绝对上限' if before > a.hard_max else '')
        print('%-22s %6d %6d %6d  %s%s' % (f, before, limit, after, [name_of(r) for r in reps][:5], flag))
        plan_groups.append({
            'family': f,
            'variants_before': before,
            'variant_limit': limit,
            'variant_contract_complete': contracted,
            'variants_after': after,
            'merged_deltas_m': merged_deltas,
            'representatives': [{
                'component_id': cid(r), 'slug': name_of(r),
                'bounds_size_m': list(bounds_of(r)),
                'variant_axis': r.get('variant_axis'),
                'variant_value': r.get('variant_value'),
                'variant_reason': r.get('variant_reason'),
                'absorbed': [name_of(m) for m in c if m is not r],
            } for c, r in zip(cl, reps)],
        })

    component_budget_over = total_after > a.component_limit
    print()
    print('组件数: %d 变体 → 收敛后 %d 个组件（房型预算 %d，剩余 %d）' % (
        total_before, total_after, a.component_limit, a.component_limit - total_after))
    print()
    violations = name_v or cid_v or axis_bad or contract_missing or absolute_over or component_budget_over
    print('PLAN_COMPONENTS_' + ('OK' if not violations else 'VIOLATIONS'))

    if a.write:
        out = a.out or os.path.join(a.lib_dir, 'component_plan.json')
        json.dump({
            'schema': 'shellstorm2.battle.component_plan',
            'schema_version': 1,
            'source_library': a.lib_dir.replace('\\', '/'),
            'regular_max_variants_per_family': a.max,
            'hard_max_variants_per_family': a.hard_max,
            'component_budget': {
                'limit': a.component_limit,
                'planned': total_after,
                'remaining': a.component_limit - total_after,
            },
            'sim_tol_m': a.tol,
            'package_count': len(pkgs),
            'component_count': total_after,
            'families': plan_groups,
            'validation': {
                'naming_violation_count': len(name_v),
                'front_axis_non_enum_count': len(axis_bad),
                'rotation_locked_count': len(rot_locked),
                'variant_contract_missing_families': [f for f, _ in contract_missing],
                'absolute_over_limit_families': [f for f, _ in absolute_over],
                'component_budget_over': component_budget_over,
            },
        }, open(out, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
        print('已写出 %s' % out)

    return 1 if violations else 0


if __name__ == '__main__':
    sys.exit(main())
