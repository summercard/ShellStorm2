# 音效重制与替换 · 2026-10-13

- FeatureID：AUDIO-SFX
- 设计依据：AUDIO-SFX r1，《音效系统与资产设计》
- 工程版本：0.1.0
- 状态：36组兼容音效已替换；新增声音素材已制作，领域触发和人工听感未全部验收。

## 交付

按废墟科技、冷硬机械、清晰瞬态制作89组140条OGG：原36组重制为v002；53组新增声音包含脚步材质、敌人预警、设施、流程失败和7组环境床。高频声音采用独立噪声、模态与瞬态变体轮换。声音为原创离线分层DSP，不含外部采样；不宣称完成录音、AI平台生成或人工试听。

母版为44.1kHz单声道PCM24 WAV，独立分层、seed、recipe与源哈希位于 `art_source/audio/sfx/<AssetID>/source/`。运行资源为OGG Vorbis q6，物理文件与事件映射在 `src/assets/audio/sfx/sfx_catalog.json`；音效账本共152条，其中140条本次制作资产、12条旧设计占位已弃用。旧v001运行文件与散落WAV移入工程上层备份，保存逐文件SHA核对记录。

AudioManager保留36个旧调用键，增加语义入口、SoundSet轮换、组并发和40个总声音预算；明确武器音频配置可直接选择能量声音。带source_node/source_position的点声源使用3D播放器，环境循环归source_node管理；UI暂停时可播放。旧调用仍按现有事实触发，不把全部领域迁移描述为完成。AI刺激半径、敌人规则及音乐系统未改。

## 验证

工程外证据：`ShellStorm2-work/sessions/2026-10-13_sfx_rebuild/`；试听合集和数值报告：`ShellStorm2-work/outputs/sfx_rebuild_20261013/`。

| 检查 | 退出码/结果 |
|---|---|
| Godot原生导入 | 0 |
| verify_audio_library_flow，无头 | 0，140条解码/时长、89组、轮换、36条替换映射 |
| verify_audio_library_flow，真实Forward+ | 0，3D播放器、循环归属、重复循环去重、UI暂停、并发与退出清理 |
| verify_requested_experience_upgrade_flow | 0 |
| verify_3d_melee_feedback_flow | 0，挥空与多目标接触主层去重 |
| check_asset_registry --ledger audio --scope full | 0 |
| check_art_source_layout | 0 |
| check_asset_runtime_naming | 1，其他角色/场景资产命名债务；报告无音效路径 |
| 全140条FFmpeg解码、SHA、4倍过采样峰值、循环边界 | 0 issue |
| check_media_asset_domains | 1，既有UI数量期望16/实际18；本次audio为152，与原迁移48区分 |
| verify_ledger_split | 1，8条场景域新增资产/专表漂移；audio失败0，未接受无关资产哈希 |
| check_documentation_contracts | 1，基线子进程python3错误指向缺少encodings的ComfyUI Python；另有既有媒体数量问题 |

预期故障注入：未执行。非预期脚本错误：真实测试首次发现已释放节点停止错误，修复后复验没有该错误。引擎既有警告：外部GLB UID退回路径；Compatibility尝试时TAA不可用，最终使用Forward+。自动化保护：Godot启动前APPDATA/LOCALAPPDATA隔离至工程外会话目录。

未执行：人工耳机/外放试听、Android新安装正式包、混合音乐听感、墙门遮挡听感。数值检查与真实播放节点测试不替代听觉验收。新增53组尚待各领域确认事实接入，不计为全游戏声音闭环；原脚步玩家听觉、武器身份分类正式迁移、撤离保存成功边沿等目标仍保留。
