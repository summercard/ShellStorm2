# 2026-10-12｜共享色盘 .import 被导入流程改坏（材质串色）—— 已修复并加门禁

业主原话：

> 「是不是改了我的材质球属性，我的材质球不能加入 MipMap，会导致有很多纹理叠加。
> 参考原来的材质球设置。」

**结论：是。是我做的。已逐字节恢复，并加了一条会失败的门禁断言防复发。**

## 一、我改坏了什么

`assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png.import` —— 这是被 git 跟踪的
**契约文件**（`.gitignore` 三处 `!` 例外专门放行它入库）。

我跑 `godot --headless --import` 后它被重写了 **5 处**（对照 `d1cfe5d9` 的 diff）：

| 项 | 原值（正确） | 我改坏的 | 后果 |
| --- | --- | --- | --- |
| `compress/mode` | **0（无损）** | **2（S3TC/ETC2 块压缩）** | 51×51 px 一格被 4×4 块压缩 ⇒ 跨格污染 |
| `mipmaps/generate` | **false** | **true** | 🔴 **缩小采样时相邻色格互相插值 ⇒ 全项目模型串色** |
| `uid` | `uid://dtuahqaj31kp2` | `uid://b7d71mrdyk8vc` | 引用它的 16 个 GLB 全部回退文本路径 |
| 纹理路径 | 单个无损 `.ctex`（694 B） | `.s3tc.ctex` + `.etc2.ctex`（各 174 828 B） | 由无损变块压缩 |
| `process/size_limit` | 1024 | 0 | 撞 `check_runtime_texture_policy` 断言 |
| `metadata/vram_texture` | false | true | 真实 GPU 内存占用反而变大 |

同一批还改坏了 `assets/art/shared/textures/enemies/tex_normal_fa20394fbaf52f6d81c7.png.import`
的 `compress/normal_map`：`1 → 2`。

**「很多纹理叠加」的技术解释**：色盘是 10×10 纯色格。开 MipMap 后，1/2、1/4… 各级
mip 层会把相邻色格平均到一起；模型上的 `PaletteUV` 岛只要有一点点越界或采样半径，
就取到这层"糊在一起"的颜色 ⇒ 看起来就是纹理/颜色叠加。加 `compress/mode=2` 的
块压缩后，块边界进一步跨格扩散，更明显。

### 为什么会发生

我用了一个**全新的隔离 APPDATA**（`D:\ssappdata_exitsign`，为跑 headless 验收而建）。
Godot 在这个"没有编辑器和导入记录"的环境里按**首次导入**处理，于是按默认值 +
3D 用途检测重写了 `.import`（默认就是 `mode=2` + `mipmaps=true`）。

我已实测确认这条边界：

| 条件 | `--import` 是否改写 `.import` |
| --- | --- |
| 全新 APPDATA（无 `uid_cache.bin`） | ❌ **会改写**（本次事故） |
| 已有 `uid_cache.bin` 的既有 APPDATA | ✅ 不改写（实测 sha256 前后一致） |
| 项目既有隔离目录 `/d/ssverif/appdata` | ⚠️ 只有 `app_userdata`、**无编辑器缓存** ⇒ 同样会走首次导入 |

同一次 import 里 `.godot/uid_cache.bin` 被重建（mtime 13:38）。

## 二、修复

| 步骤 | 动作 | 结果 |
| --- | --- | --- |
| 1 | 备份污染版到 `ShellStorm2-work/scratch/exit_neon_sign/import_restore_backup/` | 可回溯 |
| 2 | `git show 02bcd6c5:<path>` 恢复到工作区（**不用 `git checkout`，避免动索引**） | 与正确基线**逐字节一致** |
| 3 | 删污染期孤儿 `*.s3tc.ctex` / `*.etc2.ctex` / `*.md5` | 强制重导 |
| 4 | 重跑 `--import` | 生成**单个无损 `.ctex`（694 B）**，`.import` sha256 前后一致 |
| 5 | `check_runtime_texture_policy.py` | **`RUNTIME_TEXTURE_POLICY_OK`，errors=[]** |
| 6 | 探针 `probe_exit_neon_sign` | `PROBE_EXIT_NEON_SIGN_OK`（三材质角色正确、AABB 不变） |

恢复后关键值：`compress/mode=0`、`mipmaps/generate=false`、`process/size_limit=1024`、
`uid="uid://dtuahqaj31kp2"`、`"vram_texture": false`、单 `path=…ctex`。

## 三、门禁加固（防复发）

`scripts/check_runtime_texture_policy.py` 新增一段**共享色盘契约**断言：

