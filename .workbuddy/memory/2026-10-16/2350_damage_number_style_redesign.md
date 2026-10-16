# 数字飘字：字体 / 样式 / 力度重做（含池化出生点 P0 修复）

用户指令（原文两轮）：
1. 「伤害字体的飘字字体和飘字动画是否有调整过？」（只读审计）
2. 「行，先收口，然后要修改字体和样式，走漫画风格的粗体+沟边的，大一点，然后字体飘起的力度感强一些，不要太整齐，带一些随机。」

## 一、审计结论：历史上「从未被改过，只被定义过一次」

- 字体与动画**参数**在 git 历史里只有一次定义提交：`63c070c7`（2026-08-07）。
- 此后三次相关提交均**未触碰**字体与动画参数：
  `384306f9`（2026-09-11 池化迁移，字体未继承）、2026-09-21（只读审计）、
  `819e4131`（2026-10-10 只改淡出通道）。
- **实机字体真相**：生效链路 `VfxDamageNumber3D` 一直是 **Label3D 默认内建字体**
  （`font = null`，字号 32 / `pixel_size` 0.010 ⇒ 世界字高 0.320 m）。
  08-07 定的「等宽终端字体」只活在**跑不到的兜底链路** `CombatDamageNumber3D` 里。
  ⇒ 即「改过没有」= 没改，但「实机到底用的什么」与文档写的一直不一致。

## 二、收口四项（改造前先清干净）

1. `Enemy3D` 重复飘字：伤害路径同时走池化件与旧 `_spawn_effect("VFX-DAMAGE-NUMBER-3D", 0.72)`，
   后者**不带伤害数字**故飘出一个 `0`。⇒ 删除该重复调用。
2. 治疗走错 AssetID：`receive_healing()` 误走伤害件 ⇒ 绿色治疗字飘红且显示 `0`。
   ⇒ 新增 `_spawn_heal_number(amount)`，改走 `VFX-HEAL-NUMBER-3D`。
3. 字体口径散在两处（`VfxDamageNumber3D` 用内建、`CombatDamageNumber3D` 用等宽终端）
   ⇒ 收敛到单一真源 `src/vfx/DamageNumberStyle.gd`，三方全部引用。
4. 验收断言跑的是**兜底链路**（`new CombatDamageNumber3D`）而非实机生效链路
   ⇒ 改为**从 `VfxPool3D` 取生效实例**再断言。

## 三、改造四项

- **字体/样式单一真源** `src/vfx/DamageNumberStyle.gd`：
  漫画风超粗体回退链 `Impact` → `Arial Black` → `Haettenschweiler` →
  `Franklin Gothic Heavy` → `sans-serif-black` → … → `sans-serif`；
  `FONT_WEIGHT = 900`、`MSDF_SIZE = 128`（`multichannel_signed_distance_field`，放大不出马赛克）、
  `PIXEL_SIZE = 0.00375`；字号分级 `116 / 134 / 152`（normal / heavy / critical，
  heavy 阈值 `HEAVY_AMOUNT_THRESHOLD = 40`）⇒ **世界字高 0.435 m**（旧 0.320 m）；
  近黑粗勾边 `OUTLINE_COLOR = Color(0.02, 0.02, 0.03, 1)`，描边 `26 / 30 / 34`。
  ⚠️ `font_families()` **只能是函数不能是 `const`**：`PackedStringArray([...])` 做 `const`
  在解析期直接报 `Assigned value for constant isn't a constant expression`。
- **放大**：字高 0.320 → 0.435 m（×1.36）；描边按字高 22% 定档
  （首版按 19% 实测屏幕只剩 2~3 px，粗笔画吃不掉，抬到 22%）。
- **力度强化**：上升曲线改 ease-out cubic `rise_t = 1 - (1-t)^3`；
  基准升距 `BASE_RISE_DISTANCE = 0.90`；弹出后收束到 `SETTLED_SCALE = 0.90`，
  收束进度**从 `POP_SETTLE_TIME = 0.14` 起算**（从 0 起算会导致永远收不到 `1.0`）。
- **随机化（纪律：随机数只许活在调用方，vfx skill §5.5.3）**：
  `Enemy3D` 下发 context 键 `spawn_offset` / `rise_scale` / `drift` / `pop_scale` / `duration_scale`
  （常量 `DMG_NUM_SPAWN_JITTER` / `DMG_NUM_RISE_SCALE` / `DMG_NUM_HORIZONTAL_DRIFT` /
  `DMG_NUM_POP_SCALE` / `DMG_NUM_DURATION_SCALE`）；
  特效脚本对同一 `context` **逐位可复现**、源码内**不出现 `randf()`**。

## 四、【P0】池化飘字出生点被 `_on_tick` 赋值覆盖（2026-09-11 起的历史缺陷）

- 探针实测（`spawn_requested = (3.0, 5.0, 7.0)`）：
  `after_activate` 位置 `(3.1, 5.05, 6.9)` → `after_tick_0.0` → **`(0.0, 0.0, 0.0)`**
  → `after_tick_end` → `(0.2, 0.9, −0.2)`。
- 根因：`_on_tick` 是**每帧重算**，却写成**赋值**
  `position.y = rise_t * _rise_distance` / `position.x = …` / `position.z = …`，
  把 `activate()` 写入的出生坐标整个抹掉。
