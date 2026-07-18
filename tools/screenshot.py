r"""Take a screenshot of a web page so Claude (or anyone) can look at it.

Usage:
    py tools\screenshot.py <url> <output.png> [options]

Options:
    --full            capture the whole page, not just the visible viewport
    --width N         viewport width in px (default 1280)
    --height N        viewport height in px (default 800)
    --mobile          shortcut for a 390x844 phone-sized viewport
    --wait SELECTOR   wait for this CSS selector to appear before shooting
    --delay MS        extra wait in milliseconds after load (default 500)

Examples:
    py tools\screenshot.py https://example.com shot.png
    py tools\screenshot.py http://localhost:8000/route-checklist/ app.png --mobile --full
"""

import argparse
import sys

from playwright.sync_api import sync_playwright


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url")
    parser.add_argument("output")
    parser.add_argument("--full", action="store_true")
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=800)
    parser.add_argument("--mobile", action="store_true")
    parser.add_argument("--wait")
    parser.add_argument("--delay", type=int, default=500)
    args = parser.parse_args()

    width, height = (390, 844) if args.mobile else (args.width, args.height)

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": width, "height": height})
        page.goto(args.url, wait_until="networkidle", timeout=30000)
        if args.wait:
            page.wait_for_selector(args.wait, timeout=15000)
        page.wait_for_timeout(args.delay)
        page.screenshot(path=args.output, full_page=args.full)
        title = page.title()
        browser.close()

    print(f"Saved {args.output} ({width}x{height}, full_page={args.full}) — page title: {title!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
