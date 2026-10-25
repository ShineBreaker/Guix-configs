#!/usr/bin/env python3
"""把一份 Markdown 报告投递到 dsh-im 已保存的主动投递目标（QQ 私聊）。

配置：与本脚本同目录的 qq-target.json（缺失即视为未配置）
    {"botId": "...", "targetId": "...", "baseUrl": "http://127.0.0.1:3080"}
用法：python3 qq-deliver.py <report.md>
输出：一行 JSON。exit 0=已投递，2=未配置目标，1=失败。
"""
import json
import pathlib
import sys
import urllib.request

# 配置跟着脚本走：仓库源与 stow 部署位（软链）解析到同一份文件
CFG = pathlib.Path(__file__).resolve().parent / "qq-target.json"


def main() -> int:
    if len(sys.argv) != 2:
        print(json.dumps({"sent": False, "reason": "usage: qq-deliver.py <report.md>"}))
        return 1
    report = pathlib.Path(sys.argv[1])
    if not report.is_file():
        print(json.dumps({"sent": False, "reason": "report-not-found", "path": str(report)}))
        return 1
    text = report.read_text(encoding="utf-8")
    if not text.strip():
        print(json.dumps({"sent": False, "reason": "empty-report"}))
        return 1
    if not CFG.is_file():
        print(json.dumps({"sent": False, "reason": "no-target", "config": str(CFG)}))
        return 2
    cfg = json.loads(CFG.read_text(encoding="utf-8"))
    payload = json.dumps({
        "botId": cfg["botId"],
        "targetId": cfg["targetId"],
        "text": text,
        "format": "markdown",
    }).encode()
    base = cfg.get("baseUrl", "http://127.0.0.1:3080").rstrip("/")
    req = urllib.request.Request(
        base + "/api/dsh-im/delivery/messages",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            out = json.loads(resp.read().decode() or "{}")
    except Exception as exc:  # noqa: BLE001 - 报告失败原因，不吞掉
        print(json.dumps({"sent": False, "reason": "request-failed", "detail": str(exc)}))
        return 1
    if out.get("sent") is True:
        print(json.dumps({"sent": True}))
        return 0
    print(json.dumps({"sent": False, "reason": "rejected", "response": out}))
    return 1


if __name__ == "__main__":
    sys.exit(main())
