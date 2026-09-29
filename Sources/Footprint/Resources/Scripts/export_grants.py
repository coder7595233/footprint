#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path

from ooxml_workbook import write_workbook


APPLICATION_HEADERS = [
    "Organisation", "Medel", "Grant category", "Currency", "Summa max", "År #",
    "Sysselsättningsgrad", "Antal månader", "Ungefärlig summa", "Öppnar", "Öppnar osäkert",
    "Ansökt datum", "Ansökt datum osäkert", "Stänger", "Stänger osäkert", "Beslutsdatum",
    "Beslutsdatum osäkert", "Beslut", "Beslut osäkert", "Projekt", "År disp",
    "Kriterie sökande", "Kriterie projekt", "Länk", "Länk 2", "Ansökt diarienr",
    "Ansökt summa", "Beviljad summa", "Förbrukat belopp", "Resultat", "Diarienummer hos lärosätet",
    "Medelsförvaltare", "Skäl till medelsförvaltare", "Lönemedel", "Material", "Doktorander",
]
RECEIVED_HEADERS = [
    "Organisation", "Medel", "Ansökningsnummer", "Anges som", "Nyttjas från",
    "Nyttjas från osäkert", "Nyttjas till", "Nyttjas till osäkert", "Summa",
    "Förbrukat belopp", "Återgälda", "Sista datum att återgälda", "Återgäldat",
]


def application_rows(applications: list[dict[str, object]]) -> list[list[str]]:
    rows = [APPLICATION_HEADERS]
    for app in applications:
        rows.append([
            str(app.get("organization") or ""), str(app.get("grantName") or ""),
            str(app.get("grantCategory") or ""), str(app.get("currency") or "SEK"),
            str(app.get("maxAmount") or ""), str(app.get("yearCount") or ""),
            str(app.get("employmentPercentage") or ""), str(app.get("employmentMonths") or ""),
            str(app.get("approximateAmount") or ""), str(app.get("opensOn") or ""),
            "Ja" if app.get("opensOnUncertain") else "", str(app.get("appliedOn") or ""),
            "Ja" if app.get("appliedOnUncertain") else "", str(app.get("closesOn") or ""),
            "Ja" if app.get("closesOnUncertain") else "", str(app.get("decisionOn") or ""),
            "Ja" if app.get("decisionOnUncertain") else "", str(app.get("decisionExpectedOn") or ""),
            "Ja" if app.get("decisionExpectedOnUncertain") else "", str(app.get("projectType") or ""),
            str(app.get("dispositionYears") or ""), str(app.get("applicantCriteria") or ""),
            str(app.get("projectCriteria") or ""), str(app.get("primaryLink") or ""),
            str(app.get("secondaryLink") or ""), str(app.get("appliedCaseNumber") or ""),
            str(app.get("appliedAmount") or ""), str(app.get("grantedAmount") or ""),
            str(app.get("receivedConsumedAmount") or ""), str(app.get("result") or ""),
            str(app.get("liuRegistered") or ""), str(app.get("applicationManager") or ""),
            str(app.get("managerReason") or ""), "Ja" if app.get("fundingSalary") else "",
            "Ja" if app.get("fundingMaterials") else "", "Ja" if app.get("fundingPhDStudents") else "",
        ])
    return rows


def received_rows(applications: list[dict[str, object]]) -> list[list[str]]:
    rows = [RECEIVED_HEADERS]
    for app in applications:
        if str(app.get("result") or "") != "Beviljat":
            continue
        rows.append([
            str(app.get("organization") or ""), str(app.get("grantName") or ""),
            str(app.get("appliedCaseNumber") or ""), str(app.get("receivedDisplayName") or ""),
            str(app.get("receivedUsageFrom") or ""), "Ja" if app.get("receivedUsageFromUncertain") else "",
            str(app.get("receivedUsageTo") or ""), "Ja" if app.get("receivedUsageToUncertain") else "",
            str(app.get("grantedAmount") or ""), str(app.get("receivedConsumedAmount") or ""),
            str(app.get("receivedRepaymentRequirement") or ""), str(app.get("receivedRepaymentDueOn") or ""),
            str(app.get("receivedRepaidOn") or ""),
        ])
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    applications = list(json.loads((args.input_dir / "applications.json").read_text(encoding="utf-8")) or [])
    write_workbook(args.output, [
        {"name": "Applications", "rows": application_rows(applications)},
        {"name": "Received grants", "rows": received_rows(applications)},
    ])
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
