# 2026-11-18 界面排版与模态收放

- **关联功能**：UI-HUD、INVENTORY-SLOTS、PRESENTATION、WEAPON-COMBAT / FATE-RULES（仅表现层）
- **工程版本**：以 `project.godot` 为准，未升级版本
- **用户范围**：不改游戏逻辑、不改命运卡购买/扣款/退款/飞卡事务、不改存档、不改输入锁语义、不改棱镜线框风格。

## 实际修改

1. K 键武器构建页与命运购卡页
   - 构建板根连线由枪身模型中心改为枪械区与卡巢区之间的中线，再横向接首个卡巢左中。
   - 首巢滚出视口时仍止于视口边界。
   - K 页与购卡页加入左右箭头；箭头只切换 `get_equipped_weapon_item_for_slot()` 返回的只读武器快照，使用同一块构建板横向滑入，不调用 `switch_weapon_slot()` / `request_weapon_slot()`。
   - 购卡候选、价格、确认、扣款、退款、来源选择、飞卡落巢和教程锁保持原Owner与生命周期。

2. 模态打开时四角 HUD
   - K 页、背包、命运购卡模态打开：`PlayerStatusBlock`、小地图、翻滚环、武器栏、快捷栏向各自屏幕边缘展开。
   - 关闭后回到记录的原位置。
   - 只改变 `Control.position` 与 Tween；节点路径、Presenter字段和输入锁保留。

3. 装备页排版
   - 左侧装备区扩大，占用原中央空白；右侧背包棋盘保留。
   - 主/副武器预览槽放大；枪下增加只读命运卡面行，保留配件格；弹药名称文字隐藏，只保留子弹模块图标。
   - 角色预览扩大；装备页HP文字与血条隐藏，但节点和HP刷新路径保留。
   - 角色下方保留背包、特殊道具、快捷物品；底部新增月亮命运卡面展示。
   - 运行时规则、拖放、交易、背包8列/保险8×2、关闭/ESC栈未改。

## 代码与文档

- `src/ui/weapon_build/WeaponBuildBoard.gd`
- `src/ui/WeaponAssemblyTreePanel.gd`
- `src/ui/weapon_build/FateHologramPresentation.gd`
- `src/ui/InventoryUI.gd`
- `src/world3d/Dungeon3D.gd`
- `tests/verification/verify_weapon_hologram_ui.gd`
- `docs/v0.1/design/战斗奖励与物品流转设计.md`
- `docs/v0.1/design/装备与棋盘式包裹设计.md`
- `docs/v0.1/design/UI与UX全局设计及全界面清单.md`
- `assets/registry/ledgers/ShellStorm2_UI账本_v001.xlsx`

## 验证结果

- 改动前副本：`ShellStorm2-backup/2026-11-18_ui_layout_revision/before_edits/`
- Godot 编辑器无头解析：退出码 0；未发现 `SCRIPT ERROR`、`Parse Error` 或 `ERROR:`。
- `git diff --check`：通过。
- UI账本结构读取：R/S派生公式仍存在；域变更日志追加 `v0.2.10`。
- 资产结构门禁退出码 1：输出仅包含既有 `enemies` 行55 与 `vfx` 行62 的状态值不合法，本轮UI账本改动未新增该红项；未批量修复无关历史项。

## 未执行 / 待补

- 尚未完成正式窗口化真实渲染截图与逐项视觉验收。
- 尚未完成 `verify_weapon_hologram_ui`、`verify_inventory_experience_visual`、`verify_reference_hud_fate_visual` 专项运行。
- 尚未运行完整文档契约门禁与关卡解耦门禁；代码解析通过不等于运行时视觉验收通过。
- 资产账本哈希未因代码UI变更伪造更新；代码路径说明与UI行备注已同步。
