# 工程、文档与开发状态表交付记录

日期：2026-09-12。记录ID：DOC-DIFF-20260912。工程版本：0.1.0。
功能范围：全模块审计的差异统计，不是新功能实现。
设计依据：用户要求按差异项目逐行比较工程与文档，并标注一致性、是否修改和修改方向；遵循[文档驱动开发规范](../../DOCUMENTATION_STANDARD.md)。
代码基线：`31ed360644768808e6faef5cd3b341b731888625`。事实来源：[工程审计](../audits/2026-09-12_engineering_audit.md)及其证据。

- 交付 Excel：保留44项跟踪，其中10项已一致、10项开发中·部分完成、6项工程/文档不匹配、12项待设计／核验、6项文档缺失；另有214条资产摘要展开明细、9项上一轮已对齐文档记录。资产汇总在主表只计1项，不与明细重复累加。
- 当前未处理方向为16项工程对齐文档、11项先确定文档再对齐、7项先核验版本；原7项“文档对齐工程”已经全部处理。
- 每行列出工程现状、文档要求、判定分类、情况说明、是否已处理、修改方向、建议、处理状态、优先级和依据；当前10项已处理、34项未处理，主表支持按字段筛选及冻结表头、识别列。
- `开发中·部分完成`是版本施工进度，不计为错误或事实冲突；只有冻结口径互相冲突、或文档错误宣称已完成时才进入`工程/文档不匹配`。未冻结项目和契约缺失分别统计，不能与开发进度混算。
- 未将明确标注未施工的30张命运卡计为错误；未将214条哈希变化认定为214个损坏资产；有争议的数值及版本保留待核验。
- 初次交付只制作统计；2026-09-12后续已修复E03，并按用户决定用当前工程行为更新E01/E02文档。原内容数据库和资产台账未修改。
- 验证：重新计算统计公式；逐表检查排版；导出后核对44条主表、9条历史记录、214组资产路径与双方完整SHA、筛选器及冻结窗格；214个资产文件的当前哈希与留存证据再次一致。未执行Excel客户端重算或新增游戏验收。

长期结构化清单保存在[差异数据](../audits/evidence/discrepancy_inventory_20260912.json)。Excel 为本次任务输出目录中的交付文件；游戏缺陷的故障证据、验收范围及限制继续以工程审计为准。
## 逐项处理状态与对应文件（全部跟踪项目）

### E01｜到达门／保存前放行

- **是否已处理：`是`；处理状态：`已修改文档`。**
- 判定：`已一致`；修改方向：`文档已对齐工程`。
- 处理结果：已完成02、05、09、11及模块状态同步；不修改运行时代码。
- 对应文件／定位：

  - `src/world3d/TowerDescent3D.gd:2196、2942`
  - `docs/v0.1/05_技术施工_关卡生成与爬楼.md；docs/v0.1/09_技术施工_存档结算与复活.md §5.4`
  - `docs/v0.1/development/2026-09-12_e01_e02_document_alignment.md`

### E02｜区段提交／提前卸载

- **是否已处理：`是`；处理状态：`已修改文档`。**
- 判定：`已一致`；修改方向：`文档已对齐工程`。
- 处理结果：已完成02、05、09、11及模块状态同步；保留后续服务解耦方向，不增加持久化门禁。
- 对应文件／定位：

  - `src/world3d/TowerDescent3D.gd:3142`
  - `docs/v0.1/05_技术施工_关卡生成与爬楼.md；docs/v0.1/09_技术施工_存档结算与复活.md §5.5`
  - `docs/v0.1/development/2026-09-12_e01_e02_document_alignment.md`

### E03｜资源扣款／失败误报成功

- **是否已处理：`是`；处理状态：`已修改并验证`。**
- 判定：`已一致`；修改方向：`工程已对齐文档`。
- 处理结果：已完成单次扣款收口；下一步按E04合并工坊扣款与解锁。
- 对应文件／定位：

  - `src/base/BaseManager.gd:702`
  - `tests/verification/verify_extraction_points_spend_transaction.gd`
  - `docs/v0.1/09_技术施工_存档结算与复活.md`
  - `docs/v0.1/development/2026-09-12_e03_extraction_points_transaction.md`

