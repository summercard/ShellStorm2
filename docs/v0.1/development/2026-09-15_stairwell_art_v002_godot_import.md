# 楼梯间 v021 正式导入 Godot

## 定位

- 功能：ASSET-PIPELINE，工程版本0.1.0。
- 源：`assets/art/environments/tower_descent_3d/source/stairs_12m/stairwell_art_v021/env_tower_stairwell_dual_art_source_v021.blend`。
- 目标：将100→99与99→98两套正式美术替换运行时临时楼梯，同时保留既有区块变换、接口和组件归类。
- 回滚：旧GLB v001保留，运行引用可回切；v020源保留为美术回滚版本。

## 实施

导出脚本按装配根分别读取A/B各382个输出网格，在不修改源文件十类集合和组合关系的前提下生成运行派生Blend。每套运行导出合并为三个网格：`StairwellArt_VisualOnly`、`FloorAndFlight_Walkable`、`EnclosureWall_VisualCollision`。后两者分别作为唯一可行走与围护碰撞源，装饰不生成玩法碰撞。

两份GLB版本为v002，不嵌入图片；Godot导入启用`scene_facility_shared_palette_post_import.gd`及`gltf/embedded_image_handling=0`，材质统一回接共享低亮多巴胺色盘。两份PackedScene v002保存AssetID、版本、源版本和碰撞所有者元数据，`TowerDescent3D`改为直接预载包装场景。

## 验收

- Godot资产重导入退出0；两份v002均执行共享色盘后处理。
- `verify_tower_grid_component_alignment.tscn`退出0：15×30m接口、v002/v021元数据、3网格及碰撞命名合同通过。
- `verify_tower_descent_flow.tscn`退出0；报告2项既有退出清理资源占用提示，不影响断言和退出码。
- `verify_tower_level_blocks.tscn`退出0；报告2项既有退出清理资源占用提示，不影响断言和退出码。
- `verify_tower_descent_visual.tscn`使用Metal Forward+真实渲染器退出0，生成`outputs/verification/tower_godot_stairwell_global_light_ph49.png`等场景采样；正式楼梯美术已出现在99层下行流程。
- GLB结构：每套3个Mesh、3个共享色盘角色材质、0张内嵌图片、0个纹理资源；每套碰撞源为1个Walkable和1个EnclosureWall。
- 预期故障注入：未执行。非预期脚本错误：无。导入时其他既有资产报告共享色盘UID回退警告，不属于本次两份楼梯资产。

## 台账与状态

`asset_import_manifest_v001.json`、主设计、模块索引及`ShellStorm2_美术资产台账_v001.xlsx`的两条楼梯记录已更新为v002正式美术接入；台账保留既有行与格式，仅更新路径、版本、哈希、状态、碰撞与验收说明。

## 运行碰撞修复

首次接入后发现合并网格丢失旧版按独立梯段/墙段设置的摄像机语义，且离散踏步与楼板唇边会阻挡角色。修复仅发生在Godot运行包装：合并Walkable改到camera-only层并标记为楼板/楼梯净空源；按既有11点楼梯路径为坡段和平台生成0.20m厚连续承重面；合并围护的玩法同形碰撞保持不变，并依据其世界包围盒在南边界增加独立camera-only墙代理。Blender源、GLB几何、材质和组件集合均未修改。

修复后`verify_tower_grid_component_alignment.tscn`、`verify_tower_descent_flow.tscn`和`verify_arrival_gate_floor_bundle_flow.tscn`均退出0；专项同时断言每个楼梯间恰有一个Walkable摄像机净空源、一个南墙摄像机代理及不少于四段连续承重碰撞。

### 一体承重模型修正

用户继续反馈分段阻挡存在卡住/掉落风险。内部承重改为`StairUnifiedSupport`唯一静态体及唯一封闭三角碰撞形状：整宽上层楼板、两跑连续坡面、整宽折返平台与下层楼板共用边界顶点，内部无竖直封边。删除原内部路线盒体，仅上下门外接驳段保留独立承重。美术Blend和GLB未修改，摄像机净空/南墙代理保留。

独立隔离存档验收`verify_stair_unified_support`退出0：48,245个表面射线采样无缺口，半径0.43m胶囊角色沿完整路线下行与逆向上行均抵达各节点，无卡住/掉落。该结果替代前一节仅统计分段碰撞数量的验收；未执行人工游戏操控验收。

