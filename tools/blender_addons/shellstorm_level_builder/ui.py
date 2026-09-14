"""3D 视图侧栏面板：场景、组件库、组件参数、吸附对齐、预览统计和资产包。"""

import bpy
from bpy.types import Panel

from . import snapping
from .catalog import COMPONENT_BY_ID, components_by_group
from .operators import anchor_label, anchor_mode, selected_component_roots
from .snapping import AXES_ITEMS, SIDE_ITEMS


def box_size(bounds):
    low, high = bounds
    size = high - low
    return f"{size.x:.3f} × {size.y:.3f} × {size.z:.3f}"


class SSLB_PT_Main(Panel):
    bl_label = "ShellStorm 关卡搭建"
    bl_idname = "SSLB_PT_main"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "ShellStorm"

    def draw(self, context):
        layout = self.layout
        settings = context.scene.sslb
        layout.prop(settings, "block_id")
        layout.prop(settings, "scene_slug")
        layout.prop(settings, "package_version")
        layout.prop(settings, "origin_mode")
        row = layout.row(align=True)
        row.prop(settings, "grid_size")
        row.prop(settings, "height_step")
        layout.prop(settings, "snap_on_create")
        layout.operator("sslb.setup_scene", icon="OUTLINER_COLLECTION")
        box = layout.box()
        box.label(text=f"布局统计：{settings.layout_summary}", icon="INFO")


class SSLB_PT_Library(Panel):
    bl_label = "组件库"
    bl_idname = "SSLB_PT_library"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "ShellStorm"
    bl_parent_id = "SSLB_PT_main"

    def draw(self, context):
        layout = self.layout
        settings = context.scene.sslb
        search = settings.search
        layout.prop(settings, "search", text="", icon="VIEWZOOM")
        shown = 0
        for group, items in components_by_group():
            matched = [
                item
                for item in items
                if not search or search.lower() in f"{item['name']} {item['id']}".lower()
            ]
            if not matched:
                continue
            layout.label(text=group, icon="COLLECTION_NEW")
            for item in matched:
                operator = layout.operator("sslb.add_component", text=item["name"], icon=item["icon"])
                operator.component_type = item["id"]
                shown += 1
        if not shown:
            layout.label(text="没有匹配组件", icon="INFO")
        layout.separator()
        layout.operator("sslb.scan_library", icon="FILE_REFRESH")
        layout.label(text=settings.library_summary, icon="INFO")
        library = [
            item
            for item in context.scene.sslb_library
            if not search or search.lower() in f"{item.display_name} {item.asset_slug} {item.category}".lower()
        ]
        if library:
            layout.label(text=f"项目资产包 · {len(library)}", icon="ASSET_MANAGER")
            for item in library[:40]:
                operator = layout.operator(
                    "sslb.append_library_asset", text=item.display_name, icon="APPEND_BLEND"
                )
                operator.manifest_path = item.manifest_path
            if len(library) > 40:
                layout.label(text="结果超过 40 项，请用搜索缩小范围")
        elif context.scene.sslb_library:
            layout.label(text="没有匹配的项目资产包", icon="VIEWZOOM")
        else:
            layout.label(text="先填项目根目录再扫描；清单需含源 .blend 与 Collection", icon="ERROR")


class SSLB_PT_Component(Panel):
    bl_label = "组件参数"
    bl_idname = "SSLB_PT_component"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "ShellStorm"
    bl_parent_id = "SSLB_PT_main"
    bl_options = {"DEFAULT_CLOSED"}

    @classmethod
    def poll(cls, context):
        return bool(selected_component_roots(context))

    def draw(self, context):
        layout = self.layout
        settings = context.scene.sslb
        roots = selected_component_roots(context)
        active = context.active_object
        root = next((item for item in roots if item is active), roots[0])
        props = root.sslb
        layout.label(text=root.name, icon="OBJECT_DATA")
        box = layout.box()
        box.label(text=f"锚点：{anchor_label(anchor_mode(settings, props.component_type))}（物体原点）")
        bounds = snapping.world_bounds([root])
        if bounds:
            low, high = bounds
            box.label(text=f"尺寸 {box_size(bounds)} m")
            box.label(text=f"底面中心 ({low.x:.3f}, {low.y:.3f}, {low.z:.3f})")
        layout.prop(props, "asset_id")
        item = COMPONENT_BY_ID.get(props.component_type)
        if item:
            for name in item["params"]:
                layout.prop(props, name)
        row = layout.row(align=True)
        row.operator("sslb.rebuild_component", icon="FILE_REFRESH")
        row.operator("sslb.reanchor", text="重设锚点", icon="PIVOT_CURSOR")
        if len(roots) > 1:
            layout.label(text=f"参数将应用到选中的 {len(roots)} 个组件", icon="DUPLICATE")
        layout.label(text="网格可直接进入编辑模式深化", icon="EDITMODE_HLT")
        if active is not None and getattr(active, "instance_type", "NONE") == "COLLECTION":
            layout.operator("sslb.make_editable", icon="DUPLICATE")