### E04｜工坊升级／两次独立保存

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 处理建议：设计升级命令，合并扣款与解锁；提交失败一起回滚，补工坊故障专项。
- 对应文件／定位：

  - `src/ui/WorkshopMenu.gd:146`
  - `src/base/BaseManager.gd:686、702`
  - `docs/v0.1/09_技术施工_存档结算与复活.md §2.1`

### E05｜撤离结算／多次提交

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 处理建议：建立单次结算事务；持久化成功后发事件；验证拒绝、重试与重载。
- 对应文件／定位：

  - `src/world3d/TowerDescent3D.gd:288`
  - `docs/v0.1/09_技术施工_存档结算与复活.md 撤离结算`

### E06｜死亡结算／场景多域写入

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 处理建议：收拢死亡结算命令；覆盖保险交接、写盘失败与重入，不重复发奖励。
- 对应文件／定位：

  - `src/world3d/Dungeon3D.gd:4727`
  - `docs/v0.1/09_技术施工_存档结算与复活.md 死亡结算`

### E07｜新特效池／回收回调

- **是否已处理：`否`；处理状态：`未修改`。**
- 判定：`工程/文档不匹配`；修改方向：`工程对齐文档`。
- 处理建议：修正信号参数契约；专项验证循环借还、active 数量及场景退出清理。
- 对应文件／定位：

  - `src/vfx/VfxEffectBase3D.gd:7、60`
  - `src/vfx/VfxPool3D.gd:64、107`
  - `docs/v0.1/14.6_特效系统与制作规范.md；docs/v0.1/audits/evidence/core_output.txt`

### E08｜特效迁移／双池与旧断言

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 处理建议：依新 Prefab 契约迁移调用者及验收；迁移完成后再退役旧池。
- 对应文件／定位：

  - `docs/v0.1/14.6_特效系统与制作规范.md`
  - `src/combat3d/WeaponModel3D.gd`
  - `src/combat3d/Projectile3D.gd`
  - `tests/verification/verify_3d_melee_feedback_flow.gd`

### E09｜世界模块／独立开发边界

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 处理建议：按楼层提交、区段、结算、UI 适配逐步抽服务；用替身测试接口边界。
- 对应文件／定位：

  - `docs/v0.1/02_技术架构总则.md`
  - `src/world3d/Dungeon3D.gd`
  - `src/world3d/TowerDescent3D.gd`
  - `docs/v0.1/audits/evidence/source_inventory.json`

### E10｜跨域写权限／事件接口

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 处理建议：集中写入权，提供命令结果与只读快照；冻结实际使用的局部事件契约。
- 对应文件／定位：

  - `src/enemy3d/EliteRosterService.gd:208`
  - `docs/v0.1/02_技术架构总则.md`

### E11｜行动与布局／身份混用

- **是否已处理：`否`；处理状态：`未修改`。**
- 判定：`工程/文档不匹配`；修改方向：`工程对齐文档`。
- 处理建议：区分 schema 与实例身份的生成者及生命周期；迁移兼容后补跨局去重测试。
- 对应文件／定位：

  - `src/world3d/RunPersistenceService.gd:18–19`
  - `src/world3d/Dungeon3D.gd:1950`
  - `docs/v0.1/09_技术施工_存档结算与复活.md`

### E12｜文件存储／故障安全证明

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 处理建议：保留最后有效备份、校验临时文件并明确单写者约束；补文件故障矩阵。
- 对应文件／定位：

  - `src/core/AtomicJsonStore.gd:27–58`
  - `src/base/BaseManager.gd`
  - `docs/v0.1/09_技术施工_存档结算与复活.md`

### E13｜自动验收／存档隔离

