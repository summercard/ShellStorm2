---
name: godot-verification-suite-triage
description: 诊断并修复 Godot 验收套件（run_verification_suite.sh + check_verification_log.py）的门禁失败——exit 1/2（依赖脚本编译失败、场景压根跑不起来）与 exit 3（意外引擎错误）、exit 4（退出时资源泄漏）。用于「套件跑出红项 / 场景 exit 1、2、3 或 4 / Identifier not declared / Failed to compile depended scripts / resources still in use at exit / ObjectDB instances leaked / 判某红项是回归还是既有 / 要不要加 expected_errors 白名单 / 套件太慢想直跑单场景分诊」这类问题。不用于资产制作、也不用于正常通过时的收尾。
agent_created: true
---

# Godot 验收套件门禁失败：定性 → 定位 → 修复

## 铁律

1. **不看裸退出码**。本机 safe-delete 守卫会拦下套件 EXIT trap 的 `rm -rf` 临时工作区并**覆盖退出码**，表现为打印 `VERIFICATION_SUITE_OK` 却 `EXIT=1`。**只看 `VERIFICATION_SUITE_OK` / `VERIFICATION_SUITE_FAILED` / `FAILED_SCENE <名>:<码>` 行。**
2. **不手搓 Godot 命令行跑验证场景**。`visual`/`renderer` 名单里的场景去掉 `--headless` 会挂死等 viewport 纹理（曾空转烧 40 分钟）。一律 `bash scripts/run_verification_suite.sh scene <名>`，它会在 `is_renderer_scene` 命中时自动切非 headless。
3. **`git status` 在本仓不可信**（曾漏报 16/17 处索引-工作区差异）。**暂存完整性一律用 `git diff --name-only`**。

## 退出码语义（`scripts/check_verification_log.py`）

读日志逐行，命中 `SCRIPT ERROR:` 或 `(^|\s)ERROR:` 的行才计入：

| 命中内容 | 返回 | 含义 |
|---|---|---|
| 白名单 `tests/verification/expected_errors/<场景>.txt` 里的正则 | 跳过 | 预期错误 |
| `resources still in use at exit` / `ObjectDB instances leaked at exit` | **4** | 资源泄漏 |
| 其他任意 `ERROR:` / `SCRIPT ERROR:` | **3** | 意外引擎错误 |

`run_scene()` 的判定链：headless 跑 `verify_scene_preflight.gd`（2=装载失败、3=preflight 日志有意外错误）→ 跑场景本体（`scene_result`）→ 判日志（`log_result`）。**当 `scene_result==0 && log_result!=0` 时返回 `log_result`**，所以「场景自己 exit 0、日志有 ERROR」会表现为 exit 3 或 4。

> ⚠️ 只有 `ERROR:` 前缀的 `ObjectDB instances leaked at exit` 才算；`WARNING: ObjectDB instances leaked at exit` 不计入。

## 决策树

```
FAILED_SCENE x:1  → 场景没跑到 quit(0)：多为依赖脚本编译失败，走「编译链断裂」
FAILED_SCENE x:2  → preflight 装载失败：场景/依赖根本 load 不出来，同上
FAILED_SCENE x:3  → 是「预期错误没声明」还是「真 bug」？
   ├─ 该 ERROR 是本测试**刻意**触发的（例如测试故意传非法 id 断言被拒绝，
   │  被调用方用 push_error 报出）→ 加白名单文件，见下节
   └─ 否则 → 真 bug，修代码

FAILED_SCENE x:4  → 资源泄漏，走「泄漏定位」
```

## exit 1 / 2：场景根本跑不起来（编译链断裂）

日志开头（不是结尾）就会出现：

```
SCRIPT ERROR: Parse Error: Identifier "XXX" not declared in the current scope.
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.
ERROR: Failed to load script "res://src/.../A.gd" with error "Compilation failed".
```

**注意区分**：这不是日志门禁（3/4）问题，是**场景压根没加载成功**。所以别去加 `expected_errors` 白名单——加白名单只会把真问题盖住。

定位三步：

1. **取第一个 `SCRIPT ERROR`**，grep 那个未声明标识符在全仓的**定义处**。
2. **「只有引用、没有定义」= 半成品**。本仓多会话并行是常态，用 `git diff -U0 <文件>` 看该文件改动：若**纯新增却引用了不存在的符号**，就是在途编辑留下的中间态。
3. **不要替它改**。同文件并发写会互相覆盖（一条消息里的多个 Edit 也会互相覆盖）。报出来 + 记进当日日志，等它收尾后补跑。

