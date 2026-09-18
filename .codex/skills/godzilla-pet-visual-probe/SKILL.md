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

## 三大坑（每个都烧过时间）

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
- 不要把设计文档的承诺当成现状。`globalScaleFor` 封顶 1.80 但渲染调用 0 次——**测试守着它，所以永远是绿的**。设计公式和实际渲染是两套，必须都查。
- 不要在审查任务里顺手改产品代码。审查就是审查。
