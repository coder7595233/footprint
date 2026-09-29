#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import zipfile
from datetime import date
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
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/word/fontTable.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml"/>
  <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
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

OWN_HANGING_TWIPS = 1417
OWN_SHORT_HANGING_TWIPS = 567
# Width of "\u2022 " at 12 pt Times New Roman; bullet paragraphs hang by this.
PROTOCOL_BULLET_TWIPS = 170
# Extra left indent per nested list level in protocol sections.
PROTOCOL_BULLET_LEVEL_TWIPS = 283
# One prefix per list level; must match ProtocolMarkup.bulletPrefixes.
PROTOCOL_BULLET_PREFIXES = ("\u2022 ", "\u25e6 ", "\u25aa ")


def protocol_bullet_level(text: str) -> int | None:
    for index, prefix in enumerate(PROTOCOL_BULLET_PREFIXES):
        if text.startswith(prefix):
            return index + 1
    return None


OWN_STYLES_TEMPLATE = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>
        <w:lang w:val="{lang_code}"/>
      </w:rPr>
    </w:rPrDefault>
    <w:pPrDefault>
      <w:pPr>
        <w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>
      </w:pPr>
    </w:pPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:qFormat/>
    <w:pPr>
      <w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>
      <w:sz w:val="24"/>
      <w:szCs w:val="24"/>
      <w:lang w:val="{lang_code}"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:customStyle="1" w:styleId="TITEL">
    <w:name w:val="TITEL"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:rPr>
      <w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/>
      <w:sz w:val="36"/>
      <w:szCs w:val="36"/>
      <w:lang w:val="{lang_code}"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Rubrik1">
    <w:name w:val="heading 1"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="Normal"/>
    <w:qFormat/>
    <w:pPr><w:outlineLvl w:val="0"/></w:pPr>
    <w:rPr>
      <w:b/>
      <w:lang w:val="{lang_code}"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:customStyle="1" w:styleId="Hngande">
    <w:name w:val="Hängande"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:pPr>
      <w:widowControl w:val="0"/>
      <w:tabs>
        <w:tab w:val="left" w:pos="{own_hanging_twips}"/>
      </w:tabs>
      <w:ind w:left="{own_hanging_twips}" w:hanging="{own_hanging_twips}"/>
    </w:pPr>
    <w:rPr>
      <w:lang w:val="{lang_code}"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:customStyle="1" w:styleId="Hngandekort">
    <w:name w:val="Hängande kort"/>
    <w:basedOn w:val="Hngande"/>
    <w:qFormat/>
    <w:pPr>
      <w:tabs>
        <w:tab w:val="clear" w:pos="{own_hanging_twips}"/>
        <w:tab w:val="left" w:pos="{own_short_hanging_twips}"/>
      </w:tabs>
      <w:ind w:left="{own_short_hanging_twips}" w:hanging="{own_short_hanging_twips}"/>
    </w:pPr>
    <w:rPr>
      <w:lang w:val="{lang_code}"/>
    </w:rPr>
  </w:style>
</w:styles>
"""

LIU_STYLES_TEMPLATE = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/>
        <w:lang w:val="{lang_code}"/>
      </w:rPr>
    </w:rPrDefault>
    <w:pPrDefault>
      <w:pPr>
        <w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>
      </w:pPr>
    </w:pPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:qFormat/>
    <w:pPr>
      <w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/>
      <w:sz w:val="24"/>
      <w:szCs w:val="24"/>
      <w:lang w:val="{lang_code}"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:customStyle="1" w:styleId="LiuSection">
    <w:name w:val="LiuSection"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:rPr>
      <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>
      <w:b/>
      <w:lang w:val="{lang_code}"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:customStyle="1" w:styleId="LiuSubsection">
    <w:name w:val="LiuSubsection"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:rPr>
      <w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/>
      <w:b/>
      <w:lang w:val="{lang_code}"/>
    </w:rPr>
  </w:style>
</w:styles>
"""

VR_STYLES_TEMPLATE = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/>
        <w:lang w:val="{lang_code}"/>
      </w:rPr>
    </w:rPrDefault>
    <w:pPrDefault>
      <w:pPr>
        <w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>
      </w:pPr>
    </w:pPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:qFormat/>
    <w:pPr>
      <w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/>
      <w:sz w:val="22"/>
      <w:szCs w:val="22"/>
      <w:lang w:val="{lang_code}"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:customStyle="1" w:styleId="VrHeading">
    <w:name w:val="VrHeading"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:rPr>
      <w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/>
      <w:b/>
      <w:sz w:val="22"/>
      <w:szCs w:val="22"/>
      <w:lang w:val="{lang_code}"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:customStyle="1" w:styleId="VrSubheading">
    <w:name w:val="VrSubheading"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:rPr>
      <w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/>
      <w:b/>
      <w:sz w:val="22"/>
      <w:szCs w:val="22"/>
      <w:lang w:val="{lang_code}"/>
    </w:rPr>
  </w:style>
</w:styles>
"""

FONT_TABLE = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:fonts xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:font w:name="Times New Roman">
    <w:family w:val="roman"/>
    <w:pitch w:val="variable"/>
  </w:font>
  <w:font w:name="Arial">
    <w:family w:val="swiss"/>
    <w:pitch w:val="variable"/>
  </w:font>
  <w:font w:name="Courier New">
    <w:family w:val="modern"/>
    <w:pitch w:val="fixed"/>
  </w:font>
</w:fonts>
"""

SETTINGS_TEMPLATE = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  {default_tab_stop}
  <w:proofState w:spelling="clean" w:grammar="clean"/>
  <w:themeFontLang w:val="{lang_code}" w:eastAsia="{lang_code}" w:bidi="{lang_code}"/>
