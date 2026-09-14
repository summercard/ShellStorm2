export const fixedSurface = item => Boolean(item?.surfaceSettings) && item.surfaceSettings.kind !== 'column';
export const unitScale = scale => ['x','y','z'].every(axis => Math.abs((scale?.[axis] ?? 1)-1) < 1e-6);
export function validateFixedModules(payload) {
  for (const item of payload.components || []) {
    if (!(fixedSurface(item) || item.stairwellSettings || item.stairSettings)) continue;
    const group = (payload.groups || []).find(group => group.name === item.group);
    if (!unitScale(item.scale) || (group && !unitScale(group.scale))) throw new Error(`墙壁和地板不能缩放，请拼接组件：${item.name}`);
    if (!fixedSurface(item)) continue;
    const s = item.surfaceSettings;
    const keys = s.kind === 'wall' ? ['width','height','thickness'] : ['length','width','thickness'];
    if (keys.some(key => !Number.isFinite(s[key]) || s[key] <= 0)) throw new Error(`无效组件尺寸：${item.name}`);
  }
}
