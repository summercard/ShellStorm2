# SKYLINE 8层大楼 Blender 美术源

- FeatureID：ASSET-PIPELINE；工程版本：0.1.0；日期：2026-09-30。
- 用户范围：按提供的天台参考图制作整栋8层楼，下方未绘出的楼层重复；重点深化天台，沿用堡垒之夜式夸张形体和色块，不制作写实材质。
- AssetID：`ENV-OPENWORLD-SKYLINE08`；最终源版本：`v004`；源状态：**Blender源已完成**。后续Godot景观导入与验收记录见文末独立阶段。
- 独立开放世界视觉资产，新增于 `skyline_08`；既有塔2、塔楼03、主场景及其运行资源没有作为输入，也没有被修改。

## 制作范围与尺寸

32×24m主体，8个4m高的重复窗墙模块，地面Z=0，天台完成面Z=32m，广告牌最高Z=45.68m。层高为参考图美术推定，不继承主塔战斗层12m契约。四面均补齐外立面；下部楼层不制作室内玩法空间。

天台实际几何包括：破损画布与卷边、蓝色城市剪影与橙色落日、广告牌钢柱和交叉撑、基础螺栓、两侧格栅检修台、五盏顶部投光灯、配电箱与垂挂电缆；七个独立SKYLINE厚字壳、包边、轮廓灯泡与安装轨；机房、铁门、门灯、通风百叶、爬梯、卫星天线、涡轮风帽；双风扇及单风扇冷凝器、分节风管、铜管走线、护栏；地砖拼缝、裂纹、杂草、连续反光积水和固定陈设。

每个源组件可编辑；楼层采用链接网格重复。保留七个可编辑字体对象，字体嵌入Blend；公共色盘保持外链。油桶、篷布、砌块登记为固定展示陈设，不赋予拾取/库存语义。

## 交付与整理

- [最终Blend源](../../../assets/art/environments/open_world/source/skyline_08/v004/SKYLINE大楼_8层_精细天台_v004.blend)。
- [组件计划](../../../assets/art/environments/open_world/source/skyline_08/v004/component_plan.json)：28类定义，实例另计。
- [catalog与252包清单](../../../assets/art/environments/open_world/source/skyline_08/v004/catalog.json)：17建筑包、192地砖包、18招牌包、23设施包、2支持包；每包具有Collection与对应磁盘manifest。
- [天台参考镜头](../../../assets/art/environments/open_world/source/skyline_08/v004/previews/01_天台参考镜头.png)、[8层全景](../../../assets/art/environments/open_world/source/skyline_08/v004/previews/02_8层完整楼体.png)、[俯视](../../../assets/art/environments/open_world/source/skyline_08/v004/previews/03_天台俯视结构.png)及三个设备/广告牌/背面镜头。
- `01_制作组件`默认隐藏，`02_游戏输出`默认可见，展示镜头和灯光归`90_展示与验收`。
- v001/v002/v003保留作本次迭代回滚；v004为本批次正式源。制作代码位于`tools/blender/build_skyline_08_source_v003.py`。

## 验收证据

Blender 4.5后台重开源文件，Cycles真实渲染6张图，人工检查参考构图、设备、广告牌、顶视与背面。几何为风格化还原，未宣称参考图像素级一致。

- [逐面色盘验收](../../../assets/art/environments/open_world/source/skyline_08/v004/qa/palette_validation.json)：退出0；源与输出全部536网格，83,708/83,708面UV岛位于单一色格安全区，活动/渲染层均`PaletteUV`；只有4角色材质，公共512色盘外链、Closest，无私有色盘副本或材质残留。
- [独立结构与目录验收](../../../assets/art/environments/open_world/source/skyline_08/v004/qa/source_audit.json)：退出0；8层高度、Z=0基准、252包与252清单一致，192地砖，高度与包络匹配，无空包/多包归属/未登记输出/未应用修改器；268输出网格、41,854面、71,262顶点。
- [账本登记](../../../assets/art/environments/open_world/source/skyline_08/v004/qa/ledger_registration.json)：场景分账本第563行，制作状态为Blender源已完成；复制写前快照并确认历史内容列及全部历史资产指纹不变。
- 工程级门禁基线与最终结果记录于[交付QA](../../../assets/art/environments/open_world/source/skyline_08/v004/qa/QA_REPORT.md)。工程历史债务不以本资产验收通过替代。

