#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path

from ooxml_workbook import write_workbook


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    payload = json.loads(args.input.read_text(encoding="utf-8"))
    write_workbook(args.output, list(payload or []))
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
