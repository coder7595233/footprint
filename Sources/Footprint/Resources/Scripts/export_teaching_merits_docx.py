#!/usr/bin/env python3

from __future__ import annotations

import argparse
import copy
import json
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from ooxml_workbook import sanitize_xml_text


W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
XML_NS = "http://www.w3.org/XML/1998/namespace"
REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
CONTENT_TYPES_NS = "http://schemas.openxmlformats.org/package/2006/content-types"


for prefix, uri in [
    ("w", W_NS),
    ("r", "http://schemas.openxmlformats.org/officeDocument/2006/relationships"),
    ("mc", "http://schemas.openxmlformats.org/markup-compatibility/2006"),
    ("w14", "http://schemas.microsoft.com/office/word/2010/wordml"),
    ("w15", "http://schemas.microsoft.com/office/word/2012/wordml"),
    ("w16", "http://schemas.microsoft.com/office/word/2018/wordml"),
    ("w16cex", "http://schemas.microsoft.com/office/word/2018/wordml/cex"),
    ("w16cid", "http://schemas.microsoft.com/office/word/2016/wordml/cid"),
    ("w16du", "http://schemas.microsoft.com/office/word/2023/wordml/word16du"),
    ("w16sdtdh", "http://schemas.microsoft.com/office/word/2020/wordml/sdtdatahash"),
    ("w16sdtfl", "http://schemas.microsoft.com/office/word/2024/wordml/sdtformatlock"),
    ("w16se", "http://schemas.microsoft.com/office/word/2015/wordml/symex"),
]:
    ET.register_namespace(prefix, uri)