- 后果：实机所有飘字都跑到**世界原点上方不到 1 米**处。塔楼是**向下建造**
  （`stage.position.y = −12.0 × floor_index`，98F ≈ −1176 m）⇒ 与怪物所在楼层相差上千米。
- 修复：新增 `_origin_local`，`_on_activate` 末尾（含 `spawn_offset` 之后）取出生点；
  `_on_tick` 改 `position = _origin_local + Vector3(drift.x·rise_t, rise_t·rise_distance, drift.z·rise_t)`。
  **两个飘字脚本（`VfxDamageNumber3D` / `VfxHealNumber3D`）都改**。
- 另一条同源纪律：**淡出必须走 `transparency`**，`outline_modulate`（勾边）不吃 `modulate` 的 alpha，
  只淡正文会留勾边残影。

## 五、验收与反向对照

- 新建专项 `tests/verification/verify_damage_number_style_flow.gd/.tscn`
  （期望值**硬编码在验收侧**，不引用被测常量；另加「常量钉子」防自印证）。
  用例：`_verify_style_constants` / `_verify_spawn_anchor` / `_verify_damage_number_style` /
  `_verify_heal_number_style` / `_verify_rise_and_pop` / `_verify_determinism` /
  `_verify_caller_randomization`（`SAMPLES = 24`）。
  关键硬编码：`EXPECTED_FONT_WEIGHT 900` / `EXPECTED_MSDF_SIZE 128` / `EXPECTED_PIXEL_SIZE 0.00375` /
  字号 116/134/152 / 描边 26/30/34 / `EXPECTED_NORMAL_GLYPH_HEIGHT 0.435` /
  `PREVIOUS_SHIPPED_GLYPH_HEIGHT 0.320` / `EXPECTED_BASE_RISE 0.90` / `EXPECTED_POP_SETTLE_TIME 0.14` /
  `EXPECTED_SPAWN_ANCHOR Vector3(3.0, 5.0, 7.0)`。
- `tests/verification/verify_3d_enemy_behavior_flow.gd` 改断**生效链路**
  （新增 `EXPECTED_DAMAGE_FONT_WEIGHT 900`、`EXPECTED_DAMAGE_FONT_SIZES {normal:116, heavy:134, critical:152}`）。
- 结果：`DAMAGE_NUMBER_STYLE_FLOW_OK`（exit 0）、`3D_ENEMY_BEHAVIOR_FLOW_OK`（exit 0）、
  `VFX_POOL_LIFECYCLE_OK`（exit 0）；账本门禁 `ASSET_REGISTRY_CHECK_OK scope=full assets=37 ledgers=1`，
  `issue_counts: {}`。
- **反向对照 4 组**全部精准变红并还原复绿（clean，无 `REVERSE-CONTROL` 残留）；
  其中第 4 组专门复刻 P0：把 `_origin_local` 置 `Vector3.ZERO` ⇒ 出生点断言精准变红。
- 视觉证据（工程外）：`outputs/damage_number_style_t0_pop.png` / `_t_mid.png` / `_t_late.png`
  —— `Impact` 命中、粗体 + 近黑粗勾边、字号分级清晰、散布自然。

## 六、文档 / 账本回写

- `docs/v0.1/14.6_特效系统与制作规范.md`：新增 **§3.8**「数字飘字（FX02-01 / FX02-02）的
  字体、样式与随机契约（2026-10-16）」+ 版本历史 **v003.9** 行。
- `docs/v0.1/06_技术施工_怪物精英与Boss.md`：原「SF Mono 风格的粗等宽终端字体」段整段订正为
  漫画风超粗体 + 勾边 + 分级 + 随机 + 治疗绿色 + P0 说明。
- `docs/v0.1/MODULE_INDEX.md`：`VFX-POOL` 行 —— 验收清单补 `verify_damage_number_style_flow`，
  现状说明补字体真源 / 样式重做 / 调用方随机化 / P0 修复 / 四项收口。
- 账本 `assets/registry/ledgers/ShellStorm2_特效账本_v001.xlsx`：
  `3D-特效` r16/r17 col16 版本 `v001 → v002`、col7 功能说明、col12 标准尺寸、col17 备注追加
  `【2026-10-16 样式重做】` 并订正历史误写的 `_v001` 后缀路径；
  `域变更日志` 追加 `v0.1.24`（幂等：按版本号判重；样式用 `copy(src._style)` 复制）。

## 七、环境坑（本次新增）

- 仓库根是 `I:/工作项目/shellstrom2/ShellStorm2`（**不是** `I:/工作项目/shellstrom2`）。
- `Write` 报 `File has been modified since read` ⇒ 先 `Read` 再 `Write`。
- `Edit` 偶报 `EBUSY: resource busy or locked`（Godot 占着该文件）⇒ 重试同一条即可。
- 视觉预览：`camera` 未入树时 `look_at()` 报 `Node not inside tree` ⇒ 先 `add_child` 再
  `look_at_from_position(from, to, Vector3.UP)`；`save_png` 耗时远超 0.7 s 生命周期 ⇒
  冻结 `process_mode` + 手动 `_on_tick` 定格后再拍。
- 新建/重写的 `.gd` / `.tscn` 默认 LF ⇒ 一律转 CRLF 并核验
  `裸LF == 0` 且 `CRCRLF == 0`。
