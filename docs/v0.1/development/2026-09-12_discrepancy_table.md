# 工程、文档与开发状态表交付记录

日期：2026-09-12。记录ID：DOC-DIFF-20260912。工程版本：0.1.0。
功能范围：全模块审计的差异统计，不是新功能实现。
设计依据：用户要求按差异项目逐行比较工程与文档，并标注一致性、是否修改和修改方向；遵循[文档驱动开发规范](../../DOCUMENTATION_STANDARD.md)。
代码基线：`31ed360644768808e6faef5cd3b341b731888625`。事实来源：[工程审计](../audits/2026-09-12_engineering_audit.md)及其证据。

- 交付 Excel：保留44项跟踪，其中24项已一致、12项开发中·部分完成、2项工程/文档不匹配、3项待设计／核验、3项文档缺失；另有214条资产摘要展开明细、23项已对齐记录。资产汇总在主表只计1项，不与明细重复累加。
- 当前16项未处理方向为10项工程对齐文档、3项先确定文档再对齐、3项先核验版本；“文档对齐工程”方向已经全部处理。
- 每行列出工程现状、文档要求、判定分类、情况说明、是否已处理、修改方向、建议、处理状态、优先级和依据；当前28项已处理、16项未处理，主表支持按字段筛选及冻结表头、识别列。
- `开发中·部分完成`是版本施工进度，不计为错误或事实冲突；只有冻结口径互相冲突、或文档错误宣称已完成时才进入`工程/文档不匹配`。未冻结项目和契约缺失分别统计，不能与开发进度混算。
- 未将明确标注未施工的30张命运卡计为错误；未将214条哈希变化认定为214个损坏资产；E19、E21以及E15、E20为P3灰色暂缓项；其余有争议的数值及版本保留待核验。
- 初次交付只制作统计；截至本轮已完成E01–E03、E05–E07、E11、E13–E14、E18、E22–E24、D01、D03–D11、D13与G02–G04的对应处理。E18、D02、G03、G04仍按开发中/设计中管理。
- 验证：重新计算统计公式；逐表检查排版；导出后核对44条主表、23条已对齐记录、214组资产路径与双方完整SHA、筛选器及冻结窗格；E05/E06新增行动结算专项。未执行Excel客户端重算。

长期结构化清单保存在[差异数据](../audits/evidence/discrepancy_inventory_20260912.json)。Excel 为本次任务输出目录中的交付文件；游戏缺陷的故障证据、验收范围及限制继续以工程审计为准。
## 逐项处理状态与对应文件（全部跟踪项目）

### E01｜到达门／保存前放行

- **是否已处理：`是`；处理状态：`已修改文档`；优先级：`P0已关闭`。**
- 判定：`已一致`；修改方向：`文档已对齐工程`。
- 工程现状：FloorBundle在内存生成、验证并登记后打开到达门；保存失败不阻断，重载使用最后成功快照。
- 文档状态：05、09已改为运行态先行：完成内存校验后开门，不等待行动快照写盘。
- 差异说明：原强一致门禁与工程不一致；已按用户决定改为最终一致，原探针保留为历史证据。
- 处理结果：已完成02、05、09、11及模块状态同步；不修改运行时代码。
- 对应文件／定位：

  - `src/world3d/TowerDescent3D.gd:2196、2942`
  - `docs/v0.1/05_技术施工_关卡生成与爬楼.md；docs/v0.1/09_技术施工_存档结算与复活.md §5.4`
  - `docs/v0.1/development/2026-09-12_e01_e02_document_alignment.md`

### E02｜区段提交／提前卸载

- **是否已处理：`是`；处理状态：`已修改文档`；优先级：`P0已关闭`。**
- 判定：`已一致`；修改方向：`文档已对齐工程`。
- 工程现状：隔离前门交互先关闭后侧路线并同步卸载旧段，随后继续开门；函数无持久化回执。
- 文档状态：05、09已改为运行态先行：前门交互完成关后门、卸载旧段并继续开门，后续快照最终收敛。
- 差异说明：原跨重启不可逆提交要求与工程不一致；已按用户决定改为最终一致，不承诺未写盘状态跨重启保留。
- 处理结果：已完成02、05、09、11及模块状态同步；保留后续服务解耦方向，不增加持久化门禁。
- 对应文件／定位：

  - `src/world3d/TowerDescent3D.gd:3142`
  - `docs/v0.1/05_技术施工_关卡生成与爬楼.md；docs/v0.1/09_技术施工_存档结算与复活.md §5.5`
  - `docs/v0.1/development/2026-09-12_e01_e02_document_alignment.md`

### E03｜资源扣款／失败误报成功

- **是否已处理：`是`；处理状态：`已修改并验证`；优先级：`P0已关闭`。**
- 判定：`已一致`；修改方向：`工程已对齐文档`。
- 工程现状：仅接受正数；扣款在写盘及回读成功后返回true，失败恢复余额；revision冲突保留重新加载的权威档案。
- 文档状态：09要求：内存变化与一次写盘同时成功，否则回滚。
- 差异说明：原失败误报及内存漂移已修复并通过专项；工坊组合事务仍单列E04。
- 处理结果：已完成单次扣款收口；下一步按E04合并工坊扣款与解锁。
- 对应文件／定位：

  - `src/base/BaseManager.gd:702`
  - `tests/verification/verify_extraction_points_spend_transaction.gd`
  - `docs/v0.1/09_技术施工_存档结算与复活.md`
  - `docs/v0.1/development/2026-09-12_e03_extraction_points_transaction.md`