def qn(local: str) -> str:
    return f"{{{W_NS}}}{local}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export teaching merits using a Word template.")
    parser.add_argument("--input-json", type=Path, required=True)
    parser.add_argument("--template", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def cell_text(cell: ET.Element) -> str:
    return "".join(cell.itertext()).strip().replace("\n", " ")


def row_cells(row: ET.Element) -> list[ET.Element]:
    return row.findall(qn("tc"))


def strip_italics(element: ET.Element) -> None:
    for tag in (qn("i"), qn("iCs")):
        for italic in list(element.iter(tag)):
            parent = None
            for candidate in element.iter():
                if italic in list(candidate):
                    parent = candidate
                    break
            if parent is not None:
                parent.remove(italic)


def first_run_properties(cell: ET.Element) -> ET.Element | None:
    for run in cell.iter(qn("r")):
        rpr = run.find(qn("rPr"))
        if rpr is not None:
            cloned = copy.deepcopy(rpr)
            strip_italics(cloned)
            return cloned
    return None


def set_cell_text(cell: ET.Element, value: str) -> None:
    paragraphs = cell.findall(qn("p"))
    if paragraphs:
        paragraph = paragraphs[0]
        for extra in paragraphs[1:]:
            cell.remove(extra)
    else:
        paragraph = ET.SubElement(cell, qn("p"))

    ppr = paragraph.find(qn("pPr"))
    run_properties = first_run_properties(cell)
    for child in list(paragraph):
        if child is not ppr:
            paragraph.remove(child)

    lines = value.split("\n") if value else [""]
    for index, line in enumerate(lines):
        run = ET.SubElement(paragraph, qn("r"))
        if run_properties is not None:
            run.append(copy.deepcopy(run_properties))
        if index:
            ET.SubElement(run, qn("br"))
        text = ET.SubElement(run, qn("t"))
        if line.startswith(" ") or line.endswith(" "):
            text.set(f"{{{XML_NS}}}space", "preserve")
        text.text = sanitize_xml_text(line)


def set_row_values(row: ET.Element, values: list[str]) -> None:
    cells = row_cells(row)
    for index, cell in enumerate(cells):
        set_cell_text(cell, values[index] if index < len(values) else "")


def insert_rows_before(table: ET.Element, before_row: ET.Element, rows: list[ET.Element]) -> None:
    children = list(table)
    insert_index = children.index(before_row)
    for offset, row in enumerate(rows):
        table.insert(insert_index + offset, row)


def insert_elements_before(parent: ET.Element, before: ET.Element, elements: list[ET.Element]) -> None:
    children = list(parent)
    insert_index = children.index(before)
    for offset, element in enumerate(elements):
        parent.insert(insert_index + offset, element)


def populate_segment(
    table: ET.Element,
    *,
    data_start_index: int,
    sum_row_index: int,
    values: list[list[str]],
    minimum_visible_rows: int = 1,
) -> ET.Element:
    rows = table.findall(qn("tr"))
    sample_row = copy.deepcopy(rows[data_start_index])
    strip_italics(sample_row)
    sum_row = rows[sum_row_index]

    for row in rows[data_start_index:sum_row_index]:
        table.remove(row)

    visible_row_count = max(minimum_visible_rows, len(values)) if not values else len(values)
    inserted_rows: list[ET.Element] = []
    for index in range(visible_row_count):
        row = copy.deepcopy(sample_row)
        set_row_values(row, values[index] if index < len(values) else [])
        inserted_rows.append(row)
    insert_rows_before(table, sum_row, inserted_rows)
    return sum_row


def set_sum_row(sum_row: ET.Element, label: str, value: str) -> None:
    cells = row_cells(sum_row)
    if not cells:
        return
    if len(cells) == 1:
        set_cell_text(cells[0], " ".join(part for part in [label, value] if part).strip())
        return
    for cell in cells[:-2]:
        set_cell_text(cell, "")
    set_cell_text(cells[-2], label)
    set_cell_text(cells[-1], value)


def normalize_title(title: str) -> str:
    return " ".join(title.replace("\n", " ").split())


def table_payload_map(payload: dict) -> tuple[dict[str, dict], list[list[str]]]:
    title_map: dict[str, dict] = {}
    for group in payload.get("groups", []):
        for table in group.get("tables", []):
            title_map[normalize_title(table.get("title", ""))] = table
    return title_map, payload.get("summaryRows", [])


def find_payload(title_map: dict[str, dict], prefix: str) -> dict:
    for title, payload in title_map.items():
        if title.startswith(prefix):
            return payload
    return {"rows": [], "sumLabel": "Summa:", "sumValue": ""}


def safe_text(value: object) -> str:
    if value is None:
        return ""
    return str(value)


def append_text_run(
    paragraph: ET.Element,
    value: str,
    *,
    bold: bool = False,
    font: str | None = "Calibri",
    size: str | None = "22",
    color: str | None = None,
) -> None:
    run = ET.SubElement(paragraph, qn("r"))
    if bold or font or size or color:
        rpr = ET.SubElement(run, qn("rPr"))
        if font:
            fonts = ET.SubElement(rpr, qn("rFonts"))
            fonts.set(qn("ascii"), font)
            fonts.set(qn("hAnsi"), font)
            fonts.set(qn("cs"), font)
        ET.SubElement(rpr, qn("b"))
        if bold:
            ET.SubElement(rpr, qn("bCs"))
        else:
            rpr.remove(rpr.find(qn("b")))
        if color:
            color_element = ET.SubElement(rpr, qn("color"))
            color_element.set(qn("val"), color)
        if size:
            size_element = ET.SubElement(rpr, qn("sz"))
            size_element.set(qn("val"), size)
            size_cs = ET.SubElement(rpr, qn("szCs"))
            size_cs.set(qn("val"), size)
    text = ET.SubElement(run, qn("t"))
    if value.startswith(" ") or value.endswith(" "):
        text.set(f"{{{XML_NS}}}space", "preserve")
    text.text = sanitize_xml_text(value)


def standalone_paragraph(
    value: str = "",
    *,
    style: str | None = None,
    bold: bool = False,
    font: str | None = "Calibri",
    size: str | None = "22",
    color: str | None = None,
    spacing_after: str = "120",
    spacing_before: str | None = None,
) -> ET.Element:
    paragraph = ET.Element(qn("p"))
    properties = ET.SubElement(paragraph, qn("pPr"))
    if style:
        paragraph_style = ET.SubElement(properties, qn("pStyle"))
        paragraph_style.set(qn("val"), style)
    spacing = ET.SubElement(properties, qn("spacing"))
    if spacing_before is not None:
        spacing.set(qn("before"), spacing_before)
    spacing.set(qn("after"), spacing_after)
    spacing.set(qn("line"), "240")
    spacing.set(qn("lineRule"), "auto")
    if value:
        append_text_run(paragraph, value, bold=bold, font=font, size=size, color=color)
    return paragraph


def standalone_cell(
    value: str,
    *,
    bold: bool = False,
    grid_span: int = 1,
    fill: str | None = None,
    width_value: int | None = None,
    font: str | None = "Calibri",
    size: str | None = "22",
) -> ET.Element:
    cell = ET.Element(qn("tc"))
    properties = ET.SubElement(cell, qn("tcPr"))
    width = ET.SubElement(properties, qn("tcW"))
    width.set(qn("w"), str(width_value if width_value is not None else 0))
    width.set(qn("type"), "dxa" if width_value is not None else "auto")
    if grid_span > 1:
        span = ET.SubElement(properties, qn("gridSpan"))
        span.set(qn("val"), str(grid_span))
    if fill:
        shading = ET.SubElement(properties, qn("shd"))
        shading.set(qn("val"), "clear")
        shading.set(qn("color"), "auto")
        shading.set(qn("fill"), fill)
    cell.append(standalone_paragraph(value, bold=bold, font=font, size=size, spacing_after="0"))
    return cell


def standalone_row(
    values: list[str],
    *,
    widths: list[int],
    bold: bool = False,
    fill: str | None = None,
    font: str | None = "Calibri",
    size: str | None = "22",
) -> ET.Element:
    row = ET.Element(qn("tr"))
    for index, width in enumerate(widths):
        row.append(standalone_cell(
            values[index] if index < len(values) else "",
            bold=bold,
            fill=fill,
            width_value=width,
            font=font,
            size=size,
        ))
    return row


def standalone_title_row(title: str, widths: list[int], fill: str) -> ET.Element:
    row = ET.Element(qn("tr"))
    row.append(standalone_cell(
        title,
        bold=True,
        grid_span=len(widths),
        fill=fill,
        width_value=sum(widths),
        font="Calibri",
        size="22",
    ))
    return row


def standalone_sum_row(label: str, value: str, widths: list[int], fill: str) -> ET.Element:
    row = ET.Element(qn("tr"))
    if len(widths) == 1:
        row.append(standalone_cell(
            " ".join(part for part in [label, value] if part).strip(),
            bold=True,
            fill=fill,
            width_value=widths[0],
            font="Calibri",
            size="22",
        ))
        return row
    row.append(standalone_cell(
        label,
        bold=True,
        grid_span=len(widths) - 1,
        fill=fill,
        width_value=sum(widths[:-1]),
        font="Calibri",
        size="22",
    ))
    row.append(standalone_cell(value, bold=True, fill=fill, width_value=widths[-1], font="Calibri", size="22"))
    return row


def standalone_column_count(headers: list[str], rows: list[list[str]]) -> int:
    row_width = max((len(row) for row in rows), default=0)
    return max(len(headers), row_width, 2)


def standalone_table_grid(widths: list[int]) -> ET.Element:
    grid = ET.Element(qn("tblGrid"))
    for width in widths:
        column = ET.SubElement(grid, qn("gridCol"))
        column.set(qn("w"), str(width))
    return grid


def standalone_table_borders(properties: ET.Element) -> None:
    borders = ET.SubElement(properties, qn("tblBorders"))
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        border = ET.SubElement(borders, qn(edge))
        border.set(qn("val"), "single")
        border.set(qn("sz"), "4")
        border.set(qn("space"), "0")
        border.set(qn("color"), "auto")


def standalone_widths_for_table(title: str, headers: list[str], rows: list[list[str]]) -> list[int]:
    column_count = standalone_column_count(headers, rows)
    normalized = normalize_title(title)
    if normalized.startswith("Schemalagd grupphandledning"):
        widths = [1303, 1101, 3543, 1136, 1701, 2551, 2799]
    elif normalized.startswith("Schemalagda föreläsningar") or normalized.startswith("Schemalagd undervisning på forskarutbildningskurs"):
        widths = [1347, 1058, 3544, 1134, 1701, 2551, 2815]
    elif normalized.startswith("Handledning av examensarbeten"):
        widths = [1366, 1123, 908, 1560, 4677, 4534]
    elif normalized.startswith("Handledning av studerande på forskarnivå - huvudhandledare"):
        widths = [1366, 1181, 850, 4678, 1559, 4534]
    elif normalized.startswith("Handledning av studerande på forskarnivå - bihandledare"):
        widths = [1365, 1182, 850, 4678, 1559, 4534]
    elif normalized.startswith("Kursansvar"):
        widths = [1507, 1032, 858, 3828, 2409, 4566]
    elif normalized.startswith("Sammanfattning"):
        widths = [12090, 1904]
    else:
        widths = [max(int(14150 / column_count), 850)] * column_count

    if len(widths) == column_count:
        return widths
    if len(widths) > column_count:
        return widths[:column_count]
    return widths + [max(int(14150 / column_count), 850)] * (column_count - len(widths))


def standalone_table_colors(title: str) -> tuple[str, str, str]:
    normalized = normalize_title(title)
    if normalized.startswith("Handledning"):
        return "F6C5AC", "FAE2D5", "FAE2D5"
    if normalized.startswith("Kursansvar"):
        return "BBE4A4", "D9F2D0", "D9F2D0"
    if normalized.startswith("Sammanfattning"):
        return "D9D9D9", "D9D9D9", "E8E8E8"
    return "A5C9EB", "DAE9F7", "DAE9F7"


def standalone_table(title: str, headers: list[str], rows: list[list[str]], sum_label: str, sum_value: str) -> ET.Element:
    widths = standalone_widths_for_table(title, headers, rows)
    title_fill, header_fill, sum_fill = standalone_table_colors(title)
    table = ET.Element(qn("tbl"))
    properties = ET.SubElement(table, qn("tblPr"))
    style = ET.SubElement(properties, qn("tblStyle"))
    style.set(qn("val"), "Tabellrutnt")
    width = ET.SubElement(properties, qn("tblW"))
    width.set(qn("w"), str(sum(widths)))
    width.set(qn("type"), "dxa")
    layout = ET.SubElement(properties, qn("tblLayout"))
    layout.set(qn("type"), "fixed")
    standalone_table_borders(properties)
    look = ET.SubElement(properties, qn("tblLook"))
    look.set(qn("val"), "04A0")
    look.set(qn("firstRow"), "1")
    look.set(qn("lastRow"), "0")
    look.set(qn("firstColumn"), "1")
    look.set(qn("lastColumn"), "0")
    look.set(qn("noHBand"), "0")
    look.set(qn("noVBand"), "1")
    table.append(standalone_table_grid(widths))
    table.append(standalone_title_row(title, widths, title_fill))
    if headers:
        table.append(standalone_row(headers, widths=widths, bold=True, fill=header_fill, font="Arial", size="20"))
    visible_rows = rows if rows else [[]]
    for row_values in visible_rows:
        table.append(standalone_row([safe_text(value) for value in row_values], widths=widths, font="Calibri", size="22"))
    table.append(standalone_sum_row(sum_label, sum_value, widths, sum_fill))
    return table


def standalone_summary_table(payload: dict) -> ET.Element:
    summary_rows = payload.get("summaryRows", [])
    summary_values = summary_rows
    summary_total = ""
    if summary_rows and normalize_title(summary_rows[-1][0] if summary_rows[-1] else "").startswith("Summa"):
        summary_total = safe_text(summary_rows[-1][1] if len(summary_rows[-1]) > 1 else "")
        summary_values = summary_rows[:-1]
    headers = [safe_text(value) for value in payload.get("summaryHeaders", [])]
    rows = [[safe_text(value) for value in row] for row in summary_values]
    widths = standalone_widths_for_table("Sammanfattning", headers, rows)
    table = ET.Element(qn("tbl"))
    properties = ET.SubElement(table, qn("tblPr"))
    style = ET.SubElement(properties, qn("tblStyle"))
    style.set(qn("val"), "Tabellrutnt")
    width = ET.SubElement(properties, qn("tblW"))
    width.set(qn("w"), "0")
    width.set(qn("type"), "auto")
    standalone_table_borders(properties)
    look = ET.SubElement(properties, qn("tblLook"))
    look.set(qn("val"), "04A0")
    look.set(qn("firstRow"), "1")
    look.set(qn("lastRow"), "0")
    look.set(qn("firstColumn"), "1")
    look.set(qn("lastColumn"), "0")
    look.set(qn("noHBand"), "0")
    look.set(qn("noVBand"), "1")
    table.append(standalone_table_grid(widths))
    table.append(standalone_row(headers, widths=widths, bold=True, fill="D9D9D9", font="Calibri", size="22"))
    visible_rows = rows if rows else [[]]
    for row_values in visible_rows:
        table.append(standalone_row(row_values, widths=widths, font="Calibri", size="22"))
    table.append(standalone_sum_row("Summa:", summary_total, widths, "E8E8E8"))
    return table


def standalone_document_root(payload: dict) -> ET.Element:
    document = ET.Element(qn("document"))
    body = ET.SubElement(document, qn("body"))
    faculty_name = safe_text(payload.get("facultyName") or "").strip()
    heading = (
        f"Redovisning av pedagogiska meriter för vid {faculty_name}"
        if faculty_name
        else "Redovisning av pedagogiska meriter"
    )
    body.append(standalone_paragraph(
        heading,
        style="Rubrik2",
        font=None,
        size="32",
        color="0F4761",
        spacing_before="160",
        spacing_after="80",
    ))
    intro_paragraphs = [
        "Fyll i tabellerna nedan med relevant erfarenhet för din docenturansökan. Fokusera på de senaste 6 åren och redovisa dem med senast utfört högst upp i respektive tabell. Har du äldre pedagogiska meriter du vill inkludera, kan du göra det på en övergripande nivå (t ex \"40% av min tid bestod av undervisning under åren 2010-2015\").",
        "",
        "För undervisningstid går det utmärkt att använda Retendo-utdrag för antal timmar. I de fall dina uppdrag inte finns i Retendo, ska undervisningstid redovisas. Förberedelsetid och faktisk undervisningstid räknas in i detta.",
        "",
        "Ta bort exemplena i kursiv stil när du fyller i dina meriter. Behöver du fler rader kan du själv lägga till dessa.",
        "",
        "",
    ]
    for text in intro_paragraphs:
        body.append(standalone_paragraph(text, font="Calibri", size="22", spacing_after="0"))

    for group in payload.get("groups", []):
        group_title = safe_text(group.get("title", "")).strip()
        if group_title:
            body.append(standalone_paragraph(
                group_title,
                style="Rubrik3",
                font=None,
                size="28",
                color="0F4761",
                spacing_before="160",
                spacing_after="80",
            ))
            body.append(standalone_paragraph(spacing_after="0"))
        for table_payload in group.get("tables", []):
            headers = [safe_text(value) for value in table_payload.get("headers", [])]
            rows = [[safe_text(value) for value in row] for row in table_payload.get("rows", [])]
            body.append(standalone_table(
                safe_text(table_payload.get("title", "")),
                headers,
                rows,
                safe_text(table_payload.get("sumLabel", "Summa:")),
                safe_text(table_payload.get("sumValue", "")),
            ))
            body.append(standalone_paragraph(spacing_after="180"))

    body.append(standalone_paragraph(
        "Sammanställning",
        style="Rubrik2",
        font=None,
        size="32",
        color="0F4761",
        spacing_before="160",
        spacing_after="80",
    ))
    body.append(standalone_paragraph(spacing_after="0"))
    body.append(standalone_summary_table(payload))

    section = ET.SubElement(body, qn("sectPr"))
    page_size = ET.SubElement(section, qn("pgSz"))
    page_size.set(qn("w"), "11906")
    page_size.set(qn("h"), "16838")
    page_margins = ET.SubElement(section, qn("pgMar"))
    page_margins.set(qn("top"), "1134")
    page_margins.set(qn("right"), "850")
    page_margins.set(qn("bottom"), "1134")
    page_margins.set(qn("left"), "850")
    page_margins.set(qn("header"), "708")
    page_margins.set(qn("footer"), "708")
    page_margins.set(qn("gutter"), "0")
    return document


def content_types_xml() -> bytes:
    types = ET.Element(f"{{{CONTENT_TYPES_NS}}}Types")
    default_rels = ET.SubElement(types, f"{{{CONTENT_TYPES_NS}}}Default")
    default_rels.set("Extension", "rels")
    default_rels.set("ContentType", "application/vnd.openxmlformats-package.relationships+xml")
    default_xml = ET.SubElement(types, f"{{{CONTENT_TYPES_NS}}}Default")
    default_xml.set("Extension", "xml")
    default_xml.set("ContentType", "application/xml")
    document_override = ET.SubElement(types, f"{{{CONTENT_TYPES_NS}}}Override")
    document_override.set("PartName", "/word/document.xml")
    document_override.set("ContentType", "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml")
    return ET.tostring(types, encoding="utf-8", xml_declaration=True)


def package_relationships_xml() -> bytes:
    relationships = ET.Element(f"{{{REL_NS}}}Relationships")
    relationship = ET.SubElement(relationships, f"{{{REL_NS}}}Relationship")
    relationship.set("Id", "rId1")
    relationship.set("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument")
    relationship.set("Target", "word/document.xml")
    return ET.tostring(relationships, encoding="utf-8", xml_declaration=True)


def empty_relationships_xml() -> bytes:
    relationships = ET.Element(f"{{{REL_NS}}}Relationships")
    return ET.tostring(relationships, encoding="utf-8", xml_declaration=True)


def table_row_title(row: ET.Element) -> str:
    return normalize_title(cell_text(row))


def table_contains_title(table: ET.Element, prefix: str) -> bool:
    return any(table_row_title(row).startswith(prefix) for row in table.findall(qn("tr")))


def split_table_at_row(table: ET.Element, split_index: int) -> tuple[ET.Element, ET.Element]:
    rows = table.findall(qn("tr"))
    first_table = copy.deepcopy(table)
    second_table = copy.deepcopy(table)
    for target in (first_table, second_table):
        for row in target.findall(qn("tr")):
            target.remove(row)
    for row in rows[:split_index]:
        first_table.append(copy.deepcopy(row))
    for row in rows[split_index:]:
        second_table.append(copy.deepcopy(row))
    return first_table, second_table


def spacer_paragraph() -> ET.Element:
    paragraph = ET.Element(qn("p"))
    properties = ET.SubElement(paragraph, qn("pPr"))
    spacing = ET.SubElement(properties, qn("spacing"))
    spacing.set(qn("after"), "120")
    spacing.set(qn("line"), "240")
    spacing.set(qn("lineRule"), "auto")
    return paragraph


def logical_teaching_tables(body: ET.Element) -> list[ET.Element]:
    tables = body.findall(qn("tbl"))
    if len(tables) >= 8:
        return tables
    if len(tables) < 7:
        raise RuntimeError("Unexpected teaching merits template structure.")

    first_table = tables[0]
    rows = first_table.findall(qn("tr"))
    lecture_start_index = next(
        (
            index
            for index, row in enumerate(rows)
            if index > 0 and table_row_title(row).startswith("Schemalagda föreläsningar")
        ),
        None,
    )
    if lecture_start_index is None or not table_contains_title(first_table, "Schemalagd grupphandledning"):
        raise RuntimeError("Unexpected teaching merits template structure.")

    group_table, lecture_table = split_table_at_row(first_table, lecture_start_index)
    insert_elements_before(body, first_table, [group_table, spacer_paragraph(), lecture_table, spacer_paragraph()])
    body.remove(first_table)
    return body.findall(qn("tbl"))


def populate_template_document(root: ET.Element, payload: dict) -> None:
    body = root.find(qn("body"))
    if body is None:
        raise RuntimeError("Template document body not found.")

    tables = logical_teaching_tables(body)
    if len(tables) < 8:
        raise RuntimeError("Unexpected teaching merits template structure.")

    title_map, summary_rows = table_payload_map(payload)

    group_teaching = find_payload(title_map, "Schemalagd grupphandledning")
    lectures = find_payload(title_map, "Schemalagda föreläsningar")
    doctoral_course = find_payload(title_map, "Schemalagd undervisning på forskarutbildningskurs")
    thesis = find_payload(title_map, "Handledning av examensarbeten")
    doctoral_main = find_payload(title_map, "Handledning av studerande på forskarnivå - huvudhandledare")
    doctoral_assistant = find_payload(title_map, "Handledning av studerande på forskarnivå - bihandledare")
    course_admin = find_payload(title_map, "Kursansvar, kursadministration och/eller kursutveckling")

    group_sum_row = populate_segment(tables[0], data_start_index=2, sum_row_index=8, values=group_teaching.get("rows", []))
    set_sum_row(group_sum_row, group_teaching.get("sumLabel", "Summa:"), group_teaching.get("sumValue", ""))
    lectures_sum_row = populate_segment(tables[1], data_start_index=2, sum_row_index=8, values=lectures.get("rows", []))
    set_sum_row(lectures_sum_row, lectures.get("sumLabel", "Summa:"), lectures.get("sumValue", ""))

    for table, section in [
        (tables[2], doctoral_course),
        (tables[3], thesis),
        (tables[4], doctoral_main),
        (tables[5], doctoral_assistant),
        (tables[6], course_admin),
    ]:
        sum_row = populate_segment(table, data_start_index=2, sum_row_index=8, values=section.get("rows", []))
        set_sum_row(sum_row, section.get("sumLabel", "Summa:"), section.get("sumValue", ""))

    summary_total = ""
    summary_values = summary_rows
    if summary_rows and normalize_title(summary_rows[-1][0] if summary_rows[-1] else "").startswith("Summa"):
        summary_total = summary_rows[-1][1] if len(summary_rows[-1]) > 1 else ""
        summary_values = summary_rows[:-1]
    summary_sum_row = populate_segment(tables[7], data_start_index=1, sum_row_index=8, values=summary_values)
    set_sum_row(summary_sum_row, "Summa:", summary_total)


def write_from_template(template_path: Path, output_path: Path, payload: dict) -> None:
    with zipfile.ZipFile(template_path, "r") as template_archive:
        document_xml = template_archive.read("word/document.xml")
        root = ET.fromstring(document_xml)
        populate_template_document(root, payload)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED) as output_archive:
            for info in template_archive.infolist():
                data = template_archive.read(info.filename)
                if info.filename == "word/document.xml":
                    data = ET.tostring(root, encoding="utf-8", xml_declaration=True)
                output_archive.writestr(info, data)


def write_standalone_document(output_path: Path, payload: dict) -> None:
    root = standalone_document_root(payload)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED) as output_archive:
        output_archive.writestr("[Content_Types].xml", content_types_xml())
        output_archive.writestr("_rels/.rels", package_relationships_xml())
        output_archive.writestr("word/document.xml", ET.tostring(root, encoding="utf-8", xml_declaration=True))
        output_archive.writestr("word/_rels/document.xml.rels", empty_relationships_xml())


def main() -> None:
    args = parse_args()
    payload = json.loads(args.input_json.read_text())
    if args.template:
        write_from_template(args.template, args.output, payload)
    else:
        write_standalone_document(args.output, payload)
    print(f"Wrote teaching merits Word document to {args.output}")


if __name__ == "__main__":
    main()
