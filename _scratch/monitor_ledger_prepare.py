from pathlib import Path
import json,sys,hashlib
import openpyxl
R=Path.cwd();D=R/'_scratch/monitor_ledger';D.mkdir(exist_ok=True);B=R/'assets/art/enemies/bosses/enm_boss_monitor002';sys.path.insert(0,str(R/'scripts'))
from ledger_registry import LedgerIndex
ix=LedgerIndex.load(R);p=ix.path_for_category('敌人');w=openpyxl.load_workbook(p,read_only=True);row=next(i for i,r in enumerate(w['资产主表'].values,1) if r[0]=='ENM-BOSS-MONITOR002-3D')
prefix=B.relative_to(R).as_posix();prefab=prefix+'/runtime/enm_boss_monitor002/enm_boss_monitor002_root_top3d.tscn';glb=prefix+'/components/enm_boss_monitor002/enm_boss_monitor002_visual_top3d.glb';dual=prefix+'/source/enm_boss_monitor002_model_v031.blend; '+prefix+'/source/enm_boss_monitor002_animation_v031.blend'
note='v031正式接入：16源剪辑/64骨/十二态/四技能/三阶段；根驱动弹簧甩臂、双螺旋坐地、黄色单帧闪形及接地电流；478项专项及真实渲染10关键帧通过；Enemy3D拥有碰撞/AI/伤害；远征01 Boss房调用boss_monitor002。'
master={f'K{row}':'active',f'M{row}':'v031',f'O{row}':prefab,f'T{row}':hashlib.sha256((R/prefab).read_bytes()).hexdigest(),f'I{row}':'12态；16剪辑：idle move melee_keyboard melee_cable heavy_spin_slam special四段 hurt stun三段 turn_left/right dead',f'P{row}':dual+'；SKEL-MONITOR002-005',f'J{row}':'远征01 Boss房及显式内容ID调用',f'V{row}':'2026-10-06',f'Y{row}':note}
states={'dormant':'idle','idle':'idle','patrol':'move','alert':'idle','chase':'move / turn_left/right','search':'move','return':'move','telegraph':'技能剪辑前摇','attack':'技能剪辑生效段 / special_channel','recovery':'技能剪辑恢复段 / special_recover','stagger':'hurt / stun_enter→stun_loop→stun_exit','dead':'dead'}
st={};sr=w['敌人动画与状态'].max_row+1
for i,(state,clip) in enumerate(states.items(),sr):
 vals=['ENM-BOSS-MONITOR002-3D',state,'显示器Boss002',clip,dual,'idle/move/通电/坐地循环；其他单次','键盘/线梢/屏幕挂点；纯色块赛博VFX','Blender采样；Enemy3D技能策略',note]
 st.update({f'{openpyxl.utils.get_column_letter(j)}{i}':v for j,v in enumerate(vals,1)})
pr=w['3D-敌人'].max_row+1
vals=['ENM-BOSS-MONITOR002-3D','MONITOR.EXE 显示器',prefab,glb,dual,'16剪辑；四技能；三阶段；双母版同64骨架','src/enemy3d/Enemy3D.gd; src/enemy3d/MonitorBossCombat.gd; src/enemy3d/MonitorBossPresentation.gd','视觉关闭；玩法开启','外部脚本Enemy3D','CylinderShape3D，沿用Boss基线1.92/2.30m','18684三角形；64骨；站立约4m；根倍率1.05','底座接地；Blender+Y / Godot-Z；Prefab根1','远征01 f00_boss；boss_monitor002','active','v031',note]
pref={f'{openpyxl.utils.get_column_letter(j)}{pr}':v for j,v in enumerate(vals,1)}
logrow=w['域变更日志'].max_row+1
logs={f'{c}{logrow}':v for c,v in zip('ABCDE',['v031','2026-10-06','Codex','ENM-BOSS-MONITOR002-3D',note])}
jobs=[{'path':str(p),'sheets':{'资产主表':{f'K{row}':'exported_pending_godot_validation'},'域变更日志':{f'{c}{logrow}':v for c,v in zip('ABCDE',['v031/S2','2026-10-06','Codex','ENM-BOSS-MONITOR002-3D','双母版签名比对、纯视觉GLB与骨姿态采样导出；中转enm_boss_monitor002_transfer_ledger.json'])}}},
 {'path':str(p),'sheets':{'资产主表':{f'K{row}':'validated'},'域变更日志':{f'{c}{logrow+1}':v for c,v in zip('ABCDE',['v031/S3','2026-10-06','Codex','ENM-BOSS-MONITOR002-3D','独立PackedScene加载，根1，无碰撞，64骨；骨与变形网格边界比对通过'])}}},
 {'path':str(p),'sheets':{'资产主表':master,'敌人动画与状态':st,'3D-敌人':pref,'域变更日志':{f'{c}{logrow+2}':v for c,v in zip('ABCDE',['v031/S4-S5','2026-10-06','Codex','ENM-BOSS-MONITOR002-3D',note])}}}]
