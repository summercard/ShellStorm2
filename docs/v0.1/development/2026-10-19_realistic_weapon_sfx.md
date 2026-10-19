# 枪械战斗音效录音替换 · 2026-10-19

- FeatureID：AUDIO-SFX；工程版本：0.1.0；设计依据：AUDIO-SFX r2。
- 来源：用户要求开枪、换弹、拾取枪械使用正常、非卡通音效。
- 状态：25条录音剪辑、13组映射已接入；自动检查通过，人工听感及Android待验。

## 交付

替换 pistol/rifle/shotgun/smg/sniper/laser_fire 的全部18个变体，以及 reload、reload_action、reload_end、ammo_empty、item_pickup、weapon_swap、weapon_attach。兼容事件名与SoundSet事件所有权不变；AudioManager兼容表和实际轮换目录同时更新，避免部分变体仍命中旧DSP。普通物品与枪械共用 item_pickup，因此该组现在都使用持物机械声。能量武器使用短促录音冲击替代旧电子滑音，并不声称录音对应现实能量枪。其他受击、近战、环境及UI素材保留原状态。

声音来自 CC0 枪械/操作录音，经 OpenSpades free pak 分发：

- [The Free Firearm Sound Library](https://opengameart.org/content/the-free-firearm-sound-library)：Ben Jaszczak、Brian Nelson、Kevin Heras、Matthew Nanney。
- [Gun reload sounds](https://opengameart.org/content/gun-reload-sounds)：SpringySpringo；原页面明确为空气枪机械操作录音。
- [Equipment clicks III](https://opengameart.org/content/equipment-clicks-iii)：LFA。
- [Handgun reload sound effect](https://opengameart.org/content/handgun-reload-sound-effect)：zer0_sol。
- [分发来源及逐条许可](https://github.com/DeathByDenim/openspades-free-pak/blob/main/License/Credits-pak001-Free.md)。项目内副本：`art_source/audio/sfx/recording_credits_20261019.md`。

每条源目录保留输入录音、PCM24/44.1kHz/mono可编辑母版与包含剪辑区间、滤波、增益、来源及哈希的recipe。开火归一到-10dBFS峰值，机械声-14dBFS，OGG Vorbis q6；保留瞬态与峰值余量，不增添音调合成层。枪声起音均小于5ms，枪声片段为单发。枪械声按听觉角色选材剪辑，不声称每类均有对应型号独立实录。旧文件、旧分层和改前账本存入工程外 `ShellStorm2-backup/2026-10-19_realistic_sfx/original_tree/`。

版本：既有v002提升至v003，新增组v001提升至v002。25个既有AssetID与账本行保持稳定；仅150个预期单元格改变，其他格值、公式、表格尺寸逐格核对不变。基线只更新这25个条目的内容摘要，不接受无关资产漂移。旧DSP批量构建入口增加明确拒绝，防止覆盖录音替换；当前母版以各自recipe和目录为准。

## 验证

工程外日志及数值：`ShellStorm2-work/sessions/2026-10-19_realistic_sfx/`。
试听合集：`ShellStorm2-work/outputs/realistic_weapon_sfx_20261019/试听合集.mp3`。
试听顺序：手枪、步枪、霰弹、冲锋枪、狙击、换弹、空仓、拾取、切枪。

| 检查 | 退出码与结果 |
|---|---|
| Godot 4.6.3 原生导入 | 0 |
| verify_audio_library_flow headless | 0；140条解码/时长、89组、变体轮换与兼容映射 |
| verify_audio_library_flow Windows真实Forward+ | 0；3D播放、暂停UI、连射并发、场景卸载清理 |
| verify_requested_experience_upgrade_flow | 0；含36项OGG、mobile_safe=true |
| verify_3d_melee_feedback_flow | 0；既有近战主反馈去重保持 |
| 25条FFmpeg解码、SHA、峰值、起音检查 | 0；无削波、缺失或哈希不一致 |
| check_asset_registry --ledger audio --scope full | 0 |
| check_media_asset_domains | 0；179条媒体资产 |
| verify_ledger_split | 0 |
| check_art_source_layout | 1；既有地下街blend1被Git忽略，与音效无关 |
| check_documentation_contracts | 1；改前已存在的断链、2个灯光用例未注册、python3子进程缺openpyxl |

正式运行前将APPDATA与LOCALAPPDATA隔离至工程外探针目录。非预期脚本错误：上述Godot验收日志未发现。预期故障注入：未执行。未执行：人工耳机/外放听感、Android清理安装后的新包试听、与BGM混合的主观听感。自动数值及播放节点检查不替代听感验收。
