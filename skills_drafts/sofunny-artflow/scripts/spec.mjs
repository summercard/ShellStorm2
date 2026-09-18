// 任务类型 spec：flags → v2 job body（对照 public/minimax-h3.js、public/ltx-video.js 的提交结构）
// 素材字段支持：http(s) URL 原样 / 服务端相对路径原样 / @路径或存在的本地文件 → 自动上传

import fs from "node:fs";
import path from "node:path";
import { CliError } from "./output.mjs";
import { getStr, getNum, getBool, getList } from "./args.mjs";

export const WARN_UPLOAD_BYTES = 150 * 1024 * 1024;
export const MAX_UPLOAD_BYTES = 180 * 1024 * 1024;

const EXT_KIND = {
  png: "image", jpg: "image", jpeg: "image", webp: "image", gif: "image", bmp: "image",
  mp4: "video", mov: "video", webm: "video", m4v: "video", mkv: "video",
  mp3: "audio", wav: "audio", flac: "audio", ogg: "audio", m4a: "audio", aac: "audio", opus: "audio",
};

const EXT_MIME = {
  png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", webp: "image/webp",
  gif: "image/gif", bmp: "image/bmp",
  mp4: "video/mp4", mov: "video/quicktime", webm: "video/webm", m4v: "video/x-m4v", mkv: "video/x-matroska",
  mp3: "audio/mpeg", wav: "audio/wav", flac: "audio/flac", ogg: "audio/ogg",
  m4a: "audio/mp4", aac: "audio/aac", opus: "audio/opus",
};

export function inferKind(filePath) {
  const ext = path.extname(filePath).slice(1).toLowerCase();
  return EXT_KIND[ext] || "";
}

function inferMime(filePath) {
  const ext = path.extname(filePath).slice(1).toLowerCase();
  return EXT_MIME[ext] || "application/octet-stream";
}

// 读取本地文件 → data_url，超限报错
export async function readAsDataUrl(filePath, { maxBytes = MAX_UPLOAD_BYTES, warnBytes = WARN_UPLOAD_BYTES, onWarn } = {}) {
  const stat = fs.statSync(filePath);
  if (stat.size > maxBytes) {
    throw new CliError("UPLOAD_TOO_LARGE", `文件过大：${filePath}（${(stat.size / 1024 / 1024).toFixed(1)}MB，上限 ${Math.round(maxBytes / 1024 / 1024)}MB）`, {
      hint: "超大素材请改用公网可访问的 URL 直接传入",
    });
  }
  if (stat.size > warnBytes && onWarn) {
    onWarn(`[upload] 文件较大（${(stat.size / 1024 / 1024).toFixed(1)}MB），上传可能较慢：${filePath}`);
  }
  const buffer = fs.readFileSync(filePath);
  return `data:${inferMime(filePath)};base64,${buffer.toString("base64")}`;
}

