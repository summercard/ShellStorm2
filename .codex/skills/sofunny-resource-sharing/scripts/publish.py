#!/usr/bin/env python3
"""将 HTML、静态站点或资源包（APK / ZIP 等）通过 token 鉴权的部署 API 发布为内网分享链接。"""

from __future__ import annotations

import argparse
import datetime as dt
import getpass
import hashlib
import html
import json
import os
import re
import shutil
import socket
import ssl
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path, PurePosixPath
from typing import NamedTuple


DEFAULT_HOST = "10.41.0.2"
DEFAULT_HTTP_PORT = 41739
DEFAULT_API_PORT = 41740
DEFAULT_PUBLIC_BASE_URL = "https://sofunny-resource-sharing.hnfunny.com"
LEGACY_PUBLIC_BASE_URL = "https://sofunny-html.hnfunny.com"
TLS_EXPIRY_WARN_DAYS = 21
DEFAULT_API_BASE_URL = f"http://{DEFAULT_HOST}:{DEFAULT_API_PORT}"
LEGACY_SKILL_NAMES = ("sofunny-publish-html",)
MAX_FILES = 5000
MAX_BYTES = 2 * 1024 * 1024 * 1024
INDEX_HASH_LIMIT = 50
MIN_DAEMON_VERSION_RESOURCE = (1, 3, 0)

SKIP_DIRS = {
    ".git",
    ".hg",
    ".svn",
    ".idea",
    ".vscode",
    "__pycache__",
    "node_modules",
    ".next",
    ".nuxt",
    ".cache",
    ".venv",
    "venv",
}
SKIP_NAMES = {
    ".env",
    ".env.local",
    ".env.production",
    ".npmrc",
    ".pypirc",
    ".netrc",
    "credentials",
    "credentials.json",
    "id_rsa",
    "id_ed25519",
}
SKIP_SUFFIXES = {".pem", ".key", ".p12", ".pfx", ".sqlite", ".sqlite3", ".db"}
STATIC_SUFFIXES = {
    ".avif",
    ".bin",
    ".bmp",
    ".css",
    ".csv",
    ".eot",
    ".gif",
    ".glb",
    ".gltf",
    ".htm",
    ".html",
    ".ico",
    ".jpeg",
    ".jpg",
    ".js",
    ".json",
    ".m4a",
    ".md",
    ".mjs",
    ".mp3",
    ".mp4",
    ".oga",
    ".ogg",
    ".ogv",
    ".otf",
    ".pdf",
    ".png",
    ".srt",
    ".svg",
    ".ttf",
    ".txt",
    ".vtt",
    ".wasm",
    ".wav",
    ".webm",
    ".webmanifest",
    ".webp",
    ".woff",
    ".woff2",
    ".xml",
    ".yaml",
    ".yml",
}
# 资源包：归档、移动端 / 桌面安装包与其它可下载产物
RESOURCE_SUFFIXES = {
    ".7z",
    ".aab",
    ".apk",
    ".apks",
    ".appimage",
    ".aar",
    ".bz2",
    ".deb",
    ".dmg",
    ".exe",
    ".gz",
    ".ipa",
    ".iso",
    ".jar",
    ".msi",
    ".pkg",
    ".rar",
    ".rpm",
    ".tar",
    ".tgz",
    ".whl",
    ".xz",
    ".zip",
}
ALLOWED_STATIC_SUFFIXES = STATIC_SUFFIXES | RESOURCE_SUFFIXES
HTML_SUFFIXES = {".html", ".htm"}
# 复合后缀：整体保留，短链才能表达「这是 tarball」而不只是「这是 gz」
COMPOUND_SUFFIXES = (".tar.gz", ".tar.bz2", ".tar.xz")
SITE_ID_PATTERN = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,94}[a-z0-9])?$")
CONTROL_CHARS_PATTERN = re.compile(r"[\x00-\x1f\x7f-\x9f]")


class Limits(NamedTuple):
    max_files: int
    max_bytes: int


class PublishError(RuntimeError):
    pass


def skill_state_root() -> Path:
    # 运行状态保存在 skill 根目录的 state/ 下，随 skill 可见，跨会话可管理。
    return Path(__file__).resolve().parent.parent / "state"


def cache_root() -> Path:
    return skill_state_root()


def legacy_state_candidates() -> list[Path]:
    """旧技能（sofunny-publish-html）的 state 目录候选位置。"""
    here = Path(__file__).resolve().parent.parent
    roots: list[Path] = [here.parent / name for name in LEGACY_SKILL_NAMES]
    for base in (Path.home() / ".codex" / "skills", Path.home() / ".claude" / "skills"):
        roots.extend(base / name for name in LEGACY_SKILL_NAMES)
    return [root / "state" for root in roots]


def adopt_legacy_state() -> str | None:
    """首次运行时接管旧技能的 state：复用其 token 配置并导入发布记录。

    会扫描所有候选旧目录（本机可能有多个克隆/安装），逐个补齐：
    - token 配置只在本地还没有时接管一次（复用 token 很关键——服务端按 token label
      判定站点归属，另起新 token 会让具名 token 用户丢失对历史站点的管理权）；
    - 发布记录按文件名去重合并（`--update` 靠它匹配来源，补齐才能原地更新历史站点）。
    返回提示文本，没有可接管内容时返回 None。
    """
    state = skill_state_root()
    server_ready = (state / "server" / "api-config.json").is_file()
    notes: list[str] = []
    token_source = ""
    for legacy in legacy_state_candidates():
        try:
            if legacy.resolve() == state.resolve():
                continue
        except OSError:
            continue
        legacy_server = legacy / "server" / "api-config.json"
        legacy_runs = legacy / "runs"
        if not server_ready and legacy_server.is_file():
            try:
                config = read_json(legacy_server) or {}
                (state / "server").mkdir(parents=True, exist_ok=True)
                legacy_token = Path(str(config.get("token_file", ""))).expanduser()
                if legacy_token.is_file():
                    token_target = state / "server" / "api-token"
                    shutil.copy2(legacy_token, token_target)
                    os.chmod(token_target, 0o600)
                    config["token_file"] = str(token_target)
                config["adopted_from"] = str(legacy)
                config_path = state / "server" / "api-config.json"
                config_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
                os.chmod(config_path, 0o600)
                server_ready = True
                token_source = str(legacy)
                notes.append("token 配置")
            except OSError as exc:
                return f"接管旧技能运行状态失败（{safe_display(exc)}），将从零开始"
        if legacy_runs.is_dir():
            imported = 0
            try:
                (state / "runs").mkdir(parents=True, exist_ok=True)
                for record_path in legacy_runs.glob("*.json"):
                    if not record_path.is_file() or record_path.is_symlink():
                        continue
                    target = state / "runs" / record_path.name
                    if target.exists():
                        continue
                    shutil.copy2(record_path, target)
                    imported += 1
            except OSError as exc:
                return f"接管旧技能运行状态失败（{safe_display(exc)}），将从零开始"
            if imported:
                notes.append(f"{imported} 条发布记录")
    if not notes:
        return None
    detail = "、".join(notes)
    origin = f"，token 来源: {token_source}" if token_source else ""
    return f"已接管旧技能的运行状态（{detail}）{origin}"


