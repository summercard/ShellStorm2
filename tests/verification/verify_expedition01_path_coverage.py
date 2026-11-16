#!/usr/bin/env python3
"""对正式几何探针输出做0.5m通行网格路径覆盖验收；断路不记作零空档。"""
import argparse
from collections import deque
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import workspace_paths as wp


def route_for(row):
    cells = {tuple(cell) for cell in row['walkable']}
    width, depth = row['dimensions']
    def position(cell):
        return (-width * .5 + cell[0] * .5 + .25, -depth * .5 + cell[1] * .5 + .25)
    if not cells:
        return []
    start, finish = [min(cells, key=lambda cell: math.dist(position(cell), landing['player'])) for landing in row['landings']]
    if any(math.dist(position(cell), landing['player']) > .75 for cell, landing in zip((start, finish), row['landings'])):
        return []
    edges = None
    if row.get('graph_method') == 'physical_capsule_swept_v1':
        edges = set()
        for x, z, nx, nz in row['walkable_edges']:
            edges.add(((x, z), (nx, nz)))
            edges.add(((nx, nz), (x, z)))
    queue, parent = deque([start]), {start: None}
    while queue:
        current = queue.popleft()
        if current == finish:
            break
        for dx, dz in ((1,0),(-1,0),(0,1),(0,-1)):
            candidate = (current[0] + dx, current[1] + dz)
            if candidate in cells and candidate not in parent and (edges is None or (current, candidate) in edges):
                parent[candidate] = current
                queue.append(candidate)
    if finish not in parent:
        return []
    route = []
    while finish is not None:
        route.append(position(finish))
        finish = parent[finish]
    return route[::-1]


def metrics(route, points):
    if not route or not points:
        return None
    longest = current = farthest = 0.0
    for point in route:
        distance = min(math.dist(point, enemy) for enemy in points)
        current = current + .5 if distance > 6.0 else 0.0
        longest, farthest = max(longest, current), max(farthest, distance)
    return {'longest_uncovered_6m_m': round(longest, 3), 'farthest_enemy_m': round(farthest, 3)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--current', type=Path, required=True)
    parser.add_argument('--output', default='sessions/2026-11-16_exp01_combat/path_coverage.json')
    args = parser.parse_args()
    old = {row['id']: row for row in json.loads(args.baseline.read_text(encoding='utf-8'))['rooms']}
    data = json.loads(args.current.read_text(encoding='utf-8'))
    failures, results = list(data.get('failures', [])), []
    expected = {'room_01': 8, 'room_02': 10, 'room_05': 39, 'room_07': 20, 'room_08': 25}
    if {row['id'] for row in data['rooms']} != set(expected):
        failures.append('五房验收集合不完整')
    for row in data['rooms']:
        route = route_for(row)
        result = {'room':row['id'], 'route_length_m':round(max(0, len(route)-1)*.5, 3), 'connected':bool(route), 'entries':row['entries'], 'boxes':row['boxes'], 'ports':[]}
        if not route:
            failures.append(row['id'] + ':真实家具碰撞通行网格A/B不连通，路径覆盖未通过')
        if row['entries'] != expected[row['id']]:
            failures.append(row['id'] + ':最大编译数量阈值变化')
        for box in row['boxes']:
            if box['capacity_no_player'] < box['need']:
                failures.append(row['id'] + ':盒容量不足:' + str(box['index']))
        if [landing['port'] for landing in row['landings']] != ['A', 'B']:
            failures.append(row['id'] + ':缺少A/B入口落点')
        result['graph_method'] = row.get('graph_method', 'legacy_aabb')
        result['production_floor_rejected_count'] = len(row.get('production_floor_rejected', []))
        baseline_row = old[row['id']]
        if len(row['boxes']) != len(baseline_row['boxes']):
            failures.append(row['id'] + ':盒数量漂移')
        for box, previous_box in zip(row['boxes'], baseline_row['boxes']):
            if box['capacity_no_player'] < previous_box['capacity_no_player']:
                failures.append(row['id'] + ':盒容量低于修前:' + str(box['index']))
        if row.get('graph_method') == 'physical_capsule_swept_v1':
            # 固定历史落点投影到同一修后物理路线，不把旧断路当作零空档基线。
            old_route = route
        else:
            old_route = route_for(baseline_row)
        result['baseline_route_basis'] = '同一修后物理路线上的固定历史敌点' if row.get('graph_method') == 'physical_capsule_swept_v1' else '历史网格路线'
        for landing, baseline_landing in zip(row['landings'], old[row['id']]['landings']):
            actual = metrics(route, landing['points'])
            previous = metrics(old_route, baseline_landing['points'])
            result['ports'].append({'port':landing['port'], 'selected':len(landing['points']), 'preplaced_ok':landing['ok'], 'baseline':previous, 'current':actual})
            if not landing['ok'] or len(landing['points']) != row['entries']:
                failures.append(row['id'] + ':' + landing['port'] + ':预摆容量不足')
            if actual and previous and actual['longest_uncovered_6m_m'] > previous['longest_uncovered_6m_m']:
                failures.append(row['id'] + ':' + landing['port'] + ':路径空档比原先增长')
        results.append(result)
        print('EXP01_PATH ' + json.dumps(result, ensure_ascii=False))
    output = wp.work_path(args.output)
    output.write_text(json.dumps({'seed':data['seed'], 'rooms':results, 'failures':failures, 'exit_code':int(bool(failures)), 'method':'0.5m四邻接BFS；physical_capsule_swept_v1使用半径0.35m/高度1.8m真实胶囊、地面支撑及相邻边扫掠；低台阶差<=0.2m。物理图绕过生产保守可达裁剪但单列其拒绝点；固定历史敌点与当前敌点在同一修后路线比较>6m最长连续段，不代签视线/AI'}, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print('EXP01_PATH_DONE failures=' + str(failures) + ' output=' + str(output))
    return int(bool(failures))


if __name__ == '__main__':
    raise SystemExit(main())
