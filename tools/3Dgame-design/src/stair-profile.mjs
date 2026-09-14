// Profile coordinates are Blender Z-up, with the origin at the upper endpoint.
export function stairProfileParts(profile, settings) {
  const count = Math.max(4, Math.round(settings.stepCount));
  const run = Math.max(3, Number(settings.runLength));
  const rise = run * Math.tan(Math.max(5, Math.min(60, settings.slopeDeg)) * Math.PI / 180);
  const parts = [];
  for (const part of profile.parts) {
    if ((settings.omitParts || []).includes(part.name)) continue;
    const repeats = part.role === 'tread' ? count : 1;
    for (let i = 0; i < repeats; i++) {
      const vertices = part.vertices.map(([x, y, z]) => {
        if (part.role === 'tread') {
          return [x * (settings.width - .42) / 5.58,
            (i + .5) * run / count + .125 + (y - .5) * (run / count - .03) / .72,
            z - i * rise / count];
        }
        return [x * settings.width / 6, y * run / 15,
          z + y * .4 - y / 15 * rise + (part.role === 'guard' ? settings.handrailHeight - 1.2 : 0)];
      });
      parts.push({ name: part.role === 'tread' ? `踏步_${i + 1}` : part.name, vertices, faces: part.faces });
    }
  }
  return parts;
}
