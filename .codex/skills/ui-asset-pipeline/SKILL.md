---
name: ui-asset-pipeline
description: 为 ShellStorm2 制作、接入或验收 UI 页面、面板、图标与交互表现资产。用于 HUD、背包、基地菜单、弹窗、手柄焦点和跨分辨率界面；不处理音效、音乐、3D模型或玩法规则。
---

# UI Asset Pipeline

## 资产边界

- 先读 `docs/v0.1/10_资产与内容规范.md`、目标功能主设计和 `assets/registry/ledger_index.json` 的 `ui` 域。
- UI AssetID 使用 `UI-*`，唯一登记在 `assets/registry/ledgers/ShellStorm2_UI账本_v001.xlsx`；先查重再制作。
- UI表现使用 `UIPalette`、`UIStyleFactory` 与已有公共控件。不得把交易、掉落、存档等业务规则复制进界面脚本。
- 图标、页面场景与脚本使用稳定运行路径；版本写在账本、源文件或元数据中，不制造平行运行副本。

## 制作与接入

1. 冻结目标页面、状态、输入方式、分辨率与可访问性契约，并登记或确认 AssetID。
2. 复用公共色板、字体、按钮和物品预览组件；新增视觉资产时保留可编辑源与许可信息。
3. 通过现有 Presenter、命令或查询接口绑定数据，不直接读写其他模块私有字段。
4. 验证键鼠、手柄焦点、`ui_cancel`、模态输入锁、1280×720基准与目标缩放；真实视觉要求使用真实渲染器。
5. 回填稳定路径、SHA-256、状态、验收入口与开发记录。

## 验收

- 至少运行与改动最接近的UI专项；公共HUD改动运行 `verify_hud_presenter_3d`，暂停/菜单输入运行 `verify_pause_game_save_reset_flow` 或 `verify_gamepad_input_flow`。
- 视觉改动补对应 `visual` 场景截图，不以 headless 结果代替真实渲染。
- 运行 `python3 scripts/check_media_asset_domains.py`、`python3 scripts/check_asset_registry.py --ledger ui` 和文档契约门禁；分别记录退出码、预期故障与未执行项。
