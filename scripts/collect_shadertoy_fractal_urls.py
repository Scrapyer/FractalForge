#!/usr/bin/env python3
"""Collect Shadertoy fractal shader URLs from paginated search results."""

from __future__ import annotations

import argparse
import sys
import time
from html.parser import HTMLParser
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote_plus, urljoin, urlparse
from urllib.request import Request, urlopen


BASE_URL = "https://www.shadertoy.com"
DEFAULT_QUERY = "Fractal"
DEFAULT_PAGES = 10
DEFAULT_PAGE_SIZE = 12
MAX_PAGES = 30


class FetchError(RuntimeError):
    pass


class ShaderLinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.urls: list[str] = []
        self._seen: set[str] = set()

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "a":
            return

        href = dict(attrs).get("href")
        if not href:
            return

        absolute = urljoin(BASE_URL, href)
        parsed = urlparse(absolute)
        if parsed.netloc != "www.shadertoy.com":
            return

        parts = [part for part in parsed.path.split("/") if part]
        if len(parts) != 2 or parts[0] != "view" or not parts[1]:
            return

        clean_url = f"{BASE_URL}/view/{parts[1]}"
        if clean_url not in self._seen:
            self._seen.add(clean_url)
            self.urls.append(clean_url)


def build_results_url(query: str, page_index: int, page_size: int) -> str:
    encoded_query = quote_plus(query)
    if page_index == 0:
        return f"{BASE_URL}/results?query={encoded_query}"

    offset = page_index * page_size
    return (
        f"{BASE_URL}/results?query={encoded_query}"
        f"&sort=popular&from={offset}&num={page_size}"
    )


def fetch_text(url: str, timeout: float) -> str:
    request = Request(
        url,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/126.0 Safari/537.36"
            )
        },
    )
    try:
        with urlopen(request, timeout=timeout) as response:
            charset = response.headers.get_content_charset() or "utf-8"
            return response.read().decode(charset, errors="replace")
    except HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        if error.code == 403 or "Just a moment" in body or "cf_chl" in body:
            raise FetchError(
                f"HTTP {error.code}: Shadertoy returned a Cloudflare challenge page. "
                "Open the page in a browser first, or retry later."
            ) from error
        raise


def collect_urls(query: str, pages: int, page_size: int, delay: float, timeout: float) -> list[str]:
    collected: list[str] = []
    seen: set[str] = set()

    for page_index in range(pages):
        page_url = build_results_url(query, page_index, page_size)
        print(f"[{page_index + 1}/{pages}] Fetching {page_url}", file=sys.stderr)

        try:
            html = fetch_text(page_url, timeout)
        except (FetchError, HTTPError, URLError, TimeoutError) as error:
            print(f"  warning: failed to fetch page: {error}", file=sys.stderr)
            continue

        parser = ShaderLinkParser()
        parser.feed(html)

        new_count = 0
        for shader_url in parser.urls:
            if shader_url not in seen:
                seen.add(shader_url)
                collected.append(shader_url)
                new_count += 1

        print(f"  found {new_count} new shader URLs", file=sys.stderr)

        if page_index + 1 < pages and delay > 0:
            time.sleep(delay)

    return collected


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Collect Shadertoy /view/ URLs from Fractal search result pages."
    )
    parser.add_argument(
        "-p",
        "--pages",
        type=int,
        default=DEFAULT_PAGES,
        help=f"Number of result pages to fetch. Default: {DEFAULT_PAGES}. Max: {MAX_PAGES}.",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("data/shadertoy_fractal_urls.txt"),
        help="Output text file. Default: data/shadertoy_fractal_urls.txt.",
    )
    parser.add_argument(
        "--query",
        default=DEFAULT_QUERY,
        help=f"Search query. Default: {DEFAULT_QUERY}.",
    )
    parser.add_argument(
        "--page-size",
        type=int,
        default=DEFAULT_PAGE_SIZE,
        help=f"Result count per page. Default: {DEFAULT_PAGE_SIZE}.",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=1.0,
        help="Delay between page requests in seconds. Default: 1.0.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=20.0,
        help="HTTP timeout in seconds. Default: 20.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.pages < 1:
        print("error: --pages must be at least 1", file=sys.stderr)
        return 2
    if args.pages > MAX_PAGES:
        print(f"error: --pages is capped at {MAX_PAGES} to keep requests modest", file=sys.stderr)
        return 2
    if args.page_size < 1 or args.page_size > 50:
        print("error: --page-size must be between 1 and 50", file=sys.stderr)
        return 2

    urls = collect_urls(
        query=args.query,
        pages=args.pages,
        page_size=args.page_size,
        delay=max(args.delay, 0.0),
        timeout=args.timeout,
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(urls) + ("\n" if urls else ""), encoding="utf-8")
    print(f"Wrote {len(urls)} URLs to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
