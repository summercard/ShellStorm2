"""派生塔楼 A 套 5m 门扇模块（v001）：把战局通用组件库的「door_5m_通用包」翻到塔楼 A 套。

源（只读，绝不修改）：
    assets/art/environments/tower_zones/battle/source/common_components/v006/
        env_battle_common_components_source_v006.blend
        -> collection `door_5m_通用包`
        -> ROOT 空物体 `ROOT_door_5m_通用组件`
             + mesh `door_5m_门扇_输出`      （5352 顶点 / 4652 面，材质角色 01/02/03）
             + mesh `door_5m_UI灯光_柔和自发光`（432 顶点 / 468 面，材质角色 04）

派生输出（带版本，塔楼区自己持有）：
    assets/art/environments/tower_descent_3d/source/door_leaf_5m/
        env_tower_door_leaf_5m_source_v001.blend

运行时输出（稳定路径，就地覆盖，名字里不带版本）：
    assets/art/environments/tower_descent_3d/components/
        env_tower_door_leaf_5m_top3d.glb

每一步变换为什么必须有（都是实测出来的，不是假设）：

  * 源 ROOT 空物体自述 front_direction="+Y"，两个 mesh 也以 Blender +Y 朝前。
    Godot 的 glTF 导入把 Blender (x, y, z) 映成 Godot (x, z, -y)，于是「+Y 朝前」
    会落到 Godot -Z；而塔楼 A 套硬要求 forward_axis="+Z"
    （assets/art/props/dungeon_3d/qa/verify_tower_module_prefabs.gd
    EXPECTED_FORWARD_AXIS）。绕 Blender Z 转 180° 把正面挪到 -Y -> Godot +Z，
    与 A 套门墙（装甲门禁与交互槽都在 +Z）共用同一条朝向约定。

  * 门扇美术在厚度轴上是对称的（实测：朝 +Y 的面 1650 个、朝 -Y 的面 1650 个，
    厚度包络 ±0.09 精确居中 —— 源侧 qa/verify_door_anchor_v006.py 也把
    「Y 中心 == 0」当作门扇的锚点契约）。也就是说 180° 翻转对当前外观是恒等变换；
    之所以照做，是为了与 A 套门墙同约定：将来美术一旦做成一面对一面空（把手、
    门禁），代码侧不必再按房间方位补 180°。

  * 源 ROOT 空物体坐在世界 (2.6, -69.344398, 0.0) —— 该批源把 25 个组件摆在一条
    展示阵列上，偏移是阵列位置、不是资产语义。Godot 侧 RoomDoor3D 会 instantiate
    整棵 Prefab 并把视觉挂到 DoorPanel 下，任何写进 glTF 根节点的非恒等变换都会
    把门扇推离门框约 69m。所以偏移必须烘焙进顶点数据（transform_apply）并把空物体
    丢掉，让导出根节点正好是 T=0 / R=恒等 / S=1。

  * 两个 mesh 合并成一个：门扇在运行时是逐实例化的一棵子树（per_instance_prefab），
    单节点单 Mesh 让包络、材质角色与替换成本都可预测；「场景级多 mesh」只会让
    包络合并逻辑与角色列表漂移，对替换美术没有收益。

  * 世界空间朝下的面（法线 z < -0.5）删除，对齐本项目基地设施与 A 套实墙的既有先例
    （scripts/blender/export_base99_wall_content_v021.py、
    source/wall_height12/export_env_tower_wall_solid_5m_v004.py）。谓词与偏航无关，
    因此在旋转之后施加。剔除必须放在三角化之后：n-gon 存的法线是各角平均，先剔会
    把背朝下的三角形留下来（A 套实墙实测：先剔残留 11 个隐藏面，三角化后再剔为 0）。
    本件实测剔除 983/5120 面，但只占 **4.2% 表面积**（全是被面板遮住的背朝下面）。
    保留该步前后同机位渲染逐像素一致（_scratch/door_cull_{source,derived}_*.png），
    因此这不是「删了能看见的东西」；A 套实墙的同一比例是 17% 面 / 未知面积，
    可见「面数占比高」在这种造型里是常态，判据要看表面积与实拍。

关于包络的一个事实（已在断言里钉死）：门扇最低点在组件原点**上方 8mm**，
这是美术原始几何 —— 关闭的门扇不该擦地。派生只负责翻朝向、不负责改尺寸，
因此如实声明 0.008..2.5，而不是把几何压到 0。

运行：
    SS_DOOR_LEAF_PHASE=derive  blender --factory-startup --background \
        --python export_env_tower_door_leaf_5m_v001.py
    SS_DOOR_LEAF_PHASE=export  blender --factory-startup --background \
        --python export_env_tower_door_leaf_5m_v001.py
"""

