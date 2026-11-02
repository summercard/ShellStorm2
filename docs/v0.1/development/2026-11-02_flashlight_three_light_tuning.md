# 2026-11-02 角色随身三盏灯配色与能量定稿

> 业主原话：「我角色身上的三个灯，数值帮我调整成这个。」附调试面板（P 键）四张截图：
> 一张是三盏灯的最终能量读数，三张是三盏灯各自的颜色拾取器（Hex 字段可见）。
> 只动 `PlayerFlashlight3D` 的 6 个 export 默认值，逻辑、范围、角度、阴影、分层一条没动。

## 1. 落地值

| 灯 | 字段 | 改前 | 改后 | 变化 |
|---|---|---:|---:|---|
| ForwardBeam · 前向主灯 | `beam_color` | `#f17554` | **`#f1c254`** | 只抬 G：117 → 194 |
| ForwardBeam · 前向主灯 | `beam_energy` | 10.80 | **13.60** | +25.9% |
| EnvironmentSpill · 环境泛光 | `spill_color` | `#fa7e34` | **`#fab134`** | 只抬 G：126 → 177 |
| EnvironmentSpill · 环境泛光 | `spill_energy` | 1.50 | **1.25** | −16.7% |
| AvatarFrontFill · 角色补光 | `front_fill_color` | `#ec8e55` | **`#ecb855`** | 只抬 G：142 → 184 |
| AvatarFrontFill · 角色补光 | `front_fill_energy` | 8.40 | 8.40 | 不动（截图读数就是 8.40） |

三张拾取器截图与三个灯的对应关系不是靠猜的 —— **R 与 B 两条通道在改前改后逐位相同**，
只有 G 变了，因此「哪张图属于哪盏灯」由旧默认值唯一确定：

| 截图 Hex | R / G / B | 旧默认值 | 同 R、同 B | 判定归属 |
|---|---|---|---:|---|
| `#f1c254` | 241 / **194** / 84 | `#f17554` = 241/117/84 | ✅ | ForwardBeam |
| `#fab134` | 250 / **177** / 52 | `#fa7e34` = 250/126/52 | ✅ | EnvironmentSpill |
| `#ecb855` | 236 / **184** / 85 | `#ec8e55` = 236/142/85 | ✅ | AvatarFrontFill |

能量值同理按面板自上而下的行序对位：13.60 在主灯段、1.25 在环境泛光段、8.40 在角色补光段
（`FlashlightColorTweaker._build_light_page()` 的段序：beam → spill → fill）。

## 2. 影响面

- **落点唯一**：只有 `src/player3d/PlayerFlashlight3D.gd` 的 `@export` 默认值持有这三组值；
  全仓 `.tscn` / `.tres` / `.json` / `.cfg` 没有一处覆盖，改默认值即全场景生效。
  `scenes/Player3D.tscn` 里该节点实例的是 `assets/art/vfx/visibility_3d/vfx_player_flashlight_root_top3d.tscn`，
  那份预置场景里**只有 `script = ExtResource(...)` 一行**，没有任何属性覆盖 —— 所以默认值确实直达运行时。
- **不在 `graphics_settings.cfg` 里（业主 2026-11-02 18:36 反馈「好像没有改啊」的原因）**：
  业主贴出的那段 JSON（`debug_postfx_*` / `debug_base_interior_*` / `hue_shift`）是
  `GraphicsSettingsManager.SAVE_PATH = "user://graphics_settings.cfg"` 的内容，它**只存后处理与基地雾气**。
  调参面板第 458 行自己也写着：「后处理 / 基地雾气参数会自动记住……镜头雾气页为临时值」。
  三盏灯不在任何持久化文件里，每次从 export 默认值来，面板改灯只影响当前会话。
  ⇒ 想看灯有没有生效，只能读运行时灯节点，不能翻配置文件。
- **调参面板**：「复位灯光为 export 默认值」现在回到这一套新值（面板首次打开时锁定的就是 export 值）。
- **不改的东西**：`beam_range 25` / `beam_angle 66°` / `beam_attenuation 0.48` / `spill_range 4.8` /
  `front_fill_range 4.0` / 分层 cull_mask / 阴影开关全部原样。截图里没有这些读数，不擅自推定。

### 2.1 主灯 +25.9% 能量对怪物受光判定的实际影响：可忽略

`EnemyIllumination3D` 的贡献公式是 `E × (1−d/R)^attenuation × angular`，判定阈值
`minimum_light_contribution = 0.035`，且**只用二进制比较**（≥ 阈值即算受光），不做梯度加权。

沿光锥轴心（`angular = 1`）反解 10.80 与 13.60 两档的受光边界距离：

| 主灯能量 | 解 `E·(1−d/25)^0.48 = 0.035` | 受光边界 |
|---|---|---|
| 10.80 | `(1−d/25) = (0.035/10.80)^(1/0.48)` | d ≈ 24.99 m |
| 13.60 | 同上 | d ≈ 24.99 m |

两档的边界都已被 `beam_range = 25 m` 自身截断，能量不是限距因子 ⇒ **玩法判定半径不变**。
唯一会动的是一圈极窄的边缘带（`angular` 接近 `cos(66°)` 处），贡献值抬 26% 会让光锥边沿的
极暗角落多几个受光采样点，量级远小于一帧的受光刷新抖动。环境泛光与角色补光本就不在
`EnemyIllumination3D.LOCAL_LIGHT_GROUP` 里，与玩法无关，纯画面。

