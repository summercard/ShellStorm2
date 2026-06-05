## 轮次411（2026-05-30 19:17 UTC+8）

### 维度选择
换弹进度条 + 武器装配树标签定位修复 — UI反馈强化

### 设计审查
**问题A：武器装配树标签定位（WeaponAssemblyTreePanel.gd）**
`_draw_node` 中用 `name_lbl.get_minimum_size().x` 计算标签起始位置，但 Label 未加入场景树时返回 (0,0)，导致 fate 标签（◆ 符号）堆叠在节点名称上方。

**修复**：先用 `name_lbl.size.x`（已加入场景树后的实际尺寸），fallback 到 `get_minimum_size().x`。

**问题B：换弹进度条（GameUIManager.gd）**
换弹时 ammo_bar 没有切换为显示换弹进度，仍显示上一次弹药量，导致换弹过程中 UI 反馈不直观。

**修复**：
- `_on_reload_started`：将 ammo_bar 切换为换弹进度模式（蓝色，max=reload_duration，value=0）
- `_on_weapon_reloaded`：恢复 ammo_bar 为弹药量模式（绿色）
- `_process`：换弹期间 ammo_bar 显示 `_reload_progress`

### 本轮改动
1. WeaponAssemblyTreePanel.gd：修复标签定位计算（name_lbl.size.x 代替 get_minimum_size().x）
2. GameUIManager.gd：换弹时 ammo_bar 显示换弹进度（蓝色）

### 修改文件
- `/Users/summercards/ShellStorm2/src/ui/WeaponAssemblyTreePanel.gd`
  - 标签定位计算：优先 name_lbl.size.x，fallback get_minimum_size().x
- `/Users/summercards/ShellStorm2/src/ui/GameUIManager.gd`
  - `_on_reload_started`：增加 ammo_bar 换弹进度模式切换
  - `_on_weapon_reloaded`：恢复 ammo_bar 弹药量模式
  - `_process`：换弹期间 ammo_bar.value = _reload_progress

### 验收标准
- [x] Godot headless --check-only --quit 编译通过 ✅（EXIT 0）
- [ ] 人类试玩：打开武器装配树，装配有命运卡片的枪，确认 ◆ 标签不与节点名称重叠
- [ ] 人类试玩：弹药用完触发换弹，确认 ammo_bar 显示蓝色换弹进度（0→100%）
- [ ] 人类试玩：换弹完成，确认 ammo_bar 恢复绿色弹药量显示

### 剩余风险
1. 人类试玩：确认换弹进度条与 ammo_label "换弹中..." 文字配合正确
2. 人类试玩：确认换弹过程中 ammo_label 显示弹药数值（0/max）是否需要处理（可能与换弹进度冲突）

### 续排判断
**继续排 cron** — 状态维持 `running`。本轮为 UI 打磨，数值体系、怪物系统、武器系统均已稳定。剩余10项均为人类试玩验证项，不依赖代码改动。继续排 cron 等待用户试玩反馈。

### 下轮最可能方向
1. **人类试玩验证（唯一优先级）**
2. 若发现Bug → 针对性修复
3. 若无Bug → 第二关专属怪物类型深化或战斗视觉反馈（屏幕震动/受击闪烁/击杀特效）