import json
import math
import os
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix

ASSET_ID = "ENV-TOWER-DOOR-LEAF-5M"
ASSET_VERSION = "v001"
NODE_NAME = "ENV_TOWER_DOOR_LEAF_5M"
MESH_NAME = "ENV_TOWER_DOOR_LEAF_5M_Mesh"

SOURCE_PACKAGE = "door_5m_通用包"
SOURCE_COMPONENT = "ROOT_door_5m_通用组件"
SOURCE_BODY = "door_5m_门扇_输出"
SOURCE_EMISSIVE = "door_5m_UI灯光_柔和自发光"
SOURCE_COMPONENT_ASSET_VERSION = "v006"

# 四个共享色盘角色。03_清漆反光 在本件只有 52 个面（门把手类的点缀），
# 若被朝下面剔除误伤就会消失，所以下面只硬断言 01/02 必在，其余按实际报出。
ROLE_METAL = "01_精工金属_紫色骨架"
ROLE_MATTE = "02_细腻哑光_青绿大面"
ROLE_ACCENT = "03_清漆反光_紫粉点缀"
ROLE_EMISSIVE = "04_柔和自发光_UI灯光"
EXPECTED_ROLES = {ROLE_METAL, ROLE_MATTE, ROLE_ACCENT, ROLE_EMISSIVE}
REQUIRED_ROLES = {ROLE_METAL, ROLE_MATTE}

DOWN_FACE_NORMAL_Z = -0.5

# 门扇的几何契约（Godot 空间，底面中心原点）：
#   宽 2.2m（±1.1，左右对称）· 高 0.008..2.5m · 厚 0.18m（厚度轴精确居中 ±0.09）
# 高度与宽度取自 TowerGeometry3D.DOOR_CLEAR_HEIGHT_M / DOOR_CLEAR_WIDTH_M。
#
# 底边为什么是 0.008 而不是 0：这是美术的原始几何，实测门扇最低点悬在组件原点上方
# 8mm。一扇关闭的门扇本来就不该擦到地面，这属于美术意图；派生脚本的职责是把资产
# 翻到 A 套朝向，不是改写尺寸。因此这里**如实声明**实测包络，而不是把几何压到 0。
# 这与 A 套门墙的既有做法一致：门墙结构盒声明 5×11.9×0.3，可视包络如实写 5×12.04×0.43
# （装饰门框向下探出 0.14m），两个包络刻意分离、各自诚实。
# 8mm 相对 2.5m 门高是 0.3%，玩家不可见；但它必须被登记，
# 否则替换美术时无从判断「底面到底对不对」。
GODOT_MIN = [-1.1, 0.008, -0.09]
GODOT_MAX = [1.1, 2.5, 0.09]
# 底边允许的区间：不得低于原点（会扎进地面），也不得高于 2cm（那就不是「底面中心」了）。
LEAF_BOTTOM_MIN_M = -0.001
LEAF_BOTTOM_MAX_M = 0.02
BOUNDS_TOLERANCE_M = 0.002

SCRIPT_DIR = Path(__file__).resolve().parent
TOWER_DIR = SCRIPT_DIR.parents[1]
PROJECT = SCRIPT_DIR.parents[5]

