---
name: sofunny-resource-sharing
version: 1.5.1
description: "把本地文件发布成内网可分享链接：HTML / 静态站点、以及 APK、ZIP、安装包等资源包。生成内网域名链接供他人访问或下载，支持原地更新（同一链接始终指向最新内容）。对外统一 HTTPS：公开域名走 443 与自动续期的受信证书，明文 80 端口只做跳转。自动检测环境并申领 token（用户只下达发布/更新/删除命令，无需配置地址与 token）。提供每人独立 token 的归属隔离、并发隔离与原子部署。运行状态保存在 skill 的 state/ 目录，跨会话可见可管，并自动接管旧技能 sofunny-publish-html 的历史站点。本仓库只有客户端发布链路；服务器（部署 daemon、静态服务、HTTPS 证书、管理后台）在 sofunny-resource-sharing-server 仓库。"
---

# sofunny-resource-sharing

把本地内容发布成内网可分享 URL。静态服务统一使用固定端口 `41739`（部署 API 为 `41740`，明文，仅内网 IP 直连），对外域名为 `https://sofunny-resource-sharing.hnfunny.com`：443 提供内容，80 端口只做 301 跳转。单文件发布生成 `/<site-id>.<后缀>` 短链（HTML 页面或安装包直链），后缀是复合后缀时整体保留（如 `.tar.gz`）；目录发布生成 `/<site-id>/` 路径；脚本负责快照、打包、并发锁与原子部署。

**本 skill 只支持服务器部署（API 免 SSH），不支持本地预览。**

