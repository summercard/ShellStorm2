# ShellStorm2 普通怪契约与实测证据

> 快照日期：2026-09-20。首只标准样板 = `ENM-MELEE-FUNGBOAR01`（小僵尸）。
> 数值来自实测与本仓代码；换项目时按同一证据顺序重建，**不要照抄这里的数字**。

## 1. 首只样板身份

| 项 | 值 |
|---|---|
| AssetID | `ENM-MELEE-FUNGBOAR01` |
| 显示名 | 小僵尸（原登记名「小菌猪」，`Enemy3D.configure_from_enemy_data()` 精确迁移旧存档尾名） |
| 逻辑 ID（= `enemy_kind`） | `melee_chaser` |
| 子类 | `normal_melee` |
| 命名前缀 | `enm_melee_fungboar01` |
| AssetID 台账行 | 敌人账本《资产主表》r6 |
| Prefab 分页行 | 敌人账本《3D-敌人》r7 |
| 中转记录 | `assets/art/enemies/normal_enemy_3d/melee_chaser/runtime/character_transfer_ledger.json` |

命名前缀 = AssetID 去掉尾部 `-3D` 后全小写、`-` 转 `_`。**7 类普通怪 AssetID 已在《资产主表》r6–r12 全部预登记**（最初全为「程序占位」）⇒ 新怪只升级既有行，新增会撞 `duplicate_asset_id`。

## 2. 尺寸链条（实测）

| 项 | 值 |
|---|---|
| 全局展示倍率 | `Enemy3D.DEFAULT_BASE_SIZE_MULTIPLIER = 0.70` |
| 源文件高 | 1.857143 m（= 1.300 / 0.70） |
| 游戏内高 | 1.300 m（比玩家 1.200 m 高 8.3%） |
| 源包围盒（朝向归正后） | X 1.2819 × Y 0.9535 × Z 1.8571 m |
| 玩家参照 | 1.500 m × 0.80 = 1.200 m |
| 横向最大半展（按新几何推） | max(X, Y) / 2 = 0.6410 m |

`Avatar` 与 `CollisionShape3D` 都是 `Enemy3D` 的直接子节点，**两者一起吃 0.70**。

## 3. 资产包实测规格

| 项 | 值 |
|---|---|
| 网格 | 2278 verts / 4552 polys / 1 Mesh / 1 材质 |
| 骨架 | **36 骨**（v002 重建；更早的母版是 41 骨 Mixamo 式） |
| 骨架 ID | `SKEL-MELEE-FUNGBOAR01-002` |
| 剪辑 | 6 段（Godot 导入核对为 6 个动画） |
| 贴图 | 2048² sRGB PNG，**仅 basecolor，无法线 / 粗糙度 / 金属度** |
| 朝向 | 面罩朝 Blender **+Y**；运行时前向 **-Z**，无额外偏航补偿 |
| 对象级变换 | rot = 0、scale = 1.0；脚底 min Z ≈ 0 |

### 六段剪辑

| 剪辑 | 时长 | 循环 | 造型要点 |
|---|---|---|---|
| `idle` | 3.2 s | ✅ | 前倾驼背、屈肘前伸、肩部下垂、晃身 |
| `walking` | 1.6 s | ✅ | 不对称拖步 / 跛脚 |
| `running` | 0.8 s | ✅ | 胸部前倾约 32°，双臂前伸，失衡前冲 |
| `attack` | 1.7 s | ❌ | 右手抬起前伸跨身弧线，迟缓收势，末帧保持 |
| `hurt` | 0.8 s | ❌ | 踉跄 + 抬脚后撤，末帧保持 |
| `dead` | 2.4 s | ❌ | 后躺砸地、两次衰减回弹，末帧保持 |

## 4. 玩法侧接线实测位置（`melee_chaser`）

| # | 位置 | 实测符号 |
|---|---|---|
| 1 | 常量 | `EnemyAvatar3D.FORMAL_MELEE_KIND = "melee_chaser"`、`FORMAL_MELEE_SCENE_PATH`、`FORMAL_MELEE_VISUAL_HEIGHT = 1.857` |
| 2 | 挂载分支 | `EnemyAvatar3D._rebuild()` 内 `if enemy_kind == FORMAL_MELEE_KIND` → `_load_formal_normal_model()` |
| 3 | 状态转发 | `EnemyAvatar3D.sync_presentation()` |
| 4 | 组件快照 | `EnemyAvatar3D.get_component_snapshot()` → 2 组件 |
| 5 | 数据适配 | `Enemy3D.configure_from_enemy_data()`（显示名迁移 + 精英互斥） |
| 6 | 死亡回收 | `Enemy3D._die()`（正式普通怪 2.4 s 表现回收，否则 0.34 s 压扁） |

