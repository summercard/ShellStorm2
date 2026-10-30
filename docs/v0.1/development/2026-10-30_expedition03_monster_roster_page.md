# 远征03 怪物总表：单文件图鉴（2026-10-30）

## 1. 业主指令

> 检查远征03 的怪物列表，每只怪物的数值也列出来，还有对应模型的图片，
> 一张表格全部涵盖，其他信息不要。

结论：产出**一张表**——32 只怪 × （模型实拍 + 名称/ID + 族 + 血量 + 伤害 + 移速 +
攻击距离 + 冷却 + 弹速 + 攻击方式/机制 + 出场房间）。

## 2. 交付物

| 文件 | 用途 |
|---|---|
| `outputs/expedition03_monster_roster/远征03_怪物数值总表.html` | 主交付。单文件，图片 base64 内嵌，发给谁都能直接开；族色 chip 可点筛选 |
| `outputs/expedition03_monster_roster/远征03_怪物数值总表.png` | 整页长图（2520×6300），贴群/贴文档用 |
| `outputs/expedition03_monster_roster/portraits/<kind>.png` | 32 张逐只单拍，同比例尺 |
| `outputs/expedition03_monster_roster/manifest.json` | 每只怪的运行时数值 + 全部行为键原值 |
| `tools/_egt_roster_portrait.gd/.tscn` | 出图 + 导数值 |
| `tools/egt_roster_page.py` | 拼表 |
| `outputs/expedition03_monster_roster/远征03_vs_原作_逐只对照.html` | **保真度核查**（同日追加）：逐只对照原作原型、血量倍率、攻击方式判定 |
| `outputs/expedition03_monster_roster/EGT对照核查.json` | 同上，机读版 |
| `tools/egt_fidelity_audit.py` | 核查脚本 |

复现：

```bash
godot --path . --scene res://tools/_egt_roster_portrait.tscn
python tools/egt_roster_page.py
python tools/egt_fidelity_audit.py
```

## 3. 三个必须说明的口径决定

### 3.1 数值必须走 `configure_from_enemy_data`，不能只调 `apply_profile`

第一版直接 `apply_profile(kind)` 读 `max_hp`，读出 **450**（= PROFILES 的 150 ×
`NORMAL_HP_MULTIPLIER` 3.0）。但实战值是 **150** —— 关卡 `monster_rules.stats.per_kind`
的 `override_max_hp` 在 `configure_from_enemy_data()` 里**覆盖最终值**，`apply_profile`
根本走不到那一段。

两条路差 3 倍。表里写 450 就是假数据，而且是个"看起来很像真的"的假数据
（450 恰好是合法的血量数量级）。

现在出图脚本先 `MonsterInjector.set_level_rules(远征03 monster_rules)`，再
`generate_box_enemy()` → `configure_from_enemy_data()`，读实例字段。
**这条链与游戏里刷怪完全相同**，表里的数就是玩家会遇到的数。

### 3.2 模型契约是朝 −Z，相机在 +Z

第一轮 32 张全是**后脑勺**（`egt_gun_nut.png` 一整排背影才发现）。
`EnemyAvatar3D` 表头写死「根在脚底、朝 −Z」。修正为 `rotation.y = 202°`
（180° 转向 + 22° 侧转露附肢）。

### 3.3 正交尺寸必须固定，不能逐只自适应

固定 `ORTHO_SIZE = 3.0m`、固定机位 ⇒ 图里的相对大小 = 游戏里的相对大小。
逐只 fit 到画面中心会让 10 血的 `blobulin` 和 1000 血的 `gun_nut` 一样大，
那张表就成了"看不出谁大谁小"的假数据。

### 3.4 分裂族三只不能标"体型色"

`blobulon / blobuloid / blobulin` 借 `melee_chaser` 正式 GLB 且**刻意不染色**
（同族同貌，靠体型区分）。此时 `COLORS` 查不到值、落到兜底白 ——
标成色块就是"布洛布是白色的"，与玩家看到的烂衣服僵尸不符。
manifest 里带 `tinted` 字段，页面据此改写成「原贴图未染色 · 同族同貌」。

## 4. 表里的事实（供后续核对）

- 32 只全部有图。远征03 `spawn_roster` 实际调用 31 只；
  第 32 只 `egt_blobulin` 是 `blobuloid` 的死亡分裂产物，不在任何盒子里 ——
  表里「出场房间」一列显式标成「分裂产物」，否则会被当成漏配。