### E04｜工坊升级／两次独立保存

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`；优先级：`P0`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 工程现状：WorkshopMenu 先扣款，再升蓝图 Tier，两步保存后直接显示成功。
- 文档状态：09将设施升级定义为一次强一致事务。
- 差异说明：【开发到一半】静态确认扣款与解锁不是同一提交；失败可能产生半完成状态。
- 处理建议：设计升级命令，合并扣款与解锁；提交失败一起回滚，补工坊故障专项。
- 对应文件／定位：

  - `src/ui/WorkshopMenu.gd:146`
  - `src/base/BaseManager.gd:686、702`
  - `docs/v0.1/09_技术施工_存档结算与复活.md §2.1`

### E05｜撤离结算／多次提交

- **是否已处理：`是`；处理状态：`已修改并验证`；优先级：`P0已关闭`。**
- 判定：`已一致`；修改方向：`工程已对齐文档`。
- 工程现状：BaseManager.commit_run_settlement把行动统计、击杀、魂、撤离战利品和行动档清理合并为一次保存；Tower与Dungeon只在提交成功后发送完成事件。
- 文档状态：09要求原子保存长期域并结束行动，保证结算幂等。
- 差异说明：撤离结算已由多次独立保存收口为单次事务；失败整体回滚并保留可重试行动，同一事务ID不会重复发放或累计统计。
- 处理结果：已建立单次结算事务并验证写盘失败、重试、重复请求与重载幂等。
- 对应文件／定位：

  - `src/base/BaseManager.gd`
  - `src/world3d/TowerDescent3D.gd`
  - `src/world3d/Dungeon3D.gd`
  - `tests/verification/verify_run_settlement_transaction.gd`
  - `tests/verification/verify_run_settlement_transaction.tscn`
  - `docs/v0.1/09_技术施工_存档结算与复活.md`
  - `docs/v0.1/development/2026-09-12_e05_e06_run_settlement_transaction.md`
  - `scripts/run_verification_suite.sh`
  - `tests/README.md`

### E06｜死亡结算／场景多域写入

- **是否已处理：`是`；处理状态：`已修改并验证`；优先级：`P0已关闭`。**
- 判定：`已一致`；修改方向：`工程已对齐文档`。
- 工程现状：Dungeon先计算死亡损失，再由BaseManager.commit_run_settlement一次提交统计、保险中转、幂等日志和行动档清理；失败恢复背包、快捷栏及保险格。
- 文档状态：09要求死亡结果、保险及行动结束具有原子交接语义。
- 差异说明：死亡长期域已由场景多次写入收口为单次事务；只有提交成功才清空运行时保险格和切换场景，失败可用同一事务重试。
- 处理结果：已覆盖保险交接、写盘失败、重试、重复请求和重载，不重复累计失败行动或复制保险物。
- 对应文件／定位：

  - `src/base/BaseManager.gd`
  - `src/world3d/Dungeon3D.gd`
  - `tests/verification/verify_run_settlement_transaction.gd`
  - `tests/verification/verify_run_settlement_transaction.tscn`
  - `docs/v0.1/09_技术施工_存档结算与复活.md`
  - `docs/v0.1/development/2026-09-12_e05_e06_run_settlement_transaction.md`
  - `scripts/run_verification_suite.sh`
  - `tests/README.md`

### E07｜新特效池／回收回调

- **是否已处理：`是`；处理状态：`已修改并验证`；优先级：`P1已关闭`。**
- 判定：`已一致`；修改方向：`工程已对齐文档`。
- 工程现状：retired信号携带effect，池仅绑定asset_id；回调参数契约已一致，并公开active/inactive计数用于验收。
- 文档状态：14.6要求特效结束后正确回收并复用实例。
- 差异说明：已修复原三参数回调错误；专项覆盖到期回收、同实例复用、计数和场景退出清理。
- 处理结果：已修改信号连接并完成对象池生命周期专项。
- 对应文件／定位：

  - `src/vfx/VfxPool3D.gd`
  - `src/vfx/VfxEffectBase3D.gd`
  - `tests/verification/verify_vfx_pool_lifecycle.gd`
  - `tests/verification/verify_vfx_pool_lifecycle.tscn`
  - `docs/v0.1/14.6_特效系统与制作规范.md`
  - `docs/v0.1/development/2026-09-12_e07_e11_e13_e14_engineering_alignment.md`

### E08｜特效迁移／双池与旧断言

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`；优先级：`P1`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 工程现状：枪械、弹丸仍走旧池；近战与敌人走新池；近战反馈测试仍查旧池。
- 文档状态：14.6以 Prefab 注册、统一借出及回收为目标契约。
- 差异说明：【开发到一半】正式调用者与验收对象分裂；旧池 slash/impact 断言失败。
- 处理建议：依新 Prefab 契约迁移调用者及验收；迁移完成后再退役旧池。
- 对应文件／定位：

  - `docs/v0.1/14.6_特效系统与制作规范.md`
  - `src/combat3d/WeaponModel3D.gd`
  - `src/combat3d/Projectile3D.gd`
  - `tests/verification/verify_3d_melee_feedback_flow.gd`

