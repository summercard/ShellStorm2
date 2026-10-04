from pathlib import Path
import json, statistics, html, subprocess, hashlib
root=Path(__file__).resolve().parents[1]
out=root/'outputs'
names=['stutter_recheck_20261004','stutter_bridge_recheck_20261004','stutter_bridge_720_recheck_20261004']
data=[json.loads((out/(n+'.json')).read_text(encoding='utf-8')) for n in names]
labels={'baseline_a':'正常 A','baseline_b':'正常 B','periodic_save_suppressed_a':'停周期保存／开云 A','periodic_save_suppressed_b':'停周期保存／开云 B','no_cloud':'保留保存／关云','both_suppressed':'停周期保存／关云 A','both_suppressed_repeat':'停周期保存／关云 B'}
tables=[]
for d,title in zip(data,['720p 楼顶：当前存档副本与画质配置','1440p 吊桥：云海交错对照','720p 吊桥：云海交错对照']):
    lines=['| 阶段 | 帧数 | P95 ms | 最大 ms | >50ms帧 | GPU中位 ms |','|---|---:|---:|---:|---:|---:|']
    for p in d['phases']:
        g=statistics.median(s['gpu_ms'] for s in d['samples'] if s['phase']==p['name'])
        lines.append(f"| {labels[p['name']]} | {p['frames']} | {p['p95_ms']:.3f} | {p['max_ms']:.3f} | {p['over50']} | {g:.3f} |")
    tables.append('### '+title+'\n\n'+'\n'.join(lines))
parts=json.loads((out/'stutter_save_parts_20261004.json').read_text(encoding='utf-8'))
cost=[]
for group in parts:
    cost.append(f"- {group['source']}：20次完整保存中位 {statistics.median(r['full_flush_ms'] for r in group['measurements']):.3f} ms，最大 {max(r['full_flush_ms'] for r in group['measurements']):.3f} ms。")
