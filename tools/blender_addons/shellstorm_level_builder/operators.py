"""插件操作器：组件生成、吸附对齐、预览统计与资产包清单。"""

import json
import math
import re
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace

import bpy
from bpy.props import EnumProperty, StringProperty
from bpy.types import Operator
from mathutils import Vector

from . import geometry, materials, snapping
from .catalog import BLOCKS, CATEGORIES, CATEGORY_BY_LABEL, COMPONENT_BY_ID
from .snapping import AXES_ITEMS, SIDE_ITEMS


ADDON_VERSION = "0.2.0"
ROOT_SUFFIX = "_中文资产管理"
LAYOUT_NAME = "01_白盒布局_可编辑"
SOURCE_NAME = "01_制作组件_按设施拆分"
OUTPUT_NAME = "02_游戏输出_独立资产包"
DISPLAY_NAME = "90_展示与验收_灯光相机"
ANNOTATION_NAME = "91_标注"
TOP_CAMERA_NAME = "SSLB_顶视图相机"
STATS_TEXT_NAME = "ShellStorm_布局统计"
VALIDATION_TEXT_NAME = "ShellStorm_LevelBuilder_Validation"
SKIP_DIRS = {".git", ".godot", "__pycache__", "node_modules"}


def safe_slug(value):
    value = re.sub(r"[^a-z0-9_-]+", "_", (value or "").strip().lower()).strip("_")
    return value or "package"


def block_record(block_id):
    return next((item for item in BLOCKS if item[0] == block_id), BLOCKS[0])


def get_or_create_collection(name, parent=None):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
    owner = parent or bpy.context.scene.collection
    if collection.name not in owner.children:
        owner.children.link(collection)
    return collection


def unlink_object_from_all(obj):
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)


def link_object_only(obj, collection):
    unlink_object_from_all(obj)
    collection.objects.link(obj)


def scene_collections(scene):
    """建立或返回规范集合树，并返回 (根, 布局, 制作源, 游戏输出, 展示, 分类字典)。"""
    settings = scene.sslb
    _, block_name, floor_range = block_record(settings.block_id)
    root = get_or_create_collection(f"{settings.scene_slug}_{block_name}{ROOT_SUFFIX}")
    root["shellstorm_level_root"] = True
    root["block_id"] = settings.block_id
    root["floor_range"] = floor_range
    layout = get_or_create_collection(LAYOUT_NAME, root)
    source = get_or_create_collection(SOURCE_NAME, root)
    source["shellstorm_source_root"] = True
    output = get_or_create_collection(f"{OUTPUT_NAME}_{settings.package_version}", root)
    output["shellstorm_output_root"] = True
    display = get_or_create_collection(DISPLAY_NAME, root)
    get_or_create_collection(ANNOTATION_NAME, display)
    source.hide_render = True
    source.hide_viewport = True
    categories = {}
    for slug, label, _description in CATEGORIES:
        collection = get_or_create_collection(label, output)
        collection["shellstorm_package_category"] = slug
        categories[slug] = collection
    return root, layout, source, output, display, categories


def output_collections(root):
    """所有版本的游戏输出集合，切换版本后旧资产包仍然可见。"""
    return [
        child
        for child in root.children
        if child.get("shellstorm_output_root") or child.name.startswith(OUTPUT_NAME)
    ]


def leaf_packages(scene):
    """遍历全部版本输出下的末级资产包，产出 (分类 slug, 资产包集合)。"""
    root, _layout, _source, output, _display, _categories = scene_collections(scene)
    visited = set()
    for output_collection in [output, *output_collections(root)]:
        if output_collection.name in visited:
            continue
        visited.add(output_collection.name)
        for category in output_collection.children:
            slug = category.get("shellstorm_package_category") or CATEGORY_BY_LABEL.get(
                category.name, CATEGORIES[0][0]
            )
            for collection in category.children:
                if collection.get("shellstorm_asset_package"):
                    yield slug, collection


def collection_objects_recursive(collection):
    return list(collection.all_objects)


def object_hierarchy(root):
    return [root, *list(root.children_recursive)]


def component_root(obj):
    while obj and not obj.get("shellstorm_component"):
        obj = obj.parent
    return obj


def selected_component_roots(context):
    roots = []
    seen = set()
    for obj in context.selected_objects:
        root = component_root(obj) or obj
        if root.name_full in seen:
            continue
        seen.add(root.name_full)
        roots.append(root)
    return roots


def in_source_collection(obj):
    return any(collection.get("shellstorm_source_root") for collection in obj.users_collection)


def whitebox_objects(scene):
    """布局统计与顶视图使用的组件集合：排除制作源、标注、相机和灯光。"""
    root, _layout, _source, _output, _display, _categories = scene_collections(scene)
    objects = []
    for obj in root.all_objects:
        if obj.type != "MESH" or obj.get("shellstorm_annotation") or in_source_collection(obj):
            continue
        objects.append(obj)
    return objects


def framing_objects(scene):
    """顶视图取景范围：组件连同标注与网格底板，保证总尺寸标题不被裁掉。"""
    root, _layout, _source, _output, _display, _categories = scene_collections(scene)
    return [
        obj
        for obj in root.all_objects
        if obj.type in {"MESH", "FONT"} and not in_source_collection(obj)
    ]


