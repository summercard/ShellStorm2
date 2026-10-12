"""只用标准库回归验证运行时贴图用途判定。"""
import ast
import collections
import configparser
import json
import re
import struct
import unittest
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/optimize_runtime_textures.py"


def load_pure_role_functions():
    tree = ast.parse(SCRIPT.read_text(encoding="utf-8"), filename=str(SCRIPT))
    wanted = {"_EXPLICIT_NORMAL_SUFFIX", "_material_texture_roles",
              "_external_image_rel", "texture_roles_for_glb",
              "assert_no_texture_role_conflicts", "normal_role_for_texture",
              "normal_map_params"}
    body = [node for node in tree.body if (
        isinstance(node, ast.Assign)
        and any(isinstance(target, ast.Name) and target.id == "_EXPLICIT_NORMAL_SUFFIX"
                for target in node.targets)
    ) or (isinstance(node, ast.FunctionDef) and node.name in wanted)]
    namespace = {
        "collections": collections,
        "Path": Path,
        "re": re,
        "unquote": unquote,
    }
    exec(compile(ast.Module(body=body, type_ignores=[]), str(SCRIPT), "exec"), namespace)
    return namespace


ROLE = load_pure_role_functions()


class RuntimeTextureRoleTests(unittest.TestCase):
    def test_actual_fat_zombie_basecolor_contract_disables_normal_import(self):
        model = ROOT / "assets/art/enemies/normal_enemy_3d/fat_zombie03/components/enm_normal_fat_zombie03_visual_top3d.glb"
        binary = model.read_bytes()
        length, kind = struct.unpack_from("<II", binary, 12)
        self.assertEqual(kind, 0x4E4F534A)
        doc = json.loads(binary[20:20 + length])
        roles = ROLE["texture_roles_for_glb"](model, doc, {}, ROOT)
        rel = "assets/art/shared/textures/enemies/tex_normal_fa20394fbaf52f6d81c7.png"
        self.assertEqual(roles[rel], {"color"})
        settings = configparser.ConfigParser()
        import_text = (ROOT / (rel + ".import")).read_text(encoding="utf-8")
        settings.read_string("[params]\n" + import_text.split("[params]", 1)[1])
        self.assertEqual(settings.getint("params", "compress/normal_map"), 2)

    def test_fat_zombie_basecolor_name_is_not_normal(self):
        self.assertFalse(ROLE["normal_role_for_texture"](
            "assets/art/enemies/fat_zombie03_enm_normal_basecolor.png", {"color"}, False
        ))

    def test_true_normal_slot_follows_texture_source_for_external_and_embedded_images(self):
        doc = {
            "images": [
                {"uri": "textures/fat_zombie03_nrm.png"},
                {"bufferView": 7},
            ],
            "textures": [{"source": 0}, {"source": 1}],
            "materials": [
                {"normalTexture": {"index": 0}},
                {"normalTexture": {"index": 1}},
            ],
        }
        roles = ROLE["texture_roles_for_glb"](
            ROOT / "assets/art/enemies/fat_zombie03.glb", doc,
            {1: "assets/art/enemies/fat_zombie03_embedded_nrm.png"}, ROOT
        )
        self.assertEqual(roles["assets/art/enemies/textures/fat_zombie03_nrm.png"], {"normal"})
        self.assertEqual(roles["assets/art/enemies/fat_zombie03_embedded_nrm.png"], {"normal"})
        self.assertTrue(ROLE["normal_role_for_texture"](
            "assets/art/enemies/textures/fat_zombie03_nrm.png",
            roles["assets/art/enemies/textures/fat_zombie03_nrm.png"], False
        ))

    def test_shared_tex_normal_used_by_base_color_stays_color(self):
        doc = {
            "images": [{"uri": "../shared/textures/enemies/tex_normal_deadbeef.png"}],
            "textures": [{"source": 0}],
            "materials": [{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}],
        }
        roles = ROLE["texture_roles_for_glb"](
            ROOT / "assets/art/enemies/fat_zombie03.glb", doc, {}, ROOT
        )
        rel = "assets/art/shared/textures/enemies/tex_normal_deadbeef.png"
        self.assertEqual(roles[rel], {"color"})
        self.assertFalse(ROLE["normal_role_for_texture"](rel, roles[rel], True))
        self.assertEqual(ROLE["normal_map_params"]("compress/normal_map=1", False),
                         "compress/normal_map=2")

    def test_same_image_in_color_and_normal_slots_is_rejected(self):
        doc = {
            "images": [{"uri": "textures/mixed.png"}],
            "textures": [{"source": 0}],
            "materials": [
                {"normalTexture": {"index": 0}},
                {"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}},
            ],
        }
        roles = ROLE["texture_roles_for_glb"](
            ROOT / "assets/art/enemies/fat_zombie03.glb", doc, {}, ROOT
        )
        with self.assertRaises(ValueError):
            ROLE["assert_no_texture_role_conflicts"](roles)
        with self.assertRaises(ValueError):
            ROLE["normal_role_for_texture"]("mixed.png", {"color", "normal"}, False)

    def test_unreferenced_asset_name_does_not_enable_normal_but_manual_setting_is_kept(self):
        rel = "assets/art/enemies/fat_zombie03_enm_normal_basecolor.png"
        self.assertFalse(ROLE["normal_role_for_texture"](rel, set(), False))
        self.assertTrue(ROLE["normal_role_for_texture"](rel, set(), True))

    def test_explicit_normal_suffix_can_enable_unreferenced_texture(self):
        for suffix in ("_normal", "_normalmap", "_nrm"):
            with self.subTest(suffix=suffix):
                rel = f"assets/art/enemies/fat_zombie03{suffix}.png"
                self.assertTrue(ROLE["normal_role_for_texture"](rel, set(), False))

    def test_normal_map_params_use_explicit_enabled_or_disabled(self):
        for previous in (0, 1, 2):
            for normal, expected in ((True, 1), (False, 2)):
                with self.subTest(previous=previous, normal=normal):
                    self.assertEqual(
                        ROLE["normal_map_params"](f"compress/normal_map={previous}", normal),
                        f"compress/normal_map={expected}",
                    )

    def test_unreferenced_directory_and_shared_hash_do_not_enable_normal(self):
        for rel in ("assets/enm_normal/diffuse.png",
                    "assets/art/shared/textures/enemies/tex_normal_deadbeef.png"):
            with self.subTest(rel=rel):
                self.assertFalse(ROLE["normal_role_for_texture"](rel, set(), False))


if __name__ == "__main__":
    unittest.main()
