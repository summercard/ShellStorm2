---
name: godzilla-pet-visual-probe
description: 在沙箱里启动 Godzilla Electron 桌宠，并抓「游戏原生帧」做外观/视觉的亲眼验证与受控 A/B 对比。当问题涉及"成长外观做到哪一步了 / 某个视觉改动生效没有 / 两个变体差在哪 / 窗口是不是真透明"，且必须排除设计文档口径、只看实际渲染结果时使用。不用于改动产品代码。
agent_created: true
---

# Godzilla 桌宠视觉探针

## 何时用

问的是**实际渲染出来的样子**，不是设计文档承诺、也不是静态读代码的推断：

- "成长模块的外观现在做的怎么样了？"
- "这个视觉改动生效没有？"
- "A 和 B 两档差在哪？"
- "窗口是不是真透明？"

**铁律：改档状态必须"杀进程 → 改档文件 → 冷启动"，不要在运行中注入 localStorage。** 见下「三大坑」第 3 条。

## 环境（本机）

- 项目：`I:\工作项目\Godzilla\Godzilla\godzilla-pet`
- Electron：`<project>/node_modules/electron/dist/electron.exe`
- 可直接双击的正式版：`<project>/dist/win-unpacked/巨兽都市桌宠.exe`
- 存档：`C:\Users\zhuangmenghong\AppData\Roaming\巨兽都市桌宠\save\tv.json`
- 日志：`C:\Users\zhuangmenghong\AppData\Roaming\巨兽都市桌宠\logs\main.log`
- Python：`C:\Users\zhuangmenghong\.workbuddy\binaries\python\versions\3.13.12\python.exe`
- 现成脚本都在 `I:\工作项目\Godzilla\Godzilla\.workbuddy\`

### Bash 工具缺陷（必踩，先避开）

PortableGit shim 缺 coreutils：`dirname` / `cd` / `head` / `tail` / `wc` / `ls` / `rm` 全部 `command not found`。

**绝对不要用管道**，会 Exit 127。正确做法 —— 重定向到文件再用 Read：

```bash
"C:/Users/zhuangmenghong/.workbuddy/binaries/python/versions/3.13.12/python.exe" "<script>" > "<out>.txt" 2>&1; echo rc=$?
```

stderr 里的 `dirname: command not found` / `cd: null directory` 是 shim 噪音，**可忽略**。删临时文件 / 列目录用 Python `os.remove` / `os.listdir`。

## 七条坑（每条都烧过时间）

### 1. 起桌宠必须剥环境变量（否则秒退、日志一行不留）

沙箱环境里有 `ELECTRON_RUN_AS_NODE=1`，会跟着 `ShellExecuteW` 传给 electron.exe → 退化成纯 node → `main.js` 的 `app.setName` TypeError → 秒退。

```python
for k in ('ELECTRON_RUN_AS_NODE', 'NODE_OPTIONS'):
    os.environ.pop(k, None)
```

**判据：日志里连一行「启动」都没有 = 死在这里。** 有「启动」但没有「电视窗口已创建」= 死在窗口那步。

### 2. 必须加三条 GPU 参数

沙箱不让 Chromium 起独立 GPU 子进程，连崩 9 次后 `FATAL: GPU process isn't usable` 自杀。

```
--in-process-gpu --disable-gpu --no-sandbox
```

### 3. 改档状态：`pagehide` 会覆盖你的注入

`game.js` 在 `pagehide` 走**同步** `sendSync` 落盘。所以"注入 localStorage 再 reload"会被旧内存**覆盖回旧档**（现象：level 恒为 01，看起来注入完全没生效）。

**正确姿势**：
```
taskkill /IM electron.exe /T /F
  → 改 C:\Users\...\巨兽都市桌宠\save\tv.json（或改临时 userData 的档）
  → 冷启动
```
`tv.json` 格式 `{ version:1, payload:"<画面自己的 JSON 字符串>" }`，**payload 原样透传**，别解析重组。

⚠️ **杀进程会干掉主人正在跑的桌宠。动手前先问，或者事后明确告知并给出双击启动路径。**

**现成脚本（`shot-appearance-zoom.cjs` / `shot-hue-ab.cjs` / `shot-talent.cjs` 等）里硬编码了 `taskkill /IM electron.exe /T /F` —— 只要主人的桌宠常驻，跑一次就会把它一起杀掉。** 运行前必须先确认：