</w:settings>
"""


CURRENT_LANG_CODE = "en-US"
SUP_START = "[[SUP]]"
SUP_END = "[[/SUP]]"
UNDERLINE_START = "[[UNDERLINE]]"
UNDERLINE_END = "[[/UNDERLINE]]"
ITALIC_START = "[[ITALIC]]"
ITALIC_END = "[[/ITALIC]]"


def own_styles(lang_code: str) -> str:
    return OWN_STYLES_TEMPLATE.format(
        lang_code=lang_code,
        own_hanging_twips=OWN_HANGING_TWIPS,
        own_short_hanging_twips=OWN_SHORT_HANGING_TWIPS,
    )


def liu_styles(lang_code: str) -> str:
    return LIU_STYLES_TEMPLATE.format(lang_code=lang_code)


def vr_styles(lang_code: str) -> str:
    return VR_STYLES_TEMPLATE.format(lang_code=lang_code)


def settings_xml(lang_code: str, *, default_tab_stop: int | None = None) -> str:
    default_tab = f'<w:defaultTabStop w:val="{default_tab_stop}"/>' if default_tab_stop is not None else ""
    return SETTINGS_TEMPLATE.format(lang_code=lang_code, default_tab_stop=default_tab)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export CV to a Word document.")
    parser.add_argument("--input-json", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


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


def append_segmented_runs(
    runs: list[str],
    text: str,
    *,
    bold: bool = False,
    italic: bool = False,
    underline: bool = False,
    font: str | None = None,
    size: int | None = None,
    superscript: bool = False,
) -> None:
    remainder = text
    current_superscript = superscript
    current_underline = underline
    current_italic = italic
    while remainder:
        start_index = remainder.find(SUP_START)
        end_index = remainder.find(SUP_END)
        underline_start_index = remainder.find(UNDERLINE_START)
        underline_end_index = remainder.find(UNDERLINE_END)
        italic_start_index = remainder.find(ITALIC_START)
        italic_end_index = remainder.find(ITALIC_END)
        marker_positions = [
            index
            for index in [
                start_index,
                end_index,
                underline_start_index,
                underline_end_index,
                italic_start_index,
                italic_end_index,
            ]
            if index != -1
        ]
        if not marker_positions:
            runs.append(
                single_run(
                    remainder,
                    bold=bold,
                    italic=current_italic,
                    underline=current_underline,
                    font=font,
                    size=size,
                    superscript=current_superscript,
                )
            )
            return
        next_index = min(marker_positions)
        if start_index != -1 and start_index == next_index:
            leading = remainder[:start_index]
            if leading:
                runs.append(single_run(leading, bold=bold, italic=current_italic, underline=current_underline, font=font, size=size, superscript=current_superscript))
            remainder = remainder[start_index + len(SUP_START):]
            current_superscript = True
            continue
        if end_index != -1 and end_index == next_index:
            leading = remainder[:end_index]
            if leading:
                runs.append(single_run(leading, bold=bold, italic=current_italic, underline=current_underline, font=font, size=size, superscript=current_superscript))
            remainder = remainder[end_index + len(SUP_END):]
            current_superscript = superscript
            continue
        if underline_start_index != -1 and underline_start_index == next_index:
            leading = remainder[:underline_start_index]
            if leading:
                runs.append(single_run(leading, bold=bold, italic=current_italic, underline=current_underline, font=font, size=size, superscript=current_superscript))
            remainder = remainder[underline_start_index + len(UNDERLINE_START):]
            current_underline = True
            continue
        if underline_end_index != -1 and underline_end_index == next_index:
            leading = remainder[:underline_end_index]
            if leading:
                runs.append(single_run(leading, bold=bold, italic=current_italic, underline=current_underline, font=font, size=size, superscript=current_superscript))
            remainder = remainder[underline_end_index + len(UNDERLINE_END):]
            current_underline = underline
            continue
        if italic_start_index != -1 and italic_start_index == next_index:
            leading = remainder[:italic_start_index]
            if leading:
                runs.append(single_run(leading, bold=bold, italic=current_italic, underline=current_underline, font=font, size=size, superscript=current_superscript))
            remainder = remainder[italic_start_index + len(ITALIC_START):]
            current_italic = True
            continue
        if italic_end_index != -1 and italic_end_index == next_index:
            leading = remainder[:italic_end_index]
            if leading:
                runs.append(single_run(leading, bold=bold, italic=current_italic, underline=current_underline, font=font, size=size, superscript=current_superscript))
            remainder = remainder[italic_end_index + len(ITALIC_END):]
            current_italic = italic


def xml_text_runs(text: str, *, bold: bool = False, italic: bool = False, font: str | None = None, size: int | None = None) -> str:
    parts = text.split("\t")
    runs: list[str] = []
    for index, part in enumerate(parts):
        if index > 0:
            runs.append("<w:r><w:tab/></w:r>")
        if part == "":
            continue
        append_segmented_runs(runs, part, bold=bold, italic=italic, font=font, size=size)
    if not runs:
        runs.append("<w:r><w:t xml:space=\"preserve\"></w:t></w:r>")
    return "".join(runs)


def single_run(text: str, *, bold: bool = False, italic: bool = False, underline: bool = False, font: str | None = None, size: int | None = None, superscript: bool = False) -> str:
    props = ""
    if bold:
        props += "<w:b/>"
    if italic:
        props += "<w:i/>"
    if underline:
        props += '<w:u w:val="single"/>'
    if superscript:
        props += '<w:vertAlign w:val="superscript"/>'
    if font:
        font_attr = quoteattr(font)
        props += f"<w:rFonts w:ascii={font_attr} w:hAnsi={font_attr} w:cs={font_attr}/>"
    if size is not None:
        props += f'<w:sz w:val="{size}"/><w:szCs w:val="{size}"/>'
    if CURRENT_LANG_CODE:
        props += f'<w:lang w:val="{CURRENT_LANG_CODE}"/>'
    rpr = f"<w:rPr>{props}</w:rPr>" if props else ""
    return f'<w:r>{rpr}<w:t xml:space="preserve">{escape(sanitize_xml_text(text))}</w:t></w:r>'


def highlighted_runs(text: str, phrase: str, *, font: str | None = None, size: int | None = None, italic: bool = False) -> str:
    phrases = name_highlight_phrases(phrase)
    if not phrases:
        return xml_text_runs(text, font=font, size=size, italic=italic)
    parts = text.split("\t")
    runs: list[str] = []
    for index, part in enumerate(parts):
        if index > 0:
            runs.append("<w:r><w:tab/></w:r>")
        if not part:
            continue
        cursor = 0
        lower_part = part.lower()
        while True:
            hit: int | None = None
            matched_phrase: str | None = None
            for candidate in phrases:
                candidate_lower = candidate.lower()
                candidate_hit = lower_part.find(candidate_lower, cursor)
                if candidate_hit == -1:
                    continue
                if hit is None or candidate_hit < hit or (candidate_hit == hit and matched_phrase is not None and len(candidate) > len(matched_phrase)):
                    hit = candidate_hit
                    matched_phrase = candidate
            if hit is None or matched_phrase is None:
                tail = part[cursor:]
                if tail:
                    append_segmented_runs(runs, tail, font=font, size=size, italic=italic)
                break
            leading = part[cursor:hit]
            if leading:
                append_segmented_runs(runs, leading, font=font, size=size, italic=italic)
            matched = part[hit:hit + len(matched_phrase)]
            append_segmented_runs(runs, matched, bold=True, font=font, size=size, italic=italic)
            cursor = hit + len(matched_phrase)
    if not runs:
        return "<w:r><w:t xml:space=\"preserve\"></w:t></w:r>"
    return "".join(runs)


def publication_data_runs(text: str, *, font: str | None = None, size: int | None = None, highlight_name: str = "") -> str:
    stripped = text.strip()
    if not stripped:
        return ""
    journal = stripped
    separator = ""
    remainder = ""
    if ". " in stripped:
        journal, remainder = stripped.split(". ", 1)
        separator = ". "
    elif "." in stripped:
        journal, remainder = stripped.split(".", 1)
        separator = "."
    runs = highlighted_runs(journal, highlight_name, font=font, size=size, italic=True)
    if separator:
        runs += single_run(separator, font=font, size=size)
    if remainder:
        runs += highlighted_runs(remainder, highlight_name, font=font, size=size)
    return runs


def conference_runs(text: str, *, font: str | None = None, size: int | None = None, highlight_name: str = "") -> str:
    marker_pairs = [
        ("[[PUBDATA]]", "[[/PUBDATA]]"),
        ("[PUBDATA]", "[/PUBDATA]"),
    ]
    for start_marker, end_marker in marker_pairs:
        if start_marker not in text or end_marker not in text:
            continue
        prefix, rest = text.split(start_marker, 1)
        publication_data, suffix = rest.split(end_marker, 1)
        runs = highlighted_runs(prefix, highlight_name, font=font, size=size)
        runs += publication_data_runs(publication_data, font=font, size=size, highlight_name=highlight_name)
        runs += highlighted_runs(suffix, highlight_name, font=font, size=size)
        return runs
    sanitized = text
    for start_marker, end_marker in marker_pairs:
        sanitized = sanitized.replace(start_marker, "").replace(end_marker, "")
    return highlighted_runs(sanitized, highlight_name, font=font, size=size)


def rich_text_runs(paragraph_payload: dict, *, font: str | None = None, size: int | None = None) -> str:
    runs_payload = paragraph_payload.get("runs", [])
    runs: list[str] = []
    for run_payload in runs_payload:
        text = run_payload.get("text", "")
        if not text:
            continue
        append_segmented_runs(
            runs,
            text,
            bold=bool(run_payload.get("bold", False)),
            italic=bool(run_payload.get("italic", False)),
            underline=bool(run_payload.get("underline", False)),
            font=font,
            size=size,
        )
    if not runs:
        runs.append("<w:r><w:t xml:space=\"preserve\"></w:t></w:r>")
    return "".join(runs)


def paragraph(
    text: str = "",
    *,
    style: str | None = None,
    bold: bool = False,
    italic: bool = False,
    font: str | None = None,
    size: int | None = None,
    spacing_before: int | None = None,
    spacing_after: int | None = None,
    left_indent: int | None = None,
    hanging_indent: int | None = None,
    tab_stop: int | None = None,
) -> str:
    ppr_bits: list[str] = []
    if style:
        ppr_bits.append(f'<w:pStyle w:val="{style}"/>')
    before = "0" if spacing_before is None else str(spacing_before)
    after = "0" if spacing_after is None else str(spacing_after)
    ppr_bits.append(f'<w:spacing w:before="{before}" w:after="{after}" w:line="240" w:lineRule="auto"/>')
    if left_indent is not None and hanging_indent is None:
        ppr_bits.append(f'<w:ind w:left="{left_indent}"/>')
    if tab_stop is not None:
        ppr_bits.append(f'<w:tabs><w:tab w:val="left" w:pos="{tab_stop}"/></w:tabs>')
    if hanging_indent is not None:
        left = hanging_indent + (left_indent or 0)
        ppr_bits.append(f'<w:ind w:left="{left}" w:hanging="{hanging_indent}"/>')
    ppr = f"<w:pPr>{''.join(ppr_bits)}</w:pPr>" if ppr_bits else ""
    return f"<w:p>{ppr}{xml_text_runs(text, bold=bold, italic=italic, font=font, size=size)}</w:p>"


def paragraph_with_runs(
    runs: str,
    *,
    style: str | None = None,
    spacing_before: int | None = None,
    spacing_after: int | None = None,
    left_indent: int | None = None,
    hanging_indent: int | None = None,
    tab_stop: int | None = None,
) -> str:
    ppr_bits: list[str] = []
    if style:
        ppr_bits.append(f'<w:pStyle w:val="{style}"/>')
    before = "0" if spacing_before is None else str(spacing_before)
    after = "0" if spacing_after is None else str(spacing_after)
    ppr_bits.append(f'<w:spacing w:before="{before}" w:after="{after}" w:line="240" w:lineRule="auto"/>')
    if left_indent is not None and hanging_indent is None:
        ppr_bits.append(f'<w:ind w:left="{left_indent}"/>')
    if tab_stop is not None:
        ppr_bits.append(f'<w:tabs><w:tab w:val="left" w:pos="{tab_stop}"/></w:tabs>')
    if hanging_indent is not None:
        left = hanging_indent + (left_indent or 0)
        ppr_bits.append(f'<w:ind w:left="{left}" w:hanging="{hanging_indent}"/>')
    ppr = f"<w:pPr>{''.join(ppr_bits)}</w:pPr>" if ppr_bits else ""
    return f"<w:p>{ppr}{runs}</w:p>"


def table_cell(text: str, *, bold: bool = False, font: str = "Times New Roman", size: int = 24) -> str:
    # Newlines inside a cell become separate paragraphs (multi-line cells).
    lines = str(text).split("\n")
    return (
        '<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr>'
        + "".join(paragraph(line, bold=bold, font=font, size=size) for line in lines)
        + "</w:tc>"
    )


def table_row(cells: list[str], *, bold: bool = False, font: str = "Times New Roman", size: int = 24) -> str:
    return "<w:tr>" + "".join(table_cell(str(cell), bold=bold, font=font, size=size) for cell in cells) + "</w:tr>"


def table_xml(headers: list[str], rows: list[list[str]], *, font: str = "Times New Roman", size: int = 24) -> str:
    if not rows:
        return ""
    parts = [
        "<w:tbl>",
        '<w:tblPr><w:tblW w:w="0" w:type="auto"/>'
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:space="0" w:color="D9D9D9"/>'
        '<w:left w:val="single" w:sz="4" w:space="0" w:color="D9D9D9"/>'
        '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="D9D9D9"/>'
        '<w:right w:val="single" w:sz="4" w:space="0" w:color="D9D9D9"/>'
        '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="D9D9D9"/>'
        '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="D9D9D9"/>'
        "</w:tblBorders></w:tblPr>",
    ]
    if headers:
        parts.append(table_row(headers, bold=True, font=font, size=size))
    for row in rows:
        parts.append(table_row(row, font=font, size=size))
    parts.append("</w:tbl>")
    return "".join(parts)


def blank_paragraph() -> str:
    return paragraph("")


def page_break_paragraph() -> str:
    return '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'


# Content width for A4 (11906 twips) minus the 1417-twip side margins.
OWN_CONTENT_WIDTH_TWIPS = 9072


def own_title_block(title: str, subtitle: str, trailing_text: str = "") -> list[str]:
    if trailing_text:
        runs = (
            xml_text_runs(title, font="Arial", size=36)
            + "<w:r><w:tab/></w:r>"
            + xml_text_runs(trailing_text, font="Times New Roman", size=24)
        )
        parts = [
            '<w:p><w:pPr><w:pStyle w:val="TITEL"/>'
            f'<w:tabs><w:tab w:val="right" w:pos="{OWN_CONTENT_WIDTH_TWIPS}"/></w:tabs>'
            '<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>'
            f"</w:pPr>{runs}</w:p>"
        ]
    else:
        parts = [paragraph(title, style="TITEL", font="Arial", size=36)]
    if subtitle:
        parts.append(blank_paragraph())
        parts.append(paragraph(subtitle, font="Arial", size=28))
        parts.append(blank_paragraph())
    return parts


def own_section(title: str) -> str:
    return paragraph(title, style="Rubrik1", bold=True, font="Times New Roman", size=24)


def own_hanging_item(text: str, *, highlight_name: str = "") -> str:
    return paragraph_with_runs(
        highlighted_runs(text, highlight_name, font="Times New Roman", size=24),
        style="Hngande",
        hanging_indent=OWN_HANGING_TWIPS,
        tab_stop=OWN_HANGING_TWIPS,
    )


def own_hanging_item_1cm(text: str, *, highlight_name: str = "") -> str:
    return paragraph_with_runs(
        highlighted_runs(text, highlight_name, font="Times New Roman", size=24),
        style="Hngandekort",
        hanging_indent=OWN_SHORT_HANGING_TWIPS,
        tab_stop=OWN_SHORT_HANGING_TWIPS,
    )


def liu_section(title: str) -> str:
    return paragraph(title, style="LiuSection", bold=True, font="Times New Roman", size=24)


def liu_subsection(title: str) -> str:
    return paragraph(title, style="LiuSubsection", bold=True, font="Courier New", size=24)


def liu_instruction(text: str) -> str:
    return paragraph(text, style="LiuSubsection", bold=True, font="Courier New", size=24)


def clean_liu_content_text(text: str) -> str:
    cleaned = text
    for marker in ("[[PUBDATA]]", "[[/PUBDATA]]", "[PUBDATA]", "[/PUBDATA]"):
        cleaned = cleaned.replace(marker, "")
    return cleaned.replace("\t", " ").strip()


def liu_content_paragraph(text: str) -> str:
    return paragraph_with_runs(
        highlighted_runs(clean_liu_content_text(text), "", font="Times New Roman", size=24, italic=True)
    )


TERMINAL_PUNCTUATION = (".", "?", "!")
TRAILING_CLOSERS = "\"')]}"


def has_terminal_punctuation(text: str) -> bool:
    stripped = text.strip().rstrip(TRAILING_CLOSERS)
    return stripped.endswith(TERMINAL_PUNCTUATION)


def citation_separator_after(text: str) -> str:
    return " " if has_terminal_punctuation(text) else ". "


def joined_citation_segments(segments: list[str]) -> str:
    visible = [segment.strip() for segment in segments if segment and segment.strip()]
    if not visible:
        return ""
    text = visible[0]
    previous = visible[0]
    for segment in visible[1:]:
        text += citation_separator_after(previous)
        text += segment
        previous = segment
    if not has_terminal_punctuation(previous):
        text += "."
    return text


def liu_ama_paragraph(item: dict) -> str:
    authors = clean_liu_content_text(item.get("authors", ""))
    title = clean_liu_content_text(item.get("title", ""))
    journal = clean_liu_content_text(item.get("journal", ""))
    tail = clean_liu_content_text(item.get("tail", ""))
    note = clean_liu_content_text(item.get("note", ""))
    text = joined_citation_segments([authors, title, journal, tail, note])
    return liu_content_paragraph(text)


def ama_paragraph(item: dict, *, font: str, size: int, highlight_name: str, style: str = "Hngandekort") -> str:
    runs = ""
    last_segment = ""

    def append_separator_if_needed() -> None:
        nonlocal runs
        if last_segment:
            runs += single_run(citation_separator_after(last_segment), font=font, size=size)

    authors = item.get("authors", "")
    if authors:
        runs += highlighted_runs(authors, highlight_name, font=font, size=size)
        last_segment = authors
    title = item.get("title", "")
    if title:
        append_separator_if_needed()
        runs += xml_text_runs(title, font=font, size=size)
        last_segment = title
    journal = item.get("journal", "")
    if journal:
        append_separator_if_needed()
        runs += xml_text_runs(journal, font=font, size=size, italic=True)
        last_segment = journal
    tail = item.get("tail", "")
    if tail:
        append_separator_if_needed()
        runs += xml_text_runs(tail, font=font, size=size)
        last_segment = tail
    note = item.get("note", "")
    if note:
        runs += single_run(" ", font=font, size=size)
        runs += xml_text_runs(note, font=font, size=size)
    hanging_indent = OWN_SHORT_HANGING_TWIPS if style == "Hngandekort" else OWN_HANGING_TWIPS
    return paragraph_with_runs(runs, style=style, hanging_indent=hanging_indent, tab_stop=hanging_indent)


def own_layout_kind(section_title: str, explicit_layout_kind: str | None = None) -> str:
    if explicit_layout_kind:
        return explicit_layout_kind
    normalized = " ".join(section_title.strip().lower().split())
    if normalized in {"grants", "publication list", "conference contributions", "reviews", "media"}:
        return {
            "grants": "grants",
            "publication list": "publicationList",
            "conference contributions": "conferenceContributions",
            "reviews": "reviews",
            "media": "media",
        }[normalized]
    return "default"


def document_xml(
    body: str,
    *,
    include_header: bool = True,
    include_footer: bool = False,
    top_margin: int = 1417,
    right_margin: int = 1417,
    bottom_margin: int = 1135,
    left_margin: int = 1417,
) -> str:
    references = ""
    if include_header:
        references += '<w:headerReference w:type="default" r:id="rIdHeader1"/>'
    if include_footer:
        references += '<w:footerReference w:type="default" r:id="rIdFooter1"/>'
    sect_pr = (
        '<w:sectPr>'
        f'{references}'
        '<w:pgSz w:w="11906" w:h="16838"/>'
        f'<w:pgMar w:top="{top_margin}" w:right="{right_margin}" w:bottom="{bottom_margin}" w:left="{left_margin}" w:header="708" w:footer="708" w:gutter="0"/>'
        '<w:cols w:space="708"/>'
        '<w:docGrid w:linePitch="360"/>'
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
  <w:body>{body}{sect_pr}</w:body>
</w:document>
"""


