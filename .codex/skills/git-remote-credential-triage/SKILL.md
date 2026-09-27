---
name: git-remote-credential-triage
description: 诊断并修复「git/Fork/IDE 里 pull push 反复索要账号密码」的问题——分清是远程地址走了 HTTPS、凭据助手被配置清空、SSH 密钥没生效，还是 known_hosts 损坏。当遇到「绑了 ssh 还要输密码」「git 每次都问用户名密码」「Fork 弹窗要密码」「credential.helper 不生效」「凭据管理器里存着却还要输」「hostfile_replace_entries Permission denied」时使用。含远程协议普查、helper 空值陷阱、逐仓库 SSH 可达性验证与带备份回滚的批量切换脚本。
agent_created: true
---

# git 反复索要密码：分诊与修复

## 0. 先分清是「哪一种密码」

用户说「要输密码」，可能是三件完全不同的事，**先问清或先看症状**：

| 现象 | 真实含义 | 走哪条线 |
|---|---|---|
| 弹「Username / Password」 | HTTPS 远程 + 没有可用凭据助手 | §2 + §3 |
| 弹「Enter passphrase for key」 | SSH 私钥有密码短语 | §4 |
| 弹「Are you sure you want to continue connecting」 | known_hosts 里没这台主机 | §5 |
| 弹「Sign in / 浏览器授权」 | GCM 在走 OAuth | §3（正常行为） |

**最高频的误判**：用户「绑好了 SSH key」却仍被要密码 —— 十有八九**远程地址压根是 HTTPS**，SSH 密钥根本不参与 HTTPS 认证。**绑多少密钥都没用。**

## 1. 先普查：远程地址到底是 SSH 还是 HTTPS

不要只查用户说的那一个仓库，**全量扫一遍**，因为往往只有少数几个是 SSH。

```bash
# 单仓库
git -C <repo> remote -v

# 批量：把 <仓库根目录列表> 喂进去
for d in <repo1> <repo2>; do printf "%-40s " "$d"; git -C "$d" remote get-url origin 2>/dev/null; done
```

判定规则：

- `git@host:owner/repo.git` 或 `ssh://...` → SSH，密钥参与
- `https://host/owner/repo.git` → HTTPS，**走的是账密/PAT，与 SSH key 无关**（← 绝大多数问题在这）
- `https://user:ghp_xxx@host/...` → **URL 里内嵌明文 Token**，先当安全事故处理（§6）

## 2. 凭据助手：最隐蔽的坑是「空值清空」

### 陷阱

git 的规则：**高优先级配置里的 `credential.helper=`（空字符串）会清空此前累积的 helper 列表。**

典型受损现场：

```ini
# ~/.gitconfig（全局层）
[credential]
	useHttpPath = true
	helper =            # ← 空值！把系统层的 manager 整个抹掉
[credential "helperselector"]
	selected = manager  # ← 只是残留的选择记录，不提供能力
```

而系统层其实是好的：

```ini
# C:\Program Files\Git\etc\gitconfig
[credential]
	helper = manager
```

结果：**GCM 装得好好的、Windows 凭据管理器里也存着一堆凭据，git 却一条都取不到，每次都问。**

### 诊断

```bash
git config --show-origin --get-all credential.helper   # 看到空值来源就中招
git config --get credential.helper                      # 返回空 = 实际无助手
```

**务必同时测 GUI 客户端自带的那份 git**（见 §7），它们用的是独立配置。

### 修复

```bash
"C:/Program Files/Git/cmd/git.exe" config --global --unset-all credential.helper
```

**保留** `[credential "helperselector"] selected` 那行（只是记录，无害）。

### 正向验证（关键：不要打印出密钥）

```bash
out=$(printf 'protocol=https\nhost=github.com\npath=owner/repo\n\n' \
      | GIT_TERMINAL_PROMPT=0 git credential fill 2>&1)
echo "$out" | awk -F= '/^username=/{print "username="$2} /^password=/{print "password 命中，长度 "length($2)}'
```

⚠️ **绝对不要直接 `echo "$out"`** —— `git credential fill` 会把 PAT 明文吐到终端，会泄漏进对话记录/日志。只打印字段名与长度。

## 3. 修正远程协议：切 SSH 前必须逐仓库验证

**不要无脑批量替换前缀后一把梭。** 同一个账号下的不同仓库权限可能不同（私有 + 无协作者权限的会切完就废）。

正确做法：**先 `git ls-remote` 只读验证，通过才改**。

```bash
test_ssh() {
  GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10" \
  GIT_TERMINAL_PROMPT=0 git ls-remote "$1" HEAD >/dev/null 2>&1
}
test_ssh git@github.com:owner/repo.git && echo OK || echo NO
```

