"""校验：运行时场景不得引用 export_presets.cfg 会排除掉的文件。

背景（2026-10-12 事故）：
    `skyline08_existing_material_bind.gd` 是**运行时**材质绑定脚本（@tool + _enter_tree
    在非编辑器分支也会执行），却被放在 `tools/asset_pipeline/` 下。而导出预设的
    `exclude_filter` 含 `tools/*` ⇒ 该脚本不进包 ⇒ 252 个 skyline_08 组件在导出后
    加载失败 ⇒ `TowerDescent3D.tscn` 加载失败 ⇒ `change_scene_to_file` 返回
    ERR_CANT_OPEN ⇒ 启动画面显示「启动失败：Can't open」。

    编辑器内运行一切正常（直读磁盘），只有导出后才炸 —— 属典型的"隐形契约无断言"。

判据：
    场景 `.tscn` / `.tres` 里的 `[ext_resource ... path="res://<p>" ...]` 是**硬加载**；
    若 `<p>` 命中了导出排除规则，则导出包内必然缺文件。本脚本把这条判据变成门禁。

用法：
    python scripts/check_export_runtime_refs.py            # 检查
    python scripts/check_export_runtime_refs.py --check     # 同上（CI/验收别名）

退出码：0 = 无命中；1 = 存在会被排除的运行时引用。
"""
import argparse
import fnmatch
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from configure_export_boundaries import EXCLUDES  # 单一正本：排除规则只此一处

EXCLUDE_RULES = [r for r in EXCLUDES.split(",") if r]
SCAN_ROOTS = ("assets", "src", "scenes")
SCAN_EXTS = (".tscn", ".tres")
EXT_RESOURCE_RE = re.compile(r'\[ext_resource[^\]]*path="res://([^"]+)"')


def excluded_by(path: str) -> str | None:
    """返回命中的排除规则；未命中返回 None。

    用 fnmatch 语义（`*` 跨 `/`），与 Godot 内部 String::matchn 的行为一致 ——
    所以 `tools/*` 会命中 `tools/asset_pipeline/x.gd`，这正是事故的成因。
    """
    for rule in EXCLUDE_RULES:
        if fnmatch.fnmatch(path, rule):
            return rule
    return None


def scan() -> dict[tuple[str, str], list[str]]:
    hits: dict[tuple[str, str], list[str]] = {}
    for root_name in SCAN_ROOTS:
        root = ROOT / root_name
        if not root.is_dir():
            continue
        for ext in SCAN_EXTS:
            for scene in root.rglob("*" + ext):
                try:
                    text = scene.read_text(encoding="utf-8", errors="ignore")
                except OSError:
                    continue
                for match in EXT_RESOURCE_RE.finditer(text):
                    target = match.group(1)
                    rule = excluded_by(target)
                    if rule is not None:
                        key = (rule, target)
                        hits.setdefault(key, []).append(
                            str(scene.relative_to(ROOT)).replace("\\", "/")
                        )
    return hits


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="CI/验收别名，行为相同")
    parser.parse_args()

    hits = scan()
    if not hits:
        print("EXPORT_RUNTIME_REFS_OK")
        return 0

    print("EXPORT_RUNTIME_REFS_VIOLATION")
    print(
        "以下运行时场景引用的文件会被 export_presets.cfg 的 exclude_filter 排除，"
        "导出后必然加载失败："
    )
    for (rule, target), sources in sorted(hits.items(), key=lambda kv: -len(kv[1])):
        print(f"\n  [rule] {rule}")
        print(f"  [dep ] res://{target}")
        print(f"  [refs] {len(sources)} 个场景，例如：")
        for src in sources[:3]:
            print(f"         {src}")
        if len(sources) > 3:
            print(f"         … 另有 {len(sources) - 3} 个")
    print(
        "\n修法：把被引用的文件移到不被排除的目录（运行时资产放 src/ 或 assets/art/…/runtime/，"
        "不要放 tools/、scripts/、docs/、tests/），再同步所有引用处与生成脚本。"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