## 3. 运行时探针（唯一能证明「灯真的变了」的判据）

`_scratch/probe_flashlight_runtime.gd`：`extends SceneTree`，实例化 `res://scenes/Player3D.tscn`，
等 4 帧让 `_ready` 跑完 `_build_lights()`，再 `set_light_enabled(true)` 并直接读灯节点的
`light_color` / `light_energy`。只读，不写盘。

```
PROBE export.beam_color=hex=f1c254     PROBE_LIGHT ForwardBeam      color=f1c254 energy=13.6
PROBE export.beam_energy=13.6
PROBE export.spill_color=hex=fab134    PROBE_LIGHT EnvironmentSpill color=fab134 energy=1.25
PROBE export.spill_energy=1.25
PROBE export.front_fill_color=hex=ecb855  PROBE_LIGHT AvatarFrontFill  color=ecb855 energy=8.4
PROBE export.front_fill_energy=8.4
```

**这条探针抓到了一起真实回滚**：第一次跑出来是 `f17554 / 10.8`（旧值）。
排查发现 `git reflog` 在 **17:07** 有一次 `pull --rebase origin 0.1.2`，
把上一轮**未提交**的 `.gd` 改动连同 `development/README.md` 索引行、`CHANGELOG.md` 条目一起覆盖回 HEAD；
反倒是那份开发记录 `.md` 因为还是 untracked、pull 不动它而幸存 ——
这正是「文档还在、代码却回到旧值」这种最容易被误判成「AI 没改」的形态。
已重新落地三处改动并复验（上面的输出就是复验结果）。

> 结论性教训：**这个仓库随时可能被 `pull --ff-only` / `--rebase` 快进**，
> 改了 `.gd` 不提交就等于随时会被抹掉。源值型改动交付后应立即 commit，
> 或者至少在同一会话内用探针复验一次再报「完成」。

## 4. 验收

> 说明：`scripts/run_verification_suite.sh` 本轮**被预检挡在跑场景之前** ——
> `check_expedition03_room_layouts.py` 退出 1（26 份 `runtime_rooms/*.tscn` 的
> `portal_fingerprint` 与文件名门位指纹不一致）。该红与本轮改动无关（本轮只动一个 `.gd`），
> 属既有债务，故改用「APPDATA 重定向到工程外临时目录 + 单场景 headless 直跑」的方式隔离验收。

| 用例 | 结果 | 关键输出 |
|---|---|---|
| `verify_enemy_illumination_states` | **exit 0** | `ENEMY_ILLUMINATION_STATES_OK: darkness, window sunlight, seam rejection, physical shadow, flashlight cone, priority, hysteresis and Boss isolation pass` |
| `verify_3d_vision_input_flow` | **exit 0** | `3D_VISION_INPUT_FLOW_OK: 360 occlusion vision, manual F flashlight, I/Tab inventory lock and recoverable pause pass` |
| `verify_3d_flashlight_charge_flow` | **exit 0** | `13/13 OK: facility pause without auto-charge, drain/stop, toggle preservation, depleted, batteries, visual module profiles, persisted module hydration, HUD, shop, checkpoints, module persistence and reveal` |
| `verify_debug_camera_fog_panel` | **exit 0** | `DEBUG_CAMERA_FOG_PANEL_OK checks=45` |
| `verify_tower_lighting_wall_combat_regressions` | **exit 1（既有红）** | 6 条失败：98F 门未开先刷怪 / 99F 支撑失活 / 上层楼板下误判阳光 / 楼梯相机三条 / `NpcCharacter3D.gd` 编译错。**无一条涉及灯能量或灯颜色**，未放宽任何阈值 |

这些用例全部以 `get_beam_energy() / get_spill_energy() / get_front_fill_energy()` 为比较基准
（不是硬编码 10.8 / 1.5 / 8.4），所以改默认值不产生新红项 —— 塔楼回归里那三条
`is_equal_approx(beam/spill/fill.light_energy, get_*_energy() × multiplier)` 断言本轮全过。

`check_documentation_contracts.py` 跑通但列表里仍是既有的 25 条问题（无关文档断链、
3 个未注册验收场景、缺 `openpyxl`），本轮新增的文档与索引行未引入新问题。

用户数据目录已重定向到工程外临时目录（`ShellStorm2-work/iso_appdata`），未触碰正式存档。


## 5. 未做 / 待观察

- **实机观感未验**：本轮是纯数值定稿。三盏灯同时偏黄（G 抬 30~58 点）后，
  手电光锥与地面溢光的色温会比原来明显更暖，需要进一次远征暗房看「墙面色偏 / 怪物轮廓可辨性」，
  这类结论只有真实渲染画面能回答，headless 报绿不算通过。
- **截图里的 `beam_range` 等读数没有出现**，本轮不推定；若业主后续要连范围一起调，另开一轮。
- 调参面板的「能量」滑条上限是 16.0（`ENERGY_SLIDER_MAX`），13.60 仍在量程内；
  若后续要再往上调过 16，得同时抬滑条上限，否则面板会顶格显示、与 export 值不一致。
