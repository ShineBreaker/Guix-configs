#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""kb_viz — 知识库 Web 可视化生成器（CLI 入口）

负责 argparse 注册、--serve 阻塞服务、xdg-open 调度。
数据预处理在 kb_viz_data.py；HTML/CSS/JS 模板在 kb_viz_html.py。
"""

import argparse
import http.server
import os
import signal
import socketserver
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

from kb_core import KB_ROOT, _load_index

from kb_viz_data import compute_stats, memory_overview, parse_filter, top_techs
from kb_viz_html import generate_html


# ═══════════════════════════════════════════════════════════════════════════════
# 常量
# ═══════════════════════════════════════════════════════════════════════════════

DEFAULT_OUTPUT = str(KB_ROOT / "kb-viz.html")
DEFAULT_PORT = 8765
SERVE_PROBE_TIMEOUT = 5.0
SERVE_PROBE_INTERVAL = 0.1


# ═══════════════════════════════════════════════════════════════════════════════
# 浏览器 / 服务器
# ═══════════════════════════════════════════════════════════════════════════════


def _open_in_browser(path: str) -> None:
    """用 xdg-open 打开本地文件或 URL。"""
    try:
        subprocess.Popen(["xdg-open", path])
        print("🌐 已在浏览器中打开。")
    except FileNotFoundError:
        print("⚠ xdg-open 不可用，请手动打开:", path)
    except OSError as e:
        print(f"⚠ xdg-open 失败: {e}")


def _serve(path: Path, port: int, should_open: bool) -> None:
    """阻塞式 HTTP 服务器，Ctrl-C 退出。"""
    workdir = path.parent
    workdir.mkdir(parents=True, exist_ok=True)
    filename = path.name
    url = f"http://localhost:{port}/{filename}"

    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, format, *args):  # noqa: A002 — 基类签名
            pass

        def do_GET(self):  # noqa: N802 — 基类签名
            try:
                super().do_GET()
            except (BrokenPipeError, ConnectionResetError):
                pass

    saved_cwd = os.getcwd()
    os.chdir(str(workdir))
    try:
        class ReuseTCPServer(socketserver.TCPServer):
            allow_reuse_address = True

        httpd = ReuseTCPServer(("", port), QuietHandler)
        # 端口探测：等服务就绪后再打开
        deadline = time.time() + SERVE_PROBE_TIMEOUT
        ready = False
        while time.time() < deadline:
            try:
                with urllib.request.urlopen(url, timeout=0.2) as r:
                    if r.status == 200:
                        ready = True
                        break
            except Exception:
                time.sleep(SERVE_PROBE_INTERVAL)
        if not ready:
            print(f"⚠ 端口 {port} 在 {SERVE_PROBE_TIMEOUT}s 内未就绪，仍尝试打开。")
        if should_open:
            _open_in_browser(url)
        print(f"🌐 浏览器已请求: {url}")
        print("按 Ctrl-C 停止服务器。")

        def _stop(_signum, _frame):
            raise KeyboardInterrupt

        signal.signal(signal.SIGINT, _stop)
        signal.signal(signal.SIGTERM, _stop)
        signal.signal(signal.SIGPIPE, signal.SIG_IGN)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n服务器已停止")
        finally:
            httpd.server_close()
    finally:
        os.chdir(saved_cwd)


# ═══════════════════════════════════════════════════════════════════════════════
# cmd_viz
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_viz(args: argparse.Namespace) -> None:
    """生成知识库可视化 HTML 页面。"""
    index = _load_index()
    if not index.get("cards"):
        print("❌ 知识库索引为空。请先运行 'kb reindex' 重建索引。")
        return

    memory = memory_overview()
    cards = index["cards"]
    stats = compute_stats(cards, memory)
    techs = top_techs(cards, limit=8)
    init_filter = parse_filter(args.filter or "")
    init_search = args.search or ""

    html = generate_html(
        updated=index.get("updated", ""),
        cards=cards,
        stats=stats,
        top_techs=techs,
        theme=args.theme,
        init_filter=init_filter,
        init_search=init_search,
    )

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html, encoding="utf-8")
    print(f"✅ 可视化页面已生成: {out}")

    if args.serve:
        _serve(out, args.port, args.open_browser)
        return
    if args.open_browser:
        _open_in_browser(str(out))


# ═══════════════════════════════════════════════════════════════════════════════
# argparse（kb 脚本会注册到自己的子命令解析器）
# ═══════════════════════════════════════════════════════════════════════════════


def add_viz_parser(subparsers) -> argparse.ArgumentParser:
    """向外部 argparse 子解析器注册 viz 子命令。"""
    p = subparsers.add_parser("viz", help="生成知识库可视化 Web 页面")
    p.add_argument(
        "--output", "-o", default=DEFAULT_OUTPUT,
        help=f"输出文件路径（默认 {DEFAULT_OUTPUT}）",
    )
    p.add_argument(
        "--open", dest="open_browser", action="store_true", default=True,
        help="生成后用 xdg-open 打开（默认）",
    )
    p.add_argument(
        "--no-open", dest="open_browser", action="store_false",
        help="不打开浏览器",
    )
    p.add_argument(
        "--serve", action="store_true",
        help="启动本地 HTTP 服务器阻塞运行，Ctrl-C 退出",
    )
    p.add_argument(
        "--port", type=int, default=DEFAULT_PORT,
        help=f"--serve 监听端口（默认 {DEFAULT_PORT}）",
    )
    p.add_argument(
        "--theme", choices=["light", "dark", "auto"], default="auto",
        help="初始主题（默认 auto，跟随系统）",
    )
    p.add_argument(
        "--filter", dest="filter", default="",
        help="初始过滤，语法: category=guix,status=stable",
    )
    p.add_argument(
        "--search", default="",
        help="初始搜索关键词",
    )
    return p


# ═══════════════════════════════════════════════════════════════════════════════
# 独立运行（仅调试 / 手动）
# ═══════════════════════════════════════════════════════════════════════════════


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="kb_viz", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    add_viz_parser(sub)
    args = parser.parse_args(argv)
    if args.command == "viz":
        cmd_viz(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
