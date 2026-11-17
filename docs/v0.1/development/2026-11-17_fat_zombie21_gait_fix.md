# 胖子僵尸2.1 v007滑步修复与登记收口

日期：2026-11-17；记录ID：FAT-ZOMBIE21-GAIT-FIX；功能ID：ENEMY-AI / ASSET-PIPELINE；工程版本：0.1.0。
设计依据与修订：[胖子僵尸03运行配置·现行2.1视觉契约](../design/胖子僵尸03运行配置.md) v007；来源：用户本次限定文件指令、原骨架/权重强约束。代码基线：本次开始时的未提交共享工作区；交付提交：工作区，不提交、不推送。

## 1. 范围与事实所有者

- 本事务只复制v007动作母版、归档被替代v006、修改胖子21三个原有稳定v002命名JSON、敌人账本既有r19/r57、目标基线/源索引及本次文档。没有改运行GD/TSCN/GLB、测试、Enemy3D/Avatar、玩法数据、其它资产行或自动化目录，不使用checkout/reset/stash或整树恢复。
- `fat_zombie03 / ENM-NORMAL-FAT-ZOMBIE03`仍是旧玩法/兼容ID，只映射 `ENM-NORMAL-FAT-ZOMBIE21` v007视觉。普通/强化与三种借皮怪边界沿用[入口替换记录](2026-11-17_fat_zombie21_replacement.md)。Enemy3D独占移动、碰撞、伤害、预爆、掉落和存档。
- 状态保留合法 `exported_pending_godot_validation`：**本次gait专项已通过282/282；全资产仍待整关验收**。专项通过不代表全资产accepted，不提升全局partial。

## 2. 真实交接、源与运行证据

工程外证据根：`I:/工作项目/shellstrom2/ShellStorm2-work/sessions/2026-11-17_1617_fat_zombie_gait/`。两份权威交接已完整读取：`animation_v007/handoff.json`、`runtime/contact_lock/handoff_contact_lock.json`；同时核对源validation、GLB roundtrip、运行verification/render及真实动作帧段。不以旧开发摘要代替交接结论。

| 对象 | 当前值 |
|---|---|
| 新动作母版 | `art_source/enemies/normal_enemy_3d/fat_zombie21/source/animation/enm_normal_fat_zombie21_animation_v007.blend` |
| 动作SHA-256 | `01ec0e16310ac5f4a325d37302f3cae0536ee8aa1d6f512c1cc6126adc37d3f3` |
| 稳定GLB | `assets/art/enemies/normal_enemy_3d/fat_zombie21/components/enm_normal_fat_zombie21/enm_normal_fat_zombie21_visual_top3d.glb` |
| GLB SHA-256 | `59cafc091fe6cd4d99c717969131d1366a41bfe63e75d19a6ae9ad6a9fd1e043` |
| 稳定包装SHA-256 | `1adb821773e115cfde8d058caf611552b41800fa34d7fea1270d6b067da432af` |
| 原几何/骨架/权重/绑定 | 四指纹与原源一致；41骨/597制作顶点/29权重组，不重绑、不改静止姿态 |
| 原动作保留 | idle、attack、move_start、move_stop逐动作hash一致；本次源只改walking/running |

源侧Blender4.5.0独立验证、GLB回导均exit0；walking/running分别961/577个四分之一帧采样覆盖两循环，源支撑最大pairwise直径约8.12734e-6/4.33887e-5m，GLB约8.85897e-6/4.36775e-5m；源到GLB顶点误差约2.12084e-6/1.95040e-6m，循环误差0。这只证明标定直线位移下源曲线与导出，不代签实际转弯。

本次只读加载v007 Blend提取元数据，未保存/重导，也未重跑Godot或动作测试：60fps，idle F0—192=3.2s、walking F0—120=2.0s、running F0—72=1.2s、move_start F0—24=0.4s、move_stop F0—36=0.6s、attack F0—150=2.5s，与GLB及Godot时长一致。原walking/running/attack的2.5/2.0/2.0声明已纠正；三个JSON保留 `previous_declared_seconds/history_source`，`source_metadata_conflict`只解除此元数据冲突，不解除整体验收。旧idle-only metrics/checks/逐帧结果加历史scope，不充当六段验证。