text='''# 楼顶与吊桥间歇卡顿复查（2026-10-04）

FeatureID：TIME-DAYNIGHT / SAVE-PROFILE / WORLD-BLOCKS / VFX-POOL。工程0.1.0，Git基线2fab729d。本次为诊断，不实施正式性能修复。
设计依据：时间日夜与画质设计、基地经济与存档结算设计、室外云海设计。

## 结论：应分开处理两类问题

1. **已确认：同步存档会占用主线程，但旧报告的百毫秒峰值本轮未复现。** 每10秒执行一次完整档案读写校验；当前17KB存档副本直接保存约12～13ms。楼顶实际三次周期保存对应29.746、22.684、18.173ms帧。停保存两段最大约17ms。另有正常A开头37.890/46.958ms两帧不对应保存，来源未定位。
2. **已确认：吊桥存在由云海渲染主导的位置相关掉帧。** 1440p停保存仍稳定复现慢区，两轮开云P95约65ms，关云均约16.8ms。GPU耗时随之大降。这类慢帧不需要周期保存就会发生。
3. **未确认：哪一项最近两天的改动造成了用户首次感受到的间歇卡顿。** 保存主链这两天没有代码差异，不能把旧保存问题直接称为新回归。当前环境和存档无法重现旧报告300ms级停顿，不能据本轮结果伪造单一根因或宣布修复。

## 本轮实测

RTX4060Ti，Godot4.6.3 Forward+，VSync关闭，60FPS限速。三次真实渲染进程分别完成6、4、4阶段；每阶段12秒，剔除首秒。另有一次headless仅拆分存档CPU/文件耗时，不用于图形结论。全部进程退出0，原始日志无ERROR/SCRIPT ERROR；有既有GLB UID警告。

用户原游戏与编辑器保持运行，没有强制关闭。独立进程启动前隔离APPDATA，复制当前base_save、画质和调参文件；只写副本。test_mode关闭行动检查点，角色沿固定路线平移，不复刻真实输入/物理和完整续档场景。楼顶y=0.05、房间start、100F；三轮均8区块/157建筑、实例变化0、节点装卸事件0。完整样本、阶段状态、GPU时间在JSON中。

'''+ '\n\n'.join(tables)+'''

帧时间包括60FPS限速；不能由16.67ms推导无上限GPU性能。GPU计时为引擎测量，有帧延迟，使用阶段统计而非与单帧CPU时间相加。1440p是提高分辨率的压力对照；用户当前进程启动参数是1280×720，不能拿1440p结果直接代表其实际窗口。

## 保存开销究竟在哪里

'''+ '\n'.join(cost)+'''

当前档案约17KB；旧报告档案约9KB。当前档案各独立操作中位：生成快照约0.006ms、建封套约1.95ms、单次校验约1.1ms、原子写入约1.09ms、单独读取解析约4.07ms、unpack校验约1.26ms；读取磁盘revision约2.83ms。各项是独立微测量，缓存/路径不同，不能机械相加还原一次调用。原子写入包含JSON stringify、flush、备份及rename，不能称为裸磁盘时延。

代码在读取旧revision时，load_dictionary的validator调用一次unpack，随后_read_disk_revision又unpack同一字典；保存后回读也重复两次。加上新封套一次，共通常5次canonical checksum。重复解析/递归校验与同步文件操作都在游戏主线程。单纯把问题归结为硬盘慢不准确。

旧报告5次直接保存135～259ms在本轮没有复现；甚至旧报告同一份存档副本现在只需约8ms。其波动不能由数据大小解释。系统当时负载、调试运行环境、文件系统拦截等只是待证假设，本次没有ETW/原进程调用栈证据，不能指认杀毒软件或驱动。

## 最近两天的改动核对

- GameTimeManager的10秒周期机制最近一次改动在2026-08-20（64b3dfbd9）；BaseManager最近在9月29日改动。以10月1日晚本地历史基线比较，GameTimeManager、BaseManager、BaseData、ProfileSaveService、AtomicJsonStore均无差异。
- 10月3日cc6b7265增加逐栋程序城市云避让；10月4日04a3b7c0增加候选缓存；2ea115fe改为三主塔避让。**当前实测main_towers_only=true，fallback_count=3，程序楼群查询关闭**。旧吊桥报告中710边界/10兜底区域的工作负载已过期。
- 当前云海仍在完整输出分辨率进行高档96步视线积分，以及密度相关光照/梯度查询。主塔避让缩减并不等于云海像素计算消失。当前视角对照确认云海代价，但尚未用完整旧版本、同存档、同路线做历史A/B，因此不能声称某个提交已被锁定为回归起点。
- 最近的交互圆点有每帧provider遍历，属于潜在CPU优化对象；本轮没有把它定位成周期百毫秒停顿源。怪物资产变化也没有在本楼顶测试中建立因果证据。
- 8个手摆区块只组织常驻建筑。本轮没有出现按距离重新加载建筑或房间流送增量，不应改成另一种“静态加载”来修本问题。

## 处理方法与优先级

### A. 修周期小顿：优化保存链，不关闭保存

先让一次读盘得到“已验证封套+unpacked结果”，供revision检查和回读确认复用，去掉同一份数据重复unpack/checksum；仍对每次实际读出的候选做完整校验，并保留bak回退。这个改动较小，但本轮数据仅支持减少几毫秒CPU工作，不能承诺消除全部卡顿。

进一步把周期保存改为：主线程生成不可变快照，单一串行后台写入者做封套、校验、文件提交；保存确认回主线程。允许合并尚未提交的周期快照；交易/结算与周期写入统一排队，处理revision冲突、写入失败、旧结果回传、退出等待。禁止后台读写实时场景节点。不是简单把现有save_base扔进Thread，也不是call_deferred（仍在主线程）。

验收：保留正常10秒保存，跑楼顶/吊桥至少3分钟，统计保存完成附近长帧；追加旧revision、写失败、bak恢复、退出等待和跨重启数据一致性验证。暂时拉长间隔只能减频，不能降低单次阻塞。

### B. 修吊桥慢区：优先压低云海像素成本

首选单独云海低分辨率渲染+深度引导合成，减少重复密度/梯度/光照查询；随后优化静态主塔距离计算。分辨率/采样档可作临时缓解，但不能当成维持原画质的正式修复。不要为了跑分快直接取消主塔禁云。

验收：沿两座吊桥重复同一路线，对比720p和1440p的P95/GPU时间，并查桥栏杆边缘、楼体边缘、室内禁云、运动闪烁和云形品质。禁止用隐藏整片云海作为最终交付。

### C. 追“最近才出现”的严重停顿：仍需事件现场证据

如果原游戏仍出现数百毫秒停住，下一步应在**实际游玩进程**加入低开销长帧环形记录：帧时间、save reason与分段计时、资源/节点变化、交互更新、GPU时间、场景/位置；触发后再批量输出，避免每帧写日志制造卡顿。若纯文件操作突然飙升，再用系统I/O跟踪定位等待对象。当前副本测试不能替代用户发生卡顿那一刻的现场记录。

## 文件、门禁与未执行项

生产代码、正式资产、画质默认值与用户原存档均未由本次修改；只新增诊断脚本、数据和本记录。没有Git提交。

文档门禁exit1：4个既有verify入口未注册；首次系统Python还缺openpyxl，改用已有WorkBuddy Python重跑后只剩4个既有入口。运行资产命名门禁exit1：既有带版本路径债务（详见原始日志）。不是本次诊断引入的生产改动；不报告全绿。

未执行：完整历史版本性能二分、实际用户输入复现、发行包、长期战斗、后台写入实现及其故障矩阵、操作系统I/O跟踪。根因已按“确认/未确认”分开记录，性能未修复。

原始文件位于outputs：stutter_recheck_20261004.json/.log、stutter_bridge_recheck_20261004.json/.log、stutter_bridge_720_recheck_20261004.json/.log、stutter_save_parts_20261004.json/.log。诊断入口位于_scratch/probe_*recheck*.gd/.tscn。
'''
md=root/'docs/v0.1/development/2026-10-04_stutter_recheck.md'
md.write_text(text,encoding='utf-8')
# Small static HTML renderer with native headings, tables and safe escaped text.
lines=text.splitlines(); blocks=[]; table=False
for line in lines:
    if line.startswith('|'):
        if not table: blocks.append('<table>'); table=True
        cells=line.strip('|').split('|')
        if all(set(c.strip())<=set('-:') for c in cells): continue
        blocks.append('<tr>'+''.join('<td>'+html.escape(c.strip())+'</td>' for c in cells)+'</tr>')
        continue
    if table: blocks.append('</table>'); table=False
    if not line: continue
    if line.startswith('#'):
        level=len(line)-len(line.lstrip('#')); blocks.append(f'<h{level}>'+html.escape(line[level:].strip())+f'</h{level}>')
    else: blocks.append('<p>'+html.escape(line)+'</p>')
page='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>间歇卡顿复查</title><style>body{background:#f3f5f7;color:#192332;font:16px/1.8 system-ui,"Microsoft YaHei";margin:0}main{max-width:1120px;margin:auto;padding:35px}h1{font-size:30px}h2{margin-top:36px;color:#176c61}table{border-collapse:collapse;background:white;width:100%;font-size:14px}td{padding:9px;border:1px solid #d7dfe5}p{overflow-wrap:anywhere}</style><main>'+''.join(blocks)+'</main></html>'
(out/'楼顶间歇卡顿复查_20261004.html').write_text(page,encoding='utf-8')
print(md)