```bash
tasklist.exe /FI "IMAGENAME eq electron.exe" /FO CSV > "<out>.txt"   # 有输出=桌宠在跑
```

有输出就必须先征得同意，或改写脚本只杀自己 spawn 的 PID 树（`taskkill /PID <pid> /T /F`）。隔离 userData（`--user-data-dir=`）不会与主人的实例抢单实例锁，但桌面上会多出一个电视窗口，同样要先说明。

### 4. 沙箱起的桌宠保不住（30 秒~19 分钟被回收）

`ShellExecuteW` 能让进程树挂到 shell 侧，但沙箱仍会回收它——TerminateProcess，**rc=1、零崩溃堆栈**。
**看 rc 分死因**：`rc=1` 沙箱强杀；`rc=0` electron 自己干净退出（窗口/托盘被正常关掉）。
**要常驻得主人自己双击** `dist/win-unpacked/巨兽都市桌宠.exe`。

### 5. 沙箱内外的耗时数字不能混用

同一天、同一份构建：**不带沙箱**（escalation 批准）实测「窗口创建 → 页面就绪」**441 ms**；
**沙箱内**同条件 **1938~2074 ms**。差 4.7 倍，全是沙箱自己的代价。

**别拿沙箱里的耗时去推断真机体验**，反之亦然。`Sandbox bypassed (escalation-approved)`
是无沙箱运行的唯一信号（工具结果里会打出来），它是偶发的、不可依赖 —— 不要把结论
建立在"下次也能拿到无沙箱"上。stderr 里有 `dirname: command not found` 那串 shim 噪音
= 沙箱内；完全没有噪音 = 那次被放行了。

### 6. 判断"到底建了几个窗口"要靠 id/pid，不是数日志行

`main.js` 的「电视窗口已创建」带 `id`（BrowserWindow id）与 `pid`。
同一个进程建了两个窗口 → 两行**pid 相同、id 不同**。
反过来：「电视窗口已创建」**前面没有「启动」行** = 同进程重建窗口（second-instance
或托盘左键），**不是新进程启动** —— 这是单实例问题最省事的判据，不用抓帧。

### 7. 重启主人的桌宠：路径含中文时 explorer 那条路会**静默失效**

`环境与缺口.md` 记的姿势是 `Start-Process explorer.exe -ArgumentList '"<bat 绝对路径>"'`。**路径里有中文时它不工作**：explorer 收到被吃掉字符的路径，什么都不做 —— 没有报错、没有弹窗、日志里连一行「启动」都没有。看起来和"electron 起不来"一模一样，很容易误判成环境问题。

实测对照（同一台机器、同一次会话）：`%TEMP%` 下纯 ASCII 路径的探针 bat 经 explorer 执行 → **marker 文件立刻出现**；`I:\工作项目\...\start-godzilla.bat` 同法执行 → **零日志**。

8.3 短名救不了：`GetShortPathNameW` 对 `工作项目` 不做缩短（4 个汉字 = 8 字节，本身就在 8.3 长度内），拿到的路径仍含中文。

**解法**：在纯 ASCII 位置放一个启动器 bat，用 **GBK**（不是 UTF-8 —— cmd 按 OEM 代码页读 bat）写中文路径，再让 explorer 执行这个 ASCII 路径。

```python
# .workbuddy/_mk_launcher.py 已留档
content = '@echo off\r\ncall "' + r'I:\工作项目\Godzilla\Godzilla\godzilla-pet\start-godzilla.bat' + '"\r\n'
open(r'C:\Users\zhuangmenghong\AppData\Local\Temp\_wb_start_pet.bat', 'wb').write(content.encode('gbk'))
```

```powershell
Start-Process explorer.exe -ArgumentList '"C:\Users\zhuangmenghong\AppData\Local\Temp\_wb_start_pet.bat"'
```

这样起的实例父链挂在 explorer 上，**能常驻**（实测存活 80s+ 且持续落盘；对照：工具直接 `Start-Process electron.exe` 的实例 40~60s 被回收）。启动器留在 `%TEMP%` 可反复用，别删。

