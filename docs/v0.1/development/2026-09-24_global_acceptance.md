# 全项目全局验收交付记录

日期：2026-09-24；记录ID：GLOBAL-AUDIT-20260924；功能ID：ASSET-PIPELINE、PERFORMANCE-RUNTIME及功能注册表全部37项；工程版本：0.1.0。
设计依据与修订：文档驱动开发规范、模块索引r10、现行功能主设计、资产规范与测试发布规范；代码基线：`bda2c82883091501e57b21d7343e02b0d0d7297b`；交付提交：工作区，尚未提交。

## 变更与原因

按用户要求重新进行六维全局验收，交付[总报告](../audits/2026-09-24_global_acceptance.md)、[37项功能表](../audits/2026-09-24_global_feature_matrix.md)和[机器可读证据](../audits/evidence/2026-09-24_global/README.md)，更新文档中心与模块索引入口。不改玩法、表现、存档、账本、资产或版本；审计不是授权修复所有红项。

阅读中心规范和各功能主源后，以功能注册、关系表、关键源码、九域分账本、磁盘扫描与本轮运行结果交叉核对。使用项目验收套件排查Skill约束故障归类；真实渲染在Metal/Forward+执行，不拿headless代签。全部资产框架/账本均检查，但没有逐件重跑Blender制作QA或逐行证明全部代码。

## 验证结果

Godot 4.6.2，macOS Apple M1。命令使用 `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot`；正式Runner在Autoload之前改写临时工程的自定义user目录，并为场景独立隔离。保留用户原有编辑器，不操作正式存档。

| 命令/场景 | 环境及存档隔离 | 结果 | 证据 |
|---|---|---|---|
| `bash scripts/run_verification_suite.sh aggregate full` | 隔离工程，缓存重建后的首次导入；不是受控零缓存A/B实验 | 退出3，导入2条ERROR，0场景运行 | runtime_results.json中runtime_full.log |
| `bash scripts/run_verification_suite.sh aggregate core` | 隔离工程/逐场景user目录，热缓存 | 退出1；133项中116通过、15失败、2跳过；4条白名单预期错误、0脚本错误、2条泄漏WARNING | runtime_core_warm.log的持久摘要与core_failure_comparison.json |
| `bash scripts/run_verification_suite.sh batch …` | 取visual列表全部非soak用例，共25项；同样隔离，使用真实渲染 | 退出1；19通过、6失败；2条脚本错误；旧塔楼用例由180秒看门狗终止，退出143 | runtime_render_sample.log的持久摘要；名称sample不表示仅抽跑部分非长测场景 |
| 十项静态检查 | 本工作区只读扫描 | 文档/追溯/跨域规则/登记/命名/媒体/拆账/class_name共8项退出0；资产完整和旧账本工具共2项退出1 | static_checks.json记录完整命令和输出 |
| 内容数据库与源路径附加检查 | 只读读取XLSX | 122公式缺缓存，未重算；7条源路径失效，涉及2个旧路径 | content_workbook.json、asset_domains.json |
| 长测、manual、目标设备、完整听觉/美术签收 | 本次未执行 | 不作通过结论 | 总报告§6明确限制 |

核心15项失败与9月23日记录集合相同；本次不因数量一致沿用旧故障细节。画廊脚本打印OK后仍有空资源脚本错误，按门禁判失败。旧爬塔脚本访问关闭的95F房间导致超时，继续按用户要求低优先级，而非升级为当前主线阻断。

首次导入在清理trap注册前退出，留下本轮1.6 GiB临时工程。核定为本次专属目录且保留日志后已清除；它可重新生成，未删除正式资源。后续两批由Runner完成临时清理。本轮不实施额外资产或用户文件删除。

## 遗留与状态更新

结论为未全局通过。总报告GA-01至GA-08分别管理导入、数据安全、运行/性能、资产追溯、设计主源、表现交接、维护发布与隐藏玩法，不把设计未实现、旧测试失配和真实故障合成bug数量。

37项实现状态保持注册表事实，不因文档编辑自动升降级；最新验收状态写入独立逐项表，新增训练场渲染失败等不能被历史complete掩盖。四份新设计覆盖14项，其余23项需迁移/审查而非全无设计；9域410资产框架完整，但1哈希、7源路径、21旧工具等仍待修复。

磁盘候选逐件输出CSV。114个非正式运行相关文件约72.63 MiB仅建议迁出/归档；122旧Blend与20孤立备份保留待核，不自动删除。编辑器重新生成的导入缓存仍被Git忽略，不能把它重新出现视为上传到Git。
