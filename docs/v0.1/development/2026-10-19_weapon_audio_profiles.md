# 枪种音效与正式路由 · 2026-10-19

- FeatureID：AUDIO-SFX；工程版本：0.1.0；设计修订：AUDIO-SFX r3。
- 用户要求：枪械种类也要区分。
- 状态：9个枪身ID、7类独立开火/换弹/拾取声音已接入并通过自动验收；人工听感、Android待验。

## 问题与结果

上一轮仅替换了声音文件，正式 `WeaponModel3D` 仍通过射速和最终弹丸数推测类别，因此高射速初始步枪可能误用冲锋枪声、加散射或复制弹的手枪可能误用霰弹声，低射速榴弹筒和蓄力炮也没有稳定身份。

`sfx_catalog.json.weapon_profiles` 现在是唯一枪身音频配置。AudioManager只消费枪身ID与动作，正式开火、换弹、地面拾取使用同一映射。射速、弹丸数量、品质、命运增益及伤害规则未改。副枪自身仍走同一个开火入口；交替副枪开火时，未发射的主枪不再多播一条声音。语义事件有gun_id时同样采用该配置；旧36项兼容事件表保留。未知开火/换弹枪身只报告并静音，不推测类别。

| 枪种 | 正式枪身ID | 开火SoundSet | 换弹 / 拾取 |
|---|---|---|---|
| 手枪 | bp_pistol | pistol_fire | reload_pistol / pickup_pistol |
| 步枪 | bp_rifle、bp_starter_rifle | rifle_fire | reload_rifle / pickup_rifle |
| 机枪 | bp_machinegun、bp_sprinkler | smg_fire（兼容键） | reload_machinegun / pickup_machinegun |
| 霰弹枪 | bp_shotgun | shotgun_fire | reload_shotgun / pickup_shotgun |
| 狙击枪 | bp_sniper | sniper_fire | reload_sniper / pickup_sniper |
| 榴弹筒 | bp_launcher | launcher_fire | reload_launcher / pickup_launcher |
| 蓄力炮 | bp_charge | laser_fire（兼容键） | reload_charge / pickup_charge |

普通物品、近战与货币保留原通用拾取路径；枪械拾取支持assembly_id、嵌套实例以及只有规范内容ID的旧物品。声音只在GroundLootPickup3D接受交接时播放一次。

## 资产与许可

手枪使用CZ-52录音片段，步枪使用SKS片段，狙击使用Mosin片段，霰弹使用独立shotgun录音；机枪保留上一轮AK-47素材。榴弹筒采用低频发射冲击和机械锁扣，蓄力炮采用更长的重型冲击与机构声，均为录音剪辑/分层的声音设计，不宣称是实物榴弹筒或虚构蓄力炮的直接录音。没有用单纯变调来冒充枪种。霰弹变体来自同一枪声录音的剪辑/滤波差异，不宣称为三次独立录制。

- [Gunshot Sounds](https://opengameart.org/content/gunshot-sounds)：Tabasco / Vincent Sevedge。网页标CC0，但下载包内 `creativecommons.txt` 写明Copyright (c) 2009 Vincent Sevedge、CC-BY-3.0；本工程保留署名并按包内较严格许可登记，不把这些样本标成原创或无署名CC0。完整说明位于 `art_source/audio/sfx/tabasco_recording_license.txt`。
- 机械操作：SpringySpringo，CC0，[Gun reload sounds](https://opengameart.org/content/gun-reload-sounds)；其中源是空气枪操作录音。
- 机枪与其他已用Foley来源沿用[上一轮逐条许可](2026-10-19_realistic_weapon_sfx.md)，完整分发清单位于 `art_source/audio/sfx/recording_credits_20261019.md`。

新增17条AssetID（榴弹开火3、七类换弹7、七类拾取7），更新15条既有枪声，合计32条本轮制作资产。旧开火版本v003→v004；机枪素材仍v003；新增素材v001。运行库从89组140条增至104组157条；音效账本152→169行。各源目录保留输入录音、PCM24/44.1kHz/mono母版、剪辑区间、降噪滤波、起音修剪、峰值、许可、哈希及recipe。枪声-10dBFS，机械声-14dBFS，OGG Vorbis q6；起音去除录音静默和降噪延迟。旧源和旧账本在 `ShellStorm2-backup/2026-10-19_weapon_profiles/original_tree/`。

账本新增只追加行；既有行号保持。查重公式、总览公式与校验范围扩至第174行，基线仅更新本轮32条资产摘要与全域列摘要，不接受无关行哈希。旧DSP及上一轮通用录音覆盖脚本都禁止覆盖已安装的枪种配置。

## 验证

工程外证据：`ShellStorm2-work/sessions/2026-10-19_weapon_profiles/`。
试听：`ShellStorm2-work/outputs/weapon_audio_profiles_20261019/枪种开火对比.mp3`。
顺序：手枪、步枪、机枪、霰弹枪、狙击枪、榴弹筒、蓄力炮。

| 检查 | 退出码 / 结果 |
|---|---|
| Godot 4.6.3资源原生导入 | 0 |
| verify_audio_library_flow，headless与真实Forward+ | 均0；157条解码与时长、104组；9个实际武器入口在30发/秒及6弹丸条件下仍按枪种选声；实际换弹与GroundLoot接受拾取路由、内容ID兼容、语义事件、交替开火无主枪假声、类间音频SHA不重复；原3D/暂停/并发/退出检查保持 |
| verify_3d_reload_state_flow | 0 |
| verify_requested_experience_upgrade_flow | 0；36项OGG、mobile_safe=true |
| verify_3d_fate_weapon_flow | 0 |
| check_asset_registry --ledger audio --scope full | 0；169条 |
| check_media_asset_domains | 0 |
| verify_ledger_split | 0；无缺失、无新增漂移、无列摘要漂移 |
| 157条运行SHA、32个母版SHA、七类×三动作的解码/起音/峰值 | 0；21个主片段起音均小于33ms、无削波 |

验收在Autoload启动前隔离APPDATA与LOCALAPPDATA至工程外探针目录。非预期Godot脚本错误：未发现；预期故障注入：未执行。人工耳机/外放听感、与BGM混音及Android清理安装后的包均未执行，不以数值或播放器验收代替听感验收。工程既有文档断链、灯光用例未注册和python3子进程环境问题另见文档门禁日志；与本次音效资产不混为通过。


## 音效分账本补齐

2026-10-19按用户要求核对并补齐42条枪械相关音效登记，资产总数仍169条，无新增AssetID。修正机枪名称、榴弹开火变体父ID、旧母版编号、实测母版时长、更新时间、枪身映射、来源许可与验收备注；附七类枪种查询说明和域变更日志v0.2.1。保持游戏版本0.1.0与所有运行音频字节不变。

36条本轮相关条目属于已接入（七类开火21、换弹7、枪械拾取7、普通拾取1）；空仓、兼容通用换弹、分段换弹2、切枪、装配共6条仅素材/事件映射就绪，账本标authored，未宣称有正式领域触发。人工听感和Android保持待验。查重/总览/下拉仍覆盖第174行，逐格核对未修改无关资产，基线只同步42条目标资产摘要及全域列摘要。

本次账本复验：check_asset_registry(audio/full)、check_media_asset_domains、verify_ledger_split均exit 0；check_documentation_contracts exit 1，仍为既有文档断链、两项灯光验收未注册及python3子进程缺openpyxl。无损校验与媒体域无失败；未运行游戏、人工试听或Android。本次只改登记与说明，不重跑声音制作与运行玩法测试。日志位于 `ShellStorm2-work/sessions/2026-10-19_audio_ledger_update/`。
