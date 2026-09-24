"""给远征 Boss 房 6 件专属组件 GLB 的 .glb.import 打公共色盘导入契约。

背景：Godot 首次导入 GLB 时生成的 .import 里 import_script/path 为空、
gltf/embedded_image_handling=1。按全库与 scene_facility_shared_palette 契约，必须改成：
  import_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"
  gltf/embedded_image_handling=0

做法与战局 v004 的 bind_v004_palette_imports.py 完全一致：只做两处字符串替换，
不重写文件结构，保持 Godot 生成的其他字段原样；幂等，可重复跑。
.import 行尾必须保持 LF（.gitattributes 已声明 `*.import text eol=lf`）。

运行（必须在 Godot 至少导入过一次、.import 已存在之后）：
  "C:/Users/zhuangmenghong/.workbuddy/binaries/python/versions/3.13.12/python.exe" \
      bind_boss_component_palette_imports.py
"""
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent          # .../common_components/v001/qa


def _find_root(start: Path) -> Path:
    for p in [start, *start.parents]:
        if (p / "project.godot").is_file():
            return p
    raise SystemExit("找不到项目根（缺 project.godot）")


ROOT = _find_root(HERE)
sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))
import godot_runtime_naming as grn  # noqa: E402

EXPEDITION = ROOT / "assets/art/environments/tower_zones/expedition"
COMPONENTS = EXPEDITION / "components" / "common_components"

TARGET_SCRIPT = '"res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"'
EMPTY_SCRIPT = 'import_script/path=""'
WRONG_EMBED = "gltf/embedded_image_handling=1"
RIGHT_EMBED = "gltf/embedded_image_handling=0"

# (slug, 出包子目录) —— 本轮 6 件，每个 slug 独占同名子目录。
TARGETS = [
    ("base_floor_base", "base_floor_base"),
    ("main_fault_screen", "main_fault_screen"),
    ("heavy_conduits", "heavy_conduits"),
    ("north_wall_typography", "north_wall_typography"),
    ("south_floor_marking", "south_floor_marking"),
    ("debris_00", "debris_00"),
]


def main() -> int:
    results = {}
    for slug, sub in TARGETS:
        glb = COMPONENTS / sub / grn.visual_glb_name(slug)
        imp = Path(str(glb) + ".import")
        if not glb.is_file():
            raise SystemExit(f"缺少 GLB（先跑导出脚本）: {glb}")
        if not imp.is_file():
            raise SystemExit(f"缺少 .import（先跑 godot --headless --import）: {imp}")

        # 必须字节级读写：Path.write_text 在 Windows 会把 \n 翻成 \r\n，
        # 而 Godot 生成 .import 时坚持写 LF（.gitattributes 也钉了 eol=lf）。
        text = imp.read_bytes().decode("utf-8")
        original = text
        text = text.replace(EMPTY_SCRIPT, f"import_script/path={TARGET_SCRIPT}")
        text = text.replace(WRONG_EMBED, RIGHT_EMBED)

        if text == original:
            results[slug] = "unchanged"
            print(f"SKIP {slug}: 契约已就位（幂等）")
            continue

        imp.write_bytes(text.encode("utf-8"))
        results[slug] = "patched"
        print(f"PATCHED {slug} -> {imp}")

    failures = []
    for slug, sub in TARGETS:
        imp = Path(str(COMPONENTS / sub / grn.visual_glb_name(slug)) + ".import")
        text = imp.read_bytes().decode("utf-8")
        if f"import_script/path={TARGET_SCRIPT}" not in text:
            failures.append(f"{slug}: import_script/path 未指向公共色盘后处理脚本")
        if RIGHT_EMBED not in text:
            failures.append(f"{slug}: gltf/embedded_image_handling 不是 0")
        if WRONG_EMBED in text:
            failures.append(f"{slug}: 仍残留 embedded_image_handling=1")
        raw = imp.read_bytes()
        crlf = raw.count(b"\r\n")
        bare = raw.count(b"\n") - crlf
        if crlf != 0 or bare == 0:
            failures.append(f"{slug}: .import 行尾不是纯 LF（crlf={crlf} bareLF={bare}）")
    if failures:
        for f in failures:
            print(f"FAIL {f}")
        print("BIND_BOSS_COMPONENT_PALETTE_IMPORTS_FAIL")
        return 1

    print("BIND_REPORT " + str(results))
    print(f"BIND_BOSS_COMPONENT_PALETTE_IMPORTS_OK total={len(TARGETS)} "
          f"patched={sum(1 for v in results.values() if v == 'patched')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
