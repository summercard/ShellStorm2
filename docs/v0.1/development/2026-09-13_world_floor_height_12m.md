# WORLD｜塔楼层高调整为12米

日期：2026-09-13  
范围：WORLD-PLAN、WORLD-GATE、塔楼/基地墙体与跨层连接资产

## 目标与边界

- 标准层高由9米改为12米；楼层世界坐标统一按`-12 * floor_index`计算。
- 玩法墙体保持完整12米阻挡；可见墙体原生制作成11.9米，继续保留0.1米楼板防共面间隙。
- 门净空2.2×2.5米、5米平面网格、房间平面尺寸、门的玩法规则与设施位置不变。

## 实施

- `TowerGeometry3D`成为层高、逻辑墙高与视觉墙高的单一数据源；小地图、AI与空间注册不再硬编码9米。
- 塔楼实墙/门墙/转角、基地普通墙/门墙/窗墙/转角和100层上层围护全部升级为12米合同；100层封顶由18米改到24米。
- 通用与楼顶楼梯重制为12米双跑资产，每跑20级；下层落地板顶面为-11.9米。
- 基地东侧上行楼梯保留5米起点和东门平面位置，改接12米门槛，门交互与门洞净空不变。
- 基地普通墙、门墙、窗墙、转角墙的GLB导入继承共享色盘后处理；专项检查每个外围墙网格的色盘绑定与最近邻采样。
- 更新相关场景元数据、资产ID、楼层判断、导入清单、美术资产台账和专项验收断言。

## 验收记录

- Blender资产生成：退出码0；版本化Blend与GLB均已输出。
- Godot重导入：退出码0；新12米资产全部可加载。工程仍会报既有共享色盘UID回退到文本路径的warning。
- 专项逻辑通过：`verify_tower_grid_component_alignment`、`verify_tower_lighting_wall_combat_regressions`、`verify_base99_wall_visual_replacement`、`verify_base99_structural_asset_integration`、`verify_floor_visibility_shadow_patch`、`verify_base99_floor_player_collision_flow`、`verify_base99_door_visuals_v021`、`verify_enemy_stimulus_activation`。
- 资产单项通过：`verify_base99_corner_l_v024_import`（退出码0）；确认11.9米视觉、12米双臂碰撞与PaletteUV。
- `scripts/run_verification_suite.sh smoke`：功能断言运行至塔楼网格项并通过，但runner因现有`2 resources still in use at exit`将该场景记为退出码4，未继续后续smoke项；本次未放宽或屏蔽该异常。
- `verify_rooftop_32x32_contract`：12米普通层外墙断言已更新，但用例的既有天台资产断言仍期待v017/39个阻挡，而当前运行时是v021，因与本次层高范围无关未改动该历史断言。
- `python3 scripts/check_asset_registry.py --scope structure`：退出码0，418项资产、0个结构问题。`--scope full`仍因工程全局既有208项SHA漂移失败；本次只同步了本功能受影响的记录，未批量接受其他漂移。
- `python3 scripts/check_documentation_contracts.py`：退出码0，57份文档、332个本地链接、0个问题。
