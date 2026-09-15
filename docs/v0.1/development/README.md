# v0.1 开发记录

工程版本：0.1.0。设计、规范与目标见 [设计目录](../design/README.md)；本目录仅保存交付事实。

- [版本开发日志](CHANGELOG.md)：按交付记变更，新增记录使用 [模板](../../templates/development_record.md)。
- [WORLD-BLOCKS 四区块场景树与资产目录整理](2026-09-13_world_level_blocks.md)：统一天台、基地、首关战斗与楼梯区块，简化运行名并同步 Blender 对照和资产台账。
- [Battle 与 Stairs 白盒目录归一](2026-09-14_battle_stairs_whitebox_relocation.md)：将98–95F战斗区和楼梯区重新定性为白盒阶段，统一数据、Blender输出和效果图目录。
- [楼梯间 Godot 反推与正式 Blender 源](2026-09-14_stairs_formal_blender_from_godot.md)：按当前12米楼梯GLB反推白盒合同，生成只含两个楼梯间资产包的正式源且不重导入Godot。
- [楼梯间参考图美术深化 v016](2026-09-14_stairs_reference_art_v016.md)：严格保留 v015 楼梯空间与接口，在原位增加工业墙板、管线、标识、灯带、灯光和固定验收镜头；Blender 材质/UV专项通过，未导入Godot。
- [楼梯间通用组件重整与栏杆修复 v017](2026-09-14_stairs_component_reclassification_v017.md)：墙、地板、楼梯收口为三个通用组件，装饰按七类内容组件整理；不改变 v016 组合与坐标，并按踏步真实边界重建栏杆。
- [楼梯间主墙、删墙、栏杆贴边与二楼墙高修复 v018](2026-09-14_stairs_wall_railing_height_v018.md)：主装饰迁到指定墙面，移除标注位置的一二楼墙段，将楼板栏杆落到边缘并统一二楼墙高；保留 v017 组件边界。
- [楼梯间对面留空墙位纠正 v019](2026-09-14_stairs_opposite_wall_opening_v019.md)：恢复 v018 误删的右侧双层墙段，将开口改到用户补充截图指定的左侧首跨；其它已确认修改保持锁定。
- [楼梯间 Blender 美术源目录规范化 v019](2026-09-14_stairs_art_source_storage_v019.md)：将 v019 建立为项目资产目录中的唯一美术源单元，源文件、组件清单、验收图与 QA 按职责对应存放。
- [楼梯间墙地与墙面配件深化 v020](2026-09-14_stairs_wall_floor_detail_v020.md)：保持原组合与十类组件，重做参考墙面附件、墙板和地板表面；117个对象锁定与严格UV验收通过，未导入Godot。
- [楼梯间复制、反向装配与99→98层对应摆放 v021](2026-09-15_stairs_dual_assembly_v021.md)：将完整楼梯间复制为两个独立装配体，按区块合同相反朝向放置到100→99与99→98层，并保持十类组件归档不变。
- [楼梯间 v021 正式导入 Godot](2026-09-15_stairwell_art_v002_godot_import.md)：导出两份GLB v002，以PackedScene替换临时楼梯资产，同步碰撞、共享色盘、台账与真实渲染验收。
- [局内关卡01-顶部数据库命名规范](2026-09-14_level01_top_database_naming.md)：将稳定的两位数字编号与可变设定名拆分，保持Battle节点、AssetID和文件路径不变。
- [白模JSON对齐3Dgame-design](2026-09-14_whitebox_3dgame_design_schema.md)：Battle与Stairs白模数据升级为工具可直接读取的v3场景文档，项目合同集中到`projectMetadata`。
- [Blender 原生关卡搭建插件](2026-09-14_blender_level_builder_addon.md)：以 `.blend` 为编辑事实所有者，提供组件库、参数化可编辑白盒、规范Collection和磁盘资产包镜像；r2 改为单网格并锚点对齐游戏资产、修复吸附、增强预览。
- [本次工程与文档审计记录](2026-09-12_documentation_audit.md)。
- [工程、文档与开发状态表交付记录](2026-09-12_discrepancy_table.md)：44项跟踪按已一致、开发中·部分完成、工程/文档不匹配、待设计／核验和文档缺失分类，另含214条资产展开明细。
- [E05/E06行动结算单次事务](2026-09-12_e05_e06_run_settlement_transaction.md)：成功撤离与死亡统一为一次原子、可重试、跨重载幂等的长期结算。
- [E07/E11/E13/E14工程对齐](2026-09-12_e07_e11_e13_e14_engineering_alignment.md)：修复VFX回收、行动身份、验收存档隔离及错误日志门禁；E15/E20降级暂缓。
- [E18–E24与D02–D11设计对齐](2026-09-12_e18_e24_d02_d11_design_alignment.md)：建立开发中的独立电力系统设计，暂缓E19/E21，按当前资产账本关闭E22–E24，并补齐弹药、价格与物品子类契约。
- [G02–G04独立功能文档](2026-09-12_g02_g04_independent_feature_docs.md)：训练场测试功能1.0标为完成；枪械工坊与局内商人建立开发中的独立玩法契约。
- [E03资源扣款失败回滚](2026-09-12_e03_extraction_points_transaction.md)：普通资源扣款在写盘失败和revision冲突时拒绝并保持权威余额。
- [E01/E02运行态先行文档对齐](2026-09-12_e01_e02_document_alignment.md)：按用户决定将开门与区段卸载改为运行态先行、快照最终一致。
- [D01、D03–D07、D13内容文档对齐](2026-09-12_d01_d03_d07_d13_document_alignment.md)：内容名称、正式ID、实现状态与商店去向按运行工程同步。
- `history/`：由原规范拆出的施工、验收、尺寸版本和缺陷修复历史；原日期与原结论保留，不补造遗漏的提交或证据。
- [2026-08-27 推送摘要](history/14.5_推送更新摘要_2026-08-27.md)和[天台至98层成品化记录](history/17_天台至98层成品化验收.md)已归入历史。

历史目录不作为开发的规则入口。尺寸、玩法和失败语义读取对应现行设计；某次历史测试通过只证明当时记录的状态。