## 3. 运行专项的实际结果与方法

以下为运行主代理既有最终交接的已执行事实，本登记事务未重复执行或修改测试：

- `verification_checks=282 / failures=0`，最后隔离导入与contact_lock_test均exit0、unexpected_errors为空。方法为120Hz真实Mesh ARRAY_BONES/WEIGHTS＋Skin bind＋实际Skeleton pose的CPU世界蒙皮；原48顶点完整stance、连续跨cycle全pairwise，不改顶点集合、不缩短支撑窗，不用骨中心代替。
- walking stride0.6m、running0.72m，以总scale2.7557166标定；`phase += actual_distance / scaled_stride`，停/堵墙不推进。实际基础巡逻0.255、追击0.51m/s，来自设计0.3/0.6×PACE0.85，不改玩法速度。
- v006旧脚本巡逻/追击对照漂移0.0645014/0.0800596m；v007锁锚前转弯对照0.619944m。最终巡逻约1.10928e-5m、追击1.34719e-5m、人工光两速度/1.5m/s关卡覆盖/强化1.5体型/加速刹停均在1cm内；最终强化转弯最坏2.06497e-5m。
- 36组双向walking/running切换，9相位×2方向×2体型；支撑跳变1.18104e-6m、摆动跳变1.68824e-6m、切换后漂移2.02824e-5m、pose scale误差1.04606e-6、堵墙切换跳变6.93194e-7m。包括重复sync、真实墙、瞬移/离树、垂直离地、非movement清锚、攻击F39/F78、与prelock攻击曲线逐骨一致、正式VFX池一次触发、flash/预爆材质恢复。
- **程序pose=true**：源局部姿态恢复后采样，支撑组按自然segment世界刚体锚，父先子后写入同一未纠偏世界快照；walking/running duty0.60/0.61。切换0.08phase混合，swing纠偏0.12phase消退，不再moving时播放旧move_start。不是纯曲线、无补偿或严格等长IK。
- 真实非headless Forward+ / Vulkan / RTX4060Ti录帧exit0：转弯前后各93帧、切换前后各181帧，30fps四段视频在 `runtime/contact_lock/`，另有源工作台两循环视频。运行交接只对接触表做静态目检，明确要求主代理继续打开连续视频复核；本事务不代签人工连续动态验收。
- 失败尝试未掩盖：测试stride/next_stride类型推断曾解析失败；随后40项失败涉及移动scale误差与running→walking duty差处重复离地纠偏。交接已用显式float、移动scale1、切换清旧release及真实源快照修复，历史日志仍在；只有最终282/0作为当前专项结果。

## 4. 登记事务与并行保护

按[工作区规范](../../WORKSPACE_LAYOUT.md)冻结在 `ShellStorm2-backup/2026-11-17_fat_zombie_gait/before_edits/registration/`；SHA清单、before_status/before.diff及所有exit/log在本会话 `registration/`。现有主代理备份未覆盖。

v007从handoff源复制后校验，正式GLB只读核对相同hash；v006先复制至 `ShellStorm2-backup/2026-11-17_fat_zombie_gait/original_tree/art_source/enemies/normal_enemy_3d/fat_zombie21/source/animation/` 并验证原SHA `e0932518ada4d9e4a9b233ce677f55cfa923f92075fb092d999ea4ea7fc8a2d3`，记录 `management/moves.jsonl`。**工具失败与最终磁盘事实分开记录**：PowerShell中文路径乱码，返回 `SAFE_DELETE_FAIL_CLOSED / path-not-found`；没有绕工具重试。之后只读终检观测工程v006已不存在，归档原SHA仍一致，说明所需“v006退出工程”结果现已成立，但无法确认是安全工具部分执行还是并行操作，本事务不冒称取得删除成功回执。工具失败原样留证，主代理需核对执行归属。旧v002 idle参考是本次未授权删除的其它源，保留不动且current=false，不假称已清空所有历史源。

