---
name: windows-cli-tool-provisioning
description: 在 Windows 上让某个命令行工具（Godot、Blender、FFmpeg、任意 exe）变成"脚本里直接敲名字就能用"，并定位装在非标准位置的已安装工具。当遇到「which X 找不到但这个软件我装了」「工具装了但不在 PATH」「脚本里的 X 命令报 not found」「给项目/CI 补齐命令行依赖」时使用。含「定位正在运行的实例」/注册表 MUICache 两条定位法、~/bin 垫片、stdout 形态（`_console` 变体到底要不要）与 CRLF 行尾坑。
agent_created: true
---

# Windows：让命令行工具"敲名字就能用"

## 0. 先做这个判断（别急着改调用方）

找到缺口后，**优先顺序**是：

1. **建垫片**（推荐）—— 不动任何既有命令、不动 DoD/CI 脚本。调用方仍写 `godot --headless ...`。
2. 改 PATH —— 影响面大（全局），且可能需要重启终端/改注册表。
3. 改调用方脚本 —— **最差**。会让文档、CI、同事的脚本全部分叉，且一旦版本变了要改多处。

**原则：缺的是"名字解析"，就只补名字解析。**

## 1. 定位：软件装了但找不到

按这个顺序找，**不要一上来就全盘 find**（慢且常常超时）：

| 顺序 | 方法 |
|---|---|
| 1 | `which X` / `where X`（cmd）—— 确认真的不在 PATH |
| 2 | **若该工具的窗口正开着：`Get-Process X \| Select-Object -First 1 -Expand Path`** —— 一次命中完整路径，最快（见下） |
| 3 | 常见位置：`/c/Program Files/X`、`/c/Program Files (x86)/X`、`~/X`、各盘根 `/c/X`、`/d/X`… |
| 4 | 浅层 `find <盘> -maxdepth 3 -iname "X*"` |
| 5 | **注册表 MUICache**（见下）—— 覆盖"装过但没在跑"的情况 |

### 正在运行的实例：比 MUICache 更快

**用户说"我把它开起来了 / 我已经打开了"时，第一招就是这个** —— 别去翻注册表。PowerShell 的 stdout 在本机可能抓不到，
所以**把结果落盘再读**：

```powershell
$lines = @()
$p = Get-Process X -ErrorAction SilentlyContinue | Select-Object -First 1
if ($p) { $lines += "RUNNING: " + $p.Path } else { $lines += "RUNNING: (none)" }
# 顺便验证候选路径与同目录下的其他 exe
Get-ChildItem "<猜测的目录>" -Recurse -Filter "X*.exe" -ErrorAction SilentlyContinue |
  ForEach-Object { $lines += "EXE: " + $_.FullName }
Set-Content "$env:TEMP\wb_probe.txt" $lines -Encoding UTF8
```

然后用 Read/`grep` 读 `$env:TEMP\wb_probe.txt`。

> **坑**：`Get-Process | Where-Object { $_.Name -like '*x*' }` 有时返回空（进程名与直觉不同，或过滤在管道里失效）。
> 稳妥做法是**先把全部进程 dump 到文件**，再在外面 grep —— 实测这样才找到了 Blender（进程名就是 `blender`，
> 而 `-like` 过滤当时什么也没返回）。

### MUICache：Windows 记录"被执行过的 exe 的完整路径"

GUI 启动过的 exe 会在这里留一条：

```
HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache
```

找法（PowerShell，输出落盘后再读——直接 stdout 可能抓不到）：

```powershell
$k='HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'
(Get-Item $k).Property | Where-Object { $_ -like '*X*' } |
  Out-File -Encoding utf8 $env:TEMP\probe.txt
```

同理可查 `%APPDATA%\Microsoft\Windows\Recent` 的快捷方式。

> `C:\Windows\Prefetch\X*.pf` 只能证明"跑过"，**不含路径**，但能确认**版本号**
> （文件名形如 `GODOT_V4.6.3-STABLE_WIN64.EXE-<hash>.pf`）。

## 2. 建垫片

先确认一个**已在 PATH 上**且可写的目录。常见候选：

- `~/bin`（Git Bash 的 PATH 里常含 `C:\Users\<user>\bin`，**即使目录不存在** —— 那就新建）
- `~/AppData/Roaming/npm`（装了 npm 就有）

验证：`echo "$PATH" | tr ':' '\n' | grep -i "<user>/bin"`

然后建**两个**文件：

`~/bin/<tool>`（sh 用，**LF** 行尾）：
```sh
#!/bin/sh
exec "I:/path/to/Tool_console.exe" "$@"
```

`~/bin/<tool>.cmd`（cmd / PowerShell 用，**必须 CRLF**）：
```
@echo off
"I:\path\to\Tool_console.exe" %*
```

```bash
chmod +x ~/bin/<tool>
```

### 坑 1：`_console` 变体 —— **要先试，别直接假定必需**

