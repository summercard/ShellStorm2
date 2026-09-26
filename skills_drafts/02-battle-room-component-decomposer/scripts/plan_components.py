#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""组件拆分判断（族上限版）：包络聚类 + 族内变体上限 3 的自动收敛。

用法:
    python plan_components.py <component_library_dir> [--write] [--out PATH] [--max 3] [--tol 0.06]

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
    """族名 = slug 去方位词/数字/尾部单字母序号后的语义核心。"""
    out = []
    for t in re.split(r'[_-]', str(slug).lower()):
        if not t or t in AXIS_WORDS or NUM_RE.match(t):
            continue
        out.append(t)
    while len(out) > 1 and SINGLE_ALPHA.match(out[-1]):
        out.pop()
    return '_'.join(out) or 'unknown'


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
    ap.add_argument('--max', type=int, default=3)
    ap.add_argument('--tol', type=float, default=0.10)
    a = ap.parse_args()

    pkgs = load_packages(a.lib_dir)
    if not pkgs:
        print('FAIL: 未找到组件包')
        return 2

    fams = collections.OrderedDict()
    for x in pkgs:
        fams.setdefault(family(name_of(x)), []).append(x)

    name_v = [x for x in pkgs if naming_violations(name_of(x))]
    cid_v = [x for x in pkgs if naming_violations(cid(x))]
    axis_bad = [x for x in pkgs if str(x.get('front_axis') or '').strip() not in VALID_AXIS]
    rot_locked = [x for x in pkgs if tuple(x.get('allowed_rotations_y_deg') or []) == (0,)]

    print('库: %s' % a.lib_dir)
    print('包数 %d ｜ 族数 %d ｜ 族上限 %d ｜ 相似容差 %.3f m' % (len(pkgs), len(fams), a.max, a.tol))
    print()
    print('--- 违规 ---')
    print('命名违规  slug %d / component_id %d' % (len(name_v), len(cid_v)))
    print('front_axis 非枚举 %d ｜ allowed_rotations 全 [0] %d' % (len(axis_bad), len(rot_locked)))
    over = [(f, len(m)) for f, m in fams.items() if len(m) > a.max]
    print('超限族（变体 > %d）: %d 个 %s' % (a.max, len(over), over if over else ''))
    print()

    total_before = 0
    total_after = 0
    plan_groups = []
    print('--- 族收敛 ---')
    print('%-22s %6s %6s  %s' % ('族', '变体', '收敛后', '代表件'))
    for f, members in sorted(fams.items(), key=lambda kv: -len(kv[1])):
        before = len(members)
        total_before += before
        cl = size_clusters(members, a.tol)
        merged_deltas = []
        if len(cl) > a.max:
            cl, merged_deltas = merge_to_max(cl, a.max)
        reps = [max(c, key=lambda x: len(x.get('objects') or [])) for c in cl]
        after = len(cl)
        total_after += after
        flag = '  << 超限' if before > a.max else ''
        print('%-22s %6d %6d  %s%s' % (f, before, after, [name_of(r) for r in reps][:4], flag))
        plan_groups.append({
            'family': f,
            'variants_before': before,
            'variants_after': after,
            'merged_deltas_m': merged_deltas,
            'representatives': [{
                'component_id': cid(r), 'slug': name_of(r),
                'bounds_size_m': list(bounds_of(r)),
                'absorbed': [name_of(m) for m in c if m is not r],
            } for c, r in zip(cl, reps)],
        })

    print()
    print('组件数: %d 变体 → 收敛后 %d 个组件（族上限 %d）' % (total_before, total_after, a.max))
    print()
    print('PLAN_COMPONENTS_' + ('OK' if not (name_v or cid_v or axis_bad or over) else 'VIOLATIONS'))

    if a.write:
        out = a.out or os.path.join(a.lib_dir, 'component_plan.json')
        json.dump({
            'schema': 'shellstorm2.battle.component_plan',
            'schema_version': 1,
            'source_library': a.lib_dir.replace('\\', '/'),
            'max_variants_per_family': a.max,
            'sim_tol_m': a.tol,
            'package_count': len(pkgs),
            'component_count': total_after,
            'families': plan_groups,
            'validation': {
                'naming_violation_count': len(name_v),
                'front_axis_non_enum_count': len(axis_bad),
                'rotation_locked_count': len(rot_locked),
                'over_limit_families': [f for f, m in fams.items() if len(m) > a.max],
            },
        }, open(out, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
        print('已写出 %s' % out)

    return 1 if (name_v or cid_v or axis_bad or over) else 0


if __name__ == '__main__':
    sys.exit(main())