### 摄像机坡面与栏杆阻挡修正

根据实机反馈，合并Walkable不再进入任何碰撞层，也不再作为整段楼梯的摄像机净空源。运行包装只为下跑创建一块`LowerFlightCameraSlab` camera-only坡面；上跑及其北向台阶面不会触发动态镜头。上下两跑各补齐左右栏杆阻挡；上层楼板边缘按可见模型的两段栏杆分别生成阻挡，中间楼梯入口保持开放，每个楼梯间共6段，均随楼梯区块流送统一启停。此次只修改Godot运行碰撞及验证，不修改Blender源、GLB、材质或组件集合。

`verify_stair_unified_support`退出0：48,245个承重表面采样、角色胶囊双向通行、下跑摄像机坡面命中、上跑摄像机层零命中以及6段栏杆阻挡全部通过。`verify_tower_grid_component_alignment`与`verify_tower_lighting_wall_combat_regressions`退出0。预期故障注入未执行；非预期脚本错误为0。既有共享色盘UID路径回退警告仍存在，与本次两份楼梯资产无关。

实机继续发现理论坡面会切入可见踏步，且旧`GUARD_END_CLEARANCE_M=4m`被误用于玩法栏杆，导致每跑两端各4米没有阻挡。运行承重顶面现统一抬高0.18m，使角色胶囊始终位于踏步表现之上；梯跑栏杆改为覆盖完整15m水平行程并在两端各重叠0.20m。随后纠正错误加在折返中心线上的整宽阻挡：按Blender v021真实楼板边缘栏杆范围改为0.22–9.06m与13.94–14.78m两段，中间4.88m入口及折返通路保持开放。专项增加两跑、两段楼板栏杆命中射线和入口零栏杆命中，并恢复角色抵达真实折返中心的双向通行。`verify_stair_unified_support`退出0；两套实例结构断言与正式下降流程断言均完成，但各自runner在退出清理阶段报告同一组2个既有资源仍占用并以4退出，未发现本次功能断言或脚本错误。

再次实机复核确认整口卡住的主因不是栏杆，而是0.18m抬升错误覆盖了上下层整块楼板，在接驳地面与楼梯间边界生成横跨入口的竖直门槛。现仅在两跑坡面中段保留0.18m抬升，坡脚和坡顶各用1m长度线性回接原楼板；上下楼板与折返平台恢复准确标高。楼板边缘栏杆同时按6m梯跑净宽收口，不再用可见扶手悬挑端侵占角色胶囊净空。新增`verify_stair_entry_clearance`以正式玩家0.34m半径、1.5m高胶囊在99→98上口横向5个位置实际穿越接口，退出0；一体承重48,245点及双向通行专项继续退出0。

### 单坡面与栏杆转角闭合修正

按最新实机要求，取消每跑“1m回接 + 抬高主体 + 1m回接”的三段坡面；`StairUnifiedSupport`现在每跑严格只有一张从坡脚到坡顶的连续斜坡面，端点与楼板/折返平台精确同高，可见踏步继续不参与角色碰撞。图示楼板栏杆与梯跑扶手转角的漏口来自旧6m净宽边界和v021可见扶手中心之间约0.85m偏差，现以可见扶手中心为收口基准并各搭接0.15m，中央通行口不变。`verify_stair_unified_support`退出0（48,245点、双向通行、6条栏杆命中及两处转角命中）；`verify_stair_entry_clearance`用两套楼梯、两跑、双侧、坡脚/中段/坡顶共24组正式角色胶囊穿越尝试验证栏杆不可穿，功能断言0失败并退出0。仅修改Godot运行碰撞与验证，Blender源、GLB、材质和集合均未修改。

扶手穿越的后续根因是碰撞与可见模型横向不重合：程序曾按6m承重面外缘把阻挡放在梯跑中心±3.12m，而Blender v021两侧可见扶手中心实测为±2.15m，留下约0.97m可见栏杆可穿区域。四条梯跑阻挡现统一贴回±2.15m模型中心线。`verify_stair_entry_clearance`升级为对Stair_A与Stair_B的上跑、下跑、左右侧共8处使用正式玩家胶囊持续横向冲撞；角色中心不得越过扶手内缘且必须命中`stair_guard_collision`，功能断言全部通过。runner仅在退出清理报告既有2资源占用并以4退出。