cp=R/'docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx';cw=openpyxl.load_workbook(cp,read_only=True);cr=cw['怪物与Boss'].max_row+1
vals=['boss_monitor002','MONITOR.EXE 显示器','boss',5200,1.204,24,6.0,0.65,'键盘24 / 数据线20 / 旋转砸地36 / 接地电流每0.8s12；HP66%/33%三阶段','远征01 f00_boss；显式内容ID调用','Enemy3D Boss结算与既有房间奖励','用户动作要求；技能设计r1','active','BossContentCatalog / MonitorBossCombat；Boss002技能设计分页','16 Blender剪辑，十二态；伤害8%韧性击晕4.8s；通电暴击可打断；单帧黄色闪形；独立资产ENM-BOSS-MONITOR002-3D']
content={f'{openpyxl.utils.get_column_letter(j)}{cr}':v for j,v in enumerate(vals,1)}
detail={'A2':'Boss002 显示器技能设计','A4':'内容ID','B4':'boss_monitor002','F4':'生命','G4':5200,'A5':'AssetID','B5':'ENM-BOSS-MONITOR002-3D','F5':'移动m/s','G5':1.204}
table=[['技能ID','名称','动作','前摇秒','生效秒','总时长秒','范围与伤害','打断与特效'],
 ['monitor_keyboard','键盘拍地','melee_keyboard',1.066667,1.066667,1.8,'前方3.2m，半径1.65m；24','单次命中；蓝/玫红；黄闪1帧'],
 ['monitor_cable','数据线甩击','melee_cable',0.8,'0.8–0.967',2.0,'160°弧，半径6m；20','螺旋前摇；平滑弧带；每目标1次'],
 ['monitor_spin_slam','旋转砸地','heavy_spin_slam',2.133333,2.133333,3.2,'前方1.4m，半径5.2m；36','3圈屏幕旋转；后仰停顿；黄闪1帧'],
 ['monitor_ground_current','接地电流','special四段',1.8,'每0.8秒脉冲','5.1 / 5.9 / 6.7','线尖接地点半径7m；每次12','通电2.4/3.2/4s；暴击可打断；冷却10s']]
for i,values in enumerate(table,8):detail.update({f'{openpyxl.utils.get_column_letter(j)}{i}':v for j,v in enumerate(values,1)})
for i,values in enumerate([['阶段','HP阈值','技能序列'],[1,'>66%','键盘、数据线、键盘、重击'],[2,'≤66%','数据线、插线、键盘、重击'],[3,'≤33%','重击、插线、数据线、重击、插线']],15):detail.update({f'{openpyxl.utils.get_column_letter(j)}{i}':v for j,v in enumerate(values,1)})
detail.update({'A20':'状态ID','B20':'表现动作','G20':'规则'})
for i,(state,clip) in enumerate(states.items(),21):detail.update({f'A{i}':state,f'B{i}':clip,f'G{i}':'韧性8%：坐下1.4s、坐地2.4s、起身1s' if state=='stagger' else '死亡2s后回收；根不压扁' if state=='dead' else 'Enemy3D状态与真实进度单向采样'})
detail.update({'A34':'规则','B34':'同层且无遮挡；命中不重复；坐地再受击不重播；读档取消危险技能','A36':'设计主源','B36':'docs/v0.1/design/Boss002显示器技能设计.md','A37':'实现源','B37':'src/enemy3d/MonitorBossCombat.gd'})
jobs.append({'path':str(cp),'sheets':{'怪物与Boss':content,'Boss002技能设计':detail},'new_sheets':['Boss002技能设计']})
pp=B/'source/boss002_production_ledger.xlsx';pw=openpyxl.load_workbook(pp,read_only=True);s=pw.active;changes={'B4':'v031 正式资产/十二态/四技能/三阶段'}
for rowvals in s:
 r=rowvals[0].row;label=rowvals[0].value
 if label=='当前源版本':changes.update({f'B{r}':'v031',f'C{r}':dual})
 if label=='绑定验证':changes.update({f'B{r}':'previews/runtime/flow_report.json',f'C{r}':note})
 if label=='面数统计':changes[f'C{r}']='source/rig_contract_v031.json'
jobs.append({'path':str(pp),'sheets':{s.title:changes}})
(D/'changes.json').write_text(json.dumps(jobs,ensure_ascii=False),encoding='utf-8')
# Snapshot only the intended asset before sparse patching; do not accept other baseline drift.
import shutil
shutil.copy2(R/'assets/registry/ledger_split_baseline.json',D/'baseline_before.json')
print('Prepared 3 stage transitions and three targeted workbook edits')