def slugify(value: str) -> str:
    """转成 Site ID 可用的 ASCII 片段；无法转换时返回空串，由调用方决定回退。"""
    value = re.sub(r"[^a-zA-Z0-9]+", "-", value).strip("-").lower()
    return value[:32]


def pick_name_hint(args_name: str | None, source_root: Path, only_entry: Path | None, kind: str) -> str:
    """选择 Site ID 的名称提示：中文等无法 slugify 时依次回退到文件名与目录名。"""
    candidates: list[str] = []
    if args_name:
        candidates.append(args_name)
    elif only_entry is not None and kind == "resource":
        candidates.append(Path(only_entry).stem)
    candidates.append(source_root.name)
    for candidate in candidates:
        slug = slugify(candidate)
        if slug:
            return slug
    return "resource" if kind == "resource" else "site"


def safe_display(value: object) -> str:
    return CONTROL_CHARS_PATTERN.sub("?", str(value))


def validate_public_base_url(value: str | None) -> None:
    """校验用户显式传入的 --public-base-url；服务器公布的地址另有一条解析校验。"""
    if not value:
        return
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname or parsed.username or parsed.password:
        raise PublishError("公开基础 URL 必须是无账号信息的 HTTP/HTTPS 地址")
    if parsed.query or parsed.fragment:
        raise PublishError("公开基础 URL 不得包含查询参数或片段")


def is_skipped(relative: Path, is_dir: bool = False) -> bool:
    if any(part in SKIP_DIRS for part in relative.parts):
        return True
    if any(part.startswith(".") for part in relative.parts):
        return True
    name = relative.name.lower()
    if name in SKIP_NAMES or name.startswith(".env."):
        return True
    if is_dir:
        # 目录名不带后缀（assets、res…），后缀白名单只约束文件
        return False
    suffix = relative.suffix.lower()
    return suffix in SKIP_SUFFIXES or suffix not in ALLOWED_STATIC_SUFFIXES


def resolve_source(
    source_value: str,
    root_value: str | None,
    entry_value: str | None,
) -> tuple[Path, Path | None, Path | None, str]:
    """解析发布来源。

    返回 (资源根目录, 入口路径或 None, 单文件入口或 None, 类型)。
    类型为 "html"（有 HTML 入口的页面/站点）或 "resource"（资源包：单个安装包、
    归档文件，或没有 index.html 的目录）。
    """
    source = Path(source_value).expanduser().resolve()
    if not source.exists():
        raise PublishError(f"source does not exist: {source}")

    kind = "html"
    if source.is_dir():
        root = Path(root_value).expanduser().resolve() if root_value else source
        only_entry = None
        if entry_value:
            entry: Path | None = Path(entry_value)
        else:
            entry = None
            for candidate in ("index.html", "index.htm"):
                if (root / candidate).is_file():
                    entry = Path(candidate)
                    break
            if entry is None:
                # 目录没有 HTML 入口：按资源包发布，随后生成索引页
                kind = "resource"
        if entry is not None and entry.suffix.lower() not in HTML_SUFFIXES:
            raise PublishError(f"entry 必须是 HTML 文件: {safe_display(entry)}")
    elif source.is_file():
        root = Path(root_value).expanduser().resolve() if root_value else source.parent
        try:
            entry = source.relative_to(root)
        except ValueError as exc:
            raise PublishError(f"source must be inside resource root: {root}") from exc
        if entry_value and Path(entry_value) != entry:
            raise PublishError("--entry cannot point away from a single-file source")
        only_entry = None if root_value else entry
        if entry.suffix.lower() not in HTML_SUFFIXES:
            kind = "resource"
    else:
        raise PublishError(f"source is not a regular file or directory: {source}")

    if not root.is_dir():
        raise PublishError(f"resource root is not a directory: {root}")
    if entry is None:
        return root, None, only_entry, kind
    if entry.is_absolute() or ".." in entry.parts:
        raise PublishError("entry must be a relative path inside the resource root")
    entry_path = (root / entry).resolve()
    try:
        entry_path.relative_to(root)
    except ValueError as exc:
        raise PublishError("entry resolves outside the resource root") from exc
    if not entry_path.is_file():
        raise PublishError(f"entry file does not exist: {entry_path}")
    if not entry_path.suffix:
        raise PublishError(f"入口文件必须带扩展名: {safe_display(entry)}")
    if entry_path.suffix.lower() not in ALLOWED_STATIC_SUFFIXES:
        raise PublishError(f"入口文件类型不在允许列表内: {safe_display(entry)}")
    return root, entry, only_entry, kind


def entry_key(entry: Path | None) -> str:
    """发布记录里的来源标识；资源包目录（无入口）用固定值。"""
    return entry.as_posix() if entry is not None else "(auto-index)"


