# P2 媒体资产与功能追溯链修复记录

日期：2026-09-23。工程版本：0.1.0。本记录只描述 P2 改动，不将尚未关闭的 P0/P1 风险写成已完成。

## 交付

| P2 项 | 修复结果 | 机器入口 |
|---|---|---|
| 媒体资产拆域 | 删除 UI+音频合并账本，拆为 UI 17、音效 48、音乐 9 三本独立账本；总目录、大类、Skill 清单与快照同步 | `ledger_index.json`、`media_domain_split_manifest.json`、`check_media_asset_domains.py` |
| 制作链 | 新增 `ui-asset-pipeline`、`audio-sfx-asset-pipeline`、`music-asset-pipeline` 三个项目 Skill，各自冻结边界、账本、制作、接入与验收 | `.codex/skills/*-asset-pipeline/` |
| 功能追溯 | 37 个 `FeatureID` 全部登记为 `FeatureID → Owner → 主设计 → 开发记录 → 已注册验收` | `docs/v0.1/feature_registry.json`、`check_feature_traceability.py` |
| 复活契约 | 补不改玩法的 v0.1 `RevivalPolicy` 空策略，明确无复活源时只返回 `no_revival_source`，无预约、无副作用 | `verify_revival_policy_contract` |
| 后处理入口 | 为既有 `verify_postfx_overlay_runtime.gd` 补场景并注册进 `core` | `verify_postfx_overlay_runtime` |

## 迁移不变量

- 媒体 74 条资产的 AssetID、文件路径、SHA-256、制作状态、授权、备注与内容顺序保留。
- 唯一允许变化是账本归属与大类：`UI → UI`、`音频/sfx → 音效`、`音频/bgm → 音乐`。
- 旧 `ShellStorm2_表现资源账本_v001.xlsx` 已删除，可从 Git 历史恢复；正式流程不再解析该文件。
- 初始拆账基线未重写；`verify_ledger_split.py` 只从受控迁移清单规范化这两个允许字段，不会掩盖其他行/列漂移。

## 验收

| 命令/用例 | 结果 | 说明 |
|---|---|---|
| `python3 scripts/check_media_asset_domains.py` | PASS | 3 域、74 条、6 个专项验收入口全部存在且已注册 |
| `python3 scripts/check_feature_traceability.py` | PASS | 37/37 功能，65 个场景验收链接和 3 个命令验收链接 |
| `python3 scripts/check_verification_registry.py` | PASS | 156 个验收场景唯一归属 |
| `verify_revival_policy_contract` | PASS | 空策略稳定失败且不改输入 |
| `verify_postfx_overlay_runtime` | PASS | 后处理独立场景入口可运行 |
| `python3 scripts/check_documentation_contracts.py` | PASS | 追溯与媒体门禁已纳入文档契约总门禁 |

## 仍未关闭

- `check_asset_registry.py --scope structure` 仍有 5 条既有场景状态 `白盒组件` 不在旧状态枚举的 P0 报告；本轮不改状态语义。
- `verify_ledger_split.py` 仍报 20 个既有非媒体基线漂移：2 旧资产缺失、4 新资产超出 2026-09-18 基线，及敌人/场景/武器/VFX 历史更新。媒体行已不出现在失败清单中。
- 资产负责人仍是 P0 的“待分配”；本次新增的功能 Owner 是代码/数据状态所有者，不伪造人员归属。