**完整重启流程**（改了 `tv/` 后让主人看到生效 —— `main.js` 直接 `loadFile` 源码、不复制不改写，所以**重启即生效，不需要重新打包**）：

1. 备份 `save/tv.json` → `outputs/tv-save-snapshot-<时间>.json`
2. 核对 PID 归属（`Get-CimInstance Win32_Process` 看 `CommandLine`/`CreationDate`；**不要从 tasklist 挑一个就杀**）
3. `taskkill /PID <主pid> /T /F` → 再列一次确认 `all_gone`
4. explorer + ASCII 启动器（见上）
5. 判据：`.workbuddy/enum-win.py <新pid>` 出 `visible=1` 且 `size=600x394`；`main.log` 有「电视窗口已创建」+「窗口已可见」
6. **逻辑修复不能只看窗口起来了** —— 要额外读存档快照验证（项目 `环境与缺口.md` 的真档探针条目）

**PowerShell 工具的两个安全策略坑**（踩过）：脚本里出现 `%VAR%` 会被当作 cmd 语法直接拦掉（用 `$env:VAR` / `Join-Path`）；`New-Object -ComObject ...`（含 `Scripting.FileSystemObject`）也被拦，需要短路径这类功能改用 Python `ctypes.windll.kernel32`。

## 抓帧：读 canvas，别用 CDP clip

**CDP `Page.captureScreenshot` 的 clip 坐标空间会被窗口缩放（0.46）重映射**，截出来是窗口外的空白。别用。

正解：连 CDP，执行 `document.querySelector('canvas').toDataURL('image/png')`，拿**原生 1280×720 帧缓冲**，写盘后在本地裁切放大。

现成脚本：`.workbuddy/shot-appearance-zoom.cjs`（多档位批量）、`.workbuddy/shot-hue-ab.cjs`（受控 A/B 单变量）。

**启动 / 单实例诊断（不用抓帧）**：`.workbuddy/probe-repeat-window.py`（模拟"双击两次"：
数建窗次数 + 看第二个进程是否留日志）、`probe-ab-startup.py`（userData 所在磁盘 × GPU 参数
2×2 对照）、`probe-save-impact.py`（空档 vs 复制真实存档）、`fix-crlf.py`（`.bat` 行尾转
CRLF，参数 `crlf` / `lf`）。这些都用 `--user-data-dir=` 隔离，验证完记得删掉那些目录。

## 读 PNG：纯 zlib 手写解码器

`.workbuddy/probe_shot.py` —— 无 Pillow 依赖，支持 RGB/RGBA。

**坑：反滤波的左邻距离必须是 `BPP`，不能硬编码 4。** 写死 4 读 RGB 图会全是花的。

配套工具：`probe-crop-zoom.py`（裁切放大）、`probe-mean.py`（均值，注意返回值是 float，print 要 `int()`）、`probe-colormatch.py` / `probe-colorhist.py`（找某颜色的像素数）、`probe-overlay-rect.py` / `probe-overlay-edges.py`（找叠色矩形边界，注意 `toDataURL` 帧是 RGBA bpp=4，先转 RGB）、`probe-diff-image.py`（两图差分）、`probe-montage.py`（拼对照图）。

## 不开 Electron：体色归因（"我的怪兽怎么变绿了"）

问"某个外观变化是哪次成长造成的"，**先别起桌宠** —— 存档 + 两张表就能定案，不用抓帧。

判据链（每环都是单一真源）：

| 环节 | 位置 | 取值 |
|---|---|---|
| 等级 | 存档 `payload.level` | — |
| 形态档 | `progression.js` `EPOCHS[].min` | 1 幼兽 / 25 亚成体 / 50 成体 / 75 完全体 / 100 灾厄体 |
| 身体底色 | `appearance.js` `FORMS[i].bodyStyle` | clean / **jade** / frost / ember / void |
| 突变覆盖 | 存档 `payload.morph.hue`（非空则优先） | crimson→ember、albino→frost、jade→jade、obsidian→clean |

变绿只有两条路径：① 升到 **25 级**（亚成体 `bodyStyle='jade'`）；
② 掷到性状突变 `t_jade`「翠化」（`progression.js`），或 `t_glacial`「冰封体」（同样写 `hue='jade'`）。
**`hue` 为空且 `mutations` 里没有 `t_*` ⇒ 只可能是等级那次**，不需要抓帧。