### E09｜世界模块／独立开发边界

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`；优先级：`P1`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 工程现状：Dungeon 与 Tower 合计 9572 行；楼层、结算、UI、存档混合且共享私有状态。
- 文档状态：02要求模块有独立状态所有者、接口、数据链和验收入口。
- 差异说明：【开发到一半】已有纯计划、查询及快照服务，但世界生命周期仍难独立替换；行数不是单独判据。
- 处理建议：按楼层提交、区段、结算、UI 适配逐步抽服务；用替身测试接口边界。
- 对应文件／定位：

  - `docs/v0.1/02_技术架构总则.md`
  - `src/world3d/Dungeon3D.gd`
  - `src/world3d/TowerDescent3D.gd`
  - `docs/v0.1/audits/evidence/source_inventory.json`

### E10｜跨域写权限／事件接口

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`；优先级：`P1`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 工程现状：精英服务调用 BaseManager 私有方法并写 data；世界直接改 currency 后补发信号。
- 文档状态：02要求唯一所有者与命令／事件边界；领域提交事件仍是目标。
- 差异说明：【开发到一半】跨域可绕过规则直接写；文档目标事件未落地，不能视为已有稳定接口。
- 处理建议：集中写入权，提供命令结果与只读快照；冻结实际使用的局部事件契约。
- 对应文件／定位：

  - `src/enemy3d/EliteRosterService.gd:208`
  - `docs/v0.1/02_技术架构总则.md`
  - `审计 A05`

### E11｜行动与布局／身份混用

- **是否已处理：`是`；处理状态：`已修改并验证`；优先级：`P1已关闭`。**
- 判定：`已一致`；修改方向：`工程已对齐文档`。
- 工程现状：运行快照分别保存schema、run_id、checkpoint_id、layout_id；新行动即使复用同一种子也生成不同run_id，旧schema占位身份按种子、楼层及布局迁移。精英encounter_id使用run_id。
- 文档状态：09区分检查点、布局、行动与 schema；稳定身份用于恢复及幂等。
- 差异说明：同种子新行动的run_id不同；不同种子的布局身份不同；重载保持所有身份稳定，schema不再进入精英遭遇身份。
- 处理结果：已完成身份字段生成、旧快照兼容和跨局／重载测试。
- 对应文件／定位：

  - `src/world3d/RunPersistenceService.gd`
  - `src/world3d/Dungeon3D.gd`
  - `tests/verification/verify_room_graph_persistence_services.gd`
  - `docs/v0.1/09_技术施工_存档结算与复活.md`
  - `docs/v0.1/development/2026-09-12_e07_e11_e13_e14_engineering_alignment.md`

### E12｜文件存储／故障安全证明

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`；优先级：`P1`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 工程现状：临时写入未先验证；旧备份先删除；revision 读写之间没有进程锁。
- 文档状态：09要求校验、原子保存、失败恢复与冲突保护。
- 差异说明：【开发到一半】静态存在备份及竞争窗口；未注入磁盘满、rename 失败或真实多进程竞争。
- 处理建议：保留最后有效备份、校验临时文件并明确单写者约束；补文件故障矩阵。
- 对应文件／定位：

  - `src/core/AtomicJsonStore.gd:27–58`
  - `src/base/BaseManager.gd`
  - `docs/v0.1/09_技术施工_存档结算与复活.md`
  - `审计 A06`

### E13｜自动验收／存档隔离

- **是否已处理：`是`；处理状态：`已修改并验证`；优先级：`P1已关闭`。**
- 判定：`已一致`；修改方向：`工程已对齐文档`。
- 工程现状：runner为每次执行创建独立项目壳和唯一Godot用户目录；预检与正式场景Autoload从启动前即隔离正式user://。
- 文档状态：现行11及 AGENTS 要求验收先隔离正式玩家数据。
- 差异说明：统一入口已消除场景内晚设test_mode/save_path的启动窗口，并在结束后清理隔离目录。
- 处理结果：已实现启动前隔离，并用runner契约场景验证OS.get_user_data_dir。
- 对应文件／定位：

  - `scripts/run_verification_suite.sh`
  - `tests/verification/verify_verification_runner_contract.gd`
  - `tests/verification/verify_verification_runner_contract.tscn`
  - `docs/v0.1/11_测试与发布.md`
  - `tests/README.md`
  - `docs/v0.1/development/2026-09-12_e07_e11_e13_e14_engineering_alignment.md`

### E14｜自动验收／退出码口径

- **是否已处理：`是`；处理状态：`已修改并验证`；优先级：`P1已关闭`。**
- 判定：`已一致`；修改方向：`工程已对齐文档`。
- 工程现状：runner捕获预检和场景完整日志；未声明ERROR/SCRIPT ERROR返回3，资源泄漏单列返回4，已声明故障注入错误才允许通过。
- 文档状态：11及文档标准要求非预期脚本错误不可计为无错误验收通过。
- 差异说明：退出0不再是唯一通过条件；场景级expected_errors提供可审查的预期错误声明。
- 处理结果：已增加日志分类器、runner门禁、预期错误示例及分类器专项。
- 对应文件／定位：

  - `scripts/run_verification_suite.sh`
  - `scripts/check_verification_log.py`
  - `tests/tooling/test_check_verification_log.py`
  - `tests/verification/expected_errors/verify_extraction_points_spend_transaction.txt`
  - `docs/v0.1/11_测试与发布.md`
  - `tests/README.md`
  - `docs/v0.1/development/2026-09-12_e07_e11_e13_e14_engineering_alignment.md`

### E15｜渲染验收／场景归类

- **是否已处理：`否`；处理状态：`暂不处理（已降级）`；优先级：`P3暂缓`。**
- 判定：`工程/文档不匹配`；修改方向：`工程对齐文档`。
- 工程现状：部分截图场景未进 renderer 清单；base_fixture_glow 在 core 读取图像。
- 文档状态：11区分无头逻辑测试与真实渲染验收。
- 差异说明：headless 套件包含真实截图操作；不能证明真实画面合格。
- 暂缓决定：按用户决定降低优先级，本阶段暂不处理；保留现状和证据，后续单独排期。
- 对应文件／定位：

  - `scripts/run_verification_suite.sh`
  - `tests/verification/verify_first_elite_visual.tscn`
  - `tests/verification/verify_player3d_head_accessory_visual.tscn`
  - `tests/verification/verify_wardrobe_layout_visual.tscn`
  - `docs/v0.1/11_测试与发布.md；审计 A07`

### E16｜后处理／正式验收入口

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`；优先级：`P1`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 工程现状：有后处理验证 .gd，没有同名 .tscn；正式场景命令 LOAD_FAILURE。
- 文档状态：11的统一验证流程要求可运行的正式场景入口。
- 差异说明：【开发到一半】临时包装输出 POSTFX_OVERLAY_RUNTIME_OK，仅证明脚本路径可运行。
- 处理建议：补正式验证场景并登记运行模式；另做真实渲染参数验证。
- 对应文件／定位：

  - `docs/v0.1/audits/evidence/postfx_missing_scene.txt、postfx_temporary_scene.txt`
  - `docs/v0.1/11_测试与发布.md`
  - `src/postfx/PostfxOverlay.gd`