def snapshot(
    source_root: Path,
    destination: Path,
    only_entry: Path | None = None,
    limits: Limits | None = None,
) -> tuple[int, int, list[str]]:
    max_files = limits.max_files if limits else MAX_FILES
    max_bytes = limits.max_bytes if limits else MAX_BYTES
    count = 0
    total = 0
    skipped: list[str] = []
    destination.mkdir(parents=True, exist_ok=False)

    if only_entry is not None:
        source_file = source_root / only_entry
        if is_skipped(only_entry) or source_file.is_symlink() or not source_file.is_file():
            raise PublishError(f"入口文件不符合静态发布规则: {safe_display(only_entry)}")
        size = source_file.stat().st_size
        if size > max_bytes:
            raise PublishError(f"入口文件超过 {format_size(max_bytes)} 上限")
        target = destination / only_entry
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_file, target)
        return 1, size, skipped

    for current, dirnames, filenames in os.walk(source_root, followlinks=False):
        current_path = Path(current)
        relative_dir = current_path.relative_to(source_root)
        kept_dirs = []
        for dirname in dirnames:
            relative = relative_dir / dirname
            path = current_path / dirname
            if is_skipped(relative, is_dir=True) or path.is_symlink():
                skipped.append(str(relative))
            else:
                kept_dirs.append(dirname)
        dirnames[:] = kept_dirs

        for filename in filenames:
            source_file = current_path / filename
            relative = relative_dir / filename
            if is_skipped(relative) or source_file.is_symlink():
                skipped.append(str(relative))
                continue
            if not source_file.is_file():
                skipped.append(str(relative))
                continue
            size = source_file.stat().st_size
            count += 1
            total += size
            if count > max_files:
                raise PublishError(f"publish root exceeds {max_files} files; use a smaller static output directory")
            if total > max_bytes:
                raise PublishError(f"publish root exceeds {format_size(max_bytes)}")
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_file, target)

    return count, total, skipped


def format_size(size: int) -> str:
    value = float(size)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if value < 1024 or unit == "TiB":
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.1f} {unit}"
        value /= 1024
    return f"{size} B"


def validate_site_id(site_id: str) -> None:
    if not SITE_ID_PATTERN.fullmatch(site_id):
        raise PublishError(f"Site ID 不合法: {safe_display(site_id)}")


















































def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def index_entry_html(relative: Path, size: int, digest: str | None) -> str:
    href = "/".join(urllib.parse.quote(part) for part in relative.parts)
    label = html.escape(relative.as_posix())
    parts = [
        f'    <li><a href="{href}" download>{label}</a>',
        f'<span class="size">{html.escape(format_size(size))}</span>',
    ]
    if digest:
        parts.append(f'<code class="hash">{html.escape(digest)}</code>')
    parts.append("</li>")
    return "".join(parts)