**一批场景同时红，先看第一个 `SCRIPT ERROR` 指向谁。** 传播链会放大：一个 config 脚本坏掉 → 所有依赖它的模块坏掉 → 依赖那些模块的场景整批 exit 1。例：`GameDesignConfig.gd` 坏了 → `WastelandLight3D.gd` 编译失败 → 四个玩家/背包/动画场景全 exit 1，而**不依赖 WastelandLight3D 的资产导入场景照样 `[PASS]`**。

### 另有两类「假故障」，先排除再报并发会话（2026-09-21 实测）

**A. 新增 `class_name` 后类缓存没刷新** —— headless 直跑场景**不会重扫** `class_name`。并行会话刚落一个带 `class_name` 的新脚本（如 `src/ui/bubble/CharacterBark3D.gd`），你这边立刻直跑就会得到
`Could not resolve class "X", because of a parser error` / `Could not find type "X" in the current scope`，**看起来像半成品，其实文件已存在**。
**判据**（秒判）：`grep -c "X" .godot/global_script_class_cache.cfg` 为 0，或缓存 mtime **晚于**你的启动时刻 ⇒ 就是它。
**修法**：先 `--headless --path . --import` 刷缓存，再重跑。**别去「替它补定义」。**

**B. 文件行尾被写成 CRCRLF（`0d 0d 0a`）** —— 用 Python **文本模式**重写一个已含 CRLF 的文件就会这样（每行被再插一个 `\r`）。两个后果：
1. `git diff` 把**整个文件**报成改写（实测 1792 行的文件 → 3377 行 diff），且 **`--ignore-cr-at-eol` 也救不了**（clean 过滤器只能把 `\r\r\n` 削成 `\r\n` ≠ blob 的 LF）。**别据此判断「LF↔CRLF 转换」，那是误判。**
2. **GDScript 解析器直接失败**：`Could not resolve class "X", because of a parser error`，该脚本整类不可用；依赖它的探针 `_ready()` 永不执行 ⇒ `get_tree().quit()` 永不被调 ⇒ **进程空转到超时**（实测空转 15m50s 才被杀）。

**判据**：`head -c 120 <文件> | xxd` 看到 `0d 0d 0a`；或 `tr -cd '\r' < <文件> | wc -c` ≈ **2×行数**（对照：`grep -c $'\r' <文件>` 也会等于行数，**看不出双 CR，别用它判**）。
**修法**：`\r\r\n` → `\r\n`（工作区口径 CRLF，git 入库时按 `core.autocrlf=true` 归一为 LF）。**闸门**：归一前后「剥掉全部 `\r`」的字节必须完全相同（内容零变化证明）+ 归一后不得残留 `0d0d0a`。`--ignore-cr-at-eol` **不能**当闸门。
**预防**：写回一律 `open(p,"rb")/open(p,"wb")`，或文本模式显式 `newline=""`。

> ⛔ **通用教训**：「探针/场景跑几分钟甚至几十分钟不结束」**先按解析失败查**（`grep -n "Parse Error\|Failed to load script" <日志>`），别当「慢」处理。解析失败的探针不会退出，会一直空转。

**特例：`Class "X" hides a global script class`（同名 `class_name` 抢注）**

报错形如 `错误 (1, 12)：Class "DungeonRoom3D" hides a global script class.`。列号 12 落在 `class_name ` 之后，说明冲突源在某个脚本的**第 1 行**。

三步定位（第 2 步是铁证）：

1. **扫全仓重复**（必须排除 `.godot`）。⚠️ 不要用 Grep 工具，本仓会 30s 超时；用 bash grep 或 Python `os.walk`，后者顺带打出每个重复项的 `文件:行号`：
   `grep -rh --include=*.gd --exclude-dir=.godot -E "^class_name +" . | sed "s/class_name *//" | sort | uniq -d`
2. **查类缓存**——它直接告诉你该类名**现在挂在哪个路径**（经常不是你以为的那份）：
   `grep -n -B6 '"class": &"X"' .godot/global_script_class_cache.cfg | grep path`
3. **重复源多半是快照/备份脚本**（`*.before.gd`）掉进了 res:// 内的 `_scratch/`。

修法：把副本**移出 res://**（放到项目外，如 `<工作区根>/_scratch/godot_script_backups/`），`.gd` 与其 `.uid` 一起移；先 grep 全仓确认无引用，再 `--headless --path . --import` 重刷缓存，最后三重复核：**缓存 path 指回正本** + **重扫重复数为 0** + **直跑一条依赖该类的场景拿 `*_OK`**。