- **是否已处理：`否`；处理状态：`未修改`。**
- 判定：`工程/文档不匹配`；修改方向：`工程对齐文档`。
- 处理建议：统一 runner 的启动前独立用户目录；把预检及 Autoload 一并隔离。
- 对应文件／定位：

  - `scripts/run_verification_suite.sh`
  - `docs/v0.1/11_测试与发布.md；AGENTS.md`

### E14｜自动验收／退出码口径

- **是否已处理：`否`；处理状态：`未修改`。**
- 判定：`工程/文档不匹配`；修改方向：`工程对齐文档`。
- 处理建议：增加场景级预期错误声明；非预期错误使聚合失败，泄漏单列。
- 对应文件／定位：

  - `scripts/run_verification_suite.sh`
  - `docs/v0.1/11_测试与发布.md`
  - `docs/v0.1/audits/evidence/core_results.json、core_output.txt`

### E15｜渲染验收／场景归类

- **是否已处理：`否`；处理状态：`未修改`。**
- 判定：`工程/文档不匹配`；修改方向：`工程对齐文档`。
- 处理建议：集中维护场景运行模式；截图用例使用真实渲染器并单独签署结果。
- 对应文件／定位：

  - `scripts/run_verification_suite.sh`
  - `tests/verification/verify_first_elite_visual.tscn`
  - `tests/verification/verify_player3d_head_accessory_visual.tscn`
  - `tests/verification/verify_wardrobe_layout_visual.tscn`
  - `docs/v0.1/11_测试与发布.md；审计 A07`

### E16｜后处理／正式验收入口

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 处理建议：补正式验证场景并登记运行模式；另做真实渲染参数验证。
- 对应文件／定位：

  - `docs/v0.1/audits/evidence/postfx_missing_scene.txt、postfx_temporary_scene.txt`
  - `docs/v0.1/11_测试与发布.md`
  - `src/postfx/PostfxOverlay.gd`

### E17｜验收超时／保护范围

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 处理建议：预检和执行均加时限；断言失败显式非零退出并保留错误阶段。
- 对应文件／定位：

  - `scripts/run_verification_suite.sh`
  - `tests/verification/verify_base_fixture_glow.tscn`
  - `docs/v0.1/11_测试与发布.md；docs/v0.1/audits/evidence/core_output.txt`

### E18｜照明参数／验收基线

- **是否已处理：`否`；处理状态：`待设计／核验`。**
- 判定：`待设计／核验`；修改方向：`核验版本后确定`。
- 处理建议：核对现行灯光设计修订；实现偏离则修代码，已批准调参则同步设计和测试。
- 对应文件／定位：

  - `docs/v0.1/13_技术施工_性能优化与热管理.md`
  - `tests/verification/verify_tower_lighting_wall_combat_regressions.gd`
  - `docs/v0.1/audits/evidence/core_output.txt`

### E19｜性能预算／实现超限

- **是否已处理：`否`；处理状态：`待设计／核验`。**
- 判定：`待设计／核验`；修改方向：`核验版本后确定`。
- 处理建议：先确定预算适用范围和设计版本；优化超限实现，必要变更先修订预算依据。
- 对应文件／定位：

  - `docs/v0.1/13_技术施工_性能优化与热管理.md`
  - `tests/verification/verify_3d_performance_budget.tscn`
  - `tests/verification/verify_full_3d_game_flow.tscn`
  - `docs/v0.1/audits/evidence/core_output.txt`

### E20｜设施材质／公共色盘

- **是否已处理：`否`；处理状态：`未修改`。**
- 判定：`工程/文档不匹配`；修改方向：`工程对齐文档`。
- 处理建议：按资产逐个核对正式版本，修复材质或导出配置后重跑专项。
- 对应文件／定位：

  - `tests/verification/verify_scene_facility_shared_palette.gd`
  - `docs/v0.1/audits/evidence/core_output.txt`

### E21｜基地表现／旧基准断言

- **是否已处理：`否`；处理状态：`待设计／核验`。**
- 判定：`待设计／核验`；修改方向：`核验版本后确定`。
- 处理建议：对照角色及设施正式版本记录；确认后同步表现规范、场景和断言。
- 对应文件／定位：

  - `tests/verification/verify_base_world_flow.gd`
  - `docs/v0.1/07_技术施工_基地设施.md`
  - `docs/v0.1/audits/evidence/core_output.txt`