// 素材值解析：URL/相对路径原样；@path 或存在的本地路径 → 上传后取 local_url（本地 Comfy 类型服务端自拉）
export async function resolveMediaValue(value, kind, { client, uploadCache, maxBytes, warnBytes, onWarn }) {
  const text = String(value || "").trim();
  if (!text) return "";
  if (/^https?:\/\//i.test(text)) return text;
  let filePath = null;
  if (text.startsWith("@")) {
    filePath = text.slice(1);
    if (!fs.existsSync(filePath)) {
      throw new CliError("VALIDATION", `素材文件不存在：${filePath}`);
    }
  }
  else if (fs.existsSync(text) && fs.statSync(text).isFile()) filePath = text;
  if (!filePath) {
    // 本地不存在的 / 开头路径视为服务器路径；其余报错
    if (text.startsWith("/")) return text;
    throw new CliError("VALIDATION", `素材不存在或不是合法 URL：${text}`, {
      hint: "支持 http(s):// URL、以 / 开头的服务端路径、@本地文件路径",
    });
  }
  const resolved = path.resolve(filePath);
  const mediaKind = kind || inferKind(resolved);
  if (!mediaKind) {
    throw new CliError("VALIDATION", `无法识别素材类型（扩展名未知）：${filePath}`);
  }
  const cacheKey = `${mediaKind}:${resolved}`;
  if (uploadCache && uploadCache.has(cacheKey)) return uploadCache.get(cacheKey);
  const dataUrl = await readAsDataUrl(resolved, { maxBytes, warnBytes, onWarn });
  const result = await client.uploadMedia(resolved, mediaKind, dataUrl);
  const url = (result && (result.local_url || result.url)) || "";
  if (!url) throw new CliError("HTTP", "上传成功但服务端未返回 URL", { body: result });
  if (uploadCache) uploadCache.set(cacheKey, url);
  return url;
}

// ---- 类型表 ----

export const TYPE_SPECS = {
  minimax_h3: {
    label: "MiniMax H3 视频/音频（本地 Comfy）",
    kind: "payload",
    mediaFields: {
      first_frame_url: { kind: "image", multiple: false },
      last_frame_url: { kind: "image", multiple: false },
      reference_images: { kind: "image", multiple: true },
      reference_videos: { kind: "video", multiple: true },
      reference_audios: { kind: "audio", multiple: true },
    },
    enums: {
      mode: ["keyframe", "reference"],
      output_kind: ["video", "audio"],
      resolution: ["480p", "720p"],
      ratio: ["16:9", "9:16", "1:1", "4:3", "3:4"],
      duration: [5, 8, 10, 15],
      audio_format: ["mp3", "flac", "opus"],
      ref_image_size: ["match", "max"],
    },
    build(flags) {
      const outputKind = getStr(flags, "output-kind", "video");
      const mode = getStr(flags, "mode", "keyframe");
      const payload = {
        output_kind: outputKind,
        mode,
        audio_format: getStr(flags, "audio-format", "mp3"),
        remove_bgm: outputKind === "audio" ? getBool(flags, "remove-bgm", true) : false,
        clean_audio: outputKind === "audio" ? getBool(flags, "clean-audio", true) : false,
        first_frame_url: getStr(flags, "first-frame", "") || "",
        last_frame_url: getStr(flags, "last-frame", "") || "",
        reference_images: getList(flags, "ref-image"),
        reference_videos: getList(flags, "ref-video").slice(0, 3),
        reference_audios: getList(flags, "ref-audio").slice(0, 3),
        ref_image_size: getStr(flags, "ref-image-size", "match"),
        prompt: getStr(flags, "prompt", "") || "",
        resolution: getStr(flags, "resolution", "480p"),
        ratio: getStr(flags, "ratio", "16:9"),
        duration: getNum(flags, "duration", 5),
        seed: getNum(flags, "seed", -1),
        shift_video: getNum(flags, "shift-video", 12),
        shift_audio: getNum(flags, "shift-audio", 3),
      };
      return { payload, outputKind, mode };
    },
    validate({ payload, mode }) {
      if (!String(payload.prompt || "").trim()) {
        throw new CliError("VALIDATION", "minimax_h3 需要 --prompt");
      }
      if (mode === "reference" && !payload.reference_images.length && !payload.reference_videos.length && !payload.reference_audios.length) {
        throw new CliError("VALIDATION", "reference 模式至少需要一个参考素材（--ref-image/--ref-video/--ref-audio）");
      }
      if (payload.reference_images.length > 9) {
        throw new CliError("VALIDATION", `参考图片最多 9 张，收到 ${payload.reference_images.length}`);
      }
    },
  },

  ltx_video: {
    label: "LTX 2.5 视频/音效（本地 Comfy）",
    kind: "payload",
    mediaFields: {
      first_frame_url: { kind: "image", multiple: false },
      last_frame_url: { kind: "image", multiple: false },
      reference_audio_url: { kind: "audio", multiple: false },
    },
    enums: {
      output_kind: ["video", "audio"],
      resolution: ["768x448", "960x544", "448x768", "768x768"],
      duration: [3, 5, 8],
      audio_format: ["mp3", "flac", "opus"],
    },
    build(flags) {
      const outputKind = getStr(flags, "output-kind", "video");
      const imageStrength = getNum(flags, "image-strength", 0.7);
      const payload = {
        output_kind: outputKind,
        first_frame_url: getStr(flags, "first-frame", "") || "",
        last_frame_url: getStr(flags, "last-frame", "") || "",
        reference_audio_url: getStr(flags, "reference-audio", "") || "",
        prompt: getStr(flags, "prompt", "") || "",
        negative_prompt:
          getStr(
            flags,
            "negative-prompt",
            "blurry, low quality, camera shake, deformed anatomy, flicker, text, watermark, distorted audio",
          ) || "",
        resolution: getStr(flags, "resolution", "768x448"),
        duration: getNum(flags, "duration", 5),
        fps: getNum(flags, "fps", 24),
        seed: getNum(flags, "seed", -1),
        cfg: getNum(flags, "cfg", 1),
        image_strength: imageStrength,
        image_compression: getNum(flags, "image-compression", 18),
        first_frame_strength: getNum(flags, "first-frame-strength", imageStrength),
        last_frame_strength: getNum(flags, "last-frame-strength", 1),
        reference_audio_guidance: getNum(flags, "reference-audio-guidance", 3),
        two_stage_upscale: getBool(flags, "two-stage-upscale", false),
        generate_audio: getBool(flags, "generate-audio", true),
        audio_format: getStr(flags, "audio-format", "mp3"),
        remove_bgm: outputKind === "audio" ? getBool(flags, "remove-bgm", true) : false,
        clean_audio: outputKind === "audio" ? getBool(flags, "clean-audio", true) : false,
      };
      return { payload, outputKind };
    },
    validate({ payload }) {
      if (!String(payload.prompt || "").trim()) {
        throw new CliError("VALIDATION", "ltx_video 需要 --prompt");
      }
    },
  },
};

// ---- 组装 ----

// 深度遍历 mediaFields：单值直接解析，数组逐项解析（空值跳过）
export async function materializeMedia(payload, mediaFields, helpers) {
  const next = { ...payload };
  for (const [field, spec] of Object.entries(mediaFields)) {
    const value = next[field];
    if (value === undefined || value === null || value === "") continue;
    if (spec.multiple) {
      if (!Array.isArray(value)) {
        throw new CliError("VALIDATION", `字段 ${field} 应为数组`);
      }
      const resolved = [];
      for (const item of value) {
        if (item === "" || item === null || item === undefined) continue;
        resolved.push(await resolveMediaValue(item, spec.kind, helpers));
      }
      next[field] = resolved;
    } else {
      next[field] = await resolveMediaValue(value, spec.kind, helpers);
    }
  }
  return next;
}

// 友好模式：flags → 完整 job body（含素材自动上传）
export async function buildJobBody(type, flags, helpers) {
  const spec = TYPE_SPECS[type];
  if (!spec) {
    throw new CliError("VALIDATION", `未知任务类型：${type}`, {
      hint: "运行 types 查看支持的类型；或用 --json 原始模式提交任意类型",
    });
  }
  const built = spec.build(flags);
  spec.validate(built);
  const payload = await materializeMedia(built.payload, spec.mediaFields, helpers);
  const body = {
    type,
    node_id: getStr(flags, "node-id", "codex-cli"),
    workflow_id: getStr(flags, "workflow-id", "codex-cli"),
    payload,
  };
  return body;
}

// 原始模式 body 里的素材字段（batch 行内 @path 用）：按类型字段表扫描 payload
export async function materializeRawBody(body, helpers) {
  const spec = TYPE_SPECS[body && body.type];
  if (!spec || !body.payload) return body;
  const payload = await materializeMedia(body.payload, spec.mediaFields, helpers);
  return { ...body, payload };
}
