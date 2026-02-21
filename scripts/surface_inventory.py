#!/usr/bin/env python3

import json
import re
import sys
import urllib.request
from html import unescape
from urllib.parse import urljoin, urlparse


BASE = "https://vaultmesh.org"
START_PATHS = ["/", "/attest/"]
MAX_DEPTH = 2

DIGEST_RE = re.compile(r"^(sha256|blake3):[0-9a-f]{16,128}$", re.I)


def http_get(url: str, timeout: int = 20) -> tuple[int, str, str]:
    req = urllib.request.Request(url, headers={"User-Agent": "vaultmesh-surface-inventory/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status = getattr(resp, "status", 200)
            ctype = resp.headers.get("content-type", "")
            data = resp.read()
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError:
                text = data.decode("utf-8", errors="replace")
            return status, ctype, text
    except urllib.error.HTTPError as e:
        try:
            body = e.read().decode("utf-8", errors="replace")
        except Exception:
            body = ""
        return int(e.code), e.headers.get("content-type", ""), body


def extract_title(html: str) -> str:
    m = re.search(r"<title>(.*?)</title>", html, re.I | re.S)
    return unescape(m.group(1).strip()) if m else ""


def extract_meta_description(html: str) -> str:
    m = re.search(
        r"<meta\s+name=[\"\']description[\"\']\s+content=[\"\'](.*?)[\"\']\s*/?>",
        html,
        re.I | re.S,
    )
    if not m:
        m = re.search(
            r"<meta\s+content=[\"\'](.*?)[\"\']\s+name=[\"\']description[\"\']\s*/?>",
            html,
            re.I | re.S,
        )
    return unescape(m.group(1).strip()) if m else ""


def extract_body_class(html: str) -> str:
    m = re.search(r"<body\s+[^>]*class=[\"\']([^\"\']+)[\"\']", html, re.I)
    return m.group(1).strip() if m else ""


def extract_nav_links(html: str) -> tuple[list[dict], list[dict]]:
    header_links: list[dict] = []
    nav_m = re.search(r"<nav\s+class=[\"\']vm-nav[\"\'][^>]*>(.*?)</nav>", html, re.I | re.S)
    if nav_m:
        nav_html = nav_m.group(1)
        for am in re.finditer(
            r"<a\s+[^>]*href=[\"\']([^\"\']+)[\"\'][^>]*>(.*?)</a>", nav_html, re.I | re.S
        ):
            href = unescape(am.group(1).strip())
            label = re.sub(r"<[^>]+>", "", am.group(2))
            label = unescape(label).strip()
            header_links.append({"href": href, "label": label})

    footer_links: list[dict] = []
    foot_m = re.search(r"<footer\s+class=[\"\']vm-footer[\"\'][^>]*>(.*?)</footer>", html, re.I | re.S)
    if foot_m:
        foot_html = foot_m.group(1)
        for am in re.finditer(
            r"<a\s+[^>]*href=[\"\']([^\"\']+)[\"\'][^>]*>(.*?)</a>", foot_html, re.I | re.S
        ):
            href = unescape(am.group(1).strip())
            label = re.sub(r"<[^>]+>", "", am.group(2))
            label = unescape(label).strip()
            footer_links.append({"href": href, "label": label})

    return header_links, footer_links


def strip_tags(s: str) -> str:
    s = re.sub(r"<script\b[^<]*(?:(?!</script>)<[^<]*)*</script>", "", s, flags=re.I)
    s = re.sub(r"<style\b[^<]*(?:(?!</style>)<[^<]*)*</style>", "", s, flags=re.I)
    s = re.sub(r"<[^>]+>", "", s)
    return unescape(re.sub(r"\s+", " ", s)).strip()


def extract_sections(path: str, html: str) -> list[dict]:
    sections: list[dict] = []

    if path.rstrip("/") == "/attest":
        for h in re.findall(r"<h1[^>]*>(.*?)</h1>", html, flags=re.I | re.S):
            heading = strip_tags(h)
            if heading:
                sections.append({"heading": heading, "text_excerpt": "", "component_type": "console"})

        sub_m = re.search(r"<div\s+class=[\"\']sub[\"\']\s*>(.*?)</div>", html, flags=re.I | re.S)
        if sub_m:
            sections.append({"heading": "", "text_excerpt": strip_tags(sub_m.group(1)), "component_type": "console"})

        for lm in re.finditer(r"<div\s+class=[\"\']label[\"\']\s*>(.*?)</div>", html, flags=re.I | re.S):
            label = strip_tags(lm.group(1))
            if label:
                sections.append({"heading": label, "text_excerpt": "", "component_type": "grid"})

        foot = re.search(r"<div\s+class=[\"\']footer[\"\']\s*>(.*?)</div>", html, flags=re.I | re.S)
        if foot:
            sections.append({"heading": "", "text_excerpt": strip_tags(foot.group(1)), "component_type": "artifact"})

        return sections

    hero_h1 = re.search(
        r"<section\s+class=[\"\']hero[\"\'][^>]*>.*?<h1[^>]*>(.*?)</h1>", html, flags=re.I | re.S
    )
    if hero_h1:
        sections.append({"heading": strip_tags(hero_h1.group(1)), "text_excerpt": "", "component_type": "static"})

    sub = re.search(r"<p\s+class=[\"\']subhead[\"\'][^>]*>(.*?)</p>", html, flags=re.I | re.S)
    if sub:
        sections.append({"heading": "", "text_excerpt": strip_tags(sub.group(1)), "component_type": "static"})

    for cm in re.finditer(r"<section\s+class=[\"\']card[\"\'][^>]*>(.*?)</section>", html, flags=re.I | re.S):
        block = cm.group(1)
        h2 = re.search(r"<h2[^>]*>(.*?)</h2>", block, flags=re.I | re.S)
        heading = strip_tags(h2.group(1)) if h2 else ""
        p = re.search(r"<p[^>]*>(.*?)</p>", block, flags=re.I | re.S)
        if p:
            excerpt = strip_tags(p.group(1))
        else:
            lis = re.findall(r"<li[^>]*>(.*?)</li>", block, flags=re.I | re.S)
            excerpt = strip_tags(lis[0]) if lis else ""
        sections.append({"heading": heading, "text_excerpt": excerpt, "component_type": "static"})

    steps = re.search(r"<section\s+class=[\"\']steps[\"\'][^>]*>(.*?)</section>", html, flags=re.I | re.S)
    if steps:
        block = steps.group(1)
        h2 = re.search(r"<h2[^>]*>(.*?)</h2>", block, flags=re.I | re.S)
        heading = strip_tags(h2.group(1)) if h2 else ""
        ol = re.search(r"<ol[^>]*>(.*?)</ol>", block, flags=re.I | re.S)
        excerpt = strip_tags(ol.group(1)) if ol else ""
        sections.append({"heading": heading, "text_excerpt": excerpt, "component_type": "static"})

    faq = re.search(r"<section\s+class=[\"\']faq[\"\'][^>]*>(.*?)</section>", html, flags=re.I | re.S)
    if faq:
        block = faq.group(1)
        h2 = re.search(r"<h2[^>]*>(.*?)</h2>", block, flags=re.I | re.S)
        heading = strip_tags(h2.group(1)) if h2 else ""
        sums = [strip_tags(x) for x in re.findall(r"<summary[^>]*>(.*?)</summary>", block, flags=re.I | re.S)]
        excerpt = " | ".join([s for s in sums if s])
        sections.append({"heading": heading, "text_excerpt": excerpt, "component_type": "static"})

    if re.search(r"class=[\"\']proof-strip[\"\']", html, flags=re.I):
        chips = [strip_tags(x) for x in re.findall(r"<span\s+class=[\"\']chip[\"\'][^>]*>(.*?)</span>", html, flags=re.I | re.S)]
        if chips:
            sections.append({"heading": "", "text_excerpt": " / ".join(chips), "component_type": "grid"})

    if re.search(r"class=[\"\']grid-2[\"\']", html, flags=re.I):
        sections.append({"heading": "", "text_excerpt": "grid-2", "component_type": "grid"})

    return sections


def extract_interactive(html: str) -> list[dict]:
    items: list[dict] = []
    for am in re.finditer(
        r"<a\s+[^>]*class=[\"\'][^\"\']*\bbtn\b[^\"\']*[\"\'][^>]*href=[\"\']([^\"\']+)[\"\'][^>]*>(.*?)</a>",
        html,
        flags=re.I | re.S,
    ):
        href = unescape(am.group(1).strip())
        label = strip_tags(am.group(2))
        items.append({"type": "link", "role": "button", "label": label, "href": href})

    for sm in re.finditer(r"<summary[^>]*>(.*?)</summary>", html, flags=re.I | re.S):
        label = strip_tags(sm.group(1))
        items.append({"type": "disclosure", "label": label})

    return items


def extract_data_sources(path: str, html: str) -> list:
    sources: list = []

    # Only record fetch() calls where the URL argument is a literal string.
    for fm in re.finditer(r"fetch\(\s*[\"\']([^\"\']+)[\"\']", html, flags=re.I):
        sources.append(fm.group(1))

    if path.rstrip("/") == "/attest":
        if "/attest/attest.json" in html or "attest.json" in html:
            sources.append("./attest.json")
        if "/attest/LATEST.txt" in html or "LATEST.txt" in html:
            sources.append("./LATEST.txt")

    out: list = []
    seen = set()
    for s in sources:
        if s not in seen:
            seen.add(s)
            out.append(s)
    return out


def detect_external_calls(html: str) -> bool:
    # Only counts script-driven network calls with a literal string URL.
    for fm in re.finditer(r"fetch\(\s*[\"\']([^\"\']+)[\"\']", html, flags=re.I):
        url = fm.group(1).strip()
        if url.startswith("http://") or url.startswith("https://"):
            try:
                if urlparse(url).netloc and urlparse(url).netloc != urlparse(BASE).netloc:
                    return True
            except Exception:
                return True
    return False


def extract_links_for_crawl(html: str) -> list[str]:
    hrefs = []
    for am in re.finditer(r"<a\s+[^>]*href=[\"\']([^\"\']+)[\"\']", html, flags=re.I):
        hrefs.append(unescape(am.group(1).strip()))
    out = []
    seen = set()
    for href in hrefs:
        if href in seen:
            continue
        seen.add(href)
        out.append(href)
    return out


def norm_path(href: str) -> str | None:
    if not href or href.startswith("#") or href.startswith("mailto:") or href.startswith("javascript:"):
        return None
    if href.startswith("http://") or href.startswith("https://"):
        u = urlparse(href)
        if u.netloc != urlparse(BASE).netloc:
            return None
        return u.path or "/"
    if href.startswith("/"):
        return href
    return urlparse(urljoin(BASE + "/", href)).path


def is_route_candidate(path: str) -> bool:
    if re.search(r"\.(css|js|png|jpg|jpeg|gif|svg|ico|txt|json|sig|sha256|map)$", path, flags=re.I):
        return False
    return True


def digest_short(s: str) -> str:
    if not isinstance(s, str):
        return ""
    m = re.match(r"^(sha256|blake3):([0-9a-f]{16,128})$", s, re.I)
    if not m:
        return s
    algo = m.group(1).lower()
    hexv = m.group(2).lower()
    return f"{algo}:{hexv[:12]}"


def walk(obj):
    if isinstance(obj, dict):
        for _, v in obj.items():
            yield from walk(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from walk(v)
    elif isinstance(obj, str):
        yield obj


def main() -> int:
    queue: list[tuple[str, int]] = [(p, 0) for p in START_PATHS]
    seen: set[str] = set()
    route_records: dict[str, dict] = {}

    while queue:
        path, depth = queue.pop(0)
        if path in seen:
            continue
        seen.add(path)

        url = urljoin(BASE, path)
        status, ctype, html = http_get(url)
        route_records[path] = {"status": status, "ctype": ctype, "html": html}

        if depth >= MAX_DEPTH:
            continue
        if "text/html" not in (ctype or ""):
            continue

        for href in extract_links_for_crawl(html):
            p = norm_path(href)
            if not p:
                continue
            if not is_route_candidate(p):
                continue
            queue.append((p, depth + 1))

    for p in ["/docs/", "/architecture/", "/proof/", "/docs"]:
        if p not in seen:
            status, ctype, body = http_get(urljoin(BASE, p))
            route_records[p] = {"status": status, "ctype": ctype, "html": body}
            seen.add(p)

    _, _, css_text = http_get(urljoin(BASE, "/shared/ui.css"))
    attest_vars = dict(re.findall(r"--(vm-attest-[a-z-]+)\s*:\s*([^;]+);", css_text))
    attest_vars = {k: v.strip() for k, v in attest_vars.items()}

    att_json_status, att_json_ctype, att_json_text = http_get(urljoin(BASE, "/attest/attest.json"))
    latest_status, latest_ctype, latest_text = http_get(urljoin(BASE, "/attest/LATEST.txt"))
    try:
        att = json.loads(att_json_text) if att_json_text else {}
    except Exception:
        att = {}

    hashes: list[str] = []
    statuses: set[str] = set()
    for s in walk(att):
        if DIGEST_RE.match(s):
            hashes.append(digest_short(s))
        if s in {"PRESENT", "MISSING", "UNKNOWN", "INVALID"}:
            statuses.add(s)
    hashes = list(dict.fromkeys(hashes))
    verification_states = sorted(statuses)

    attest_extract = {
        "schema_id_values": [att.get("schema_id")] if att.get("schema_id") is not None else [],
        "hash_fields_short": hashes,
        "verification_states": verification_states,
        "drift": att.get("health", {}).get("drift", {}),
        "anchors": att.get("anchors", {}),
        "receipt_count": att.get("continuity", {}).get("receipt_count", {}),
        "authority": att.get("authority", {}),
        "latest_txt": (latest_text or "").strip(),
    }

    def design_profile_for(path: str, html: str):
        body_class = extract_body_class(html)
        profile = {"background": "", "primary_colors": [], "font_style": "", "layout_style": ""}
        if "vm-attest" in body_class.split():
            profile["background"] = attest_vars.get("vm-attest-bg", "")
            profile["primary_colors"] = [
                attest_vars.get("vm-attest-bg", ""),
                attest_vars.get("vm-attest-text", ""),
                attest_vars.get("vm-attest-panel", ""),
                attest_vars.get("vm-attest-line", ""),
                attest_vars.get("vm-attest-line-soft", ""),
            ]
            profile["primary_colors"] = [c for c in profile["primary_colors"] if c]
            profile["font_style"] = "var(--font-mono)"
            if path.rstrip("/") == "/attest":
                profile["layout_style"] = ".wrap (max-width: 1100px); .grid (12-column); .row key/value"
            else:
                profile["layout_style"] = ".page (max-width: 980px); sections: .hero, .card, .steps, .faq; grids: .grid-2/.grid-3"
        return profile

    preferred = ["/", "/attest/", "/verify/", "/trust/", "/support/", "/proof-pack/"]

    def sort_key(p: str):
        if p in preferred:
            return (0, preferred.index(p))
        return (1, p)

    routes_out: list[dict] = []
    site_map: list[str] = []

    for path in sorted(route_records.keys(), key=sort_key):
        rec = route_records[path]
        status = rec["status"]
        ctype = rec["ctype"] or ""
        html = rec["html"] or ""

        route_obj = {
            "path": path,
            "status_code": status,
            "title": extract_title(html) if "text/html" in ctype else "",
            "meta_description": extract_meta_description(html) if "text/html" in ctype else "",
            "navigation": {"header_links": [], "footer_links": []},
            "sections": [],
            "interactive_elements": [],
            "data_sources": [],
            "external_calls_detected": False,
            "design_profile": {"background": "", "primary_colors": [], "font_style": "", "layout_style": ""},
        }

        if "text/html" in ctype:
            header_links, footer_links = extract_nav_links(html)
            route_obj["navigation"]["header_links"] = header_links
            route_obj["navigation"]["footer_links"] = footer_links
            route_obj["sections"] = extract_sections(path, html)
            route_obj["interactive_elements"] = extract_interactive(html)
            route_obj["data_sources"] = extract_data_sources(path, html)
            route_obj["external_calls_detected"] = detect_external_calls(html)
            route_obj["design_profile"] = design_profile_for(path, html)

        if path.rstrip("/") == "/attest":
            route_obj["data_sources"] = route_obj["data_sources"] + [
                {"/attest/attest.json": {"status_code": att_json_status, "content_type": att_json_ctype}},
                {"/attest/LATEST.txt": {"status_code": latest_status, "content_type": latest_ctype}},
                {"attestation_extracted": attest_extract},
            ]

        routes_out.append(route_obj)
        site_map.append(path)

    home_html = route_records.get("/", {}).get("html", "")
    attest_html = route_records.get("/attest/", {}).get("html", "")

    marketing_layer_present = "Proof you can hand to skeptics." in home_html
    console_first_design = "Public Attestation" in attest_html
    institutional_positioning_visible = ("VaultMesh Foundation" in home_html) or ("VaultMesh Foundation" in attest_html)

    trust_surface_maturity = "v0"
    att_title = extract_title(attest_html)
    m = re.search(r"\(v(\d+)\.(\d+)\)", att_title)
    if m:
        major = int(m.group(1))
        trust_surface_maturity = "v2" if major >= 2 else "v1"

    out = {
        "site_map": site_map,
        "routes": routes_out,
        "surface_assessment": {
            "marketing_layer_present": bool(marketing_layer_present),
            "console_first_design": bool(console_first_design),
            "institutional_positioning_visible": bool(institutional_positioning_visible),
            "trust_surface_maturity": trust_surface_maturity,
        },
    }

    json.dump(out, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
