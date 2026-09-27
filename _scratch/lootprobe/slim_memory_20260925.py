# -*- coding: utf-8 -*-
"""MEMORY.md 瘦身（2026-09-25）：
① 把 2026-09-19 之后新增长条目下沉到 MEMORY-playbooks.md（新节）
② MEMORY.md 对应段落压缩成「结论 + 指针」
两个文件都是 CRLF；脚本在 LF 域做替换、写回时统一转 CRLF，并做字节校验。
任一 old 未命中即报错退出，不写盘。
"""
import os

MEM = r"I:\工作项目\shellstrom2\.workbuddy\memory"
MAIN = os.path.join(MEM, "MEMORY.md")
PLAY = os.path.join(MEM, "MEMORY-playbooks.md")

NEW_SECTIONS = """
## 下滑自 MEMORY.md（2026-09-25 瘦身，MEMORY.md 只留结论与指针）

### 导出包（PCK）实测三结论（2026-09-25，Godot 4.6.3，`--export-pack` 871MB / 9088 文件）
- ① **`.blend` 不进包** —— Godot 用 `.godot/` 导入产物替代源文件 ⇒ `source/` 缺 `.gdignore` 的代价是**编辑器导入开销与 `.godot` 体积，不是包体**。
- ② **`.json` / `.import` / `tests/` / `docs/` / `tools/` / `_scratch/` 全进包**。根因 `export_presets.cfg` 三个 preset 皆 `export_filter="all_resources"` + `exclude_filter` 空 ⇒ dev-only 元数据约 33.56 MB 混进发行包；包体实体是 `.ctex` 492 MB + `.scn` 317 MB。
- ③ **`.gitignore` / `.gdignore` / `export_filter` 三者互不相干** ⇒ 判断「会不会打包」**必须真跑一次导出**，别推理。
- 裁包前查硬约束：`FloorPlanGenerator.gd:18-20` 用 `FileAccess` 读 `source/…/boss_room_50x40_v002.layout.json`（是 `source/` 内的运行时依赖）⇒ 对 `source/**` 一刀切排除会打断 Boss 房装配。
- 工具：skill `godot-export-pack-audit`，内含 PCK **v3** 解析器（索引在**文件尾部**、`dir_offset` 在 header@32；自校验 = 解析终点须等于文件大小）。

### 墙件换件的两个必查（2026-09-25 实证）
**碰撞归属（两条装配路径不同）**
- 程序化路径 `DungeonRoom3D._build_tower_wall_run()` 会调 `_add_tower_wall_collision()` / `_add_tower_solid_run_collision()` 补 0.30 m 代理。
- **授权布局路径 `_build_authored_layout_shell()` 一处都不调**（全文仅 3 处调用点 L2203 / L2216 / L2530，全在程序化路径）⇒ 授权布局挡人**全靠墙件 prefab 包内自带碰撞**。
- 换件前必查 prefab 的 `collision_owner` / `visual_only`：`self` = 包内自带（battle 通用墙/门墙、**tower L 角件**）；`visual_only=true` = 包内 0 碰撞（**tower 直墙/门墙**）。**同套美术家族内碰撞归属并不统一**（tower 六件里五件 visual_only，唯 L 角件例外）。
- 实测远征 12 房实体碰撞 383（battle 实墙 289 + 门墙 12 + 角件 82），全房 layer=1 共 447。
**朝向（`forward_axis` 两套相反）**
- battle 通用墙 / 门墙 = `−Z`（装甲朝房内，与摆位源 `FACE_IN_ROTATION_DEG` 同口径）；**tower A 套 = `+Z`**（派生时绕竖轴 180°）。
- `_spawn_authored_layout_wall()` 只做 `rotation.y = deg_to_rad(...)`、**无朝向归一化** ⇒ 直接换 tower 件，装饰面会翻到房外。
- 注册表 `shell_component_catalog.json` 是运行时唯一真源；摆位源用 primary_key（`ENV-SHARED-GENERIC-*`）而非批次号别名 ⇒ 换件改注册表 `prefab_path` 一条即可、不必改布局数据。

### 行尾转换的静默坑（2026-09-25 实测）
- Write / 脚本产出的新文件默认 LF。收尾前用 `git diff --cached --diff-filter=A` 列出新增，**先断言文件内无 `\\r`**，再 `b.replace(b'\\n', b'\\r\\n')`，然后重新暂存。
- 🔴 转换条件**别写成** `count(CR) != count(CRLF)` —— 纯 LF 文件两值都是 0 ⇒ 判 False ⇒ **静默跳过**（实测把新建记忆文件漏成 LF 却报「成功」）。条件应是「**无 CR 且有 LF 就转**」。

### 排查三坑（2026-09-25）
- 图纸 SVG 目视核验：临时写个 `extends Node` 的 tscn，用 `load(svg).get_image().save_png(...)` 在 headless 下光栅化（用完即删）。⚠️ **Godot 渲染 SVG 不画 `<text>`** ⇒ PNG 只能验形状/配色，文字必须在浏览器看图集 HTML。
- `git status --porcelain` 的中文路径会被 `core.quotepath` 转义成 `\\345\\205\\263` 形态，Python `io.open` 报 `No such file or directory`（**看着像文件不存在、其实是转义**）⇒ 一律用 `git -c core.quotepath=false status --porcelain`。
- 门禁假红：`check_asset_registry.py --scope full` 比 SHA（原始字节 vs 账本 LF）⇒ 假漂移**只在 Windows 出现**（macOS 检出 LF ⇒ full 只报 1 条 vs 本机 204 条）。对门禁红数**必须先标平台**再对比。

### 远征01 墙面裁定证据链（2026-09-25）
- 事务 `1609` / `1642` / `1804` / `1818` / `1847` / `1944` 六份：调研 → 同源性校准 → 朝向与共墙实证 → prefab 全量画廊 31 件 → 换墙可行性判定 → 主人裁定。
- 结论：**不换既有件**，改为「为远征01 单独做正式墙面资产、届时再换」。**禁止**把直墙换成 `ENV-TOWER-WALL-SOLID-5M`。
- 正式资产接单条件：几何 `(5, 11.9, 0.3)` / `bottom_center` / `grid_unit_m=5` / `visual_height_m=11.9` **逐值一致**；**必须声明 `forward_axis` 且推荐 `-Z`**；**优先包内自带碰撞 `collision_owner="self"`**（授权布局路径不生成结构碰撞代理 ⇒ 不自带就没挡人）；若非自带须补 0.30 m 代理并断言「实体碰撞体 ≥ 383」；装甲前凸建议 ≥100 mm（现用件仅 3.0 mm）；接线走注册表。

### 远征01 怪物与掉落口径（2026-09-25 实测）
- 运行时主题 `iron_frontier`、`difficulty_rank = 1`（**全项目无任何场景/资源给它赋值**，口径见 `RewardPoolRegistry` 注释）⇒ `floor = 1`、`FLOOR_SCALING[1] = 1.0/1.0`、主题倍率 HP ×0.95 / 伤害 ×0.95 / 速度 ×1.0 ⇒ 怪物名一律带前缀「边境」。
- **层档（floor_level）按房序线性折算**：`clampi(int(idx / (记录数−1) × 3), 0, 3)`。远征01 记录 13 条 ⇒ 序列 `[0,0,0,0,1,1,1,1,2,2,2,2,3]` ⇒ `room_01~03` 吃 `loot_floor_1_2`、`room_04~07` 吃 `loot_floor_3_4`、`room_08`/`room_10` 吃 `loot_floor_5`。⚠️ 它跟「越深越难」无关，只是「第几间房」。
- 单只普通怪掉落：**26%** 出 1 件非货币物品（count 恒 1）；**34%** 出 `item_ammo_pack` 3–8 发（池里已抽到同一物品则以整包数量覆盖）；魂 = `2 + 1 × floor` = **3**。
- 容器池恒为 `scavenge_floor_1`（表名 = `scavenge_floor_%d % min(5, maxi(1, difficulty_rank))`）。每房可搜容器 = 房内 prop 的 50%；prop 数：`size_class=tower_cell` ⇒ 3、`SCAVENGE`/`STORAGE` **+2** ⇒ 5、**Boss 房 = 0**。开容器发 8 m 声音刺激（吸引怪）。
- 🔴 **Boss 房无 Boss**：设计源未写 `boss_content_id`，而 `BossContentCatalog` 只登记 **95 / 90 / 85** 三层，本关 `floor_number = 0` ⇒ `resolve_profile("", 0)` 返回空 ⇒ 运行时「首领房未指派首领 · 区域已放行」，**连精英随从也不刷**；`boss_floor_1` 池**永不消费**。
- ⚠️ 设计页 §4.5 把 `melee_chaser` 写成「小菌猪」，代码 `BASE_ENEMY_TYPES` 里是**「小僵尸」**（运行时「边境小僵尸」）—— 待改，属「一物一名」违规。
- 主题 `enemy_pool` 被设计源架空：9 间房写了 `enemy_spawn_plan` ⇒ 公式路径的池与权重**完全不参与**；设计源池里出现主题池没有的壳甲卫兵 / 蜂巢怪 / 地刺虫（有意设计，但改主题不会影响本关刷怪）。
- 交付物：`outputs/expedition01_monsters_loot.html`（生成器 `_scratch/lootprobe/build_expedition01_report.py`、池明细 `_scratch/lootprobe/loot_pools_dump.tsv`、运行时探针 `_scratch/lootprobe/probe_expedition_monsters.tscn`）。
"""

