---
name: audio-sfx-asset-pipeline
description: 为 ShellStorm2 制作、转码、接入或验收短时游戏音效。用于武器、近战、受击、UI、门、容器、波次、Boss与交互事件；不处理BGM、配乐编排、UI图像或3D模型。
---

# Audio SFX Asset Pipeline

## 资产边界

- 先读 `docs/v0.1/10_资产与内容规范.md` §10、`src/音效接入说明.md` 和 `assets/registry/ledger_index.json` 的 `audio` 域。
- 音效 AssetID 使用 `AUD-SFX-*`，大类为“音效”，唯一登记在 `assets/registry/ledgers/ShellStorm2_音效账本_v001.xlsx`。
- 事件键由 `AudioManager.SFX` 持有；调用方只请求事件键，不直接加载音频文件，也不回退 `SynthSfx`。
- 本 Skill 不改伤害、射速、动画时序或其他玩法规则。

## 制作与接入

1. 冻结事件键、触发者、是否空间化、并发/去重、目标响度和移动端要求，先查重并领取 AssetID。
2. 保留可恢复母版与许可来源；运行资产使用 OGG Vorbis，当前正式路径遵循 `src/assets/audio/sfx/*_vNNN.ogg`。
3. 在 `AudioManager.SFX` 建立唯一事件映射；同一行为不得在多个调用方各自实现随机、冷却或回退。
4. 实测单次触发、连射峰值、同帧多目标、暂停/退出与 Android 资源加载。
5. 回填路径、SHA-256、版本、事件键、许可与验收入口。

## 验收

- 运行 `verify_requested_experience_upgrade_flow`，要求 `AudioManager.validate_runtime_assets()` 保持36项、无缺失、无非OGG且 `mobile_safe=true`。
- 战斗反馈改动另跑对应专项，如 `verify_3d_melee_feedback_flow`；检查一次攻击的主接触音不因多目标重复播放。
- 运行 `python3 scripts/check_media_asset_domains.py`、`python3 scripts/check_asset_registry.py --ledger audio` 和文档契约门禁，并记录退出码与听感未执行项。
