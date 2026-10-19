# 2026-10-19 枪声爆响与户外环境混音修正

FeatureID：AUDIO-MUSIC。依据《音效系统与资产设计》r6及用户反馈：枪声爆音、风声不好听且持续过大，室内不要风声与鸟叫。版本保持0.1.0。

## 改动

抽查七类主枪声源OGG峰值约-10.2至-8.9dBFS，无削波；真实音频设备下多类密集叠加测试，原混音峰值1.829，存在超出满幅风险。新增Gunfire子总线，七类SoundSet（兼容及语义事件共用）发送至此；总线降低6dB，压缩阈值-14dB、比率3、起效200微秒、释放80毫秒、补偿增益0，再发送到WorldSFX保留楼梯间回声。调整后同组测试峰值0.137；这是七类各六轮密集叠加压力场景，不代表普通单枪响度。没有改射速、触发次数、枪种身份、换弹、拾取、脚步或其他总线音量。压缩参数语义参照[Godot官方AudioEffectCompressor](https://docs.godotengine.org/en/stable/classes/class_audioeffectcompressor.html)。

风声复用有许可录音，通过独立OutdoorWind总线的120Hz高通/1800Hz低通，削减低频轰鸣和高频嘶响。天台播放增益+7→-10dB，户外+3→-13dB；进入户外等待2–5秒，5–9秒风段与9–18秒安静段交替，使用独立音频RNG及淡变。进入室内立即停风与鸟叫。

`WorldAudioContext3D`改为明确户外声明才允许户外声音：天台房型/楼层或audio_environment标记。普通房型、非天台楼层、未知支撑默认室内；头顶遮挡可进一步收紧户外判定，缺少屋顶碰撞不再自动判户外。解决切角室内没有屋顶碰撞而一直响风/鸟的问题。

修改AudioManager、world_environment_profiles、WorldAudioContext3D/WorldAudioEnvironment3D、七个SoundSet总线字段及两项现有专项。没有修改166条OGG/WAV文件、AssetID、路径、SHA、许可、178条资产账本或无损基线；本次是运行混音与触发修正。备份位于工程同级`ShellStorm2-backup/2026-10-19_gunfire_mix/before_edits/`，探针日志在`ShellStorm2-work/probes/2026-10-19_gunfire_mix/`。

## 验证

Godot启动前隔离APPDATA/LOCALAPPDATA。真实声音输出使用Windows Forward+及音频设备；音频总线捕获测量实际叠加输出。

| 检查 | 退出码/结果 |
|---|---|
| verify_audio_library_flow，Windows | 0；实际枪声叠加A/B峰值下降；七类路由、166 OGG/108组、原有保护哈希、UI暂停、并发与退出清理保持 |
| verify_audio_library_flow，无头 | 0；资源与枪种契约 |
| verify_world_environment_audio_flow，Windows | 0；低增益阵风/安静段、独立风声总线、无顶室内与未知支撑禁止户外声、已有设备/脚步/开关/楼梯回声及正式塔楼安装 |
| verify_requested_experience_upgrade_flow | 0；36项兼容OGG及mobile_safe=true |
| 媒体域/音效账本full/关卡解耦门禁 | 均0；全部166条运行文件SHA保持 |
| 四份场景日志错误门禁 | 均0；无非预期ERROR |
| check_documentation_contracts | 1；既有断链、子进程python3缺openpyxl及本轮范围外三项测试未注册（base_lamp_dynamics/base_lamp_visual/board_debris_vfx）；新音效记录链接未报错 |

人工耳机/外放听感、全塔逐房走场与Android未执行。正式塔楼专项仍有既有ObjectDB退出WARNING，未发现非预期脚本ERROR。本轮不把自动峰值验证等同用户听感确认。