SOURCE_BLEND = (
    PROJECT
    / "assets/art/environments/tower_zones/battle/source/common_components/v006"
    / "env_battle_common_components_source_v006.blend"
)
OUTPUT_BLEND = SCRIPT_DIR / ("env_tower_door_leaf_5m_source_%s.blend" % ASSET_VERSION)
GLB_OUTPUT = TOWER_DIR / "components" / "env_tower_door_leaf_5m_top3d.glb"
MANIFEST = SCRIPT_DIR / ("env_tower_door_leaf_5m_%s_manifest.json" % ASSET_VERSION)


def rel(path):
    try:
        return str(Path(path).resolve().relative_to(PROJECT))
    except ValueError:
        return str(path)


def open_blend(path):
    if not path.exists():
        raise RuntimeError("Missing blend: %s" % path)
    bpy.ops.wm.open_mainfile(filepath=str(path))
    current = bpy.data.filepath
    if not current or Path(current).resolve() != path.resolve():
        raise RuntimeError("Expected %s to be open, got %s" % (path, current))
    print("OPENED %s" % path)


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def world_down_face_count(obj):
    import mathutils

    rotation = obj.matrix_world.to_3x3()
    total = 0
    for face in obj.data.polygons:
        if (rotation @ mathutils.Vector(face.normal)).normalized().z < DOWN_FACE_NORMAL_Z:
            total += 1
    return total


def remove_downward_faces(obj):
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    rotation = obj.matrix_world.to_3x3()
    remove = [
        face
        for face in bm.faces
        if (rotation @ face.normal).normalized().z < DOWN_FACE_NORMAL_Z
    ]
    if remove:
        bmesh.ops.delete(bm, geom=remove, context="FACES")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return len(remove)


