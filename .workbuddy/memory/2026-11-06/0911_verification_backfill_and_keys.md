# 0911 四个孤儿验收登记 + 收招两处缺陷修复 + 钥匙口径拉直

## 做了什么
4 个 `unregistered` 验收全部登记（`VERIFICATION_REGISTRY_OK scenes=277`，core 224 / visual 41）：
- `verify_base_lamp_dynamics` → core，原样通过（N1–N12，ACCEPT）。
- `verify_base_lamp_visual` → visual，真渲染通过（V1 六通道 + V3 关灯态）。
- `verify_stairwell_turn_rail` → core，**修判据坐标系**：旧稿拿世界常量 -6.0 当折返平台楼面，
  层高 12m 后 99↔98 楼梯间可视根在世界 -12 ⇒ 护栏高被算成 -10.845m。改成楼梯间装配根局部坐标
  （半层层高）+ 向下射线复核（只对外沿段，内侧段最高点是上行踏步 -5.508 而非 -6.0），
  并新增「楼梯间不可见时护栏碰撞必须卸载」的开合判据。
  **关键坑**：`PROCESS_MODE_DISABLED` 的子树连碰撞体都不进物理步进 ⇒ 打开连接器要同时恢复
  visible / process_mode / collision 三样，少一样射线一根都打不中。
- `verify_enemy_action_recovery` → core，按当前 AI 节奏重写（checks=3278、notes=9）。
  旧稿整张作废：EGT 收招已按攻击方式分档 0.08~0.18s；快照键 `skill_effect_active` 已删（连发改
  `_pending_volleys`），旧稿从第一帧就抛异常、从未跑完。

## 顺带修的代码缺陷（src/enemy3d/Enemy3D.gd）
1. 收招段 `_brake_planar` 之后 `_push_planar(_external_velocity)` = 稳态放大器：
   击退 5.0 → 9.7 → 14+，玩家一拳把怪打飞出房间。改成外推生效时直接赋值。
2. `_pending_volleys` 按延迟无条件开火，`transition_to` 从不清 ⇒ 死掉的怪在半空打完剩下 3 发。
   现在进入 stagger/dormant/dead 清空（recovery→chase 不清）。

## 记了没改（待业主裁决）
- 近战结算不看视线（只有胖子查 LOS），贴薄墙会被打到；历史如此，非本轮回归。
- **P1 候选**：体型缩放放大 `move_and_slide` 位移。同样 velocity=7.2：scale 0.7 → 0.120 m/帧；
  scale 1.05 → 1.080 m/帧（约 7 倍，非线性）。影响 `_strong`、精英 2.5×、Boss，
  意味着 speed 配置值已被实测调参吸收了缩放误差，改缩放会整体跳变。
- 收招是线性刹车 18 m/s²，「突进后静止窗口」在当前 build 不存在（0.4s > 0.34s）。

## 钥匙口径（拉直后）
- 判据是能力 `Dungeon3D._room_key_economy_enabled()`（默认 true，`TowerDescent3D` 在 flow 规则下覆写 false），
  **不是关卡 ID 分支**（解耦门禁 violations=0）。
- 远征03 整条退役：宝箱 requires_key 删 + fate_card_per_open=0；怪物掉落表删钥匙小子行；
  清房拾取池删钥匙行（权重 24.36，剩三项归一化 40.405/6.09/3.045）；开局钥匙清零；
  清房钥匙不再生成；命运卡太阳钥印不进报价池；状态栏不写「钥匙已掉落」。
- 文档偏差（已修）：04 §249 太阳钥印、04 §718 HUD 说显示钥匙（实测只在开门时状态栏报「剩余钥匙 N」）、
  05 §5.4 保底返还钥匙（已补远征03 例外）、怪物设计 §T8 表「钥匙小子必掉钥匙=缺失」+ §T2.7「奖励层缺位」。
- 未修：12 完成度清单没有远征03 章节；物品道具账本/内容数据库的 item_room_key 掉落池列是全局口径
  （对 EGT 已不成立，但字面不算错）。

## 产物
- docs/v0.1/development/2026-11-06_verification_registry_backfill.md（主力记录）
- docs/v0.1/audits/2026-11-06_design_vs_build_audit.md（D2 已结、新增两条待裁决）
- CHANGELOG 一条 + MODULE_INDEX 一条