`BatchMode=yes` + `GIT_TERMINAL_PROMPT=0` 的作用：**不通过就直接失败，绝不挂起等输入**。批量脚本必须带这两个参数，否则会卡死。

改地址：

```bash
git -C <repo> remote set-url origin git@github.com:owner/repo.git
```

### 带备份与回滚的批量脚本

见 `scripts/fix_git_remotes.py`（默认干跑，`--apply` 才动手；先备份每份 `.git/config` 与 `~/.gitconfig`，生成 `manifest.json` 与 `restore.py`）。

## 4. SSH 侧确认（切 SSH 前先保证它真的通）

```bash
ssh -T git@github.com      # 期望: Hi <用户名>! You've successfully authenticated
ssh -T git@<内网GitLab>     # 期望: Welcome to GitLab, @<用户名>!
```

**想知道实际用的是哪把钥匙**（多把 key 时非常有用）：

```bash
ssh -v -T git@github.com 2>&1 | grep -iE "Offering|Server accepts|Authenticated"
```

注意 ssh 按 `~/.ssh/config`（若不存在则按默认顺序 id_rsa → id_ecdsa → id_ed25519）依次试探，**第一个被接受的才是生效的那把**。

内网 GitLab 的 `Welcome to GitLab, @username!` 会直接告诉你账户名，比猜快得多。

## 5. `hostfile_replace_entries ... Permission denied`

现象：每次 ssh 都打印

```
hostfile_replace_entries: unlink /path/.ssh/known_hosts.old: Permission denied
update_known_hosts: hostfile_replace_entries failed for /path/.ssh/known_hosts: Permission denied
```

**通常不是 ACL 问题。** 排查顺序：

1. 看 ACL 与属性：`icacls <path>`、`attrib <path>` —— 若 Full control 齐全、属性只有 `A`，**别改 ACL**
2. 确认目录可创建可删除、无残留 ssh 进程占用
3. **直接删掉残留的 `known_hosts.old`**：

```bash
rm -f ~/.ssh/known_hosts.old && ssh -T git@github.com   # 报错应消失
```

危害等级低（已有主机记录仍能用），但会导致新主机 key 无法写入、每次都要手工确认 host key。

## 6. 顺带必查：URL 里内嵌的明文凭据

扫描模式：`ghp_` / `://user:pass@`

```bash
# 遍历所有仓库 .git/config + 全局配置
grep -rn "ghp_" ~/.gitconfig ~/.git-credentials <repo>/.git/config
```

发现后：
- 本地：`git remote set-url origin <干净地址>`（切 SSH 时顺手就清了）
- **远端吊销必须让用户本人去平台操作** —— 本地清理不能阻止已泄漏的 Token 被使用。要在结论里明确提示吊销。

## 7. GUI 客户端（Fork / Tower / SourceTree）特有注意

GUI 常**自带一份 PortableGit 和自己的配置**，与系统 git 完全独立。**只查系统 git 会误判。**

以 Fork 为例（Windows）：

| 用途 | 路径 |
|---|---|
| 自带 git | `%LOCALAPPDATA%\Fork\gitInstance\<版本>\` |
| 其系统级配置 | `...\gitInstance\<版本>\etc\gitconfig` |
| 仓库清单 | `%LOCALAPPDATA%\ForkData\repositories.toml`（`path` 字段） |

验证 GUI 那份 git 的生效配置：

```bash
FGIT="$LOCALAPPDATA/Fork/gitInstance/<版本>/mingw64/bin/git.exe"
HOME=/c/Users/<user> "$FGIT" config --show-origin --get-all credential.helper
```

⚠️ **`repositories.toml` 里的 `opened` 时间戳可能被批量刷成同一个值**，不能用来判断「用户最近在用哪个仓库」。

## 8. 平台差异备忘

| 事项 | Windows | 备注 |
|---|---|---|
| 凭据存储 | Windows 凭据管理器 | `cmdkey /list` 查看；bash 里必须加 `MSYS2_ARG_CONV_EXCL="*"`，否则 `/list` 被当路径转换、报「命令行参数不正确」 |
| 凭据助手 | Git Credential Manager (`helper = manager`) | 二进制 `mingw64/bin/git-credential-manager.exe` |
| GitHub 推送 | **只接受 SSH key 或 PAT，不接受账户密码** | 所以 HTTPS 路线必须有 PAT，切 SSH 更省事 |

## 9. 验收标准（必须在 `GIT_TERMINAL_PROMPT=0` 下通过）

```bash
export GIT_TERMINAL_PROMPT=0
git -C <repo> ls-remote origin HEAD    # 成功 = 确实没有任何弹窗
```

只在交互式终端里「看起来没问」不算通过 —— 那可能是凭据刚好缓存着。