def triangulate(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def local_bounds(obj):
    import mathutils

    points = [obj.matrix_world @ mathutils.Vector(corner) for corner in obj.bound_box]
    lows = [min(p[i] for p in points) for i in range(3)]
    highs = [max(p[i] for p in points) for i in range(3)]
    return lows, highs


def bounds_report(obj):
    lows, highs = local_bounds(obj)
    return {
        "min": [round(v, 5) for v in lows],
        "max": [round(v, 5) for v in highs],
        "size": [round(highs[i] - lows[i], 5) for i in range(3)],
    }


def material_roles(obj):
    return [slot.material.name for slot in obj.material_slots if slot.material]


def derive():
    open_blend(SOURCE_BLEND)

    package = bpy.data.collections.get(SOURCE_PACKAGE)
    if package is None:
        raise RuntimeError("Missing collection %s" % SOURCE_PACKAGE)

    root = bpy.data.objects.get(SOURCE_COMPONENT)
    if root is None or root.type != "EMPTY":
        raise RuntimeError("Missing ROOT empty %s" % SOURCE_COMPONENT)
    root_location = root.matrix_world.translation.copy()
    print("SOURCE ROOT world = (%.6f, %.6f, %.6f)" % tuple(root_location))
    print("SOURCE ROOT props = %s" % dict(root.items()))

    sources = []
    for name in (SOURCE_BODY, SOURCE_EMISSIVE):
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != "MESH":
            raise RuntimeError("Missing source mesh %s" % name)
        if not any(collection == package for collection in obj.users_collection):
            raise RuntimeError("%s is not in %s" % (name, SOURCE_PACKAGE))
        sources.append(obj)

    # 绕 Blender Z 转 180°（以 ROOT 原点为轴），再整体平移回原点，最后烘焙进顶点，
    # 让导出根节点保持恒等。
    yaw = Matrix.Rotation(math.pi, 4, "Z")
    recenter = Matrix.Translation(-root_location)
    bake = yaw @ recenter

    export_collection = bpy.data.collections.new("runtime_%s" % ASSET_VERSION)
    bpy.context.scene.collection.children.link(export_collection)

    removed_down = 0
    faces_before = 0
    triangles_pre_cull = 0
    for source in sources:
        clone = source.copy()
        clone.data = source.data.copy()
        clone.animation_data_clear()
        # Object.copy 会保留生产环境的父子关系；必须断掉，否则世界变换会在 GLB 里
        # 沿原层级被再算一次。
        clone.parent = None
        clone.matrix_world = bake @ source.matrix_world
        clone.name = "DERIVED_%s" % source.name
        # 展示阵列里有默认隐藏的集合；清掉隐藏标记保证 transform_apply / join 与导出
        # 都真的看得见这份几何。
        clone.hide_viewport = False
        clone.hide_render = False
        clone.hide_set(False)
        export_collection.objects.link(clone)

        faces_before += len(clone.data.polygons)
        activate(clone)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        # 先三角化再剔除。n-gon 存的法线是各角平均，非平面的面可能平均后高于阈值，
        # 而它的三角形低于阈值 —— 先剔就会把这些隐藏三角形留下（A 套实墙实测残留 11 个）。
        # 剔除三角形的法线才是精确的。
        triangulate(clone)
        triangles_pre_cull += len(clone.data.polygons)
        removed_down += remove_downward_faces(clone)

    activate(export_collection.objects[0])
    for clone in export_collection.objects:
        clone.select_set(True)
    bpy.context.view_layer.objects.active = export_collection.objects[0]
    bpy.ops.object.join()
    merged = bpy.context.view_layer.objects.active
    merged.name = NODE_NAME
    merged.data.name = MESH_NAME

    # 丢掉没有面的材质槽：源里若有角色一个面都没占，glTF 也带不走，
    # 在此移除能让导出诚实。
    dropped_slots = []
    used = {poly.material_index for poly in merged.data.polygons}
    for index in reversed(range(len(merged.material_slots))):
        if index not in used:
            dropped_slots.append(merged.material_slots[index].material.name)
            activate(merged)
            merged.active_material_index = index
            bpy.ops.object.material_slot_remove()

    roles = material_roles(merged)
    missing_required = sorted(REQUIRED_ROLES - set(roles))
    if missing_required:
        raise RuntimeError(
            "DERIVE_MATERIAL_ROLES_FAILED: 必需角色缺失 %s（实得 %s）"
            % (missing_required, roles)
        )
    unexpected = sorted(set(roles) - EXPECTED_ROLES)
    if unexpected:
        raise RuntimeError(
            "DERIVE_MATERIAL_ROLES_FAILED: 出现未登记角色 %s（实得 %s）" % (unexpected, roles)
        )

    # 溯源与派生后的真相。front_axis_blender 被改写，因为源声明（"+Y"）在偏航后不再成立。
    merged["asset_id"] = ASSET_ID
    merged["asset_version"] = ASSET_VERSION
    merged["visual_only"] = True
    merged["origin_contract"] = "bottom_center"
    merged["front_axis_blender"] = "-Y"
    merged["front_axis_godot"] = "+Z"
    merged["collision_owner"] = "RoomDoor3D"
    merged["derived_from_blend"] = rel(SOURCE_BLEND)
    merged["derived_from_component"] = SOURCE_COMPONENT
    merged["derived_from_package"] = SOURCE_PACKAGE
    merged["source_component_asset_version"] = SOURCE_COMPONENT_ASSET_VERSION
    merged["derivation"] = (
        "yaw 180 about Blender Z (declared front +Y -> -Y so the YUP export lands on "
        "Godot +Z); offset baked into vertices and the ROOT empty dropped; two meshes "
        "joined into one; downward faces (world normal z < -0.5) deleted after "
        "triangulation."
    )
    merged["front_axis_note"] = (
        "门扇在厚度轴上镜面对称（±0.09 居中），翻转对当前外观是恒等变换；"
        "做这一步是为了与 A 套门墙共用「正面 = Godot +Z」约定。"
    )

    # 只留下导出载体，让派生 blend 不会被误当生产源，也保证重复导出是确定性的。
    for obj in list(bpy.data.objects):
        if obj is not merged:
            bpy.data.objects.remove(obj, do_unlink=True)
    for collection in list(bpy.data.collections):
        if collection != export_collection:
            bpy.data.collections.remove(collection)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)

    # 批源里有 12 个 Scene（11 个审阅场景 + 1 个生产场景），glTF 导出默认会把它们
    # 全部写出去，Godot 于是加载 0 号默认场景（一个空审阅场景）——模型导入成空。
    # 收敛成单一干净场景，并清掉批源的场景级自定义属性（否则会带出一条
    # "independent_meshes_no_join" 策略串，与本次派生刻意合并单 Mesh 相矛盾）。
    keep_scene = bpy.context.scene
    scenes_removed = 0
    for scene in list(bpy.data.scenes):
        if scene != keep_scene:
            bpy.data.scenes.remove(scene)
            scenes_removed += 1
    for key in list(keep_scene.keys()):
        del keep_scene[key]
    keep_scene.name = "env_tower_door_leaf_5m_%s" % ASSET_VERSION

    uv_layers = [layer.name for layer in merged.data.uv_layers]
    if "PaletteUV" in uv_layers:
        merged.data.uv_layers["PaletteUV"].active_render = True
    merged.data.calc_loop_triangles()

    report = {
        "asset_id": ASSET_ID,
        "asset_version": ASSET_VERSION,
        "node_name": NODE_NAME,
        "source_blend": rel(SOURCE_BLEND),
        "source_package": SOURCE_PACKAGE,
        "source_component": SOURCE_COMPONENT,
        "source_component_asset_version": SOURCE_COMPONENT_ASSET_VERSION,
        "source_root_world_translation": [round(v, 6) for v in root_location],
        "baked_yaw_deg": 180,
        "faces_before_optimize": faces_before,
        "triangles_before_cull": triangles_pre_cull,
        "downward_faces_removed": removed_down,
        "faces_after_optimize": len(merged.data.polygons),
        "triangles_after_optimize": len(merged.data.loop_triangles),
        "material_roles": roles,
        "dropped_empty_material_slots": dropped_slots,
        "scenes_removed": scenes_removed,
        "uv_layers": uv_layers,
        "bounds_blender": bounds_report(merged),
        "derived_blend": rel(OUTPUT_BLEND),
    }

    OUTPUT_BLEND.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    MANIFEST.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("DOOR_LEAF_V001_DERIVE_REPORT " + json.dumps(report, ensure_ascii=False))
    print("DERIVE_OK blend=%s" % OUTPUT_BLEND)


