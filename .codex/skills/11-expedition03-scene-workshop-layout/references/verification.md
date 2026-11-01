# 远征03布局验证参考

工程路径相对ShellStorm2项目根；下述只是检查入口，不表示本次已运行。项目流程文档：`docs/v0.1/11_远征03场景工坊布局与陈设流程.md`。

## 运行前先确认隔离

1. 调用本Skill `scripts/prepare_isolated_project.py --project-root <root> --session <本次标签> --case <case名>`。需要本机兼容渲染器时显式加 `--renderer gl_compatibility`，不修改正式项目设置。脚本仅建工程外副本配置与只读用途资源链接，不启动Godot。
2. 从输出取得isolated_project、guard_args、namespace和user_data_link。先用Godot运行guard_args：退出0且两条实际路径指向本case命名空间，才运行测试。每个并发case单独prepare。禁止从旧副本配置中假定存在字段后只做replace。
3. 资源目录是符号链接，不是操作系统强制只读：测试fixture写盘必须指向工程外独立路径，不能覆盖链接中的正式资源；需要任意res写盘的测试应另建真实文件副本。原工程 `project.godot` 哈希应保持不变；默认用户目录可能有用户游戏/其他进程并发写入，不以其SHA波动判断本case路径正确。出错即停止本case，保留日志和当前数据；不杀用户游戏、不猜测覆盖存档。
4. Windows不具备符号链接权限或缓存不可用时，准备器明确失败。可在工程外改用经过核验的资源复制方案，但仍必须显式设置用户目录并跑实际路径guard；不回退到原工程跑测试。

## 结构与作者布局

- 目标路径由game_rooms/RuntimeRoomArtSource确认，再跑check_room_scope。TSCN format=3、Node3D根、稳定Prefab引用；不要要求01/02的旧组名同步迁移。
- 改前快照与正式保存结果按节点路径比较，区分新增/删改/未动。并发改动单列，不能拿旧备份覆盖当前作者值。
- 实测组件包络、底面、完整父变换、单位缩放、墙体边界；逐对查家具阻挡碰撞。门墙结构件单独归类，避免把合法结构接缝当家具互穿。
- 全部合法门位用RoomArtLayoutContract查询。它的furnishing_conflicts只查layer1阻挡，易碎件layer4不会被它捕获；所以易碎件还要用实际包络/footprint对全部door_boxes做净空查询，不以“不挡玩家”跳过视觉门口检查。
- 比较正式TSCN与实际装入的AuthoredLayoutArtRoot/SafeRoomArtRoot，核查作者灯光参数、实例数及Transform。跨种子改的是房间世界位置和门墙，房内作者摆位保持。

## 破碎验收

- 每种组件须有真实Projectile3D命中HitReceiver，确认命中信号/方向、broken信号入房间账；不能直接调用take_damage或shatter模拟子弹。
- 大量射击测试先物理查询起点和弹路净空，避免子弹生在邻近家具中；遮挡严重时修改摆位，不增加穿透或删碰撞来迎合测试。
- 原生窗口使用玩家当前WeaponModel3D.try_fire链路及真实玩家接触，至少分别覆盖目标房间；直接生成Projectile3D的专项与玩家武器专项分开统计。
- 每件一次破碎，重复触发幂等；HitReceiver层关闭、PlayerContact停监测、本体隐藏；材质类别碎片、飞散/落定与无残留阻挡。现有上限5片/件，96件是480片，功能通过不等于设备性能通过。
- detail流送：作者件随壳体常驻，实例应不变且保持已碎；随机detail件重建应是新实例。另序列化房间breakable_clutter状态，回灌全新房间实例，验证同ID恢复、未打碎件仍完整。别用同一实例重复断言冒充重新加载。

## 现有检查入口

在已通过guard的工程外项目中运行，按变更范围选择；实际支持参数以脚本为准：

```text
Godot --headless --path <isolated_project> --script res://tools/scene_builder/test_fixed_furnishing.gd -- <工程外输出目录>
Godot --headless --path <isolated_project> --scene res://tests/verification/probe_authored_breakable_clutter.tscn
Godot --headless --path <isolated_project> --scene res://tests/verification/probe_expedition03_save_roundtrip.tscn
```

真实渲染用原生窗口，不带headless。加载正式ExpeditionLevel03_3D.tscn，游戏灯光/雾与观察相机截图分开注明；需要时补选关→加载界面的正式入口链。不要用摄影棚补光证明游戏内效果。

工程根门禁：

```text
python3 scripts/check_documentation_contracts.py
python3 scripts/check_level_decoupling.py
python3 scripts/check_asset_runtime_naming.py
python3 scripts/check_asset_registry.py --scope structure --ledger scenes
python3 tools/asset_pipeline/verify_ledger_split.py
git diff --check
```

依赖不在时使用工程外临时依赖环境。失败按来源记录，不批量接受历史哈希、改阈值或改完成状态消除红项。只改Skill/文档时不重复启动游戏验收；应验证Skill结构、范围拒绝、准备器真实隔离路径和安装字节一致性。