⚠️ **别给 `_scratch` 加 `.gdignore`**：那里的 `probe_*.gd` / `*.tscn` 是要真跑的探针，加了就再也加载不了。**只搬带 `class_name` 的副本**。

⚠️ **危害大于报错本身**：缓存被旧副本抢注后，`extends X` / `X.常量` 会**静默拿到旧版脚本**（2026-09-20 先例：`DungeonRoom3D` 被 `_scratch/task_house/DungeonRoom3D.before.gd` 顶掉，正是这个错把问题暴露出来的）。所以必须复核缓存 path，不能只看报错消失。

## 加速分诊：`--headless` 直跑单场景（只分诊，不替代套件）

套件每跑一条都要重建隔离工程，实测**单场景 >7 分钟**；直跑同一条只要 **4–7 秒**：

```bash
"<Godot>_console.exe" --headless --path "<工程绝对路径>" \
  --scene "res://tests/verification/<场景>.tscn"
```

用途：快速拿到**权威 PASS/FAIL 与原始日志**来定位破损点（尤其 exit 1/2 这种"跑不起来"的情形）。

**三条限制，都必须记住**：

- **只对非渲染场景**：`visual_scenes` / `renderer_scenes` 名单里的场景去掉 `--headless` 会挂死等 viewport 纹理（见铁律 2）。⚠️ 反过来更常见：**给截图类场景加了 `--headless`，`get_viewport().get_texture().get_image()` 返回 null** → 报 `Cannot save ... preview` / `Parameter "t" is null`。这是**跑法错了，不是代码坏了**。跑前先查该场景在不在 `visual_scenes`。
- **用真实 user dir**：不隔离存档，会写存档的场景别这么跑。副作用之一：可能多出 `ERROR: Can't create shader cache folder`（套件的隔离 user dir 里不会出现），会让日志门禁误判 exit 3。
- **跳过 `check_verification_log.py`**：`[PASS]` 里也可能夹带 `SCRIPT ERROR`，**不能据此判绿**。

**要拿正式判定时的替身组合**：直跑场景取场景退出码 + 单独手跑日志门禁
`python3 scripts/check_verification_log.py <日志> tests/verification/expected_errors/<场景>.txt`
两者都 0 即等价于套件判定。注意脚本场景名要带 `I:/...` 绝对路径的日志，别让相对路径落到错误的工作目录。

> ⚠️ **绝不要用 `: > "$exp"` 之类去"准备一个空白名单"** —— 若 `$exp` 恰好指向仓库里**真实存在**的
> `expected_errors/<场景>.txt`，这会**把仓库白名单清空**，原本绿的场景立刻变 exit 3。
> 需要"无白名单"时用 `/dev/null`，并且**先 `[ -f ]` 判断存在就原样沿用**。
> 已清空的用 `git checkout -- <文件>` 还原，再用 `git diff --name-only` 确认。

### 套件在本机跑不动时的判定（Windows + PortableGit + 安全守卫）

症状：`bash scripts/run_verification_suite.sh ...` **无输出、日志 0 字节、被 SIGTERM 杀掉**，`run_in_background` 也一样，绕过沙箱也一样。两个叠加原因：

1. **`cygpath` 版本错配（可修）**。为补 `dirname`/`basename` 而 `export PATH="/c/Program Files/Git/usr/bin:$PATH"`，会让 `cygpath` 解析到 **Git for Windows** 的版本，它把 `/tmp` 映射成 **`C:/Windows`**：
   ```
   cygpath -m /tmp        -> C:/windows        # 错！套件会在 C:\Windows 下建工作区
   cygpath -m /c/Users/…  -> C:/Users/…        # 对
   cygpath -m I:/…        -> I:/…              # 对（Windows 风格原样透传）
   ```
   所以跑套件前**把 TMPDIR 设成 Windows 风格路径**（如 `I:/…/_scratch/vtmp`），别让它落到 `/tmp`。
2. **退出清理被守卫拦下**（不可绕）。套件 EXIT trap 里的 `rm -rf` 会被本机 safe-delete 守卫拦，进程随之被终止——表现为启动阶段就被 SIGTERM，连第一个 `printf` 都写不进日志。

**结论**：本机套件的正式判定不可得。用上面的「直跑 + 手跑日志门禁」组合做**定向回归**（把该功能相关的场景列出来逐条跑），并把套件留到能正常执行的环境上补跑。**不要因为套件跑不动就宣称验收通过**——要说清哪几项是用替身组合验的。