def read_glb_json(path):
    """直接从 .glb 里把 JSON chunk 抠出来（不经过任何导入器）。

    这是唯一能证明消费方实际会看到什么的地方：等到 Godot 实例化时，
    Blender 侧状态早已不存在。
    """
    import struct

    data = path.read_bytes()
    magic, _version, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise RuntimeError("Not a GLB: %s" % path)
    offset = 12
    while offset < length:
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8: offset + 8 + chunk_length]
        if chunk_type == 0x4E4F534A:
            return json.loads(chunk.decode("utf-8"))
        offset += 8 + chunk_length + ((4 - chunk_length % 4) % 4 if chunk_length % 4 else 0)
    raise RuntimeError("GLB has no JSON chunk: %s" % path)


def verify_glb():
    gltf = read_glb_json(GLB_OUTPUT)
    problems = []

    scenes = gltf.get("scenes", [])
    if len(scenes) != 1:
        problems.append("expected exactly 1 glTF scene, found %d" % len(scenes))
    default_index = gltf.get("scene", 0)
    if scenes and default_index != 0:
        problems.append("default scene index is %d, expected 0" % default_index)

    nodes = gltf.get("nodes", [])
    if len(nodes) != 1:
        problems.append("expected exactly 1 glTF node, found %d" % len(nodes))
    else:
        node = nodes[0]
        if node.get("name") != NODE_NAME:
            problems.append("node name is %r, expected %r" % (node.get("name"), NODE_NAME))
        for key in ("translation", "rotation", "scale", "matrix"):
            if key in node:
                problems.append(
                    "root node carries %s=%s; the offset must be baked into the "
                    "vertex data (RoomDoor3D instantiates the whole tree)"
                    % (key, node[key])
                )

    meshes = gltf.get("meshes", [])
    if len(meshes) != 1:
        problems.append("expected exactly 1 mesh, found %d" % len(meshes))
    primitives = meshes[0].get("primitives", []) if meshes else []
    if len(primitives) != len(EXPECTED_ROLES):
        problems.append(
            "expected %d primitives (4 palette roles), found %d"
            % (len(EXPECTED_ROLES), len(primitives))
        )

    accessors = gltf.get("accessors", [])
    lows = [None, None, None]
    highs = [None, None, None]
    for primitive in primitives:
        accessor = accessors[primitive["attributes"]["POSITION"]]
        for axis in range(3):
            lows[axis] = accessor["min"][axis] if lows[axis] is None else min(lows[axis], accessor["min"][axis])
            highs[axis] = accessor["max"][axis] if highs[axis] is None else max(highs[axis], accessor["max"][axis])

    for axis in range(3):
        if lows[axis] is None or abs(lows[axis] - GODOT_MIN[axis]) > BOUNDS_TOLERANCE_M:
            problems.append(
                "godot bounds min axis %d = %s, expected %.4f" % (axis, lows[axis], GODOT_MIN[axis])
            )
        if highs[axis] is None or abs(highs[axis] - GODOT_MAX[axis]) > BOUNDS_TOLERANCE_M:
            problems.append(
                "godot bounds max axis %d = %s, expected %.4f" % (axis, highs[axis], GODOT_MAX[axis])
            )
    # 门扇的锚点契约是「底面中心 + 厚度轴居中」（源侧 qa/verify_door_anchor_v006.py
    # 就是这么断言的）。厚度轴一旦不居中，门扇贴回门框时就会前后偏半块板厚。
    if lows[2] is not None and highs[2] is not None and abs(lows[2] + highs[2]) > BOUNDS_TOLERANCE_M:
        problems.append(
            "thickness axis is not centred (godot z = %s .. %s); the source anchor "
            "contract requires a thickness-symmetric leaf" % (lows[2], highs[2])
        )
    if lows[1] is not None and not (LEAF_BOTTOM_MIN_M <= lows[1] <= LEAF_BOTTOM_MAX_M):
        problems.append(
            "leaf bottom (godot y min) = %s, outside [%.3f, %.3f]"
            % (lows[1], LEAF_BOTTOM_MIN_M, LEAF_BOTTOM_MAX_M)
        )

    if gltf.get("images") or gltf.get("textures"):
        problems.append(
            "GLB embeds images/textures; the shared palette must be bound after "
            "import, not baked in"
        )

    if problems:
        raise RuntimeError("DOOR_LEAF_V001_GLB_VERIFY_FAILED: " + " | ".join(problems))

    size = [round(highs[axis] - lows[axis], 5) for axis in range(3)]
    print(
        "DOOR_LEAF_V001_GLB_VERIFIED scenes=1 nodes=1 meshes=1 prims=%d "
        "godot_min=%s godot_max=%s godot_size=%s nodes_trs=identity"
        % (
            len(primitives),
            [round(v, 5) for v in lows],
            [round(v, 5) for v in highs],
            size,
        )
    )


