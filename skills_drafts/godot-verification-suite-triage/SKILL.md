---
name: godot-verification-suite-triage
description: 诊断并修复 Godot 验收套件（run_verification_suite.sh + check_verification_log.py）的门禁失败——exit 1/2（依赖脚本编译失败、场景压根跑不起来）与 exit 3（意外引擎错误）、exit 4（退出时资源泄漏）。用于「套件跑出红项 / 场景 exit 1、2、3 或 4 / Identifier not declared / Failed to compile depended scripts / resources still in use at exit / ObjectDB instances leaked / 判某红项是回归还是既有 / 改了一个配置常量或开关后一批用例同时红且要分清新红与既有红 / 要不要给用例加配置早退 / 要不要加 expected_errors 白名单 / 套件太慢想直跑单场景分诊」这类问题。不用于资产制作、也不用于正常通过时的收尾。
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

**C. 本项目把「变量类型由 Variant 推断」当**硬 Parse Error**（warning-as-error）** —— 只要写 `var x := <某个返回 Variant 的表达式>`，GDScript 会抛
`SCRIPT ERROR: Parse Error: The variable type is being inferred from a Variant value, so it will be typed as Variant.`（2026-09-22 实测，`verify_gamepad_input_flow.gd` 里 `var first_frame := face_of.call()`）。
**最容易踩的源头是 `Object.call()` / `Callable.call()` / `Dictionary.get()` / `Array.pop_back()` 这类内置返回 Variant 的调用**：语法上完全合法、编辑器不标红，但一旦被 `:=` 接住就**整脚本编译失败**。
**传染性症状（很迷惑）**：脚本是 autoload 时表现为 `Failed to instantiate an autoload`，且**别的会话的用例会跟着整批红**（本次实测另一会话的 `verify_finite_ammo_flow` 因此红，被误判成回归）。
**修法**：给变量显式标注类型 —— `var first_frame: Vector2 = face_of.call()`；或先 `var raw: Variant = ...` 再显式转换。**别把 `:=` 用在任何 `call()` 返回值上。**
**判据**：日志里 grep `inferred from a Variant` 命中即确诊，不用再往下查。

**D. 自己的补丁把**注释前缀**丢了（漏一个 `## `）** —— 往 `##` 文档注释块里插行时，漏写前缀，
那一行就**变成代码**（`（同一判据也给 … 用）` 这种以全角括号开头的行），整个脚本解析失败（2026-09-22 实测）。

**传染性症状（最能骗人的一条）**：报的不是「某一行语法错」，而是一串**类名**：

```text
SCRIPT ERROR: Parse Error: Could not parse global class "Dungeon3D" from "res://src/world3d/Dungeon3D.gd".
SCRIPT ERROR: Parse Error: Could not parse global class "TowerDescent3D" from "res://src/world3d/TowerDescent3D.gd".
ERROR: Failed to instantiate an autoload, script 'res://src/enemy3d/MonsterAIManager.gd' does not inherit from 'Node'.
ERROR: Failed to load script "res://tests/verification/verify_xxx.gd" with error "Parse error".
```

**基类挂了 ⇒ 子类也报「Could not parse global class」⇒ 引用它的 autoload 挂 ⇒ 探针压根没加载。**
此时探针**一条 `ok` 都不会打印**、`verify_*_OK` 行永远不出现、进程**空转不退**（本次空转 7m52s 才被手动杀）。
所以日志里「只有引擎噪音 + `Could not parse global class`」= 不是慢，是自己的脚本坏了。

**判据**：`grep -n "Could not parse global class" <日志>` → 拿到文件名 → 只看它**最近改过的那几行**：
`sed -n 'A,Bp' <文件> | cat -A`。**必须以 `cat -A` 看行首**（`^I` = tab，`^I## ` / `^I# ` 才是注释；
直接看内容看不出丢没丢前缀）。

**修法**：补齐注释前缀（`## ` / `# `）。**闸门**：改完必须 `cat -A` 复看整段；
再跑一次探针，确认 `grep -c "Parse Error"` 为 0 且结果行出现。

**预防**：任何「往注释块里插行」的补丁脚本，插入文本的每一行都要**自带注释前缀**，
别依赖「上一行的前缀会延续」——GDScript 没有块注释延续，Markdown 侧也没有。

**E. 自己写的「源码守卫」永久红 —— 先怀疑守卫自己**（2026-09-22 实测）