### E22｜基地结构／版本标识

- **是否已处理：`否`；处理状态：`待设计／核验`。**
- 判定：`待设计／核验`；修改方向：`核验版本后确定`。
- 处理建议：核对正式结构包及替换记录；有效迁移更新验收定位，否则恢复正确引用。
- 对应文件／定位：

  - `tests/verification/verify_base99_structural_asset_integration.gd`
  - `docs/v0.1/audits/evidence/core_output.txt`

### E23｜基地墙面／坐标基线

- **是否已处理：`否`；处理状态：`待设计／核验`。**
- 判定：`待设计／核验`；修改方向：`核验版本后确定`。
- 处理建议：查对应布局设计及作者源变更；确认后更新场景或验收基准。
- 对应文件／定位：

  - `tests/verification/verify_base99_wall_content_v021.gd`
  - `docs/v0.1/audits/evidence/core_output.txt`

### E24｜基地设施／资产包数量

- **是否已处理：`否`；处理状态：`待设计／核验`。**
- 判定：`待设计／核验`；修改方向：`核验版本后确定`。
- 处理建议：按包 ID 对照正式目录、删除／替换记录，确认差集后再修代码或验收。
- 对应文件／定位：

  - `tests/verification/verify_base99_remaining_facilities_v021.gd`
  - `docs/v0.1/audits/evidence/core_output.txt`

### E25｜画质控制／参数契约

- **是否已处理：`否`；处理状态：`待补设计文档`。**
- 判定：`文档缺失`；修改方向：`先定文档，再对齐`。
- 处理建议：先冻结后处理参数、默认值、持久化及画质服务接口，再同步 UI 和测试。
- 对应文件／定位：

  - `docs/v0.1/13_技术施工_性能优化与热管理.md；docs/v0.1/MODULE_INDEX.md GRAPHICS-POSTFX`
  - `tests/verification/verify_graphics_settings_ui_flow.tscn`
  - `docs/v0.1/audits/evidence/core_output.txt`

### D01｜弹药／显示名称

- **是否已处理：`是`；处理状态：`已修改文档并核对`。**
- 判定：`已一致`；修改方向：`文档对齐工程`。
- 处理结果：已将B18名称改为“通用弹药”，保留稳定ID。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜掉落物品 B18`
  - `src/base/ItemRegistry.gd:678`
  - `docs/v0.1/04_技术施工_战斗与局内成长.md`
  - `docs/v0.1/development/2026-09-12_d01_d03_d07_d13_document_alignment.md`

### D02｜弹药／堆叠上限

- **是否已处理：`否`；处理状态：`待设计／核验`。**
- 判定：`待设计／核验`；修改方向：`先定文档，再对齐`。
- 处理建议：先确认“发／组”及目标上限，再同时修改内容表和运行定义。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜G18`
  - `docs/v0.1/audits/evidence/content_parity.json`
  - `docs/v0.1/04_技术施工_战斗与局内成长.md`

### D03｜大电池／内容 ID

- **是否已处理：`是`；处理状态：`已修改文档并核对`。**
- 判定：`已一致`；修改方向：`文档对齐工程`。
- 处理结果：已同步ID、名称、堆叠、使用动作、掉落权重、状态和事实源。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜掉落物品 A42:O46`
  - `docs/v0.1/03_技术施工_玩家与操作.md §10.3–10.6`
  - `src/base/ItemRegistry.gd:722–816`
  - `src/game/ItemUseHandler.gd`
  - `tests/verification/verify_3d_flashlight_charge_flow.gd`
  - `docs/v0.1/development/2026-09-12_d01_d03_d07_d13_document_alignment.md`

### D04｜电池组／内容 ID

- **是否已处理：`是`；处理状态：`已修改文档并核对`。**
- 判定：`已一致`；修改方向：`文档对齐工程`。
- 处理结果：已同步ID、名称、堆叠、使用动作、掉落权重、状态和事实源。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜掉落物品 A42:O46`
  - `docs/v0.1/03_技术施工_玩家与操作.md §10.3–10.6`
  - `src/base/ItemRegistry.gd:722–816`
  - `src/game/ItemUseHandler.gd`
  - `tests/verification/verify_3d_flashlight_charge_flow.gd`
  - `docs/v0.1/development/2026-09-12_d01_d03_d07_d13_document_alignment.md`

