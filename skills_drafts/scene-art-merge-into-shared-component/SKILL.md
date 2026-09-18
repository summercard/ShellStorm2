---
name: scene-art-merge-into-shared-component
description: 把房间/场景自持的方位化美术（墙面装甲、门禁、地砖压边等装饰）剥离并并入通用组件库，再让房间侧槽位改为引用组件，使任意 5m 网格槽位与朝向自动对齐、无需按方位区分资产。用于装饰并库、冗余方位包清理、房间版本升版与全链路复验；不用于新建设施资产、不用于角色/武器/道具。
agent_created: true
---

# 把房间美术并入通用组件

## 适用边界

- **适用**：房间或场景里「按方位重复出现、但每面几何其实一样」的装饰 —— 墙面装甲壁板、门框门禁、地砖压边与拼缝、墙脚压条。目标是**把装饰搬进通用组件**，房间侧只留槽位引用，于是「不用按方位、完整替换、自动对上」。
- **不适用**：新建具体设施资产（→ `blender-game-prop-standard` / `godot-model-asset-import-standard`）；房间从白模起做正式美术（→ `scene-full-pipeline`）。

先读 `scene-full-pipeline` 确认当前处在哪一阶段；本 skill 是**阶段2↔阶段3 之间的装饰并库动作**，前置条件是通用组件库已存在、房间已引用组件**裸结构**。

## 为什么这件事能做（先证明，再动手）

能不能并，取决于三条事实。**三条都要在动手前用只读探针量出来**，不能假设：

1. **同一单元在各方位逐值相同。** 在**组件局部帧**量每个槽位的装饰并集盒，比对是否逐值一致。若某方位不同（原稿节奏不落在网格上，例如 5×2.9m 不落 5m 槽），该方位要么正常化、要么排除，并记为明确的例外。
2. **结构与装饰可解耦。** 组件**结构板**的顶点数/面数/包围盒，必须与房间原槽位的结构件逐值相同。若相同，就能只在装饰上做增量、不动本体板；若不同，先解释差异再动。
3. **房间的方位装饰确实已被覆盖。** 按名字前缀把房间侧装饰分组（`墙体内嵌面板`/`面板分缝`/`门框立柱`/`门框蓝色灯条`/`门楣护板`/`门楣顶灯`/`地砖压边`/`蓝色拼缝`/`检修格栅`/`格栅暗底`/`地砖磨损`），逐组登记件数与包围盒，作为后续交接与"损失记账"的基线。

## 步骤

### 1. 只读探针（不改任何文件）

- 探组件库：列出目标组件的集合名、对象名、父级、顶点/面数、**对象局部**包围盒、材质。
- 探房间源：按集合分组列出墙/地/门相关美术，标注哪些属于即将被吸收的装饰。
- 探已存在的房间槽位：结构件的顶点/面数（做第 2 条事实的对照）。

### 2. 在组件库升版新目录（不要就地改旧版）

沿用 vNNN 递增。旧版保留可回滚。把装饰并入时：

- 用**连通分量分解**（并查集过 mesh edges）把合并美术拆成按件几何 —— 直接按整体包围盒切是错的。
- 逐件保留 `PaletteUV` 与材质；不要重新赋材质。
- **canonicalisation 陷阱**：库件几何已在 root-local（顶点已是 root-local、对象挂在携带展示阵列偏移的 `ROOT_*` 下且自身恒等变换）。**不要再减一次 ROOT 位置**，否则整排件移位数十米。断言要在 **root-local** 下做（`W(root).inverted()` 折算），不要在展示阵列的世界坐标下看"居中"。

### 3. 写 replay 断言（这是"自动就能对上"的证明）

把组件局部美术经**每个槽位的变换**推回房间世界几何，逐槽比对原房间艺术盒。判据分两类：

- **整件 replay**：适用于每槽完全一致的件（装甲、门禁）。
- **结构框 replay**：地砖因每块磨损独一无二、且某些类目真分两款，整砖不可能全同。改为对**结构框**（4 条压边 + 2 条拼缝）逐值对齐，并显式记录"磨损重复/取某一款"为 WARNING，而不是假装通过。

### 4. 导出 GLB + PackedScene + 色盘契约

- GLB：`export_apply=True`、`export_yup=True`、`export_image_format="NONE"`（不内嵌色盘）。
- `.glb.import` 必须打色盘契约：`import_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"` 且 `gltf/embedded_image_handling=0`。
- PackedScene：`Node3D` 根（挂 metadata）+ `ImportedModel`（GLB 实例）+ `StaticBody3D` 碰撞。**碰撞盒按结构不按美术** —— 装饰不改变体积，碰撞盒必须与上一版**逐值相同**，否则等于偷偷改了阻挡。另存 `visual_bounds_size_m`（美术实测）以便事后核对，别让它和碰撞盒混淆。
- **生成器要硬拦重复 metadata 键**。同一 `metadata/xxx` 写两次时后写静默覆盖前者，会悄悄丢掉基线契约（例如地板失去 `per_instance_instantiation`）。让生成器在写之前 `SystemExit`。

### 5. 房间侧升版（新目录，不就地改）

