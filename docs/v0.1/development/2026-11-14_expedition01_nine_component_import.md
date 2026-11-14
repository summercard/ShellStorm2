# 远征01九组件v029导入与账本文档同步

FeatureID：ASSET-PIPELINE / WORLD-PLAN；游戏版本：0.1.0；日期：2026-11-14。
来源：用户明确授权九件同路径替换及最小账本文档同步；状态：九组件导入专项已有通过证据，本次同步门禁见下表，远征整关仍为partial。
设计依据：[远征关卡01设计 §3.1.1](../design/远征关卡01设计.md)、[Boss房02装配契约](../design/远征关卡01_Boss房02装配.md)。
代码基线：`172d32de74068473c4a65bcafbc05ba9ef176819`，分支`0.2`；工作区已有未提交修改，不将本记录视作干净提交验收。

## 1. 范围与版本语义

九件已由主代理完成GLB及Prefab同路径替换，本事务仅核验其磁盘hash并同步登记，不再写任何GLB、Prefab、模型清单或制作源。

| 组件 | 三角面前→后 | 场景账本《资产主表》 | 《3D-场景通用》 |
|---|---:|---|---|
| matrix_bay_5m | 30672→6132 | 900，独立组件v029 | 760，v029 |
| cables_crown | 19456→3890 | 896，独立组件v029 | 756，v029 |
| cables_mirrored | 19456→3890 | 895，独立组件v029 | 755，v029 |
| cables_swept | 19456→3890 | 894，独立组件v029 | 754，v029 |
| floor_detail_b | 22788→4556 | 246，DB总行仅备注 | 不新增登记 |
| mid_gallery | 19516→3900 | 244，BRIDGE总行仅备注 | 不新增登记 |
| upper_bank_z5450 | 14040→2806 | 244，BRIDGE总行仅备注 | 不新增登记 |
| filing_run | 16104→3218 | 243，OFFICE总行仅备注 | 不新增登记 |
| planting_perimeter | 13240→2648 | 243，OFFICE总行仅备注 | 不新增登记 |

五个含下划线的旧组件ID逐字保留，不重命名、不补独立资产行；其追溯落在既有房型总行：DB的M=v014、BRIDGE的M=v002、OFFICE的M=v001均保持，主文件路径及T列SHA-256也保持原始语义。组件优化版本v029不等于整个房型或组件库升版。

`work_cluster`工位v031为8162三角、减面50.012%的候选，未导入、不升版、不回填其正式资产hash。本次九件范围不包含工位。

## 2. 证据与核验边界

- 实际安装manifest：`I:/工作项目/shellstrom2/ShellStorm2-work/outputs/expedition01_optimization/import_20261114/manifest.json`，`installed=true`。九条records记录原始源、v029优化源、GLB及Prefab路径与hash before/after。
- 主代理Godot验证：同目录`godot_verification.json`，`passed=true`、`failures=[]`，九件三角面及v029与manifest一致；主代理以真实OpenGL加载探针核对公共色盘材质与优化后bbox符合记录，非用户人工验收确认。该JSON的`rendering`字段仅写`Windows`，不将其单独解释为渲染后端证据。
- 本次独立复核：九件源/优化源/GLB/Prefab实际SHA-256均匹配manifest；原始源before=after；177份受保护房间TSCN逐文件hash一致。碰撞形状数量为filing_run=2、upper_bank_z5450=1、其余7件=0。
- 主代理报告的正式重导扫描存在旧palette UID错误，但九目标导入成功；验证阶段存在其他旧资产palette UID路径回退及兼容渲染器TAA警告，无SCRIPT ERROR。本事务没有重新执行Godot或修复这些告警，不把重导扫描描述为零错误。
- bbox按优化后的实测结果验收，不宣称与原始几何绝对相等；详细数值在manifest及Godot验证JSON。
- 本次门禁日志与变更白名单：同目录`sync/`，保留`before_*`、`after_*`、`preflight.json`及`ledger_changes.json`。可续用工程外`sync_ledger_docs.py final`只读复核保护范围；`apply`带一次性前置断言，不应重复执行。

## 3. 备份、并发保护与最小更新

系统shell实取时间为`2026-11-14T19:26:58+0800`，写前快照`2026-11-14T19:29:01+08:00`，账本落盘时间`2026-11-14T19:30:17+08:00`，不是以文档日期替代真实取时。

备份位于工程外`ShellStorm2-backup/2026-11-14_expedition01_nine_import/before_edits/`。账本与baseline既有备份未覆盖，已核对其hash等于本次写前文件；四份受影响文档补备份时使用独占创建。保留工作区原有设计页、运行数据、刷怪验收及其他会话修改，不回滚或重生成布局。