# (old, new)；old 必须逐字命中；new 为 "" 表示删除该行（含其前导换行）
EDITS = [
    # 1) _INDEX 并发
    (
        "- 🟡 父目录 `<日期>/_INDEX.md` 是**并发共享文件**：另一会话会**整体重写**（2026-09-25 22:2x 实测被整表重写，并带出 16 处 `\\r\\r\\n` CRCRLF）。⇒ 追加索引行后**必须字节校验** `crlf`/`loneLF`/`loneCR`；见 `\\r\\r\\n` 用 `replace(b'\\r\\r\\n', b'\\r\\n')` 修（内容零丢失）。父目录不在 git 内 ⇒ CRLF 只是约定、不卡门禁，但**别替别人事务文件改行尾**（只管自己那份；实测另一会话 3 份仍是纯 LF）。",
        "- 🟡 父目录 `<日期>/_INDEX.md` 是**并发共享文件**（另一会话会**整体重写**：2026-09-25 22:2x 实测整表被重写并带出 16 处 `\\r\\r\\n`）⇒ 追加索引行后必须字节校验行尾；`\\r\\r\\n` 用 `replace(b'\\r\\r\\n', b'\\r\\n')` 修。父目录不在 git 内 ⇒ CRLF 只是约定、不卡门禁；**别替别人的事务文件改行尾**（只管自己那份）。",
    ),
    # 2) CRLF 转换条件 → 下沉
    (
        "- 行尾 CRLF（`.gd/.tscn/.json/.md`；例外 `project.godot`、`scenes/TowerDescent3D.tscn`、`.uid` 单行 LF；`.gitattributes` 只把 `*.import` 钉 `eol=lf`，**别给 `*.gd/.tscn/.md` 加 `eol=lf`**）。Write/脚本产出的新文件默认 LF ⇒ 收尾前用 `git diff --cached --diff-filter=A` 列出新增、**先断言文件内无 `\\r`** 再 `replace(b'\\n', b'\\r\\n')`，然后重新暂存。⚠️ 转换条件**别写成** `count(CR) != count(CRLF)`（纯 LF 文件两值都为 0 ⇒ 判 False ⇒ **静默跳过**，实测把新建记忆文件漏成 LF 却报\"成功\"）；条件应是「无 CR 且有 LF 就转」。",
        "- 行尾 CRLF（`.gd/.tscn/.json/.md`；例外 `project.godot`、`scenes/TowerDescent3D.tscn`、`.uid` 单行 LF；`.gitattributes` 只把 `*.import` 钉 `eol=lf`，**别给 `*.gd/.tscn/.md` 加 `eol=lf`**）。Write/脚本产出的新文件默认 LF ⇒ 收尾前按 `git diff --cached --diff-filter=A` 列新增、**断言文件内无 `\\r`**、再 `replace(b'\\n', b'\\r\\n')` 后重新暂存。⚠️ 转换条件别写成 `count(CR) != count(CRLF)`（纯 LF 两值都 0 ⇒ **静默跳过**）；口径见 playbooks「行尾转换的静默坑」。",
    ),
    # 3) 假红三例
    (
        "- 工具/口径假红：① `check_feature_traceability.py` 反斜杠 vs 正斜杠 ⇒ 恒报 37（已修）；② `check_asset_registry.py --scope full` SHA 原始字节 vs 账本 LF；③ 缺 `--import`。②的假漂移**只在 Windows 出现**（macOS 检出 LF ⇒ full 只报 1 条 vs 本机 204 条）⇒ 对门禁红数**必须先标平台**再对比。",
        "- 工具/口径假红：① `check_feature_traceability.py` 反斜杠 vs 正斜杠（**已修**）；② `check_asset_registry.py --scope full` 比 SHA（**假漂移只在 Windows 出现**：macOS 只报 1 条 vs 本机 204 条）；③ 缺 `--import`。⇒ 对门禁红数**必须先标平台**再对比。",
    ),
    # 4) PCK → 下沉
    (
        "- 🔴 **导出包（PCK）实测三结论**（2026-09-25，Godot 4.6.3，`--export-pack` 871MB/9088 文件）：① **`.blend` 不进包**（Godot 用 `.godot/` 导入产物替代源文件）⇒ `source/` 缺 `.gdignore` 的代价是**编辑器导入开销与 .godot 体积，不是包体**；② **`.json` / `.import` / `tests/` / `docs/` / `tools/` / `_scratch/` 全进包**（根因 `export_presets.cfg` 三个 preset 皆 `export_filter=\"all_resources\"` + `exclude_filter` 空）⇒ dev-only 元数据约 33.56MB 混进发行包，包体实体是 `.ctex` 492MB + `.scn` 317MB；③ **`.gitignore`/`.gdignore`/`export_filter` 三者互不相干**，判断「会不会打包」**必须真跑一次导出**，别推理。裁包前查硬约束：`FloorPlanGenerator.gd:18-20` 用 `FileAccess` 读 `source/…/boss_room_50x40_v002.layout.json`（是 `source/` 内的运行时依赖）⇒ 对 `source/**` 一刀切排除会打断 Boss 房装配。流程见 skill `godot-export-pack-audit`（含 PCK **v3** 解析器：索引在**文件尾部**、`dir_offset` 在 header@32，自校验=解析终点须等于文件大小）。",
        "- 🔴 导出包（PCK）：`.blend` **不进包**；但 `.json`/`.import`/`tests/`/`docs/`/`_scratch/` **全进包**（≈33.56MB dev 元数据混进发行包）；`.gitignore`/`.gdignore`/`export_filter` 三者互不相干 ⇒ **必须真跑一次导出**。`source/**` 不能一刀切排除（`FloorPlanGenerator.gd:18-20` 有运行时依赖）。全口径见 playbooks「导出包实测三结论」＋ skill `godot-export-pack-audit`。",
    ),
    # 5) SVG / quotepath → 下沉
    (
        "- 图纸 SVG 目视核验：可临时写个 `extends Node` 的 tscn 用 `load(svg).get_image().save_png(...)` 在 headless 下光栅化（用完即删）。⚠️ **Godot 渲染 SVG 不画 `<text>`** ⇒ PNG 只能验形状/配色，文字必须在浏览器看图集 HTML。⚠️ `git status --porcelain` 的中文路径会被 `core.quotepath` 转义成 `\\345\\205\\263` 形式，Python `io.open` 报 `No such file or directory`（**看着像文件不存在、其实是转义**）⇒ 用 `git -c core.quotepath=false status --porcelain`。",
        "- 图纸 SVG 目视核验：临时 tscn 用 `load(svg).get_image().save_png(...)` headless 光栅化（用完即删）；⚠️ **Godot 不画 SVG 的 `<text>`** ⇒ 文字必须在浏览器看图集 HTML。中文路径的 `git status` 转义坑见 playbooks「排查三坑」。",
    ),
    # 6) 墙件碰撞归属 → 压缩
    (
        "- 🔴 **两条墙件装配路径的碰撞归属不同（换墙件必查）**：① 程序化路径 `DungeonRoom3D._build_tower_wall_run()` 会调 `_add_tower_wall_collision()`/`_add_tower_solid_run_collision()` 补 0.30m 代理；② **授权布局路径 `_build_authored_layout_shell()` 一处都不调**（全文仅 3 处调用点 L2203/2216/2530，全在①）⇒ 授权布局挡人**全靠墙件 prefab 包内自带碰撞**。故换件前必查两件 prefab 的 `collision_owner`/`visual_only`：`self`=包内自带（battle 通用墙/门墙、**tower L 角件**）、`visual_only=true`=包内 0 碰撞（**tower 直墙/门墙**）。**同套美术家族内碰撞归属并不统一**（tower 六件里五件 visual_only，唯 L 角件例外）。实测远征 12 房实体碰撞 383（battle 实墙 289+门墙 12+角件 82），全房 layer=1 共 447。",
        "- 🔴 **换墙件必查两件**（全口径见 playbooks「墙件换件的两个必查」）：① **碰撞归属** —— 授权布局路径 `_build_authored_layout_shell()` **不补任何碰撞代理** ⇒ 挡人全靠 prefab 自带（`collision_owner=\"self\"`）；**tower 六件里五件 `visual_only`，唯 L 角件例外**。② **朝向** —— `forward_axis` 两套相反（battle `−Z` / tower A 套 `+Z`），`_spawn_authored_layout_wall()` 无朝向归一化 ⇒ 直接换 tower 件装饰面会翻到房外。注册表 `shell_component_catalog.json` 是运行时唯一真源，换件只改它的 `prefab_path`。",
    ),
    # 7) forward_axis 详解行 → 删除（已并入上条）
    (
        "\n- 🔴 **`forward_axis` 两套相反（换墙件必查）**：battle 通用墙/门墙 `−Z`（装甲朝房内，与摆位源 `FACE_IN_ROTATION_DEG` 同口径）、**tower A 套 `+Z`**（派生时绕竖轴 180°）。`_spawn_authored_layout_wall()` 只做 `rotation.y=deg_to_rad(...)`、**无朝向归一化** ⇒ 直接换 tower 件装饰面会翻到房外。注册表 `shell_component_catalog.json` 是运行时唯一真源，摆位源用 primary_key（`ENV-SHARED-GENERIC-*`）而非批次号别名 ⇒ 换件改注册表 `prefab_path` 一条即可、不必改布局数据。",
        "",
    ),
    # 8) 墙面路线裁定 → 压缩
    (
        "- 🔴 **墙面路线已裁定（2026-09-25 19:44）：不换既有件，改为「为远征01 单独做正式墙面资产、届时再换」**。禁止把直墙换成 `ENV-TOWER-WALL-SOLID-5M`（证据见事务 `1847`/`1818`/`1804`：两件 `forward_axis` 差 180°、碰撞归属 self vs visual_only，且授权布局路径无碰撞代理兜底 ⇒ 换完穿墙）。**做正式资产的接单条件**：几何 `(5,11.9,0.3)`/`bottom_center`/`grid_unit_m=5`/`visual_height_m=11.9` 逐值一致；**必须声明 `forward_axis` 且推荐 `-Z`**；**优先包内自带碰撞 `collision_owner=\"self\"`**（授权布局路径不生成结构碰撞代理 ⇒ 不自带就没挡人）；若不是自带则须补 0.30m 代理并断言「实体碰撞体 ≥ 383」；装甲前凸建议 ≥100mm（现用件仅 3.0mm）；接线走注册表。",
        "- 🔴 **墙面路线已裁定（2026-09-25 19:44）：不换既有件，改为「为远征01 单独做正式墙面资产、届时再换」**。**禁止**把直墙换成 `ENV-TOWER-WALL-SOLID-5M`。接单条件（几何逐值一致 / 声明 `forward_axis` 且推荐 `-Z` / 优先包内自带碰撞 / 否则补 0.30m 代理并断言实体碰撞 ≥383 / 装甲前凸 ≥100mm / 接线走注册表）见 playbooks「远征01 墙面裁定证据链」。",
    ),
    # 9) 支线两条 → 合并
    (
        "- **支线不另起代号**：支线只是设计页上的一句标注 ＋ L2 `role=\"branch\"`；支线房从锁定池直接取模板，**不新增模板、不新增一套编号**。支线可以是任意主路房型延展出去的房型。\n- **一物一名**：同一间房 / 同一房型在任何文档、设计页、数据文件里**只允许有一个代号**。",
        "- **支线不另起代号**：支线只是设计页上的一句标注 ＋ L2 `role=\"branch\"`，支线房从锁定池直接取模板，**不新增模板、不新增编号**。**一物一名**：同一间房 / 同一房型在任何文档、设计页、数据文件里**只允许有一个代号**。",
    ),
    # 10) 设计页长条目 → 压缩（playbooks 已有全口径）
    (
        "- 设计页 `docs/v0.1/design/远征关卡01设计.md`（设计区、非账本，FeatureID `WORLD-PLAN`）：改版图先读它、再走 `09-level-plan-authoring`，**不手改 `floor_00.json`**。图集由 `render_expedition01_plan_sheet.py` 生成（**文档即数据源**、改表就重跑；新增房型须在 `build_details()` 补图）。⚠️ 脚本内 `OUTLINES` 是**手写常量**、不随文档变，改房型尺寸/轮廓必须同步它，且要与 `room_templates/*.json::variant_footprints` 逐值一致（同房型的多个实例复用同一份顶点，如 room_01/room_08 = `l_turn`）。资产门禁 `check_expedition_room_asset_status.py`（只认 `ENV-` AssetID 与锚点 `#### 3.1.1`）。",
        "- 设计页 `docs/v0.1/design/远征关卡01设计.md`（设计区、非账本，FeatureID `WORLD-PLAN`）：改版图先读它、再走 `09-level-plan-authoring`，**不手改 `floor_00.json`**。图集由 `render_expedition01_plan_sheet.py` 生成（**文档即数据源**、改表就重跑；新增房型须在 `build_details()` 补图）。⚠️ 脚本内 `OUTLINES` 是**手写常量**，改房型尺寸/轮廓必须同步它、并与 `room_templates/*.json::variant_footprints` 逐值一致。文档接通全口径见 playbooks。",
    ),
    # 11) 输入/展示/特效节 → 压缩
    (
        "- 玩法走 InputMap action；`InputSettings`/`InputDevice`/`GamepadInput`/`MobileInput` 共虚拟输入入口。面向即弹道及准星；屏幕右投影 `Vector2(-f.y, f.x)`。\n- 手柄朝向三档：右摇杆>左摇杆>保持上次，绝不发零回鼠标；死区滞回 ×0.7。`gamepad_left_stick_aim` 默认 false。\n- 右摇杆瞄准「2+1」：`GamepadInput.resolve_aim_speed_scale`（`clamp(t)^1.60`）+ `AimAssist3D`（只吸存活+已照亮+锥内+射程内、上限 8°）。\n- 覆盖菜单必须默认焦点（`UiMenuFocus.ensure_focus`）；自建覆盖层在动画收尾、`disabled=false` 后 `grab_focus()`；取消走 `ui_cancel`；同帧重开必须先 `remove_child` 再 `queue_free()`。\n- 剧情从 `gameplay_started` 进入；`NarrativeDirector` 不可摘。输入锁归还 `refresh_player_input_lock`。\n- **UI 皮肤由 `UIStyleFactory.apply_tactical_tree` 统一注入**；自绘 UI 须带 `ui_style_exempt` meta。数值给公式，视觉改动需实拍。",
        "- 玩法走 InputMap action（`InputSettings`/`InputDevice`/`GamepadInput`/`MobileInput`）。面向即弹道及准星；屏幕右投影 `Vector2(-f.y, f.x)`。手柄朝向三档 = 右摇杆>左摇杆>保持上次、绝不发零回鼠标、死区滞回 ×0.7；右摇杆瞄准「2+1」= `resolve_aim_speed_scale`（`clamp(t)^1.60`）+ `AimAssist3D`（上限 8°）。**细则见 playbooks「输入与手柄细则」**。\n- 覆盖菜单必须默认焦点（`UiMenuFocus.ensure_focus`）；自建覆盖层在动画收尾、`disabled=false` 后 `grab_focus()`；取消走 `ui_cancel`；同帧重开必须先 `remove_child` 再 `queue_free()`。\n- 剧情从 `gameplay_started` 进入；`NarrativeDirector` 不可摘；输入锁归还 `refresh_player_input_lock`。**UI 皮肤由 `UIStyleFactory.apply_tactical_tree` 统一注入**，自绘 UI 须带 `ui_style_exempt` meta。数值给公式，视觉改动需实拍。",
    ),
]