def anchor_mode(settings, component_type):
    item = COMPONENT_BY_ID.get(component_type or "")
    game_anchor = (item or {}).get("game_anchor", geometry.BOTTOM_CENTER)
    if settings.origin_mode == "GAME_ASSET":
        return game_anchor
    return geometry.BOTTOM_CENTER


def anchor_label(anchor):
    return "底面中心" if anchor == geometry.BOTTOM_CENTER else "厚度中心"


def resolve_project_path(scene, value):
    project_root = Path(bpy.path.abspath(scene.sslb.project_root or "//"))
    path = Path(value)
    return path if path.is_absolute() else project_root / path


def relative_or_absolute(path, base):
    try:
        return Path(path).resolve().relative_to(Path(base).resolve()).as_posix()
    except ValueError:
        return Path(path).as_posix()


def write_text(name, content):
    text = bpy.data.texts.get(name) or bpy.data.texts.new(name)
    text.clear()
    text.write(content)
    return text


def configure_snap(context):
    """打开 Blender 原生吸附并把视口网格设成项目网格，返回生效的视图数。"""
    settings = context.scene.sslb
    tools = context.scene.tool_settings
    tools.use_snap = True
    tools.snap_elements = {"VERTEX", "INCREMENT"}
    tools.snap_target = "CLOSEST"
    tools.use_snap_align_rotation = True
    tools.use_snap_grid_absolute = True
    tools.use_snap_translate = True
    tools.use_snap_rotate = True
    viewports = 0
    grid = settings.grid_size if settings.grid_size > 0 else 1.0
    for window in context.window_manager.windows:
        for area in window.screen.areas:
            if area.type != "VIEW_3D":
                continue
            for space in area.spaces:
                if space.type != "VIEW_3D" or space.overlay is None:
                    continue
                space.overlay.grid_scale = grid
                space.overlay.grid_subdivisions = 5
                space.overlay.show_ortho_grid = True
                viewports += 1
    return viewports


class SSLB_OT_SetupScene(Operator):
    bl_idname = "sslb.setup_scene"
    bl_label = "建立规范集合"
    bl_options = {"REGISTER", "UNDO"}

    def execute(self, context):
        scene_collections(context.scene)
        context.scene.unit_settings.system = "METRIC"
        context.scene.unit_settings.scale_length = 1.0
        viewports = configure_snap(context)
        self.report(
            {"INFO"},
            f"已建立 ShellStorm2 规范集合，并启用原生吸附与 "
            f"{context.scene.sslb.grid_size:g}m 网格（{viewports} 个视图）",
        )
        return {"FINISHED"}


class SSLB_OT_AddComponent(Operator):
    bl_idname = "sslb.add_component"
    bl_label = "添加关卡组件"
    bl_options = {"REGISTER", "UNDO"}

    component_type: StringProperty()

    def execute(self, context):
        item = COMPONENT_BY_ID.get(self.component_type)
        if not item:
            self.report({"ERROR"}, "未知组件类型")
            return {"CANCELLED"}
        settings = context.scene.sslb
        _root, layout, _source, _output, _display, _categories = scene_collections(context.scene)
        anchor = anchor_mode(settings, self.component_type)
        defaults = SimpleNamespace(**item["defaults"])
        obj = bpy.data.objects.new(
            item["name"], geometry.build_mesh(item["name"], self.component_type, defaults, anchor)
        )
        layout.objects.link(obj)
        obj["shellstorm_component"] = True
        obj["component_type"] = self.component_type
        obj["asset_id"] = item["asset_id"]
        props = obj.sslb
        props.component_type = self.component_type
        props.asset_id = item["asset_id"]
        for name, value in item["defaults"].items():
            setattr(props, name, value)
        location = context.scene.cursor.location.copy()
        if settings.snap_on_create:
            location.x = snapping.snap_value(location.x, settings.grid_size)
            location.y = snapping.snap_value(location.y, settings.grid_size)
            location.z = snapping.snap_value(location.z, settings.height_step)
        obj.location = location
        materials.apply_appearance(obj, self.component_type, settings.use_palette, settings.show_wireframe)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        context.view_layer.objects.active = obj
        self.report(
            {"INFO"},
            f"已添加 {item['name']}；锚点在{anchor_label(anchor)}，使用原生吸附或侧栏吸附按钮摆放",
        )
        return {"FINISHED"}


class SSLB_OT_RebuildComponent(Operator):
    bl_idname = "sslb.rebuild_component"
    bl_label = "应用组件参数"
    bl_options = {"REGISTER", "UNDO"}

    @classmethod
    def poll(cls, context):
        return selected_component_roots(context) != []

    def execute(self, context):
        settings = context.scene.sslb
        rebuilt = 0
        for obj in selected_component_roots(context):
            props = obj.sslb
            if not props.component_type or obj.type != "MESH":
                continue
            anchor = anchor_mode(settings, props.component_type)
            mesh = geometry.build_mesh(obj.name, props.component_type, props, anchor)
            old_mesh = obj.data
            obj.data = mesh
            if old_mesh and old_mesh.users == 0:
                bpy.data.meshes.remove(old_mesh)
            materials.apply_appearance(
                obj, props.component_type, settings.use_palette, settings.show_wireframe
            )
            rebuilt += 1
        if not rebuilt:
            self.report({"ERROR"}, "选中的对象不是插件组件")
            return {"CANCELLED"}
        self.report({"INFO"}, f"已按参数重建 {rebuilt} 个组件")
        return {"FINISHED"}


