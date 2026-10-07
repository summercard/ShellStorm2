from pathlib import Path
R=Path.cwd()
def change(path,fn):
 p=R/path;text=p.read_text(encoding='utf-8');p.write_text(fn(text),encoding='utf-8')
def animation(s):
 s=s.replace('命中第33帧触发2D手绘尖角爆点、贴地冲击环；挥击和命中短促点缀蓝色/玫红电子干扰；手绘特效尺寸为v014的1.65倍；源文件独立预览集合保存，不混入角色几何，Godot表现与伤害另行接入。','命中第33帧触发无勾线纯色爆裂形与贴地脉冲环；挥击和命中点缀冷蓝、冰蓝与少量玫红电子干扰，黄色高亮仅1帧。预览集合不混入角色几何；正式Godot VFX与技能时间轴同步。')
 s=s.replace('重击复用image-2手绘图集，大范围双层冲击环与放射爆点在F64触发，旋转时使用专用高饱和正红/亮蓝渐细环形弧带，不复用打击爆点；','大范围纯色分段冲击环与黄色爆裂形在F64触发，旋转时使用冷蓝/冰蓝及少量玫红的专用弧带，不复用打击爆点；')
 s=s.replace('特效仅源级独立预览，正式事件同步待接入。','正式特效由技能真实时间驱动。')
 start=s.index('状态唯一所有者为后续Boss运行控制器；');end=s.index('## 9. 验收入口与制作顺序',start)
 s=s[:start]+'''状态唯一所有者为Enemy3D；MonitorBossCombat提供schema1只读表现上下文 `{action_id,time,skill_id,phase,electric_active,telegraph_radius,contact_point,hit_flash}`，time为秒，空间为世界米。MonitorBossPresentation由AnimationPlayer索引Blender求值姿态；不根据手端位置生成程序手臂、不从美术关键帧写HP。候选接触标记按技能契约冻结到真实命中时间。

待机↔移动使用0.18秒混合；旋转、命中等关键姿态保持真实时间。特殊持续从insert进入，恢复/打断解除电流；坐地优先级和伤害规则见技能设计。表情由新状态重设，代码UV滚动相位连续。左右转抵消动作内的底座yaw，由逻辑根消费角度，避免双转。

未知动作或资源加载失败明确报错，不静默显示其他Boss；未知技能拒绝并回chase。插线点采用动作接地点转世界坐标，无外部任意点输入。死亡、失活和卸载取消技能；读档危险状态退alert。正式ID boss_monitor002映射远征01 Boss房；旧Boss目录保持原映射。

''' +s[end:]
 s=s.replace('正式15剪辑放动作母版','正式16剪辑放动作母版').replace('最后做特殊四段与击晕三段，补hurt。','最后做特殊四段与击晕三段，补hurt与dead。')
 s=s.replace('正式接入入口待Boss002内容映射和动作制作完成后建立，由Boss运行控制器驱动表现适配器。独立Blender预览通过不代表游戏伤害判定、碰撞、存档或Boss流程已通过。制作记录见[开发记录](../development/2026-10-03_boss002_monitor_source.md)。','正式接入由BossContentCatalog→MonsterInjector→Enemy3D驱动，独立入口为verify_monitor_boss_flow与verify_monitor_boss_visual；源姿态、玩法判定、读档与真实渲染需分别验收。源制作历史见[记录](../development/2026-10-03_boss002_monitor_source.md)，正式接入事实见[开发记录](../development/2026-10-06_boss002_runtime_import.md)。')
 return s
change('docs/v0.1/design/Boss002显示器动画设计.md',animation)
def module(s):
 lines=s.splitlines()
 for i,line in enumerate(lines):
  if line.startswith('BOSS-STAGES / ASSET-PIPELINE：'):lines[i]='BOSS-STAGES / ASSET-PIPELINE：[Boss002技能设计](design/Boss002显示器技能设计.md)、[动画设计](design/Boss002显示器动画设计.md)。v031正式Prefab、16剪辑/64骨、十二态、四技能与三阶段已接入远征01 f00_boss；同AssetID台账active。专项与真实渲染证据见[正式导入记录](development/2026-10-06_boss002_runtime_import.md)。'
  if line.startswith('| BOSS-STAGES |'):lines[i]='| BOSS-STAGES | 显示器Boss002、95/90/85 Boss及下行权限 | [Boss002技能设计](design/Boss002显示器技能设计.md)、[06](06_技术施工_怪物精英与Boss.md) | `BossContentCatalog`→Enemy3D→Tower | `verify_monitor_boss_flow`、`verify_monitor_boss_visual`、`verify_unique_boss_content_flow` | Boss002正式链已验收；既有钥匙实体契约仍未完全对齐 |'
 return '\n'.join(lines)+'\n'
change('docs/v0.1/MODULE_INDEX.md',module)
entry='''## 2026-10-06｜Boss002 v031 正式导入、十二态与四技能

BOSS-STAGES / ENEMY-AI / ASSET-PIPELINE：动画r25、技能r1。双母版同64骨架、纯视觉GLB与16剪辑采样导出；正式Prefab由Enemy3D驱动四技能/三阶段，远征01 Boss房指派boss_monitor002。新增独立怪物表行及Boss002技能设计页，敌人账本与中转active。507项专项、真实渲染10帧、旧Boss及Enemy3D回归通过；聚合计划/资产/文档历史门禁问题分开记录。见[正式接入记录](2026-10-06_boss002_runtime_import.md)。

'''
change('docs/v0.1/development/CHANGELOG.md',lambda s:s.replace('# 游戏设计文档 v0.1 变更记录\n','# 游戏设计文档 v0.1 变更记录\n\n'+entry,1))
print('Current design, feature index and delivery record synchronized')
