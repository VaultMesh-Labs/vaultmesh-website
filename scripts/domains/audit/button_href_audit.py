#!/usr/bin/env python3
"""Audit CTA/button/link wiring for static HTML surfaces.

Outputs JSON Lines with fields:
  page, label, href, status, source

Statuses:
  OK
  BAD_HREF              href empty/#/javascript
  SELF_LINK             href points to same page route
  BUTTON_NO_ACTION      button not nested in form and no onclick
  DEAD_TEXT             expected label appears in visible text but not linked/buttoned
  MISSING_LABEL         expected label not found in page text or controls
  MISROUTE_EXPECTED     expected label linked but href doesn't match expected_href
"""

from __future__ import annotations

import argparse
import json
import os
import re
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path
from typing import Any


def clean_text(s: str) -> str:
    return re.sub(r"\s+", " ", s or "").strip()


@dataclass
class AnchorItem:
    label: str
    href: str
    source_line: int


@dataclass
class ButtonItem:
    label: str
    form_action: str | None
    onclick: str | None
    source_line: int


class HtmlAuditParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.anchors: list[AnchorItem] = []
        self.buttons: list[ButtonItem] = []
        self.visible_text: list[str] = []

        self._in_script = False
        self._in_style = False

        self._anchor_attrs: dict[str, str] | None = None
        self._anchor_text: list[str] = []

        self._button_attrs: dict[str, str] | None = None
        self._button_text: list[str] = []

        self._form_stack: list[str | None] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_map = {k.lower(): (v or "") for k, v in attrs}
        t = tag.lower()
        if t == "script":
            self._in_script = True
            return
        if t == "style":
            self._in_style = True
            return
        if t == "form":
            self._form_stack.append(attrs_map.get("action") or None)
            return
        if t == "a":
            self._anchor_attrs = attrs_map
            self._anchor_text = []
            return
        if t == "button":
            self._button_attrs = attrs_map
            self._button_text = []
            return

    def handle_endtag(self, tag: str) -> None:
        t = tag.lower()
        if t == "script":
            self._in_script = False
            return
        if t == "style":
            self._in_style = False
            return
        if t == "form":
            if self._form_stack:
                self._form_stack.pop()
            return
        if t == "a" and self._anchor_attrs is not None:
            label = clean_text("".join(self._anchor_text))
            href = self._anchor_attrs.get("href", "")
            self.anchors.append(AnchorItem(label=label, href=href, source_line=self.getpos()[0]))
            self._anchor_attrs = None
            self._anchor_text = []
            return
        if t == "button" and self._button_attrs is not None:
            label = clean_text("".join(self._button_text))
            form_action = self._form_stack[-1] if self._form_stack else None
            onclick = self._button_attrs.get("onclick") or None
            self.buttons.append(
                ButtonItem(label=label, form_action=form_action, onclick=onclick, source_line=self.getpos()[0])
            )
            self._button_attrs = None
            self._button_text = []
            return

    def handle_data(self, data: str) -> None:
        if self._in_script or self._in_style:
            return
        d = clean_text(data)
        if not d:
            return
        self.visible_text.append(d)
        if self._anchor_attrs is not None:
            self._anchor_text.append(d)
        if self._button_attrs is not None:
            self._button_text.append(d)


def route_for_file(base: Path, f: Path) -> str:
    rel = f.relative_to(base).as_posix()
    if rel == "index.html":
        return "/"
    if rel.endswith("/index.html"):
        return "/" + rel[: -len("index.html")]
    if rel.endswith(".html"):
        return "/" + rel
    return "/" + rel


def normalize_href_to_route(href: str) -> str | None:
    if not href:
        return None
    if href.startswith("http://") or href.startswith("https://"):
        return None
    if href.startswith("mailto:") or href.startswith("tel:"):
        return None
    if href.startswith("javascript:"):
        return None
    h = href.split("#", 1)[0]
    if not h:
        return None
    if not h.startswith("/"):
        return None
    return h