### E17｜验收超时／保护范围

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`；优先级：`P1`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 工程现状：预加载在看门狗外；fixture_glow 断言失败后未退出，最终超时 180 秒。
- 文档状态：11要求失败可诊断、测试有受控退出与时限。
- 差异说明：【开发到一半】用例失败路径与预检阶段没有完整统一退出契约。
- 处理建议：预检和执行均加时限；断言失败显式非零退出并保留错误阶段。
- 对应文件／定位：

  - `scripts/run_verification_suite.sh`
  - `tests/verification/verify_base_fixture_glow.tscn`
  - `docs/v0.1/11_测试与发布.md；docs/v0.1/audits/evidence/core_output.txt`

### E18｜电力系统／手电与基地能源

- **是否已处理：`是`；处理状态：`开发中（设计已建立）`；优先级：`P1开发中`。**
- 判定：`开发中·部分完成`；修改方向：`先定文档，再对齐`。
- 工程现状：当前手电按装备模块独立耗电：基础/加强/节能满电时长300/420/600秒；基地只暂停耗电。基地电力上限100，每游戏小时恢复4，恢复舱一次消费25。
- 文档状态：15.1已建立统一电力系统设计：基地电力与手电电力同属POWER-SYSTEM、分别结算；现有行为为当前事实，基地灯光、应急照明及设施负载标为待完善。
- 差异说明：【开发到一半】统一电力系统设计与现行数据已建立；基地电力对灯光和设施负载的表现尚未施工，不属于工程/文档错误。
- 处理结果：已新增独立电力系统设计并登记模块边界、接口、数据、失败语义和独立验收；后续按15.1实现基地用电表现。
- 对应文件／定位：

  - `docs/v0.1/15.1_技术施工_电力系统.md`
  - `docs/v0.1/15_技术施工_时间日夜与基地能源.md`
  - `src/base/BaseEnergyService.gd`
  - `src/player3d/PlayerFlashlight3D.gd`
  - `tests/verification/verify_tower_lighting_wall_combat_regressions.gd`
  - `docs/v0.1/development/2026-09-12_e18_e24_d02_d11_design_alignment.md`

### E19｜性能预算／实现超限

- **是否已处理：`否`；处理状态：`暂不处理（完整版后验收）`；优先级：`P3暂缓`。**
- 判定：`待设计／核验`；修改方向：`核验版本后确定`。
- 工程现状：旧性能专项曾记录HUD、预览和总节点超旧预算；本轮未重跑性能验收，也未改阈值。
- 文档状态：13已注明：首个完整版完成后再冻结场景范围、目标设备、采样方式和正式验收标准。
- 差异说明：当前项目尚未到首个完整版性能签署阶段；旧结果保留为历史观察，不作为本阶段红色阻断。
- 暂缓决定：暂缓性能预算验收；首个完整版功能冻结后建立正式性能矩阵并在目标设备执行。
- 对应文件／定位：

  - `docs/v0.1/13_技术施工_性能优化与热管理.md`
  - `tests/verification/verify_3d_performance_budget.tscn`
  - `tests/verification/verify_full_3d_game_flow.tscn`
  - `docs/v0.1/development/2026-09-12_e18_e24_d02_d11_design_alignment.md`

### E20｜设施材质／公共色盘

- **是否已处理：`否`；处理状态：`暂不处理（已降级）`；优先级：`P3暂缓`。**
- 判定：`工程/文档不匹配`；修改方向：`工程对齐文档`。
- 工程现状：部分 v002／v003 材质缺公共色盘或不是最近邻采样，专项报 24 项问题。
- 文档状态：设施资产生产规范及公共色盘验收要求共享色盘与规定采样。
- 差异说明：当前正式引用未通过材质契约；本次未完成逐资产视觉核验。
- 暂缓决定：按用户决定降低优先级，本阶段暂不处理；保留现状和证据，后续单独排期。
- 对应文件／定位：

  - `tests/verification/verify_scene_facility_shared_palette.gd`
  - `docs/v0.1/audits/evidence/core_output.txt`
  - `审计 A07／核心回归表`

### E21｜基地表现／旧基准断言

- **是否已处理：`否`；处理状态：`暂不处理（已降级）`；优先级：`P3暂缓`。**
- 判定：`待设计／核验`；修改方向：`核验版本后确定`。
- 工程现状：基地表现专项仍引用旧节点、移动动画与locked环基线；本轮没有批准新的完整表现目标。
- 文档状态：07已将本项注明为待澄清；在基地表现版本冻结前保留现状和旧证据。
- 差异说明：需求边界尚不清晰，无法判断该把当前表现改向哪一版；属于暂缓核验，不显示为红色错误。
- 暂缓决定：与E15/E20同级暂缓；以后先冻结基地表现版本，再同步场景、规范与断言。
- 对应文件／定位：

  - `docs/v0.1/07_技术施工_基地设施.md`
  - `tests/verification/verify_base_world_flow.gd`
  - `docs/v0.1/development/2026-09-12_e18_e24_d02_d11_design_alignment.md`

### E22｜基地结构／版本标识

- **是否已处理：`是`；处理状态：`已修改并验证`；优先级：`P1已关闭`。**
- 判定：`已一致`；修改方向：`文档对齐工程`。
- 工程现状：当前正式布局以asset_import_manifest的base99_source_policy、v026主源和现行运行布局为准；楼梯使用V023现行结构ID。
- 文档状态：10已明确当前资产账本优先，V021旧标识与被替换节点均标为（旧资产）。
- 差异说明：原专项把被替换的V021楼梯标识当作当前契约；现已按当前账本更新验收并通过。
- 处理结果：核对当前清单与场景引用，更新结构专项到现行结构ID和9个结构子节点。
- 对应文件／定位：

  - `assets/art/asset_import_manifest_v001.json`
  - `assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d_v002.tscn`
  - `tests/verification/verify_base99_structural_asset_integration.gd`
  - `docs/v0.1/10_资产与内容规范.md`
  - `docs/v0.1/development/2026-09-12_e18_e24_d02_d11_design_alignment.md`

### E23｜基地墙面／坐标基线

- **是否已处理：`是`；处理状态：`已修改并验证`；优先级：`P1已关闭`。**
- 判定：`已一致`；修改方向：`文档对齐工程`。
- 工程现状：当前v022墙面账本和运行场景采用南墙资料板(-14.7555,4.2925,4.29)与WORK_TOGETHER(14.527748,4.72,8.45)。
- 文档状态：10已规定现行运行布局与资产账本为准，旧V021坐标标为（旧资产）。
- 差异说明：旧坐标断言属于旧资产；现已按当前墙面账本更新验收并通过。
- 处理结果：将墙面专项改为核验当前v022坐标，不回退已批准的现行场景。
- 对应文件／定位：

  - `assets/art/asset_import_manifest_v001.json`
  - `assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d_v002.tscn`
  - `tests/verification/verify_base99_wall_content_v021.gd`
  - `docs/v0.1/10_资产与内容规范.md`
  - `docs/v0.1/development/2026-09-12_e18_e24_d02_d11_design_alignment.md`

### E24｜基地设施／资产包数量

- **是否已处理：`是`；处理状态：`已修改并验证`；优先级：`P1已关闭`。**
- 判定：`已一致`；修改方向：`文档对齐工程`。
- 工程现状：当前remaining facilities v004总装为45个根子节点，其中1个场景VFX、35个具有实体阻挡；设施包装可在嵌套层保留ImportedModel和碰撞。
- 文档状态：10已规定当前总装与账本为准，旧46包基线标为（旧资产）。
- 差异说明：46包断言属于旧资产；现已按v004总装元数据、嵌套包装和实际碰撞结构更新验收并通过。
- 处理结果：更新设施专项到45包现行总装，并递归核验包装内模型、碰撞和collision_policy。
- 对应文件／定位：

  - `assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities_v021/env_base99_remaining_facilities_root_top3d_v004.tscn`
  - `tests/verification/verify_base99_remaining_facilities_v021.gd`
  - `docs/v0.1/10_资产与内容规范.md`
  - `docs/v0.1/development/2026-09-12_e18_e24_d02_d11_design_alignment.md`

### E25｜画质控制／参数契约

- **是否已处理：`否`；处理状态：`待补设计文档`；优先级：`P1`。**
- 判定：`文档缺失`；修改方向：`先定文档，再对齐`。
- 工程现状：当前画质 UI 未满足专项要求的 9 项效果控制；新后处理另有参数路径。
- 文档状态：旧设计条目与当前 9 项测试要求未形成统一完整参数清单。
- 差异说明：文档、UI 与测试三方口径不一致；不能仅按控件数量判定玩法目标。
- 处理建议：先冻结后处理参数、默认值、持久化及画质服务接口，再同步 UI 和测试。
- 对应文件／定位：

  - `docs/v0.1/13_技术施工_性能优化与热管理.md；docs/v0.1/MODULE_INDEX.md GRAPHICS-POSTFX`
  - `tests/verification/verify_graphics_settings_ui_flow.tscn`
  - `docs/v0.1/audits/evidence/core_output.txt`

### D01｜弹药／显示名称

- **是否已处理：`是`；处理状态：`已修改文档并核对`；优先级：`P2已关闭`。**
- 判定：`已一致`；修改方向：`文档对齐工程`。
- 工程现状：item_ammo_pack运行名称为“通用弹药”。
- 文档状态：掉落物品B18已改为“通用弹药”；D02仍单独跟踪堆叠上限。
- 差异说明：原显示名差异已消除；本项不包含尚未冻结的999发堆叠上限。
- 处理结果：已将B18名称改为“通用弹药”，保留稳定ID。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜掉落物品 B18`
  - `src/base/ItemRegistry.gd:678`
  - `docs/v0.1/04_技术施工_战斗与局内成长.md`
  - `docs/v0.1/development/2026-09-12_d01_d03_d07_d13_document_alignment.md`

