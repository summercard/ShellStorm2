# 四张库贴图与七种可编辑附魔飞行动态

- FeatureID：WEAPON-COMBAT / FATE-RULES / VFX-POOL；工程版本0.1.0。
- 用户来源：2026-11-18指定火tex_flame_01、冰毒tex_smoke_01、雷spark_02、其余三属性flame_04；随机动态/旋转/大小分属性调整，生命周期由大到小；评估射出后样式而非原地；每种提供可手调TSCN，更新设计和账本。
- 主设计：[战斗奖励与物品流转设计](../design/战斗奖励与物品流转设计.md)；工程契约：[14.6 §3.5a](../14.6_特效系统与制作规范.md)。本记录不提升全模块partial，不继承上一轮通过数。

## 1. 原图获取与来源

内网assetlib服务100.117.192.4:8099，使用已安装assetlib.py执行stats/search/files/get；四张截图中的文件均有准确匹配。原图先取至工程外`ShellStorm2-work/sessions/2026-11-18_projectile_enchant_motion/intake`，确认原尺寸512×512后保存到`art_source/vfx/projectile_enchant/textures/`，原文件不修改；运行图convert RGBA并LANCZOS缩至256×256，覆盖既有稳定路径。

| 使用属性 | 库路径 | 合成方式 |
|---|---|---|
| fire | aleksei-starter-vfx-lite/tex_flame_01.png | additive；原图alpha全255黑底，黑色零贡献，不抠图 |
| ice / poison | aleksei-starter-vfx-lite/tex_smoke_01.png | alpha，分别蓝/绿调色 |
| lightning | kenney_particle_pack/spark_02.png | additive，短促密集 |
| bounce / homing / return | kenney_particle_pack/flame_04.png | alpha，分别金橙/青绿/紫 |

库包许可字段均`-`，登记未提供/待核对，不杜撰CC0或称项目原创。原图与七运行贴图SHA详见`art_source/vfx/projectile_enchant/manifest.json`。本轮没有把用户截图当作素材。

## 2. 当前制作规则

七份正式`assets/art/vfx/combat_3d/vfx_projectile_enchant_{key}_root_top3d.tscn`升v003，是唯一可编辑参数源。每份TSCN同时包含完整子弹主体`BulletRoot/Core/Shell`：低面`CylinderMesh`、`resource_local_to_scene`材质、可染色参数、GPUParticles3D与灯挂点均在同一场景资源内冻结；有附魔时完整TSCN是视觉主体唯一可编辑真源，运行时将实际附魔颜色传给TSCN材质，首属性只作为TSCN主体挂载宿主选择，主体颜色取全部去重属性RGB平均。旧`VfxBulletBody`主体仅隐藏避免重复显示，Projectile3D仍独立保留方向、运动、命中和`SphereShape3D`碰撞；TSCN的Core/Shell/Particles不自动成为碰撞体。无附魔与滚石继续原主体路径。GPUParticles3D、ParticleProcessMaterial、Curve/Gradient和QuadMesh都保存在场景资源里，默认visible/emitting=true、speed_scale1，编辑器打开即可预览；无需改脚本。旧generate_projectile_enchant.py已移除覆写，默认和--prefabs-only均只读检查，避免再次运行抹掉人工调参。

| 属性 | 单属性基数B | 生命周期s | 随机scale | 尺寸曲线0→0.5→1 | 角速度°/s |
|---|---:|---:|---|---|---|
| fire | 10 | 0.52 | 0.85—1.35 | 1→0.60→0.06 | -90—90 |
| ice | 12 | 0.40 | 0.70—1.20 | 1→0.70→0.05 | -35—35 |
| poison | 8 | 0.68 | 1.10—1.75 | 1→0.75→0.08 | -24—24 |
| lightning | 40 | 0.11 | 0.60—1.30 | 1→0.45→0.04 | -720—720 |
| bounce | 16 | 0.24 | 0.75—1.40 | 1→0.55→0.05 | -240—240 |
| homing | 12 | 0.34 | 0.80—1.25 | 1→0.65→0.06 | -120—120 |
| return | 14 | 0.42 | 0.90—1.50 | 1→0.70→0.07 | -180—180 |

全部初始角0—360、非固定种子，寿命随机度0.15—0.35；方向/扩散/线性加速度/阻尼按属性不同，详见TSCN及14.6参数表。仍围绕弹心box出生，局部+Z漂移产生短尾，不开启旧几何拖尾。不同属性有不同发射率：名义B/lifetime火约19.2/s、毒约11.8/s、雷约363.6/s；GPU实际受寿命随机影响，不将名义值当实测。

