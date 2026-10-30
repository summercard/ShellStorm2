"""Manor v017 export workflow.
1. In the live Blender MCP session with the raw master open, run prepare_manor_export.py.
2. Reopen the persisted optimized file in a clean Blender process with --background
   --factory-startup --python scripts/blender/write_manor_glbs.py.
3. Run validate_manor_packages.py, build_manor_prefabs.py, then isolated Godot checks.
Modeling and visual iteration use live MCP. Batch conversion excludes the unused
reference scene; exporting that alongside the gallery crashes Blender 4.5.
"""
