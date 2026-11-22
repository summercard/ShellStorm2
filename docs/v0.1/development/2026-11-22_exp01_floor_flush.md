# 2026-11-22 远征01棋盘地砖补缝

设计见[远征01设计](../design/远征关卡01设计.md#13-棋盘地砖接缝2026-11-22)。截图种子 1711333344 的 03 号房使用战局 C01/C02；原底板 4.94m 与 5m 槽位相差 0.06m。以已交付 GLB 恢复精确发布几何，派生两份 Blender 源及独立优化文件，将基础板平面尺寸扩至 5m，沿用面材、色盘 UV、上层饰面与碰撞。优化与哈希见 `art_source/environments/tower_zones/expedition/source/common_components/floor_tile_flush/v001/asset_manifest.json`。

两款专用 PackedScene 由 12 份远征01主路静态布局引用。复用这些正式布局的四个秘室模板也会继承变体。Boss 深井使用自身地板。场景账本补充《3D-场景通用》P91/P92 和《资产主表》Y243 的变体追溯。

## 验收

- Blender 4.3.2 导出两款，Godot 4.7.2 实际重新导入，均退出 0。原共享 GLB 哈希复核一致。
- Windows Compatibility 使用截图种子进入 03 号房，实测 48 块地砖的视觉包围盒 X/Z 均为 5m，碰撞仍为原 4.94m。退出 0，最终运行的非预期错误 0。
- 画面证据位于工程外 `ShellStorm2-work/probes/2026-11-22_exp01_floor_flush/qa_final/room_03_floor.png`。保留蓝色装饰接缝。
- 接续复核：隔离用户目录后，Windows Forward+ 用相同种子进入 03 号房，48 块地砖全部通过，退出 0；无脚本错误，仍有既有资源 UID 回退警告。清单所列 8 个源文件、运行模型和原共享模型哈希一致。复验图见工程外 `ShellStorm2-work/probes/2026-11-22_handoff_recheck/room_03_floor.png`。
- 未执行全关通关与秘室逐房截图。