class SSLB_OT_MakeEditable(Operator):
    bl_idname = "sslb.make_editable"
    bl_label = "转为本地可编辑"
    bl_options = {"REGISTER", "UNDO"}

    @classmethod
    def poll(cls, context):
        active = context.active_object
        return active is not None and getattr(active, "instance_type", "NONE") == "COLLECTION"

    def execute(self, context):
        bpy.ops.object.duplicates_make_real(use_base_parent=True, use_hierarchy=True)
        self.report({"INFO"}, "集合实例已转为本地可编辑对象")
        return {"FINISHED"}


class SSLB_OT_CreatePackage(Operator):
    bl_idname = "sslb.create_package"
    bl_label = "将选中对象归入资产包"
    bl_options = {"REGISTER", "UNDO"}

    def execute(self, context):
        settings = context.scene.sslb
        selected = list(context.selected_objects)
        if not selected:
            self.report({"ERROR"}, "请先选择对象")
            return {"CANCELLED"}
        _root, _layout, _source, _output, _display, categories = scene_collections(context.scene)
        slug = safe_slug(settings.package_slug)
        package = get_or_create_collection(
            f"{settings.package_name}_{slug}_资产包", categories[settings.package_category]
        )
        package["shellstorm_asset_package"] = True
        package["package_id"] = slug
        package["asset_slug"] = slug
        package["display_name"] = settings.package_name
        package["category"] = settings.package_category
        package["version"] = settings.package_version
        objects = []
        seen = set()
        for selected_object in selected:
            root = component_root(selected_object) or selected_object
            for obj in object_hierarchy(root):
                if obj.name_full not in seen:
                    seen.add(obj.name_full)
                    objects.append(obj)
        for obj in objects:
            link_object_only(obj, package)
        self.report({"INFO"}, f"已归入资产包 {package.name}")
        return {"FINISHED"}


def manifest_source(record):
    for key in ("source_blend", "source", "source_blend_path"):
        value = record.get(key)
        if value:
            return value
    return None


def manifest_collection(record):
    for key in (
        "blender_collection",
        "collection",
        "output_collection",
        "editable_collection",
        "game_output_collection",
    ):
        value = record.get(key)
        if value:
            return value
    return None


class SSLB_OT_ScanLibrary(Operator):
    bl_idname = "sslb.scan_library"
    bl_label = "扫描项目资产包"

    def execute(self, context):
        scene = context.scene
        library = scene.sslb_library
        library.clear()
        project_root = Path(bpy.path.abspath(scene.sslb.project_root or "//"))
        if not project_root.exists():
            scene.sslb.library_summary = "项目根目录不存在"
            self.report({"ERROR"}, "项目根目录不存在，请填写项目根目录或先保存 .blend")
            return {"CANCELLED"}
        manifest_total = 0
        missing_fields = 0
        missing_source = 0
        for manifest_path in project_root.rglob("asset_manifest.json"):
            if SKIP_DIRS.intersection(manifest_path.parts):
                continue
            try:
                record = json.loads(manifest_path.read_text(encoding="utf-8"))
            except (OSError, ValueError, UnicodeError):
                continue
            manifest_total += 1
            source_value = manifest_source(record)
            collection_name = manifest_collection(record)
            if not source_value or not collection_name:
                missing_fields += 1
                continue
            source = Path(source_value)
            source = source if source.is_absolute() else project_root / source
            if not source.exists() or source.suffix.lower() != ".blend":
                missing_source += 1
                continue
            item = library.add()
            item.display_name = (
                record.get("display_name") or record.get("name") or manifest_path.parent.name
            )
            item.asset_slug = (
                record.get("asset_slug") or record.get("package_id") or manifest_path.parent.name
            )
            item.category = record.get("category", "未分类")
            item.source_blend = str(source)
            item.collection_name = collection_name
            item.manifest_path = str(manifest_path)
        skipped = missing_fields + missing_source
        scene.sslb.library_summary = (
            f"{len(library)} 个可用 / 共 {manifest_total} 个清单"
            f"（跳过 {skipped}：缺字段 {missing_fields}、源 .blend 缺失 {missing_source}）"
        )
        self.report(
            {"INFO"},
            f"已扫描 {len(library)} 个可追加资产包；跳过 {skipped} 个"
            f"（缺字段 {missing_fields}，源文件缺失 {missing_source}）",
        )
        return {"FINISHED"}


