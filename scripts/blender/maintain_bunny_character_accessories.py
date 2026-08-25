"""Merge maintained character accessory collections into the Bunny master Blend.

Run with Blender in background mode from the ShellStorm2 project root:
blender --background <bunny-master.blend> --python scripts/blender/maintain_bunny_character_accessories.py
"""

from pathlib import Path
import bpy


PROJECT_ROOT = Path(__file__).resolve().parents[2]
ACCESSORY_BLEND = PROJECT_ROOT / "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/accessories/head/chibi_anime_head_v001/source/chr_player_bunny01_head_chibi_anime_source_v001.blend"
MASTER_BLEND = PROJECT_ROOT / "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/chr_player_capsule01_bunny01_top3d_v008.blend"
COLLECTION_NAME = "二次元头部配件_中文管理"


def main() -> None:
    if not ACCESSORY_BLEND.exists():
        raise FileNotFoundError(ACCESSORY_BLEND)
    with bpy.data.libraries.load(str(ACCESSORY_BLEND), link=False) as (source, destination):
        if COLLECTION_NAME not in source.collections:
            raise RuntimeError(f"Accessory collection missing: {COLLECTION_NAME}")
        destination.collections = [COLLECTION_NAME]
    imported = destination.collections[0]
    if imported is None:
        raise RuntimeError("Accessory collection failed to load")
    existing = bpy.data.collections.get(COLLECTION_NAME)
    if existing is not None and existing != imported:
        bpy.data.collections.remove(existing)
    if imported.name not in [child.name for child in bpy.context.scene.collection.children]:
        bpy.context.scene.collection.children.link(imported)
    bpy.context.scene["character_accessory_maintenance_source"] = str(ACCESSORY_BLEND.relative_to(PROJECT_ROOT)).replace("\\", "/")
    bpy.context.scene["character_accessory_maintenance_contract"] = "HeadJoint-aligned accessories are maintained in this Bunny master Blend and exported to independent runtime GLBs."
    bpy.ops.wm.save_as_mainfile(filepath=str(MASTER_BLEND))
    print(f"BUNNY_CHARACTER_ACCESSORIES_MERGED:{MASTER_BLEND}")


if __name__ == "__main__":
    main()
