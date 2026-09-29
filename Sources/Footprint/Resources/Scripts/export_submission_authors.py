#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path

from ooxml_workbook import write_workbook


HEADERS = [
    "Förnamn", "Efternamn", "Titel", "ORCID", "Organisation", "Avdelning", "Ort", "Land",
    "E-post", "Telefonetikett", "Telefon", "Telefonetikett 2", "Telefon 2",
]
CREDIT_HEADERS = [
    "Conceptualization", "Data curation", "Formal analysis", "Funding acquisition", "Investigation",
    "Methodology", "Project administration", "Resources", "Software", "Supervision", "Validation",
    "Visualization", "Writing - original draft", "Writing - review & editing",
]


def author_rows(authors: list[dict[str, object]]) -> list[list[str]]:
    rows = [HEADERS + CREDIT_HEADERS]
    for author in authors:
        assigned_roles = {str(role) for role in (author.get("creditRoles") or [])}
        contributions = {
            str(key): str(value)
            for key, value in dict(author.get("creditRoleContributions") or {}).items()
        }
        rows.append([
            str(author.get("firstName") or ""),
            str(author.get("lastName") or ""),
            str(author.get("title") or ""),
            str(author.get("orcid") or ""),
            str(author.get("organization") or ""),
            str(author.get("department") or ""),
            str(author.get("city") or ""),
            str(author.get("country") or ""),
            str(author.get("email") or ""),
            str(author.get("phoneLabel") or ""),
            str(author.get("phoneNumber") or ""),
            str(author.get("phoneLabelSecondary") or ""),
            str(author.get("phoneNumberSecondary") or ""),
        ] + [contributions.get(role, "X") if role in assigned_roles else "" for role in CREDIT_HEADERS])
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-json", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    payload = json.loads(args.input_json.read_text(encoding="utf-8"))
    if isinstance(payload, dict) and "headers" in payload and "rows" in payload:
        rows = [[str(value) for value in list(payload.get("headers") or [])]] + [
            [str(value) for value in list(row or [])]
            for row in list(payload.get("rows") or [])
        ]
    else:
        rows = author_rows(list(payload or []))
    write_workbook(args.output, [{"name": "Authors", "rows": rows}])
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