### D02｜弹药／堆叠上限

- **是否已处理：`是`；处理状态：`已对齐现行值；设计中`；优先级：`P1开发中`。**
- 判定：`开发中·部分完成`；修改方向：`先定文档，再对齐`。
- 工程现状：item_ammo_pack以“发”为数量单位，当前stack_max=999。
- 文档状态：04 §6.5与内容库G18已登记现行上限999；最终弹药平衡仍标为设计中。
- 差异说明：【开发到一半】现行工程和表格已一致；999只是v0.1运行上限，最终容量和掉落节奏尚未冻结。
- 处理结果：将弹药堆叠并入枪械设计，记录现行999与后续平衡待设计，内容库同步G18。
- 对应文件／定位：

  - `src/base/ItemRegistry.gd`
  - `docs/v0.1/04_技术施工_战斗与局内成长.md §6.5`
  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜G18`
  - `docs/v0.1/development/2026-09-12_e18_e24_d02_d11_design_alignment.md`

### D03｜大电池／内容 ID

- **是否已处理：`是`；处理状态：`已修改文档并核对`；优先级：`P1已关闭`。**
- 判定：`已一致`；修改方向：`文档对齐工程`。
- 工程现状：运行注册表与内容表均使用item_battery_l；75%恢复、stack_max=5及运行掉落已登记。
- 文档状态：掉落物品A42及玩家手电章节已同步正式ID、运行字段和[已实装]状态。
- 差异说明：旧设计ID battery_l及未实装状态已由正式运行事实取代。
- 处理结果：已同步ID、名称、堆叠、使用动作、掉落权重、状态和事实源。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜掉落物品 A42:O46`
  - `docs/v0.1/03_技术施工_玩家与操作.md §10.3–10.6`
  - `src/base/ItemRegistry.gd:722–816`
  - `src/game/ItemUseHandler.gd`
  - `tests/verification/verify_3d_flashlight_charge_flow.gd`
  - `docs/v0.1/development/2026-09-12_d01_d03_d07_d13_document_alignment.md`

