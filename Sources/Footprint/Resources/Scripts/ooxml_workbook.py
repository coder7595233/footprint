from __future__ import annotations

import re
from pathlib import Path
from typing import Optional
from xml.etree import ElementTree
from xml.sax.saxutils import escape
from zipfile import ZIP_DEFLATED, ZipFile


_ILLEGAL_XML_10 = re.compile(
    "[\x00-\x08\x0b\x0c\x0e-\x1f\ud800-\udfff\ufffe\uffff]"
)


def sanitize_xml_text(value: object) -> str:
    return _ILLEGAL_XML_10.sub("", str(value))


def _maybe_number(value: str) -> bool:
    cleaned = value.replace(" ", "").replace("%", "").replace("kr", "").strip()
    if not re.fullmatch(r"-?\d+(?:[.,]\d+)?", cleaned):
        return False
    digits = cleaned.lstrip("-")
    # A leading zero marks an identifier (phone number, org number), not a
    # quantity; numeric coercion would silently drop the zero.
    if digits.startswith("0") and len(digits) > 1 and digits[1] not in ".,":
        return False
    return True


def _cell_xml(cell_ref: str, value: str, style_index: int = 0) -> str:
    value = sanitize_xml_text(value)
    if value == "":
        return f'<c r="{cell_ref}" s="{style_index}"/>' if style_index else ""
    style = f' s="{style_index}"' if style_index else ""
    if _maybe_number(value):
        cleaned = value.replace("%", "").replace("kr", "").replace(" ", "").replace(",", ".").strip()
        return f'<c r="{cell_ref}"{style}><v>{cleaned}</v></c>'
    preserve = ' xml:space="preserve"' if value != value.strip() else ""
    return f'<c r="{cell_ref}"{style} t="inlineStr"><is><t{preserve}>{escape(value)}</t></is></c>'


def _column_name(index: int) -> str:
    name = ""
    current = index + 1
    while current:
        current, remainder = divmod(current - 1, 26)
        name = chr(65 + remainder) + name
    return name


def _sheet_xml(
    rows: list[list[str]],
    column_widths: Optional[list[int]],
    sheet_style: Optional[str],
    currency_cells: set[tuple[int, int]],
    hyperlinks: list[dict[str, object]],
) -> str:
    normalized_rows = [[sanitize_xml_text(value) for value in row] for row in rows]
    max_columns = max((len(row) for row in normalized_rows), default=1)
    if column_widths is None:
        widths = []
        for column_index in range(max_columns):
            content_width = max(
                (len(row[column_index]) if column_index < len(row) else 0 for row in normalized_rows),
                default=0,
            )
            widths.append(min(max(content_width + 2, 12), 48))
    else:
        widths = list(column_widths)
        if len(widths) < max_columns:
            widths.extend([18] * (max_columns - len(widths)))

    cols_xml = "".join(
        f'<col min="{index + 1}" max="{index + 1}" width="{width}" customWidth="1"/>'
        for index, width in enumerate(widths[:max_columns])
    )
    rows_xml = []
    for row_index, row in enumerate(normalized_rows, start=1):
        is_summary_section = sheet_style == "projectSummary" and row_index > 2 and sum(bool(value) for value in row) == 1
        cells = []
        for column_index in range(max_columns if is_summary_section or row_index <= 2 else len(row)):
            base_style_index = (
                    1 if sheet_style == "projectSummary" and row_index == 1
                    else 2 if sheet_style == "projectSummary" and row_index == 2
                    else 3 if is_summary_section
                    else 5 if sheet_style == "projectSummary" and column_index % 2 == 0
                    else 6 if sheet_style == "projectSummary"
                    else 4 if sheet_style == "projectTable" and row_index == 1
                    else 7 if sheet_style == "projectTable" and row_index % 2 == 1
                    else 0
            )
            zero_based_ref = (row_index - 1, column_index)
            is_hyperlink = any(
                int(link.get("row", -1)) == zero_based_ref[0]
                and int(link.get("column", -1)) == zero_based_ref[1]
                for link in hyperlinks
            )
            if is_hyperlink:
                style_index = 12 if base_style_index == 7 else 11
            elif zero_based_ref in currency_cells:
                style_index = 9 if base_style_index == 7 else 10 if base_style_index == 6 else 8
            else:
                style_index = base_style_index
            cells.append(
                _cell_xml(
                    f"{_column_name(column_index)}{row_index}",
                    row[column_index] if column_index < len(row) else "",
                    style_index,
                )
            )
        height = (
            ' ht="34" customHeight="1"' if sheet_style == "projectSummary" and row_index == 1
            else ' ht="24" customHeight="1"' if sheet_style == "projectSummary" and (row_index == 2 or is_summary_section)
            else ' ht="30" customHeight="1"' if sheet_style == "projectTable" and row_index == 1
            else ""
        )
        rows_xml.append(f'<row r="{row_index}"{height}>{"".join(cells)}</row>')

    sheet_views = '<sheetViews><sheetView workbookViewId="0" showGridLines="0"/></sheetViews>'
    pane = ""
    auto_filter = ""
    merge_cells = ""
    if sheet_style == "projectTable" and len(normalized_rows) > 1:
        pane = '<sheetViews><sheetView workbookViewId="0" showGridLines="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
        auto_filter = f'<autoFilter ref="A1:{_column_name(max_columns - 1)}{len(normalized_rows)}"/>'
    elif sheet_style == "projectSummary":
        merged = [f'A1:{_column_name(max_columns - 1)}1', f'A2:{_column_name(max_columns - 1)}2']
        merged.extend(
            f'A{row_index}:{_column_name(max_columns - 1)}{row_index}'
            for row_index, row in enumerate(normalized_rows, start=1)
            if row_index > 2 and sum(bool(value) for value in row) == 1
        )
        merge_cells = f'<mergeCells count="{len(merged)}">' + "".join(f'<mergeCell ref="{ref}"/>' for ref in merged) + '</mergeCells>'
    hyperlink_xml = ""
    if hyperlinks:
        entries = []
        for relationship_index, link in enumerate(hyperlinks, start=1):
            row_index = int(link.get("row", -1)) + 1
            column_index = int(link.get("column", -1))
            if row_index < 1 or column_index < 0:
                continue
            entries.append(
                f'<hyperlink ref="{_column_name(column_index)}{row_index}" r:id="rId{relationship_index}"/>'
            )
        if entries:
            hyperlink_xml = f'<hyperlinks>{"".join(entries)}</hyperlinks>'
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        f'{pane or sheet_views}<cols>{cols_xml}</cols><sheetData>{"".join(rows_xml)}</sheetData>{auto_filter}{merge_cells}{hyperlink_xml}</worksheet>'
    )


