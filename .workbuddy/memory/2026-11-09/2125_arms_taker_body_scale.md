# 收租人体型：1 级 1.5 倍、12 级封顶 4.00 m

功能：ELITE-ROSTER / ENEMY-AI。契约 r14 → **r15**。

## 业主诉求

「体型初始为 1.5 倍，最上限体型是 4 米。4.07 米或者 4 米，你自己帮我换算一下。」

## 换算（唯一真源链）

`H(L) = 3.5 m（模型 bind）× 0.70（Enemy3D.DEFAULT_BASE_SIZE_MULTIPLIER）× M(L)`
`M(L) = 1.5 + (L-1) × 0.012`

- 1 级 **3.675 m**
- 12 级 **3.998 m**（目标 4.00，per_level 取整 0.012 得 3.9985，差 1.5 mm）

`per_level = (4.00/2.45 - 1.5)/11 = 0.01206 → 0.012`

## 两个必须记住的连带后果

1. **移动圆柱逼近门洞上限**：`R(L) = 0.816 × 0.70 × M(L)` ⇒ 1 级 0.857 m、12 级 0.932 m；上限 `MAX_COLLISION_RADIUS_M = 0.935`，**只剩 3 mm**。
   - 且该钳制只对 `egt_*` 生效，收租人（`melee_chaser`）**不受保护**。
   - 旧参数（1.0/0.06）12 级 `R = 0.948 m` **本来就已越线**，只是玩家没见过满级实体。新参数反而拉回线内。
2. **成长幅度暴跌**：1→12 级只涨 0.323 m（+8.8%，旧参数 +66%）。体型差异几乎全靠 1.5 倍起点。想更明显只能抬上限，但每抬都要先算门（4.07 → 0.949 越线；4.5 → 1.045 必然走不通）。

其它：近战判定 `attack_range` 仍 1.90 m（未动），体型变大后实际空气间隙从 1.58 → 0.64 m，反而更贴合手感。`EliteArmsTakerCombat` 里 `2.55×scale.y` / `1.15×scale.x` / `3.65×scale.y` 自动跟随，无需改。

## 关键发现：夹具一直测的是 fallback

`SecondEliteStateFixture.make_enemy()` **从不传 `elite_growth_profile`** ⇒ `Enemy3D` 走 `get("body_scale_base", 1.0)` 的默认值。全仓收租人专项（state_flow / tactics / roaming）此前测的都是 1.0 / 0.06，不是内容库真值。
真实链路：`EliteRosterService.apply_archive_to_enemy_config()` 里 `result["elite_growth_profile"] = growth_profile`。
已给夹具加可选 `growth_profile` 参数（默认空 = 不动既有行为），体型用例传真值。

**以后改任何 `growth_profile` 里的数值，夹具不传就是白改。**

## 验收

- `SECOND_ELITE_STATE_FLOW_OK checks=1437`（原 1428，+9 条体型断言）
- `ARMS_TAKER_TACTICS_OK checks=257`
- `ARMS_TAKER_ROAMING_OK checks=1766`
- 均退出 0，headless + 隔离 `APPDATA`/`LOCALAPPDATA`

**未跑真渲染**：`src/combat3d/WeaponModel3D.gd` 正被并行会话编辑（mtime 21:22，`Cannot infer the type of "before_ammo"` 等 Parse Error 57 条），此时出图不可信。穿墙观感、血条高度、门洞通过手感**未验收**。

## 环境坑复现

- `godot --check-only --script` 在无 autoload 上下文时会报 `Identifier not found: MonsterAIManager/BaseManager/...` —— 全是假红，别据此判定脚本坏了。
- headless 首次运行（`.godot` 类缓存冷）会吐一批 `Failed to compile depended scripts`，**第二次跑归零**。用 `grep -c` 对比两次即可区分"缓存冷启动"与"真坏了"。
