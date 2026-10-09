# 远征全息城市 · UI 特效包

资产 ID：UI-SCREEN-LEVEL-SELECT；版本 v002；状态：原型已接入，视觉待验收。

本包属于世界空间 UI 特效，不属于战斗 VFX 或基地固定设施模型；原平台模型不复制、不改布局。

| 文件 | 唯一职责 |
| --- | --- |
| hologram_city.tscn | 正式 PackedScene 入口及资产身份 |
| hologram_block.gdshader | 实体 Box 楼块：实例化、延迟生长、波浪与扫描 |
| hologram_wire.gdshader | 悬浮线框 Box：延迟生长与透明轮廓 |
| hologram_field.gdshader | 背景星云，随部署渐显 |
| hologram_frame.gdshader | 入口边框：常亮描边与悬停环流 |
| ../../../../src/ui/HologramCity3D.gd | 确定性城市生成、径向密度、楼顶入口、分阶段装饰及升降粒子 |
| ../../../../scenes/RogueMapSelectMenu.gd | 镜头、压暗、输入、生命周期与原有出发交接 |

资源均为程序几何，不依赖参考图片作为运行时贴图。生成种子 990129，世界比例 0.09；主楼、两入口、周边城市按时间错峰；反向使用同一进度以支持任意时刻取消。完整进入 4.4 秒、退出 3.6 秒。粒子采用实例化小方块簇，只在楼块升降前沿出现，完成后隐藏。

账本：assets/registry/ledgers/ShellStorm2_UI账本_v001.xlsx 既有 ID；同步脚本 scripts/register_hologram_city_ui.py 仅更新目标行及相应基线。

设计：docs/v0.1/design/远征全息城市交互设计.md。
验收：tests/verification/verify_expedition_hologram_city.tscn；--tower 验证实际设施路径。
截图输出位于 _scratch/hologram_city_*.png，不属于发行资产。
表现修订 r3：主体楼群横向约 3.1m，外围追加 42 座不同高度建筑。城市起始由 1.54 秒前移至 0.54 秒，保持原展开速度；继承玩法环境至 1.936 秒后渐变，3.168 秒完成压暗。真实出发可追加 --tower --enter-01 或 --tower --enter-99，验证到达场景而非仅记录按钮 ID。

表现修订 r4：入口标记悬停倍率 1.09 → 1.32，并以 14/s 的收敛率平滑过渡，光标一离开入口即复原（放大/流光/高亮由焦点驱动，焦点与 Enter 的选中目标分开：选中项在移开时保留，焦点如实置 -1）；四条边框加粗至 0.05 并改用 hologram_frame.gdshader，按各自周长占比分配流光相位、以 0.42 圈/秒绕框环流，光头约占周长三分之一并向后拖出长尾。点击入口时触发 0.34 倍脉冲，随后按 5/s 衰减回弹，并保留 0.18 秒展示窗口再交接出发。Esc 关闭改为从按下瞬间起播（关闭曲线回落指数 1.35 / 1.6），消除原 opening 映射反向时相机 1.62 秒、楼群 0.82 秒的静止段。
