// 零依赖参数解析：--key=value / --key value / 可重复 flag 聚合 / 布尔 flag / -- 分隔
// 返回 { command, positionals, flags }，flags 是 Map<string, string[] | true>

export class UsageError extends Error {
  constructor(message) {
    super(message);
    this.code = "USAGE";
  }
}

export function parseArgs(argv) {
  const positionals = [];
  const flags = new Map();
  let i = 0;

  const pushFlag = (key, value) => {
    if (value === true) {
      if (flags.has(key)) {
        const prev = flags.get(key);
        if (prev !== true) flags.set(key, prev);
      } else {
        flags.set(key, true);
      }
      return;
    }
    const prev = flags.get(key);
    if (prev === true || prev === undefined) flags.set(key, [value]);
    else prev.push(value);
  };

  const looksLikeFlag = (text) => text.startsWith("-") && !/^-\d/.test(text);

  while (i < argv.length) {
    const arg = argv[i];
    if (arg === "--") {
      for (let j = i + 1; j < argv.length; j++) positionals.push(argv[j]);
      break;
    }
    if (arg === "-" || !arg.startsWith("-")) {
      positionals.push(arg);
      i += 1;
      continue;
    }
    let key = arg;
    let inlineValue;
    const eq = arg.indexOf("=");
    if (eq !== -1) {
      key = arg.slice(0, eq);
      inlineValue = arg.slice(eq + 1);
    }
    if (!key.startsWith("--")) {
      // 不支持单字母短 flag 组合；约定短 flag 一律 --xxx
      throw new UsageError(`不支持的参数形式：${arg}（请使用 --key value 形式）`);
    }
    const name = key.slice(2);
    if (!name) throw new UsageError(`不支持的参数形式：${arg}`);
    if (inlineValue !== undefined) {
      pushFlag(name, inlineValue);
      i += 1;
      continue;
    }
    // 布尔 flag：后一个参数不存在 / 是下一个 flag（负数除外，如 --seed -1）→ 视为 true
    const next = argv[i + 1];
    if (next === undefined || next === "--" || looksLikeFlag(next)) {
      pushFlag(name, true);
      i += 1;
    } else {
      pushFlag(name, next);
      i += 2;
    }
  }

  const command = positionals.shift() || "";
  return { command, positionals, flags };
}

export function getStr(flags, key, def = undefined) {
  const v = flags.get(key);
  if (v === undefined || v === true) return def;
  return String(v[v.length - 1]);
}

export function getNum(flags, key, def = undefined) {
  const raw = getStr(flags, key);
  if (raw === undefined) return def;
  const n = Number(raw);
  if (!Number.isFinite(n)) throw new UsageError(`--${key} 需要数字，收到：${raw}`);
  return n;
}

export function getBool(flags, key, def = false) {
  const v = flags.get(key);
  if (v === undefined) return def;
  if (v === true) return true;
  const raw = String(v[v.length - 1]).trim().toLowerCase();
  if (["false", "0", "no", "off"].includes(raw)) return false;
  return true;
}

export function getList(flags, key) {
  const v = flags.get(key);
  if (v === undefined || v === true) return [];
  return [...v];
}

export function hasFlag(flags, key) {
  return flags.has(key);
}