探针里用 `FileAccess.get_file_as_string("res://src/xxx.gd")` 再 `contains("A\n\t\tB")` 搜**跨行片段**时：
本仓 `.gd` 是 **CRLF**，用 `\n` 拼出来的多行模式**永远匹配不上** ⇒ 守卫**永久红**，
看起来像「代码真的坏了」，其实坏的是守卫。

**判据**：这条守卫红了、但它守的那段代码肉眼看着完全正常 ⇒ 立刻怀疑匹配串。
`print(片段长度)` 或改成**分别按单行片段**搜，一次就能确诊。
⚠️ 这类守卫**不能只跑一次就信**：它「红」可能与自己无关，它「绿」也可能是巧合 —— 所以
**必须做反向对照**（把被守的代码改坏 ⇒ 守卫要变红；还原 ⇒ 要变绿），否则等于没验。

**修法**：读源码后一律先归一 —— `.replace("\r\n", "\n")`，再做跨行 `contains`。
单行片段不受影响，但统一归一最省心（也顺手把「脚本自己写死 CRLF」的隐患一起挡掉）。

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
- **先隔离 `APPDATA`**：默认用真实 user dir、不隔离存档，会写存档的场景别裸跑。**跑前 `export APPDATA="<独享纯 ASCII 目录>"` 即可隔离 `user://`**（见下文），并顺手消掉 `ERROR: Can't create shader cache folder`（不隔离时它会让日志门禁误判 exit 3）。
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
   所以要在**同一个 shell 里**把 `TMPDIR` 设成 Windows 风格路径（如 `I:/…/_scratch/vtmp`），别让它落到 `/tmp`。
   ⚠️ **但这在本机救不了套件 —— 见下面第 3 条**（2026-09-22 实测修正：`export TMPDIR=…` 在子 shell 里会消失）。
2. **退出清理被守卫拦下**（不可绕）。套件 EXIT trap 里的 `rm -rf` 会被本机 safe-delete 守卫拦，进程随之被终止——表现为启动阶段就被 SIGTERM，连第一个 `printf` 都写不进日志。
3. **`TMPDIR` 根本传不进子 shell（2026-09-22 实测，两次归因被证伪后的定论）**。Bash 工具的 shim（`shell-runtime-bash-env.sh`）在拉起子进程时会**清掉 `TMPDIR`**：
   ```
   export TMPDIR="/i/_ss_tmp/tmp"; bash -c 'echo "[$TMPDIR]"'   # => []   ← 空的
   ```
   ⚠️ 危险之处：**同一个 shell 里直接 `mktemp` 却能落到 I:**，所以"我在同一行验过、能行"是**假绿**。于是套件里的 `mktemp -d "${TMPDIR:-/tmp}/shellstorm-verification.XXXXXX"` 永远回落 `/tmp` → 经上面第 1 条的 `cygpath` 错配变成 **`C:\windows`**（系统盘 + 要提权）。
4. **`ln -s` 在本机是"整工程复制"不是软链（更致命）**。脚本靠 `ln -s <entry> <隔离工程>/<name>` 铺隔离工程，实测生成的是**真实目录**（`ls -la` 是 `d` 不是 `l`），单次 **5.6 GB**（`.godot` + `_scratch` + `outputs` + assets 全量）。
   后果：① 每个场景**光复制就 10 分钟以上**（实测 13m32s 连第一个场景都没进断言阶段）；② 直接把系统盘撑满（历史上 `C:\$Recycle.Bin` 里 31.9 GB 的 `shellstorm-verification.*` 就是它产的）。
   报错在 `No space left on device` 与 `Permission denied` 之间交替 —— **两者都会被误读成"磁盘满/符号链接权限"**，真相是路径落错盘 + 复制。

**结论**：本机套件的正式判定不可得。用上面的「直跑 + 手跑日志门禁」组合做**定向回归**（把该功能相关的场景列出来逐条跑），并把套件留到能正常执行的环境上补跑。**不要因为套件跑不动就宣称验收通过**——要说清哪几项是用替身组合验的。

**性价比实测对照（2026-09-22）**：套件 13min+/场景（还没跑完）vs 直跑 **21s/场景**、两个场景 49s。

