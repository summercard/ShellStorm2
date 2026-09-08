import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXPORT_MANIFEST = ROOT / 'source/art/blender/base_facility_layout/export/v023/export_manifest.json'
RUNTIME = ROOT / 'assets/art/environments/base_facility_3d/runtime'
REMAINING = RUNTIME / 'env_base99_remaining_facilities_v021'

data = json.loads(EXPORT_MANIFEST.read_text())
bed = data['packages']['loft_bed_and_bedding']
stair = data['packages']['northwest_l_stair']

def replace_required(text, old, new, file):
    assert old in text, f'{file} missing expected text: {old}'
    return text.replace(old, new)

# New bed wrapper: retain the existing root/collision layout, replace only the optimized visual GLB.
bed_old = REMAINING / 'loft_bed_and_bedding/loft_bed_and_bedding_root_top3d_v003.tscn'
bed_new = bed_old.with_name('loft_bed_and_bedding_root_top3d_v004.tscn')
text = bed_old.read_text()
text = replace_required(text, 'loft_bed_and_bedding_visual_top3d_v003.glb', 'loft_bed_and_bedding_visual_top3d_v004.glb', bed_old)
text = replace_required(text, 'ENV-BASE99-V022::loft_bed_and_bedding', 'ENV-BASE99-V023::loft_bed_and_bedding', bed_old)
text = replace_required(text, 'metadata/asset_version = "v022"', 'metadata/asset_version = "v023"', bed_old)
text = replace_required(text, 'base_facility_runtime_layout_hq_v022.blend', 'base_facility_runtime_layout_hq_v023.blend', bed_old)
text = replace_required(text, 'export/v022/base_facility_runtime_layout_hq-v022-updated_packages.blend', 'export/v023/base_facility_runtime_layout_hq-v023-stair_bed.blend', bed_old)
text = replace_required(text, 'metadata/triangles_before = 3852', f'metadata/triangles_before = {bed["triangles_before"]}', bed_old)
text = replace_required(text, 'metadata/triangles_after = 3230', f'metadata/triangles_after = {bed["triangles_after"]}', bed_old)
text = replace_required(text, 'metadata/downward_triangles_removed = 622', f'metadata/downward_triangles_removed = {bed["downward_triangles_removed"]}', bed_old)
bed_new.write_text(text)

# New remaining-facilities assembly: only its bed child changes version.
remaining_old = REMAINING / 'env_base99_remaining_facilities_root_top3d_v003.tscn'
remaining_new = REMAINING / 'env_base99_remaining_facilities_root_top3d_v004.tscn'
text = remaining_old.read_text()
text = replace_required(text, 'loft_bed_and_bedding_root_top3d_v003.tscn', 'loft_bed_and_bedding_root_top3d_v004.tscn', remaining_old)
text = replace_required(text, 'base_facility_runtime_layout_hq_v022.blend', 'base_facility_runtime_layout_hq_v023.blend', remaining_old)
text = replace_required(text, 'metadata/derived_from_version = "v022"', 'metadata/derived_from_version = "v023"', remaining_old)
text = text.replace('metadata/optimized_package_count = 32', 'metadata/optimized_package_count = 32\nmetadata/v023_reoptimized_packages = "loft_bed_and_bedding"')
remaining_new.write_text(text)

# New walkable-stair wrapper: preserve the Base99WalkableModule3D functional script and all collision contracts.
stair_old = RUNTIME / 'env_base99_stair_l_z5/env_base99_stair_l_z5_root_top3d_v005.tscn'
stair_new = stair_old.with_name('env_base99_stair_l_z5_root_top3d_v006.tscn')
text = stair_old.read_text()
text = replace_required(text, 'env_base99_stair_l_z5_visual_top3d_v005.glb', 'env_base99_stair_l_z5_visual_top3d_v006.glb', stair_old)
text = replace_required(text, 'metadata/asset_version = "v005"', 'metadata/asset_version = "v006"', stair_old)
text = replace_required(text, 'base_facility_runtime_layout_hq_v022.blend', 'base_facility_runtime_layout_hq_v023.blend', stair_old)
text = replace_required(text, 'export/v022/base_facility_runtime_layout_hq-v022-updated_packages.blend', 'export/v023/base_facility_runtime_layout_hq-v023-stair_bed.blend', stair_old)
text = text.replace('metadata/derived_blend = "res://source/art/blender/base_facility_layout/export/v023/base_facility_runtime_layout_hq-v023-stair_bed.blend"', 'metadata/derived_blend = "res://source/art/blender/base_facility_layout/export/v023/base_facility_runtime_layout_hq-v023-stair_bed.blend"\nmetadata/triangles_before = %d\nmetadata/triangles_after = %d\nmetadata/downward_triangles_removed = %d\nmetadata/legacy_uv_layers_removed = %d' % (stair['triangles_before'], stair['triangles_after'], stair['downward_triangles_removed'], stair['legacy_uv_layers_removed']))