def header_xml(text: str, *, font: str = "Times New Roman", size: int = 20) -> str:
    runs = xml_text_runs(text, font=font, size=size)
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
  <w:p>
    <w:pPr>
      <w:jc w:val="right"/>
    </w:pPr>
    {runs}
  </w:p>
</w:hdr>
"""


def footer_xml(text: str = "", *, include_page_number: bool = False, font: str = "Times New Roman", size: int = 20) -> str:
    runs = []
    if text.strip():
        runs.append(xml_text_runs(text, font=font, size=size))
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
    if runs:
        body = f'<w:p><w:pPr><w:jc w:val="center"/><w:tabs><w:tab w:val="center" w:pos="4680"/></w:tabs></w:pPr>{"".join(runs)}</w:p>'
    else:
        body = '<w:p/>'
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


def statistic_bars_table(bars: list[dict]) -> str:
    """One fixed-layout borderless table per bar group: label, a nested
    shaded table whose width is the bar value, and the value text."""
    label_w, track_w, value_w = 2800, 4200, 2072
    rows: list[str] = []
    for bar in bars:
        try:
            fraction = max(0.0, min(1.0, float(bar.get("fraction", 0))))
        except (TypeError, ValueError):
            fraction = 0.0
        color = (str(bar.get("colorHex", "")) or "2563EB")[:6]
        bar_w = int(round(fraction * (track_w - 100)))
        if fraction > 0:
            bar_w = max(bar_w, 80)
        nested = ""
        if bar_w > 0:
            nested = (
                "<w:tbl><w:tblPr>"
                f'<w:tblW w:w="{bar_w}" w:type="dxa"/>'
                '<w:tblLayout w:type="fixed"/>'
                '<w:tblCellMar><w:left w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar>'
                "</w:tblPr>"
                f'<w:tblGrid><w:gridCol w:w="{bar_w}"/></w:tblGrid>'
                '<w:tr><w:trPr><w:trHeight w:val="140" w:hRule="exact"/></w:trPr>'
                f'<w:tc><w:tcPr><w:tcW w:w="{bar_w}" w:type="dxa"/>'
                f'<w:shd w:val="clear" w:color="auto" w:fill="{color}"/></w:tcPr>'
                '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="140" w:lineRule="exact"/></w:pPr></w:p>'
                "</w:tc></w:tr></w:tbl>"
            )
        trailing_paragraph = '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="100" w:lineRule="exact"/></w:pPr></w:p>'
        label_cell = (
            f'<w:tc><w:tcPr><w:tcW w:w="{label_w}" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>'
            + paragraph(str(bar.get("label", "")), font="Times New Roman", size=22)
            + "</w:tc>"
        )
        track_cell = (
            f'<w:tc><w:tcPr><w:tcW w:w="{track_w}" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>'
            + nested
            + trailing_paragraph
            + "</w:tc>"
        )
        value_cell = (
            f'<w:tc><w:tcPr><w:tcW w:w="{value_w}" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>'
            + paragraph(str(bar.get("valueText", "")), font="Times New Roman", size=22)
            + "</w:tc>"
        )
        rows.append("<w:tr>" + label_cell + track_cell + value_cell + "</w:tr>")
    if not rows:
        return ""
    return (
        "<w:tbl><w:tblPr>"
        f'<w:tblW w:w="{label_w + track_w + value_w}" w:type="dxa"/>'
        '<w:tblLayout w:type="fixed"/>'
        "</w:tblPr>"
        f'<w:tblGrid><w:gridCol w:w="{label_w}"/><w:gridCol w:w="{track_w}"/><w:gridCol w:w="{value_w}"/></w:tblGrid>'
        + "".join(rows)
        + "</w:tbl>"
    )


def build_own_document(payload: dict, *, include_header: bool, include_footer: bool) -> str:
    parts: list[str] = []
    highlight_name = payload.get("highlightName", "")
    parts.extend(
        own_title_block(
            payload.get("title", "CURRICULUM VITAE"),
            payload.get("subtitle", ""),
            payload.get("titleTrailingText", ""),
        )
    )

    for paragraph_payload in payload.get("summaryRichParagraphs", []):
        parts.append(
            paragraph_with_runs(
                rich_text_runs(paragraph_payload, font="Times New Roman", size=24)
            )
        )

    for line in payload.get("summaryLines", []):
        if line:
            parts.append(
                paragraph(
                    line,
                    font="Times New Roman",
                    size=24,
                )
            )

    for section in payload.get("sections", []):
        raw_layout_kind = section.get("layoutKind", "")
        layout_kind = own_layout_kind(section.get("title", ""), section.get("layoutKind"))
        has_content = (
            section.get("rows")
            or section.get("items")
            or section.get("paragraphs")
            or section.get("richParagraphs")
            or section.get("subsections")
        )
        if not has_content:
            continue
        if raw_layout_kind in ("pageBreakBefore", "protocol"):
            parts.append(page_break_paragraph())
        parts.append(blank_paragraph())
        parts.append(own_section(section.get("title", "")))
        for paragraph_payload in section.get("richParagraphs", []):
            parts.append(
                paragraph_with_runs(
                    rich_text_runs(paragraph_payload, font="Times New Roman", size=24)
                )
            )
        for paragraph_text in section.get("paragraphs", []):
            if paragraph_text:
                parts.append(
                    paragraph(
                        paragraph_text,
                        font="Times New Roman",
                        size=24,
                        hanging_indent=OWN_HANGING_TWIPS,
                        tab_stop=OWN_HANGING_TWIPS,
                    )
                )
        for item in section.get("items", []):
            if item:
                if layout_kind == "conferenceContributions":
                    parts.append(
                        paragraph_with_runs(
                            conference_runs(item, highlight_name=highlight_name, font="Times New Roman", size=24),
                            style="Hngandekort",
                            hanging_indent=OWN_SHORT_HANGING_TWIPS,
                            tab_stop=OWN_SHORT_HANGING_TWIPS,
                        )
                    )
                elif layout_kind in {"grants", "reviews", "media", "publicationList"}:
                    parts.append(own_hanging_item_1cm(item, highlight_name=highlight_name))
                else:
                    parts.append(own_hanging_item(item, highlight_name=highlight_name))
        parts.append(
            table_xml(
                section.get("headers", []),
                section.get("rows", []),
                font="Times New Roman",
                size=24,
            )
        )
        is_protocol_section = raw_layout_kind == "protocol"
        for subsection in section.get("subsections", []):
            title = subsection.get("title", "").strip()
            subsection_layout_kind = own_layout_kind(title, layout_kind if layout_kind != "default" else None)
            if title:
                if is_protocol_section:
                    # Protocol day headings: 14 pt bold with tight spacing.
                    parts.append(
                        paragraph(
                            title,
                            bold=True,
                            font="Times New Roman",
                            size=28,
                            spacing_before=180,
                            spacing_after=60,
                        )
                    )
                else:
                    parts.append(blank_paragraph())
                    parts.append(paragraph(title, bold=True, font="Times New Roman", size=24))
            protocol_spacing_after = 60 if is_protocol_section else None
            for paragraph_text in subsection.get("paragraphs", []):
                if paragraph_text:
                    if is_protocol_section:
                        bullet_level = protocol_bullet_level(paragraph_text)
                        parts.append(
                            paragraph(
                                paragraph_text,
                                font="Times New Roman",
                                size=24,
                                spacing_after=protocol_spacing_after,
                                left_indent=(bullet_level - 1) * PROTOCOL_BULLET_LEVEL_TWIPS if bullet_level else None,
                                hanging_indent=PROTOCOL_BULLET_TWIPS if bullet_level else None,
                            )
                        )
                    else:
                        parts.append(
                            paragraph(
                                paragraph_text,
                                font="Times New Roman",
                                size=24,
                                hanging_indent=OWN_HANGING_TWIPS,
                                tab_stop=OWN_HANGING_TWIPS,
                            )
                        )
            for paragraph_payload in subsection.get("richParagraphs", []):
                plain_text = "".join(run.get("text", "") for run in paragraph_payload.get("runs", []))
                if is_protocol_section:
                    # Real bullet behaviour: wrapped lines start under the
                    # first letter after the bullet, not under the bullet;
                    # nested levels shift left by a fixed step per level.
                    bullet_level = protocol_bullet_level(plain_text)
                    parts.append(
                        paragraph_with_runs(
                            rich_text_runs(paragraph_payload, font="Times New Roman", size=24),
                            spacing_after=protocol_spacing_after,
                            left_indent=(bullet_level - 1) * PROTOCOL_BULLET_LEVEL_TWIPS if bullet_level else None,
                            hanging_indent=PROTOCOL_BULLET_TWIPS if bullet_level else None,
                        )
                    )
                else:
                    parts.append(
                        paragraph_with_runs(
                            rich_text_runs(paragraph_payload, font="Times New Roman", size=24),
                            hanging_indent=OWN_HANGING_TWIPS,
                            tab_stop=OWN_HANGING_TWIPS,
                        )
                    )
            bars_xml = statistic_bars_table(subsection.get("bars", []))
            if bars_xml:
                parts.append(bars_xml)
            for ama_item in subsection.get("amaItems", []):
                ama_style = "Hngandekort" if subsection_layout_kind == "publicationList" else "Hngande"
                parts.append(ama_paragraph(ama_item, font="Times New Roman", size=24, highlight_name=highlight_name, style=ama_style))
            for item in subsection.get("items", []):
                if item:
                    if subsection_layout_kind == "conferenceContributions":
                        parts.append(
                            paragraph_with_runs(
                                conference_runs(item, highlight_name=highlight_name, font="Times New Roman", size=24),
                                style="Hngandekort",
                                hanging_indent=OWN_SHORT_HANGING_TWIPS,
                                tab_stop=OWN_SHORT_HANGING_TWIPS,
                            )
                        )
                    elif subsection_layout_kind in {"grants", "reviews", "media", "publicationList"}:
                        parts.append(own_hanging_item_1cm(item, highlight_name=highlight_name))
                    else:
                        parts.append(own_hanging_item(item, highlight_name=highlight_name))

    return document_xml(
        "".join(parts),
        include_header=include_header,
        include_footer=include_footer,
    )


def build_liu_document(payload: dict, *, include_header: bool, include_footer: bool) -> str:
    parts: list[str] = []

    for section_index, section in enumerate(payload.get("sections", [])):
        if section_index > 0:
            parts.append(blank_paragraph())
        parts.append(liu_section(section.get("title", "")))
        for paragraph_payload in section.get("richParagraphs", []):
            parts.append(
                paragraph_with_runs(
                    rich_text_runs(paragraph_payload, font="Times New Roman", size=24)
                )
            )
        for paragraph_text in section.get("paragraphs", []):
            if paragraph_text:
                parts.append(liu_instruction(paragraph_text))
        for item in section.get("items", []):
            if item:
                parts.append(liu_content_paragraph(item))
        parts.append(
            table_xml(
                section.get("headers", []),
                section.get("rows", []),
                font="Times New Roman",
                size=24,
            )
        )
        for subsection in section.get("subsections", []):
            title = subsection.get("title", "").strip()
            if title:
                parts.append(blank_paragraph())
                parts.append(liu_subsection(title))
            for paragraph_text in subsection.get("paragraphs", []):
                if paragraph_text:
                    parts.append(liu_instruction(paragraph_text))
            for ama_item in subsection.get("amaItems", []):
                parts.append(liu_ama_paragraph(ama_item))
            for item in subsection.get("items", []):
                if item:
                    parts.append(liu_content_paragraph(item))

    return document_xml(
        "".join(parts),
        include_header=include_header,
        include_footer=include_footer,
    )


def build_vr_document(payload: dict, *, include_header: bool, include_footer: bool) -> str:
    parts: list[str] = []
    highlight_name = payload.get("highlightName", "")
    title = payload.get("title", "").strip()
    subtitle = payload.get("subtitle", "").strip()

    if title:
        parts.append(paragraph(title, style="VrHeading", bold=True, font="Arial", size=22, spacing_after=80))
    if subtitle:
        parts.append(paragraph(subtitle, font="Arial", size=22, spacing_after=120))

    for section in payload.get("sections", []):
        has_content = (
            section.get("subsections")
            or section.get("items")
            or section.get("paragraphs")
            or section.get("richParagraphs")
            or section.get("rows")
        )
        if not has_content:
            continue
        if parts:
            parts.append(blank_paragraph())
        parts.append(paragraph(section.get("title", ""), style="VrHeading", bold=True, font="Arial", size=22, spacing_after=40))

        for paragraph_text in section.get("paragraphs", []):
            if paragraph_text:
                parts.append(paragraph_with_runs(highlighted_runs(paragraph_text, highlight_name, font="Arial", size=22)))

        for item in section.get("items", []):
            if item:
                parts.append(
                    paragraph_with_runs(
                        highlighted_runs(item, highlight_name, font="Arial", size=22),
                        hanging_indent=OWN_SHORT_HANGING_TWIPS,
                        tab_stop=OWN_SHORT_HANGING_TWIPS,
                    )
                )

        parts.append(
            table_xml(
                section.get("headers", []),
                section.get("rows", []),
                font="Arial",
                size=22,
            )
        )

        for subsection in section.get("subsections", []):
            title = subsection.get("title", "").strip()
            has_subsection_content = subsection.get("paragraphs") or subsection.get("items") or subsection.get("vrItems")
            if not has_subsection_content:
                continue
            if title:
                parts.append(paragraph(title, style="VrSubheading", bold=True, font="Arial", size=22, spacing_before=60, spacing_after=20))
            for paragraph_text in subsection.get("paragraphs", []):
                if paragraph_text:
                    parts.append(paragraph_with_runs(highlighted_runs(paragraph_text, highlight_name, font="Arial", size=22)))
            for vr_item in subsection.get("vrItems", []):
                citation = vr_item.get("citation", "")
                note = vr_item.get("note", "").strip()
                if citation:
                    parts.append(
                        paragraph_with_runs(
                            highlighted_runs(citation, highlight_name, font="Arial", size=22),
                            hanging_indent=OWN_SHORT_HANGING_TWIPS,
                            tab_stop=OWN_SHORT_HANGING_TWIPS,
                        )
                    )
                if note:
                    parts.append(
                        paragraph_with_runs(
                            highlighted_runs(note, highlight_name, font="Arial", size=22),
                            left_indent=OWN_SHORT_HANGING_TWIPS,
                            spacing_after=20,
                        )
                    )
            for item in subsection.get("items", []):
                if item:
                    parts.append(
                        paragraph_with_runs(
                            highlighted_runs(item, highlight_name, font="Arial", size=22),
                            hanging_indent=OWN_SHORT_HANGING_TWIPS,
                            tab_stop=OWN_SHORT_HANGING_TWIPS,
                        )
                    )

    return document_xml(
        "".join(parts),
        include_header=include_header,
        include_footer=include_footer,
        top_margin=1417,
        right_margin=1417,
        bottom_margin=1417,
        left_margin=1417,
    )


def build_document(payload: dict) -> tuple[str, str, str, str, str]:
    global CURRENT_LANG_CODE
    style = payload.get("style", "own")
    export_language = payload.get("exportLanguage", "english")
    header_text = payload.get("headerText", "")
    footer_text = payload.get("footerText", "")
    include_page_numbers = bool(payload.get("includePageNumbers", False))
    include_header = bool(str(header_text).strip())
    include_footer = bool(str(footer_text).strip()) or include_page_numbers
    lang_code = "sv-SE" if export_language == "swedish" else "en-US"
    CURRENT_LANG_CODE = lang_code
    if style == "liu":
        return (
            build_liu_document(payload, include_header=False, include_footer=False),
            liu_styles(lang_code),
            settings_xml(lang_code, default_tab_stop=709),
            header_xml("", font="Times New Roman", size=20),
            footer_xml("", include_page_number=False, font="Times New Roman", size=20),
        )
    if style == "vetenskapsradet":
        return (
            build_vr_document(payload, include_header=include_header, include_footer=include_footer),
            vr_styles(lang_code),
            settings_xml(lang_code),
            header_xml(header_text, font="Arial", size=22),
            footer_xml(footer_text, include_page_number=include_page_numbers, font="Arial", size=20),
        )
    return (
        build_own_document(payload, include_header=include_header, include_footer=include_footer),
        own_styles(lang_code),
        settings_xml(lang_code),
        header_xml(header_text, font="Times New Roman", size=20),
        footer_xml(footer_text, include_page_number=include_page_numbers, font="Times New Roman", size=20),
    )


def main() -> None:
    args = parse_args()
    payload = json.loads(args.input_json.read_text(encoding="utf-8"))
    document, styles, settings, header, footer = build_document(payload)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", CONTENT_TYPES)
        archive.writestr("_rels/.rels", ROOT_RELS)
        archive.writestr("word/document.xml", document)
        archive.writestr("word/header1.xml", header)
        archive.writestr("word/footer1.xml", footer)
        archive.writestr("word/styles.xml", styles)
        archive.writestr("word/fontTable.xml", FONT_TABLE)
        archive.writestr("word/settings.xml", settings)
        archive.writestr("word/_rels/document.xml.rels", DOCUMENT_RELS)
    print(f"Wrote CV Word document to {args.output}")


if __name__ == "__main__":
    main()
