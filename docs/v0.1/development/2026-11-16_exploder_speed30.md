# 炸弹果移动与步频同步提高30%

- FeatureID：ENEMY-AI / ASSET-PIPELINE；工程0.1.0；资产ENM-BOMBER-FRUIT01/v002，21:53用户修订。
- 来源：用户要求「走路动画频率可以再快点，游戏内移动速度也可以快一点。加快30%」。本次不是第二次额外叠加动画倍率。
- 主设计：[怪物设计·炸弹果](../design/怪物设计.md)；初次美术接入见[两段动画记录](2026-11-16_exploder_mech_animation_import.md)。

## 修改

| 入口 | 原值 | 新值 | 关系 |
|---|---:|---:|---|
| Enemy3D.PROFILES exploder speed | 3.1 | 4.03 | ×1.30 |
| MonsterInjector exploder speed（px/s） | 70 | 91 | ×1.30 |
| Profile当前实际速度 | 1.8445m/s | 2.39785m/s | 乘全局0.595 |
| 普通Injector当前实际速度 | 1.735416667m/s | 2.256041667m/s | px/s÷24×0.595 |

两种初始化来源分别设置最终速度，不彼此相乘。关卡显式绝对override_speed仍按原契约优先。本次不改其它怪和七只exploder代理怪。

动画包装字节不变：标定分母move_reference_speed固定1.8445；实际速度提高30%，动画相位同步提高30%，不另乘1.30，避免误成1.69。源move仍0.5秒，旧Profile标定条件下新实际周期约0.384615秒。蓄爆explode仍0.9秒，不受移动倍率或人工光减速影响。原模型、动作源、GLB、贴图、碰撞/尺寸、生命/伤害/掉落不变；资产美术版本不提升。

修改文件为 `src/enemy3d/Enemy3D.gd`、`src/map/MonsterInjector.gd`；专项在既有 `tests/verification/verify_exploder_presentation.gd` 追加提速断言，不删除旧断言。设计、登记与追溯同步，运行时调参和源动作时长分开记录。

## 验证

启动Autoload前隔离APPDATA/LOCALAPPDATA/HOME/USERPROFILE/TEMP/XDG目录；复用工程外最小配置与junction，不复制整个项目、不运行正式档、不导入新模型。

- 正式专项exit0、日志门禁exit0：`EXPLODER_PRESENTATION_OK checks=351`；新增199项提速断言，`EXPLODER_SPEED30_OK checks_added=199`。
- Profile真实Enemy六物理帧位移0.184432983→0.239776611m，比1.30007446；步频相位比1.30007441。
- Injector真实Enemy位移0.173538208→0.225585938m，比1.29992087；步频相位比1.29992095。浮点物理误差在专项容差内。
- Profile速度0.1秒驱动动画推进0.129995439秒，约0.13，明确不是0.169。Injector0.1秒推进0.122301945秒，基准不同但同比仍1.3。
- 两入口重复configure不叠加，source/theme倍率正常；其它怪/七代理速度字段和外壳不变。
- 人工光下实际速度及动画相位均保留40%；停步相位不推进。
- 原move0.5、蓄爆0.899秒不爆、跨0.9秒转attack；主动爆炸单次伤害30且零碎片；普通击杀8碎片每片8，碰撞0.88/1.28、根0.546、死亡回收0.34秒均保持。
- SCRIPT ERROR/ERROR均0；55条资源invalid UID回退warning保留，非本次逻辑失败。
- 14项被保护美术源/运行资产哈希不变，未重做骨架/贴图或重导GLB。

证据统一位于工程外 `ShellStorm2-work/sessions/2026-11-16_2153_exploder_speed30/test/`：`final.log`、`final.result.json`及启动前隔离文件。

本次未重跑整关人工实玩/设备/APK/core/full，也不以本专项通过代签全项目。工作区已有未提交并行修改保留；本次不提交、不推送。备份位于上层 `ShellStorm2-backup/2026-11-16_2153_exploder_speed30/before_edits/`。