def _safe_sheet_name(raw: str, fallback: str, used: set[str]) -> str:
    cleaned = re.sub(r"[:\\\\/?*\\[\\]]", " ", sanitize_xml_text(raw)).strip() or fallback
    cleaned = cleaned[:31]
    candidate = cleaned
    suffix = 2
    while candidate in used:
        addition = f" ({suffix})"
        candidate = f"{cleaned[:31 - len(addition)]}{addition}"
        suffix += 1
    used.add(candidate)
    return candidate


def _validated_xml(value: str) -> str:
    ElementTree.fromstring(value.encode("utf-8"))
    return value


def write_workbook(output_path: Path, sheets: list[dict[str, object]]) -> None:
    if not sheets:
        raise ValueError("A workbook must contain at least one sheet.")

    used_names: set[str] = set()
    normalized: list[tuple[str, str, Optional[str]]] = []
    for index, sheet in enumerate(sheets, start=1):
        name = _safe_sheet_name(str(sheet.get("name") or ""), f"Sheet {index}", used_names)
        rows = [
            [sanitize_xml_text(value) for value in list(row or [])]
            for row in list(sheet.get("rows") or [])
        ]
        raw_widths = sheet.get("column_widths")
        widths = [int(value) for value in list(raw_widths)] if raw_widths is not None else None
        raw_currency_cells = list(sheet.get("currencyCells") or [])
        currency_cells = {
            (int(cell.get("row", -1)), int(cell.get("column", -1)))
            for cell in raw_currency_cells
            if isinstance(cell, dict)
        }
        hyperlinks = [
            link for link in list(sheet.get("hyperlinks") or [])
            if isinstance(link, dict) and str(link.get("target") or "").strip()
        ]
        hyperlink_rels = None
        if hyperlinks:
            relationship_entries = "".join(
                f'<Relationship Id="rId{relationship_index}" '
                'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" '
                f'Target="{escape(str(link["target"]), {chr(34): "&quot;"})}" TargetMode="External"/>'
                for relationship_index, link in enumerate(hyperlinks, start=1)
            )
            hyperlink_rels = (
                '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                f'{relationship_entries}</Relationships>'
            )
        normalized.append((
            name,
            _sheet_xml(rows, widths, str(sheet.get("style") or "") or None, currency_cells, hyperlinks),
            hyperlink_rels,
        ))

    sheet_overrides = "\n".join(
        f'  <Override PartName="/xl/worksheets/sheet{index}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        for index in range(1, len(normalized) + 1)
    )
    content_types = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
{sheet_overrides}
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>"""
    root_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>"""
    workbook_sheets = "\n".join(
        f'    <sheet name="{escape(name)}" sheetId="{index}" r:id="rId{index}"/>'
        for index, (name, _, _) in enumerate(normalized, start=1)
    )
    workbook = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
{workbook_sheets}
  </sheets>
