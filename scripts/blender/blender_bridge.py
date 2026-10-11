"""BlenderMCP addon 直连桥（不依赖宿主加载 MCP 工具）。

协议: TCP + 单个 JSON 对象，请求 {"type": ..., "params": {...}}，响应 JSON。
服务端由 Blender 侧 addon.py 的 "Connect to MCP server" 启动，默认端口 9876。

用法:
    python blender_bridge.py <cmd> [json_params]
    python blender_bridge.py --code "bpy 代码"
    python blender_bridge.py --code-file path/to/code.py
    python blender_bridge.py --port 9876 <cmd>

内置命令: get_scene_info / get_object_info / get_viewport_screenshot / execute_code
"""

import argparse
import json
import socket
import sys

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 9876
DEFAULT_TIMEOUT = 180


def call(command, host=DEFAULT_HOST, port=DEFAULT_PORT, timeout=DEFAULT_TIMEOUT):
    sock = socket.create_connection((host, port), timeout=timeout)
    sock.settimeout(timeout)
    try:
        sock.sendall(json.dumps(command).encode("utf-8"))
        buf = b""
        while True:
            try:
                chunk = sock.recv(65536)
            except socket.timeout:
                break
            if not chunk:
                break
            buf += chunk
            try:
                return json.loads(buf.lstrip(b"\x00").decode("utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
        if not buf:
            raise RuntimeError("连接成功但没有收到任何响应（addon 可能未启动服务器）")
        return json.loads(buf.lstrip(b"\x00").decode("utf-8"))
    finally:
        sock.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", nargs="?", default=None)
    ap.add_argument("params", nargs="?", default="{}")
    ap.add_argument("--code", default=None)
    ap.add_argument("--code-file", default=None)
    ap.add_argument("--host", default=DEFAULT_HOST)
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT)
    ap.add_argument("--raw", action="store_true", help="原样打印 JSON，不做美化")
    args = ap.parse_args()

    if args.code_file:
        with open(args.code_file, "r", encoding="utf-8") as f:
            code = f.read()
        command = {"type": "execute_code", "params": {"code": code}}
    elif args.code:
        command = {"type": "execute_code", "params": {"code": args.code}}
    elif args.cmd:
        try:
            params = json.loads(args.params)
        except json.JSONDecodeError:
            params = {}
        command = {"type": args.cmd, "params": params}
    else:
        ap.error("需要 <cmd> 或 --code / --code-file")

    try:
        resp = call(command, args.host, args.port, args.timeout)
    except ConnectionRefusedError:
        print(
            f"[bridge] 连不上 {args.host}:{args.port}（连接被拒绝）。\n"
            "         Blender 侧 MCP 服务没启动：3D 视图按 N -> BlenderMCP 侧栏 -> "
            "点「Connect to MCP server」。",
            file=sys.stderr,
        )
        return 2
    except (socket.timeout, TimeoutError):
        print(
            f"[bridge] {args.host}:{args.port} 连上了但超时没回包。\n"
            "         常见原因：Blender 里弹着模态对话框 / 正在拖拽，命令排队在主线程没执行。",
            file=sys.stderr,
        )
        return 2
    except OSError as exc:
        print(f"[bridge] 连接失败 {args.host}:{args.port}: {exc}", file=sys.stderr)
        return 2

    print(json.dumps(resp, ensure_ascii=False, indent=2) if not args.raw
          else json.dumps(resp, ensure_ascii=False))
    ok = isinstance(resp, dict) and resp.get("status") == "success"
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())