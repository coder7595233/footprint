#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape, quoteattr

from ooxml_workbook import sanitize_xml_text


CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
  <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
</Types>
"""

ROOT_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
"""

DOCUMENT_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rIdHeader1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>
  <Relationship Id="rIdFooter1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>
</Relationships>
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export publications grouped in AMA style to a Word document.")
    parser.add_argument("--input-json", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def optional_int(value: object, fallback: int | None = None) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return fallback


def run(
    text: str,
    *,
    bold: bool = False,
    italic: bool = False,
    underline: bool = False,
    size: int | None = None,
    font: str | None = None,
) -> str:
    if not text:
        return ""
    run_props = ""
    if font:
        font_attr = quoteattr(font)
        run_props += f"<w:rFonts w:ascii={font_attr} w:hAnsi={font_attr} w:cs={font_attr}/>"
    if bold:
        run_props += "<w:b/>"
    if italic:
        run_props += "<w:i/>"
    if underline:
        run_props += '<w:u w:val="single"/>'
    if size is not None:
        run_props += f'<w:sz w:val="{size}"/><w:szCs w:val="{size}"/>'
    r_props = f"<w:rPr>{run_props}</w:rPr>" if run_props else ""
    parts = text.split("\t")
    runs: list[str] = []
    for index, part in enumerate(parts):
        if part:
            runs.append(f"<w:r>{r_props}<w:t xml:space=\"preserve\">{escape(sanitize_xml_text(part))}</w:t></w:r>")
        if index < len(parts) - 1:
            runs.append(f"<w:r>{r_props}<w:tab/></w:r>")
    return "".join(runs)


def name_highlight_phrases(phrase: str) -> list[str]:
    full = phrase.strip()
    if not full:
        return []
    variants = [full]
    particles = {"af", "av", "de", "del", "der", "van", "von", "la", "le", "da", "di"}
    words = full.split()
    if len(words) >= 2:
        surname_words = [words[-1]]
        if len(words) >= 3 and words[-2].lower() in particles:
            surname_words = words[-2:]
        surname = " ".join(surname_words)
        given_words = words[: len(words) - len(surname_words)]
        initials = "".join(word[0] for word in given_words if word and word[0].isalpha())
        if surname and initials:
            variants.append(f"{surname} {initials}")
            variants.append(f"{surname}, {initials}")
    seen: set[str] = set()
    ordered: list[str] = []
    for variant in sorted(variants, key=len, reverse=True):
        lowered = variant.lower()
        if lowered not in seen:
            seen.add(lowered)
            ordered.append(variant)
    return ordered


def paragraph(
    text: str,
    *,
    bold: bool = False,
    size: int | None = None,
    spacing_after: int = 120,
    font: str | None = None,
) -> str:
    p_props = f'<w:pPr><w:spacing w:after="{spacing_after}"/></w:pPr>'
    return f"<w:p>{p_props}{run(text, bold=bold, size=size, font=font)}</w:p>"


def header_xml(text: str, *, size: int = 20, font: str | None = None) -> str:
    body = (
        '<w:p>'
        '<w:pPr><w:jc w:val="right"/></w:pPr>'
        f'{run(text, size=size, font=font)}'
        '</w:p>'
    ) if text.strip() else '<w:p/>'
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:hdr xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
 xmlns:o="urn:schemas-microsoft-com:office:office"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
 xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
 xmlns:v="urn:schemas-microsoft-com:vml"
 xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing"
 xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
 xmlns:w10="urn:schemas-microsoft-com:office:word"
 xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
 xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"
 xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
 xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk"
 xmlns:wne="http://schemas.microsoft.com/office/2006/wordml"
 xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
 mc:Ignorable="w14 wp14">
  {body}
</w:hdr>
"""


def footer_xml(text: str = "", *, include_page_number: bool = False, size: int = 20, font: str | None = None) -> str:
    runs = []
    if text.strip():
        runs.append(run(text, size=size, font=font))
    if include_page_number:
        if runs:
            runs.append('<w:r><w:tab/></w:r>')
        runs.extend([
            '<w:r><w:fldChar w:fldCharType="begin"/></w:r>',
            '<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>',
            '<w:r><w:fldChar w:fldCharType="separate"/></w:r>',
            '<w:r><w:t>1</w:t></w:r>',
            '<w:r><w:fldChar w:fldCharType="end"/></w:r>',
        ])
    body = (
        '<w:p><w:pPr><w:jc w:val="center"/><w:tabs><w:tab w:val="center" w:pos="4680"/></w:tabs></w:pPr>'
        + "".join(runs) +
        '</w:p>'
    ) if runs else '<w:p/>'
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:ftr xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
 xmlns:o="urn:schemas-microsoft-com:office:office"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
 xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
 xmlns:v="urn:schemas-microsoft-com:vml"
 xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing"
 xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
 xmlns:w10="urn:schemas-microsoft-com:office:word"
 xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
 xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"
 xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
 xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk"
 xmlns:wne="http://schemas.microsoft.com/office/2006/wordml"
 xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
 mc:Ignorable="w14 wp14">
  {body}
</w:ftr>
"""


def styled_author_runs(authors: str, highlight_name: str, underlined_names: list[str], *, font: str | None = None, size: int | None = None) -> str:
    bold_variants = [(variant, "bold") for variant in name_highlight_phrases(highlight_name)]
    underline_variants: list[tuple[str, str]] = []
    for name in underlined_names:
        underline_variants.extend((variant, "underline") for variant in name_highlight_phrases(name))
    variants = bold_variants + underline_variants
    if not variants:
        return run(authors, font=font, size=size)

    runs: list[str] = []
    cursor = 0
    lower_authors = authors.lower()
    while cursor < len(authors):
        hit_index: int | None = None
        hit_text = ""
        hit_style = ""
        for candidate, style in variants:
            idx = lower_authors.find(candidate.lower(), cursor)
            if idx == -1:
                continue
            if hit_index is None or idx < hit_index or (idx == hit_index and len(candidate) > len(hit_text)):
                hit_index = idx
                hit_text = authors[idx:idx + len(candidate)]
                hit_style = style
        if hit_index is None:
            runs.append(run(authors[cursor:], font=font, size=size))
            break
        if hit_index > cursor:
            runs.append(run(authors[cursor:hit_index], font=font, size=size))
        runs.append(run(hit_text, bold=(hit_style == "bold"), underline=(hit_style == "underline"), font=font, size=size))
        cursor = hit_index + len(hit_text)
    return "".join(runs) if runs else run(authors, font=font, size=size)


TERMINAL_PUNCTUATION = (".", "?", "!")
TRAILING_CLOSERS = "\"')]}"


def has_terminal_punctuation(text: str) -> bool:
    stripped = text.strip().rstrip(TRAILING_CLOSERS)
    return stripped.endswith(TERMINAL_PUNCTUATION)


def citation_separator_after(text: str) -> str:
    return " " if has_terminal_punctuation(text) else ". "


def citation_paragraph(
    item: dict,
    highlight_name: str,
    underlined_names: list[str],
    spacing_after: int = 100,
    hanging_indent_twips: int | None = None,
    tab_stop_twips: int | None = None,
    font: str | None = None,
    size: int | None = None,
) -> str:
    p_prop_segments = [f'<w:spacing w:after="{spacing_after}"/>']
    if hanging_indent_twips is not None and hanging_indent_twips > 0:
        p_prop_segments.append(f'<w:ind w:left="{hanging_indent_twips}" w:hanging="{hanging_indent_twips}"/>')
    if tab_stop_twips is not None and tab_stop_twips > 0:
        p_prop_segments.append(f'<w:tabs><w:tab w:val="left" w:pos="{tab_stop_twips}"/></w:tabs>')
    p_props = f"<w:pPr>{''.join(p_prop_segments)}</w:pPr>"
    authors = item.get("authors", "")
    title = item.get("title", "")
    journal = item.get("journal", "")
    tail = item.get("tail", "")
    note = item.get("note", "")

    runs = []
    last_segment = ""

    def append_separator_if_needed() -> None:
        if last_segment:
            runs.append(run(citation_separator_after(last_segment), font=font, size=size))

    if authors:
        append_separator_if_needed()
        runs.append(styled_author_runs(authors, highlight_name, underlined_names, font=font, size=size))
        last_segment = authors
    if title:
        append_separator_if_needed()
        runs.append(run(title, font=font, size=size))
        last_segment = title
    if journal:
        append_separator_if_needed()
        runs.append(run(journal, italic=True, font=font, size=size))
        last_segment = journal
    if tail:
        append_separator_if_needed()
        runs.append(run(tail, font=font, size=size))
        last_segment = tail
    if last_segment and not has_terminal_punctuation(last_segment):
        runs.append(run(".", font=font, size=size))
    if note:
        runs.append(run(" ", font=font, size=size))
        runs.append(run(note, font=font, size=size))
    return f"<w:p>{p_props}{''.join(runs)}</w:p>"


def build_document(payload: dict) -> str:
    parts: list[str] = []
    title = payload.get("title", "Publications")
    highlight_name = payload.get("highlightName", "")
    underlined_names = payload.get("underlinedNames", [])
    hanging_indent_twips = payload.get("citationIndentTwips")
    tab_stop_twips = payload.get("citationTabStopTwips")
    font = (payload.get("fontFamily") or "").strip() or None
    body_size = optional_int(payload.get("fontSizeHalfPoints"))
    title_size = optional_int(payload.get("titleFontSizeHalfPoints"), body_size if body_size is not None else 32)
    section_size = optional_int(payload.get("sectionFontSizeHalfPoints"), body_size if body_size is not None else 26)
    parts.append(paragraph(title, bold=True, size=title_size, spacing_after=220, font=font))

    for section in payload.get("sections", []):
        parts.append(paragraph(section.get("title", ""), bold=True, size=section_size, spacing_after=160, font=font))
        items = section.get("items", [])
        if not items:
            parts.append(paragraph(" ", spacing_after=100, font=font, size=body_size))
            continue
        for item in items:
            parts.append(
                citation_paragraph(
                    item,
                    highlight_name,
                    underlined_names,
                    spacing_after=100,
                    hanging_indent_twips=hanging_indent_twips,
                    tab_stop_twips=tab_stop_twips,
                    font=font,
                    size=body_size,
                )
            )

    header_ref = '<w:headerReference w:type="default" r:id="rIdHeader1"/>'
    footer_ref = '<w:footerReference w:type="default" r:id="rIdFooter1"/>'
    page_width_twips = optional_int(payload.get("pageWidthTwips"), 11906)
    page_height_twips = optional_int(payload.get("pageHeightTwips"), 16838)
    page_size_code = optional_int(payload.get("pageSizeCode"))
    page_size_code_xml = f' w:code="{page_size_code}"' if page_size_code is not None else ""
    body = "".join(parts) + (
        '<w:sectPr>'
        f'{header_ref}{footer_ref}'
        f'<w:pgSz w:w="{page_width_twips}" w:h="{page_height_twips}"{page_size_code_xml}/>'
        '<w:pgMar w:top="1417" w:right="1417" w:bottom="1135" w:left="1417" w:header="708" w:footer="708" w:gutter="0"/>'
        '<w:cols w:space="708"/>'
        '</w:sectPr>'
    )
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
 xmlns:o="urn:schemas-microsoft-com:office:office"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
 xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
 xmlns:v="urn:schemas-microsoft-com:vml"
 xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing"
 xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
 xmlns:w10="urn:schemas-microsoft-com:office:word"
 xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
 xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"
 xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
 xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk"
 xmlns:wne="http://schemas.microsoft.com/office/2006/wordml"
 xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
 mc:Ignorable="w14 wp14">
  <w:body>{body}</w:body>
</w:document>
"""


def main() -> None:
    args = parse_args()
    payload = json.loads(args.input_json.read_text())
    document_xml = build_document(payload)
    font = (payload.get("fontFamily") or "").strip() or None
    body_size = optional_int(payload.get("fontSizeHalfPoints"))
    header_footer_size = optional_int(payload.get("headerFooterFontSizeHalfPoints"), body_size if body_size is not None else 20) or 20
    header = header_xml(payload.get("headerText", ""), size=header_footer_size, font=font)
    footer = footer_xml(
        payload.get("footerText", ""),
        include_page_number=bool(payload.get("includePageNumbers", False)),
        size=header_footer_size,
        font=font,
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", CONTENT_TYPES)
        archive.writestr("_rels/.rels", ROOT_RELS)
        archive.writestr("word/document.xml", document_xml)
        archive.writestr("word/header1.xml", header)
        archive.writestr("word/footer1.xml", footer)
        archive.writestr("word/_rels/document.xml.rels", DOCUMENT_RELS)

    print(f"Wrote AMA Word document to {args.output}")


if __name__ == "__main__":
    main()
