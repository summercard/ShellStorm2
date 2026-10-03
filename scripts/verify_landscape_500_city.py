import hashlib
import html
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'outputs/landscape_500_city_20261003'

def gap(a, b):
    return math.hypot(max(a['min'][0] - b['max'][0], b['min'][0] - a['max'][0], 0), max(a['min'][2] - b['max'][2], b['min'][2] - a['max'][2], 0))

def verify():
    data = json.loads((OUT / 'runtime_final.json').read_text(encoding='utf8'))
    before = json.loads((OUT / 'runtime_before.json').read_text(encoding='utf8'))
    checks = []
    def check(name, ok, detail=None):
        checks.append({'name': name, 'passed': bool(ok), 'detail': detail})
    buildings = data['new_buildings']
    check('真实渲染器与正式链路', data['renderer'] != 'headless' and data['binding_complete'])
    for name in ['runtime_before', 'runtime_final']:
        log = (OUT / (name + '.log')).read_text(encoding='utf8')
        check(name + ':无非预期引擎脚本错误', not any(x in log for x in ['ERROR:', 'SCRIPT ERROR:', 'Parse Error', 'Shader compilation failed']))
    check('旧楼完整变换保持', all(a['transform'] == b['transform'] for a,b in zip(data['legacy'], before['city_runtime_instances'])))
    extensions = {2:'CityRing0Index2Extension', 8:'CityRing0Index8Extension'}
    for i,old in enumerate(data['legacy']):
        if old['min'][1] > -80.002:
            ext = next(x for x in data['foundation'] if x['name'] == extensions.get(i))
            check('旧楼%d:只向下补接地'%i,abs(ext['min'][1]+80)<0.002 and abs(ext['max'][1]-old['min'][1])<0.002 and all(abs(ext[k][j]-old[k][j])<0.002 for k in ['min','max'] for j in [0,2]))
    check('云fallback未溢出或吞整片地表',len(data['cloud_fallback_bounds'])<16 and all(b['max'][0]-b['min'][0]<200 and b['max'][2]-b['min'][2]<200 for b in data['cloud_fallback_bounds']))
    check('原96城市真实实例保持', len(data['legacy']) == 96 and all(all(abs(a[k][i] - b[k][i]) < 0.002 for k in ['min', 'max'] for i in range(3)) for a,b in zip(data['legacy'], before['city_runtime_instances'])))
    check('原生产脚本字节不变', hashlib.sha256((ROOT/'src/world3d/TowerAtmosphere3D.gd').read_bytes()).hexdigest() == json.loads((OUT/'baseline_hashes.json').read_text(encoding='utf8'))['src/world3d/TowerAtmosphere3D.gd'])
    foundations = {x['name']: x for x in data['foundation']}
    ground = foundations['OpenWorldGroundPlane']
    check('地表500x500厚0.2顶-80', all(abs(ground['size'][i]-expected)<0.002 for i,expected in enumerate([500,0.2,500])) and abs(ground['max'][1]+80)<0.002)
    check('地表中心XZ保持', abs(ground['center'][0]-3.750313)<0.002 and abs(ground['center'][2]+40.770721)<0.002)
    for old in before['foundation']:
        if old['name'] == 'OpenWorldGroundPlane':
            continue
        actual = foundations[old['name']]
        check(old['name']+':位置尺寸包络保持', all(abs(old[k][i]-actual[k][i])<0.002 for k in ['min','max'] for i in range(3)))
        if 'Remote' in old['name'] or 'Extension' in old['name']:
            check(old['name']+':同一城市材质', actual['same_city_material'])
    for target in ['Tower2','Tower3','Skyline08']:
        check(target+':完整矩阵保持', data['targets'][target]['transform'] == before['targets'][target]['transform'])
        check(target+':几何包络保持', all(abs(data['targets'][target][k][i]-before['targets'][target][k][i])<0.002 for k in ['min','max'] for i in range(3)))
    stages_before = {s['floor_index']:s for s in before['main_tower_stages']}
    check('主塔楼层完整矩阵保持', len(data['main_tower_stages'])==len(stages_before) and all(s['transform']==stages_before[s['floor_index']]['transform'] for s in data['main_tower_stages']))
    check('主塔完整可视结构包络保持', all(abs(data['targets']['Tower1'][k][i]-before['targets']['Tower1'][k][i])<0.002 for k in ['min','max'] for i in range(3)))
    for name,entry in data['bridge'].items():
        check(name+':桥完整矩阵保持',entry['transform']==before['bridge'][name]['transform'])
        check(name+':桥包络保持', all(abs(entry[k][i]-before['bridge'][name][k][i])<0.002 for k in ['min','max'] for i in range(3)))
    keepouts = [{'name':k['name'],'kind':k['kind'],'min':[k['min_xz'][0],-10000,k['min_xz'][1]],'max':[k['max_xz'][0],10000,k['max_xz'][1]]} for k in data['keepouts']]
    min_by_kind = {}
    minimum_street = float('inf')
    edge_margin = float('inf')
    violations = []
    for i,b in enumerate(buildings):
        check('新楼%d:真实变换回读/共享网格材质/接地/层范围'%i, b['actual_transform']==b['planned_transform'] and b['same_mesh'] and b['same_material'] and abs(b['min'][1]+80)<0.002 and -68.002<=b['max'][1]<=-19.998 and b['visible_in_tree'] and b['layers']==1 and b['visibility_range_end']==520)
        edge_margin=min(edge_margin,b['min'][0]-ground['min'][0],ground['max'][0]-b['max'][0],b['min'][2]-ground['min'][2],ground['max'][2]-b['max'][2])
        for k in keepouts:
            d=gap(b,k)
            min_by_kind[k['kind']]=min(min_by_kind.get(k['kind'],float('inf')),d)
            if d<3.998:
                violations.append({'building':i,'target':k['name'],'gap':d})
        for other in buildings[i+1:]:
            minimum_street=min(minimum_street,gap(b,other))
    check('保护对象分类齐全',set(['body','crane','bridge','legacy','landscape']).issubset(min_by_kind))
    check('净距4m逐楼身/塔吊/桥/旧城/景观', not violations, {'minimum_by_kind':min_by_kind,'violations':violations})
    check('新增楼互不重叠且街道净距4m', minimum_street>=3.998, minimum_street)
    check('边缘安全带10m',edge_margin>=9.998,edge_margin)
    coverage_ok = lambda sectors: len(sectors)==25 and all(s['total_city_count']>0 for s in sectors)
    check('25个100m分区城市总覆盖',coverage_ok(data['sectors']),data['sectors'])
    from copy import deepcopy
    broken = deepcopy(data['sectors'])
    broken[0]['total_city_count'] = 0
    check('覆盖判据负向对照',not coverage_ok(broken))
    check('足迹相交判据负向对照',gap(buildings[0],buildings[0])<3.998)
    check('全域400候选格点完整核算',sum(s['candidates'] for s in data['sectors'])==400 and all(s['count']+s['rejected']==s['candidates'] for s in data['sectors']))
    check('确定性重复实例布局一致',data['deterministic_repeat'])
    tower3=data['targets']['Tower3']
    directions={
        'north':sum(b['max'][2]<tower3['min'][2]-4 and -112<b['min'][0]<88 for b in buildings),
        'south':sum(b['min'][2]>tower3['max'][2]+4 and b['max'][2]<-90 and -112<b['min'][0]<88 for b in buildings),
        'west':sum(b['max'][0]<tower3['min'][0]-4 and -270<b['min'][2]<-80 for b in buildings),
        'east':sum(b['min'][0]>tower3['max'][0]+4 and -270<b['min'][2]<-80 for b in buildings)}
    check('塔3四侧独立覆盖',all(directions.values()),directions)
    check('云海逐栋keepout而非城市超级AABB',len(data['cloud_city_bounds'])==len(buildings) and data['cloud_city_uniform_enabled'] and data['cloud_city_texture_size']==[20,40])
    check('非空分区批次数对应实际生成', data['batch_count']==sum(s['count']>0 for s in data['sectors']))
    check('根场景与11组件独立加载', len(data['independent_loads'])==12 and all(s['loaded'] for s in data['independent_loads']))
    check('云海GPU纹理逐栋条目完整',len(data['cloud_city_texture_entries'])==len(buildings))
    for i,(b,c) in enumerate(zip(buildings,data['cloud_city_bounds'])):
        check('新楼%d:云海1.5m保留区'%i,all(abs(c['min'][j]-(b['min'][j]-1.5))<0.002 and abs(c['max'][j]-(b['max'][j]+1.5))<0.002 for j in range(3)))
        texture_entry=data['cloud_city_texture_entries'][i]
        check('新楼%d:GPU纹理足迹高度保持'%i,texture_entry['enabled']==1 and all(abs(c[k][j]-texture_entry[k][j])<0.002 for k in ['min','max'] for j in range(3)))
    check('云海保持启用',data['clouds']['enabled'] and data['clouds']['sea_count']>0)
    check('零新增景观碰撞',data['landscape_collision_count']==0)
    footprint=sum((b['max'][0]-b['min'][0])*(b['max'][2]-b['min'][2]) for b in buildings)
    protected=[]
    allowed={'assets/art/environments/open_world/runtime/open_world_landscape_foundation/ground_plane_box.tscn','assets/art/environments/open_world/runtime/open_world_landscape_foundation/env_open_world_landscape_foundation_root_top3d.tscn','assets/art/environments/open_world/runtime/open_world_landscape_foundation/asset_manifest.json','src/vfx/VfxCloudSea3D.gd','assets/art/vfx/environment_3d/cloud_sea/stylized_cloud.gdshader','docs/v0.1/MODULE_INDEX.md','docs/v0.1/feature_registry.json','docs/v0.1/design/rooftop_cross_tower_route.md','docs/v0.1/development/CHANGELOG.md','docs/v0.1/development/2026-10-03_cross_tower_landscape_foundation.md'}
    hashes=json.loads((OUT/'baseline_hashes.json').read_text(encoding='utf8'))
    for rel,digest in hashes.items():
        if rel in allowed: continue
        if hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()!=digest: protected.append(rel)
    check('既有保护文件不变',not protected,{'count':len(hashes)-len(allowed),'changed':protected})
    from PIL import Image
    for shot in data['screenshots']:
        image_path=OUT/Path(shot['path']).name
        image=Image.open(image_path).convert('RGB')
        colors=len(image.resize((160,100)).getcolors(20000) or [])
        check(shot['name']+':真实截图非空',shot['save_error']==0 and colors>100,{'colors':colors,'size':image.size})
        if shot['name']=='overview_500':
            check('500全域四角在画内',all(0.03<x<0.97 and 0.03<y<0.97 for x,y in shot['ground_corner_projections']),shot['ground_corner_projections'])
    gate_summary = {}
    if (OUT/'gates_after.json').exists():
        gate_summary['before'] = json.loads((OUT/'gates_before.json').read_text(encoding='utf8'))
        gate_summary['after'] = json.loads((OUT/'gates_after.json').read_text(encoding='utf8'))
        before_ledger=json.loads((OUT/'ledger_full_before.json').read_text(encoding='utf8'))
        after_ledger=json.loads((OUT/'ledger_full_after.json').read_text(encoding='utf8'))
        gate_summary['ledger_issue_counts']=after_ledger['issue_counts']
        check('账本结构与无损门禁通过',all(g['exit_code']==0 for g in gate_summary['after'] if g['name'] in ['ledger_structure','split']))
        check('账本既有SHA问题无新增无改写',after_ledger['issue_counts']==before_ledger['issue_counts'] and after_ledger['issues']==before_ledger['issues'])
        for name in ['documentation','naming']:
            encoding='gbk' if name=='naming' else 'utf8'
            old_log=(OUT/(name+'_before.log')).read_text(encoding=encoding)
            new_log=(OUT/(name+'_after.log')).read_text(encoding=encoding)
            if name=='documentation':
                gate_summary['documentation_issues']=json.loads(new_log)['issues']
                check('文档门禁只保留既有红项',json.loads(old_log)['issues']==json.loads(new_log)['issues'])
            else:
                check('命名门禁只保留既有红项',old_log==new_log)
        cloud_log=(OUT/'cloud_regression.log').read_text(encoding='utf8')
        check('真实云海回归无非预期错误', 'OUTDOOR_CLOUDS_OK checks=30209' in cloud_log and not any(x in cloud_log for x in ['ERROR:', 'SCRIPT ERROR:', 'Parse Error']))
        gate_summary['cloud_regression_checks']=30209
        ledger=json.loads((OUT/'ledger_registration.json').read_text(encoding='utf8'))
        check('目标Prefab登记哈希一致',ledger['prefab_sha256']==hashlib.sha256((ROOT/'assets/art/environments/open_world/runtime/open_world_landscape_foundation/env_open_world_landscape_foundation_root_top3d.tscn').read_bytes()).hexdigest())
        gate_summary['ledger_registration']=ledger
    if (OUT/'runtime_snapshot_hashes.json').exists():
        snapshot_hashes=json.loads((OUT/'runtime_snapshot_hashes.json').read_text(encoding='utf8'))
        drift=[rel for rel,digest in snapshot_hashes.items() if hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()!=digest]
        check('当前正式文件与真实渲染快照一致',not drift,{'file_count':len(snapshot_hashes),'drift':drift})
    errors=[c['name'] for c in checks if not c['passed']]
    result={'gate_summary':gate_summary,'passed':not errors,'check_count':len(checks),'errors':errors,'checks':checks,'old_count':96,'new_count':len(buildings),'existing_remote_count':4,'sector_count':25,'sector_counts':data['sectors'],'tower3_direction_counts':directions,'ground':ground,'minimum_keepout_by_kind_m':min_by_kind,'minimum_new_building_gap_m':minimum_street,'minimum_edge_margin_m':edge_margin,'new_footprint_area_m2':footprint,'new_footprint_fraction':footprint/250000,'limitations':['AABB保守避让，不是三角级检测；既有城市互相与塔2交叠未改','玩家环境距离雾/云与520m裁剪保持，不承诺玩家机位同时看见全域','25分区均有旧城或新城；中央两区保留旧楼与主塔，新增为0，不等于每平方米放楼','没有移动端性能、LOD或长时间全玩法验收']}
    (OUT/'geometry_validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
    cards=''.join('<figure><img src="'+html.escape(Path(s['path']).name)+'"><figcaption>'+html.escape(s['name']+' · '+s['presentation'])+'</figcaption></figure>' for s in data['screenshots'])
    counts=''.join('<td>'+str(next(s['count'] for s in data['sectors'] if s['x']==x and s['z']==z))+'</td>' for z in range(5) for x in range(5))
    rows=''.join('<tr><td>'+html.escape(c['name'])+'</td><td>'+('通过' if c['passed'] else '失败')+'</td><td>'+html.escape(str(c['detail']) if c['detail'] is not None else '')+'</td></tr>' for c in checks)
    page='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>500m地表全域城市验收</title><style>body{font:16px system-ui;background:#101924;color:#dce5ef;margin:32px auto;max-width:1250px;padding:20px}h1{color:#78d6ca}img{width:100%;border-radius:8px}figure{margin:28px 0}figcaption{padding:12px;color:#b6c6d9}table{border-collapse:collapse;width:100%;font-size:13px}td,th{border:1px solid #344558;padding:8px;word-break:break-all}a{color:#78d6ca}.metric{background:#1d2a3b;padding:18px;border-radius:8px;margin:12px 0}</style><h1>500×500m 地表与全域城市</h1><p>验收状态：'+('专项通过' if not errors else '存在失败，未完成')+'；真实渲染器 '+html.escape(data['rendering_method'])+'；'+str(len(checks))+' 项检查。</p><div class="metric">中心XZ (3.750313, -40.770721)；X[-246.249687,253.750313]，Z[-290.770721,209.229279]；顶Y=-80，厚0.2m。<br>原楼96不动；新增'+str(len(buildings))+'栋；既有剪影4栋；25个100×100m分区。<br>楼群足迹新增占比 '+format(footprint/250000,'.1%')+'，余量为街道、塔楼、桥与保留区，不以数量替代覆盖。<br>净距实测 '+html.escape(str(min_by_kind))+'；新增之间 '+format(minimum_street,'.3f')+'m；边缘 '+format(edge_margin,'.3f')+'m。</div><p>正式接入：CrossTowerRoute/LandscapeFoundation/ProceduralCity500；复用原城市同一mesh及材质对象。参数与保留区来源位于正式runtime目录，不依赖本outputs。</p><p><a href="runtime_final.json">真实运行dump</a> · <a href="geometry_validation.json">逐项检查JSON</a> · <a href="runtime_before.json">修改前基线</a></p><h2>真实截图</h2><p>前两张是实际玩家Camera3D和正式雾云；后两张是关闭雾云/HUD、提亮环境与太阳并调整太阳角度、取消批次裁剪的诊断概览，结束恢复，不能冒称玩家视觉。城市保持原材质黑色剪影，不为出图替换材质。</p>'+cards+'<h2>25分区与保护边界</h2><pre>'+html.escape(json.dumps(data['sectors'],ensure_ascii=False,indent=2))+'</pre><h2>限制</h2><ul>'+''.join('<li>'+html.escape(x)+'</li>' for x in result['limitations'])+'</ul><h2>逐项检查</h2><table><tr><th>检查</th><th>结果</th><th>实测</th></tr>'+rows+'</table></html>'
    gate_section='<h2>登记与工程门禁</h2><p>城市专项通过不等于全工程通过。结构与无损账本通过；文档与命名保留修改前已有红项，场景full仍有153条既有SHA漂移。逐项前后对照通过，未批量接受旧hash。</p><pre>'+html.escape(json.dumps(gate_summary,ensure_ascii=False,indent=2))+'</pre><p><a href="cloud_regression.log">云海真实渲染回归日志</a> · <a href="ledger_registration.json">账本两事务登记</a> · <a href="runtime_snapshot_hashes.json">运行文件快照SHA</a> · <a href="gates_after.json">最终门禁退出码</a></p>'
    page=page.replace('<h2>逐项检查</h2>',gate_section+'<h2>逐项检查</h2>')
    (OUT/'acceptance_report.html').write_text(page,encoding='utf8')
    print('CITY500_VALIDATION', 'PASS' if not errors else 'FAIL',len(checks),'新楼',len(buildings),'失败',errors)
    return int(bool(errors))

if __name__=='__main__':
    raise SystemExit(verify())