class SSLB_OT_AppendLibraryAsset(Operator):
    bl_idname = "sslb.append_library_asset"
    bl_label = "追加为本地可编辑组件"
    bl_options = {"REGISTER", "UNDO"}

    manifest_path: StringProperty()

    def execute(self, context):
        item = next(
            (entry for entry in context.scene.sslb_library if entry.manifest_path == self.manifest_path),
            None,
        )
        if item is None:
            self.report({"ERROR"}, "组件库记录已失效，请重新扫描")
            return {"CANCELLED"}
        source_path = Path(item.source_blend)
        try:
            with bpy.data.libraries.load(str(source_path), link=False) as (source, target):
                if item.collection_name not in source.collections:
                    raise ValueError(f"源文件中不存在 Collection：{item.collection_name}")
                target.collections = [item.collection_name]
            appended = target.collections[0]
        except Exception as error:
            self.report({"ERROR"}, f"追加失败：{error}")
            return {"CANCELLED"}
        _root, layout, _source, _output, _display, _categories = scene_collections(context.scene)
        if appended.name not in layout.children:
            layout.children.link(appended)
        appended["shellstorm_library_asset"] = True
        appended["asset_slug"] = item.asset_slug
        appended["source_manifest"] = item.manifest_path
        bpy.ops.object.select_all(action="DESELECT")
        for obj in appended.all_objects:
            obj.select_set(True)
        if appended.all_objects:
            context.view_layer.objects.active = appended.all_objects[0]
        self.report({"INFO"}, f"已追加 {item.display_name}；数据为本地副本，可直接编辑")
        return {"FINISHED"}


def validation_issues(scene):
    issues = []
    packages = list(leaf_packages(scene))
    membership = {}
    for _category, package in packages:
        objects = collection_objects_recursive(package)
        if not objects:
            issues.append(f"空资产包：{package.name}")
        for obj in objects:
            membership.setdefault(obj.name_full, []).append(package.name)
    for object_name, owners in membership.items():
        if len(owners) > 1:
            issues.append(f"对象属于多个资产包：{object_name} -> {', '.join(owners)}")
    return packages, issues


class SSLB_OT_ValidateStructure(Operator):
    bl_idname = "sslb.validate_structure"
    bl_label = "验证集合与资产包"

    def execute(self, context):
        packages, issues = validation_issues(context.scene)
        loose = [
            obj.name
            for obj in whitebox_objects(context.scene)
            if not any(
                collection.get("shellstorm_asset_package") for collection in obj.users_collection
            )
        ]
        lines = [
            "SHELLSTORM LEVEL BUILDER VALIDATION",
            f"packages={len(packages)} issues={len(issues)} unassigned={len(loose)}",
            "\n".join(issues) if issues else "OK",
        ]
        if loose:
            lines.append(f"未归入资产包（仅提示）：{'、'.join(sorted(loose)[:20])}")
        write_text(VALIDATION_TEXT_NAME, "\n".join(lines) + "\n")
        self.report(
            {"ERROR" if issues else "INFO"},
            f"验证完成：{len(packages)} 个资产包，{len(issues)} 个问题，{len(loose)} 个未归包组件",
        )
        return {"FINISHED"}


def local_origin_note(settings):
    if settings.origin_mode == "GAME_ASSET":
        return "底面中心，Blender坐标(0,0,0)；地砖按游戏资产厚度居中"
    return "底面中心，Blender坐标(0,0,0)"


