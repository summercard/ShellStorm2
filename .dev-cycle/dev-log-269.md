# 开发日志 — 2026-05-27

## 轮次 269 — 2026-05-27 07:42 UTC+8

### 维度
PH07精英怪成长系统：档案池首次运行播种 + 损坏存档自修复

### 问题
EliteArchiveModule._load_archive() 在无存档或存档损坏时直接返回空池，导致首次运行时 get_spawnable_elites() 永远为空。精英怪成长系统虽然在代码层面完整（生成→遭遇→成长→再登场），但"第一局没有精英可抽取"会让整个系统对玩家不可见，直到不知道多少局之后才偶然触发。

### 玩家可感知结果
- 首次进入游戏（无存档）：EliteSpawnDirector 从 2 只播种精英中抽样
- 第一次遭遇精英：玩家开始感知"这只怪我上局没打死，它又回来了"
- 精英死亡不掉井：击杀一只后，另一只继续存活并在后续局中成长
- 档案损坏/存档文件损坏：自动重新播种，不卡死

### 修改内容
| 文件 | 改动 |
|---|---|
| `src/enemy/EliteArchiveModule.gd` | `_load_archive()` 新增空存档保护：`FileAccess.file_exists` 为 false → `_seed_starter_elites()` 播种；f.read 失败 → `_seed_starter_elites()` 播种；JSON.parse 异常 → `_seed_starter_elites()` 播种；archive.is_empty() 兜底 → `_seed_starter_elites()` 播种 |
| `src/enemy/EliteArchiveModule.gd` | 新增 `_seed_starter_elites()`：创建 2 只新手引导型精英（背枪的裂口爬虫 + 吞弹者·孢子射手），各自带不同特征（武器寄生/子弹偷取），让玩家从第一局就能感知精英威胁 |

### 关键实现细节
- 2 只播种精英各有独特名字后缀（"背枪的…" + "吞弹者·…"），首次遭遇时给玩家留下记忆点
- 精英 ID 格式 "elite_%06d"，与 create_elite() 生成的格式完全一致
- stolen_modules 使用 MODULE_CONVERSION 映射（GunBody → EnemySkill_BackMountedMachinegun，Bullet → EnemyRanged_AdaptedBullet）
- _get_next_id() 在 from_dict 之后调用，确保 ID 不会和存档加载的记录冲突
- save_archive() 在 _exit_tree() 自动触发，播种的精英在下一次退出游戏时被持久化

### 精英播种后链路验证
1. `_load_archive()` → 存档不存在 → `_seed_starter_elites()` → 2 只播种 ✅
2. `EliteSpawnDirector.try_select_elite()` → `get_spawnable_elites()` 返回 2 只 ✅
3. 首次波次生成 → `_build_elite_spawn_data()` → `stolen_modules` + `name` + `level` 注入到 `RoomWaveSpawner` ✅
4. 精英死亡 → `_on_enemy_death()` → `kill_elite()` → `state="Killed"` → 降级为纪念记录 ✅
5. 另一只精英未死 → 存档存在 → 后续局继续成长（逃脱+属性提升）✅

### 验证
- Godot --headless --quit-after 1: EXIT 0 ✅
- 逻辑验证：无存档时播种 2 只，有存档时正常加载，损坏时自修复 ✅

### 剩余风险
- 新手引导精英的强度是否合适（1级基础数值可能被当前玩家数值碾压）
- `from_dict` 中 `Array(d.get("modifiers", []), TYPE_STRING, "", null)` 的转型在 Godot 4 GDScript 中可能产生兼容警告（需人类试玩确认）
- "_seed_starter_elites" 仅在 RoomGameMode._setup_elite_archive() 时被调用一次，如果其他代码直接访问 EliteArchiveModule，空 archive 仍会是问题
- 人类试玩确认：首次遭遇精英时名字是否足够有辨识度

### 下轮最可能方向
1. **PH07 精英怪装备偷取实际验证**：玩家死亡后掉落枪械→精英捡走→下一局遇到时名字变化（需要死亡掉落链路连通）
2. **PH12门视觉深化**：门框光效/开启动画/门类型颜色区分（当前门只有ColorRect标记）
3. **精英遭遇通知HUD**：精英出现时右上角出现警告提示（"背枪的裂口爬虫出现！"）