- 场景分账本通过`ledger_index.json`解析归属。四独立行仅M/T/V/Y：M=v029，T为O列稳定Prefab的实际SHA-256（不是GLB或Blend的hash），V为真实日期，Y追加原始源/优化源及导出追溯。
- 三房型总行仅Y列备注。对应四条3D分页仅O/P：O=v029，P追加同批追溯，E保留原始制作源。既有制作状态、尺寸契约、碰撞职责、ID与稳定路径保持。
- 主表事务域日志`v0.1.87`、3D分页事务`v0.1.88`；账本回读逐格差异恰好41格，包含两条域日志14格，不增加资产行。不改R/S公式、总览范围、DV及其他分页。
- 基线仅七条批准资产`v`、列摘要13/20/22/25及`sheet_digests["3D-场景通用"]`变化；列摘要按九域当前并集重算，但其他列的旧漂移保留。其他资产指纹、专表摘要、captured_at、分类数量与asset_count=1447保持，不接纳双宝箱等未登记基线缺口。没有运行`--baseline-only`。
- 设计正文仅补当前组件优化源/版本及房型归属事实；运行日志、测试数与警告保留在本开发记录，不借本批导入提高整关实现/验收状态。

## 4. 本事务门禁与真实退出码

门禁均由Python subprocess独立捕获退出码，stdout/stderr分开留存，未通过管道吞掉失败。改前已在九件安装完成、账本尚未更新的时点执行。

| 检查 | 改前退出码 | 改后退出码 | 对照结论 |
|---|---:|---:|---|
| check_documentation_contracts.py | 1 | 1 | 11→11条既有断链；忽略新增导航引起的旧行号位移后逐项相同，新增0 |
| check_asset_runtime_naming.py --json | 0 | 0 | 通过；未使用--update-debt |
| check_asset_registry.py --scope structure | 1 | 1 | 102→102：50条查重键公式、50条查重结果公式、2条状态枚举问题；逐项相同（数组对象内存地址不作内容差异） |
| check_asset_registry.py --scope full --ledger scenes | 1 | 1 | 6→2条sha_mismatch；四个批准替换的组件hash闭环，余下两条既有漂移逐项相同，无新增 |
| verify_ledger_split.py | 1 | 1 | 109→109项；工具输出的前40条失败规范化后相同，双宝箱extra仍保留；未接纳其他资产指纹/分页摘要 |
| check_expedition_room_asset_status.py --json | 1 | 1 | 46→46条同名既有问题，均为其他远征相关条目未在01表收录；本批不扩大登记或改门禁 |

scenes full保留的两条旧hash漂移为`ENV-BASE99-REMAINING-FACILITIES-V021`（主表232）及`ENV-OPENWORLD-UNDERGROUND-STREET`（主表962），这两行未改。结构门禁的敌人R/S公式等红项属于改前工作区；split仍有双宝箱`PRP-3D-REWARD-CHEST-ADVANCED/NORMAL`不在基线及其他历史指纹/公式/分页缺口，未为本批全绿而补录。文档11条旧断链涉及制作框架图片、旧技术施工引用、内容数据库旧路径及历史CHANGELOG链接，不在本次修复范围。

各检查的真实命令、退出码与stdout/stderr见`sync/before_gates.json`、`after_gates.json`及对应日志；新旧摘要见`sync/gate_comparison.json`。失败检查均如实保留为exit 1，不把封装器成功退出误写为门禁通过。

最终保护复核退出0：九件源/优化源/GLB/Prefab、运行模型JSON清单及current_source_index均与写前快照相同，177份房间TSCN与manifest相同。零依赖`scripts/blender/xlsx_read.py`回读确认四组件v029及三房型原版本；文档逐行对比仅四条组件源说明替换及本批新增内容，写前已有并发内容未删除。`git diff --check`退出0（只有Git的LF→CRLF提示）。定点差异证据另见`sync/final_scope_audit.json`。

## 5. 未执行与交付边界

账本文档子事务未重新制作/导出/导入模型；主代理本批已替换九个稳定GLB并定点更新九个Prefab的版本/优化源/hash元数据，节点结构、碰撞和房间摆位保持。主代理随后在九个组件包asset_manifest.json同步optimization_v029记录（floor_detail_b此前缺包级清单，本批补齐），记录原始/优化源hash、三角面、预算、导出与引擎专项证据。四个Boss组件原始源版本仍为v027，runtime/optimized版本单独记v029；库级旧整批导入记录保留历史语义。未跑远征整关、smoke/core/full完整套件、正式存档往返、人工手感、Forward+性能或移动端。主代理九件真实OpenGL加载专项不等于远征01整关通过；整关partial及工位候选未导入的状态保持。

工位50%候选已持久化为`art_source/environments/tower_zones/expedition/source/common_components/v009/component_packages/work_cluster/export/v031/work_cluster_optimized_v031.blend`；仅输出集合16328→8162三角、8036→4912多边形，4912面PaletteUV验证通过。按174连通部件隔离简化，没有使用原失败80%候选。原始源及色盘hash不变；同机位五视角对照未见先前大面积塌面，但俯视四根细条存在颜色外观差异，保留待审核、未导入，工位稳定GLB/Prefab未改。报告位于工程外`outputs/expedition01_optimization/workcluster50/updated_persistent_candidate.json`。