贴图实测（躯干 1445×979 / 头部 391×289，实心像素均值，alpha≥200）：

| 皮肤 | 躯干均值 | 主导通道 | G−B |
|---|---|---|---|
| jade | `#0f2b1c` | **G** | **+15.3** |
| clean | `#1b1a23` | B | −8.8 |
| frost | `#1a2738` | B | −17.7 |
| ember | `#361206` | R | +11.8 |
| void | `#241139` | B | −40.9 |

jade 是**唯一** G 主导的皮肤，头部同样只有它偏绿（+19.4）→ 全身一致，不是某个槽位漏换。

脚本（全只读，不碰存档）：
- `.workbuddy/probe-save-appearance.py` —— dump 存档全字段 + 外观关键字段
- `.workbuddy/probe-save-history.py` —— 目录里所有 `tv*.json` 的 level / hue / bodyStyle 对照表（**`tv-reset-*.json` 是重置前的旧档**，可做时间线）
- `.workbuddy/probe-body-color.py` —— 贴图色均值 + 主导通道 + G−B（与 `probe-mean.py` 同源，按需挑一个）

**坑**：存档是 `{version:1, payload:"<字符串>"}` 的**双层 JSON**，payload 要二次 `json.loads`；
`tv.json` 是单行 5–8KB，Read 工具按 2000 字符截断，必须用脚本解析。

## 建议流程

1. **先静态核对"声明 → 消费"**：`audit-appearance-final.py` 扫一遍，看哪些字段声明了但渲染链路不读。这能省掉一半截图。
2. **抓多档位对照帧**（如 L1 / L25 / L50 / L100），拼成 `_montage-growth.png`，**亲眼看**。
3. **对可疑点做受控 A/B**：只改一个变量（比如同 L50 只改 `hue`），差分出边界坐标。
4. **量颜色覆盖率**：设计说"随等级变色"，就全帧搜那个色值数像素——个位数像素就是"不可见"。
5. **结论分三档**：真生效 / 死声明 / 真问题（附截图与坐标证据）。

## 受控 before/after：只换一个函数

要证明"这次改动到底改了什么"，最干净的做法不是留一份旧构建，而是**在同一个工作区里只把
那一个函数换回 HEAD 版本**，抓帧，再按字节还原：

```python
old = subprocess.run(['git','show','HEAD:godzilla-pet/tv/game.js'], capture_output=True, text=True).stdout
mutant = new_src.replace(new_body, old_body)      # 只换目标函数
assert mutant != new_src and '<旧实现的特征字符串>' in mutant   # 替换必须真的发生
try:
    GAME.write_text(mutant, encoding='utf-8', newline='')
    run_probe(ROUTE_ONLY='A-main')
finally:
    GAME.write_bytes(original)                     # 按字节还原，不是按文本
    assert GAME.read_bytes() == original
```

要点：
- **按字节读、按字节还**（`read_bytes`/`write_bytes`）。文本读写会做换行翻译，还原后 git diff 就脏了。
- 断言里钉住"旧实现的特征字符串"（如 `rect(x0-8,65,w+16,4`），否则函数没抽对时会静默抓出一张假对照图。
- 跑完 `git diff --stat` 复核，确认没留下痕迹。
- 现成实现：`.workbuddy/route-before-after.py`。

### ⛔ 上面那招对 `tv/game.js` 内部的函数**无效** —— 用「冻结帧 A/B」代替

`tv/game.js` 整个包在 IIFE 里（首行 `'use strict'`、次行 `(() => {`、末行 `})();`），
里面所有函数**都不是全局的**。CDP 里 `typeof drawWeather` 返回 `undefined`，
`window.drawWeather = function(){}` 静默无效、页面照旧渲染，看起来"替换成功了"。

`tv/progression.js` 反而**是**全局的（`root.IdleProgression = api`），
所以数据层的开关可以直接改 —— 2026-09-20 验天气层就是这么做的：

```js
// 把当前章的天气换成"不画"，drawWeather 整层不渲染，其余一切不变
window.IdleProgression.CHAPTERS.forEach(c => { c.weather = { key:'clear', … }; });
```