### D04｜电池组／内容 ID

- **是否已处理：`是`；处理状态：`已修改文档并核对`；优先级：`P1已关闭`。**
- 判定：`已一致`；修改方向：`文档对齐工程`。
- 工程现状：运行注册表与内容表均使用item_cell_pack；100%恢复、stack_max=3及运行掉落已登记。
- 文档状态：掉落物品A43及玩家手电章节已同步正式ID、名称“电芯包”、运行字段和[已实装]状态。
- 差异说明：旧设计ID cell_pack、名称“能量包”及未实装状态已由正式运行事实取代。
- 处理结果：已同步ID、名称、堆叠、使用动作、掉落权重、状态和事实源。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜掉落物品 A42:O46`
  - `docs/v0.1/03_技术施工_玩家与操作.md §10.3–10.6`
  - `src/base/ItemRegistry.gd:722–816`
  - `src/game/ItemUseHandler.gd`
  - `tests/verification/verify_3d_flashlight_charge_flow.gd`
  - `docs/v0.1/development/2026-09-12_d01_d03_d07_d13_document_alignment.md`

### D05｜基础手电模块／ID

- **是否已处理：`是`；处理状态：`已修改文档并核对`；优先级：`P1已关闭`。**
- 判定：`已一致`；修改方向：`文档对齐工程`。
- 工程现状：正式物品ID为item_flashlight_basic，内部module_id=basic；默认模块已接入运行与存档。
- 文档状态：掉落物品A44及玩家手电章节已区分正式物品ID与内部module_id，并标记[已实装]。
- 差异说明：旧占位ID及未实装状态已更新，物品ID与模块内部ID不再混用。
- 处理结果：已同步正式ID、类型、子类、数值、状态和事实源。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜掉落物品 A42:O46`
  - `docs/v0.1/03_技术施工_玩家与操作.md §10.3–10.6`
  - `src/base/ItemRegistry.gd:722–816`
  - `src/game/ItemUseHandler.gd`
  - `tests/verification/verify_3d_flashlight_charge_flow.gd`
  - `docs/v0.1/development/2026-09-12_d01_d03_d07_d13_document_alignment.md`

### D06｜进阶手电模块／ID

- **是否已处理：`是`；处理状态：`已修改文档并核对`；优先级：`P1已关闭`。**
- 判定：`已一致`；修改方向：`文档对齐工程`。
- 工程现状：正式物品ID为item_flashlight_advanced，内部module_id=advanced；Tier 1解锁、工坊切换与存档恢复已接入。
- 文档状态：掉落物品A45及玩家手电章节已同步正式ID、0.7143×／1.20×数值和[已实装]状态。
- 差异说明：旧占位ID、价格和未实装状态已按运行注册表及专项事实更新。
- 处理结果：已同步正式ID、类型、子类、解锁来源、数值、状态和事实源。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜掉落物品 A42:O46`
  - `docs/v0.1/03_技术施工_玩家与操作.md §10.3–10.6`
  - `src/base/ItemRegistry.gd:722–816`
  - `src/game/ItemUseHandler.gd`
  - `tests/verification/verify_3d_flashlight_charge_flow.gd`
  - `docs/v0.1/development/2026-09-12_d01_d03_d07_d13_document_alignment.md`

### D07｜高效手电模块／ID

- **是否已处理：`是`；处理状态：`已修改文档并核对`；优先级：`P1已关闭`。**
- 判定：`已一致`；修改方向：`文档对齐工程`。
- 工程现状：正式物品ID为item_flashlight_efficient，内部module_id=efficient；掉落、带回99F解锁及存档已接入。
- 文档状态：掉落物品A46及玩家手电章节已同步正式ID、0.50×／0.85×数值和[已实装]状态。
- 差异说明：旧占位ID、价格和未实装状态已按运行注册表及专项事实更新。
- 处理结果：已同步正式ID、类型、子类、掉落来源、数值、状态和事实源。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜掉落物品 A42:O46`
  - `docs/v0.1/03_技术施工_玩家与操作.md §10.3–10.6`
  - `src/base/ItemRegistry.gd:722–816`
  - `src/game/ItemUseHandler.gd`
  - `tests/verification/verify_3d_flashlight_charge_flow.gd`
  - `docs/v0.1/development/2026-09-12_d01_d03_d07_d13_document_alignment.md`