def export():
    open_blend(OUTPUT_BLEND)
    obj = bpy.data.objects.get(NODE_NAME)
    if obj is None or obj.type != "MESH":
        raise RuntimeError("Derived blend is missing %s" % NODE_NAME)

    # 契约断言。这些正是会静默上线的失败：偏移没烘干净、朝下面残留、
    # 出现第二个 Mesh、厚度轴不居中、材质角色漂移。
    problems = []
    mesh_objects = [item for item in bpy.data.objects if item.type == "MESH"]
    if len(mesh_objects) != 1:
        problems.append("expected exactly 1 mesh object, found %d" % len(mesh_objects))
    if obj.matrix_world != Matrix.Identity(4):
        problems.append("root transform is not identity: %s" % obj.matrix_world)
    remaining_down = world_down_face_count(obj)
    if remaining_down != 0:
        problems.append("%d downward faces survived the cull" % remaining_down)
    if [layer.name for layer in obj.data.uv_layers] != ["PaletteUV"]:
        problems.append("unexpected UV layers: %s" % [l.name for l in obj.data.uv_layers])
    roles = sorted(material_roles(obj))
    if set(roles) - EXPECTED_ROLES:
        problems.append("unexpected material roles: %s" % roles)
    if REQUIRED_ROLES - set(roles):
        problems.append("missing required material roles: %s" % sorted(REQUIRED_ROLES - set(roles)))

    lows, highs = local_bounds(obj)
    # Blender 空间的期望（绕 Z 偏航 180°，X 与厚度轴因对称而不变）：
    #   x = -1.1 .. 1.1（宽，左右对称）
    #   y = -0.09 .. 0.09（厚度，精确居中 —— 门扇锚点契约）
    #   z = 0.008 .. 2.5（高；底边悬在原点上方 8mm，见文件头说明）
    expected_min = [-1.1, -0.09, 0.008]
    expected_max = [1.1, 0.09, 2.5]
    for axis, (got, want) in enumerate(zip(lows, expected_min)):
        if abs(got - want) > BOUNDS_TOLERANCE_M:
            problems.append("bounds min axis %d = %.5f, expected %.5f" % (axis, got, want))
    for axis, (got, want) in enumerate(zip(highs, expected_max)):
        if abs(got - want) > BOUNDS_TOLERANCE_M:
            problems.append("bounds max axis %d = %.5f, expected %.5f" % (axis, got, want))
    # 底边区间：不得低于原点（会扎进地面），也不得高过 2cm（那就丢掉「底面中心」语义了）。
    if not (LEAF_BOTTOM_MIN_M <= lows[2] <= LEAF_BOTTOM_MAX_M):
        problems.append(
            "leaf bottom (Blender z min) = %.5f, outside [%.3f, %.3f]"
            % (lows[2], LEAF_BOTTOM_MIN_M, LEAF_BOTTOM_MAX_M)
        )
    # 厚度轴居中（门扇锚点契约）。注意 Godot 的 Z 来自 Blender 的 -Y。
    if abs(lows[1] + highs[1]) > BOUNDS_TOLERANCE_M:
        problems.append(
            "thickness axis is not centred in Blender (y = %.5f .. %.5f)" % (lows[1], highs[1])
        )

    if problems:
        raise RuntimeError("DOOR_LEAF_V001_EXPORT_CONTRACT_FAILED: " + " | ".join(problems))

    GLB_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    activate(obj)
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_OUTPUT),
        export_format="GLB",
        use_selection=True,
        use_active_scene=True,
        export_apply=True,
        export_yup=True,
        export_extras=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )
    verify_glb()

    # Godot 空间预测：Blender (x, y, z) -> Godot (x, z, -y)。
    lows, highs = local_bounds(obj)
    godot_size = [highs[0] - lows[0], highs[2] - lows[2], highs[1] - lows[1]]
    godot_min = [lows[0], lows[2], -highs[1]]
    godot_max = [highs[0], highs[2], -lows[1]]
    report = {
        "glb": rel(GLB_OUTPUT),
        "bounds_godot_predicted_min": [round(v, 5) for v in godot_min],
        "bounds_godot_predicted_max": [round(v, 5) for v in godot_max],
        "bounds_godot_predicted_size": [round(v, 5) for v in godot_size],
        "material_roles": material_roles(obj),
        "triangles": len(obj.data.loop_triangles),
    }
    print("DOOR_LEAF_V001_EXPORT_REPORT " + json.dumps(report, ensure_ascii=False))
    print("EXPORT_OK glb=%s" % GLB_OUTPUT)


def main():
    phase = os.environ.get("SS_DOOR_LEAF_PHASE", "derive").strip().lower()
    if phase == "derive":
        derive()
    elif phase == "export":
        export()
    else:
        raise RuntimeError("Unknown SS_DOOR_LEAF_PHASE=%s" % phase)


main()
