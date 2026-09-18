#!/usr/bin/env node
// ArtFlow CLI：AI agent 批量视频生成接入工具（零依赖，Node >= 18）
// 用法：node scripts/artflow.mjs <command> [flags]   完整文档见 references/cli-commands.md

import { parseArgs, getStr } from "./args.mjs";
import { CliError, emitJson, emitError, parseDuration, progress } from "./output.mjs";
import { resolveRuntime } from "./config.mjs";
import { ArtFlowClient } from "./api.mjs";
import {
  cmdLogin, cmdLogout, cmdWhoami, cmdDoctor, cmdTypes,
  cmdUpload, cmdSubmit, cmdStatus, cmdList, cmdWait,
  cmdCancel, cmdRerun, cmdRecover, cmdDelete, cmdDownload, cmdBatch,
} from "./commands.mjs";

const COMMANDS = {
  login: cmdLogin,
  logout: cmdLogout,
  whoami: cmdWhoami,
  doctor: cmdDoctor,
  types: cmdTypes,
  upload: cmdUpload,
  submit: cmdSubmit,
  status: cmdStatus,
  list: cmdList,
  wait: cmdWait,
  cancel: cmdCancel,
  rerun: cmdRerun,
  recover: cmdRecover,
  delete: cmdDelete,
  download: cmdDownload,
  batch: cmdBatch,
};

const HELP = `ArtFlow CLI — AI agent 视频生成接入工具（ArtFlow 平台）

用法：node \${SKILL_DIR}/scripts/artflow.mjs <command> [flags]

命令：
  login --feishu                               飞书设备码登录（与网页同账号，唯一登录方式）
  logout                                       清除本地凭据
  whoami                                       当前身份
  doctor                                       自检（连通性/鉴权/注册表）
  types [type]                                 任务类型与参数
  upload <file...> [--kind image|video|audio]  上传参考素材
  submit --type T [--prompt ...] [--dry-run]   提交任务（或 --json/--json-file 原始模式）
  status <jobId...>                            查询任务
  list [--type --status --limit --mine]        最近任务列表
  wait <jobId...> [--timeout 4h] [--download dir]  等待任务完成
  cancel / rerun / recover / delete <jobId>    任务操作
  download <jobId...> --out-dir dir            下载成品
  batch <jobs.jsonl> [--wait --out results.jsonl --stream]  批量提交

全局：--base-url <url>（默认 https://artflow.hnfunny.com）--timeout-per-request 60s --quiet
环境变量：ARTFLOW_CLI_BASE_URL / ARTFLOW_CLI_CONFIG（凭据来自 login --feishu 保存的本机配置）

输出：stdout 恰好一个 JSON；stderr 进度与错误 JSON。退出码 0 成功 / 1 CLI 错误 / 2 任务级失败。
文档：references/cli-commands.md`;

export async function main(argv) {
  if (argv.length === 0 || argv[0] === "help" || argv[0] === "--help") {
    process.stdout.write(HELP + "\n");
    return 0;
  }
  if (argv[0] === "version" || argv[0] === "--version") {
    emitJson({ name: "artflow-cli", version: "2.0.1" });
    return 0;
  }

  const { command, positionals, flags } = parseArgs(argv);
  const handler = COMMANDS[command];
  if (!handler) {
    throw new CliError("USAGE", `未知命令：${command}（运行 help 查看全部命令）`);
  }

  const runtime = resolveRuntime({
    baseUrl: getStr(flags, "base-url"),
    username: getStr(flags, "username"),
  });

  const client = new ArtFlowClient({
    baseUrl: runtime.baseUrl,
    token: runtime.token,
    requestTimeoutMs: parseDuration(getStr(flags, "timeout-per-request"), 60_000),
  });

  if (getBoolFlag(flags, "quiet")) process.env.ARTFLOW_CLI_QUIET = "1";

  const uploadCache = new Map();
  const ctx = {
    client,
    flags,
    positionals,
    runtime,
    mediaHelpers() {
      return {
        client,
        uploadCache,
        onWarn: (message) => progress(message),
      };
    },
  };

  const { exitCode, result } = await handler(ctx);
  emitJson(result);
  return exitCode;
}

function getBoolFlag(flags, key) {
  const v = flags.get(key);
  return v !== undefined;
}

// 入口：错误统一走 stderr JSON + 退出码；正常路径 stdout 只有一个 JSON
main(process.argv.slice(2)).then(
  (code) => {
    process.exitCode = code || 0;
  },
  (err) => {
    emitError(err);
    process.exitCode = err.exitCode || (err instanceof CliError ? 1 : 1);
  },
);