多属性`amount_i=max(1,floor(B_i/N))`，B_i首次从TSCN缓存，不再把每种强行改为24；reset恢复原场景容量，不写amount1。运行仅控制启停/回收、宿主size/grow、实例box轴向与AABB，不覆写美术寿命、曲线、随机或材质。实例化先reset再add_child，防预览默认发射在运行时闪出。

标准弹主体染色、特殊弹保色、力量滚石和独立彩灯沿用上一轮。每发一盏灯、回收归零，不改伤害/弹速/碰撞/命运行为/存档。

## 3. 验收方法

旧静止/2m/s手动移动不再作为主验收。专项在Autoload前隔离用户目录及工程，正常通过ProjectilePool3D.acquire→Projectile3D.activate，以23m/s真实_physics_process推进；mask0、range48m，7条飞行lane，约0.8秒发射一轮，飞出20m才退役。统计位移/真实物理时间核验23m/s，单独粒子追踪viewport排除主体脉动和灯光，检测真实粒子帧变化。

动态采样目标72帧/约0.045秒间隔，保存实际时间戳而不是假定恒帧率；缩放展示倍率×2明确标注，真实玩法速度不降速。原grid/mix/七单属性/灯投光仅补充，不代替飞行证据。运行结束检查pool active0。更新断言保留主体/灯/池化/保色/碰撞，不把旧24、恒1曲线、旧透明火图规则强行套用新设计。

## 4. 运行与同步结果

本轮实际尝试了23m/s真实飞行runner，但runner超时且没有生成scene报告；因此真实23m/s位移、随机模拟、池化复借、连续帧和双分辨率飞行均保持**尚未通过/无证据**，不得写`validated`。静态manifest/TSCN检查只作为制作同步依据，不替代Godot真实运行。七项账本主表67—73及3D页同ID保持`authored（已制作／待验）`；7独立灯v001、标准弹v001/r27及其历史状态不变。门禁按修改前/后比较，不重基线无关资产漂移。

本轮同步门禁：四份Markdown、账本主表r67—73、`3D-特效`同ID行及`ledger_split_baseline.json`；未改源码、tests或manifest。备份位于工程同级`ShellStorm2-backup/2026-11-18_projectile_enchant_full_bullet/before_edits/docs_ledger/`（账本最终回填另存`.../before_edits/ledger_finalize/ledgers/`）。账本状态保持`authored（已制作／待验）`，未写`validated`。未执行：整关人工游玩、Android、满屏压力/GPU耗时、所有构筑组合穷举。素材许可未在库中提供，正式发行前需完成许可确认。共享索引未纳入本轮目标；若写入失败不强行替换。

## 5. 完整子弹主体回填（2026-11-18 收尾）

七份TSCN的`BulletRoot/Core/Shell`主体已实际存在（逐份核验v003、`resource_local_to_scene`、GPUParticles3D齐备）。本次把该事实补进账本：主表r67—73的规格列追加“TSCN同时含完整可染色子弹主体、有附魔时唯一可见主体、旧主体隐藏但保留碰撞/方向/命中、TSCN内几何不参与碰撞、碰撞仍为独立`SphereShape3D`、无附魔与滚石走原路径”，备注列追加同一口径并保留“未跑Godot、不得写validated”；`3D-特效`r261—267的GLB列改为“无GLB；TSCN内程序几何BulletRoot/Core/Shell+贴图QuadMesh粒子”，Blender源列补“TSCN含完整可染色子弹主体”。`MODULE_INDEX`2026-11-18现行段补注“每份同一文件内含完整子弹主体＋粒子＋灯挂点”。

基线只做定向更新：7条粒子行`v`指纹重算＋`sheet_digests["3D-特效"]`；`column_digests`、`category_counts`、其他资产指纹、7灯v001与标准弹v001均未动。`verify_ledger_split`失败数32→24，剩余24项为其他域并发未提交漂移（敌人/场景/道具行内容与两件奖励箱新增、若干移动页），本轮不代为重基线。DV数量保存前后一致（15条），公式列未被改写。共享`MODULE_INDEX`此前`write_text`报`OSError Errno 22`，本次改用编辑工具写入成功。

仍未运行Godot：完整子弹在TSCN内的实际外观、染色、粒子包裹与23m/s飞行均无本轮实机证据，整局/压力/Android未验。