但**光有开关还不够**（这是关键）。直接在两次抓帧之间改状态 → 差分里混进
十几秒的游戏时间：巨兽在走、镜头在推、敌人子弹在动。实测噪声地板 mean **14~18**，
信号完全淹没在里面。2026-09-20 验天气层时，这条路连续失败三次：

| 尝试 | 失败原因 |
| --- | --- |
| 替换函数为空 | 函数在 IIFE 里，不是全局的，替换不掉 |
| 跨帧差分（隔十几秒抓两帧） | 场景位移把差分撑到 mean 14+，噪声地板就有 14 |
| 单帧水平扫描找特征带 | 把**地标塔楼**当成了目标（大阪的通天阁同样是一段亮带） |

**解法：把画面冻住再比。** 杠杆在主循环 —— `tv/game.js` 末尾是
`requestAnimationFrame(frame)`。覆写它就能把帧回调**劫持**下来：

```js
window.requestAnimationFrame = function(cb){ window.__cb = cb; return 0; };  // 循环停住
// 等 ~0.9s，让上一次已经排队的回调把 __cb 交出来，然后手动驱动：
const T = performance.now();
window.__cb(T); window.__cb(T);      // 第二次才真正 dt=0（第一次把 last 对齐到 T）
```

`frame(now)` 里 `rawDt = (now-last)/1000`，喂常量 `T` → `rawDt = 0` → `dt = 0`
→ 画面**完全静止**。此后任意次 `__cb(T)` 都渲染出**逐像素相同**的一帧，
此时两张图的差异只可能来自你主动改掉的那个变量。

**必须做的三重校验，缺一个结论都不成立：**

| 校验 | 做法 | 不通过意味着 |
| --- | --- | --- |
| 冻结检验 | 同状态连驱两次，差分必须**逐像素 0** | 没冻住 → 整条结论作废 |
| 仪器校准 | 挑一个"按定义不该有任何变化"的档跑一遍，差分必须 ≈0 | 有别的东西在变 → 仪器不可信 |
| 控制带 | 划一块**被测效果不可能覆盖**的区域（如画面底部路面） | 它也有差分 → 存在全局污染（如全屏闪光） |

统计量用**中位绝对差 + ">4 的像素占比"**，不要用均值：
零散动点会拉高均值，而大面积均匀的效果会推高中位数与占比。

现成实现：`.workbuddy/_c6-frozen.cjs`（抓帧）+ `_c6-fz-diff.py`（分析）。
2026-09-20 用这套量出：大阪（clear）差分 0.02 全部像素 <4、东京云层 mean 3.30 /
21.8% 像素变化、纽约雾 mean 3.82 —— 从而定案"东京的云是纽约雾的 0.86 倍，同一量级"。

### ⛔ 暗画面的缩略图上，肉眼判读不可靠 —— 先量、后看图

同一次任务里我据一张拼图缩略图断言"云几乎看不见"，量完之后是 0.86 倍于纽约的雾；
后来又断言"更早那版像素上没有任何差异"，量完是 0.95（不是 0，只是弱到 1/4）。

**暗画面的低对比差异在缩小后的缩略图上会被压没。** 结论必须来自像素统计，
缩略图只用来确认"形状对不对"。顺序不能反：**先量，后看图。**

顺带一个可迁移的判据构造法：把"可见度"表达成 `alpha × Δluma`（混色对比度），
就能把"看得见/看不见"变成一条会失败的单元测试 —— 而且它比"色值比背景亮"这种
朴素判据强：`#2b3a55`（luma 56.6）确实比夜空顶色 `#07112f`（luma 17.4）亮，
朴素判据照样通过，但乘上 alpha .17 后对比度只有 6.7，实测可见度只有标尺的 0.25 倍。

## 抓 UI 区域，不只是抓怪兽

同一套流程也能验 HUD：抓完整 1280×720 原生帧后，用 `probe-crop-zoom.py` 裁出目标区域
（如推图轨道 `230 2 840 86`）再放 2~3 倍，`probe-montage.py` 把多档竖着拼起来。
**放大是必须的** —— 12px 的中文字在 1:1 下看不出 1 像素错位，而"进度条比节点低 21 像素"
这种缺陷恰恰就是这么来的。

