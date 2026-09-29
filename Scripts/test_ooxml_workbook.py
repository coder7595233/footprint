#!/usr/bin/env python3

from __future__ import annotations

import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "Sources" / "Footprint" / "Resources" / "Scripts"
sys.path.insert(0, str(SCRIPTS))

from ooxml_workbook import sanitize_xml_text, write_workbook  # noqa: E402


class OOXMLWorkbookTests(unittest.TestCase):
    def test_illegal_xml_controls_are_removed_and_all_parts_parse(self) -> None:
        with tempfile.TemporaryDirectory(prefix="FootprintOOXMLTests-") as directory:
            output = Path(directory) / "control-characters.xlsx"
            write_workbook(
                output,
                [{
                    "name": "Unsafe\u0001 sheet",
                    "rows": [["Header", "Value"], ["A\u0000B", "12,5"], ["Unicode", "Åäö – 漢字"]],
                }],
            )

            with ZipFile(output) as archive:
                for name in archive.namelist():
                    if name.endswith((".xml", ".rels")):
                        ET.fromstring(archive.read(name))
                sheet = archive.read("xl/worksheets/sheet1.xml")
                self.assertNotIn(b"\x00", sheet)
                self.assertNotIn(b"\x01", sheet)

    def test_empty_workbook_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="FootprintOOXMLTests-") as directory:
            with self.assertRaises(ValueError):
                write_workbook(Path(directory) / "empty.xlsx", [])

    def test_text_sanitizer_preserves_valid_unicode(self) -> None:
        self.assertEqual(sanitize_xml_text("Åäö – 漢字"), "Åäö – 漢字")
        self.assertEqual(sanitize_xml_text("A\u0000B\u000bC"), "ABC")

    def test_leading_zero_identifiers_stay_text(self) -> None:
        with tempfile.TemporaryDirectory(prefix="FootprintOOXMLTests-") as directory:
            output = Path(directory) / "identifiers.xlsx"
            write_workbook(
                output,
                [{
                    "name": "Kontakter",
                    "rows": [
                        ["Telefon", "Antal", "Andel"],
                        ["070 123 45 67", "0", "0,5"],
                    ],
                }],
            )

            with ZipFile(output) as archive:
                sheet = archive.read("xl/worksheets/sheet1.xml").decode("utf-8")
                # Phone-style values keep their leading zero as inline text.
                self.assertIn("070 123 45 67", sheet)
                self.assertNotIn("<v>701234567</v>", sheet)
                # Plain zero and decimal fractions remain numeric.
                self.assertIn('<c r="B2"><v>0</v></c>', sheet)
                self.assertIn('<c r="C2"><v>0.5</v></c>', sheet)

    def test_currency_cells_and_external_hyperlinks_are_preserved(self) -> None:
        with tempfile.TemporaryDirectory(prefix="FootprintOOXMLTests-") as directory:
            output = Path(directory) / "formatted-project.xlsx"
            write_workbook(
                output,
                [{
                    "name": "Ansökningar",
                    "style": "projectTable",
                    "rows": [["Belopp", "Länk"], ["500000", "www.example.com"]],
                    "currencyCells": [{"row": 1, "column": 0}],
                    "hyperlinks": [{"row": 1, "column": 1, "target": "https://www.example.com"}],
                }],
            )

            with ZipFile(output) as archive:
                sheet = archive.read("xl/worksheets/sheet1.xml").decode("utf-8")
                relationships = archive.read("xl/worksheets/_rels/sheet1.xml.rels").decode("utf-8")
                styles = archive.read("xl/styles.xml").decode("utf-8")
                self.assertIn('<c r="A2" s="8"><v>500000</v></c>', sheet)
                self.assertIn('<hyperlink ref="B2" r:id="rId1"/>', sheet)
                self.assertIn('Target="https://www.example.com" TargetMode="External"', relationships)
                self.assertIn('numFmtId="164"', styles)
                self.assertIn('formatCode="#,##0&quot; kr&quot;"', styles)


if __name__ == "__main__":
    unittest.main()
