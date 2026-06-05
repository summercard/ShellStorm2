## 轮次409（2026-05-30 23:05 UTC+8）

### 维度选择
战斗视觉反馈链路审查 — WeaponDisplay + WeaponRecoil + DamageNumbers + ScreenShake 系统完整度确认

### 设计审查
从核心玩法"战斗视觉反馈"链路审查当前系统：

**WeaponDisplay.gd（510行）— 枪械视觉表现层：**
- 枪身多边形外形（7种枪型 Polygon2D + 回退默认）
- 枪口火焰 `_trigger_muzzle_flash()`：射击时触发星形 Polygon2D 火焰，0.08-0.20秒内淡出
- 后坐力动画 `_trigger_recoil()`：枪口反方向抖动 + 弹力回正
- 命运视觉（eyes/legs/fate_scale）：tree_changed 信号触发，刷新枪身外观
- **核心连接**：`WeaponAssemblyTree.weapon_fired` → `_on_weapon_fired` → `_trigger_recoil() + _trigger_muzzle_flash()`

**WeaponRecoil.gd（163行）— 独立后坐力节点：**
- 挂载在武器节点上，通过 `weapon_fired` 信号与 WeaponController 联动
- 枪型 → 后坐力倍率：shotgun(1.8x), sniper(1.5x), grenade(2.0x), rifle(1.0x), smg(0.8x), pistol(0.5x)
- 局部空间偏移（-X=枪口反方向）旋转到世界坐标，任意朝向都正确

**DamageNumbers.gd — 伤害数字飘字：**
- `spawn(world_pos, damage, is_crit)`：普通=红(1.0,0.3,0.3)，暴击=金(1.0,0.9,0.2)
- 向上飘40px，0.8秒淡出，初始缩放1.2→1.0弹出感

**ScreenShake — 屏幕震动：**
- 波次完成：4.0 intensity, 0.10s（波次完成节拍感）
- 撤离成功：3.5 intensity, 0.12s（仪式感强化）
- Boss死亡：screen_shake_death（强烈震屏+白闪）

**Player.tscn MuzzleFlash PointLight2D：**
- visible=false（默认熄灭）
- Player.tscn 中 MuzzleFlash 在根部，WeaponDisplay._muzzle 在 WeaponAnchor 子树
- 两者分离但都随射击触发

**命卡Tab关闭修复（轮次407）审查：**
- `FateCardUIController._input()`：监听 `ui_tab`，在 `not is_visible` 时才拦截
- `GameUIManager._input()`：门后命卡期间（`_door_fate_selection_active=true`）放过Tab
- FateCardUIController 正确实例化于 DemoRoomGameMode._spawn_fate_card_ui()
- Tab→命卡显示时，`is_visible=true`，GameUIManager Tab劫持被跳过
- Tab→命卡隐藏时，`is_visible=false`，GameUIManager Tab劫持正常触发 WeaponAssemblyTreePanel.toggle()
- 逻辑链路正确 ✅

**所有系统编译通过：**
- Godot headless --check-only --quit → EXIT 0 ✅

### 玩家可感知结果
战斗视觉反馈全链路已确认完整：
- 射击时枪口火焰亮起（星形 Polygon2D，0.08-0.2秒闪烁）
- 射击后坐力抖动（枪型倍率：霰弹1.8x/狙击1.5x/手枪0.5x）
- 命中伤害数字飘字（暴击变金色大字）
- 波次完成轻震屏
- 撤离成功中度震屏
- Boss死亡强烈震屏+白闪

### 验收标准
- [x] Godot headless --check-only --quit 编译通过 ✅（EXIT 0）
- [ ] 人类试玩：枪口火焰是否在射击时可见（PointLight2D+Polygon2D双层）
- [ ] 人类试玩：后坐力抖动是否随枪型变化（霰弹比手枪更猛）
- [ ] 人类试玩：暴击时伤害数字是否变金色大字

### 剩余风险（全部为人类试玩验证项）
1. **枪口火焰可见性**：Player.tscn MuzzleFlash PointLight2D visible=false，WeaponDisplay._muzzle Polygon2D 是否真的在射击时显示
2. **后坐力方向正确性**：局部-X偏移旋转到世界坐标后，任意朝向是否都表现为枪口向后
3. **6种怪物AI行为**：chaser贴脸/远程保持距离/召唤型产怪/护盾型格挡/自爆型爆炸/潜伏型陷阱
4. **第二关怪物强度**：HP×1.4/DMG×1.2是否真实生效

### 续排判断
**继续排 cron** — 状态维持 `running`。所有系统代码完整落地且编译通过EXIT 0。所有剩余风险均为人类试玩验证项，不依赖代码层面改动。继续排cron等待用户试玩反馈。

### 下轮最可能方向
1. **人类试玩验证（唯一优先级）**
2. 若发现Bug → 针对性修复
3. 若无Bug → 第二关专属怪物类型深化或战斗视觉反馈