- 复制上一版全部 qa 脚本到新版本目录，**先把脚本里的源版本常量与路径批量升版**，再改逻辑。升版只作用于 `source/`（blend、导出清单、`component_packages`）与 manifest/节点 meta 的版本字段；**`components/` 与 `runtime/` 的 Godot 路径不带版本号，脚本输出的 GLB/PackedScene 名不受版本影响**（替换即覆盖）。
- 槽位改为实例化**完整组件视觉**（结构 + 装饰一起），删除冗余方位包。
- 重新对齐计数断言（包数、槽位数、槽位对象数）。**槽位对象数 = 结构件 + 装饰件**，逐类目写清期望值，别只写总数。
- **别漏上一版的合并/evaluate 阶段**。房间包通常有一个"逐包合并成 `整合主体` + `UI灯光_柔和自发光`"的段落，它同时产出 `outputs`/`bounds`/`merge_consistent`。漏掉它会在下游以 `KeyError: 'outputs'` 的形式炸出来。

### 6. 独立复验（重开保存文件，不复用构建期内存）

独立验证器必须**重新打开磁盘上的 blend** 量交付几何，检查项与构建自检**刻意不重合**。除继承上一版的检查外，为本次变更新增：

- 房间不得持有任何方位化装饰（按前缀白名单扫全库）。
- 装饰必须**在槽位里**，且各类目件数与组件契约一致。
- 槽位局部帧一致性（与构建脚本的同名断言互为独立实现）。

### 7. Godot 验收场景 + 无头导入

- 仿上一版写 `*_vNNN.gd/.tscn`，路径指向新版 tscn，几何期望尺寸按**本次导出实测**填写。
- **按组件类型分流校验**：门扇是嵌在门洞里的独立板件，不贴网格中线、XZ 对称，别用墙那套判据套它。
- 加进 `scripts/run_verification_suite.sh` 的 core 套件，并复跑上一版场景确认**无回归**。

### 8. 台账升版 —— 就地改行，不追加新行

版本写在版本列，AssetID 全表唯一、无 version 后缀。因此升版是**改那一行**（路径 + 版本列 + 说明列），不是追加。用**外科式 XML 补丁**只替换 `xl/worksheets/sheetNN.xml`，逐字节复制其余条目，保留 styles / sharedStrings / mergeCells / dataValidation；补丁后断言 XML 合法 **且行数不变**、目标行 AssetID 与期望一致。写盘前先 `--dry-run`。

账本已按域分册（映射唯一真源 `assets/registry/ledger_index.json`，说明见 `assets/registry/README.md`）：本流程改的是**场景账本** `assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx`，**不是**总目录 `assets/registry/ShellStorm2_美术资产台账_v001.xlsx`。总目录不含资产行，写错文件会被 `scripts/check_asset_registry.py` 的跨文件契约拦下。

## 一致性口径：同一个数只能定义一次

多级校验最容易出的错是**同一件事两处用不同容差**。例：槽位级门洞闸门用严格 AABB 判 `eat > 0`，把组件自带门框 LED 条的 17.5mm 判成冲突；同一次构建的物件级扫描却按 30mm 容差放行。**把容差常量上提到文件头单点定义**供两处共用，并把小量值记为可审计的具名记录（`..._lips_under_core_skin`），而不是隐藏或删除 —— 闸门仍要能抓真缺陷（墙板落进门洞、单元转错、门楣掉进洞口，侵入量都远大于 30mm）。

## 环境陷阱（Git Bash + 原生 Godot 的 Windows）

- `mktemp "${TMPDIR:-/tmp}/..."` 在 Git Bash 下产出 `/tmp/...`；Godot 是原生 exe，直接判 `Invalid project path` 并 abort；python 也会把 `/i/...` 解析成 `I:\i\...`。脚本里加：**能拿到 `cygpath` 时把 `project_root` / 临时目录转成 drive-letter 形式**（macOS/Linux 无 `cygpath`，整段跳过，行为不变）。
- 跑法：
  ```
  export GODOT_BIN="<...>/Godot_v4.6.3-stable_win64_console.exe"
  bash scripts/run_verification_suite.sh scene <verify_scene_name>
  ```
- 导出新 GLB 后要触发导入扫描（`--headless --path . --import`）才会生成 `.import` 与 `.godot/imported/*.scn`。

## 序列化容器陷阱

- `catalog.json` 可能是**裸 list**（不是 `{'packages': [...]}`）；`tree.txt` 才是 slug→集合名。读之前先探类型。
- 自建 CONTRACT 的键名可能与预期不同：`parts[<part>]['local_bounds'/'family']` + `component_bounds`，而不是 `family_bounds`。**先 probe 键名，再写读取代码**。
- `.tscn` 里 metadata 字符串要带双引号，`Vector3(...)` 构造式不带引号。

## 交接与记账

- 每个被删除的房间侧装饰包，记「删了多少件 → 由多少槽位件供给 → 是逐值复刻还是规范化的」。**规范化必须显式写出来**，不能混在"已完成"里。
- 房间 README / QA_REPORT 要写清：哪些是逐值复刻、哪些是规范化的例外、哪些是风格化（磨损之类）。
- **Blender 美术完成 ≠ 已接入运行时。** 交付前先确认 `src/` 下是否真的存在引用该资产 AssetID 或目录的 `.gd`/`.tscn`；若没有，交付说明里必须写"运行时未接线"，并把它作为独立的桥接设计任务列出（需先定 `room_type → 组件` 映射），不要擅自开工。