想只重跑其中一档：给探针留一个 `XXX_ONLY=<tag 前缀>` 环境变量过滤，单档约 30 秒。

**UI 状态类问题要把两侧窗口同框连上**：权威状态在电视窗口那个实例里，玩家看到的却是
面板窗口那份渲染，两者可以各说各话（2026-09-18 的"按钮点下去没反应"就是面板侧已亮、
电视侧还是灰的）。只连电视窗口看不出分歧 —— 必须在一次运行里同时读两边的同一个元素。
`window.__tvHost.openPanel(key)` 可以从 CDP 直接把真面板窗口叫起来。

## 交互行为：抓帧看不出来的那一类

"按钮点下去不暗 / 点了没反应 / 状态卡住不弹回"——**抓帧一定看不出来**（帧是静止的，
故障发生在事件命中那一层）。这类问题只能用**真实输入事件**验。

两个代表性场景与各自的判据：

**① `-webkit-app-region` 命中归属（Electron frameless 窗口）**

拖动区吞掉点击时，按钮的 `:active` 拿不到 —— 表现为"按下去不暗"，而窗口会跟着手走
一小段，**两端都不报错**。光读 CSS 也验不出来（`button { no-drag }` 写着呢，
漏的是侧栏自己的 padding、组间距、`span` 小标题、装饰性旋钮）。

> ⛔ **已证伪的方法（2026-09-19 推翻，别再照抄）**：
> `elementFromPoint()` + `getComputedStyle(el)['-webkit-app-region']` 读不出拖动判定。
> 它读的是 **CSS 声明值**，而拖动判定发生在 **browser 进程的 NonClientHitTest
> （WM_NCHITTEST）** 那一层 —— 两者不是一回事。更糟的是它**方向会反**：
> `body{drag}` 时侧栏元素的 computed 值继承到 `drag`，看起来"确实被吞了"，
> 但你以为挖洞已生效的判断同样只能靠这个值，于是**假绿**。
> `.workbuddy/probe-sidebar-drag.cjs` 就是这么给出假绿的（`badCount===0` 全通过，
> 真机上两个按钮点不动）。同理 `sendInputEvent` 也是**错的**：它走的是 renderer
> 的 IPC 注入，**绕过 NonClientHitTest**，永远测不出"拖动区吞点击"。
>
> **正确判据：开真窗口，对锚点逐个问系统 `WM_NCHITTEST`。**
> Chromium 在那里返回 `HTCAPTION`（算拖窗口）还是 `HTCLIENT`（算点页面）——
> 这就是拖动判定的真源，不需要派发任何输入。
> 现成脚本：`.workbuddy/probe-region-run.py`（起窗口 + 逐锚点问 + 打印判定），
> `.workbuddy/probe-region-points.py`（锚点表）。

**实测得到的形状规则（推翻了"大祖先 drag + 子级挖洞"这个直觉）**：

真机逐锚点扫描四种形状，只有一种满足"侧栏可点 + 画面能拖"：

| 形状 | 侧栏按钮 | 画面 / 台标 / 页脚 | 判定 |
| --- | --- | --- | --- |
| `body{drag}` + `.shell{drag}` + 侧栏 `no-drag` | HTCAPTION ✗ | HTCAPTION ✓ | 不满足 |
| 去掉 `body`，留 `.shell{drag}` | HTCAPTION ✗ | HTCAPTION ✓ | 不满足 |
| `body{no-drag}` + 三块 `drag` | HTCLIENT ✓ | 也全 HTCLIENT ✗ | 不满足 |
| **`body` / `.shell` 留空，`drag` 只落三块** | **HTCLIENT ✓** | **HTCAPTION ✓** | **采用** |

结论：**`body` 上一旦出现任何声明，整窗判定就退化成"全听 body 的"** ——
`body{drag}` 时挖洞无效，`body{no-drag}` 时连子级的 `drag` 也一起失效。
另外 `.shell{drag}` 时，作为它**兄弟**的 `.tv-sidebar` 同样挡不住。
所以拖动区只能落在**互不包含**的几块上，且必须显式断言 `body`/`.shell` 声明为空。