</workbook>"""
    workbook_rels_entries = "\n".join(
        f'  <Relationship Id="rId{index}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet{index}.xml"/>'
        for index in range(1, len(normalized) + 1)
    )
    workbook_rels = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
{workbook_rels_entries}
  <Relationship Id="rId{len(normalized) + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>"""
    styles = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0&quot; kr&quot;"/></numFmts>
  <fonts count="6">
    <font><sz val="11"/><name val="Aptos"/><family val="2"/></font>
    <font><b/><sz val="22"/><color rgb="FFFFFFFF"/><name val="Aptos Display"/></font>
    <font><b/><sz val="12"/><color rgb="FFFFFFFF"/><name val="Aptos"/></font>
    <font><b/><sz val="11"/><color rgb="FF243447"/><name val="Aptos"/></font>
    <font><i/><sz val="12"/><color rgb="FF51606F"/><name val="Aptos"/></font>
    <font><u/><sz val="11"/><color rgb="FF0563C1"/><name val="Aptos"/></font>
  </fonts>
  <fills count="7">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FF243447"/><bgColor indexed="64"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FF2B6F73"/><bgColor indexed="64"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFDCE8F2"/><bgColor indexed="64"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFEEF3F6"/><bgColor indexed="64"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFF7FAFC"/><bgColor indexed="64"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border/>
    <border><bottom style="thin"><color rgb="FFB8C5CE"/></bottom></border>
  </borders>
  <cellStyleXfs count="1"><xf/></cellStyleXfs>
  <cellXfs count="13">
    <xf xfId="0" fontId="0" fillId="0" borderId="0"/>
    <xf xfId="0" fontId="1" fillId="2" borderId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center"/></xf>
    <xf xfId="0" fontId="4" fillId="0" borderId="0" applyFont="1" applyAlignment="1"><alignment vertical="center"/></xf>
    <xf xfId="0" fontId="2" fillId="3" borderId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center"/></xf>
    <xf xfId="0" fontId="3" fillId="4" borderId="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
    <xf xfId="0" fontId="3" fillId="5" borderId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
    <xf xfId="0" fontId="0" fillId="0" borderId="0" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
    <xf xfId="0" fontId="0" fillId="6" borderId="0" applyFill="1" applyAlignment="1"><alignment vertical="center"/></xf>
    <xf xfId="0" fontId="0" fillId="0" borderId="0" numFmtId="164" applyNumberFormat="1" applyAlignment="1"><alignment vertical="center"/></xf>
    <xf xfId="0" fontId="0" fillId="6" borderId="0" numFmtId="164" applyFill="1" applyNumberFormat="1" applyAlignment="1"><alignment vertical="center"/></xf>
    <xf xfId="0" fontId="0" fillId="0" borderId="0" numFmtId="164" applyNumberFormat="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
    <xf xfId="0" fontId="5" fillId="0" borderId="0" applyFont="1" applyAlignment="1"><alignment vertical="center"/></xf>
    <xf xfId="0" fontId="5" fillId="6" borderId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center"/></xf>
  </cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>"""
    core = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <dc:creator>Footprint</dc:creator>
</cp:coreProperties>"""
    app = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
  <Application>Footprint</Application>
</Properties>"""

    parts = {
        "[Content_Types].xml": content_types,
        "_rels/.rels": root_rels,
        "xl/workbook.xml": workbook,
        "xl/_rels/workbook.xml.rels": workbook_rels,
        "xl/styles.xml": styles,
        "docProps/core.xml": core,
        "docProps/app.xml": app,
    }
    for index, (_, xml, relationships) in enumerate(normalized, start=1):
        parts[f"xl/worksheets/sheet{index}.xml"] = xml
        if relationships is not None:
            parts[f"xl/worksheets/_rels/sheet{index}.xml.rels"] = relationships
    for value in parts.values():
        _validated_xml(value)

    with ZipFile(output_path, "w", compression=ZIP_DEFLATED) as archive:
        for name, value in parts.items():
            archive.writestr(name, value)
