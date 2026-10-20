---
name: static-site-localization
description: Use when asked to put a browser tool or static web app on a local or remote machine while keeping its live data services online, to make a site locally accessible without promising offline operation, or to export the local site's generated 3D scene as a model (GLB/OBJ/FBX) imported into Blender.
---

# Localize a Static Frontend

## When
- The user asks to make a web tool local, self-host its frontend, or use a site's UI from a LAN/Tailnet host.
- The user chooses a local-frontend/online-data deployment rather than a fully offline mirror.
- The local site generates a 3D scene and the user wants a model (GLB/OBJ/FBX) to import into Blender — see `references/3d-model-export.md`.

## Steps
1. Inspect the site before copying. Fetch the page and enumerate its script, stylesheet, and asset references. Read the loader/module code enough to distinguish files that can be served locally from runtime data services. Record external endpoints such as map tiles, elevation tiles, geocoding, Overpass, or CDN APIs; do not imply that downloading HTML makes those services local.
2. Build a minimal local tree containing the entry HTML and every required local static dependency. Download without conversion, preserve relative paths, and verify each file is non-empty. If the page is a single inline bundle plus one library, do not mirror unrelated runtime data or the whole upstream site.
3. Transfer to the target host as one archive when the target is remote: create a tar.gz locally with `COPYFILE_DISABLE=1`, copy the archive, extract into a new target directory, then count and checksum the extracted files. A successful transfer command alone is not proof that the target tree is complete.
4. Start a simple local HTTP server from the target directory on an unused port, bound to `0.0.0.0`; do not use `file://` because relative modules, fetches, and browser security behavior differ. Preserve the chosen path and PID in a small local state file so a later check can distinguish an existing server from a new launch.
5. Verify from both sides: request `/` on the target itself and through its LAN/Tailnet address, require HTTP 200 and the expected content length/type, confirm the server process and listening socket, and report the exact URL. If browser automation is available, open the URL and check the page loads; otherwise state that only HTTP delivery was verified.
6. Explain the boundary explicitly: this is a local frontend with online data. For offline use, plan a separate bounded cache of the required location's OSM/building, elevation, and map-tile data; do not present it as complete until those runtime requests are captured and served locally.

## Export the site's 3D scene as a model (branch)
When the local site generates a 3D scene and the user asks for a model to import into Blender (GLB/OBJ/FBX), read `references/3d-model-export.md`. Essentials: prefer the site's own exporter; verify a completed scene before exporting; if the normal download yields no file, use the page's in-memory exporter through CDP; a timeout means a clearly labeled lightweight export, never a silent substitute; import with headless Blender and verify by exit 0 plus a reported object count.

## Decision rules
- Prefer local frontend + external data when the user asks for the easiest local deployment; do not mirror global geographic data unnecessarily.
- After an interrupted attempt, inspect the target directory, port, PID, and logs before copying or starting anything; resume only missing steps.
- Use a new directory and an unused port; do not overwrite an existing project or service without identifying it first.
- Keep upstream attribution and license files in the local tree, and tell the user which external data providers remain in use.

## Done when
The target contains the verified static files, its server is listening, local and remote HTTP checks return 200, the exact URL and online-data boundary are reported, and no claim of offline operation is made without verifying cached runtime data. For the export branch, the model imported into Blender and its paths were reported (`references/3d-model-export.md`).