**仪器校准的教训**：矩阵探针早期给出"5 种配置全 0/9 可点"，看着像"全都坏"，
其实是探针自己的坑。校准办法是拿一个**已知答案**的合成页（body=drag + 一块
no-drag 绿地）先跑一遍，确认仪器在能出绿的地方确实出绿 ——
`.workbuddy/probe-nchit-control.cjs` / `.py` 就是这个用途。

**锁屏时真实鼠标输入不可用**：`SendInput` 在会话未激活时不被派发，
`GetForegroundWindow()` 返回 0，真鼠标测试会全 FAIL 但**不可信**。
`WM_NCHITTEST` 不需要输入派发，是锁屏下唯一可靠的判据。
两者已在可交互环境下对过账，结论一致 —— 所以现在一律以 `WM_NCHITTEST` 为准。

**真鼠标点击的正确做法（2026-09-19 打通，三件套）**

想拿到"主人的手点下去到底会怎样"这个终局判据，必须**同时**满足三件事，
少一件都会得到假结果：

| 件 | 做法 | 错了会怎样 |
| --- | --- | --- |
| ① 输入走 OS | Python `ctypes` 调 `SetCursorPos` + `user32.mouse_event(LEFTDOWN/UP)` | 用 `sendInputEvent` → 绕过 NonClientHitTest，**永远假绿** |
| ② 坐标由窗口侧算 | Electron 里 `getBoundingClientRect()` 取中心，**在窗口侧**换算成屏幕坐标：`bounds.x + cssX × zoomFactor`，直接把屏幕坐标打印出来 | 外部脚本自己换算，**漏乘 zoom** 就整条偏掉（我漏过一次：点到了「巨兽」小标题上，表现为"按钮没反应"）；靠截图目测也会偏十几像素 |
| ③ 判据直接读 DOM | Electron 侧 `executeJavaScript` 读状态；再加一个**只在探针里挂**的监听器数 click（`document.addEventListener('click', …, true)` + 每个按钮各一个计数器） | 读 `#management.hidden` 会误判 —— 裸探针窗口**没有宿主**（无 `tv-preload` 桥），点遥控器本来就开不上面板（面板由宿主 `window.__tvHost.openPanel` 开）。**"面板没开"≠"点击没收到"** |

现成实现：`.workbuddy/probe-realclick-live.cjs`（起真尺寸窗口 + 注入真 CSS + 打印屏幕坐标 + 打印探针计数）
+ `.workbuddy/probe-realclick-live-run.py`（驱动真鼠标点击）。

**在运行中的真实实例上验（最硬的一档）**：
- `.workbuddy/verify-live-pet.py <pid>` —— 枚举该 pid 的窗口拿 rect，按 tv 版面比例算锚点，
  逐个问 `WM_NCHITTEST`；桌面可交互时再用真鼠标点遥控器、看面板窗口是否新生。
- `.workbuddy/verify-live-click.py <pid>` —— 沿侧栏竖向**扫描**真鼠标点击（看面板窗口有没有新生），
  绕开"锚点算不准"这个坑。实测能扫出按钮的完整连续命中区间。
- ⚠️ 收尾记得 `_check-windows.py <pid>` 看有没有**被我点开的残留面板窗口**，有就用
  `_close-stray-panel.py` 发 `WM_CLOSE` 关掉（只发消息给那个句柄，不动进程、不动电视窗口）。
  别给主人留一个凭空多出来的窗口。

### ⛔ 屏幕 BitBlt 抓不到 Electron 透明窗口的实时帧

想用"点击前后截图对比"验换台这类**不开新窗口**的操作 —— 这条路在这个项目上不通：
`user32.GetDC(0)` + `gdi32.BitBlt` 抓电视窗口矩形，**连续两次抓图逐像素 100% 相同**
（画面明明是活的）。窗口可见、在前台、光标下顶层就是它，都没用。
判据从"全屏差异"到"单像素取样"全都读到冻结帧。

所以别再往这个方向烧时间：**要验不开窗口的操作，就读 DOM 状态**（上一节三件套的第 ③ 件）。

顺带两条读像素的坑（写这类脚本时踩过）：
- `GetDIBits` 32bpp 出来是 **BGRA**。`xxx.hex()` 看到的是 `#BBGGRR` ——
  把 `432b15` 读成"暖棕"就错了，它其实是 `#152b43` 深蓝（电视按钮底色）。
  读颜色前先确认字节序，否则会得出"抓到的不是这个窗口"的错误结论。