# 读取（LF 域）
main = open(MAIN, "rb").read().decode("utf-8").replace("\r\n", "\n")
play = open(PLAY, "rb").read().decode("utf-8").replace("\r\n", "\n")

before_main = len(main.encode("utf-8"))

missing = []
for old, new in EDITS:
    if old not in main:
        missing.append(old[:70])
        continue
    main = main.replace(old, new, 1)

if missing:
    print("!! 未命中，未写盘：")
    for m in missing:
        print("   -", m)
    raise SystemExit(1)

# playbooks 追加
anchor = "- 落设计源前必核两处：Boss 房门位（草案画「西进东出」vs 美术源「南进西出」）、`floor_00.json` 的 `entry_side=east`/`exit_side=west` 语义（与草案方向相反，且会让安全屋两门重合）。"
if anchor not in play:
    print("!! playbooks 锚点未命中，未写盘")
    raise SystemExit(1)
if "下滑自 MEMORY.md（2026-09-25 瘦身" in play:
    print("!! playbooks 已含本轮新节，未写盘")
    raise SystemExit(1)
play = play.replace(anchor, anchor + "\n" + NEW_SECTIONS.rstrip("\n"), 1)

# 写回（CRLF）
def write_crlf(path, text):
    data = text.replace("\n", "\r\n").encode("utf-8")
    open(path, "wb").write(data)
    return data

d_main = write_crlf(MAIN, main)
d_play = write_crlf(PLAY, play)

for name, data in (("MEMORY.md", d_main), ("MEMORY-playbooks.md", d_play)):
    crlf = data.count(b"\r\n")
    lone = data.count(b"\n") - crlf
    crcr = data.count(b"\r\r")
    print("%-22s size=%d crlf=%d loneLF=%d crcr=%d" % (name, len(data), crlf, lone, crcr))
print("MEMORY.md: %d -> %d bytes (%+d)" % (before_main, len(d_main), len(d_main) - before_main))
