# 环境及实体音效自然化 · 2026-10-19

- FeatureID：AUDIO-SFX；工程版本：0.1.0；设计依据：AUDIO-SFX r4。
- 用户要求：其余音效一并改为正常、非卡通声音，系统音效除外。
- 状态：47组84条世界/实体声音已替换，系统提示与既有枪械声音保留；自动验收通过，人工听感及Android待验。

## 范围与交付

显式声音策略在 `art_source/audio/sfx/world_audio_policy.json`，运行目录保存同一份 `world_style_policy`：47组自然世界声音、29组系统提示、28组已完成枪械声音，三类互斥且覆盖当前104组157条资产。没有新增AssetID或改变音效事件数量。系统提示和既有枪声共73条的目录记录、运行文件与母版SHA均保持改前值，避免本轮重新制作冲掉上轮枪种区别。

本轮替换覆盖：

- 三类脚步、落地、受伤、倒下、死亡、闪避。
- 敌人受击、死亡、预警、搜索、攻击、召唤、治疗、避光、蓄力、举盾、爆炸。
- 近战挥砍、命中、重击、取消及弹体接触。
- 门开关、门锁、容器搜索/完成/取消、手电筒/灯具/收音机开关、设施启动。
- 全部7组环境循环：基地设施、工坊、恢复区、远征室内、远征开放区、撤离设施、Boss区域。

系统提示的完整保留清单以策略文件为准，包含UI、命运/魂球、交易、波次/Boss流程、撤离/结算、加载故障、手电筒电量警告、设施成功/拒绝和剧情提示；保留其电子/提示性风格。

实体声音使用来源明确的Foley、机械操作、打击、衣物、人体发声和口部怪物表演。敌人技能用碎屑、气流、机构与发声分层，不以旋律或电子滑音替代。虚构怪物/技能属于声音设计，不声称是真实生物录音。环境床由通风、风声和风扇素材构成，10秒母版、线性交叉淡化；不使用旧正弦振荡器或噪声合成器重造这些组。素材来源页没有说明录制方法的内容不额外声称为野外实录。

原触发者和事件键不变。已正式接入的行为立即使用新映射与全部变体；尚未接入领域事件的素材继续保留待接入状态。本轮没有新增脚步玩家听觉触发或7种环境床的场景自动启动机制，也没有把素材更新当作全游戏触发链闭环。AI声音传播、射速、伤害、动画时序、门锁规则和BGM不变。

## 来源与制作

- Kenney，[Impact Sounds](https://kenney.nl/assets/impact-sounds)、[RPG Audio](https://kenney.nl/assets/rpg-audio)，CC0；下载包内许可原文随共享源库保存。
- StarNinjas，[16 Monster Growls](https://opengameart.org/content/16-monster-growls)，CC0；口部发声素材。
- HaelDB，[Male Grunt/Yelling sounds](https://opengameart.org/content/male-gruntyelling-sounds)，选择页面提供的CC0许可。
- MidFag，[Ventilation version2](https://opengameart.org/content/ventilation-version2)，CC-BY-3.0。
- dklon，[Broken Fan Loop](https://opengameart.org/content/broken-fan-loop)，CC-BY-3.0。
- remaxim，[Short wind sound](https://opengameart.org/content/short-wind-sound)，CC0。
- OpenSpades free pak分发的接触、空气、爆炸与碎屑，逐文件许可继承项目内原 `recording_credits_20261019.md`，包括magnuswaker、satanicupsman、Iwan Gabovitch、Michel Baradari、Blender Foundation等来源；没有把该集合整体当成CC0。

可复用原始素材只保留一份于 `art_source/audio/sfx/recorded_world_library/source/`，该目录的source_index与CREDITS记录逐文件来源、署名、许可和SHA；它是制作依赖，不是新增运行资产。每个AssetID自己的source目录保留最新PCM24 WAV母版及引用共享源的recipe，含分层、起点、时长、增益、低通与循环接缝参数。运行OGG Vorbis q6，44.1kHz mono，由引擎进行3D空间化。旧母版、分层、OGG及改前映射/账本保存于 `ShellStorm2-backup/2026-10-19_natural_world_audio/`，不在工程内叠放过期母版。

输出一次性声音按材质留-12至-21dBFS峰值余量。环境床以-31dBFS RMS为归一目标，同时施加-21dBFS峰值上限，实际RMS约-31.8至-39.2dBFS；不会为了追平均响度削掉风声瞬态。环境床接缝采用0.5秒线性交叉淡化，源循环拼接采用0.2秒交叉淡化。固定峰值与接缝检查不替代主观听感。

## 账本与验证

音效账本仍169条：157条运行声音及12条弃用占位。84条目标资产更新版本、母版/运行路径、规格、SHA、许可、更新时间与备注；不变更原接入状态，不修改无关条目。域变更日志v0.2.2。逐格对照仅755个预期资产单元格变化，公式、行数与数据校验覆盖范围不变。基线仅更新84个目标条目的内容摘要和全域列摘要。

工程外过程与检查日志：`ShellStorm2-work/sessions/2026-10-19_natural_world_audio/`。
试听：`ShellStorm2-work/outputs/natural_world_audio_20261019/`。

| 检查 | 退出码 / 结果 |
|---|---|
| Godot 4.6.3原生导入 | 0 |
| verify_audio_library_flow，无头与真实Forward+ | 均0；157条解码/时长，104组，47组自然声音覆盖，7组循环，73条受保护资产哈希；七类枪种身份、真实3D播放器、UI暂停、并发与退出清理保持 |
| verify_requested_experience_upgrade_flow | 0；36项兼容OGG资源及mobile_safe=true |
| verify_3d_melee_feedback_flow | 0；挥空/命中与多目标接触主音去重保持 |
| check_asset_registry --ledger audio --scope full | 0 |
| check_media_asset_domains | 0 |
| verify_ledger_split | 0；无缺失、无额外资产、无列摘要漂移 |
| 84条FFmpeg解码/幅度/时长，全部运行SHA、目标母版SHA | 0；无无效样本、削波或哈希差异 |
| 7组循环解码后的接缝 | 0；边界差分约为日常95%差分的0.16–1.06倍，无异常跳变 |
| 账本无关格、公式、行数、ZIP层数据校验 | 0；非目标格不变；C/K/L列仍覆盖第174行 |
| check_art_source_layout | 1；既有地下街blend1源被Git忽略，无音效路径问题 |
| check_documentation_contracts | 1；既有断链、两项灯光测试未注册及python3子进程缺openpyxl；独立媒体域检查为0 |

近战专项首次exit 1，原因是验收脚本仍将路径尾缀写死为旧 `_v002.ogg`；本轮素材已合法升级为v003。断言更新为新版本并增加Godot原生OGG解码检查后复验exit 0，多目标主接触音去重、挥空与碰撞边界未放宽。初次失败日志与复验 `melee_final.log` 均保留。

自动运行前在Autoload启动之前隔离APPDATA/LOCALAPPDATA至工程外探针目录。非预期Godot脚本错误：上述验收日志未发现。预期故障注入：未执行。人工耳机/外放听感、与BGM混合听感、Android全新安装正式包未执行；仍需用户听感确认。整库素材替换不代表那些标明待接入的领域事件已具有正式触发。
