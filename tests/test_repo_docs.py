#!/usr/bin/env python3
"""Public documentation / EN FR ZH branding regressions — offline only."""
from __future__ import annotations
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGS = ("README.md", "README.fr.md", "README.zh-CN.md")
logo = ROOT / "docs/assets/logo.svg"
assert logo.is_file()
assert ET.parse(logo).getroot().tag.endswith("svg")
docs = [*ROOT.glob("README*.md"), *ROOT.glob("docs/*.md"),
        *ROOT.glob("installer/*.md"), *ROOT.glob("files/*.md")]
not_found = []
for md in docs:
    contents = md.read_text(encoding="utf-8")
    for m in re.finditer(r"!?(?:\[[^\]\n]*\])\(([^)]+)\)|(?:href|src)=\"([^\"]+)\"", contents):
        link = (m.group(1) or m.group(2)).strip().split("#", 1)[0].split(" ?", 1)[0]
        if not link or link.startswith(("https://", "http://", "mailto:", "data:", "#", "javascript:")):
            continue
        link = link.replace("%20", " ")
        if not (md.parent / link).exists():
            not_found.append((str(md.relative_to(ROOT)), link))
assert not not_found, f"Broken local documentation links: {not_found[:20]}"
for lang in LANGS:
    doc = (ROOT / lang).read_text()
    for ref in LANGS:
        assert ref in doc or ref == lang, f"Missing language link {ref} in {lang}"
    assert "docs/assets/logo.svg" in doc, lang
    assert "installer/README.md" in doc, lang
    assert "40" in doc and "25" in doc, lang
    assert "S55 Lite" in doc, lang
for mandatory in ("installer/INSTALL.sh", "installer/README.md",
                  "scripts/build-s55-lineage18-kit.sh", "docs/CRDROID-LEGACY.md"):
    assert (ROOT / mandatory).is_file(), mandatory
print(f"REPO_DOCUMENTATION=PASS ({len(docs)} documents; EN, FR, ZH + SVG)")
