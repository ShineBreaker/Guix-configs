#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
menu_translate.py - 菜单英文提取与文件式翻译工作流

推荐流程：
1. `prepare`：按包名自动执行“查找源码 -> 扫描 -> 导出 JSON”；
2. 把 JSON 文件内容交给另一个 AI CLI，只让它填写 `target`；
3. `render-elisp`：读取翻译后的 JSON，生成可直接复制粘贴的 Elisp 文件。

兼容的手动流程仍然保留：
1. `scan`：扫描目录/文件，更新“已翻译文件/未翻译文件”索引；
2. `extract-file`：把待翻译菜单项导出成一个单独 JSON 文件。
"""

from __future__ import annotations

import argparse
import gzip
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Iterable


DEFAULT_TARGET = Path(__file__).with_name("context-menu.el")
DEFAULT_INDEX = Path(__file__).with_name("menu_translate_index.json")
DEFAULT_BATCH = Path(__file__).with_name("menu_translate_batch.json")
DEFAULT_PROMPT_TEMPLATE = Path(__file__).with_name("menu_translate_prompt.txt")

STRING_RE = r'"((?:\\.|[^"\\])*)"'

# easy-menu 向量项，如 ["Find file" projectile-find-file]
# 前面要求是行首或空白/括号/quote，避免把字符串里的 `[` 误当成向量起始。
VECTOR_LABEL_RE = re.compile(
    rf'(?:(?<=^)|(?<=[\s(`\']))\[\s*{STRING_RE}\s+(?:[#\'(A-Za-z_])',
    re.MULTILINE,
)

# menu-item 项，如 (menu-item "Undo" undo ...)
MENU_ITEM_LABEL_RE = re.compile(rf"menu-item\s+{STRING_RE}")

# easy-menu 子菜单，如 ("Find...") / '("Projectile" :visible ...)
LIST_LABEL_RE = re.compile(
    rf'^\s*[`\']?\([ \t]*{STRING_RE}[ \t]*(?:$|:|\[|\()',
    re.MULTILINE,
)

TRANSLATION_ENTRY_RE = re.compile(
    rf'^\s*\({STRING_RE}\s+\.\s+{STRING_RE}\)',
    re.MULTILINE,
)

ELISP_LIBRARY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]*$")


def now_iso() -> str:
    """返回当前带时区的 ISO 时间。"""
    return datetime.now().astimezone().isoformat(timespec="seconds")


def read_text(path: Path) -> str:
    """读取文本文件；支持 `.gz`。"""
    if path.suffix == ".gz":
        with gzip.open(path, "rt", encoding="utf-8") as handle:
            return handle.read()
    return path.read_text(encoding="utf-8")


def write_json(path: Path, payload: object) -> None:
    """把 JSON 写入 PATH。"""
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def read_json(path: Path) -> object:
    """读取 JSON 文件。"""
    return json.loads(path.read_text(encoding="utf-8"))


def load_prompt_template(path: Path) -> str:
    """读取提示词模板。"""
    return read_text(path).strip()


def is_elisp_source_file(path: Path) -> bool:
    """判断 PATH 是否是可扫描的 Elisp 源文件。"""
    name = path.name
    return path.is_file() and (name.endswith(".el") or name.endswith(".el.gz"))


def escape_elisp_literal(text: str) -> str:
    """把 Python 字符串转成可放进 Elisp 源码的字面量。"""
    return text.replace("\\", r"\\").replace('"', r"\"")


def looks_like_library_name(text: str) -> bool:
    """判断输入是否更像 `locate-library` 用的库名。"""
    return bool(ELISP_LIBRARY_RE.fullmatch(text))


def locate_libraries(names: list[str]) -> dict[str, Path]:
    """调用 Emacs 的 `locate-library` 查找库文件路径。"""
    if not names:
        return {}

    names_form = " ".join(f'"{escape_elisp_literal(name)}"' for name in names)
    expr = f"""
    (progn
      (require 'json)
      (let* ((names '({names_form}))
             (items
              (mapcar
               (lambda (name)
                 (list (cons 'name name)
                       (cons 'path (locate-library name))))
               names)))
        (princ (json-encode items))))
    """
    result = subprocess.run(
        ["emacs", "--batch", "--quick", "--eval", expr],
        check=False,
        capture_output=True,
        encoding="utf-8",
    )
    if result.returncode != 0:
        stderr = result.stderr.strip() or "未知错误"
        raise RuntimeError(f"调用 Emacs 查找库失败：{stderr}")

    try:
        payload = json.loads(result.stdout or "[]")
    except json.JSONDecodeError as exc:
        raise RuntimeError("Emacs 返回的 locate-library 结果不是合法 JSON。") from exc

    located: dict[str, Path] = {}
    missing: list[str] = []
    for item in payload:
        if not isinstance(item, dict):
            continue
        name = item.get("name")
        path = item.get("path")
        if isinstance(name, str) and isinstance(path, str) and path:
            located[name] = Path(path).expanduser().resolve()
        elif isinstance(name, str):
            missing.append(name)

    if missing:
        missing_text = ", ".join(missing)
        raise RuntimeError(f"以下库无法通过 locate-library 找到：{missing_text}")

    return located


def resolve_compiled_source(path: Path) -> Path:
    """把 `.elc` 优先映射回 `.el` / `.el.gz` 源文件。"""
    resolved = path.expanduser().resolve()
    if resolved.name.endswith(".el.gz"):
        return resolved
    if resolved.suffix == ".el":
        return resolved
    if resolved.suffix != ".elc":
        return resolved

    plain = resolved.with_suffix(".el")
    gz = Path(f"{plain}.gz")
    if plain.exists():
        return plain
    if gz.exists():
        return gz
    return resolved


def choose_library_scan_target(name: str, source_path: Path, scope: str) -> Path:
    """按策略决定库名输入最终扫描文件还是目录。"""
    source = resolve_compiled_source(source_path)
    if scope == "file":
        return source
    if scope == "dir":
        return source.parent

    if "site-lisp" in source.parts:
        return source.parent
    parent_name = source.parent.name.lower()
    if parent_name == name.lower() or parent_name.startswith(f"{name.lower()}-"):
        return source.parent
    return source


def dedupe_paths_preserve_order(paths: Iterable[Path]) -> list[Path]:
    """保持原顺序去重路径。"""
    result: list[Path] = []
    seen: set[Path] = set()
    for path in paths:
        resolved = path.expanduser().resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        result.append(resolved)
    return result


def resolve_inputs_to_targets(inputs: list[str], scope: str) -> tuple[list[Path], list[dict[str, str]]]:
    """把“路径或库名”输入解析成可扫描目标，并返回解析记录。"""
    path_targets: list[Path] = []
    library_inputs: list[str] = []
    records: list[dict[str, str]] = []

    for item in inputs:
        candidate = Path(item).expanduser()
        if candidate.exists():
            resolved = resolve_compiled_source(candidate.resolve())
            path_targets.append(resolved)
            records.append(
                {
                    "input": item,
                    "kind": "path",
                    "resolved": str(resolved),
                    "scan_target": str(resolved),
                }
            )
            continue

        if not looks_like_library_name(item):
            raise RuntimeError(f"输入既不是存在的路径，也不像合法库名：{item}")
        library_inputs.append(item)

    located = locate_libraries(library_inputs)
    for name in library_inputs:
        located_path = located[name]
        source_path = resolve_compiled_source(located_path)
        scan_target = choose_library_scan_target(name, source_path, scope)
        path_targets.append(scan_target)
        records.append(
            {
                "input": name,
                "kind": "library",
                "located": str(located_path),
                "resolved": str(source_path),
                "scan_target": str(scan_target),
            }
        )

    return dedupe_paths_preserve_order(path_targets), records


def resolve_source_files(paths: list[Path]) -> list[Path]:
    """把文件/目录列表展开成待扫描源文件列表。"""
    result: list[Path] = []
    seen: set[Path] = set()

    for path in paths:
        resolved = path.expanduser().resolve()
        candidates: list[Path] = []
        if resolved.is_dir():
            candidates = [child for child in resolved.rglob("*") if is_elisp_source_file(child)]
        elif is_elisp_source_file(resolved):
            candidates = [resolved]

        for candidate in sorted(candidates):
            if candidate not in seen:
                seen.add(candidate)
                result.append(candidate)

    return result


def extract_easy_menu_blocks(text: str) -> list[str]:
    """提取 `(easy-menu-define ...)` 的完整 s-expression 文本。"""
    blocks: list[str] = []
    start = 0
    marker = "(easy-menu-define"

    while True:
        index = text.find(marker, start)
        if index < 0:
            return blocks

        depth = 0
        in_string = False
        in_comment = False
        escape = False

        for cursor in range(index, len(text)):
            char = text[cursor]

            if in_comment:
                if char == "\n":
                    in_comment = False
                continue

            if in_string:
                if escape:
                    escape = False
                elif char == "\\":
                    escape = True
                elif char == '"':
                    in_string = False
                continue

            if char == ";":
                in_comment = True
                continue

            if char == '"':
                in_string = True
                continue

            if char == "(":
                depth += 1
                continue

            if char == ")":
                depth -= 1
                if depth == 0:
                    blocks.append(text[index : cursor + 1])
                    start = cursor + 1
                    break
        else:
            blocks.append(text[index:])
            return blocks


def unescape_elisp_string(text: str) -> str:
    """对常见 Elisp 字符串转义做最小反转义。"""
    replacements = {
        r"\\": "\\",
        r"\"": '"',
        r"\n": "\n",
        r"\t": "\t",
        r"\r": "\r",
    }
    for source, target in replacements.items():
        text = text.replace(source, target)
    return text


def escape_elisp_string(text: str) -> str:
    """把字符串转成可写回 Elisp 的字面量。"""
    return text.replace("\\", r"\\").replace('"', r"\"")


def looks_like_menu_label(label: str) -> bool:
    """尽量过滤掉非菜单标题字符串。"""
    stripped = label.strip()
    if not stripped:
        return False
    if stripped in {"---", "----"}:
        return False
    if len(stripped) > 90:
        return False
    if "\n" in stripped:
        return False
    if re.search(r"[\u4e00-\u9fff]", stripped):
        return False
    return bool(re.search(r"[A-Za-z%]", stripped))


def dedupe_preserve_order(items: Iterable[str]) -> list[str]:
    """保持原顺序去重。"""
    result: list[str] = []
    seen: set[str] = set()
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        result.append(item)
    return result


def extract_labels_from_text(text: str) -> list[str]:
    """从源码文本中提取候选菜单标题。"""
    labels: list[str] = []
    for pattern in (VECTOR_LABEL_RE, MENU_ITEM_LABEL_RE):
        for match in pattern.finditer(text):
            label = unescape_elisp_string(match.group(1))
            if looks_like_menu_label(label):
                labels.append(label)

    for block in extract_easy_menu_blocks(text):
        for match in LIST_LABEL_RE.finditer(block):
            label = unescape_elisp_string(match.group(1))
            if looks_like_menu_label(label):
                labels.append(label)

    return dedupe_preserve_order(labels)


def extract_labels(paths: list[Path]) -> list[str]:
    """从多个文件中提取候选标题。"""
    labels: list[str] = []
    for path in paths:
        labels.extend(extract_labels_from_text(read_text(path)))
    return dedupe_preserve_order(labels)


def load_existing_translations(path: Path) -> dict[str, str]:
    """读取现有 `("EN" . "中文")` 翻译表。"""
    text = read_text(path)
    result: dict[str, str] = {}
    for match in TRANSLATION_ENTRY_RE.finditer(text):
        source = unescape_elisp_string(match.group(1))
        target = unescape_elisp_string(match.group(2))
        result[source] = target
    return result


def filter_untranslated(labels: list[str], existing: dict[str, str]) -> list[str]:
    """只保留尚未在目标 alist 中出现的英文项。"""
    return [label for label in labels if label not in existing]


def build_scan_index(
    source_files: list[Path],
    existing: dict[str, str],
    target_el: Path,
    tracked_paths: list[Path],
) -> dict[str, object]:
    """生成翻译状态索引。"""
    translated_files: list[dict[str, object]] = []
    untranslated_files: list[dict[str, object]] = []

    for source_file in source_files:
        labels = extract_labels_from_text(read_text(source_file))
        if not labels:
            continue

        pending = filter_untranslated(labels, existing)
        record = {
            "path": str(source_file),
            "total_labels": len(labels),
            "pending_count": len(pending),
            "pending_labels": pending,
        }
        if pending:
            untranslated_files.append(record)
        else:
            translated_files.append(record)

    translated_files.sort(key=lambda item: item["path"])
    untranslated_files.sort(key=lambda item: item["path"])

    return {
        "schema_version": 1,
        "target_el": str(target_el),
        "tracked_paths": [str(path.expanduser().resolve()) for path in tracked_paths],
        "last_scan": now_iso(),
        "translated_files": translated_files,
        "untranslated_files": untranslated_files,
    }


def load_index(path: Path) -> dict[str, object]:
    """读取索引文件；不存在时返回默认结构。"""
    if not path.exists():
        return {
            "schema_version": 1,
            "target_el": str(DEFAULT_TARGET),
            "tracked_paths": [],
            "last_scan": "",
            "translated_files": [],
            "untranslated_files": [],
        }

    payload = read_json(path)
    if not isinstance(payload, dict):
        raise RuntimeError(f"索引文件格式错误，不是对象: {path}")
    return payload


def build_batch_payload(source_files: list[Path], existing: dict[str, str], target_el: Path, include_all: bool) -> dict[str, object]:
    """根据源文件生成待翻译 JSON。"""
    merged: dict[str, dict[str, object]] = {}

    for source_file in source_files:
        labels = extract_labels_from_text(read_text(source_file))
        labels = labels if include_all else filter_untranslated(labels, existing)
        for label in labels:
            entry = merged.setdefault(
                label,
                {
                    "source": label,
                    "target": "",
                    "source_files": [],
                },
            )
            source_list = entry["source_files"]
            if str(source_file) not in source_list:
                source_list.append(str(source_file))

    items = list(merged.values())
    return {
        "schema_version": 1,
        "target_el": str(target_el),
        "generated_at": now_iso(),
        "source_files": [str(path) for path in source_files],
        "items": items,
    }


def parse_translated_items(payload: object) -> list[tuple[str, str]]:
    """从翻译结果 JSON 中解析 `(source, target)` 列表。"""
    if isinstance(payload, dict):
        items = payload.get("items")
        if not isinstance(items, list):
            raise RuntimeError("翻译结果 JSON 缺少 `items` 列表。")
    elif isinstance(payload, list):
        items = payload
    else:
        raise RuntimeError("翻译结果 JSON 必须是对象或数组。")

    pairs: list[tuple[str, str]] = []
    for index, item in enumerate(items):
        if not isinstance(item, dict):
            raise RuntimeError(f"第 {index + 1} 项不是对象。")
        source = item.get("source")
        target = item.get("target")
        if not isinstance(source, str) or not source.strip():
            raise RuntimeError(f"第 {index + 1} 项缺少合法的 `source`。")
        if not isinstance(target, str) or not target:
            raise RuntimeError(f"第 {index + 1} 项缺少合法的 `target`。")
        pairs.append((source, target))

    return pairs


def make_elisp_snippet(pairs: list[tuple[str, str]]) -> str:
    """生成可直接粘贴回 alist 的 Emacs Lisp 片段。"""
    return "\n".join(
        f'  ("{escape_elisp_string(source)}" . "{escape_elisp_string(target)}")'
        for source, target in pairs
    )


def make_elisp_file_content(pairs: list[tuple[str, str]], input_path: Path) -> str:
    """生成完整的 Elisp 输出文件。"""
    snippet = make_elisp_snippet(pairs)
    return (
        ";;; menu-translation-snippet.el --- Generated translation snippet -*- lexical-binding: t; -*-\n\n"
        ";;; Commentary:\n"
        f";; 从 `{input_path.name}` 生成。\n"
        ";; 将下面这些条目复制到 `custom:context-menu-label-translations` 中。\n\n"
        ";;; Code:\n\n"
        "'(\n"
        f"{snippet}\n"
        ")\n\n"
        ";;; menu-translation-snippet.el ends here\n"
    )


def build_arg_parser() -> argparse.ArgumentParser:
    """构造命令行参数。"""
    parser = argparse.ArgumentParser(
        description="提取 Emacs 菜单英文、维护翻译索引，并生成可粘贴的 Elisp 片段。"
    )
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    locate_parser = subparsers.add_parser(
        "locate",
        help="把库名解析为实际源码路径与建议扫描范围。",
    )
    locate_parser.add_argument(
        "inputs",
        nargs="+",
        help="一个或多个 Emacs 库名，或已经存在的文件/目录路径。",
    )
    locate_parser.add_argument(
        "--library-scope",
        choices=("auto", "file", "dir"),
        default="auto",
        help="库名输入默认扫描范围：auto=第三方包目录/内置文件，file=只扫主文件，dir=扫所在目录。",
    )

    prepare_parser = subparsers.add_parser(
        "prepare",
        help="一键执行“查找源码 -> 扫描索引 -> 导出待翻译 JSON”。",
    )
    prepare_parser.add_argument(
        "inputs",
        nargs="+",
        help="一个或多个 Emacs 库名，或已经存在的文件/目录路径。",
    )
    prepare_parser.add_argument("--target-el", type=Path, default=DEFAULT_TARGET, help="已有汉化文档路径。")
    prepare_parser.add_argument("--index-file", type=Path, default=DEFAULT_INDEX, help="翻译状态索引文件。")
    prepare_parser.add_argument("--output", type=Path, default=DEFAULT_BATCH, help="导出的待翻译 JSON 文件。")
    prepare_parser.add_argument("--all", action="store_true", help="导出全部菜单项，而不是只导出未汉化项。")
    prepare_parser.add_argument(
        "--library-scope",
        choices=("auto", "file", "dir"),
        default="auto",
        help="库名输入默认扫描范围：auto=第三方包目录/内置文件，file=只扫主文件，dir=扫所在目录。",
    )

    extract_parser = subparsers.add_parser("extract", help="直接输出提取到的菜单标题。")
    extract_parser.add_argument("sources", nargs="+", type=Path, help="要扫描的文件或目录。")
    extract_parser.add_argument("--target-el", type=Path, default=DEFAULT_TARGET, help="已有汉化文档路径。")
    extract_parser.add_argument("--all", action="store_true", help="输出全部候选项，而不是只输出未汉化项。")
    extract_parser.add_argument("--format", choices=("text", "json"), default="text", help="输出格式。")

    scan_parser = subparsers.add_parser("scan", help="扫描文件并更新已翻译/未翻译索引。")
    scan_parser.add_argument("sources", nargs="+", type=Path, help="要扫描的文件或目录。")
    scan_parser.add_argument("--target-el", type=Path, default=DEFAULT_TARGET, help="已有汉化文档路径。")
    scan_parser.add_argument("--index-file", type=Path, default=DEFAULT_INDEX, help="翻译状态索引文件。")

    extract_file_parser = subparsers.add_parser("extract-file", help="导出待翻译 JSON 文件。")
    extract_file_parser.add_argument("sources", nargs="*", type=Path, help="要导出的文件或目录；省略时从索引读取未翻译文件。")
    extract_file_parser.add_argument("--target-el", type=Path, default=DEFAULT_TARGET, help="已有汉化文档路径。")
    extract_file_parser.add_argument("--index-file", type=Path, default=DEFAULT_INDEX, help="翻译状态索引文件。")
    extract_file_parser.add_argument("--output", type=Path, default=DEFAULT_BATCH, help="导出的待翻译 JSON 文件。")
    extract_file_parser.add_argument("--all", action="store_true", help="导出全部菜单项，而不是只导出未汉化项。")

    render_parser = subparsers.add_parser("render-elisp", help="把翻译结果 JSON 渲染成 Elisp 文件。")
    render_parser.add_argument("--input", required=True, type=Path, help="AI 翻译后的 JSON 文件。")
    render_parser.add_argument("--output", required=True, type=Path, help="输出的 Elisp 文件。")

    prompt_parser = subparsers.add_parser("prompt", help="输出给另一套 AI CLI 用的提示词模板。")
    prompt_parser.add_argument("--template", type=Path, default=DEFAULT_PROMPT_TEMPLATE, help="提示词模板文件。")

    return parser


def command_extract(args: argparse.Namespace) -> int:
    """处理 extract 子命令。"""
    source_files = resolve_source_files(args.sources)
    existing = load_existing_translations(args.target_el)
    labels = extract_labels(source_files)
    output = labels if args.all else filter_untranslated(labels, existing)

    if args.format == "json":
        print(json.dumps(output, ensure_ascii=False, indent=2))
    else:
        for label in output:
            print(label)
    return 0


def command_locate(args: argparse.Namespace) -> int:
    """处理 locate 子命令。"""
    targets, records = resolve_inputs_to_targets(args.inputs, args.library_scope)
    for record in records:
        print(json.dumps(record, ensure_ascii=False))
    print(f"建议扫描目标数: {len(targets)}")
    return 0


def command_scan(args: argparse.Namespace) -> int:
    """处理 scan 子命令。"""
    source_files = resolve_source_files(args.sources)
    existing = load_existing_translations(args.target_el)
    payload = build_scan_index(source_files, existing, args.target_el, args.sources)
    write_json(args.index_file, payload)

    translated = payload["translated_files"]
    untranslated = payload["untranslated_files"]
    print(f"已更新索引: {args.index_file}")
    print(f"已翻译文件: {len(translated)}")
    print(f"未翻译文件: {len(untranslated)}")
    return 0


def command_extract_file(args: argparse.Namespace) -> int:
    """处理 extract-file 子命令。"""
    if args.sources:
        source_files = resolve_source_files(args.sources)
    else:
        index = load_index(args.index_file)
        source_files = [
            Path(item["path"])
            for item in index.get("untranslated_files", [])
            if isinstance(item, dict) and item.get("path")
        ]

    if not source_files:
        raise RuntimeError("没有可导出的待翻译文件。请先运行 scan，或显式传入 sources。")

    existing = load_existing_translations(args.target_el)
    payload = build_batch_payload(source_files, existing, args.target_el, args.all)
    write_json(args.output, payload)

    items = payload["items"]
    print(f"已导出待翻译文件: {args.output}")
    print(f"源文件数: {len(payload['source_files'])}")
    print(f"待翻译条目数: {len(items)}")
    return 0


def command_prepare(args: argparse.Namespace) -> int:
    """处理 prepare 子命令。"""
    tracked_targets, records = resolve_inputs_to_targets(args.inputs, args.library_scope)
    source_files = resolve_source_files(tracked_targets)
    existing = load_existing_translations(args.target_el)

    index_payload = build_scan_index(source_files, existing, args.target_el, tracked_targets)
    write_json(args.index_file, index_payload)

    batch_payload = build_batch_payload(source_files, existing, args.target_el, args.all)
    batch_payload["requested_inputs"] = list(args.inputs)
    batch_payload["resolved_targets"] = [record["scan_target"] for record in records]
    write_json(args.output, batch_payload)

    for record in records:
        print(json.dumps(record, ensure_ascii=False))
    print(f"已更新索引: {args.index_file}")
    print(f"已导出待翻译文件: {args.output}")
    print(f"建议扫描目标数: {len(tracked_targets)}")
    print(f"实际源文件数: {len(source_files)}")
    print(f"待翻译条目数: {len(batch_payload['items'])}")
    return 0


def command_render_elisp(args: argparse.Namespace) -> int:
    """处理 render-elisp 子命令。"""
    payload = read_json(args.input)
    pairs = parse_translated_items(payload)
    content = make_elisp_file_content(pairs, args.input)
    args.output.write_text(content, encoding="utf-8")

    print(f"已生成 Elisp 文件: {args.output}")
    print(f"条目数: {len(pairs)}")
    return 0


def command_prompt(args: argparse.Namespace) -> int:
    """处理 prompt 子命令。"""
    print(load_prompt_template(args.template))
    return 0


def main() -> int:
    """程序入口。"""
    parser = build_arg_parser()
    args = parser.parse_args()

    try:
        if args.subcommand == "locate":
            return command_locate(args)
        if args.subcommand == "prepare":
            return command_prepare(args)
        if args.subcommand == "extract":
            return command_extract(args)
        if args.subcommand == "scan":
            return command_scan(args)
        if args.subcommand == "extract-file":
            return command_extract_file(args)
        if args.subcommand == "render-elisp":
            return command_render_elisp(args)
        if args.subcommand == "prompt":
            return command_prompt(args)
    except Exception as exc:  # noqa: BLE001
        print(f"错误: {exc}", file=sys.stderr)
        return 1

    parser.error(f"未知子命令: {args.subcommand}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