很多 Windows 程序分**两个 exe**：GUI 版 + `_console.exe` 包装版。**但"必须用 `_console.exe`"是错的**，
真正的判据是 **stdout 是"附着到控制台"还是"被管道/重定向捕获"**：

| 场景 | 结果 |
|---|---|
| GUI 子系统 exe **附着控制台**（用户直接在 cmd 里手敲） | stdout **丢失**，看起来像"跑成功但没结果" |
| GUI 子系统 exe **被管道/重定向捕获**（`... \| grep`、`$(...)`、CI、bash 工具调用） | stdout **正常** ✅ |

所以：

- **bash / CI 调用（我们的主场景）通常不需要 `_console.exe`** —— 先直接指向 GUI exe 试一次，**跑通就用**。
- 只有"用户手敲时必须看到输出"才需要 `_console.exe`。
- **正反两个实例**：Godot 有 `_console.exe` 包装版（用它更保险）；
  **Blender 没有 console 变体，`blender.exe` 在管道下输出完全正常** —— 若照抄"必须 `_console`"的教条，
  会去找一个根本不存在的文件。

**动作**：拿到候选路径后，**先裸跑一次验证形态**，再决定用哪个变体：
```bash
"<候选 exe>" --version 2>&1 | head -3
```

### 坑 2：目录名可能本身以 `.exe` 结尾

例如解压 Godot 会得到 `Godot_v4.6.3-stable_win64.exe\` 这个**目录**，里面才是真的 exe。
肉眼看文件列表极易误判为"就是个文件"，从而以为没装。**用 `ls -d` / `find -type d` 确认类型。**

### 坑 3：`.cmd` / `.bat` 必须 CRLF

写文件工具通常产出 LF。写完转一次，并断言没有 `\r`（避免 CRCRLF）：

```python
b = open(p,'rb').read()
assert b'\r' not in b
open(p,'wb').write(b.replace(b'\n', b'\r\n'))
```

`sh` 脚本保持 LF，不要转。

### 坑 4：垫片要写"真身路径"，并留下重建线索

把**绝对路径 + 一个可复现的定位依据**写进注释（目录名、是否 `_console` 变体、建立日期）。
将来垫片丢了，看注释就能重建 —— 否则下次又得从头找一遍。

```sh
#!/bin/sh
# <tool> 启动垫片 —— 让 `<tool> --xxx ...` 直接可用（PATH 已含 ~/bin）
# 真身：<绝对路径>   ← 重建靠这一行
exec "<绝对路径>" "$@"
```

## 3. 验证（必须在新 shell 里）

```bash
bash -lc 'which <tool> && <tool> --version'
```

- `which` 为空 ⇒ 那个目录不在 PATH，或没 `chmod +x`。
- 能跑但**没有输出** ⇒ 可能是 stdout 形态问题（坑 1）——注意**要在管道里测**（`| head`），
  因为"附着控制台"与"被管道捕获"结果不同。
- 用**新 shell**（`bash -lc`）验证，别在当前 shell —— 当前 shell 的 PATH 可能是旧的。
- **最能说明问题的是"照文档原样敲一遍"**：如果文档里写 `blender --background --python x.py -- --out y`，
  就用**裸命令 + 完全相同的参数**跑一次，而不是用绝对路径跑个 `--version` 就宣布可用。

## 4. 顺带：确认"版本要求"是不是真的硬要求

**在报"版本不符/缺依赖"之前，先去代码里找有没有东西真的读这个版本号。**

- `grep` 审计脚本、CI 配置、测试判据里有没有版本比较
- 看 DoD / 验收命令是否只是"能跑起来"而不是"版本 ≥ X"
- 文档里写的"目标版本"常常只是**上一台机器的事实陈述**，不是门禁

> 实例：某项目文档通篇写"引擎 4.7.x"，实际审计脚本里一行版本检查都没有，
> 任务 DoD 只要求"工程能打开无导入错误"。4.6.3 实测完全够用 ——
> 差点因为照抄文档而误报一条不存在的硬阻断。

若确认口径要改，**同步所有出现处 + 记一条裁定**（否则下次又会有人按旧值报阻断）。

## 5. 反模式

| 反模式 | 问题 |
|---|---|
| 直接改调用方脚本的路径 | 文档/CI/同事全分叉；工具升级时到处改 |
| 只建 `~/bin/<tool>` 不建 `.cmd` | 从 cmd/PowerShell 调用失败 |
| 用 GUI 变体做 CLI 包装 | **不一定错**：只要调用侧是管道/重定向就行。别把"必须 `_console`"当教条（坑 1） |
| 把工具拷进项目目录提交 | 大二进制进 git，且平台绑定 |
| 用软链接 | Windows 需开发者模式/管理员，且 git 存成文本 |
| 没验证就宣布可用 | 新 shell 里 `which` 一下就知道了 |
