# 99F 基地 NPC「绿苔」观感返工（BASE-NPC r3）

工程 0.1.0 / FeatureID `BASE-NPC` / 设计修订 r3。业主一次性给了六条实机截图反馈，全部落地。
设计文档 `docs/v0.1/20_技术施工_基地NPC.md`，开发记录 `docs/v0.1/development/2026-11-02_base99_npc_green.md`。

## 六条口径与改法

| 原话 | 改法 |
|---|---|
| 为什么是自发光的绿色？荧光感太强了 | `NpcCatalog.SKIN_EMISSION` 0.30 → **0**，不再 `emission_enabled` |
| 头要和角色一样大，现在大了很多 | 补 `Player3D.DEFAULT_BASE_SIZE_MULTIPLIER`（0.8）—— 玩家是**运行时**乘的，`Player3D.tscn` 里是原始尺寸 |
| 对话框太小了 / 大一倍先 | 气泡 `pixel_size` 0.0026→0.0042→**0.0084** |
| e 交谈提示要接近才出来 | 交互半径 2.4→**1.5m**，热区中心 0.9→0.6 |
| 白点去掉 / 名字也去掉 | `is_interaction_dot_visible()=false`；撤 `NameLabel`/`RoleLabel`；只留黄色 `[E] 交谈` |
| 点交谈后角色要立刻停下来面对角色 | `_talk_engaged`：按 E 瞬时停步 + 朝向吸附（不插值）；离开范围才解除 |

「行走有残影」与第 1 条**同源**：99F `WorldEnvironment` 开着 `glow`（bloom 档 `glow_intensity 0.72`），自发光体移动会拖光晕。关自发光后一起消失。

## 五个必须记住的坑

1. **`wrap_width_px` 不能跟 `pixel_size` 一起翻倍**。两者都 ×2 时，20 字台词刚好塞一行 ⇒ 气泡变 **8.27m 宽横幅**横跨屏幕（实拍）。字号 ×2、折行保持 560（≈11 字/行）才是两行 4.7×1.21m。
2. **气泡抬高要按新的半高算**。字放大一倍后半高 0.605，中心 1.88 时底边只剩 1.275，压在兔耳上；取 **2.05** 才对。
3. **NPC 体型必须抄 `Player3D` 的 0.8**。`_initialize_debug_scale_contract()` 里乘的，`Player3D.tscn` 场景实例是原始尺寸。漏了就是大 25%，头顶那一圈最明显。
4. **解除"搭话定住"不能用气泡消失作条件**。气泡 6s 自动收，NPC 会在玩家还站着时自己走开。用"玩家离开交互范围"。
5. **本机 Git Bash 的 `timeout` 会吞环境变量**。`NPC_SHOT_HOUR=12 timeout 300 godot ...` 里脚本读到的是空串 ⇒ 退回默认路径/时间，截图看起来"参数没生效"。**别套 timeout**。

## 并发写冲突（本轮真实踩到）

另一个会话把这批改动**整批回滚到 HEAD**：`TowerDescent3D` 的 `_install_base_npc()` + 三个只读方法、`suit_green` 衣柜变体、账本第 31 行、`MODULE_INDEX` / `feature_registry` / `CHANGELOG`、套件注册，全没了。

**发现它靠的是真实渲染截图**：NPC 渲染成洋红色 —— 那正是 `NpcCatalog.get_skin_albedo()` 取不到衣柜变体时的设计行为（醒目失败，不悄悄换绿）。如果只看 `git status` 会漏掉：**被回滚的文件是干净的**，不显示为改动。

⇒ 多会话并行时，要按「文件是否仍是 HEAD 版本」复核改动清单，不能只看有没有 diff。

## 验收

`verify_base_npc_flow` 扩到含 8 组新断言（A13b 体型 / A14b 无自发光 / A14 头顶无多余 Label / A20b 2.0m 不给候选 / A20c 圆点 invisible / A22b 按 E 定住转向 / A22c 定住期间不漂移 / A24b 气泡底板实测 ≥3m / A25b 3s 内恢复巡逻），**exit 0**。

- `verify_player3d_diy_flow`、`verify_wardrobe_preview_fill_flow` 回归通过
- 账本三件（structure 1418 / full 26 / split）绿；命名 gd 23·tscn 93 绿；追溯 44 绿；关卡解耦绿
- 文档契约 exit 1，17 条**全是既有红项**，逐条筛过没有一条指向 NPC 文件
- `check_verification_registry` 仍红：4 个历史场景未登记（`verify_base_lamp_dynamics` / `verify_base_lamp_visual` / `verify_enemy_action_recovery` / `verify_stairwell_turn_rail`），**不含** `verify_base_npc_flow`

证据图四张在 `docs/v0.1/audits/evidence/2026-11-02_base99_npc/`：noon / night / closeup / prompt。

## 账本

重建第 31 行 `CHR-PLY-BUNNY01-NPC-GREEN`（原型已接入，`scenes/BaseNpc3D.tscn`）日志 `v0.1.27`；bunny01 根变体行补 `suit_green` 记法 `v0.1.28`；查重公式 R/S 区间重写到 `$R$6:$R$31`。
新增 `scripts/refresh_ledger_baseline_npc_polish.py`：只重算基线逐列指纹，绕开 `register_base_npc_ledger.py` 的"新增集合必须恰好是 NEW_ID"断言（重跑必挂）。
