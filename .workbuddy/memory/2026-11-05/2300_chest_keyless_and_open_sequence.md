# 宝箱：免钥匙直开 + 命运卡购买 + 钥匙退役 + 开箱前后过渡

时间：2026-11-05 23:00 ~ 23:55

## 业主口径（三轮，按顺序）

1. 「宝箱开启方式是直接开启，开启的同时会弹出命运卡购买界面，同时也会掉出掉在地上那个物品。
   不需要使用钥匙，远征03 的这个钥匙掉落可以全部去掉，不需要钥匙掉落。」
2. 追问确认：**只弹购买界面，不再自动发 1 张命运卡。**
3. 「打开宝箱需要有前置动画，点击之后宝箱会抖两下，然后箱子砰的一下打开，然后才会弹出命运卡界面。
   整个过程中需要有前置和后置，不要突然打开完全没有过渡。」

## 落地

- 开箱时间轴（`TreasureChest3D`）：抖动两周期 0.42s → 回正 0.05s → 蓄力 0.12s →
  **砰** 0.14s（盖子 −122° 过冲、箱体上跳 5.5cm、光 3.2→7.0、音效、镜头冲击）→ 余韵 0.36s。
- 掉落绑在「砰」那一帧（`get_open_burst_delay()`），购买界面再等 0.30s 并以 0.18s 淡入。
- 新增 `OpenPhase` 枚举、`burst` / `open_animation_finished` 信号、快照阶段字段。
- 钥匙经济在远征03 整条退役：能力判据 `_room_key_economy_enabled()`（仅 flow 关卡 false）。

## 查出的 P0（重要）

**远征里按 E 开箱从来没生效过**（2026-10-29 起）。`TowerDescent3D._append_plan_room_record()`
自建远征房间，6 个房间信号里漏接 `chest_open_requested` ⇒ 信号到房间层就断，
`Dungeon3D._on_chest_open_requested()` 从未被调用；表现是「箱子抖、音效响、什么都不发生」，不报错。

之前几轮宝箱/拟态验收全绿，因为探针直接调处理函数，正好绕过断链。

**教训（长期有效）**：凡是「信号 → 处理函数」的链路，验收必须至少有一条走信号的断言。
补了 `_egt_chest_probe` 第 ⑧ 条（`perform_interaction()` 开第二只箱），修前红、修后绿。

## 本轮踩到的其它坑

1. `OPEN_BURST_DELAY_SECONDS` 漏算回正 0.05s ⇒ 掉落比「砰」早 0.05s。回正提成常量并入总和。
2. 蓄力 tween 与弹盖 tween 抢 `rotation:x` ⇒ 砰那帧盖子只动 2.5°。`_fire_burst()` 先 kill。
3. 蓄力用 `EASE_IN` 时前半段几乎不动 ⇒ 换 `EASE_OUT`。
4. 渲染取景按**关着**的箱子算 ⇒ 开盖后盖子出画；`get_image()` 同步阻塞导致采样点漂 0.14s
   ⇒ 改协程 + `Time.get_ticks_msec()` 绝对时钟。
5. `PlayerCameraFeedback3D` 包络分母写死 `SHAKE_DURATION` ⇒ 短震动振幅被压掉 92%。
   改成按本次震动时长算，`request_environment_impact()` 加 `duration` 形参（缺省不变）。

## 验证

- `_egt_chest_probe` / `_egt_mimic_chest_probe` / `_egt_drop_probe` 全绿。
- 变异测试：把 `_play_open_sequence()` 直接跳终态 ⇒ 探针报 2 条红（证明断言不空转）。
- 真实渲染：`outputs/verification/egt_chest_open_sequence.png`（六帧序列）。
- 未执行：`verify_fate_card_purchase_flow` / `probe_expedition03_playable` /
  `probe_expedition03_save_roundtrip` —— 被**既有**预检红（27 项房间门位指纹漂移）阻断。

## 账本注意

`scripts/sync_inventory_item_ledger.py --write` 会**抹掉**账本里已有的 8 行远征03导航
（脚本只从 expedition_01 + 掉落 CSV 生成）。改远征03掉落时不要跑 `--write`，按行手改。
