#!/usr/bin/env python3
import re
import sys
from pathlib import Path


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def remove_block_between_markers(src: str, start_marker: str, end_marker: str) -> str:
    start = src.find(start_marker)
    end = src.find(end_marker, start + len(start_marker)) if start >= 0 else -1
    if start >= 0 and end >= 0:
        return src[:start] + src[end + len(end_marker):]
    return src


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: render_html_template.py <export_html> <template_dir>", file=sys.stderr)
        return 2

    export_html = Path(sys.argv[1])
    template_dir = Path(sys.argv[2])

    if not export_html.is_file():
        print(f"WARNING: Export HTML not found: {export_html}")
        return 0

    sw_head = read(template_dir / "service_worker_cleanup_head.html")
    picker_css = read(template_dir / "file_picker.css").strip()
    picker_html = read(template_dir / "file_picker.html").strip()
    boot_block = read(template_dir / "boot_block.js").strip()

    src = read(export_html)

    # 1) Force service worker registration path off.
    sw_gate = "if (GODOT_CONFIG['serviceWorker'] && GODOT_CONFIG['ensureCrossOriginIsolationHeaders'] && 'serviceWorker' in navigator) {"
    if sw_gate in src:
        src = src.replace(sw_gate, "if (false) {", 1)
    src = re.sub(r'"serviceWorker"\s*:\s*"[^"]*"', '"serviceWorker":""', src, count=1)

    # 2) Insert stale service worker cleanup snippet directly after <head>.
    if "cleared stale service workers/caches" not in src and "<head>" in src:
        src = src.replace("<head>", sw_head, 1)

    # 3) Replace file picker CSS and HTML from template markers.
    src = remove_block_between_markers(src, "/* OPM_FILE_PICKER_CSS_START */", "/* OPM_FILE_PICKER_CSS_END */")
    src = remove_block_between_markers(src, "/* MOHAA_FILE_PICKER_CSS_START */", "/* MOHAA_FILE_PICKER_CSS_END */")
    if "</style>" in src:
        src = src.replace("</style>", "\n" + picker_css + "\n</style>", 1)

    src = remove_block_between_markers(src, "<!-- OPM_FILE_PICKER_HTML_START -->", "<!-- OPM_FILE_PICKER_HTML_END -->")
    src = remove_block_between_markers(src, "<!-- MOHAA_FILE_PICKER_HTML_START -->", "<!-- MOHAA_FILE_PICKER_HTML_END -->")
    # Legacy fallback: remove old ad-hoc loader block if still present.
    src = re.sub(r'\s*<div id="(?:opm|mohaa)-loader">.*?</div>\s*</div>\s*(?=\s*<script)', "\n", src, flags=re.DOTALL)

    script_tag = '<script src="mohaa.js"></script>'
    if script_tag in src:
        src = src.replace(script_tag, picker_html + "\n\t\t" + script_tag, 1)

    # 4) Replace boot sequence with template block.
    boot_markers = [
        ("/* MOHAA_BOOT_START */", "/* MOHAA_BOOT_END */"),
        ("/* OPM_BOOT_START */", "/* OPM_BOOT_END */"),
    ]
    for start_marker, end_marker in boot_markers:
        s_idx = src.find(start_marker)
        e_idx = src.find(end_marker, s_idx) if s_idx >= 0 else -1
        if s_idx >= 0 and e_idx >= 0:
            src = src[:s_idx] + boot_block + src[e_idx + len(end_marker):]
            break
    else:
        # First-time patch against vanilla Godot export block.
        first = src.find("setStatusMode('progress');")
        last = src.find("}, displayFailureNotice);", first) if first >= 0 else -1
        if first >= 0 and last >= 0:
            last += len("}, displayFailureNotice);")
            src = src[:first] + boot_block + src[last:]

    export_html.write_text(src, encoding="utf-8")
    print(f"Rendered templated web HTML: {export_html}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
