"""给 100F 天台装饰组件 GLB 的 `.glb.import` 打公共色盘导入契约。

背景（全库契约，见 docs/v0.1/10_资产与内容规范.md）：
Godot **首次**导入 GLB 时生成的 `.import` 里 `import_script/path=""`；而天台装饰件
全部声明 `metadata/preserve_authored_palette = true`（见 runtime/*.tscn），必须改成：
    import_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"
否则新件会**白板**（材质不重绑到唯一色盘），且不触发 albedo_null=0 门禁判据。

⚠️ 漏绑不会报错，只会在实机上是白模 —— 所以本脚本对**全部**天台装饰件都做断言，
   而不只是新加的那件。

⛔ 只动 `import_script/path` 这一行。
   `gltf/embedded_image_handling` **不动**：天台既有 11 件的值是 `1`（Godot 默认），
   全库另有 125 个 `=0` 的件（battle v003/v004 口径）—— 两种取值在本仓库并存，
   且天台 GLB 导出时用 `export_image_format="NONE"`（无内嵌贴图），该开关对它们是
   行为空转。既然空转，就**没有理由**顺手改掉既有 11 件的导入参数、逼它们重导一遍。

做法与 tower_zones/battle/.../qa/bind_v004_palette_imports.py 一致：只做字符串替换，
不重写文件结构，Godot 生成的其他字段保持原样。幂等。

运行（必须在 Godot 至少导入过一次、`.import` 已存在之后）：
  python bind_rooftop_decor_palette_imports_v001.py
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent                  # .../rooftop/source
ROOFTOP = HERE.parent                                   # .../rooftop
COMPONENTS = ROOFTOP / "components"

TARGET_SCRIPT = '"res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"'
EMPTY_SCRIPT = 'import_script/path=""'

# 天台装饰件 slug → GLB 文件名（与 generate_rooftop_decor_prefabs_v001.py 同一份口径）
TARGETS = [
    ("hvac_small", "env_rooftop_ref_hvac_small_top3d.glb"),
    ("hvac_vent", "env_rooftop_ref_hvac_vent_top3d.glb"),
    ("pipe_straight", "env_rooftop_ref_pipe_straight_top3d.glb"),
    ("pipe_elbow", "env_rooftop_ref_pipe_elbow_top3d.glb"),
    ("pipe_tee", "env_rooftop_ref_pipe_tee_top3d.glb"),
    ("pipe_riser", "env_rooftop_ref_pipe_riser_top3d.glb"),
    ("pipe_bracket", "env_rooftop_ref_pipe_bracket_top3d.glb"),
    ("ivy", "env_rooftop_ref_ivy_top3d.glb"),
    ("parapet_ivy", "env_rooftop_ref_parapet_ivy_top3d.glb"),
    ("flowerbox", "env_rooftop_ref_flowerbox_top3d.glb"),
    ("plant_large", "env_rooftop_ref_plant_large_top3d.glb"),
    ("plant_small", "env_rooftop_ref_plant_small_top3d.glb"),
]


def main() -> int:
    results = {}
    for slug, glb_name in TARGETS:
        glb = COMPONENTS / glb_name
        imp = Path(str(glb) + ".import")
        if not glb.is_file():
            print("FAIL %s: 缺少 GLB（先跑导出脚本）: %s" % (slug, glb))
            return 1
        if not imp.is_file():
            print("FAIL %s: 缺少 .import（先跑 godot --headless --import）: %s" % (slug, imp))
            return 1

        text = imp.read_text(encoding="utf-8")
        if EMPTY_SCRIPT not in text:
            results[slug] = "already_bound"
            continue
        imp.write_text(text.replace(EMPTY_SCRIPT, "import_script/path=%s" % TARGET_SCRIPT), encoding="utf-8")
        results[slug] = "patched"
        print("PATCHED %s -> %s" % (slug, imp))

    failures = []
    for slug, glb_name in TARGETS:
        imp = Path(str(COMPONENTS / glb_name) + ".import")
        text = imp.read_text(encoding="utf-8")
        if "import_script/path=%s" % TARGET_SCRIPT not in text:
            failures.append("%s: import_script/path 未指向公共色盘后处理脚本" % slug)
        if EMPTY_SCRIPT in text:
            failures.append("%s: 仍残留 import_script/path=\"\"" % slug)
        if "gltf/embedded_image_handling=1" not in text:
            failures.append("%s: gltf/embedded_image_handling 偏离天台既有口径（应为 1）" % slug)
    if failures:
        for item in failures:
            print("FAIL", item)
        print("BIND_ROOFTOP_DECOR_PALETTE_IMPORTS_FAIL")
        return 1

    print("BIND_REPORT " + str(results))
    print("BIND_ROOFTOP_DECOR_PALETTE_IMPORTS_OK total=%d patched=%d" % (
        len(TARGETS), sum(1 for value in results.values() if value == "patched")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
