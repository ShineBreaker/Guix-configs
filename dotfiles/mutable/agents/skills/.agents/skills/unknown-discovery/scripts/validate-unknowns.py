#!/usr/bin/env python3
"""Validate a JSONL file of unknowns against the unknown-discovery schema.

Schema (one unknown per line):
    {
      "id": "U001",                    # required, unique within file
      "statement": "string",           # required, the unknown itself
      "tag": "USER|PROBLEM|SOLUTION|ECOSYSTEM|META",  # required
      "stage": 1..5,                   # required, current stage
      "importance": 1..5,              # required, design impact
      "risk": 1..5,                    # required, risk if wrong
      "cost": 1..5,                    # required, cost to research
      "score": number,                 # optional, importance*risk/cost
      "starred": bool,                 # optional, top-priority flag
      "status": "open|researching|validated|invalid|resolved",  # required
      "added": "YYYY-MM-DD",           # required, ISO date
      "notes": "string"                # optional, free text
    }

Usage:
    python3 validate-unknowns.py unknowns.jsonl
    python3 validate-unknowns.py --strict unknowns.jsonl   # warnings -> errors
    python3 validate-unknowns.py --quiet unknowns.jsonl    # only errors

Exit codes:
    0  valid (or only warnings in non-strict mode)
    1  validation errors
    2  usage / file not found
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

VALID_TAGS = {"USER", "PROBLEM", "SOLUTION", "ECOSYSTEM", "META"}
VALID_STAGES = {1, 2, 3, 4, 5}
VALID_STATUSES = {"open", "researching", "validated", "invalid", "resolved"}
REQUIRED_FIELDS = ("id", "statement", "tag", "stage", "importance",
                   "risk", "cost", "status", "added")


def validate_record(rec: Any, line_no: int) -> list[str]:
    """Return list of error messages for a single record."""
    errors: list[str] = []

    if not isinstance(rec, dict):
        return [f"line {line_no}: not a JSON object"]

    for field in REQUIRED_FIELDS:
        if field not in rec:
            errors.append(f"line {line_no}: missing required field '{field}'")

    if "id" in rec and not isinstance(rec["id"], str):
        errors.append(f"line {line_no}: 'id' must be a string")
    if "statement" in rec and not isinstance(rec["statement"], str):
        errors.append(f"line {line_no}: 'statement' must be a string")
    if "tag" in rec and rec["tag"] not in VALID_TAGS:
        errors.append(
            f"line {line_no}: 'tag' must be one of {sorted(VALID_TAGS)}, "
            f"got {rec['tag']!r}"
        )
    if "stage" in rec and rec["stage"] not in VALID_STAGES:
        errors.append(
            f"line {line_no}: 'stage' must be 1..5, got {rec['stage']!r}"
        )
    for int_field in ("importance", "risk", "cost"):
        v = rec.get(int_field)
        if v is None:
            continue
        if not isinstance(v, int) or isinstance(v, bool) or not 1 <= v <= 5:
            errors.append(
                f"line {line_no}: '{int_field}' must be integer 1..5, "
                f"got {v!r}"
            )
    if "status" in rec and rec["status"] not in VALID_STATUSES:
        errors.append(
            f"line {line_no}: 'status' must be one of "
            f"{sorted(VALID_STATUSES)}, got {rec['status']!r}"
        )
    if "added" in rec:
        added = rec["added"]
        if not (isinstance(added, str) and len(added) == 10
                and added[4] == "-" and added[7] == "-"):
            errors.append(
                f"line {line_no}: 'added' must be YYYY-MM-DD, got {added!r}"
            )
    if "starred" in rec and not isinstance(rec["starred"], bool):
        errors.append(f"line {line_no}: 'starred' must be a bool")
    if "score" in rec:
        score = rec["score"]
        if not isinstance(score, (int, float)) or isinstance(score, bool):
            errors.append(f"line {line_no}: 'score' must be a number")

    return errors


def check_invariants(records: list[dict]) -> list[str]:
    """Cross-record checks: uniqueness, derived fields, etc."""
    errors: list[str] = []

    # Unique IDs
    seen: dict[str, int] = {}
    for i, rec in enumerate(records, 1):
        rid = rec.get("id")
        if rid in seen:
            errors.append(
                f"line {i}: duplicate id {rid!r} (also at line {seen[rid]})"
            )
        else:
            seen[rid] = i

    # Score consistency (if importance/risk/cost set, score should match)
    for i, rec in enumerate(records, 1):
        if all(k in rec for k in ("importance", "risk", "cost")):
            cost = rec["cost"]
            if cost == 0:
                continue
            expected = round(rec["importance"] * rec["risk"] / cost, 2)
            if "score" in rec:
                if abs(rec["score"] - expected) > 0.01:
                    errors.append(
                        f"line {i}: score {rec['score']} != "
                        f"importance*risk/cost = {expected}"
                    )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate unknowns.jsonl against unknown-discovery schema"
    )
    parser.add_argument("path", type=Path, help="Path to JSONL file")
    parser.add_argument("--strict", action="store_true",
                        help="Promote warnings to errors")
    parser.add_argument("--quiet", action="store_true",
                        help="Only print errors (suppress warnings/stats)")
    args = parser.parse_args()

    if not args.path.exists():
        print(f"error: file not found: {args.path}", file=sys.stderr)
        return 2

    records: list[dict] = []
    parse_errors: list[str] = []
    with args.path.open() as f:
        for line_no, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError as e:
                parse_errors.append(f"line {line_no}: invalid JSON: {e}")
                continue
            records.append(rec)

    all_errors: list[str] = []
    all_errors.extend(parse_errors)
    for i, rec in enumerate(records, 1):
        all_errors.extend(validate_record(rec, i))
    all_errors.extend(check_invariants(records))

    # Stats
    warnings: list[str] = []
    if records:
        stages: dict[int, int] = {}
        statuses: dict[str, int] = {}
        tags: dict[str, int] = {}
        starred = 0
        for rec in records:
            stage_key = rec.get("stage") or 0
            status_key = rec.get("status") or "?"
            tag_key = rec.get("tag") or "?"
            stages[stage_key] = stages.get(stage_key, 0) + 1
            statuses[status_key] = statuses.get(status_key, 0) + 1
            tags[tag_key] = tags.get(tag_key, 0) + 1
            if rec.get("starred"):
                starred += 1
        warnings.append(f"total unknowns: {len(records)}")
        warnings.append(f"starred (top priority): {starred}")
        warnings.append(f"by stage: {dict(sorted(stages.items()))}")
        warnings.append(f"by status: {statuses}")
        warnings.append(f"by tag: {tags}")

    # Output
    if not args.quiet:
        for w in warnings:
            print(w)

    if all_errors:
        print(f"\n{len(all_errors)} error(s):", file=sys.stderr)
        for e in all_errors:
            print(f"  {e}", file=sys.stderr)
        return 1

    if not args.quiet:
        print("\nOK — all records valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())