配套：

- `EnemyAvatar3D.FOOTPRINT_PROFILES["melee_chaser"] = {"radius": 1.02, "height": 1.30}` —— **旧程序网格口径，未跟新模型几何（0.641 / 1.857）同步**，属玩法数值待拍板。
- `EnemyAvatar3D.COLORS["melee_chaser"] = Color(0.58, 0.19, 0.12)` —— 程序网格回落色（现已隐藏，优先级低）。
- `MonsterInjector.BASE_ENEMY_TYPES["melee_chaser"] = {"name": "小僵尸", "hp_base": 25, "damage_base": 5, "speed": 80}` —— 2D 侧名称 / 数值表。

## 5. 门禁实测命令与期望

```bash
python scripts/check_asset_runtime_naming.py                     # 期望 ASSET_RUNTIME_NAMING_OK（exit 0）
python scripts/asset_guard.py assets/art/enemies/normal_enemy_3d/melee_chaser --classify child_variant
                                                                 # 期望 ASSET_GUARD_PASS（exit 0）
python scripts/check_asset_registry.py --ledger 敌人              # 期望 ASSET_REGISTRY_CHECK_OK assets=12
Godot_console.exe --headless --path . res://tests/verification/verify_melee_zombie_presentation.tscn
                                                                 # 期望 MELEE_ZOMBIE_PRESENTATION_OK states=12 clips=6 death=2.4 collision_unchanged=true
```

`check_asset_registry.py` 全量模式的**已知基线红项**（2026-09-20 实测）：`invalid_status=5`、`path_not_found=25`、`sha_mismatch=42`。**红项 ⊆ 基线 ∪ 本次有意变更才算过**。

## 6. `asset_guard.py` 与敌人中转记录

角色域与敌人域的中转记录**命名与 schema 都不同**，`scripts/asset_guard.py` 已兼容：

| | 角色域 | 敌人域 |
|---|---|---|
| 文件名 | `character_transfer_ledger_v<NNN>.json` | `character_transfer_ledger.json` |
| 位置 | `.../variants/<v>/production/v<NNN>/` | `<包根>/runtime/` |
| 哈希形态 | `files: [{path, sha256, bytes}]` | `files` / `runtime_files` 列表 + `outputs` / `source_sha256` 映射 |

`asset_guard.py` 按 `<package>` 逐候选找本包账本（`character_transfer_ledger_<name>.json` → `character_transfer_ledger.json` → `runtime/character_transfer_ledger.json`），取并集哈希；命中同 AssetID 或同哈希即视为重复，**必须显式 `--classify` 归类，否则 exit 2**。

## 7. 已知未闭合（2026-09-20）

| # | 缺什么 | 处置 |
|---|---|---|
| 1 | 碰撞 `FOOTPRINT_PROFILES`（1.02 / 1.30）与模型几何（0.641 / 1.857）不一致 | **玩法数值，须拍板**；缩半径会明显提高闪避难度 |
| 2 | 贴图只有 basecolor，**无 NormalMap** | Tripo 只交付 basecolor；材质 `NORMAL_MAP` 节点未接线 |
| 3 | `COLORS` 回落色未按新美术口径复核 | 程序网格已隐藏，优先级低 |
| 4 | `verify_3d_enemy_behavior_flow` 有七类敌人「3D 飘字缺失」红项 | 已用**改动前 Prefab 做基线对照**复现（7/7 同错），确认与本资产链路无关；根因是 `Enemy3D.take_damage()` 未产生 `CombatDamageNumber3D` |
| 5 | 主账本《3D Prefab总控》的计数是手工快照（更新日期 2026-09-12），敌人页计数与分账本公式口径会漂移 | 本次未动；需一次专门对账 |
| 6 | 敌人账本《3D-敌人》r6（精英）「原点与朝向」列写 **Blender -Y**，与 `16.1` 的 **+Y** 契约及本包实测不一致 | 疑似精英行登记笔误，未擅改；新行按实测 +Y 写 |
| 7 | 精英包 `elite_3d/rift_boar_armed/source/` **没有 `.gdignore`**，Godot 会去导入它的 `.blend` | 与本链路同域不一致，待确认是否补齐 |
| 8 | 敌人 runtime Prefab 命名仍带 `_vNNN`（`enm_elite_rift_boar_armed_root_top3d_v001.tscn`） | 已在命名门禁欠账快照内；去版本化是独立批次 |