def index_page(title: str, site_dir: Path, digest_map: dict[str, str]) -> str:
    files: list[tuple[Path, int]] = []
    for path in sorted(site_dir.rglob("*")):
        if not path.is_file() or path.name in {"index.html", "index.htm"}:
            continue
        try:
            files.append((path.relative_to(site_dir), path.stat().st_size))
        except OSError:
            continue
    total = sum(size for _, size in files)
    rows = "\n".join(
        index_entry_html(relative, size, digest_map.get(relative.as_posix()))
        for relative, size in files
    )
    stamp = dt.datetime.now().astimezone().strftime("%Y-%m-%d %H:%M")
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>{html.escape(title)} · 资源下载</title>
<style>
:root {{ color-scheme: light dark; }}
body {{ margin: 0; padding: 2.5rem 1.25rem; font: 15px/1.6 -apple-system, "PingFang SC", "Microsoft YaHei", system-ui, sans-serif; }}
main {{ max-width: 46rem; margin: 0 auto; }}
h1 {{ font-size: 1.4rem; margin: 0 0 .35rem; }}
p.meta {{ margin: 0 0 1.5rem; opacity: .65; font-size: .85rem; }}
ul.files {{ list-style: none; margin: 0; padding: 0; border-top: 1px solid rgba(128,128,128,.3); }}
ul.files li {{ display: flex; flex-wrap: wrap; align-items: baseline; gap: .75rem; padding: .7rem .2rem; border-bottom: 1px solid rgba(128,128,128,.3); }}
ul.files a {{ font-weight: 600; text-decoration: none; word-break: break-all; }}
ul.files a:hover {{ text-decoration: underline; }}
.size {{ opacity: .65; font-size: .85rem; }}
.hash {{ width: 100%; opacity: .5; font-size: .72rem; word-break: break-all; }}
p.note {{ margin-top: 1.5rem; opacity: .6; font-size: .8rem; }}
</style>
</head>
<body>
<main>
<h1>{html.escape(title)}</h1>
<p class="meta">{len(files)} 个文件 · {html.escape(format_size(total))} · 由 sofunny-resource-sharing 于 {stamp} 生成</p>
<ul class="files">
{rows}
</ul>
<p class="note">本页由发布工具自动生成。在资源根目录放置 index.html 即可替换本页。链接为内网 HTTP 能力链接，任何持有该链接的人都可下载，请勿放置敏感文件。</p>
</main>
</body>
</html>
"""


def write_index_page(site_dir: Path, title: str) -> tuple[bool, dict[str, str]]:
    """资源包没有 HTML 入口时生成索引页；返回 (是否生成, 文件校验值表)。"""
    for candidate in ("index.html", "index.htm"):
        if (site_dir / candidate).is_file():
            return False, {}
    digest_map: dict[str, str] = {}
    try:
        files = [path for path in sorted(site_dir.rglob("*")) if path.is_file()]
        if len(files) <= INDEX_HASH_LIMIT:
            for path in files:
                digest_map[path.relative_to(site_dir).as_posix()] = sha256_file(path)
    except OSError as exc:
        raise PublishError(f"生成校验值失败: {safe_display(exc)}") from exc
    page = index_page(title, site_dir, digest_map)
    (site_dir / "index.html").write_text(page, encoding="utf-8")
    return True, digest_map


def entry_url(base_url: str, site_id: str | None, entry: Path) -> str:
    base = base_url.rstrip("/") + "/"
    prefix = f"{urllib.parse.quote(site_id)}/" if site_id else ""
    if entry.as_posix() == "index.html":
        path = prefix
    else:
        path = prefix + "/".join(urllib.parse.quote(part) for part in entry.parts)
    return urllib.parse.urljoin(base, path)


def full_suffix(name: str) -> str:
    """取完整后缀：`.tar.gz` 这类复合后缀整体返回，其余取最后一段。"""
    lower = str(name).lower()
    for compound in COMPOUND_SUFFIXES:
        if lower.endswith(compound):
            return compound
    return PurePosixPath(lower).suffix


def short_url(base_url: str, site_id: str, entry: Path) -> str:
    """单文件发布的短链：/<site-id><完整后缀>，由静态服务映射到站点目录内同后缀的唯一文件。"""
    return f"{base_url.rstrip('/')}/{site_id}{full_suffix(entry.name)}"


def health_check(url: str, attempts: int = 12) -> str | None:
    last_error = "unknown error"
    opener = build_direct_opener()
    for _ in range(attempts):
        try:
            request = urllib.request.Request(url, method="GET", headers={"User-Agent": "sofunny-resource-sharing/1"})
            with opener.open(request, timeout=2) as response:
                if 200 <= response.status < 400:
                    return None
                last_error = f"HTTP {response.status}"
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last_error = str(exc)
        time.sleep(0.25)
    return last_error


def public_base_url_from_info(info: dict) -> str:
    """取服务器公布的公开基址；字段缺失或格式不对时返回空串，由调用方回退到内置默认值。"""
    text = str(info.get("public_base_url") or "").strip()
    if not text:
        return ""
    parsed = urllib.parse.urlsplit(text)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname or parsed.username or parsed.password:
        return ""
    if parsed.query or parsed.fragment:
        return ""
    return f"{parsed.scheme}://{parsed.netloc}{parsed.path.rstrip('/')}"


def probe_tls(host: str, port: int = 443, timeout: float = 6.0) -> dict:
    """对公开域名做一次真实 TLS 握手（走系统信任库校验），回报证书与协商结果。"""
    context = ssl.create_default_context()
    try:
        with socket.create_connection((host, port), timeout=timeout) as raw:
            with context.wrap_socket(raw, server_hostname=host) as tls:
                cert = tls.getpeercert()
                version = tls.version() or "?"
                cipher = (tls.cipher() or ("?",))[0]
    except ssl.SSLCertVerificationError as exc:
        return {"ok": False, "error": f"证书校验失败：{exc.verify_message or exc}"}
    except (OSError, ssl.SSLError) as exc:
        return {"ok": False, "error": str(exc)}

    def flatten(name: str) -> str:
        parts = [f"{key}={value}" for entry in cert.get(name, ()) for key, value in entry]
        return ", ".join(parts) or "?"

    expires: dt.datetime | None = None
    raw_not_after = str(cert.get("notAfter") or "")
    try:
        expires = dt.datetime.strptime(raw_not_after, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=dt.timezone.utc)
    except ValueError:
        pass
    days_left = (expires - dt.datetime.now(dt.timezone.utc)).days if expires else None
    return {
        "ok": True,
        "subject": flatten("subject"),
        "issuer": flatten("issuer"),
        "sans": [value for kind, value in cert.get("subjectAltName", ()) if kind == "DNS"],
        "not_after": expires,
        "days_left": days_left,
        "version": version,
        "cipher": cipher,
    }


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    """不让 urllib 自动跟随跳转。

    urllib 默认会把 301 跟掉，于是拿到的最后一个响应是跳转**之后**的结果
    （探测路径本就不存在 → 404），跳转本身反而看不到了。返回 None 让它把 3xx
    当异常抛出，由调用方读 Location —— 这才是要验证的东西。
    """

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001
        return None


def check_https_redirect(host: str, port: int = 80, timeout: float = 5.0) -> str:
    """确认 80 端口把明文请求跳到 HTTPS；返回空串表示正常，否则返回问题描述。

    探的必须是普通路径，不能探健康检查路径：健康检查在跳转逻辑之前就被应答（204），
    拿它探测会把「跳转正常」误判成「未跳转」。2026-10-08 首次上线时就误报过一次。
    """
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirectHandler())
    request = urllib.request.Request(
        f"http://{host}:{port}/__https_redirect_probe__",
        method="GET",
        headers={"User-Agent": "sofunny-resource-sharing/1"},
    )
    try:
        with opener.open(request, timeout=timeout) as response:
            location = response.headers.get("Location", "")
    except urllib.error.HTTPError as exc:
        if exc.code in {301, 302, 307, 308}:
            location = exc.headers.get("Location", "")
        else:
            return f"HTTP {exc.code}"
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return str(exc)
    if not location.startswith("https://"):
        return f"未跳转到 HTTPS（Location: {safe_display(location) or '缺失'}）"
    return ""


def host_covered(pattern: str, host: str) -> bool:
    """证书里的一条 SAN 是否覆盖某个主机名。

    通配只覆盖一层：`*.example.com` 匹配 `a.example.com`，不匹配 `a.b.example.com`。
    写成 `host in sans` 的精确比较会在用通配证书时误报「SAN 不包含」——
    2026-10-08 首次用 `*.hnfunny.com` 上线时就误报过一次。
    """
    pattern = pattern.lower().rstrip(".")
    host = host.lower().rstrip(".")
    if pattern == host:
        return True
    if not pattern.startswith("*."):
        return False
    suffix = pattern[2:]
    if not host.endswith("." + suffix):
        return False
    return "." not in host[: -(len(suffix) + 1)]


def tls_status(args: argparse.Namespace) -> int:
    host = args.host or urllib.parse.urlsplit(DEFAULT_PUBLIC_BASE_URL).hostname or ""
    port = args.port or 443
    if not host:
        raise PublishError("无法确定要探测的公开域名，请用 --host 指定")
    result = probe_tls(host, port)
    if not result.get("ok"):
        print(f"公开域名: {host}:{port}")
        print(f"TLS: 失败（{safe_display(result.get('error', '未知错误'))}）")
        print("提示: 服务器上尚未签发证书时属预期；在服务器执行 ~/.publish-html/setup-tls.py 完成签发与 443 服务。")
        return 1
    sans = result["sans"]
    covered = any(host_covered(san, host) for san in sans)
    print(f"公开域名: {host}:{port}")
    print(f"TLS: {result['version']} / {result['cipher']}")
    print(f"颁发者: {safe_display(result['issuer'])}")
    print(f"证书主体: {safe_display(result['subject'])}")
    print(f"覆盖域名: {', '.join(safe_display(item) for item in sans) or '（无 SAN）'}")
    if result["not_after"] is not None:
        print(f"到期时间: {result['not_after'].astimezone().isoformat(timespec='seconds')}（剩余 {result['days_left']} 天）")
    redirect_error = check_https_redirect(host)
    print(f"80 端口跳转: {'正常' if not redirect_error else safe_display(redirect_error)}")
    problems = []
    if not covered:
        problems.append(f"证书 SAN 不包含 {host}")
    if result["days_left"] is not None and result["days_left"] < TLS_EXPIRY_WARN_DAYS:
        problems.append(f"证书 {result['days_left']} 天后到期，请检查自动续期")
    if redirect_error:
        problems.append(f"80 端口未跳转：{redirect_error}")
    for item in problems:
        print(f"警告: {item}")
    return 1 if problems else 0


def describe_public_failure(public_base_url: str, host: str, http_port: int) -> str:
    """公开域名健康检查失败时给出可执行的诊断，而不是笼统的「不可达」。

    纯 DNS 问题与「443 没起 / 证书没装」的处理方式完全不同，必须先分清。
    """
    parsed = urllib.parse.urlsplit(public_base_url)
    public_host = parsed.hostname or public_base_url
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    common = (
        f"站点已在 {host}:{http_port} 就绪但公开域名不可达。先确认已连内网/VPN；"
        f"域名不解析时让 IT 在内网 DNS 增加 {public_host}，或本机临时在 /etc/hosts 加 "
        f"{DEFAULT_HOST} {public_host}。"
    )
    if parsed.scheme != "https":
        return f"公开域名 {public_host} 当前不可达：{common}"
    probe = probe_tls(public_host, port)
    if probe.get("ok"):
        return (
            f"公开域名 {public_host} 的证书与 TLS 握手正常，但站点路径检查失败："
            f"多半是 443 实例还在跑旧脚本或未重启，请在服务器上执行 server.py upgrade"
            f"（sofunny-resource-sharing-server 仓库）后重试。"
        )
    return (
        f"公开域名 {public_host} 的 HTTPS 不可用（{safe_display(str(probe.get('error', '未知错误')))}）。{common}"
        f"证书缺失时在服务器执行 ~/.publish-html/setup-tls.py install 签发；应急可用 "
        f"--public-base-url {LEGACY_PUBLIC_BASE_URL}（旧域名，同一台服务器）。"
    )


def print_result(
    mode: str,
    url: str,
    site_id: str,
    files: int,
    size: int,
    skipped: list[str],
    warnings: list[str] | None = None,
    pid: int | None = None,
    extra: list[tuple[str, str]] | None = None,
) -> None:
    print(f"发布成功 ({safe_display(mode)})")
    print(f"URL: {safe_display(url)}")
    for label, value in extra or []:
        print(f"{label}: {safe_display(value)}")
    print(f"Site ID: {safe_display(site_id)}")
    if pid is not None:
        print(f"PID: {pid}")
    print(f"Files: {files}")
    print(f"Bytes: {size}")
    if skipped:
        preview = ", ".join(safe_display(item) for item in skipped[:8])
        suffix = f" (+{len(skipped) - 8} more)" if len(skipped) > 8 else ""
        print(f"已跳过: {preview}{suffix}")
    for item in warnings or []:
        print(f"警告: {safe_display(item)}")


def read_json(path: Path) -> dict[str, object] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def load_api_config() -> tuple[str, str, str, int] | None:
    """读取部署 API 配置，返回 (base_url, token, host, http_port)；未配置返回 None。"""
    base_url = os.environ.get("PUBLISH_HTML_API_BASE_URL")
    token = os.environ.get("PUBLISH_HTML_API_TOKEN")
    host = ""
    http_port = DEFAULT_HTTP_PORT
    config_path = cache_root() / "server" / "api-config.json"
    config = read_json(config_path) if config_path.is_file() else None
    if config:
        host = str(config.get("host") or "")
        try:
            http_port = int(config.get("http_port") or DEFAULT_HTTP_PORT)
        except (TypeError, ValueError):
            http_port = DEFAULT_HTTP_PORT
        if not base_url and config.get("base_url"):
            base_url = str(config["base_url"])
        if not token and config.get("token_file"):
            try:
                token = Path(str(config["token_file"])).expanduser().read_text(encoding="utf-8").strip()
            except OSError:
                token = None
    if base_url and token:
        parsed = urllib.parse.urlsplit(base_url)
        if not host:
            host = parsed.hostname or ""
        if parsed.port:
            # 与 save_api_config 的端口推导保持一致，供健康检查使用
            http_port = parsed.port - (DEFAULT_API_PORT - DEFAULT_HTTP_PORT)
        return base_url.rstrip("/"), token.strip(), host, http_port
    return None


def save_api_config(base_url: str, token: str) -> str:
    parsed = urllib.parse.urlsplit(base_url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname or parsed.username or parsed.password:
        raise PublishError("部署 API 基础 URL 必须是无账号信息的 HTTP/HTTPS 地址")
    if parsed.query or parsed.fragment:
        raise PublishError("部署 API 基础 URL 不得包含查询参数或片段")

    api_port = parsed.port or DEFAULT_API_PORT
    http_port = api_port - (DEFAULT_API_PORT - DEFAULT_HTTP_PORT)
    server_dir = cache_root() / "server"
    server_dir.mkdir(parents=True, exist_ok=True)
    token_file = server_dir / "api-token"
    token_file.write_text(token.strip() + "\n", encoding="utf-8")
    os.chmod(token_file, 0o600)
    api_config = {
        "base_url": base_url.rstrip("/"),
        "token_file": str(token_file),
        "host": parsed.hostname,
        "http_port": http_port,
        "api_port": api_port,
        "configured_at": dt.datetime.now().astimezone().isoformat(),
    }
    config_path = server_dir / "api-config.json"
    config_path.write_text(json.dumps(api_config, indent=2) + "\n", encoding="utf-8")
    os.chmod(config_path, 0o600)
    return str(config_path)


def auto_label() -> str:
    # 服务端会强制加 auto- 前缀，这里只提供用户名部分
    return slugify(getpass.getuser())[:32] or "user"


def ensure_api_config() -> tuple[str, str, str, int]:
    """返回可用的 API 配置；未配置时自动向服务器申领 token 并保存。"""
    api_config = load_api_config()
    if api_config:
        return api_config

    base_url = DEFAULT_API_BASE_URL
    print(f"首次使用：自动连接部署服务器 {base_url} 并申领 token ...", flush=True)
    try:
        health = api_request(base_url, "", "GET", "/api/v1/health")
        if health.get("status") != "ok":
            raise PublishError("部署 API 健康检查返回异常状态")
        result = api_request(base_url, "", "POST", f"/api/v1/register?label={urllib.parse.quote(auto_label())}")
    except PublishError as exc:
        hint = ""
        if isinstance(exc.__cause__, OSError) and exc.__cause__.errno in (65, 64, 51):
            hint = "（若在 macOS 上，请到 系统设置 → 隐私与安全性 → 本地网络 允许你的 Python，如 Homebrew Python）"
        raise PublishError(
            f"无法自动连接部署服务器 {base_url}（{safe_display(exc)}）{hint}。"
            "请检查是否已连接内网/VPN；若问题持续请联系服务器管理员。"
        ) from exc
    token = str(result.get("token", "")).strip()
    if not token:
        raise PublishError("服务器未返回有效 token，请联系服务器管理员")
    label = str(result.get("label", auto_label()))
    config_path = save_api_config(base_url, token)
    print(f"已自动申领 token（身份: {safe_display(label)}），配置写入: {config_path}", flush=True)
    return load_api_config() or (base_url, token, DEFAULT_HOST, DEFAULT_HTTP_PORT)


def build_direct_opener() -> urllib.request.OpenerDirector:
    """绕过系统代理：部署 API 与静态服务只经内网直连，代理转发会导致不可达。"""
    return urllib.request.build_opener(urllib.request.ProxyHandler({}))


def api_request(
    base_url: str,
    token: str,
    method: str,
    path: str,
    body: bytes | None = None,
    headers: dict[str, str] | None = None,
    body_file: Path | None = None,
) -> dict:
    url = base_url.rstrip("/") + path
    all_headers = {"User-Agent": "sofunny-resource-sharing/1"}
    if token:
        all_headers["Authorization"] = f"Bearer {token}"
    if headers:
        all_headers.update(headers)
    stream = None
    if body_file is not None:
        # 大文件流式上传：显式声明 Content-Length，避免 urllib 退化为 chunked 编码
        stream = body_file.open("rb")
        all_headers["Content-Length"] = str(body_file.stat().st_size)
        body = None  # type: ignore[assignment]
    request = urllib.request.Request(url, method=method, data=stream if stream is not None else body, headers=all_headers)
    try:
        with build_direct_opener().open(request, timeout=300) as response:
            payload = response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        try:
            message = json.loads(detail).get("error", detail)
        except (json.JSONDecodeError, AttributeError):
            message = detail
        raise PublishError(f"API error {exc.code}: {safe_display(message)}") from exc
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise PublishError(f"无法连接部署 API {safe_display(url)}: {safe_display(exc)}") from exc
    finally:
        if stream is not None:
            stream.close()
    try:
        result = json.loads(payload)
    except json.JSONDecodeError as exc:
        raise PublishError("部署 API 返回了无效 JSON") from exc
    return result if isinstance(result, dict) else {}


def parse_version(value: object) -> tuple[int, ...]:
    parts = []
    for piece in str(value or "").split("."):
        if not piece.isdigit():
            break
        parts.append(int(piece))
    return tuple(parts)


def fetch_server_info(base_url: str) -> tuple[dict, list[str]]:
    """读取服务器公布的版本与上限；不可用时回退本地默认值并提示。"""
    try:
        return api_request(base_url, "", "GET", "/api/v1/health"), []
    except PublishError as exc:
        return {}, [f"未取到服务器信息，按本地默认上限执行（{safe_display(exc)}）"]


def limits_from_info(info: dict) -> Limits:
    limits = Limits(MAX_FILES, MAX_BYTES)
    max_bytes = info.get("max_bytes")
    max_files = info.get("max_files")
    if isinstance(max_bytes, int) and max_bytes > 0:
        limits = Limits(limits.max_files, min(MAX_BYTES, max_bytes))
    if isinstance(max_files, int) and max_files > 0:
        limits = Limits(min(limits.max_files, max_files), limits.max_bytes)
    return limits


def find_update_target(source_root: Path, entry: Path | None) -> str | None:
    """在本地发布记录中查找同一来源最近一次的站点，用于原地更新。"""
    runs_dir = cache_root() / "runs"
    best_site_id: str | None = None
    best_created_at = ""
    if runs_dir.is_dir():
        for record_path in runs_dir.glob("*.json"):
            try:
                record = json.loads(record_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if not isinstance(record, dict):
                continue
            if str(record.get("source")) != str(source_root):
                continue
            if str(record.get("entry")) != entry_key(entry):
                continue
            created_at = str(record.get("created_at", ""))
            if created_at >= best_created_at and record.get("site_id"):
                best_site_id = str(record["site_id"])
                best_created_at = created_at
    return best_site_id


def publish_server(args: argparse.Namespace) -> int:
    validate_public_base_url(getattr(args, "public_base_url", None))
    api_config = ensure_api_config()
    source_root, entry, only_entry, _kind = resolve_source(args.source, args.root, args.entry)
    target_site_id = getattr(args, "site_id", None)
    if target_site_id:
        validate_site_id(target_site_id)
    elif getattr(args, "update", False):
        target_site_id = find_update_target(source_root, entry)
        if target_site_id is None:
            raise PublishError(
                "本地没有该来源的发布记录，无法原地更新。请先直接发布一次（生成站点），"
                "之后再次修改后用 --update 保持同一链接更新。"
            )
    return publish_server_via_api(
        args, *api_config, target_site_id=target_site_id, resolved=(source_root, entry, only_entry, _kind)
    )


def build_upload_archive(site_dir: Path, archive: Path, compress: bool) -> None:
    mode = "w:gz" if compress else "w"
    with tarfile.open(archive, mode) as tar:
        for path in sorted(site_dir.rglob("*")):
            tar.add(path, arcname=path.relative_to(site_dir), recursive=False)


def publish_server_via_api(
    args: argparse.Namespace,
    base_url: str,
    token: str,
    host: str,
    http_port: int,
    target_site_id: str | None = None,
    resolved: tuple[Path, Path | None, Path | None, str] | None = None,
) -> int:
    if resolved is not None:
        source_root, entry, only_entry, kind = resolved
    else:
        source_root, entry, only_entry, kind = resolve_source(args.source, args.root, args.entry)
    info, warnings = fetch_server_info(base_url)
    limits = limits_from_info(info)
    if kind == "resource":
        server_version = parse_version(info.get("version"))
        if server_version and server_version < MIN_DAEMON_VERSION_RESOURCE:
            raise PublishError(
                "服务器 daemon 版本过低（"
                + ".".join(str(part) for part in server_version)
                + "），不支持资源包发布。请服务器操作员用 sofunny-resource-sharing-server 仓库执行"
                " `python3 scripts/server.py upgrade` 后重试。"
            )
        if entry is None and args.no_index:
            raise PublishError("目录发布必须生成资源索引页，不能使用 --no-index")
    name_hint = pick_name_hint(args.name, source_root, only_entry, kind)
    title = args.name or (Path(only_entry).name if only_entry is not None else source_root.name)

    with tempfile.TemporaryDirectory(prefix="resource-sharing-") as temporary:
        temp_path = Path(temporary)
        site_dir = temp_path / "staging"
        files, size, skipped = snapshot(source_root, site_dir, only_entry, limits)
        if files == 0:
            raise PublishError("来源目录中没有可发布的文件（检查文件类型是否在允许列表内）")
        if entry is not None and not (site_dir / entry).is_file():
            raise PublishError(f"entry was excluded from snapshot: {entry}")
        digest_map: dict[str, str] = {}
        if kind == "resource":
            if not args.no_index:
                _created, digest_map = write_index_page(site_dir, title)
            if only_entry is not None and not digest_map:
                digest_map[only_entry.as_posix()] = sha256_file(site_dir / only_entry)
        # 这里不再对内容做任何检查：发布链路只保证路径安全、归属、包体限额与后缀白名单
        archive = temp_path / ("upload.tar" if kind == "resource" else "upload.tar.gz")
        build_upload_archive(site_dir, archive, compress=kind != "resource")
        deploy_path = f"/api/v1/deploy?name={urllib.parse.quote(name_hint)}&kind={kind}"
        if target_site_id:
            deploy_path += f"&site_id={urllib.parse.quote(target_site_id)}"
        result = api_request(
            base_url,
            token,
            "POST",
            deploy_path,
            body_file=archive,
            headers={"Content-Type": "application/x-tar" if kind == "resource" else "application/x-tar-gz"},
        )
    site_id = str(result.get("site_id", ""))
    validate_site_id(site_id)
    # 公开基址以服务器公布值为准：换域名或换证书时只改服务器，客户端不用跟着升级
    public_base_url = (
        args.public_base_url or public_base_url_from_info(info) or DEFAULT_PUBLIC_BASE_URL
    )

    def site_url(base: str) -> str:
        if only_entry is not None:
            # 单文件发布：短链 /<site-id><后缀>，由静态服务映射到站点目录内同后缀的唯一文件
            return short_url(base, site_id, only_entry)
        if entry is None:
            return f"{base.rstrip('/')}/{site_id}/"
        return entry_url(base, site_id, entry)

    url = site_url(public_base_url)
    landing_url = f"{public_base_url.rstrip('/')}/{site_id}/"
    extras: list[tuple[str, str]] = []
    if kind == "resource" and only_entry is not None:
        if args.no_index:
            extras.append(("文件地址", landing_url + urllib.parse.quote(Path(only_entry).name)))
        else:
            extras.append(("入口页", landing_url))
        digest = digest_map.get(Path(only_entry).as_posix())
        if digest:
            extras.append(("SHA256", digest))
    health_error = health_check(site_url(f"http://{host}:{http_port}"), attempts=5)
    if health_error:
        warnings.append(f"部署已上传，但链接健康检查失败: {health_error}")
    elif health_check(site_url(public_base_url), attempts=2):
        warnings.append(describe_public_failure(public_base_url, host, http_port))
    print_result(
        "server-api-update" if target_site_id else "server-api",
        url,
        site_id,
        int(result.get("files", files)),
        int(result.get("bytes", size)),
        skipped,
        warnings=warnings,
        extra=extras,
    )

    runs_dir = cache_root() / "runs"
    runs_dir.mkdir(parents=True, exist_ok=True)
    now_iso = dt.datetime.now().astimezone().isoformat()
    record_path = runs_dir / f"{site_id}.json"
    previous_created_at = now_iso
    if target_site_id and record_path.is_file():
        try:
            previous = json.loads(record_path.read_text(encoding="utf-8"))
            if isinstance(previous, dict) and previous.get("created_at"):
                previous_created_at = str(previous["created_at"])
        except (OSError, json.JSONDecodeError):
            pass
    record = {
        "site_id": site_id,
        "url": url,
        "owner": "",
        "kind": kind,
        "created_at": previous_created_at,
        "updated_at": now_iso,
        "source": str(source_root),
        "entry": entry_key(entry),
    }
    (runs_dir / f"{site_id}.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    return 0


def remove_server(args: argparse.Namespace) -> int:
    validate_site_id(args.site_id)
    if args.confirm_site_id != args.site_id:
        raise PublishError("服务器删除需要 --confirm-site-id 与 Site ID 完全一致")
    api_config = ensure_api_config()
    base_url, token, _host, _http_port = api_config
    api_request(
        base_url,
        token,
        "DELETE",
        f"/api/v1/sites/{urllib.parse.quote(args.site_id)}",
        headers={"X-Confirm-Site-Id": args.site_id},
    )
    record_path = cache_root() / "runs" / f"{args.site_id}.json"
    if record_path.is_file():
        record_path.unlink()
    print(f"已删除服务器站点: {args.site_id}")
    return 0


def server_sites(_: argparse.Namespace) -> int:
    base_url, token, _host, _http_port = ensure_api_config()
    result = api_request(base_url, token, "GET", "/api/v1/sites")
    sites = result.get("sites")
    if not isinstance(sites, list) or not sites:
        print("No remote sites.")
        return 0
    for site in sites:
        if not isinstance(site, dict):
            continue
        print(
            f"{safe_display(site.get('site_id'))}\t{safe_display(site.get('kind') or 'site')}\t"
            f"{safe_display(site.get('created_at'))}\t"
            f"{safe_display(site.get('files'))} files\t{safe_display(site.get('bytes'))} bytes"
        )
    return 0


def status(_: argparse.Namespace) -> int:
    runs_dir = cache_root() / "runs"
    records = []
    if runs_dir.is_dir():
        for metadata_path in sorted(runs_dir.glob("*.json")):
            try:
                record = json.loads(metadata_path.read_text(encoding="utf-8"))
                if isinstance(record, dict) and record.get("site_id"):
                    records.append(record)
            except (OSError, json.JSONDecodeError):
                continue
    if not records:
        print("No deployments recorded.")
        return 0
    api_config = load_api_config()
    for record in records:
        site_id = str(record["site_id"])
        state = "running"
        if api_config:
            base_url, token, _host, _http_port = api_config
            try:
                result = api_request(base_url, token, "GET", f"/api/v1/sites/{urllib.parse.quote(site_id)}")
                if not result.get("exists", True):
                    state = "stale"
            except PublishError:
                state = "unverified"
        elif health_check(str(record.get("url", "")), attempts=1):
            state = "stale"
        print(
            f"{safe_display(site_id)}\t{safe_display(record.get('kind') or 'site')}\t{state}\t"
            f"{safe_display(record.get('url', ''))}"
        )
    return 0


def config_server(args: argparse.Namespace) -> int:
    base_url = args.base_url.rstrip("/")
    try:
        config_path = save_api_config(base_url, args.token.strip())
    except PublishError as exc:
        raise PublishError(f"配置无效: {exc}") from exc
    token = args.token.strip()

    try:
        health = api_request(base_url, token, "GET", "/api/v1/health")
    except PublishError as exc:
        raise PublishError(f"无法连接部署 API，配置可能无效: {exc}") from exc
    if health.get("status") != "ok":
        raise PublishError("部署 API 健康检查返回异常状态")
    api_port = urllib.parse.urlsplit(base_url).port or DEFAULT_API_PORT
    print(f"客户端配置已写入: {config_path}")
    print(f"部署 API 已连接: {base_url}（静态服务端口 {api_port - (DEFAULT_API_PORT - DEFAULT_HTTP_PORT)}）")
    return 0


def admin_url(_: argparse.Namespace) -> int:
    """打印管理后台地址。管理页本身要管理员 token，这里只给地址、不申领 token。"""
    api_config = load_api_config()
    if api_config is None:
        print("尚未配置部署 API（先发布一次或运行 status 完成自动配置）。")
        print(f"按内置服务器推测的地址: {DEFAULT_API_BASE_URL}/admin")
        return 0
    base_url, _token, _host, _http_port = api_config
    print(f"管理后台: {base_url.rstrip('/')}/admin")
    print("打开后用管理员 token 进入（服务端 publish-daemon.py grant-admin <label> 授予；")
    print("安装时生成的第一个 token 已是管理员）。管理页只在服务器所在内网可达。")
    return 0


def add_publish_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("source", help="HTML 文件、资源文件（APK / ZIP 等）或静态目录")
    parser.add_argument("--root", help="resource root; defaults to the file's parent or source directory")
    parser.add_argument("--entry", help="entry HTML path relative to the resource root")
    parser.add_argument("--name", help="human-readable name used in the unique Site ID")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    server = subparsers.add_parser("server", help="上传到内置内网服务器（通过部署 API）")
    add_publish_arguments(server)
    server.add_argument("--public-base-url")
    server.add_argument(
        "--update",
        action="store_true",
        help="原地更新该来源上次发布的站点（URL 保持不变，已传播的链接继续有效）",
    )
    server.add_argument("--site-id", help="原地更新指定站点（优先于 --update 的自动匹配）")
    server.add_argument(
        "--no-index",
        action="store_true",
        help="资源包发布时不生成资源索引页（单文件发布生效；目录发布必须生成索引页）",
    )
    server.set_defaults(handler=publish_server)

    remove_parser = subparsers.add_parser("remove-server", help="删除指定服务器站点（破坏性操作）")
    remove_parser.add_argument("site_id")
    remove_parser.add_argument("--confirm-site-id", required=True)
    remove_parser.set_defaults(handler=remove_server)

    sites_parser = subparsers.add_parser("server-sites", help="列出服务器上由当前 token 部署的站点")
    sites_parser.set_defaults(handler=server_sites)

    admin_parser = subparsers.add_parser("admin-url", help="打印服务器管理后台地址（需要管理员 token）")
    admin_parser.set_defaults(handler=admin_url)

    tls_parser = subparsers.add_parser("tls-status", help="检查公开域名的 HTTPS 证书、443 服务与 80 跳转")
    tls_parser.add_argument("--host", help=f"要探测的域名（默认 {DEFAULT_PUBLIC_BASE_URL}）")
    tls_parser.add_argument("--port", type=int, default=443)
    tls_parser.set_defaults(handler=tls_status)

    config_parser = subparsers.add_parser("config-server", help="配置部署 API 访问（保存 base_url 与 token）")
    config_parser.add_argument("--base-url", required=True, help="例如 http://10.41.0.2:41740")
    config_parser.add_argument("--token", required=True, help="自己的部署 token")
    config_parser.add_argument("--http-port", type=int, help="静态服务端口（默认由 base-url 端口推导）")
    config_parser.set_defaults(handler=config_server)

    status_parser = subparsers.add_parser("status", help="查看本 skill 已部署的站点缓存")
    status_parser.set_defaults(handler=status)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        adopted = adopt_legacy_state()
        if adopted:
            print(f"提示: {safe_display(adopted)}", flush=True)
        return int(args.handler(args))
    except PublishError as exc:
        print(f"错误: {safe_display(exc)}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"错误: {safe_display(exc)}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Interrupted.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