上述Blender制作阶段没有执行GLB、Godot PackedScene、碰撞、LOD或正式场景接入；后续景观运行接入单独记录如下，不回写历史验收口径。

## 用户后续灰阶要求（v004）

用户要求不要纯白，所有白色向暗灰移动两档。保留原灯光、机位和几何，将公共色盘R10C10改为R8C10（#8998AA），R9C10改为R7C10（#718195）。31324个唯一网格面完成UV移动，最浅两档剩余面数为0；几何签名前后一致。6张预览已用相同镜头重新渲染。源、清单与账本同步为v004。验证见qa/white_darkening.json。

## Godot 大地图景观接入（2026-09-30）

- ASSET-PIPELINE；工程版本0.1.0；用户指定v004源，按塔2/塔3逐包派生流程导出252个GLB及252个独立组件PackedScene，再由稳定整楼场景 `assets/art/environments/open_world/runtime/skyline_08/env_skyline_08_root_top3d.tscn` 装配。不导出整楼GLB，不改变源几何。
- 导出源SHA-256 `2a41fb5d67132305924c7c3b8b89b12d6e4519fbed0f93d8e7a14bdfbafa5d67` 保持不变。派生Blend与逐包哈希见 `source/skyline_08/export/v004/export_manifest.json`；100599三角面、339表面，GLB无内嵌图片/纹理、展示相机或灯光。
- 严格不新增材质球：后导入钩子清除新GLB缓存材质，包装入树时绑定塔2既有四角色材质；验收逐表面核对资源路径与对象同一性。所有 `.tres` 集合及内容哈希保持不变，仍使用既有公共色盘、最近邻与禁用MipMap。
- 正式布局所有者为跨塔路线TSCN。实测东向+X，塔2原根 `(20,-100.5,-90)`；最终塔2 `(40,-100.5,-90)`，景观 `(10,-100.5,-90)`；塔3 `(-12,-40.15,-173.925626)` 不动。仅新增景观实例并改变塔2根X，原桥、塔3及路线碰撞不动，既有主场景与云海改动保留。
- Godot4.6.3正式 `--headless --import` 退出0；真实Windows/OpenGL Compatibility / RTX4060Ti验收9481检查、0失败、退出0。252组件与整楼独立加载、底面0、根缩放1、无玩法碰撞及新MultiMesh、材质对象复用、坐标与逐组件包络通过。整楼Godot XYZ包络33.020×45.680×25.935m。
- 清单转正，场景分账本《资产主表》第563行更新运行入口并追加252组件行（564–815）；《3D-场景通用》追加253实际Prefab行。状态为“已导入；优化完成”。总目录仅更新索引计数，不登记资产行；无关资产内容与基线指纹不变。
- 验收文件与六张截图位于 `outputs/skyline08_import_20260930/`；`01_asset_whole.png`/`02_asset_roof.png` 为独立场景，`03_actual_scene.png`/`04_actual_skyline.png` 为实际主场景；`05_layout_diagnostic.png` 仅测试期关闭雾与云海；`06_route_isolated_diagnostic.png` 在相同正式路线实例坐标下额外临时隐藏外围几何，排除主塔遮挡。上述诊断均未保存正式场景参数。逐表面339×3=1017次核对均通过；451保护文件未变。
- 注册结构与账本无损基线退出0。场景全量仍有152条既有SHA不一致；与任务最初的 `ledger_before.log` 逐条完全一致，新增0项（中途路线已修改但尚未登记时的153条不作为任务初始基线）；运行命名门禁仍有14个带版本文件、3目录及引用93→97的既有债务；文档门禁仍因4个无关专项未注册而退出1。未修复、放宽或更新债务快照。
- 告警：用户指定的原尺寸根坐标导致景观与塔2视觉包络交叠，截图中存在遮挡；包围盒交叠不等同逐三角面穿插验证，不擅自移动/缩放消除交叠。旧主场景部分资产仍提示色盘UID无效并回退有效文本路径，本批材质和色盘检查通过。仅景观表现可用，不宣称楼内可行走、导航或移动端性能验收。未Git提交。
