"""ShellStorm2 关卡组件目录、区块与分类定义。

每个组件声明默认尺寸、参数顺序、锚点规则和 AssetID。
锚点指物体原点落在组件的哪个位置，默认统一为底面中心，与游戏内实墙 GLB 一致。
"""


COMPONENTS = (
    {
        "id": "WALL",
        "name": "墙壁 5×0.3×11.9m",
        "category": "建筑结构",
        "icon": "MESH_CUBE",
        "asset_id": "ENV-TOWER-WALL-SOLID-5M",
        "game_anchor": "BOTTOM_CENTER",
        "params": ("width", "depth", "height"),
        "defaults": {"width": 5.0, "depth": 0.3, "height": 11.9},
    },
    {
        "id": "FLOOR",
        "name": "地板 5×5×0.3m",
        "category": "地面系统",
        "icon": "MESH_GRID",
        "asset_id": "ENV-TOWER-FLOOR-TILE-5M",
        "game_anchor": "CENTER_Z",
        "params": ("width", "depth", "thickness"),
        "defaults": {"width": 5.0, "depth": 5.0, "thickness": 0.3},
    },
    {
        "id": "COLUMN",
        "name": "拐角柱 0.5×0.5×12.9m",
        "category": "建筑结构",
        "icon": "MESH_CUBE",
        "asset_id": "",
        "game_anchor": "BOTTOM_CENTER",
        "params": ("width", "depth", "height"),
        "defaults": {"width": 0.5, "depth": 0.5, "height": 12.9},
    },
    {
        "id": "DOOR_OPENING",
        "name": "门洞 2×0.3×2.4m",
        "category": "建筑结构",
        "icon": "MOD_BOOLEAN",
        "asset_id": "",
        "game_anchor": "BOTTOM_CENTER",
        "params": ("width", "depth", "height", "opening_width", "opening_height"),
        "defaults": {
            "width": 5.0,
            "depth": 0.3,
            "height": 11.9,
            "opening_width": 2.0,
            "opening_height": 2.4,
        },
    },
    {
        "id": "STAIR",
        "name": "参数化直梯",
        "category": "建筑结构",
        "icon": "MOD_ARRAY",
        "asset_id": "",
        "game_anchor": "BOTTOM_CENTER",
        "params": ("width", "step_count", "step_height", "tread_depth"),
        "defaults": {"width": 6.0, "step_count": 20, "step_height": 0.3, "tread_depth": 0.75},
    },
    {
        "id": "RAILING",
        "name": "栏杆 5×0.1×1.1m",
        "category": "建筑结构",
        "icon": "MOD_WIREFRAME",
        "asset_id": "",
        "game_anchor": "BOTTOM_CENTER",
        "params": ("width", "depth", "thickness", "railing_height"),
        "defaults": {"width": 5.0, "depth": 0.1, "thickness": 0.1, "railing_height": 1.1},
    },
    {
        "id": "FIXTURE",
        "name": "固定设施占位盒",
        "category": "固定设施",
        "icon": "CUBE",
        "asset_id": "",
        "game_anchor": "BOTTOM_CENTER",
        "params": ("width", "depth", "height"),
        "defaults": {"width": 2.0, "depth": 1.0, "height": 2.0},
    },
)

COMPONENT_BY_ID = {item["id"]: item for item in COMPONENTS}

COMPONENT_GROUPS = ("建筑结构", "地面系统", "固定设施", "环境支持")


def components_by_group():
    """按侧栏显示顺序返回 (分类, 组件列表)。"""
    grouped = []
    for group in COMPONENT_GROUPS:
        items = [item for item in COMPONENTS if item["category"] == group]
        if items:
            grouped.append((group, items))
    return grouped


CATEGORIES = (
    ("architecture", "01_建筑结构", "墙、楼板、楼梯、门洞和栏杆"),
    ("floor", "02_地面系统", "独立地砖及其附着细节"),
    ("facilities", "03_区域固定设施", "可独立维护的固定设施"),
    ("support", "04_环境支持", "跨设施管线、灯光与环境支持"),
)

CATEGORY_BY_LABEL = {label: slug for slug, label, _description in CATEGORIES}

BLOCKS = (
    ("rooftop", "天台区", "100F"),
    ("base", "基地区", "99F"),
    ("battle", "局内关卡01-顶部数据库", "98–95F"),
    ("stairs", "楼梯区", "100→99、99→98"),
)