class SSLB_PT_Snap(Panel):
    bl_label = "吸附与对齐"
    bl_idname = "SSLB_PT_snap"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "ShellStorm"
    bl_parent_id = "SSLB_PT_main"

    def draw(self, context):
        layout = self.layout
        settings = context.scene.sslb
        tools = context.scene.tool_settings
        row = layout.row(align=True)
        row.prop(tools, "use_snap", text="原生吸附", toggle=True)
        elements = layout.row(align=True)
        elements.prop_enum(tools, "snap_elements", "VERTEX")
        elements.prop_enum(tools, "snap_elements", "EDGE")
        elements.prop_enum(tools, "snap_elements", "FACE")
        elements.prop_enum(tools, "snap_elements", "INCREMENT")
        row = layout.row(align=True)
        row.prop(tools, "snap_target", text="")
        row.prop(tools, "use_snap_grid_absolute", text="绝对网格", toggle=True)
        layout.operator("sslb.configure_snap", icon="SNAP_ON")
        layout.separator()
        layout.operator("sslb.snap_to_grid", icon="SNAP_GRID")
        layout.label(text="贴齐到活动对象（先选活动对象，再选其他）", icon="SNAP_FACE")
        grid = layout.grid_flow(row_major=True, columns=3, even_columns=True, align=True)
        for key, label, _tip in SIDE_ITEMS:
            operator = grid.operator("sslb.snap_adjacent", text=label)
            operator.side = key
        layout.label(text="对齐轴", icon="ORIENTATION_GLOBAL")
        axes = layout.grid_flow(row_major=True, columns=5, even_columns=True, align=True)
        for key, label, _tip in AXES_ITEMS:
            operator = axes.operator("sslb.align_to_active", text=label)
            operator.axes = key
        layout.separator()
        layout.operator("sslb.move_to_cursor", icon="CURSOR")
        layout.label(text=f"网格 {settings.grid_size:g}m / 标高步进 {settings.height_step:g}m", icon="GRID")


class SSLB_PT_Preview(Panel):
    bl_label = "预览与统计"
    bl_idname = "SSLB_PT_preview"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "ShellStorm"
    bl_parent_id = "SSLB_PT_main"
    bl_options = {"DEFAULT_CLOSED"}

    def draw(self, context):
        layout = self.layout
        settings = context.scene.sslb
        row = layout.row(align=True)
        row.prop(settings, "use_palette", toggle=True)
        row.prop(settings, "show_wireframe", toggle=True)
        layout.label(text="两个开关即时生效；手动改过材质的对象可用下方按钮恢复", icon="INFO")
        layout.operator("sslb.refresh_appearance", icon="MATERIAL")
        layout.separator()
        layout.operator("sslb.measure_layout", icon="DRIVER_DISTANCE")
        layout.prop(settings, "show_annotations", toggle=True)
        row = layout.row(align=True)
        row.operator("sslb.build_annotations", text="生成标注", icon="FONT_DATA")
        row.operator("sslb.clear_annotations", text="清除标注", icon="TRASH")
        layout.separator()
        layout.operator("sslb.setup_top_camera", icon="CAMERA_DATA")
        layout.operator("sslb.render_top_view", icon="RENDER_STILL")
        layout.prop(settings, "render_root")


class SSLB_PT_Packages(Panel):
    bl_label = "资产包与目录"
    bl_idname = "SSLB_PT_packages"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "ShellStorm"
    bl_parent_id = "SSLB_PT_main"
    bl_options = {"DEFAULT_CLOSED"}

    def draw(self, context):
        layout = self.layout
        settings = context.scene.sslb
        layout.prop(settings, "package_name")
        layout.prop(settings, "package_slug")
        layout.prop(settings, "package_category")
        layout.operator("sslb.create_package", icon="NEWFOLDER")
        layout.label(text="归入资产包后对象移入末级包，包内即独立导出边界", icon="INFO")
        layout.separator()
        layout.prop(settings, "project_root")
        layout.prop(settings, "package_root")
        layout.prop(settings, "validate_before_sync")
        row = layout.row(align=True)
        row.operator("sslb.validate_structure", icon="CHECKMARK")
        row.operator("sslb.sync_manifests", icon="EXPORT")


CLASSES = (
    SSLB_PT_Main,
    SSLB_PT_Library,
    SSLB_PT_Component,
    SSLB_PT_Snap,
    SSLB_PT_Preview,
    SSLB_PT_Packages,
)
