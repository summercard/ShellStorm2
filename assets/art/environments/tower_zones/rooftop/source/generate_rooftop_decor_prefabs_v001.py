"""Generate stable visual-only PackedScenes for rooftop decoration GLBs."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[6]
ROOFTOP = ROOT / "assets/art/environments/tower_zones/rooftop"
COMPONENTS = ROOFTOP / "components"
RUNTIME = ROOFTOP / "runtime"
RUNTIME.mkdir(parents=True, exist_ok=True)

ASSETS = {
    "hvac_small": ("ENV-ROOFTOP-REF-HVAC-SMALL", "env_rooftop_ref_hvac_small_top3d.glb", "小型空调机组", "wall_mounted_hvac"),
    "hvac_vent": ("ENV-ROOFTOP-REF-HVAC-VENT", "env_rooftop_ref_hvac_vent_top3d.glb", "小通风口", "wall_vent"),
    "pipe_straight": ("ENV-ROOFTOP-REF-PIPE-STRAIGHT", "env_rooftop_ref_pipe_straight_top3d.glb", "直管段", "pipe_loop_segment"),
    "pipe_elbow": ("ENV-ROOFTOP-REF-PIPE-ELBOW", "env_rooftop_ref_pipe_elbow_top3d.glb", "转角弯管", "pipe_loop_corner"),
    "pipe_tee": ("ENV-ROOFTOP-REF-PIPE-TEE", "env_rooftop_ref_pipe_tee_top3d.glb", "三通管", "pipe_loop_branch"),
    "pipe_riser": ("ENV-ROOFTOP-REF-PIPE-RISER", "env_rooftop_ref_pipe_riser_top3d.glb", "立管下水管", "pipe_riser"),
    "pipe_bracket": ("ENV-ROOFTOP-REF-PIPE-BRACKET", "env_rooftop_ref_pipe_bracket_top3d.glb", "管道支架", "pipe_bracket"),
    "ivy": ("ENV-ROOFTOP-REF-IVY", "env_rooftop_ref_ivy_top3d.glb", "墙面攀爬藤蔓", "wall_ivy"),
    "parapet_ivy": ("ENV-ROOFTOP-REF-PARAPET-IVY", "env_rooftop_ref_parapet_ivy_top3d.glb", "女儿墙挂藤", "parapet_ivy"),
    "flowerbox": ("ENV-ROOFTOP-REF-FLOWERBOX", "env_rooftop_ref_flowerbox_top3d.glb", "长条花箱", "flowerbox"),
    "plant_large": ("ENV-ROOFTOP-REF-PLANT-LARGE", "env_rooftop_ref_plant_large_top3d.glb", "大盆栽", "large_plant"),
    "plant_small": ("ENV-ROOFTOP-REF-PLANT-SMALL", "env_rooftop_ref_plant_small_top3d.glb", "小盆栽", "small_plant"),
}

for slug, (asset_id, glb, label, role) in ASSETS.items():
    path = RUNTIME / f"{slug}.tscn"
    content = f'''[gd_scene load_steps=2 format=3]\n\n; 100F 天台装饰组件：{label}（v002 参考组件库导出，纯视觉）\n; 稳定运行时路径：rooftop/runtime/{slug}.tscn\n; GLB：rooftop/components/{glb}\n\n[ext_resource type="PackedScene" path="res://assets/art/environments/tower_zones/rooftop/components/{glb}" id="1_visual"]\n\n[node name="Rooftop{slug.title().replace("_", "")}" type="Node3D"]\nmetadata/asset_id = "{asset_id}"\nmetadata/package_id = "{asset_id}"\nmetadata/asset_version = "v002"\nmetadata/source_blend = "res://assets/art/environments/tower_zones/rooftop/source/reference_components/v002/天台区块_参考组件库_v002.blend"\nmetadata/source_glb = "res://assets/art/environments/tower_zones/rooftop/components/{glb}"\nmetadata/visual_only = true\nmetadata/collision_owner = "TowerFloorStage3D"\nmetadata/preserve_authored_palette = true\nmetadata/runtime_instantiation = "per_instance_prefab"\nmetadata/layout_role = "{role}"\nmetadata.component_slug = "{slug}"\n\n[node name="ImportedModel" parent="." instance=ExtResource("1_visual")]\n'''
    path.write_text(content, encoding="utf-8", newline="\n")
    print(f"GENERATED {path}")
print(f"ROOFTOP_DECOR_PREFABS_OK count={len(ASSETS)} output={RUNTIME}")