**直跑时的 user:// 隔离（修正上面那条"用真实 user dir"）**：只要**把 `APPDATA` 指到一个独享的纯 ASCII 目录**，Godot 的 `user://` 就整体搬过去，等价于套件的隔离，且不会再报 `Can't create shader cache folder`：
```bash
export APPDATA="I:/_ss_tmp/appdata"   # 纯 ASCII、非系统盘、独享
```
套件额外做的 `config/use_custom_user_dir` 改写只是为了让隔离目录在**真实 APPDATA 下**不串档，`APPDATA` 一换就不需要。

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

## 改了一个配置常量/开关 → 一批用例同时红（2026-09-22 实测）

场景：把 `TowerDescent3D.DEEPEST_PLANNED_FLOOR` 由 85 改成 98（塔楼只留 98F），
12 个相关场景里 3 个变红。这类红**不是 bug，是用例的「前提」被配置改掉了**。

### 归因铁律：不要用 stash，要**把那个常量改回旧值**再跑一遍

`git stash` 只能回到 HEAD，而 HEAD 里常量**已经是新值** ⇒ 两边都红，分不出谁是谁。
**临时把那个常量改回旧值**，同一条命令重跑，然后**逐条 diff ERROR 集合**：

```bash
# 注意：UNEXPECTED_ENGINE_ERROR 前缀只存在于 check_verification_log.py 的输出里，
# **scene 日志里没有** —— grep 错文件就会得到「两次都 0 条」的假结论。
grep -oE "^ERROR: .*" <场景>.after.log  | sed 's/[0-9]\{4,\}//g' | sort -u > a.txt
grep -oE "^ERROR: .*" <场景>.before.log | sed 's/[0-9]\{4,\}//g' | sort -u > b.txt
diff a.txt b.txt
```

⚠️ 归一化先行：把 `#500665691787` 这类**运行时对象 id** 和纯数字去掉（上面 `sed` 那步），
否则同一句错误每次跑都不同，diff 全是假差异。

三种判读：

- **两次集合完全相同** ⇒ **纯既有红，与本次改动毫无关系**。铁证，不必再查。
  （实测：`verify_tower_journey_polish` 的 3 条在 85/98 下逐字相同 ⇒ 与砍层无关。）
- **新集合 ⊃ 旧集合** ⇒ 多出来的是本次造成的，少的那批是既有红，两边要分开报。
- 旧为空、新非空 ⇒ 全部是本次造成的。

改完**务必还原常量**，并用 `git status --porcelain -- <文件>` 确认为空。

### 修法：让用例对常量**双向受检**，而不是改期望值

直接把期望值改成新值 = **把门禁掰弯**（旧配置下的行为再也没人看着了，改回常量的那天
用例不会自己长回来）。正确做法是让用例**实测**自己处在哪一支，两支都做**正向断言**：

1. **判据取运行时事实，不读常量**。例：查 `_floor_plan_snapshots.has(3)`（物理层 3 在不在），
   而不是读 `DEEPEST_PLANNED_FLOOR`。这样两种配置下判据都成立。
2. **两支方向相反，且都不能是「找不到就放过」**。无那一支必须断「**一条都没有**」，
   并配**哨兵**：断「无下行竖边」时同时断「98↔99 上行竖边仍在」——
   否则塔楼根本没建起来也能通过。
3. **早退必须有可判读的取证**。照本仓既有范式（`verify_tower_descent_flow` 的
   `TOWER_DESCENT_FLOW_MIGRATED`）打印 `<用例名>_SKIPPED: <原因>` + **实测关键状态**，
   再 `quit(0)`；不要静默 `return`。该目录下**没有** `expected_errors/<场景>.txt` 时，
   早退后「零 ERROR」即日志门禁通过。
4. **早退的判据必须在数据建出来之后再算**。例：`generate_through_floor_for_test(85)`
   **之后**才查计划层；放在之前会因为计划层还没建而**永远早退**（假守卫）。

> ⚠️ **假守卫必须反向对照**：把常量改回旧值跑一遍，必须**真的跑完整条用例并拿到 `*_OK`**。
> 不验这一步就可能做出「永远跳过、永远绿」的守卫 —— 比红更糟。

### 什么时候**不要**加早退

用例本身已经因为**别的原因**是红的（既有红不为空）时，**别加早退** ——
它会把那些既有红一起盖掉，信号反而丢了。原样留着，在报告里写清
「N 条既有红（列出来源）+ M 条本次配置红」，等既有红对齐了再谈早退。
（实测：`verify_arrival_gate_floor_bundle_flow` 基线就有 7 条红，全是 2026-09-21
「门一律普通门」留下的陈旧期望，故刻意不加守卫。）

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