def status_for_anchor(page_route: str, href: str) -> str:
    h = (href or "").strip()
    if h == "" or h == "#" or h.lower().startswith("javascript:"):
        return "BAD_HREF"
    route = normalize_href_to_route(h)
    if route is not None:
        normalized_page = page_route.rstrip("/") or "/"
        normalized_route = route.rstrip("/") or "/"
        if normalized_page == normalized_route:
            return "SELF_LINK"
    return "OK"


def load_expectations(path: str | None) -> list[dict[str, Any]]:
    if not path:
        return []
    p = Path(path)
    obj = json.loads(p.read_text(encoding="utf-8"))
    if isinstance(obj, dict) and "expectations" in obj:
        obj = obj["expectations"]
    if not isinstance(obj, list):
        raise ValueError("expectations file must be a list or {expectations:[...]}")
    out: list[dict[str, Any]] = []
    for item in obj:
        if not isinstance(item, dict):
            continue
        if "page" not in item or "label" not in item:
            continue
        out.append(item)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Audit button/link href contracts for static HTML")
    ap.add_argument("--root", default="dist", help="Root directory to scan (default: dist)")
    ap.add_argument("--expect", default=None, help="Optional expectations JSON file")
    ap.add_argument("--output", default="-", help="Output JSONL file (default: stdout)")
    ap.add_argument(
        "--fail-on",
        default="",
        help="Comma-separated statuses that should return non-zero if present (e.g. BAD_HREF,DEAD_TEXT,MISROUTE_EXPECTED)",
    )
    args = ap.parse_args()

    root = Path(args.root).resolve()
    if not root.exists():
        raise SystemExit(f"root_not_found: {root}")

    expectations = load_expectations(args.expect)
    out_lines: list[str] = []

    html_files = sorted(root.rglob("*.html"))
    for f in html_files:
        page = route_for_file(root, f)
        src = f.relative_to(root).as_posix()
        html = f.read_text(encoding="utf-8", errors="replace")

        parser = HtmlAuditParser()
        parser.feed(html)

        for a in parser.anchors:
            rec = {
                "page": page,
                "label": a.label,
                "href": a.href,
                "status": status_for_anchor(page, a.href),
                "source": src,
            }
            out_lines.append(json.dumps(rec, ensure_ascii=False))

        for b in parser.buttons:
            status = "OK"
            href = None
            if not b.form_action and not b.onclick:
                status = "BUTTON_NO_ACTION"
            rec = {
                "page": page,
                "label": b.label,
                "href": href,
                "status": status,
                "source": src,
            }
            out_lines.append(json.dumps(rec, ensure_ascii=False))

        visible = " ".join(parser.visible_text)
        for exp in expectations:
            if exp.get("page") != page:
                continue
            label = clean_text(str(exp.get("label", "")))
            if not label:
                continue
            expected_href = exp.get("expected_href")

            match_anchor = next((a for a in parser.anchors if a.label == label), None)
            match_button = next((b for b in parser.buttons if b.label == label), None)

            if match_anchor:
                status = "OK"
                if expected_href is not None and match_anchor.href != expected_href:
                    status = "MISROUTE_EXPECTED"
                rec = {
                    "page": page,
                    "label": label,
                    "href": match_anchor.href,
                    "status": status,
                    "source": src,
                    "expected_href": expected_href,
                }
            elif match_button:
                rec = {
                    "page": page,
                    "label": label,
                    "href": match_button.form_action,
                    "status": "OK" if match_button.form_action or match_button.onclick else "BUTTON_NO_ACTION",
                    "source": src,
                    "expected_href": expected_href,
                }
            else:
                if label in visible:
                    status = "DEAD_TEXT"
                else:
                    status = "MISSING_LABEL"
                rec = {
                    "page": page,
                    "label": label,
                    "href": None,
                    "status": status,
                    "source": src,
                    "expected_href": expected_href,
                }
            out_lines.append(json.dumps(rec, ensure_ascii=False))

    payload = "\n".join(out_lines) + ("\n" if out_lines else "")
    if args.output == "-":
        print(payload, end="")
    else:
        Path(args.output).write_text(payload, encoding="utf-8")

    fail_set = {x.strip() for x in args.fail_on.split(",") if x.strip()}
    if fail_set:
        for line in out_lines:
            rec = json.loads(line)
            if rec.get("status") in fail_set:
                return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