- 多显示器时 `GetDC(0)` 只覆盖主屏。用 `GetSystemMetrics(SM_XVIRTUALSCREEN/…)`
  先确认窗口在不在主屏内。
- 那个 `Exception in thread Thread-2 (_readerthread) UnicodeDecodeError` 噪音：
  Electron 的 GPU 报错是 **GBK**，混进 UTF-8 流会炸。Popen 别用 `text=True`，
  读 bytes 再 `decode('utf-8', errors='replace')`。不影响结果，但会污染日志。

**② 双态按钮能不能亮回去 / 暗下去**

连点 N 次同一个按钮，每次松开后读类名与文案，**第 1 次与第 N 次的状态都必须回到
预期**。只验一次"点亮了"会漏掉"卡在点亮态出不来"这半边 —— 而主人报的正是后一半。

现成实现（2026-09-19）：`probe-sidebar-drag.cjs` 连点换台 7 次，覆盖 6 个频道后
回到直播，断言 `cls` 里 `.on` 出现又消失。

## 写新探针时的进程纪律

**唯一允许的杀法**：把自己 spawn 出来的那棵树收掉。

```js
const proc = spawn(EXE, [...args, '--user-data-dir=' + TMP], { detached: true, stdio: ['ignore', out, out] });
proc.unref();
// 收尾只杀自己这棵树
spawnSync('taskkill', ['/PID', String(proc.pid), '/T', '/F'], { stdio: 'ignore' });
```

### ⛔ 血本：不要从 tasklist 里挑一个 PID 手杀

`.workbuddy/` 里的老脚本（`shot-appearance-zoom.cjs` 等）硬编码 `taskkill /IM electron.exe /T /F`，
主人桌宠常驻时跑一次就连带杀掉 —— 这是已知的。**但更隐蔽的坑是"手动挑 PID"**：

2026-09-18 为了清一个"看起来像自己探针"的残留进程，直接
`taskkill /PID <从 tasklist 读来的号> /T /F`，**没有核验归属** —— 那个 PID 其实是
主人正开着的观测面板窗口的渲染进程（父进程 = 主人桌宠的主进程）。结果主人的面板窗口
变成一块白板，只能重启桌宠。（电视窗口没受影响，存档无损失。）

要动手之前必须核验：

```powershell
Get-CimInstance Win32_Process -Filter "Name='electron.exe'" |
  Select-Object ProcessId,ParentProcessId,CommandLine
```

- **父进程 PID 必须等于你 spawn 出来的那个**，否则一概不碰；
- 从 Node 里调 powershell 拿进程表是可行的（`spawnSync('powershell.exe', ['-NoProfile','-Command', ...])`
  能正常拿到 stdout）；被安全策略挡住的只是 Bash 工具里的 `wmic.exe`；
- 收尾一律走 `killOwn()`，不要"顺手再清一个"。

`--user-data-dir=` 隔离开的单实例锁与主人实例不冲突，可以并存 —— 但**并存不等于可以乱杀**。

### 两个会让人白跑半小时的 API 细节

- **面板窗口与电视窗口的 URL 完全相同**（`main.js` 用 `loadFile(ORIGINAL_GAME)`，没有 query）。
  CDP 里区分只能读页面自己的标：`window.__panelMode === true` 是面板，否则是电视。
  按 URL 过滤 `panel=1` 会永远找不到面板。
- **`pages()` 必须兜住 fetch 的 ECONNREFUSED**：端口没起来是常态（Electron 引导要几百毫秒
  到几秒），一个未捕获的 fetch 异常会让脚本在启动瞬间就崩，日志里只剩一行 `fetch failed`。

## 不要做的事

- 不要用探针数字替代看图。数字只用来**定位**，最后必须 Read PNG 亲眼确认。
- 不要把设计文档的承诺当成现状。设计公式和实际渲染是两套，必须都查 ——
  本项目已抓到过两类：① 同一条曲线在两个文件里各有一份（两个上限谁也不认谁）；
  ② 名字相近的两个上限被当成一件事（体型系数上限 vs 屏幕表观上限，
  前者调大不会让画面变大，后者才是渲染安全线）。
- 不要在审查任务里顺手改产品代码。审查就是审查。