### D08｜断刃／基地成交价

- **是否已处理：`是`；处理状态：`已设计并对齐`；优先级：`P2已关闭`。**
- 判定：`已一致`；修改方向：`先定文档，再对齐`。
- 工程现状：weapon_greatblade运行价格为买入165、卖出83。
- 文档状态：04价格矩阵与内容库P47:Q47均为165/83。
- 差异说明：此前缺少可追溯价格设计；现已补充价值梯度并同步表格。
- 处理结果：采用165/83：高于基础近战，出售取买入价约50%并向上取整。
- 对应文件／定位：

  - `src/base/ItemRegistry.gd`
  - `docs/v0.1/04_技术施工_战斗与局内成长.md §9.3`
  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜P47:Q47`
  - `docs/v0.1/development/2026-09-12_e18_e24_d02_d11_design_alignment.md`

### D09｜战斧／基地成交价

- **是否已处理：`是`；处理状态：`已设计并对齐`；优先级：`P2已关闭`。**
- 判定：`已一致`；修改方向：`先定文档，再对齐`。
- 工程现状：weapon_waraxe运行价格为买入240、卖出120。
- 文档状态：04价格矩阵与内容库P48:Q48均为240/120。
- 差异说明：此前缺少可追溯价格设计；现已补充价值梯度并同步表格。
- 处理结果：采用240/120：作为更高价值重型近战，出售取买入价50%。
- 对应文件／定位：

  - `src/base/ItemRegistry.gd`
  - `docs/v0.1/04_技术施工_战斗与局内成长.md §9.3`
  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜P48:Q48`
  - `docs/v0.1/development/2026-09-12_e18_e24_d02_d11_design_alignment.md`

### D10｜普通房间钥匙／缺省价格

- **是否已处理：`是`；处理状态：`已设计并对齐`；优先级：`P2已关闭`。**
- 判定：`已一致`；修改方向：`先定文档，再对齐`。
- 工程现状：item_room_key现行参考价值40、基地出售20，不进入普通购买货架；Boss/任务钥匙不可出售。
- 文档状态：04与内容库第21行已写入40/20及交易边界。
- 差异说明：缺省价格已变成明确可出售价格，交易边界已冻结。
- 处理结果：新增普通房间钥匙价格40/20，并在注册表、表格和商店专项中验证。
- 对应文件／定位：

  - `src/base/ItemRegistry.gd`
  - `tests/verification/verify_base_shop_save_flow.gd`
  - `docs/v0.1/04_技术施工_战斗与局内成长.md §9.3`
  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜第21行`
  - `docs/v0.1/development/2026-09-12_e18_e24_d02_d11_design_alignment.md`

### D11｜小电池／子类字段

- **是否已处理：`是`；处理状态：`已修改并验证`；优先级：`P2已关闭`。**
- 判定：`已一致`；修改方向：`工程对齐文档`。
- 工程现状：item_battery_s现已显式声明subtype=battery。
- 文档状态：内容库第41行子类为battery。
- 差异说明：子类语义已确认并在运行注册表补齐，工程与内容库一致。
- 处理结果：补充运行时subtype字段，并加入目录专项断言。
- 对应文件／定位：

  - `src/base/ItemRegistry.gd`
  - `tests/verification/verify_base_shop_save_flow.gd`
  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜第41行`
  - `docs/v0.1/development/2026-09-12_e18_e24_d02_d11_design_alignment.md`

### D12｜Boss 下行钥匙／数据形态