# The prior live layout owned world-space convex blockers for this baked
# stair. Preserve those exact shapes: Base99WalkableModule3D is local-space
# and would place its procedural ramps around the origin for this asset.
legacy_stair = RUNTIME / 'env_base99_structural_v021/northwest_l_stair/northwest_l_stair_root_top3d_v001.tscn'
legacy_text = legacy_stair.read_text()
legacy_resources = legacy_text.split('[node name="14_西北贴墙L型楼梯_资产包"', 1)[0]
legacy_resources = legacy_resources.split('[ext_resource', 1)[1]
legacy_resources = legacy_resources[legacy_resources.find('[sub_resource'):]
legacy_collision = '[node name="StaticCollision"' + legacy_text.split('[node name="StaticCollision"', 1)[1]
text = text.replace('[gd_scene load_steps=3 format=3]', '[gd_scene load_steps=11 format=3]')
text = text.replace('[ext_resource type="Script" path="res://src/world3d/Base99WalkableModule3D.gd" id="2_collision"]\n', '')
text = text.replace('script = ExtResource("2_collision")\ncollision_role = "l_stair"\ntarget_walkable_height_m = 5.0\n', '')
text = text.replace('metadata/collision_contract = "single_static_body_with_continuous_ramp_landing_ramp_shapes_and_independent_guard_blockers"', 'metadata/collision_contract = "preserved_source_convex_ramps_and_rails"\nmetadata/collision_policy = "source_convex_ramps_and_rails"\nmetadata/legacy_source_collision_preserved = true')
text = text.replace('metadata/origin_contract = "center_bottom"', 'metadata/origin_contract = "baked_world_coordinates_root_at_origin"')
text = text.replace('\n[node name="基地99层L型楼梯Z5米"', '\n' + legacy_resources + '\n[node name="基地99层L型楼梯Z5米"')
text += '\n' + legacy_collision
stair_new.write_text(text)

# Rebind every imported material to the project's nearest-filtered palette.
# The GLB embeds Blender image data, so this explicit Godot import hook is
# required to keep the runtime material contract independent of the DCC path.
def configure_shared_palette_import(glb_relative: str) -> None:
    import_path = ROOT / (glb_relative + '.import')
    text = import_path.read_text()
    old = 'import_script/path=""'
    new = 'import_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"'
    if old in text:
        text = text.replace(old, new)
    elif new not in text:
        raise RuntimeError(f'Unexpected Godot import configuration: {import_path}')
    import_path.write_text(text)

configure_shared_palette_import(bed['glb'])
configure_shared_palette_import(stair['glb'])

# Keep historical layout v001 intact; v002 is the current gameplay layout with the v023 references.
layout_old = RUNTIME / 'env_base_facility_art_layout_top3d_v001.tscn'
layout_new = RUNTIME / 'env_base_facility_art_layout_top3d_v002.tscn'
text = layout_old.read_text()
text = replace_required(text, 'env_base99_structural_v021/northwest_l_stair/northwest_l_stair_root_top3d_v001.tscn', 'env_base99_stair_l_z5/env_base99_stair_l_z5_root_top3d_v006.tscn', layout_old)
text = replace_required(text, 'env_base99_remaining_facilities_v021/env_base99_remaining_facilities_root_top3d_v003.tscn', 'env_base99_remaining_facilities_v021/env_base99_remaining_facilities_root_top3d_v004.tscn', layout_old)
text = replace_required(text, 'metadata/runtime_owner = "TowerDescent3D._install_facilities"', 'metadata/runtime_owner = "TowerDescent3D._install_facilities"\nmetadata/source_blend = "base_facility_runtime_layout_hq_v023.blend"\nmetadata/art_revision = "v023_stair_bed_reimport"', layout_old)
layout_new.write_text(text)

ledger = {
    'asset_id': 'ENV-BASE99-V023-STAIR-BED',
    'version': 'v023',
    'source_blend': data['source_blend'],
    'source_sha256': data['source_sha256'],
    'derived_blend': data['derived_blend'],
    'packages': data['packages'],
    'runtime': {
        'bed_prefab': str(bed_new.relative_to(ROOT)),
        'stair_prefab': str(stair_new.relative_to(ROOT)),
        'remaining_assembly': str(remaining_new.relative_to(ROOT)),
        'art_layout': str(layout_new.relative_to(ROOT)),
    },
    'collision_contract': {
        'bed': 'preserved optimized output bounds collision',
        'northwest_l_stair': 'preserved source world-space convex ramp and guard blockers',
    },
    'lock_signature': data['lock_signature'],
}
ledger_path = ROOT / 'assets/art/environments/base_facility_3d/source/env_base99_stair_bed_v023_import_manifest.json'
ledger_path.write_text(json.dumps(ledger, ensure_ascii=False, indent=2) + '\n')

global_path = ROOT / 'assets/art/asset_import_manifest_v001.json'
global_manifest = json.loads(global_path.read_text())
global_manifest['base_facility_stair_bed_v023'] = {
    'asset_id': ledger['asset_id'],
    'version': ledger['version'],
    'package_count': 2,
    'import_manifest': str(ledger_path.relative_to(ROOT)),
    'runtime': ledger['runtime'],
}
global_path.write_text(json.dumps(global_manifest, ensure_ascii=False, indent=2) + '\n')
print('BASE99_V023_STAIR_BED_IMPORTED packages=2')