class SSLB_OT_SyncManifests(Operator):
    bl_idname = "sslb.sync_manifests"
    bl_label = "同步磁盘清单"

    def execute(self, context):
        scene = context.scene
        settings = scene.sslb
        if not bpy.data.filepath:
            self.report({"ERROR"}, "请先保存当前 .blend，清单必须指向真实源文件")
            return {"CANCELLED"}
        packages, issues = validation_issues(scene)
        if settings.validate_before_sync and issues:
            self.report({"ERROR"}, f"验证失败，未写盘：{issues[0]}")
            return {"CANCELLED"}
        if not packages:
            self.report({"ERROR"}, "没有可同步的资产包，未写盘；请先归入资产包")
            return {"CANCELLED"}
        root = resolve_project_path(scene, settings.package_root)
        project_root = Path(bpy.path.abspath(settings.project_root or "//"))
        source_blend = relative_or_absolute(bpy.data.filepath, project_root)
        catalog = []
        tree = []
        for category, package in sorted(packages, key=lambda entry: (entry[0], entry[1].name)):
            slug = safe_slug(package.get("asset_slug", package.name))
            folder = root / category / slug
            folder.mkdir(parents=True, exist_ok=True)
            objects = collection_objects_recursive(package)
            bounds = snapping.world_bounds(objects)
            if bounds:
                low, high = bounds
                center = [round(value, 6) for value in (low + high) / 2.0]
                dimensions = [round(value, 6) for value in high - low]
            else:
                center, dimensions = [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]
            names = [obj.name for obj in objects]
            manifest = {
                "package_id": package.get("package_id", slug),
                "display_name": package.get("display_name", package.name),
                "asset_slug": slug,
                "category": category,
                "version": package.get("version", settings.package_version),
                "block_id": settings.block_id,
                "source_blend": source_blend,
                "collection": package.name,
                "blender_collection": package.name,
                "root_objects": [obj.name for obj in package.objects if obj.parent is None],
                "object_names": names,
                "objects": names,
                "world_center_m": center,
                "bounding_size_m": dimensions,
                "local_origin": local_origin_note(settings),
                "forward_axis": "Blender -Y",
                "grid_size_m": settings.grid_size,
                "material_roles": sorted(
                    {
                        material.name
                        for obj in objects
                        if obj.type == "MESH"
                        for material in obj.data.materials
                        if material
                    }
                ),
                "has_animation": any(obj.animation_data for obj in objects),
                "has_light": any(obj.type == "LIGHT" for obj in objects),
                "dependencies": [],
                "expected_export": f"{slug}_visual_top3d_v001.glb",
                "collision_status": "not_authored",
                "exported": False,
                "runtime_integrated": False,
                "generator": f"shellstorm_level_builder {ADDON_VERSION}",
                "generated_at": datetime.now().isoformat(timespec="seconds"),
            }
            (folder / "asset_manifest.json").write_text(
                json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
            catalog.append(manifest)
            tree.append(f"{category}/{slug}/asset_manifest.json  {manifest['display_name']}")
        root.mkdir(parents=True, exist_ok=True)
        (root / "catalog.json").write_text(
            json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        (root / "tree.txt").write_text("\n".join(tree) + "\n", encoding="utf-8")
        self.report({"INFO"}, f"已同步 {len(catalog)} 个资产包清单：{root}")
        return {"FINISHED"}


class SSLB_OT_ConfigureSnap(Operator):
    bl_idname = "sslb.configure_snap"
    bl_label = "启用原生吸附与网格"

    def execute(self, context):
        viewports = configure_snap(context)
        settings = context.scene.sslb
        self.report(
            {"INFO"},
            f"已启用顶点/增量吸附与 {settings.grid_size:g}m 视口网格（{viewports} 个视图）",
        )
        return {"FINISHED"}


class SSLB_OT_SnapToGrid(Operator):
    bl_idname = "sslb.snap_to_grid"
    bl_label = "吸附到网格"
    bl_options = {"REGISTER", "UNDO"}

    @classmethod
    def poll(cls, context):
        return bool(context.selected_objects)

    def execute(self, context):
        settings = context.scene.sslb
        moved = 0
        for obj in list(context.selected_objects):
            bounds = snapping.unit_bounds(obj)
            if bounds is None:
                continue
            delta = snapping.grid_delta(bounds, settings.grid_size, settings.height_step)
            if delta.length_squared < 1e-9:
                continue
            for root in snapping.unit_roots(obj):
                snapping.translate_world(root, delta)
            context.view_layer.update()
            moved += 1
        if not moved:
            self.report({"WARNING"}, "所选对象已在网格上")
            return {"FINISHED"}
        self.report(
            {"INFO"},
            f"已吸附 {moved} 个组件到 {settings.grid_size:g}m 网格 / {settings.height_step:g}m 标高",
        )
        return {"FINISHED"}


class SSLB_OT_AlignToActive(Operator):
    bl_idname = "sslb.align_to_active"
    bl_label = "对齐到活动对象"
    bl_options = {"REGISTER", "UNDO"}

    axes: EnumProperty(name="对齐轴", items=AXES_ITEMS, default="XY")

    @classmethod
    def poll(cls, context):
        return context.active_object is not None and len(context.selected_objects) > 1

    def execute(self, context):
        active = context.active_object
        target = snapping.unit_bounds(active)
        if target is None:
            self.report({"ERROR"}, "活动对象没有网格，无法作为对齐基准")
            return {"CANCELLED"}
        moved = 0
        for obj in list(context.selected_objects):
            if obj is active:
                continue
            bounds = snapping.unit_bounds(obj)
            if bounds is None:
                continue
            delta = snapping.align_delta(self.axes, target, bounds)
            if delta.length_squared < 1e-9:
                continue
            for root in snapping.unit_roots(obj):
                snapping.translate_world(root, delta)
            context.view_layer.update()
            moved += 1
        self.report({"INFO"}, f"已按 {self.axes} 对齐 {moved} 个组件到 {active.name}")
        return {"FINISHED"}


class SSLB_OT_SnapAdjacent(Operator):
    bl_idname = "sslb.snap_adjacent"
    bl_label = "贴齐到活动对象"
    bl_options = {"REGISTER", "UNDO"}

    side: EnumProperty(name="贴合方向", items=SIDE_ITEMS, default="X_PLUS")

    @classmethod
    def poll(cls, context):
        return context.active_object is not None and len(context.selected_objects) > 1

    def execute(self, context):
        active = context.active_object
        target = snapping.unit_bounds(active)
        if target is None:
            self.report({"ERROR"}, "活动对象没有网格，无法作为贴合基准")
            return {"CANCELLED"}
        label = next((name for key, name, _tip in SIDE_ITEMS if key == self.side), self.side)
        moved = 0
        for obj in list(context.selected_objects):
            if obj is active:
                continue
            bounds = snapping.unit_bounds(obj)
            if bounds is None:
                continue
            delta = snapping.flush_delta(self.side, target, bounds)
            for root in snapping.unit_roots(obj):
                snapping.translate_world(root, delta)
            context.view_layer.update()
            moved += 1
        self.report({"INFO"}, f"已把 {moved} 个组件贴齐到 {active.name} 的{label}")
        return {"FINISHED"}


class SSLB_OT_MoveToCursor(Operator):
    bl_idname = "sslb.move_to_cursor"
    bl_label = "底面中心移到游标"
    bl_options = {"REGISTER", "UNDO"}

    @classmethod
    def poll(cls, context):
        return bool(context.selected_objects)

    def execute(self, context):
        cursor = context.scene.cursor.location
        moved = 0
        for obj in list(context.selected_objects):
            bounds = snapping.unit_bounds(obj)
            if bounds is None:
                continue
            low, high = bounds
            center = (low + high) / 2.0
            delta = Vector((cursor.x - center.x, cursor.y - center.y, cursor.z - low.z))
            if delta.length_squared < 1e-9:
                continue
            for root in snapping.unit_roots(obj):
                snapping.translate_world(root, delta)
            context.view_layer.update()
            moved += 1
        if not moved:
            self.report({"WARNING"}, "所选组件的底面中心已在游标位置")
            return {"FINISHED"}
        self.report({"INFO"}, f"已把 {moved} 个组件的底面中心放到游标")
        return {"FINISHED"}


class SSLB_OT_Reanchor(Operator):
    bl_idname = "sslb.reanchor"
    bl_label = "重设锚点为底面中心"
    bl_options = {"REGISTER", "UNDO"}

    @classmethod
    def poll(cls, context):
        return bool(context.selected_objects)

    def execute(self, context):
        settings = context.scene.sslb
        changed = 0
        label = anchor_label(geometry.BOTTOM_CENTER)
        for obj in list(context.selected_objects):
            anchor = anchor_mode(settings, obj.sslb.component_type)
            if geometry.reanchor_object(obj, anchor):
                changed += 1
                label = anchor_label(anchor)
        context.view_layer.update()
        if not changed:
            self.report({"WARNING"}, "所选对象的锚点已经符合规则")
            return {"FINISHED"}
        self.report({"INFO"}, f"已把 {changed} 个对象的网格锚点移到{label}，世界坐标未变")
        return {"FINISHED"}


class SSLB_OT_RefreshAppearance(Operator):
    bl_idname = "sslb.refresh_appearance"
    bl_label = "刷新白盒外观"
    bl_options = {"REGISTER", "UNDO"}

    @classmethod
    def poll(cls, context):
        return bool(context.selected_objects)

    def execute(self, context):
        settings = context.scene.sslb
        refreshed = 0
        for obj in list(context.selected_objects):
            if obj.type != "MESH":
                continue
            kind = obj.sslb.component_type or "WALL"
            materials.apply_appearance(obj, kind, settings.use_palette, settings.show_wireframe)
            refreshed += 1
        self.report({"INFO"}, f"已刷新 {refreshed} 个对象的白盒配色与描边")
        return {"FINISHED"}


class SSLB_OT_MeasureLayout(Operator):
    bl_idname = "sslb.measure_layout"
    bl_label = "统计布局尺寸"

    def execute(self, context):
        settings = context.scene.sslb
        objects = whitebox_objects(context.scene)
        lines = ["SHELLSTORM LEVEL BUILDER LAYOUT", f"组件数：{len(objects)}"]
        counts = {}
        for obj in objects:
            kind = obj.sslb.component_type or "未分类"
            counts[kind] = counts.get(kind, 0) + 1
        bounds = snapping.world_bounds(objects)
        summary = f"{len(objects)} 件 · 无网格"
        if bounds:
            low, high = bounds
            size = high - low
            lines.append(
                f"占用范围 X {low.x:.3f}..{high.x:.3f} / Y {low.y:.3f}..{high.y:.3f} "
                f"/ Z {low.z:.3f}..{high.z:.3f}"
            )
            lines.append(f"总尺寸 {size.x:.3f} × {size.y:.3f} × {size.z:.3f} m")
            lines.append(f"底面面积 {size.x * size.y:.2f} m²")
            summary = f"{len(objects)} 件 · {size.x:.1f}×{size.y:.1f}×{size.z:.1f}m"
        for kind in sorted(counts):
            lines.append(f"{kind}: {counts[kind]}")
        lines.append("")
        lines.append("逐组件：名称 | 底面中心 | 尺寸")
        for obj in sorted(objects, key=lambda item: item.name):
            obj_bounds = snapping.world_bounds([obj])
            if obj_bounds is None:
                continue
            low, high = obj_bounds
            size = high - low
            lines.append(
                f"{obj.name} | ({low.x:.3f}, {low.y:.3f}, {low.z:.3f}) | "
                f"{size.x:.3f}×{size.y:.3f}×{size.z:.3f}"
            )
        write_text(STATS_TEXT_NAME, "\n".join(lines) + "\n")
        settings.layout_summary = summary
        if settings.show_annotations and annotations_exist():
            bpy.ops.sslb.build_annotations()
        self.report({"INFO"}, f"布局统计：{summary}（文本块 {STATS_TEXT_NAME}）")
        return {"FINISHED"}


def annotation_collection(scene):
    _root, _layout, _source, _output, display, _categories = scene_collections(scene)
    return get_or_create_collection(ANNOTATION_NAME, display)


def annotations_exist():
    """场景里是否已有插件生成的标注对象。"""
    return any(obj.get("shellstorm_annotation") for obj in bpy.data.objects)


def clear_annotations(collection):
    removed = 0
    for obj in list(collection.objects):
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        removed += 1
        if data is None or data.users:
            continue
        if isinstance(data, bpy.types.Mesh):
            bpy.data.meshes.remove(data)
        elif isinstance(data, bpy.types.Curve):
            bpy.data.curves.remove(data)
    return removed


def add_annotation(
    collection, body, location, material, size=0.6, align="CENTER", valign="CENTER"
):
    curve = bpy.data.curves.new(f"标注_{body[:16]}", type="FONT")
    curve.body = body
    curve.size = size
    curve.align_x = align
    curve.align_y = valign
    curve.materials.append(material)
    obj = bpy.data.objects.new(curve.name, curve)
    obj["shellstorm_annotation"] = True
    obj.show_in_front = True
    collection.objects.link(obj)
    obj.location = location
    return obj


def compact_meters(value):
    """5.00 -> 5，11.90 -> 11.9，0.30 -> 0.3，用于缩短标注文字。"""
    text = f"{value:.2f}".rstrip("0").rstrip(".")
    return text or "0"


def grid_overlay(collection, low, high, grid):
    """生成单对象模块网格底板，用于目视核对模数对齐。"""
    step = grid if grid > 0 else 5.0
    half = min(0.04, step * 0.01)
    x0 = math.floor(low.x / step) * step
    x1 = math.ceil(high.x / step) * step
    y0 = math.floor(low.y / step) * step
    y1 = math.ceil(high.y / step) * step
    z = low.z - 0.05
    vertices = []
    faces = []

    def quad(a, b, c, d):
        base = len(vertices)
        vertices.extend([a, b, c, d])
        faces.append((base, base + 1, base + 2, base + 3))

    value = y0
    while value <= y1 + 1e-6:
        quad(
            (x0, value - half, z), (x1, value - half, z),
            (x1, value + half, z), (x0, value + half, z),
        )
        value += step
    value = x0
    while value <= x1 + 1e-6:
        quad(
            (value - half, y0, z), (value + half, y0, z),
            (value + half, y1, z), (value - half, y1, z),
        )
        value += step
    mesh = bpy.data.meshes.new("SSLB_模块网格_网格")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    if faces:
        mesh.materials.append(materials.ensure_grid_material())
    obj = bpy.data.objects.new("SSLB_模块网格", mesh)
    obj["shellstorm_annotation"] = True
    collection.objects.link(obj)
    return obj


class SSLB_OT_BuildAnnotations(Operator):
    bl_idname = "sslb.build_annotations"
    bl_label = "生成顶视图标注"
    bl_options = {"REGISTER", "UNDO"}

    def execute(self, context):
        settings = context.scene.sslb
        collection = annotation_collection(context.scene)
        clear_annotations(collection)
        objects = whitebox_objects(context.scene)
        if not objects:
            self.report({"ERROR"}, "布局内没有组件可标注")
            return {"CANCELLED"}
        material = materials.ensure_annotation_material()
        grid = settings.grid_size if settings.grid_size > 0 else 5.0
        label_size = min(1.2, max(0.4, grid * 0.12))
        for obj in objects:
            bounds = snapping.world_bounds([obj])
            if bounds is None:
                continue
            low, high = bounds
            size = high - low
            center = (low + high) / 2.0
            kind = obj.sslb.component_type or "OBJECT"
            name = COMPONENT_BY_ID.get(kind, {}).get("name", kind)
            label = (
                f"{name}\n{compact_meters(size.x)}×{compact_meters(size.y)}"
                f"×{compact_meters(size.z)}"
            )
            add_annotation(
                collection,
                label,
                Vector((center.x, center.y, high.z + 0.4)),
                material,
                label_size,
                "CENTER",
                "TOP",
            )
        total = snapping.world_bounds(objects)
        if total:
            low, high = total
            grid_overlay(collection, low, high, settings.grid_size)
            size = high - low
            title = (
                f"{settings.scene_slug} · {len(objects)} 件 · "
                f"{compact_meters(size.x)}×{compact_meters(size.y)}×{compact_meters(size.z)}m"
                f" · 网格 {settings.grid_size:g}m"
            )
            add_annotation(
                collection,
                title,
                Vector((low.x, high.y + 2.0, high.z + 0.2)),
                material,
                max(0.8, label_size * 1.6),
                "LEFT",
            )
        settings.show_annotations = True
        self.report({"INFO"}, f"已生成 {len(objects)} 条组件标注与总尺寸标注")
        return {"FINISHED"}


class SSLB_OT_ClearAnnotations(Operator):
    bl_idname = "sslb.clear_annotations"
    bl_label = "清除标注"
    bl_options = {"REGISTER", "UNDO"}

    def execute(self, context):
        removed = clear_annotations(annotation_collection(context.scene))
        context.scene.sslb.show_annotations = False
        self.report({"INFO"}, f"已清除 {removed} 条标注")
        return {"FINISHED"}


def ensure_top_camera(scene, objects):
    _root, _layout, _source, _output, display, _categories = scene_collections(scene)
    camera = bpy.data.objects.get(TOP_CAMERA_NAME)
    if camera is None or camera.type != "CAMERA":
        camera = bpy.data.objects.new(TOP_CAMERA_NAME, bpy.data.cameras.new(TOP_CAMERA_NAME))
    if camera.name not in display.objects:
        display.objects.link(camera)
    data = camera.data
    data.type = "ORTHO"
    data.clip_start = 0.1
    data.clip_end = 5000.0
    camera.rotation_euler = (0.0, 0.0, 0.0)
    bounds = snapping.world_bounds(objects)
    if bounds:
        low, high = bounds
        center = (low + high) / 2.0
        size = high - low
        aspect = scene.render.resolution_x / max(1, scene.render.resolution_y)
        need_w = max(size.x, 1.0) * 1.08
        need_h = max(size.y, 1.0) * 1.08
        data.ortho_scale = (
            max(need_w, need_h * aspect) if aspect >= 1.0 else max(need_h, need_w / aspect)
        )
        camera.location = (center.x, center.y, high.z + max(10.0, size.z + 10.0))
    return camera


class SSLB_OT_SetupTopCamera(Operator):
    bl_idname = "sslb.setup_top_camera"
    bl_label = "建立顶视相机"
    bl_options = {"REGISTER", "UNDO"}

    def execute(self, context):
        objects = framing_objects(context.scene)
        if not objects:
            self.report({"ERROR"}, "布局内没有组件，无法建立顶视图")
            return {"CANCELLED"}
        camera = ensure_top_camera(context.scene, objects)
        context.scene.camera = camera
        self.report(
            {"INFO"}, f"已建立正交顶视相机 {camera.name}，正交尺寸 {camera.data.ortho_scale:.2f}m"
        )
        return {"FINISHED"}


def render_path(scene):
    settings = scene.sslb
    folder = resolve_project_path(scene, settings.render_root)
    return folder / f"whitebox_{safe_slug(settings.scene_slug)}_{settings.package_version}_top.png"


class SSLB_OT_RenderTopView(Operator):
    bl_idname = "sslb.render_top_view"
    bl_label = "渲染顶视图"

    def execute(self, context):
        scene = context.scene
        if not bpy.data.filepath:
            self.report({"ERROR"}, "请先保存当前 .blend，验收图需要写入项目目录")
            return {"CANCELLED"}
        objects = whitebox_objects(scene)
        if not objects:
            self.report({"ERROR"}, "布局内没有组件，未渲染")
            return {"CANCELLED"}
        scene.camera = ensure_top_camera(scene, framing_objects(scene))
        shading = scene.display.shading
        restore = (
            scene.render.engine,
            scene.render.filepath,
            scene.render.image_settings.file_format,
            scene.render.film_transparent,
            shading.light,
            shading.color_type,
            shading.show_shadows,
            shading.show_object_outline,
            shading.background_type,
            tuple(shading.background_color),
            tuple(shading.object_outline_color),
            getattr(shading, "shadow_intensity", None),
        )
        try:
            scene.render.engine = "BLENDER_WORKBENCH"
            scene.render.image_settings.file_format = "PNG"
            scene.render.film_transparent = False
            shading.light = "STUDIO"
            shading.color_type = "MATERIAL"
            shading.show_shadows = True
            if hasattr(shading, "shadow_intensity"):
                shading.shadow_intensity = 0.30
            shading.show_object_outline = True
            shading.object_outline_color = (0.80, 0.80, 0.80)
            shading.background_type = "VIEWPORT"
            shading.background_color = (0.12, 0.13, 0.15)
            path = render_path(scene)
            path.parent.mkdir(parents=True, exist_ok=True)
            scene.render.filepath = str(path)
            bpy.ops.render.render(write_still=True)
        finally:
            (
                scene.render.engine,
                scene.render.filepath,
                scene.render.image_settings.file_format,
                scene.render.film_transparent,
                shading.light,
                shading.color_type,
                shading.show_shadows,
                shading.show_object_outline,
                shading.background_type,
                background,
                outline,
                intensity,
            ) = restore
            shading.background_color = background
            shading.object_outline_color = outline
            if intensity is not None and hasattr(shading, "shadow_intensity"):
                shading.shadow_intensity = intensity
        self.report({"INFO"}, f"顶视图已写出：{render_path(scene)}")
        return {"FINISHED"}


CLASSES = (
    SSLB_OT_SetupScene,
    SSLB_OT_AddComponent,
    SSLB_OT_RebuildComponent,
    SSLB_OT_MakeEditable,
    SSLB_OT_CreatePackage,
    SSLB_OT_ScanLibrary,
    SSLB_OT_AppendLibraryAsset,
    SSLB_OT_ValidateStructure,
    SSLB_OT_SyncManifests,
    SSLB_OT_ConfigureSnap,
    SSLB_OT_SnapToGrid,
    SSLB_OT_AlignToActive,
    SSLB_OT_SnapAdjacent,
    SSLB_OT_MoveToCursor,
    SSLB_OT_Reanchor,
    SSLB_OT_RefreshAppearance,
    SSLB_OT_MeasureLayout,
    SSLB_OT_BuildAnnotations,
    SSLB_OT_ClearAnnotations,
    SSLB_OT_SetupTopCamera,
    SSLB_OT_RenderTopView,
)