### 加白名单的正确姿势

`tests/verification/expected_errors/<场景>.txt`，一行一个 **Python 正则**，`#` 开头是注释：

```
# 说明这是哪个测试的哪一项刻意触发的
ERROR: \[MusicManager\] music_id 未注册
```

- 文件编码 UTF-8、无 BOM、CRLF（与同目录既有文件一致）。
- **正则里的 `[` 必须转义**：`[MusicManager]` 会被当成字符类，静默匹配不到。
- 匹配的只是那一行；断言本身失败仍走 `get_tree().quit(1)`，不会被掩盖。
- 先确认这不是本次改动引入的：`git stash push -- <改动文件>` 后在 HEAD 上复跑，同样的 exit 码即既有问题。

## 泄漏定位（exit 4）

**第一步：判归属。** 若多个不相关场景的泄漏签名**恒为同一句 `2 resources still in use at exit`**（数值不随场景加载的资产变化），那必是 **autoload / 全局单例级**，不是资产。若泄漏数值随场景变化，才往资产方向查。

**第二步：看漏了什么。** 套件只报条数。加 `--verbose` 取证的做法是**复制套件脚本**，只在两处场景分支（`is_renderer_scene` 的 if/else）加 `--verbose --scene`，然后走套件自身的隔离工作区跑：

```bash
cp scripts/run_verification_suite.sh /tmp/_tmp_verbose_suite.sh
# 在两条分支的 godot 命令行里插入 --verbose
GODOT_BIN="<godot_console.exe>" bash /tmp/_tmp_verbose_suite.sh scene <场景名> 2>&1 | grep "still in use"
```

日志会出现 `Resource still in use: <res://路径> (类型)`。

**第三步：判「时序相关」还是「确定性」。** 同一场景连跑 5–6 次统计泄漏次数。偶发即时序相关——这类**不能靠加 `stop()` 解决**，要顺着「谁在退出前后还动了它」查。

**第四步：区分「真回归」与「既有」。**

```bash
git stash push -- <改动文件>          # 回到 HEAD
bash scripts/run_verification_suite.sh scene <场景名>
git stash pop
```

两边同码即既有。另可用审计基线 `docs/v0.1/audits/evidence/core_results.json` 对 `aggregate core` 做集合比较：**判据是「当前红项集合 ⊆ 基线红项集合」，不是「core 全绿」**——本仓 core 从来不是全绿。

## 已知修复约定：headless 不真播

**先例**：`src/core/AudioManager.gd:72`

```gdscript
# Headless validation不创建播放器，但仍可通过 validate_runtime_assets() 校验文件。
if DisplayServer.get_name() == "headless":
    return
```

套件对**非渲染场景**一律加 `--headless`，而这些场景只断言状态、不校验声音。所以在 headless 下跳过真实播放是**仓库认可的写法**，不是绕过测试。

`MusicManager` 的已落地版本（`docs/v0.1/development/2026-09-17_music_manager_headless_exit_leak.md`）：

- `_exit_tree()`：kill tween → `stop()` + `stream = null` → 清状态 → 回收运行期补建的 AudioBus。
- `_shutting_down` 标志：**在 `play()` 和 `_play_track()` 两处都要守卫**，因为 `_on_stream_finished` 的循环重播会绕过 `play()` 直接进 `_play_track()`。
- `_play_track()` 在 headless 下**不 `load()`、不播放**，只落状态字段并发变更信号 → 副作用是 headless 下 `is_playing()` 恒 `false`，判「在放哪首」必须用 `get_current_music_id()`。

> 关键教训：**`stop()` + `stream = null` 压不住 Ogg 回放对象**（`AudioStreamPlaybackOggVorbis` / `OggPacketSequence` 在解码收尾阶段无法确定性释放）。真正的解法是**根本不在 headless 里加载它**。

## 收尾

1. 跑 `aggregate core` 复验，确认泄漏行归零且**红项集合 ⊆ 基线**。
2. 跑静态门禁：`python3 scripts/check_asset_runtime_naming.py --quiet`、`python3 scripts/check_asset_registry.py --scope structure`（需 venv python + openpyxl，且在 `/tmp` 下跑）、`check_documentation_contracts.py`。
3. 删掉临时脚本，`git diff --name-only` 应为空。
4. 提交信息里写清：症状 → 根因（含被排除的可能性）→ 修法 → 逐场景验收 → 相对基线的红项集合比较。
5. **同步记忆**：若本次推翻/补全了旧结论，改 `MEMORY-playbooks.md` 里的原条目（别只追加）。
