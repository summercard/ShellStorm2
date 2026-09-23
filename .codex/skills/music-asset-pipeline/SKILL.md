---
name: music-asset-pipeline
description: 为 ShellStorm2 制作、导入、编排或验收BGM与场景配乐资产。用于曲目A/B版本、循环、场景触发、Music总线与授权登记；不处理短时SFX、UI图像、3D模型或玩法规则。
---

# Music Asset Pipeline

## 资产边界

- 先读 `docs/v0.1/14.8_音乐系统与配乐资产.md` 和 `assets/registry/ledger_index.json` 的 `music` 域。
- 配乐 AssetID 使用 `AUD-BGM-*`，大类为“音乐”，唯一登记在 `assets/registry/ledgers/ShellStorm2_音乐账本_v001.xlsx`。
- `MusicCatalog` 持有 `music_id → tracks`，`MusicManager` 持有播放、栈、循环和总线状态；场景只请求 `music_id`。
- 不把生成平台凭据写进仓库；外部生成曲必须登记账号归属、商业许可与原始任务编号。

## 制作与接入

1. 冻结使用场景、情绪、长度、循环方式、A/B策略、淡入淡出与许可要求，先查重并领取 AssetID。
2. 原始MP3/WAV放在曲目包 `source/` 并由 `.gdignore` 隔离；运行资产转为 OGG Vorbis，使用现有曲目目录和版本命名。
3. 更新 `MusicCatalog`，不在场景脚本复制曲目路径；切换、压栈与恢复只经 `MusicManager`。
4. 检查循环接缝、A/B加载、未知ID拒绝、重复播放稳定性、场景退出资源释放与Music总线。
5. 回填路径、SHA-256、版本、music_id、许可与验收入口。

## 验收

- 运行 `verify_music_system`；要求Catalog、A/B资源、重复播放、push/restore、未知ID拒绝和退出释放通过。
- 需要听感或循环接缝判断时使用真实音频设备人工验收，并明确记录未执行项；headless只证明状态与资源存在。
- 运行 `python3 scripts/check_media_asset_domains.py`、`python3 scripts/check_asset_registry.py --ledger music` 和文档契约门禁，分别记录退出码。
