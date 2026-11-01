# 2026-11-01 远征03公馆门正式接入

工程0.1.0；FeatureID：WORLD-PLAN、ASSET-PIPELINE；来源：用户指出远征03仍在用远征01装甲门，要求换成03门。主设计：[远征03§2.1.5](../design/远征关卡03设计.md)、[公馆组件规范](../design/远征03复古公馆组件制作规范.md)。

原因：`DungeonRoom3D._door_panel_visual()`对slide统一选择塔楼A套门扇，没有使用已有`ENV-EXP03-MANOR-DOOR-DOUBLE`。本次在`DungeonTheme3D`增加可选`door_panel_visual_scene:PackedScene`，房间优先使用显式主题门外观，空值保持原有塔楼/基地分支；没有加入关卡ID判断。

远征03场景单独引用`assets/art/environments/dungeon_3d/env_expedition03_manor_kit_top3d.tres`，该资源保留原铁前线主题的全部既有参数，仅新增公馆门Prefab引用。门模型沿既有左右双滑门适配，各X0.55、宽1.21m，高2.5m、厚约0.203m；中缝覆盖与原滑轨一致。未拆网格、重导GLB、换材质或改变PaletteUV；不是新造门，也没有伪造独立半扇模型。两面沿原模型定义，正面黄铜木饰、背面木面。

外观唯一所有者为本关表现资源；模型/材质归稳定Prefab；门权限、目标、感应开合、动画和碰撞仍归既有RoomDoor3D/地图边。本次RoomDoor3D、TowerDescent3D文件SHA不变，生成器和存档逻辑未修改。失败/回滚：显式资源加载错误记为失败，不能把缺资源后的空值回退签为成功；主动空覆写走原选择，回退03场景的visual_theme引用可恢复旧外观。25份已完成03房间TSCN和整个《房间运行登记》均不重存；01的19份运行TSCN也不变。

## 复用与账本

复用公馆v017已有优化包。核对原GLB SHA与每包manifest一致；原Prefab字节保持，原SHA登记为CRLF `d852da2af68ce1f2b946ee20f8d5ae0f8626f3c6c2a1b916ad9d9629f63506f7`，当前LF为`33e173321a710a29226cfe6a84368d7beaa58ac120603e86d89fe80fb5a75617`，换行归一可精确互证；不把换行差异当模型变更，不批量回填哈希。Blend仅LFS指针/OID核查，没有实际重新打开或重导源。

场景账本《资产主表》r985及《3D-场景通用》r812只更新门的正式使用范围/接入状态/说明，版本与原哈希保留；域变更日志v0.1.60。无新增AssetID或组件。基线只更新该资产行指纹、相应列指纹与这一专表摘要，逐行保护其他资产和房间登记；未把无关漂移整体重采样。

## 当前验收

Godot4.7.2，Mac M1/OpenGL Compatibility。audit/native分别准备独立工程，显式用户目录设置、guard核对实际用户/存档路径，两个guard退出0；正式project.godot不改，不依赖test_mode隔离。

| 验收 | 退出码 | 结果 |
|---|---:|---|
| 6种子真实门实例/几何/碰撞/左右行程，01对照 | 0 | `MANOR_DOOR_OK checks=2437 legacy_doors=14 failures=0`；03共173扇门全部公馆AssetID、两份ImportedDoorVisual有真实网格；宽1.21/高2.5/厚<0.28；关门覆盖中缝且挡路、开门实际网格让净2.2m并放行 |
| 原生真实关卡感应与穿门 | 0 | `MANOR_NATIVE_OK checks=18 failures=0`；north/east玩家靠近打开、真实Player3D穿过门线约2.27/1.67m、走远自动关；权限字段与开合方式未改变 |
| 固定陈设/门口快速回归 + 主题覆写/空值负测 | 0 | `FIXED_FURNISHING_OK checks=1148 failures=0 files=65 used=19 door_samples=342`，种子77003244/42；显式主题在lift/slide均优先，旧主题空值及FACILITY保持原门选择 |

最终上述脚本/渲染ERROR 0；既有Forward+限定功能在Compatibility下的WARNING保留。快速回归夹具初次提前静态引用游戏类，导致MainLoop在Autoload前编译出错并产生连锁假红；改为运行后动态加载，与原夹具入口一致，重跑通过。初次错误日志保留，不计作游戏门或布局故障。

[实机前后图、正常游戏镜头与机器摘要](../../art/expedition03_manor_doors_20261101/README.md)。截图保持原游戏光/雾，未加摄影棚光。只签署门外观与当前开合/通行专项，不沿用上一批24种子通过作为本轮结果；未重跑全24种子、完整通关、旧气闸恒关/挡路债务、所有未来种子或目标Windows性能，整关仍partial。

工程根门禁与清理在交付附记中登记。工程外过程目录为`ShellStorm2-work/sessions/2026-11-01_expedition03_manor_doors/`。


## 交付附记

- `check_level_decoupling.py`退出0，7个通用机制容器0违规；本次按表现配置声明，没有新增关卡ID分支。
- 场景账本structure检查退出0（1013资产）、九域无损基线检查退出0（1417资产），所有其他资产行及房间登记保留。
- 文档检查退出1，与上一批相同44项旧问题（43断链、1组未注册测试）；运行资产命名检查退出1，仍为既有bunny v022/v023/v024 import/目录，当前新增主题路径无版本号。未回填无关债务。
- `git diff --check`退出0。未修改RoomDoor3D/TowerDescent3D、原门GLB/Prefab或正式project.godot；25份03房间+19份01运行文件SHA均保留。
- audit/native两个隔离工程和各自UUID用户目录链接已清理；复现配置、临时脚本、日志、截图及隔离用户数据保留工程外。没有关闭用户游戏或修改默认存档。已运行场景需重新进入/运行远征03才读取新表现配置。
