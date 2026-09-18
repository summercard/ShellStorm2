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

### 4. 沙箱起的桌宠保不住（30 秒~19 分钟被回收）

`ShellExecuteW` 能让进程树挂到 shell 侧，但沙箱仍会回收它——TerminateProcess，**rc=1、零崩溃堆栈**。
**看 rc 分死因**：`rc=1` 沙箱强杀；`rc=0` electron 自己干净退出（窗口/托盘被正常关掉）。
**要常驻得主人自己双击** `dist/win-unpacked/巨兽都市桌宠.exe`。

## 抓帧：读 canvas，别用 CDP clip

**CDP `Page.captureScreenshot` 的 clip 坐标空间会被窗口缩放（0.46）重映射**，截出来是窗口外的空白。别用。

正解：连 CDP，执行 `document.querySelector('canvas').toDataURL('image/png')`，拿**原生 1280×720 帧缓冲**，写盘后在本地裁切放大。

现成脚本：`.workbuddy/shot-appearance-zoom.cjs`（多档位批量）、`.workbuddy/shot-hue-ab.cjs`（受控 A/B 单变量）。

## 读 PNG：纯 zlib 手写解码器

`.workbuddy/probe_shot.py` —— 无 Pillow 依赖，支持 RGB/RGBA。

**坑：反滤波的左邻距离必须是 `BPP`，不能硬编码 4。** 写死 4 读 RGB 图会全是花的。

配套工具：`probe-crop-zoom.py`（裁切放大）、`probe-mean.py`（均值，注意返回值是 float，print 要 `int()`）、`probe-colormatch.py` / `probe-colorhist.py`（找某颜色的像素数）、`probe-overlay-rect.py` / `probe-overlay-edges.py`（找叠色矩形边界，注意 `toDataURL` 帧是 RGBA bpp=4，先转 RGB）、`probe-diff-image.py`（两图差分）、`probe-montage.py`（拼对照图）。

## 建议流程

1. **先静态核对"声明 → 消费"**：`audit-appearance-final.py` 扫一遍，看哪些字段声明了但渲染链路不读。这能省掉一半截图。
2. **抓多档位对照帧**（如 L1 / L25 / L50 / L100），拼成 `_montage-growth.png`，**亲眼看**。
3. **对可疑点做受控 A/B**：只改一个变量（比如同 L50 只改 `hue`），差分出边界坐标。
4. **量颜色覆盖率**：设计说"随等级变色"，就全帧搜那个色值数像素——个位数像素就是"不可见"。
5. **结论分三档**：真生效 / 死声明 / 真问题（附截图与坐标证据）。

## 不要做的事

- 不要用探针数字替代看图。数字只用来**定位**，最后必须 Read PNG 亲眼确认。
- 不要把设计文档的承诺当成现状。`globalScaleFor` 封顶 1.80 但渲染调用 0 次——**测试守着它，所以永远是绿的**。设计公式和实际渲染是两套，必须都查。
- 不要在审查任务里顺手改产品代码。审查就是审查。
