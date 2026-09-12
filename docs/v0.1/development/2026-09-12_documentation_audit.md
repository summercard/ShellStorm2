# 工程结构与文档分离审计交付

日期：2026-09-12。记录ID：DOC-AUDIT-20260912。工程版本：0.1.0。
功能ID：本次为全模块审计，覆盖[索引](../MODULE_INDEX.md)全部32项；不属于这些功能的新实现。
设计依据：用户要求检查独立开发、数据链和文档同步，并将设计与开发日志分离；既有[架构总则](../02_技术架构总则.md)的六项契约和[存档规范](../09_技术施工_存档结算与复活.md)。
代码基线：`31ed360644768808e6faef5cd3b341b731888625`。交付状态：工作区变更，未提交或推送。

## 1. 变更

- 新增文档入口、文档驱动开发规范、设计与日志模板、设计目录、32功能/18模块索引和审计报告。
- 将17处历史章节/整页、1156行原记录实际迁入development；保留原入口跳转与章节锚点。
- 校正剧情完成度、统一交互、行动存档、精英档案、手电基地规则、特效注册路径及常量等确定的文档过期项。
- 新增`check_documentation_contracts.py`结构检查与仓库根`AGENTS.md`开发约定，未接CI/Hook。正文设计路径保留，避免已有技能和工具引用失效。
- 运行时代码、场景、内容XLSX、资产文件和台账均未作为本次整改对象修改。缺陷与差异保留审计证据，后续先按设计更新再施工。

## 2. 验证

| 项目 | 环境 | 结果 | 证据 |
|---|---|---|---|
| 核心aggregate core | Godot4.6.2、headless、用户目录预隔离 | 61项：49退出0，11失败，1超时；非预期错误另列，不签署全绿 | [核心输出](../audits/evidence/core_output.txt) |
| 行动自动保存/98F重载 | 同上 | 两项通过 | [保存](../audits/evidence/runtime_autosave.txt)、[重载](../audits/evidence/runtime_restart.txt) |
| 音乐 | 同上 | 退出0；未知ID拒绝符合用例，仍有资源泄漏告警 | [音乐](../audits/evidence/music.txt) |
| 后处理 | 正式scene命令/临时包装场景 | 正式入口缺tscn；临时包装POSTFX_OVERLAY_RUNTIME_OK | [入口失败](../audits/evidence/postfx_missing_scene.txt)、[探针](../audits/evidence/postfx_temporary_scene.txt) |
| 持久化故障注入 | 第二独立用户目录，仅handler级探针 | 复现扣款误报成功及写盘失败仍开门 | [探针](../audits/evidence/failure_probes.txt) |
| 内容对照 | 只读XLSX+正式Godot注册表 | 有13条原始差异，含缺省字段差异；5组ID映射缺失、弹药堆叠与近战成交字段问题 | [数据](../audits/evidence/content_parity.json) |
| 资产台账full检查 | 只读文件与SHA | 418条登记，214条sha_mismatch | [台账](../audits/evidence/asset_registry_check.json) |
| 历史迁移保真 | 比较Git基线；仅规范化相对链接 | 17/17保留原内容 | [迁移检查](../audits/evidence/migration_verification.json) |
| 文档结构检查 | Python标准库，本地显式执行 | 43份文档、271个本地链接、32个功能ID、42个测试引用，issues=[]；不检查语义/锚点或运行效果 | `python3 scripts/check_documentation_contracts.py` |

未执行full、全新缓存导入、真实视觉/GPU/长测；不能将本次headless逻辑结果签署为发布或美术验收。退出0中的非预期ERROR与退出泄漏记录仍保留。

## 3. 遗留与下一交付

审计[ A01–A10及整改顺序](../audits/2026-09-12_engineering_audit.md)为后续工作依据。先补楼层/区段/经济/结算原子事务、VFX回收和验收框架，再逐批对齐数据与资产，最后推进模块服务化及缺失设计。

没有补造旧功能开发记录或确认未冻结玩法；功能索引中“缺设计/缺记录”项仍然需要实际交付。旧历史页中保留的用户语境和测试结论仅属于原记录时点。