三个原有JSON文件名 `_v002.json`作为稳定兼容入口保留，内部版本v007；更新新源path/bytes/SHA、运行GLB、包装hash、真实clips、locomotion_calibration/runtime_contact_lock及风险。transfer的manifest自身bytes/SHA随最终manifest同步。未修改桌面原源、模型v002、已确认idle/attack。

openpyxl仅修改敌人账本《资产主表》r19/r57的M/N/P/T/V/Y；当天日期相同的V实际不产生diff，两行共10个实变格。r19 T为稳定包装SHA，r57 T为稳定GLB SHA；AssetID/逻辑ID/制作状态/原主路径及其它所有单元格、样式/专表保留。域日志从当前最大v0.1.56新增唯一 **v0.1.57**（7格），不重复v0.1.56。合计17实变格，全部公式/DV在ZIP层相等；原R/S与权威函数逐行一致。实际逐格before/after保存在 `registration/ledger_cell_diff.json`。

共享current_source_index读取最新并在写前hash校验，只改胖子21动作项/旧superseded指向及fat_zombie03视觉映射，保留其它asset和VFX追溯。基线只改两个目标v及13/14/16/20/25五列摘要；各列改前九域联合摘要先匹配才准更新，所有其它asset指纹/专表/历史元数据逐项不变，不接受其它漂移。账本写入前hash校验，保存临时文件验证后再次hash检查再替换。

开发README/CHANGELOG/MODULE_INDEX仅追加本次条目，不改并行条目；本记录为新增独立开发入口，不回写历史替换记录。

## 5. 静态门禁前后差分

修改前七项已执行，逐项命令、exit及stdout/stderr在 `registration/baseline_*`；修改后对应 `registration/after_*`，集合差分见 `gate_diff.json`，最终交接见 `handoff_registration.json`。本次不以命令exit0掩盖日志问题，不批量修旧债。

| 门禁 | 改前exit / 问题 | 改后 |
|---|---|---|
| check_documentation_contracts | 1；14条断链＋verify_fat_zombie21_gait未登记，共15项 | 1；同15项，新增0；忽略仅追加条目造成的断链行号偏移 |
| check_asset_runtime_naming | 0 | 0；通过 |
| check_art_source_layout | 1；12条既有ignored源/缓存 | 1；同12项，新增0 |
| check_ledger_refs | 0 | 0；通过 |
| check_asset_registry structure | 1；17项既有结构债 | 1；同17项，新增0 |
| check_asset_registry full enemies | 1；r55非法状态＋目标两行SHA失配 | 1；仅r55既有非法状态；目标两条SHA失配消除，新增0 |
| verify_ledger_split | 1；24项、额外2资产，无列摘要漂移 | 1；同24项/额外2资产，无列摘要漂移，新增0 |

## 6. 风险、未执行与交接

1. 世界锚不是等长IK，近端到支撑段可伸缩；只验自然stance及±0.35rad转向，极端转弯/长时间原地转向不得外推。
2. swing恢复源clip；短pose混合不保证全身速度/加速度严格连续，堵墙时混合冻结。
3. 楼梯、动态平台、任意非等比缩放未验；小于原瞬移阈值且无显式事件的位置跳变无法可靠区分真实位移。
4. 未跑完整关卡AI录像、主工程重新导入、全资产/core/full运行套件、移动端与完整存档往返。本次用既有工程外最小项目专项证据，不代签完整主工程。
5. move_start/move_stop源未改且不宣称移动锁脚通过；idle-only历史数据不代表全部动作。其它缺失剪辑、眼位/四足轮廓/旧碰撞完整可玩兼容、输入许可仍待完整验收。
6. 安全工具报告失败但终检观测v006已移出、归档SHA正确；不绕过重试、不恢复它，执行归属仍需主代理确认。其它未授权源保持；不以v007当前映射冒称目录里所有历史参考都已清理。运行视频连续复核由主代理负责。

恢复必须先对照本次hash与后续并行改动，再逐文件最小处理；禁止整树覆盖、git恢复无关文件。正式运行文件本次应保持开始时字节不变，具体保护清单与复核结果以registration交接为准。