- 血量 10（blobulin / bullat）→ 1000（gun_nut），9 个族。
- `egt_mimic` 未出现在表里：2026-10-30 业主「宝箱还没做正式设计，先不做宝箱怪」，
  已从 `n07` 编成摘除，`box_egt_mimic_trap.json` 与 PROFILES 保留。
- 伤害一列只有 2 个 0：`egt_gunsinger`（辅助不输出）、`egt_gripmaster`
  （原作 Gripmaster deal no damage，只改位置）。
- 冲撞族 4 只的「弹速」列写 `—`：PROFILES 里它们也有 `projectile_speed: 8.0`，
  但那是撞到后附加弹的默认值，不是冲撞速度（真实冲撞速度在 `suicide_rush.speed`，
  11.0 / 10.5 / 10.0 / 9.5，已写进机制列）。填 8 会被读成"这只怪以 8m/s 冲过来"。

## 5. 未做的事

- **逐只实拍核对模型朝向之外的东西**（例如 `egt_king_bullat` 借炸弹果后
  是否还能看出"王"的身份）没有结论 —— 那属美术替换范畴。
- 表只覆盖远征03。塔楼与远征01/02 的原生怪（`melee_chaser` 等）不在范围内。

## 6. 同日追加：与《挺进地牢》第一层的逐只保真度核查

业主问「每只对应原作哪一只、数值和攻击方式是不是都相同」。

### 6.1 核对方式（两层，机械优先）

| 层 | 做法 | 可机读 |
|---|---|---|
| 血量 | 解析参考表 §7 附录的原作血量 ÷ 我们运行时实测 hp，倍率不是 10.00 就判 FAIL | **是** |
| 攻击方式 | 原作是英文行为描述、无可机读结构，逐条人工核对后写进脚本的 `AUDIT` 表 | 否 |

**不要把第二层当机械比对。** 脚本里 `verdict` 是人工判断，脚本只负责把它印出来 ——
这是刻意的诚实，因为原作没有「连发数 → 字段」这种结构可解析。

### 6.2 结论

| 项 | 结果 |
|---|---|
| 血量 | **32 / 32 严格等比 ×10，0 偏差**（15→150、33.8→338、18.8→188 逐只都是 ×10） |
| 伤害 | 全部 17（2 只 0）—— 原作「几乎一切伤害都是半颗心」是全局约定，我们换算成 17 = 100 血的 1/6 |
| 速度 | 序关系对，绝对值不可比（原作只给定性五档，无数字） |
| 攻击方式 | 照抄 13 / 近似 15 / 真差异 4 |

### 6.3 四条真差异（GAP）

| 怪 | 原作 | 我们 |
|---|---|---|
| 硝酸怪 `egt_nitra` | 死亡炸成**一条线**，线朝远离玩家方向；贴脸则反向朝玩家 | **圆形爆炸** + 伤害场。线爆与双向规则都没做 |
| 钥匙小子 `egt_keybullet_kin` | 击杀掉 1 把钥匙 | 不掉（局内经济未接入） |
| 运气小子 `egt_chance_kin` | 击杀掉 1 个随机非钥匙拾取 | 同上 |
| 抓握大师 `egt_gripmaster` | 扔回**前几个房间**并**重置该批房间重新刷怪**；清场后**转射击形态可被伤害** | 只抛 10m；清场后**自己死** |

### 6.4 一处自我纠正

第一版把链枪手判成「照抄」。复查 `_fire_projectile` 后确认**没有穿墙标记** ——
链上子弹走普通弹道，撞墙即消，而原作明确写 `the chain can go through walls`。
改判 APPROX。这条记在这里，是因为它是本轮唯一一处「看起来实现了、实际没实现」的项；
同类的坑（`blink.on_attack` 从上线起就没有消费点）设计文档 §T2.7 已经记过一次。

### 6.5 仍在范围内的已知近似（不列为 GAP，但要知悉）

- 枪坚果的**判定起点是怪中心**，不是剑尖 ⇒ 不复刻「弹可穿过小障碍墙」。
- 蓝书怪的字母弹是**每隔 3 次**才换，原作描述像"始终带"，近似取舍。
- 红衣主教的「偶尔」取 1/3；查斯布洛布的「有几率自杀」取 20% —— 都是把定性变定量。
- 已确认者 / 枪精灵的**生成通道**改了：原作是注入替换（每层 ≤1）与破罐 0.05% 事件，
  我们固定编进 `n08` —— 照抄概率等于几乎见不到。