- **是否已处理：`否`；处理状态：`部分完成（待续开发）`；优先级：`P1`。**
- 判定：`开发中·部分完成`；修改方向：`工程对齐文档`。
- 工程现状：ItemRegistry 无 item_boss_descent_key；Tower 用专门计数授予下行权限。
- 文档状态：掉落物品第 37 行设计冻结了专用钥匙 ID，状态为未实装。
- 差异说明：【开发到一半】计数式权限与目标物品链不同；文档已注明未实装，不属于虚报完成。
- 处理建议：保留目标钥匙设计；先补物品与权限计数的转换、存档及门消耗契约，再实现。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜第37行`
  - `docs/v0.1/audits/evidence/content_parity.json`
  - `docs/v0.1/09_技术施工_存档结算与复活.md`

### D13｜商店／购买物品去向

- **是否已处理：`是`；处理状态：`已修改文档并核对`；优先级：`P2已关闭`。**
- 判定：`已一致`；修改方向：`文档对齐工程`。
- 工程现状：正式99F购买进入当前I键背包；独立主基地使用待装载集合。
- 文档状态：基地商店A2已同步购买去向，L5:L11继续保持“当前I键背包”。
- 差异说明：A2与行记录及工程的购买去向冲突已消除。
- 处理结果：已修正A2总说明，明确99F背包与独立主基地待装载集合。
- 对应文件／定位：

  - `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx｜基地商店 A2、L5:L11`
  - `src/base/BaseShopService.gd`
  - `docs/v0.1/09_技术施工_存档结算与复活.md`
  - `docs/v0.1/development/2026-09-12_d01_d03_d07_d13_document_alignment.md`

### A01｜资产台账／214 条摘要漂移

- **是否已处理：`否`；处理状态：`待设计／核验`；优先级：`P1`。**
- 判定：`待设计／核验`；修改方向：`核验版本后确定`。
- 工程现状：418 条登记中，214 个可解析单文件的实际 SHA-256 与台账不同。
- 文档状态：台账记录旧摘要，按规范应能追溯已验收资产版本与正式引用。
- 差异说明：差异已逐文件确认；不等于 214 个损坏资产。完整行、路径和双方摘要见资产明细。
- 处理建议：逐批核验来源：合法且验收通过的替换→更新台账；非预期改动→恢复或重导出。
- 对应文件／定位：

  - `assets/registry/ShellStorm2_美术资产台账_v001.xlsx`
  - `docs/v0.1/audits/evidence/asset_registry_check.json`
  - `审计 A09`

### G01｜后处理／专项设计缺口

- **是否已处理：`否`；处理状态：`待补设计文档`；优先级：`P1`。**
- 判定：`文档缺失`；修改方向：`先定文档，再对齐`。
- 工程现状：PostfxOverlay 及调参入口已存在，并有脚本探针。
- 文档状态：功能索引标注缺完整专项设计、参数契约和正式验收闭环。
- 差异说明：工程先形成参数及实现，文档无法完整指导独立开发。
- 处理建议：先建立参数、所有者、接口、默认值、保存／恢复、验收契约；实证记录现状。
- 对应文件／定位：

  - `src/postfx/PostfxOverlay.gd`
  - `docs/v0.1/MODULE_INDEX.md；docs/v0.1/13_技术施工_性能优化与热管理.md`
  - `审计 A10`

### G02｜独立训练场／测试功能文档

- **是否已处理：`是`；处理状态：`已新建设计文档并验证`；优先级：`P2已关闭`。**
- 判定：`已一致`；修改方向：`先定文档，再对齐`。
- 工程现状：TrainingRange3D可独立启动；现有10枪身、8弹药模块、59组合、三类靶标、统计、重置、退出、暂停和BaseData隔离。
- 文档状态：11.1已建立测试类功能独立契约，功能版本1.0标为已完成，并列出边界、接口、失败规则与验收入口。
- 差异说明：原缺少独立设计与逐功能记录；现已按当前工程建立1.0文档并由专项复核。
- 处理结果：新增11.1训练场文档，登记模块索引和开发记录；不修改现有玩法实现。
- 对应文件／定位：

  - `docs/v0.1/11.1_测试功能_独立训练场.md`
  - `src/training3d/TrainingRange3D.gd`
  - `scenes/TrainingRange3D.tscn`
  - `tests/verification/verify_training_range_3d_flow.gd`
  - `docs/v0.1/development/2026-09-12_g02_g04_independent_feature_docs.md`

### G03｜枪械工坊／独立玩法文档

- **是否已处理：`是`；处理状态：`开发中（独立文档已建立）`；优先级：`P1开发中`。**
- 判定：`开发中·部分完成`；修改方向：`先定文档，再对齐`。
- 工程现状：WorkshopMenu已提供三类蓝图Tier、成本与手电模块切换；BaseManager保存余额、Tier和模块，但升级仍由UI先扣款再写Tier。
- 文档状态：07.1已建立独立玩法文档，记录当前功能、所有者、数据链、接口和目标原子升级事务，状态为开发中。
- 差异说明：【开发到一半】功能文档缺口已补；升级组合事务、配置化成本与独立故障专项仍未完成。
- 处理结果：新增07.1枪械工坊文档并登记模块索引；保留E04作为后续工程任务。
- 对应文件／定位：

  - `docs/v0.1/07.1_玩法系统_枪械工坊.md`
  - `src/ui/WorkshopMenu.gd`
  - `src/base/BaseManager.gd`
  - `docs/v0.1/07_技术施工_基地设施.md`
  - `docs/v0.1/development/2026-09-12_g02_g04_independent_feature_docs.md`

### G04｜局内商人／独立玩法文档

- **是否已处理：`是`；处理状态：`开发中（独立文档已建立）`；优先级：`P1开发中`。**
- 判定：`开发中·部分完成`；修改方向：`先定文档，再对齐`。
- 工程现状：MerchantUI已实现分层候选、最多6件货架、±10%价格、容量和魂检查、背包失败返魂、成交移除及交易撤离条件。
- 文档状态：04.1已建立独立玩法文档，记录现行链路、所有者、事件、失败语义和目标交易事务，状态为开发中。
- 差异说明：【开发到一半】功能文档缺口已补；商人会话服务、跨域原子提交、重载规则与独立专项仍未完成。
- 处理结果：新增04.1局内商人文档并登记模块索引；后续从UI提取会话和购买事务。
- 对应文件／定位：

  - `docs/v0.1/04.1_玩法系统_局内商人.md`
  - `src/ui/MerchantUI.gd`
  - `src/game/LootModule.gd`
  - `src/world3d/Dungeon3D.gd`
  - `docs/v0.1/development/2026-09-12_g02_g04_independent_feature_docs.md`

### G05｜版本开发／设计修订追溯

- **是否已处理：`否`；处理状态：`待补设计文档`；优先级：`P1`。**
- 判定：`文档缺失`；修改方向：`先定文档，再对齐`。
- 工程现状：已建立文档结构检查，但尚未接 CI／Hook；历史提交缺逐功能设计修订映射。
- 文档状态：文档标准要求设计修订→实现基线→验证结果→开发记录可追溯。
- 差异说明：35 个 src 提交有 15 个未同提交改 docs，仅为线索，不能单凭该数认定违规。
- 处理建议：从下一工作包建立 feature_id／设计修订／提交／验收关联；旧项只补可验证追溯，禁止倒填虚构日志。
- 对应文件／定位：

  - `docs/DOCUMENTATION_STANDARD.md`
  - `scripts/check_documentation_contracts.py`
  - `docs/v0.1/audits/evidence/commit_trace.json`
