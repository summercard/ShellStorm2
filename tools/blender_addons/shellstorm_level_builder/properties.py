"""插件属性：场景级配置、组件参数和项目资产库条目。"""

import bpy
from bpy.props import (
    BoolProperty,
    CollectionProperty,
    EnumProperty,
    FloatProperty,
    IntProperty,
    PointerProperty,
    StringProperty,
)
from bpy.types import PropertyGroup

from .catalog import BLOCKS, CATEGORIES


BLOCK_ITEMS = [(key, name, floor_range) for key, name, floor_range in BLOCKS]
CATEGORY_ITEMS = [(key, name, description) for key, name, description in CATEGORIES]
ORIGIN_ITEMS = (
    ("BOTTOM_CENTER", "底面中心（推荐）", "物体原点在组件底面中心，与游戏内实墙 GLB 一致"),
    ("GAME_ASSET", "对齐游戏资产", "地砖使用厚度居中原点，与运行时地砖包装一致；其余仍为底面中心"),
)


def managed_objects():
    """插件管理的组件对象：带 sslb 参数且声明了组件类型。"""
    return [
        obj
        for obj in bpy.data.objects
        if getattr(obj, "sslb", None) is not None and obj.sslb.component_type
    ]


def _appearance_update(self, context):
    """切换白盒配色/线框后立即生效，无需再点刷新。"""
    from . import materials

    for obj in managed_objects():
        obj.show_wire = self.show_wireframe
        if obj.type == "MESH":
            materials.apply_appearance(
                obj, obj.sslb.component_type, self.use_palette, self.show_wireframe
            )


def _annotations_update(self, context):
    """标注开关直接控制显隐，不触发生成或删除。"""
    visible = bool(self.show_annotations)
    for obj in bpy.data.objects:
        if obj.get("shellstorm_annotation"):
            obj.hide_viewport = not visible
            obj.hide_render = not visible


class SSLB_SceneSettings(PropertyGroup):
    project_root: StringProperty(name="项目根目录", subtype="DIR_PATH")
    render_root: StringProperty(
        name="验收图目录",
        default="source/art/blender/level_builder/renders",
        description="相对项目根目录，或绝对路径",
    )
    block_id: EnumProperty(name="关卡区块", items=BLOCK_ITEMS, default="stairs")
    scene_slug: StringProperty(name="场景标识", default="level_scene")
    package_version: StringProperty(name="资产包版本", default="v001")
    package_root: StringProperty(
        name="清单目录",
        default="source/art/blender/level_builder/component_packages_v001",
        description="相对项目根目录，或绝对路径",
    )
    search: StringProperty(name="搜索组件", default="")
    package_slug: StringProperty(name="资产包 Slug", default="new_package")
    package_name: StringProperty(name="资产包中文名", default="新资产包")
    package_category: EnumProperty(name="资产类别", items=CATEGORY_ITEMS, default="architecture")
    validate_before_sync: BoolProperty(name="同步前验证", default=True)
    origin_mode: EnumProperty(name="组件锚点", items=ORIGIN_ITEMS, default="BOTTOM_CENTER")
    grid_size: FloatProperty(name="平面网格", default=5.0, min=0.0, unit="LENGTH")
    height_step: FloatProperty(name="高度步进", default=0.3, min=0.0, unit="LENGTH")
    snap_on_create: BoolProperty(name="新建组件吸附网格", default=True)
    use_palette: BoolProperty(name="白盒配色", default=True, update=_appearance_update)
    show_wireframe: BoolProperty(name="线框描边", default=True, update=_appearance_update)
    show_annotations: BoolProperty(
        name="显示标注", default=False, update=_annotations_update,
        description="控制顶视图标注与网格底板的显隐；生成与删除使用右侧按钮",
    )
    layout_summary: StringProperty(name="布局统计", default="尚未统计")
    library_summary: StringProperty(name="组件库状态", default="尚未扫描项目资产包")


class SSLB_ComponentSettings(PropertyGroup):
    component_type: StringProperty(name="组件类型")
    asset_id: StringProperty(name="Asset ID")
    width: FloatProperty(name="宽度", default=5.0, min=0.01, unit="LENGTH")
    depth: FloatProperty(name="深度", default=0.3, min=0.01, unit="LENGTH")
    height: FloatProperty(name="高度", default=11.9, min=0.01, unit="LENGTH")
    thickness: FloatProperty(name="厚度", default=0.3, min=0.01, unit="LENGTH")
    opening_width: FloatProperty(name="洞口宽度", default=2.0, min=0.2, unit="LENGTH")
    opening_height: FloatProperty(name="洞口高度", default=2.4, min=0.2, unit="LENGTH")
    step_count: IntProperty(name="级数", default=20, min=1, max=200)
    step_height: FloatProperty(name="级高", default=0.3, min=0.01, unit="LENGTH")
    tread_depth: FloatProperty(name="踏步深度", default=0.75, min=0.01, unit="LENGTH")
    railing_height: FloatProperty(name="栏杆高度", default=1.1, min=0.1, unit="LENGTH")


class SSLB_LibraryItem(PropertyGroup):
    display_name: StringProperty()
    asset_slug: StringProperty()
    category: StringProperty()
    source_blend: StringProperty(subtype="FILE_PATH")
    collection_name: StringProperty()
    manifest_path: StringProperty(subtype="FILE_PATH")


CLASSES = (SSLB_SceneSettings, SSLB_ComponentSettings, SSLB_LibraryItem)


def register_properties():
    bpy.types.Scene.sslb = PointerProperty(type=SSLB_SceneSettings)
    bpy.types.Scene.sslb_library = CollectionProperty(type=SSLB_LibraryItem)
    bpy.types.Object.sslb = PointerProperty(type=SSLB_ComponentSettings)


def unregister_properties():
    del bpy.types.Object.sslb
    del bpy.types.Scene.sslb_library
    del bpy.types.Scene.sslb
