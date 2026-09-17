"""Godot 运行资产命名契约 —— 唯一定义处。

规则（见 assets/art/3D模型资产目录与命名规范.md §坐标与替换契约）
  - `components/` 与 `runtime/` 的**文件名与目录名不含版本号**。
  - Godot 侧替换只有「覆盖同路径同名文件」一种方式；不派生新文件、不新建版本目录。
  - 版本号只属于 `source/`、`asset_manifest.json`、资产台账版本列、
    Prefab 根节点 `metadata/asset_version`。

导出/构建脚本一律调用本模块拼 Godot 侧路径，禁止在脚本里再写 `f"..._{VERSION}.glb"`。
Blender 脚本导入方式（在算出 ROOT 之后）：

    import sys
    sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))
    import godot_runtime_naming as grn
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# 遗留命名：<名>_v001.glb / <名>_v012.tscn
LEGACY_VERSIONED = re.compile(r"_v\d{3}\.[A-Za-z0-9]+$")


def visual_glb_name(slug: str) -> str:
    """Godot 视觉 GLB 的稳定文件名。"""
    return f"{slug}_visual_top3d.glb"


def root_scene_name(slug: str) -> str:
    """Godot 包装 PackedScene 的稳定文件名。"""
    return f"{slug}_root_top3d.tscn"


def legacy_versioned_files(directory: Path, *, recursive: bool = False) -> list[Path]:
    """列出目录下仍是旧命名（带 `_vNNN` 后缀）的运行资产文件。

    运行资产通常落在 `<套件>/<slug>/<文件>` 这一层，所以调用方多半需要
    `recursive=True`（见 guard_no_legacy_versioned 的默认值）。
    """
    if not directory.is_dir():
        return []
    it = directory.rglob("*") if recursive else directory.iterdir()
    return sorted(p for p in it if p.is_file() and LEGACY_VERSIONED.search(p.name))


def guard_no_legacy_versioned(
    directory: Path, *, script: str, allow: bool = False, recursive: bool = True
) -> None:
    """存量去版本未完成时直接失败，避免稳定名与旧版本名同时在库里。

    默认递归：资产在 `<套件>/<slug>/` 之下，只看一层会漏掉全部文件。
    `--allow-legacy-versioned` 用于 P6 未完成期间的重跑；默认拒绝。
    """
    if allow:
        return
    legacy = legacy_versioned_files(directory, recursive=recursive)
    if not legacy:
        return
    shown = ", ".join(str(p.relative_to(directory)) for p in legacy[:5])
    more = f" 等 {len(legacy)} 个" if len(legacy) > 5 else ""
    raise SystemExit(
        f"{script}: {directory} 下仍存在旧命名运行资产（{shown}{more}）。\n"
        f"  去版本化把路径固定为 <套件>/<slug>/<slug>_visual_top3d.glb|_root_top3d.tscn，\n"
        f"  现在重跑会在库里同时留下两套文件名。先完成存量重命名（执行计划 P6），\n"
        f"  或确知影响时显式加 --allow-legacy-versioned。"
    )


def version_from_argv(default: str) -> str:
    """取 `--version vNNN`；Blender 透传的参数可能出现在 `--` 之后。"""
    argv = [a for a in sys.argv if a != "--"]
    for i, token in enumerate(argv):
        if token == "--version" and i + 1 < len(argv):
            return argv[i + 1]
        if token.startswith("--version="):
            return token.split("=", 1)[1]
    return default


def allow_legacy_from_argv() -> bool:
    return "--allow-legacy-versioned" in sys.argv


def require_version_metadata(meta_items, version: str, *, script: str) -> None:
    """manifest / 节点 meta 必须写入本次采用的源版本号。

    GLB 不带版本号后，这三处是唯一溯源入口，缺失即视为丢失溯源。
    """
    pairs = dict(meta_items)
    got = pairs.get("asset_version")
    if got != version:
        raise SystemExit(
            f"{script}: asset_version 元数据缺失或错误（期望 {version!r}，实际 {got!r}）。\n"
            f"  GLB 路径不含版本号，manifest 与节点 metadata/asset_version 是唯一溯源入口，必须有值。"
        )


def split_glb_version(rel: str) -> tuple[str, str | None]:
    """把清单里的 GLB 相对路径拆成（稳定路径，源版本号）。

    `.../env_x_visual_top3d_v003.glb` → (`.../env_x_visual_top3d.glb`, `v003`)
    """
    m = re.search(r"(_v\d{3})(\.[A-Za-z0-9]+)$", rel)
    if not m:
        return rel, None
    return rel[: m.start()] + m.group(2), m.group(1).lstrip("_")


def require_stable_glb(project_root: Path, rel: str, *, script: str) -> tuple[str, str | None]:
    """把清单里的（可能带版本的）GLB 路径归一为稳定路径，并确认它在磁盘上存在。

    拿到稳定路径但文件还没重命名时直接失败，而不是继续引用带版本的旧路径——
    否则生成出来的场景会立刻违反路径恒定契约。
    """
    stable, version = split_glb_version(rel)
    if stable == rel:
        return rel, version
    target = project_root / stable
    legacy = project_root / rel
    if target.is_file():
        return stable, version
    hint = "（旧命名文件仍在磁盘）" if legacy.is_file() else ""
    raise SystemExit(
        f"{script}: 清单里的 GLB 仍是旧命名 {rel}{hint}。\n"
        f"  期望稳定路径 {stable}。请先完成存量去版本重命名（执行计划 P6），再重跑本脚本。"
    )