### D05｜基础手电模块／ID

- **是否已处理：`是`；处理状态：`已修改文档并核对`。**
- 判定：`已一致`；修改方向：`文档对齐工程`。
- 处理结果：已同步正式ID、类型、子类、数值、状态和事实源。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜掉落物品 A42:O46`
  - `docs/v0.1/03_技术施工_玩家与操作.md §10.3–10.6`
  - `src/base/ItemRegistry.gd:722–816`
  - `src/game/ItemUseHandler.gd`
  - `tests/verification/verify_3d_flashlight_charge_flow.gd`
  - `docs/v0.1/development/2026-09-12_d01_d03_d07_d13_document_alignment.md`

### D06｜进阶手电模块／ID

- **是否已处理：`是`；处理状态：`已修改文档并核对`。**
- 判定：`已一致`；修改方向：`文档对齐工程`。
- 处理结果：已同步正式ID、类型、子类、解锁来源、数值、状态和事实源。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜掉落物品 A42:O46`
  - `docs/v0.1/03_技术施工_玩家与操作.md §10.3–10.6`
  - `src/base/ItemRegistry.gd:722–816`
  - `src/game/ItemUseHandler.gd`
  - `tests/verification/verify_3d_flashlight_charge_flow.gd`
  - `docs/v0.1/development/2026-09-12_d01_d03_d07_d13_document_alignment.md`

### D07｜高效手电模块／ID

- **是否已处理：`是`；处理状态：`已修改文档并核对`。**
- 判定：`已一致`；修改方向：`文档对齐工程`。
- 处理结果：已同步正式ID、类型、子类、掉落来源、数值、状态和事实源。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜掉落物品 A42:O46`
  - `docs/v0.1/03_技术施工_玩家与操作.md §10.3–10.6`
  - `src/base/ItemRegistry.gd:722–816`
  - `src/game/ItemUseHandler.gd`
  - `tests/verification/verify_3d_flashlight_charge_flow.gd`
  - `docs/v0.1/development/2026-09-12_d01_d03_d07_d13_document_alignment.md`

### D08｜断刃／基地成交价

- **是否已处理：`否`；处理状态：`待设计／核验`。**
- 判定：`待设计／核验`；修改方向：`先定文档，再对齐`。
- 处理建议：补齐价格设计依据；确认 165／83 或新批准价格后同步表格与代码。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜P47:Q47`
  - `docs/v0.1/audits/evidence/content_parity.json`

### D09｜战斧／基地成交价

- **是否已处理：`否`；处理状态：`待设计／核验`。**
- 判定：`待设计／核验`；修改方向：`先定文档，再对齐`。
- 处理建议：补齐价格设计依据；确认 240／120 或新批准价格后同步两端。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜P48:Q48`
  - `docs/v0.1/audits/evidence/content_parity.json`

### D10｜普通房间钥匙／缺省价格

- **是否已处理：`否`；处理状态：`待设计／核验`。**
- 判定：`待设计／核验`；修改方向：`先定文档，再对齐`。
- 处理建议：在字段字典明确不可交易物品的 null／0 语义，再统一导出和表格。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜第21行／价格`
  - `docs/v0.1/audits/evidence/content_parity.json`

### D11｜小电池／子类字段

