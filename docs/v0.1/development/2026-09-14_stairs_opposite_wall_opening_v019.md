# 楼梯间对面留空墙位纠正 v019

## 目标

纠正 v018 对用户绿色标注墙位的误判：恢复误删的右侧一、二楼墙段，将连续双层开口改到对面的左侧首跨。保持主墙装饰、楼板栏杆、二楼墙高和组件分类不变。

## 交付事实

- 当前美术源为 `assets/art/environments/tower_descent_3d/source/stairs_12m/stairwell_art_v019/env_tower_stairwell_art_source_v019.blend`；v018 工具保存版本保留用于回滚和追溯。
- 右侧 `墙体.043/051`、对应一二楼装甲板和竖向骨架恢复；右侧横框恢复完整长度。
- 左侧首跨基线本就没有承重墙模块，本次移除实际覆盖开口的一二楼装甲板及竖向边框，并将三根横框收口至 `Y=2.50m`。
- v019 仍为三个通用组件与七类装饰组件，合计 301 个输出网格；磁盘组件清单同步为 v019。

## 验收

- 范围锁定脚本退出码 0：290 个未授权对象与 v018 完全一致，恢复项、移除项、左右收口包络和 manifest 一致性全部通过。
- Blender 材质/UV专项退出码 0：全文件 640 个网格、21,422 个面通过。
- 输出墙位对调总览和左侧连续双层开口近景。
- 未执行 GLB、碰撞、LOD、PackedScene 或 Godot 运行时替换。

详细结果见 `assets/art/environments/tower_descent_3d/source/stairs_12m/stairwell_art_v019/qa/QA_REPORT.md`。
