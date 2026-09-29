#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path

from ooxml_workbook import write_workbook


HEADERS = ["Lönekälla", "Projektnummer", "PEOE", "%-sats", "Period från", "Period till"]


def rows(items: list[dict[str, object]]) -> list[list[str]]:
    return [HEADERS] + [
        [
            str(item.get("source") or ""),
            str(item.get("projectNumber") or ""),
            str(item.get("peoe") or ""),
            str(item.get("percentage") or ""),
            str(item.get("from") or ""),
            str(item.get("to") or ""),
        ]
        for item in items
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    payload = list(json.loads(args.input.read_text(encoding="utf-8")) or [])
    write_workbook(
        args.output,
        [{"name": "Löneplan", "rows": rows(payload), "column_widths": [42, 18, 14, 12, 14, 14]}],
    )
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