- **是否已处理：`否`；处理状态：`待设计／核验`。**
- 判定：`待设计／核验`；修改方向：`先定文档，再对齐`。
- 处理建议：确认 subtype 是必填语义还是派生分类；按冻结字典补字段或映射。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜第41行／子类`
  - `docs/v0.1/audits/evidence/content_parity.json`

### D12｜Boss 下行钥匙／数据形态

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 处理建议：保留目标钥匙设计；先补物品与权限计数的转换、存档及门消耗契约，再实现。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜第37行`
  - `docs/v0.1/audits/evidence/content_parity.json`
  - `docs/v0.1/09_技术施工_存档结算与复活.md`

### D13｜商店／购买物品去向

- **是否已处理：`是`；处理状态：`已修改文档并核对`。**
- 判定：`已一致`；修改方向：`文档对齐工程`。
- 处理结果：已修正A2总说明，明确99F背包与独立主基地待装载集合。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜基地商店 A2、L5:L11`
  - `src/base/BaseShopService.gd`
  - `docs/v0.1/09_技术施工_存档结算与复活.md`
  - `docs/v0.1/development/2026-09-12_d01_d03_d07_d13_document_alignment.md`

### A01｜资产台账／214 条摘要漂移

- **是否已处理：`否`；处理状态：`待设计／核验`。**
- 判定：`待设计／核验`；修改方向：`核验版本后确定`。
- 处理建议：逐批核验来源：合法且验收通过的替换→更新台账；非预期改动→恢复或重导出。
- 对应文件／定位：

  - `assets/registry/ShellStorm2_美术资产台账_v001.xlsx`
  - `docs/v0.1/audits/evidence/asset_registry_check.json`

### G01｜后处理／专项设计缺口

- **是否已处理：`否`；处理状态：`待补设计文档`。**
- 判定：`文档缺失`；修改方向：`先定文档，再对齐`。
- 处理建议：先建立参数、所有者、接口、默认值、保存／恢复、验收契约；实证记录现状。
- 对应文件／定位：

  - `src/postfx/PostfxOverlay.gd`
  - `docs/v0.1/MODULE_INDEX.md；docs/v0.1/13_技术施工_性能优化与热管理.md`

### G02｜训练场／专项设计缺口

- **是否已处理：`否`；处理状态：`待补设计文档`。**
- 判定：`文档缺失`；修改方向：`先定文档，再对齐`。
- 处理建议：冻结训练会话边界、靶标统计与装备恢复规则；补正式路径验收及开发记录。
- 对应文件／定位：

  - `src/training3d/TrainingRange3D.gd`
  - `docs/v0.1/MODULE_INDEX.md TRAINING`

### G03｜工坊／功能文档与记录

- **是否已处理：`否`；处理状态：`待补设计文档`。**
- 判定：`文档缺失`；修改方向：`先定文档，再对齐`。
- 处理建议：在现有07建立工坊专章，补版本、接口、价格来源、错误码和升级矩阵；如实补当前核验记录。
- 对应文件／定位：

  - `src/ui/WorkshopMenu.gd`
  - `docs/v0.1/07_技术施工_基地设施.md；docs/v0.1/MODULE_INDEX.md BASE-WORKSHOP`

### G04｜局内商人／交易契约缺口

- **是否已处理：`否`；处理状态：`待补设计文档`。**
- 判定：`文档缺失`；修改方向：`先定文档，再对齐`。
- 处理建议：先冻结交易命令及异常语义，再下沉 UI 业务编排并补独立验收。
- 对应文件／定位：

  - `src/ui/MerchantUI.gd`
  - `docs/v0.1/04_技术施工_战斗与局内成长.md；docs/v0.1/MODULE_INDEX.md RUN-MERCHANT`

### G05｜版本开发／设计修订追溯

- **是否已处理：`否`；处理状态：`待补设计文档`。**
- 判定：`文档缺失`；修改方向：`先定文档，再对齐`。
- 处理建议：从下一工作包建立 feature_id／设计修订／提交／验收关联；旧项只补可验证追溯，禁止倒填虚构日志。
- 对应文件／定位：

  - `docs/DOCUMENTATION_STANDARD.md`
  - `scripts/check_documentation_contracts.py`
  - `docs/v0.1/audits/evidence/commit_trace.json`