本仓库是**客户端**：只做打包与上传，服务器代码在 [sofunny-resource-sharing-server](https://git.sofunny.io/skill-libs/sofunny-resource-sharing-server)。安装、升级、证书、token 管理都在那个仓库，本 skill 里没有也不执行服务器代码。

## 安装与更新（含旧技能退场）

本仓库是 GitLab public 仓库，SSH 与 HTTPS 均可直接拉取：

```bash
npx skills add git@git.sofunny.io:skill-libs/sofunny-resource-sharing.git -g -y
```

安装到 `~/.agents/skills/sofunny-resource-sharing`，并软链到已检测到的各 Agent 目录。更新用 `npx skills update sofunny-resource-sharing -g -y`，更新后需重启 Agent 会话。**更新只换客户端**；服务器 daemon 的升级在服务端仓库执行（`python3 scripts/server.py upgrade`），客户端不做也不碰。

用户若还装着旧技能 `sofunny-publish-html`，按顺序执行三步，**不要跳步**：

```bash
# 1) 安装本技能
npx skills add git@git.sofunny.io:skill-libs/sofunny-resource-sharing.git -g -y
# 2) 先让本技能跑一次，接管旧技能的 state（token 与发布记录）
python3 ~/.agents/skills/sofunny-resource-sharing/scripts/publish.py status
#    期望看到「已接管旧技能的运行状态（token 配置、N 条发布记录）」与历史站点列表
# 3) 确认历史站点可见后，再卸载旧技能
npx skills remove sofunny-publish-html -g -y
```

第 2 步必须在第 3 步之前：旧技能的 token 与发布记录存在它自己的 `state/` 里，先卸载就一起删掉了——具名 token 用户会失去历史站点管理权，`--update` 也会失效。第 3 步若报 `No matching skills found`（旧技能是手工软链或拷贝安装的，安装器扫描不到软链），直接删链接即可，**不要删链接指向的目录**：

```bash
rm -f ~/.claude/skills/sofunny-publish-html ~/.codex/skills/sofunny-publish-html
```

若这两处之外还存在旧技能目录（例如 `~/.agents/skills/sofunny-publish-html`），说明安装器漏掉了它：先确认第 2 步的接管已完成，再删除该目录，并留意它内部 `state/` 是否还有未接管的记录。

## 与旧技能 sofunny-publish-html 的关系

本 skill 由 `sofunny-publish-html` 演进而来，替代它继续维护。两者共用**同一套服务器**（同一 daemon、同一 `sites/` 存储、同一 token 库），因此：

- 旧技能的站点、token、链接全部继续有效，**无需重新发布**。
- 本 skill 首次运行时自动接管旧技能的 `state/`（复用 token 配置、导入发布记录），之后 `status`、`--update`、`remove-server` 都能管理历史站点。
- 对外域名从 `sofunny-html.hnfunny.com` 过渡到 `sofunny-resource-sharing.hnfunny.com`；两个域名指向同一台服务器，旧链接在旧域名保留期间继续可用。
- 服务器上的目录、系统服务名仍沿用历史命名（`~/.publish-html/`、`com.publish-html.api`、`com.publish-html.static80`）——它们由两代技能共用，**不要重命名**，否则会与既有部署脱节。
- 旧域名 `sofunny-html.hnfunny.com` 的明文链接仍然有效：请求会被 301 跳到同域名的 HTTPS，证书同时覆盖新老两个域名，老链接不会失效。

## 调用须知：先了解已运行站点

运行状态保存在 **skill 根目录的 `state/`** 下：`runs/` 为本地缓存的发布记录、`server/` 为部署 API 配置与 token。状态不依赖任何会话，新会话同样可读可管。

任何调用开始时——尤其当用户询问「有哪些已发布的服务」「能不能删除」这类问题时——先执行 `status` 掌握现状，再决定下一步：

```bash
python3 "${CODEX_HOME:-$HOME/.codex}/skills/sofunny-resource-sharing/scripts/publish.py" status
```

## 核心场景

| 场景 | 模式 | 结果 |
|---|---|---|
| 发布资源包（APK / ZIP 等） | `server app.apk` | 直链 `https://sofunny-resource-sharing.hnfunny.com/site-id.apk` + 入口页 `/site-id/`（含大小与 SHA256） |
| 发布资源目录（多个文件） | `server ./release-dir` | `/site-id/`，自动生成资源索引页列出全部文件 |
| 发布 HTML / 静态站点 | `server index.html`、`server ./dist` | 单文件 `/<site-id>.html`；目录 `/site-id/` |
| **原地更新已发布内容** | `server SOURCE --update` | **URL 保持不变**，内容替换为最新 |
| 列出服务器上我部署的站点 | `server-sites` | 仅自己 token 部署的站点（含类型 kind） |
| 查看本 skill 部署缓存 | `status` | 本地 `runs/` 记录 + 存活校验 |
| 检查 HTTPS 证书与 80 跳转 | `tls-status` | 证书主体、覆盖域名、剩余天数、跳转是否正常 |
| 删除我部署的站点 | `remove-server` | 服务器按归属校验 |
| 查看服务器上**所有人**的链接 | `admin-url` | 打印管理后台地址，浏览器里用管理员 token 打开（只读） |
| 配置部署 API 访问 | `config-server` | 可选：手工指定 base_url 与操作员签发的 token |

服务器侧的安装（`install`）、升级（`upgrade`）、token 管理（`token-*`）与 HTTPS 证书都在 [sofunny-resource-sharing-server](https://git.sofunny.io/skill-libs/sofunny-resource-sharing-server) 仓库，由操作员通过 SSH 执行，**本 skill 不含这些命令**。

## 环境自检（自动，无需用户操作）

首次调用时若本机未配置部署 API，脚本会**自动**执行：

1. 尝试接管旧技能 `sofunny-publish-html` 的 `state/`（存在则复用其 token 与发布记录，避免重复申领、避免丢失旧站点归属）。
2. 仍无配置时连接默认部署服务器（内置地址）做健康检查；不可达时提示检查内网/VPN。
3. 调用 `/api/v1/register` 自动申领 token（身份 label 形如 `auto-<用户名>`），写入 `state/server/`。

之后 `server` / `server-sites` / `remove-server` 命令直接可用。用户只需下达「发布 / 更新 / 删除」等命令。只有当用户持有操作员签发的具名 token 时，才需要手工 `config-server` 覆盖自动配置。

## 发布前检查

1. 解析 HTML 文件、静态目录或资源文件；目录优先取 `index.html` / `index.htm` 作为入口。
2. 单个 HTML 默认只发布该文件，避免误传父目录中的无关内容。需要 CSS、JavaScript 或图片时，优先传入专用静态目录；只有人工确认目录内容后才使用 `--root`。
3. 优先发布 `dist/`、`build/` 等产物目录，不上传源码、数据库、用户数据或服务端程序。
4. 检查资源使用相对路径；`/assets/app.css`、`<base href="/">` 会绕过 `/site-id/`。
5. 目录没有 HTML 入口时按**资源包**发布，脚本自动生成索引页列出全部文件（大小 + SHA256），放置自己的 `index.html` 即可覆盖。
6. 告知用户：链接是内网 HTTPS 能力链接，传输已加密，但**没有登录鉴权**；持有完整 URL 的人可读取或下载内容。

脚本会排除隐藏文件、符号链接、非允许后缀文件、`.env`、私钥、数据库和依赖缓存（这是后缀与文件名白名单，不是内容检查），然后把内容原样打包上传。**发布链路不对内容做任何凭据检查**：文本里的 key、压缩包里的 `.env`、签名文件、内部资料都不会被识别、拦截或提示。内容是否可公开，完全由发布者自行确认。

## 发布到服务器

### 资源包（APK / ZIP / 安装包等）

支持的后缀：`.apk .apks .aab .ipa .dmg .pkg .exe .msi .deb .rpm .appimage .jar .aar .whl .zip .7z .rar .tar .gz .tgz .bz2 .xz .iso` 等。

```bash
# 单个安装包：给出 .apk 直链 + 入口页（含大小与 SHA256）
python3 "${CODEX_HOME:-$HOME/.codex}/skills/sofunny-resource-sharing/scripts/publish.py" server "/absolute/path/to/App-Release.apk"

# 多个文件（无 index.html 的目录）：自动生成索引页，逐个提供下载
python3 "${CODEX_HOME:-$HOME/.codex}/skills/sofunny-resource-sharing/scripts/publish.py" server "/absolute/path/to/release-dir"
```

- 单文件资源发布返回两条链接：`URL` 为 `/<site-id>.<后缀>` 直链（可直接分享给同事下载），`入口页` 为 `/<site-id>/` 资源页（列出文件名、大小与 SHA256，便于核对完整性）。复合后缀（`.tar.gz` / `.tar.bz2` / `.tar.xz`）在直链里整体保留，接收方一眼能看出这是 tarball。
- 目录发布返回 `/<site-id>/` 索引页；同后缀文件不唯一时直链不可用，用索引页里的文件链接。
- 不想要自动索引页时加 `--no-index`（仅单文件发布可用，此时会额外输出 `文件地址:`）。目录发布必须生成索引页。
- 上限：单次部署默认 5000 个文件、2 GiB（服务器可用 `--max-upload-mib` / `--max-files` 调整，客户端会按服务器公布的上限提前拦截）。上传分块流式传输，不占用两端内存，1 GiB 级安装包可直接发布。这是服务器侧的发布上限，与文件内容无关。

### HTML / 静态站点

```bash
python3 "${CODEX_HOME:-$HOME/.codex}/skills/sofunny-resource-sharing/scripts/publish.py" server "/absolute/path/to/index.html"
```

非默认入口使用 `--entry demo.html`。返回 `URL:` 与 `Site ID:`。部署成功后记录写入 skill 的 `state/runs/`，之后任何会话都可用 `status` 查看、`remove-server` 删除。

### 公开域名不可达时的处理

发布结束若出现 `公开域名 ...` 开头的警告，说明站点已上传成功但分享链接暂时打不开。脚本会先探测一次 TLS，把诊断分成三类，按提示处理：

| 警告内容 | 含义 | 处理 |
|---|---|---|
| `的 HTTPS 不可用（...）` | 443 连不上、证书缺失或证书校验失败 | 先确认已连内网/VPN；服务器上执行 `setup-tls.py status` 看证书与服务状态；证书缺失时执行 `setup-tls.py install` |
| `的证书与 TLS 握手正常，但站点路径检查失败` | 证书没问题，443 实例在跑旧脚本或没重启 | 操作员用服务端仓库执行 `server.py upgrade` 重启 443 实例 |
| `当前不可达`（明文 HTTP 域名） | 域名还没在内网 DNS 生效 | 让 IT 在内网 DNS 增加 `sofunny-resource-sharing.hnfunny.com → 10.41.0.2`（与旧域名同机），或本机临时在 `/etc/hosts` 加一行 `10.41.0.2 sofunny-resource-sharing.hnfunny.com` |

随时可以单独检查证书与跳转：

```bash
python3 "${CODEX_HOME:-$HOME/.codex}/skills/sofunny-resource-sharing/scripts/publish.py" tls-status
```

它输出证书主体、颁发者、覆盖域名、剩余天数，并实测 80 端口是否跳到 HTTPS。剩余天数少于 21 天或 SAN 不覆盖当前域名时以非零码退出，便于接监控。

应急：`--public-base-url https://sofunny-html.hnfunny.com`（旧域名，同一张证书、同一台服务器）。

### 原地更新（链接不变）

当用户表达「更新 / 重新发布 / 我改了文件，帮忙推上去 / 同步到服务器」等意图时，**必须使用 `--update` 原地更新**，而不是重新发布：

```bash
python3 "${CODEX_HOME:-$HOME/.codex}/skills/sofunny-resource-sharing/scripts/publish.py" \
  server "/absolute/path/to/index.html" --update
```

- 客户端根据来源路径在 `state/runs/` 匹配该来源上次发布的站点，覆盖更新其内容，**Site ID 与 URL 完全不变**，已传播给他人的链接继续展示最新内容。
- 匹配不到历史记录时报错提示先发布；也可用 `--site-id SITE_ID` 显式指定要更新的站点（跨技能更新历史站点用这种方式最稳）。
- 只有当用户明确要求「发布一个新链接」时才不带 `--update`。

管理站点：

```bash
python3 "${CODEX_HOME:-$HOME/.codex}/skills/sofunny-resource-sharing/scripts/publish.py" status
python3 "${CODEX_HOME:-$HOME/.codex}/skills/sofunny-resource-sharing/scripts/publish.py" server-sites
python3 "${CODEX_HOME:-$HOME/.codex}/skills/sofunny-resource-sharing/scripts/publish.py" remove-server SITE_ID --confirm-site-id SITE_ID
```

## 多人使用与归属隔离

每个 token 代表一个用户身份。**服务端强制归属校验**：站点部署时记录 owner（token 的 label），`server-sites` 只列出当前 token 部署的站点，`remove-server` 只允许删除当前 token 部署的站点。任何人都无法通过 API 改动或删除其他用户部署的内容。

本 skill 与旧技能共用同一 token 库：自动申领的身份 label 都是 `auto-<用户名>`，因此换用本 skill 后仍能列出、更新、删除历史上用旧技能发布的站点。

### 服务器侧的安装、升级与用户管理（操作员）

全部在 [sofunny-resource-sharing-server](https://git.sofunny.io/skill-libs/sofunny-resource-sharing-server) 仓库里执行，本 skill 不含这些命令：

```bash
git clone git@git.sofunny.io:skill-libs/sofunny-resource-sharing-server.git && cd sofunny-resource-sharing-server

python3 scripts/server.py install --first-token-label <你的名字>   # 首次部署（含首个管理员 token）
python3 scripts/server.py upgrade                                  # 升级并重启全部静态实例
python3 scripts/server.py token-add <用户名>                        # 具名身份（便于统一吊销）
python3 scripts/server.py token-list                               # 查看 label 与角色（含自动申领的 auto-*）
python3 scripts/server.py token-revoke <用户名或auto-xxx>           # 吊销
python3 scripts/server.py token-grant-admin <label>                # 管理后台权限
```

`install` 打印的 `TOKEN=` 只显示一次。要让本机客户端接管这个具名 token，用它的输出提示执行 `publish.py config-server --base-url <BASE_URL> --token <TOKEN>`。操作员手册（部署形态、三个静态实例、证书、管理后台）见该仓库 README。

**资源包发布需要 daemon ≥ 1.3.0**（管理后台需要 ≥ 1.5.0）：版本不足时客户端直接报「服务器 daemon 版本过低」并拒绝上传，HTML 发布不受影响。

### 管理后台（看全服务器的链接）

`admin-url` 打印地址，浏览器打开后用**管理员 token** 进入（`install` 生成的第一个 token 已是管理员；已有的具名 token 由操作员 `token-grant-admin` 提权）。页面只读，列出全部 token 的站点、按所有者汇总、磁盘与证书状态，每站给一条可直接复制的链接。

管理页只监听内网明文端口 `41740`，管理 token 在这条链路上是明文传输的：不要把它放到公网或加端口转发。**删除仍走 `remove-server`**，管理页不做删除。

### 升级服务器 daemon

```bash
python3 scripts/server.py upgrade    # 服务端仓库，不影响既有 token 与站点
```

升级会重启部署 API 与三个静态实例（数秒），站点文件与 token 不变。三个实例都执行磁盘上的 `safe-static-server.py`：daemon 拉起的 `41739` 实例、LaunchAgent `com.publish-html.static443`（443）、`com.publish-html.static80`（80 跳转）。**只重启 daemon 不会更新后两个**，漏掉会出现「新后缀在公开域名 404、`IP:41739` 正常」的半新半旧状态；`server.py upgrade` 已内置全部重启，手工操作时请逐个确认。

## HTTPS 证书与续期（服务器操作员）

证书由 **acme.sh + 阿里云 DNS 接口**签发，CA 是 **ZeroSSL**（不是 Let's Encrypt：这张网络挡住它
的 `172.65.0.0/16`）。走 DNS-01 挑战，域名不需要公网可达，只要能把 `_acme-challenge` TXT 记录写进
`hnfunny.com` 的公网 DNS 区。90 天有效、每日自动续期，续签后自动重启 443 实例。

安装与巡检在服务器上执行（脚本来自服务端仓库，见其 README）：

```bash
export Ali_Key=<阿里云 AccessKeyId>; export Ali_Secret=<阿里云 AccessKeySecret>
python3 ~/.publish-html/setup-tls.py install --email <你的邮箱>   # 一次性，幂等
python3 ~/.publish-html/setup-tls.py status                      # 只看现状
```

凭据需要独立的阿里云 RAM 用户，只授予 **AliyunDNSFullAccess**（仅用于写 TXT 记录），acme.sh 把它
存在 `~/.acme.sh/account.conf`（600）供无人值守续期使用。

**证书与服务名不要改**：`~/.publish-html/tls/` 与 LaunchAgent 标签（`com.publish-html.acme` 等）
被脚本硬引用。改域名只需改 `--domain` 与 `server-config.json` 里的 `public_base_url`，客户端会自动
跟随（客户端优先用服务器公布的地址，不写死本地默认值）。

**升级与签发要一起做**：新版 daemon 会把 `https://sofunny-resource-sharing.hnfunny.com` 作为对外基址
公布给所有客户端，而 443 由 `setup-tls.py` 负责。只升级、没证书时每次发布都会返回打不开的 `https://`
链接——daemon 启动日志里会有这条警告。

客户端随时可巡检（剩余不足 21 天返回非零码）：

```bash
python3 "${CODEX_HOME:-$HOME/.codex}/skills/sofunny-resource-sharing/scripts/publish.py" tls-status
```

**HTTPS 是公开域名特有的**：`10.41.0.2:41739`（静态）与 `10.41.0.2:41740`（部署 API、含管理后台）
仍是明文，靠内网边界保护。

## 删除服务器站点

这是不可恢复的远端删除。必须由用户明确提出并确认准确 Site ID，随后将同一 ID 传入两次：

```bash
python3 "${CODEX_HOME:-$HOME/.codex}/skills/sofunny-resource-sharing/scripts/publish.py" \
  remove-server SITE_ID --confirm-site-id SITE_ID
```

不得批量删除、猜测 Site ID，或清理未由用户明确指定的目录。服务器会校验该 Site ID 属于当前 token，否则拒绝。

## 常见错误处理

- `入口文件类型不在允许列表内`：该后缀不在发布白名单；确认是否真的需要发布，或先改名为受支持的类型。
- `入口文件超过 X 上限` / `publish root exceeds X`：客户端按服务器公布的上限提前拦截；改用更小的包，或请操作员提高服务器上限。
- `目录发布必须生成资源索引页`：目录没有 HTML 入口时不能加 `--no-index`；改为单文件发布或提供 `index.html`。
- `公开域名 ... 的 HTTPS 不可用`：443 未监听、证书缺失或证书不受信；按上文「公开域名不可达时的处理」分类处理，**不要声称链接已验证**。
- `公开域名 ... 的证书与 TLS 握手正常，但站点路径检查失败`：443 实例在跑旧脚本或未重启；操作员用服务端仓库执行 `python3 scripts/server.py upgrade`。
- `服务器 daemon 版本过低`：资源包发布需要 daemon ≥ 1.3.0；请操作员用服务端仓库执行 `python3 scripts/server.py upgrade`（HTML 发布不受影响）。
- 浏览器报证书不受信 / `NET::ERR_CERT_AUTHORITY_INVALID`：`tls-status` 看证书是否到期或 SAN 不覆盖域名；到期未续签时在服务器查 `~/.publish-html/logs/com.publish-html.acme.log`，并在 `~/.publish-html/setup-tls.py install --force` 后确认 `Ali_Key` / `Ali_Secret` 仍然有效。
- 浏览器报 `ERR_TOO_MANY_REDIRECTS`：80 与 443 指向了同一个实例；确认 443 实例带 `--tls-cert`、80 实例带 `--redirect-to-https`，不要给同一个进程同时传这两组参数。
- `API error 413`：服务器收到的请求体超过上限；确认服务器 daemon 已升级，或降低包体积。
- `API error 507`：服务器磁盘空间不足；联系服务器管理员清理。
- `无法自动连接部署服务器`：本机未配置且默认服务器不可达；提示用户检查内网/VPN 连接后重试。
- `API error 401`：token 已被吊销；联系操作员用 `server.py token-add` 生成新 token 并重新 `config-server`，或删除 `state/server/` 后重新自动申领。
- `API error 503 (自动申领)`：服务器 token 数量达到上限；联系操作员清理 `auto-*` 身份（`server.py token-revoke`）。
- `API error 404 (删除站点)`：站点不存在，或该站点不属于当前 token。
- `无法连接部署 API`：检查服务器 daemon 是否存活（`launchctl list | grep publish-html` 或查看 `~/.publish-html/logs/daemon.log`）。
- 页面资源 404：修正为相对路径后重新发布。
- CSP 阻止外部资源或请求：默认保持阻止；只有确认目标可信且用户明确接受外联风险后，才评估调整策略。
- 下载中断无法续传：静态服务不支持 Range 请求，中断后需重新下载；特别大的包建议先确认网络稳定。

## 安全边界

发布者需要知道的边界（链接是能力链接、不做内容检查、会被排除的文件、上限、归属隔离的范围、发布前自查）见 [references/security-boundary.md](references/security-boundary.md)。处理敏感内容前必须阅读。服务器侧的安全模型（部署 API、管理后台、TLS、剩余风险）在服务端仓库的 `references/server-security.md`。

要点：**本 skill 不对内容做任何凭据检查** —— 发布链路只有四条非内容类约束：后缀与文件名白名单（隐藏文件、`.env`、`*.key`、`*.pem`、`*.p12`、数据库按文件名或后缀排除）、路径安全、归属校验、包体限额。包里的密钥、`.env`、签名文件、内部资料都不会被识别或拦截，**发布者必须自行确认包内没有密钥、签名文件、内部资料或未经授权分发的第三方内容**。公开域名是 HTTPS 能力链接（传输加密、HSTS 一年），但仍然拿到即可下载——加密不等于鉴权；Site ID 不含随机串、可被猜，不要靠它保密。
