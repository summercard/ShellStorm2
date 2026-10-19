# 2026-10-19 环境音效与场景接入

FeatureID：AUDIO-MUSIC。依据《音效系统与资产设计》r5及用户要求：天台风声、户外鸟叫、不同地板脚步、鼓风机/风扇、电灯开关和楼梯间回声。沿用自然录音风格，系统提示音保持原风格。工程版本仍0.1.0。

## 实现与边界

`Dungeon3D`生成完成后安装一个场景所有的`WorldAudioEnvironment3D`，塔楼和远征继承同一入口。监听器跟随真实玩家；初始扫描及后续`node_added`识别设备，卸载场景停止循环并释放声学状态。纯音频配置位于`src/assets/audio/sfx/world_environment_profiles.json`，不依赖关卡ID。

- 天台/户外复用自然风声，室内外平滑淡入淡出。鸟叫在进入户外2–4秒后开始，之后每8–18秒随机方位播放；进入室内停止鸟叫。随机数使用独立RNG，不推进玩法随机序列。
- `Player3D`在真实着地且移动时发出独立可听脚步信号，站立/冲刺/空中不播放。按支撑碰撞祖先的`audio_surface`、组件语义或房型解析混凝土、金属、碎石与木地板；无声明默认混凝土。现有怪物AI脚步刺激的0.55秒周期、半径及判定保持。
- 正式桌面风扇、空调和天台通风口Prefab根节点作为空间循环声源；最近最多6个，距离12–18米，楼层高度差超过4.5米停声，障碍遮挡降低16dB并低通。隐藏/停机(`audio_enabled=false`)/释放设备即停止声音。没有对应实体时不制造无位置设备声。
- `RoomLightSwitch3D.toggle_light`只在接受玩家开关操作后播机械点击；读档恢复、联动同步、无绑定或忙碌拒绝均不补播。
- 支撑碰撞的竖直连接器、stairs组件或STAIR_LOBBY声明楼梯间；进入后WorldSFX渐入混响及125毫秒低电平回声，离开渐退。枪声与实体声音走此总线，UI和系统提示保持干声；风声/设备环境床仍由Ambience管理。

环境判断读取实际脚下碰撞与头顶遮蔽，场景可通过`audio_environment`和`audio_acoustics`声明能力。首版不做逐频段建筑声传播；窄门外和大型遮挡边缘的感受仍需人工走场确认。未改伤害、射速、AI刺激、掉落、存档格式与天台BGM关闭开关。

## 素材与账本

新增4组9条：木地板脚步4变体、户外鸟叫3变体、风扇/鼓风机各1条8秒循环。木脚步使用Kenney CC0，鸟叫使用syncopika的CC0实录，设备复用dklon和MidFag的CC-BY-3.0录音。逐文件署名、来源与许可见共享源目录的CREDITS和source_index，每个AssetID有PCM24母版、recipe与运行OGG。旧157条运行文件保持，系统/枪械73条受保护哈希检查继续通过。

运行库108组166条，36个兼容事件保持。音效账本178条（166运行+12弃用），新增9条、更新15条既有脚步/开关/风声接入状态为原型已接入；域日志v0.2.3。R/S查重公式、总览、C/K/L数据验证均扩展至183行，无损基线仅更新对应条目摘要及派生汇总。

改前备份：工程同级`ShellStorm2-backup/2026-10-19_world_audio_runtime/before_edits/`。过程与原始验收日志：工程同级`ShellStorm2-work/probes/2026-10-19_world_audio_runtime/`；素材构建报告在`ShellStorm2-work/sessions/2026-10-19_world_audio_runtime/`。

## 验收

所有Godot运行在Autoload启动前隔离APPDATA/LOCALAPPDATA。Windows真实Forward+与音频设备输出单独执行，未用无头结果代替真实声音输出。

| 检查 | 退出码及证据 |
|---|---|
| verify_world_environment_audio_flow，无头/Windows | 均0：室内外、四类脚步、实际玩家门控、真实设备Prefab、距离/隐藏/停机/释放、开关唯一触发、UI干声、场景卸载；正式塔楼控制器跟随玩家，出生天台判定正确、识别2处设备 |
| Windows音频总线捕获 | 0；楼梯间脚步有实际回声尾音，干声尾能量0，混响尾能量大于0；日志保留数值 |
| verify_audio_library_flow，无头/Windows | 均0；166 OGG、108组、51组自然声音、9组循环、73条保护哈希及七类枪种路由 |
| verify_requested_experience_upgrade_flow | 0；36项兼容OGG，mobile_safe=true |
| verify_3d_melee_feedback_flow | 0；多目标主接触音去重保持 |
| verify_tower_descent_flow | 0；旧流程明确迁移到到达门专项，不视为全塔流程验收 |
| check_asset_registry --ledger audio --scope full | 0；178条，无路径/哈希/公式问题 |
| check_media_asset_domains / verify_ledger_split | 均0；无额外/缺失资产或列摘要漂移 |
| check_level_decoupling / check_asset_runtime_naming | 均0；未引入关卡ID分支或运行路径命名债务 |
| 新增9条FFmpeg解码/母版及运行哈希/循环接缝 | 0；无削波/无效样本；设备两条接缝差分为平日95%差分的0.35/0.03倍；改前157条运行文件哈希全部保持 |
| check_documentation_contracts | 1；既有13处断链、两项基地灯光测试未注册、python3子进程缺openpyxl；独立媒体域检查为0，本轮新增文档链接未报错 |
| check_verification_registry | 1；仅既有verify_base_lamp_dynamics / verify_base_lamp_visual未注册；本轮新增专项已归core及真实输出名单 |
| check_art_source_layout | 1；仅既有地下街blend1源被Git忽略，无音效源路径问题 |

非预期脚本错误：上述场景未发现。新正式塔楼探针与原有`verify_tower_descent_flow`均出现同样的ObjectDB退出WARNING；无ERROR级泄漏，未把该既有警告认作无警告通过。原生导入另有既有远征房间重复UID警告。`--check-only --script`直接检查依赖Autoload的脚本会产生伪缺标识符错误，实际工程场景加载通过后不使用该调用作为验收。

人工耳机/外放听感、整塔逐房走场、移动端预算、Android全新安装和故障注入未执行。素材与实际播放接线通过不代表人工混音验收完成。