```python
# 共享色盘契约（业主 2026-10-12 反馈「材质球不能加 MipMap、会纹理叠加」）：
# 色盘是 10×10 纯色格，一旦开 MipMap 或改用块压缩（mode=2），缩小采样时
# 相邻色格会互相插值 ⇒ 全项目引用它的模型集体串色。这两项都是引擎在
# 「全新 APPDATA / 缓存失配」下重导时按默认值回归的，必须由断言盯着。
if rel=='assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png.import':
    for want_key,want_value in (('compress/mode','0'),('mipmaps/generate','false')):
        ...
        errors.append({'path':rel,'error':'shared_palette_contract',
                       'key':want_key,'want':want_value,'got':got})
```

脚本本来就在套件里（`run_verification_suite.sh` 静态段）⇒ **任何人再污染，套件直接红。**

**反向对照（项目标准做法，断言必须能红）**：

| 注入 | 门禁输出 |
| --- | --- |
| 正常态 | `RUNTIME_TEXTURE_POLICY_OK` errors=[] |
| `mipmaps/generate=true` | `RUNTIME_TEXTURE_POLICY_FAILED` → `shared_palette_contract key=mipmaps/generate want=false got=true` |
| 再叠 `compress/mode=2` | 报 **2 条** `shared_palette_contract` |
| 还原 | 逐字节一致 + `OK` |

## 四、没动的东西

- 未改色盘 PNG 本身（`mtime` 仍是 2026-09-17，字节未动）；
- 未改任何 GLB / 材质 .tres / 场景；
- 未改 `tex_normal` 的 `mode` / `mipmaps`（那两项**本来就是这个值**，`d1cfe5d9` 的 diff
  显示我那次只动了 `normal_map`）；
- 未改 `enm_boss_monitor002` 的 `body_palette`（见下）。

## 五、⚠️ 顺带发现：Boss002 `body_palette` 有同源风险（**未擅自改**）

`assets/art/enemies/bosses/enm_boss_monitor002/components/enm_boss_monitor002/enm_boss_monitor002_visual_top3d_body_palette.png.import`

实测：这张 256×256 的图是 **10×10 纯色格色盘**（格心仅 9 种唯一色），而它的
`mipmaps/generate=true` + `compress/mode=2` —— **与色盘同一类串色风险**。

**但它不是我改的**：`git status` 对该文件为空，历史里（`02bcd6c5`）就是 `mode=2 / mipmaps=true`。
它属于别人的资产、且是 `.gitignore` 放行的契约文件 ⇒ **我没有擅自改**。

需要业主定夺：是否把它也按"纯色格色盘 ⇒ 关 MipMap + 无损"处理？
若处理，应连带重导并跑 Boss002 的表现验收。

## 六、纪律（新增）

1. 🔴 **跑 `--import` 不要用一次性新建的隔离 APPDATA。** 全新 APPDATA = 首次导入 =
   按默认值重写 `.import`。要重导就用**已有缓存**的环境，且**跑完核对 `.import` 是否被改**
   （`git status` + sha256 比对）。
2. 🔴 **被 git 跟踪的 `.import` 是契约文件，不是缓存**。它们被 `!` 例外专门放行入库，
   就是为了锁住导入参数。导入后出现"我没改过的 .import 却被改了"，一律先怀疑导入环境。
3. 🔴 **导入日志里成片的 `invalid UID ... using text path instead` 不要当噪声放过。**
   本次它刷了 16 条，我上一轮误判为既有现象 —— 其中一部分确实是历史 UID 格式问题
   （`dtuahqaj31kp2` 只有 13 字符，Godot 4.6 合法 UID 为 14 字符，项目 2026-10-09
   块00设施文档已记录过该回退），但**成片出现时仍应先核对 `.import` 的 `uid=` 有没有被动过**。

## 七、本事务文件

| 文件 | 动作 |
| --- | --- |
| `assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png.import` | 恢复（= `02bcd6c5` 逐字节） |
| `assets/art/shared/textures/enemies/tex_normal_fa20394fbaf52f6d81c7.png.import` | 恢复 `normal_map=1` |
| `scripts/check_runtime_texture_policy.py` | 新增共享色盘契约断言 |
| `ShellStorm2-work/scratch/exit_neon_sign/import_restore_backup/` | 污染版备份（可回溯） |

⚠️ **两个 `.import` 的恢复目前只在工作区，尚未提交** —— `HEAD`（`f3a10234`）里仍是污染值，
不提交则等于没修。需要一次提交把它固定。
