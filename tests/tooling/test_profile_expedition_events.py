#!/usr/bin/env python3
"""Reject invalid expedition performance evidence without starting Godot."""
import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from profile_expedition_events import classify_console, finalize_summary, summarize_run


class ExpeditionBudgetTests(unittest.TestCase):
    def setUp(self):
        self.run_data = {
            "godot": "4.7.2-stable (official)",
            "renderer": "forward_plus",
            "quality": "high",
            "viewport": "(1280.0, 720.0)",
            "warm_a": {"completed": True, "skipped": False, "truncated": "",
                       "kinds_done": 4, "kinds_total": 4, "vfx_total": 14, "vfx_pending": 0},
            "warm_b": {"skipped": False, "truncated": "", "rooms": 2, "total": 2,
                       "box_enemy_resources": {"completed": True, "entries": []},
                       "roar_icon": {"completed": True, "retained": True},
                       "occlusion_overlay": {"applicable": True, "completed": True,
                                             "restored": True, "same_material": True}},
            "rooms": ["start", "r1"],
            "visited": ["start", "r1"],
            "events": [
                {"phase": "enter/r1", "details": {"room": "r1", "current_room": "r1"}},
                {"phase": "fixture_flight/0", "details": {"confirmed": True, "hp_before": 2, "hp_after": 1}},
                {"phase": "chest/0", "details": {"created": True}},
            ],
            "samples": [["enter/r1", 12.0], ["enter/r1", 7.0], ["component_room", 100.0]],
        }

    def summary(self):
        return summarize_run(self.run_data, requested_rooms=1)

    def test_complete_sample_and_event_percentiles(self):
        result = self.summary()
        self.assertTrue(result["passed"])
        self.assertEqual(result["environment_mismatches"], {})
        self.assertTrue(result["warm_a_complete"] and result["warm_b_complete"])
        self.assertNotIn("component_room", result["phases"])
        phase = result["phases"]["enter/r1"]
        self.assertEqual((phase["frames"], phase["p50_ms"], phase["p95_ms"], phase["p99_ms"], phase["max_ms"]),
                         (2, 7.0, 12.0, 12.0, 12.0))

    def test_environment_mismatch_rejects_otherwise_complete_sample(self):
        invalid = {"renderer": "gl_compatibility", "quality": "balanced", "viewport": "(1920.0, 1080.0)",
                   "godot": "4.6.3-stable (official)"}
        for field, value in invalid.items():
            with self.subTest(field=field):
                original = self.run_data[field]
                self.run_data[field] = value
                result = self.summary()
                self.assertFalse(result["passed"])
                self.assertTrue(result["warm_complete"])
                self.assertEqual(set(result["environment_mismatches"]), {field})
                self.assertEqual(result["environment_mismatches"][field]["actual"], value)
                self.run_data[field] = original

    def test_warm_a_rejects_skipping_truncation_and_incomplete_work(self):
        for field, value in (("completed", False), ("skipped", True), ("truncated", "frames"),
                             ("kinds_done", 3), ("vfx_pending", 1), ("vfx_total", 0)):
            with self.subTest(field=field):
                warm_a = self.run_data["warm_a"]
                original = warm_a[field]
                warm_a[field] = value
                result = self.summary()
                self.assertFalse(result["passed"])
                self.assertFalse(result["warm_a_complete"])
                self.assertTrue(result["warm_b_complete"])
                warm_a[field] = original

    def test_warm_b_rejects_skipping_truncation_and_missing_special_draws(self):
        for field, value in (("skipped", True), ("truncated", "budget"), ("rooms", 1),
                             ("roar_icon", {"completed": True, "retained": False}),
                             ("occlusion_overlay", {"applicable": True, "completed": True, "restored": False})):
            with self.subTest(field=field):
                warm_b = self.run_data["warm_b"]
                original = warm_b[field]
                warm_b[field] = value
                result = self.summary()
                self.assertFalse(result["passed"])
                self.assertTrue(result["warm_a_complete"])
                self.assertFalse(result["warm_b_complete"])
                warm_b[field] = original
        self.run_data["warm_b"]["occlusion_overlay"] = {"applicable": False}
        self.assertTrue(self.summary()["passed"])

    def test_box_resource_loading_is_checked_separately(self):
        warm = self.run_data["warm_b"]
        for payload in ({"completed": True}, {"completed": False, "entries": []},
                        {"completed": True, "entries": [{"path": "res://normal.tscn", "kinds": ["alias"], "state": "failed"}]}):
            with self.subTest(payload=payload):
                warm["box_enemy_resources"] = payload
                result = self.summary()
                self.assertFalse(result["box_enemy_resources_complete"])
                self.assertFalse(result["passed"])
        warm.pop("box_enemy_resources")
        self.assertFalse(self.summary()["passed"])
        for state in ("loaded", "reused"):
            warm["box_enemy_resources"] = {"completed": True, "entries": [
                {"path": "res://normal.tscn", "kinds": ["alias"], "state": state},
            ]}
            self.assertTrue(self.summary()["passed"])

    def test_route_damage_and_chest_remain_required(self):
        for index, field, value in ((0, "current_room", "start"), (1, "hp_after", 2), (2, "created", False)):
            with self.subTest(event=index):
                details = self.run_data["events"][index]["details"]
                original = details[field]
                details[field] = value
                self.assertFalse(self.summary()["passed"])
                details[field] = original

    def test_exit_cleanup_is_independent_from_frame_budget(self):
        summary = self.summary()
        errors, warnings = classify_console([
            "WARNING: invalid UID, using text path instead\n",
            "WARNING: 1 ObjectDB instance was leaked at exit (run with --verbose for details).\n",
            "WARNING: 42 ObjectDB instances were leaked at exit (run with --verbose for details).\n",
            "ERROR: 2 resources still in use at exit\n",
            "  SCRIPT ERROR: failed verification callback\n",
            "ERROR: unable to open scene\n",
        ])
        self.assertEqual(errors, 2)
        self.assertEqual(len(warnings), 3)
        blocked = finalize_summary(summary, sources_stable=True, execution_ok=True, exit_warnings=warnings)
        self.assertTrue(blocked["frame_gate_passed"])
        self.assertFalse(blocked["shutdown_clean"])
        self.assertFalse(blocked["passed"])
        clean = finalize_summary(summary, sources_stable=True, execution_ok=True, exit_warnings=[])
        self.assertTrue(clean["shutdown_clean"] and clean["passed"])
        self.assertFalse(finalize_summary(summary, sources_stable=False, execution_ok=True, exit_warnings=[])["passed"])
        self.assertFalse(finalize_summary(summary, sources_stable=True, execution_ok=False, exit_warnings=[])["passed"])

    def test_existing_p99_and_max_limits(self):
        for typical_ms, peak_ms, expected in ((33.3, 50.0, True), (33.4, 50.0, False), (33.3, 50.01, False)):
            with self.subTest(typical_ms=typical_ms, peak_ms=peak_ms):
                self.run_data["samples"] = [["enter/r1", typical_ms]] * 99 + [["enter/r1", peak_ms]]
                result = self.summary()
                self.assertEqual(result["passed"], expected)
                self.assertEqual(result["violations"], [] if expected else ["enter/r1"])


if __name__ == "__main__":
    unittest.main()
