# Exporting the Site's 3D Scene as a Model

Read this when the local site **generates a 3D scene** and the user asks for a model (GLB/OBJ/FBX) they can import into Blender. Prefer the site's own exporter; the result is a generated blockout from the site's available map/elevation data, not an upstream source project. Do this branch once the frontend is up and reachable — the localization steps themselves are in the main skill.

1. Build the requested location and verify the page exposes a completed scene/data state before exporting. If browser automation cannot reach a private LAN URL, use a local SSH tunnel or run headless Chromium on the host that serves the page; do not claim a browser-rendered check from an HTTP-only check.
2. If the normal download does not produce a file, inspect the page's export handler and use its in-memory exporter through CDP. A browser download failure does not prove that the scene or exporter failed.
3. Large vegetation/remote-detail exports can exceed headless time or memory. First try the full export; if it times out, make a clearly labeled lightweight export by skipping vegetation and far/background objects while retaining buildings, roads, terrain, and urban props. Do not silently call that equivalent to the full export.
4. Extract the returned `ArrayBuffer`/`Uint8Array` in bounded base64 chunks (rather than one oversized CDP result), write the binary on the serving host, check the file type and size, then import it with headless Blender (`blender -b --python ...`). Save a separate `.blend` beside the source model; never overwrite an existing Blender scene without explicit authorization.
5. Verify the import by requiring Blender exit 0, the glTF import completion message, a saved `.blend`, and a reported object count. Report omitted categories, attribution requirements, and the exact `.glb`/`.blend` paths.

## Decision rules
- After an interrupted attempt, inspect the download directory and the Blender destination before retrying, so a partial file is not mistaken for a completed artifact.
- Keep exported models and imported `.blend` files in a separate, clearly named subdirectory.
- Preserve the site's map-data attribution when distributing exported models.

## Done when
Blender imported the model (exit 0, glTF completion message, a saved `.blend`, reported object count), the exact `.glb`/`.blend` paths are reported, and any omitted categories or attribution requirements are stated.
