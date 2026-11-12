#!/usr/bin/env python3
"""Screen opt-in candidate JSON with live requests before native iOS verification.

Install requests, beautifulsoup4, lxml and regex. Only explicit HTML selector
rules are screened. Passes are evidence from this network and this parser, not
an iOS certification. The output contains measurements and source identities,
never chapter text.
"""

import argparse
from concurrent.futures import as_completed, ThreadPoolExecutor
from datetime import datetime, timezone
import ipaddress
import json
from pathlib import Path
import re
import socket
import sys
import time
from threading import local
import unicodedata
from urllib.parse import parse_qsl, quote, quote_from_bytes, urlencode, urljoin, urlsplit, urlunsplit

from bs4 import BeautifulSoup, Tag
import regex
import requests
from soupsieve import SelectorSyntaxError


HEADERS = {
    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "zh-CN,zh-Hans;q=0.9",
}
ATTRIBUTES = {
    "text", "text()", "textnodes", "owntext", "html", "html()", "href", "src",
    "content", "data-original", "data-src", "title", "value", "alt",
}
URL_ATTRIBUTES = {"href", "src", "data-original", "data-src"}
NEXT_PAGE_LABELS = {"下一页", "下页", "下一頁", "下頁", "nextpage"}
UNFINISHED = re.compile(r"本章未完|本章未完結|点击下一页|點擊下一頁|下一页继续|下一頁繼續")
CHAPTER_NUMBER = re.compile(r"第\s*([0-9零〇一二两兩三四五六七八九十百千万萬]+)\s*[章节節回]")
BLOCK_TITLE = re.compile(
    r"captcha|cloudflare|just a moment|access denied|网站防火墙|人机验证|安全验证|"
    r"访问受限|页面不存在|域名出售|正在跳转", re.I,
)
DEFAULT_TITLES = ("凡人修仙传", "诡秘之主", "斗破苍穹", "三体", "紅樓夢", "诡秘")
MAX_BODY = 5 * 1024 * 1024
MAX_TOC_PAGES = 12
MAX_CHAPTER_PAGES = 10
PROXY_ADDRESSES = ipaddress.ip_network("198.18.0.0/15")
PROBE_CONTEXT = local()


class ProbeError(Exception):
    pass


def require_http(value, base=""):
    value = value.split(",{", 1)[0].strip()
    if not value or value.startswith("#"):
        raise ProbeError("missing or fragment-only URL")
    parts = urlsplit(urljoin(base, value))
    if (
        parts.scheme not in {"http", "https"} or not parts.hostname
        or parts.username or parts.password or parts.port not in {None, 80, 443}
    ):
        raise ProbeError("unsupported URL")
    return parts._replace(fragment="").geturl()


def check_public_host(url):
    host = urlsplit(url).hostname
    if not host or "." not in host or host.endswith((".local", ".localhost", ".internal", ".test", ".invalid")):
        raise ProbeError("non-public host")
    try:
        addresses = {entry[4][0] for entry in socket.getaddrinfo(host, None)}
    except socket.gaierror as error:
        raise ProbeError(f"DNS failed for {host}") from error
    is_proxy = getattr(PROBE_CONTEXT, "allow_proxy_addresses", False)
    if not addresses or any(
        not address.is_global and not (is_proxy and address in PROXY_ADDRESSES and not host.replace(".", "").isdigit())
        for address in map(ipaddress.ip_address, addresses)
    ):
        raise ProbeError("non-public address")


def fetch(session, url, referer, timeout, method="GET", body=None):
    url = require_http(url)
    headers = {"Referer": quote(require_http(referer), safe=":/?[]@!$&'()*+,;=%-._~")}
    if method == "POST":
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    end = time.monotonic() + timeout
    for _ in range(6):
        remaining = end - time.monotonic()
        if remaining <= 0:
            raise ProbeError("request deadline")
        check_public_host(url)
        with session.request(
            method, url, data=body, headers=headers, allow_redirects=False,
            stream=True, timeout=min(remaining, timeout),
        ) as response:
            if response.is_redirect:
                url = require_http(response.headers["Location"], response.url)
                if response.status_code in {301, 302, 303}:
                    method, body = "GET", None
                    headers.pop("Content-Type", None)
                continue
            response.raise_for_status()
            if not 200 <= response.status_code < 300:
                raise ProbeError(f"HTTP {response.status_code}")
            data = bytearray()
            for chunk in response.iter_content(64 * 1024):
                data.extend(chunk)
                if len(data) > MAX_BODY or time.monotonic() >= end:
                    raise ProbeError("response exceeded size or time limit")
            for encoding in ("utf-8-sig", "gb18030", "gbk", "gb2312", "iso-8859-1"):
                try:
                    doc = BeautifulSoup(data.decode(encoding), "lxml")
                except UnicodeDecodeError:
                    continue
                if doc.title and BLOCK_TITLE.search(doc.title.get_text(" ", strip=True)):
                    raise ProbeError("challenge or error page")
                return doc, require_http(response.url)
    raise ProbeError("redirect limit")


def clean_rule(rule):
    if not isinstance(rule, str):
        raise ProbeError("non-string rule")
    rule = rule.strip()
    if len(rule.encode("utf-8")) > 65_536:
        raise ProbeError("oversized rule")
    lower = rule.lower()
    if re.search(r"@js:|</?js|\{\{|java\.|@json:|@xpath:|^\$|^//(?!meta\[)", lower):
        raise ProbeError("script, dynamic template, JSONPath or XPath")
    if lower.startswith("@css:"):
        rule = rule[5:].strip()
    elif rule.startswith("@@"):
        rule = rule[2:].strip()
    return rule


def select_chain(root, rule):
    chain = clean_rule(rule).lstrip("-+").strip()
    current = [root]
    for token in filter(None, map(str.strip, chain.split("@"))):
        reverse = "[-1:0]" in token
        token = re.sub(r"\[[^\]]*:[^\]]*\]$", "", token)
        exclude = None
        if "!" in token:
            token, _, excluded = token.partition("!")
            exclude = int(excluded.replace(".", ""))
            token = token.rstrip(".")
        index = None
        indexed = re.fullmatch(r"(.+)\.(-?\d+)", token)
        if indexed:
            token, index = indexed[1], int(indexed[2])
        head, dot, tail = token.partition(".")
        if dot and head == "class":
            token = "." + ".".join(tail.split())
        elif dot and head == "id":
            token = "#" + tail
        elif dot and head == "tag":
            token = tail
        elif dot and head == "text":
            token = f"a:-soup-contains({json.dumps(tail, ensure_ascii=False)})"
        elif token == "children":
            token = ":scope > *"
        token = re.sub(r"^//meta\[@property='([^']+)'\]$", r'meta[property="\1"]', token)
        token = re.sub(r":eq\((\d+)\)", lambda m: f":nth-child({int(m[1]) + 1})", token)
        token = re.sub(r":contains\(([^)]*)\)", lambda m: f":-soup-contains({json.dumps(m[1])})", token)
        matches = []
        for element in current:
            if not token:
                matches.append(element)
                continue
            selected = element.select(token)
            # SwiftSoup includes the root only when it is the sole match.
            if not selected and isinstance(element, Tag) and element.css.match(token):
                selected = [element]
            matches.extend(selected)
        if reverse:
            matches.reverse()
        if exclude is not None and -len(matches) <= exclude < len(matches):
            del matches[exclude]
        if index is not None:
            matches = [matches[index]] if -len(matches) <= index < len(matches) else []
        current = matches
        if not current:
            break
    return current


def select_list(root, rule):
    for alternative in rule.split("||"):
        try:
            candidate = clean_rule(alternative).lstrip("-+").strip()
            if not candidate or not (candidate[0].isalpha() or candidate[0] in ".#*[:"):
                continue
            if any(marker in candidate for marker in ";{}"):
                continue
            selected = select_chain(root, candidate)
        except (ProbeError, SelectorSyntaxError, ValueError):
            continue
        if selected:
            return selected
    return []


def replace_regex(text, pattern, replacement):
    # ICU-style numbered capture replacements. The timeout also bounds malformed
    # candidate regexes that would otherwise tie up a worker.
    replacement = re.sub(r"(?<!\\)\$(\d+)", lambda m: rf"\g<{m[1]}>", replacement)
    return regex.sub(pattern, replacement, text, timeout=0.1)


def extract_single(root, rule, base):
    selector, *regex_parts = rule.split("##", 2)
    # The Swift implementation splits on @ even inside a meta selector. Reject
    # unsupported XPath chains here instead of simulating a different parser.
    selector = clean_rule(selector)
    attribute = "text"
    if selector.endswith("/text()"):
        selector = selector[:-7]
    for suffix in ("/@content", "/@href"):
        if selector.endswith(suffix):
            selector, attribute = selector[:-len(suffix)], suffix[2:]
            break
    tokens = [t.strip() for t in selector.split("@") if t.strip()]
    if tokens and tokens[-1].lower() in ATTRIBUTES:
        attribute = tokens.pop().lower()
    values = []
    for node in select_chain(root, "@".join(tokens)):
        if attribute in {"text", "text()", "owntext"}:
            value = node.get_text(" ", strip=True)
        elif attribute == "textnodes":
            value = re.sub(r"<br[^>]*>|</p>", "\n", node.decode_contents(), flags=re.I)
            value = re.sub(r"<[^>]+>", "", value)
        elif attribute in {"html", "html()"}:
            value = node.decode_contents()
        else:
            value = node.get(attribute, "")
        if isinstance(value, str) and value.strip():
            values.append(value.strip())
            if attribute in URL_ATTRIBUTES:
                break
    result = "\n".join(values)
    if result and regex_parts and regex_parts[0]:
        result = replace_regex(result, regex_parts[0], regex_parts[1] if len(regex_parts) > 1 else "")
    result = result.strip()
    if result and (attribute in URL_ATTRIBUTES or result.startswith("/")):
        return urljoin(base, result.split(",{", 1)[0])
    return result


def extract(root, rule, base):
    for alternative in rule.split("||"):
        values = [extract_single(root, part, base) for part in alternative.split("&&") if part.strip()]
        result = " · ".join(filter(None, values))
        if result:
            return result
    return ""


def make_search(source, title):
    template = source["searchUrl"]
    is_gbk = any(charset in template.lower() for charset in ("gbk", "gb2312"))
    encoded = quote_from_bytes(title.encode("gb18030" if is_gbk else "utf-8"))
    for token, replacement in (("key", encoded), ("page", "1")):
        template = template.replace("{{" + token + "}}", replacement).replace("{" + token + "}", replacement)
    address, option_separator, options = template.partition(",{")
    clean_rule(address)
    method = "GET"
    body = None
    if option_separator:
        options = "{" + options
        if re.search(r"@js:|</?js|\{\{|java\.|webView", options, re.I):
            raise ProbeError("unsupported request options")
        if re.search(r"""['"]post['"]""", options, re.I):
            method = "POST"
            try:
                body = json.loads(options.replace("'", '"')).get("body")
            except json.JSONDecodeError:
                match = re.search(r"""['"]body['"]\s*:\s*['"]([^'"]+)['"]""", options, re.I)
                body = match[1] if match else None
            if not isinstance(body, str):
                raise ProbeError("unresolved POST body")
    return require_http(address, source["bookSourceUrl"]), method, body


def normalize_title(value):
    return "".join(c for c in unicodedata.normalize("NFKC", value).casefold() if c.isalnum())


def possible_book_urls(doc, base, source, title):
    rule = source["ruleSearch"]
    expected = normalize_title(title)
    seen = set()
    for element in select_list(doc, rule["bookList"]):
        name = normalize_title(extract(element, rule["name"], base))
        if name != expected:
            continue
        value = extract(element, rule.get("bookUrl") or "tag.a.0@href||a@href", base)
        if value:
            url = require_http(value, base)
            if url not in seen:
                seen.add(url)
                yield url


def toc_next(doc, source, url):
    explicit = extract(doc, source["ruleToc"].get("nextTocUrl") or "", url)
    if explicit:
        return require_http(explicit, url)
    for anchor in doc.select("a[rel=next], link[rel=next], a[href]"):
        label = re.sub(r"\s+", "", anchor.get_text()).lower()
        container = [anchor, *list(anchor.parents)[:3]]
        is_paging = any(
            "pag" in str(item.get("class", "")).lower() or "pag" in item.get("id", "").lower()
            for item in container
        )
        if "next" in anchor.get("rel", []) or is_paging and label in NEXT_PAGE_LABELS | {"next", "»", ">>", ">"}:
            href = anchor.get("href", "")
            if href and not href.startswith("#"):
                return require_http(href, url)
    return None


def load_toc(session, book_url, source, timeout):
    rule = source["ruleToc"]
    doc, url = fetch(session, book_url, source["bookSourceUrl"], timeout)
    explicit = extract(doc, (source.get("ruleBookInfo") or {}).get("tocUrl") or "", url)
    if explicit and require_http(explicit, url) != url:
        doc, url = fetch(session, require_http(explicit, url), url, timeout)
    catalogue_url = url
    seen_pages, chapters = set(), {}
    for page in range(1, MAX_TOC_PAGES + 1):
        if url in seen_pages:
            raise ProbeError("catalogue pagination loop")
        seen_pages.add(url)
        count_before = len(chapters)
        for element in select_list(doc, rule["chapterList"]):
            title = extract(element, rule.get("chapterName") or "text", url)
            href = extract(element, rule.get("chapterUrl") or "href", url)
            if title and href and not href.startswith(("javascript:", "#")):
                chapter_url = require_http(href, url)
                if chapter_url != url:
                    chapters.setdefault(chapter_url, title)
        if len(chapters) <= count_before:
            raise ProbeError("catalogue added no unique chapters")
        next_url = toc_next(doc, source, url)
        if next_url is None:
            if len(chapters) < 3:
                raise ProbeError("catalogue has fewer than three distinct chapters")
            return list(chapters.items()), page, catalogue_url
        doc, url = fetch(session, next_url, url, timeout)
    raise ProbeError("catalogue probe page limit")


def chapter_stem(url):
    scheme, host, path, query, _ = urlsplit(url)
    path = re.sub(r"[_-]\d+(?=\.[a-zA-Z]+$)", "", path)
    query = urlencode([(k, v) for k, v in parse_qsl(query) if k.lower() not in {"page", "p", "pageno"}])
    return urlunsplit((scheme, host, path, query, ""))


def chapter_number(value):
    match = CHAPTER_NUMBER.search(unicodedata.normalize("NFKC", value))
    if not match:
        return None
    token = match[1]
    if token.isdecimal():
        return int(token)
    digits = dict(zip("零一二三四五六七八九", range(10))) | {"〇": 0, "两": 2, "兩": 2}
    if all(c in digits for c in token):
        return int("".join(str(digits[c]) for c in token))
    digit = subtotal = total = 0
    for char in token:
        if char in digits:
            digit = digits[char]
        elif char in {"万", "萬"}:
            total += (subtotal + digit) * 10000
            subtotal = digit = 0
        elif char in {"十", "百", "千"}:
            subtotal += max(1, digit) * {"十": 10, "百": 100, "千": 1000}[char]
            digit = 0
        else:
            return None
    return total + subtotal + digit


def chapter_next(doc, url, first_url, next_chapter, rule):
    counter = any(
        int(match[1]) < int(match[2])
        for node in doc.select("h1, title, .pagination, .pager, .pagebar")
        for match in re.finditer(r"(\d+)\s*[/／]\s*(\d+)", node.get_text())
    )
    unfinished = counter or UNFINISHED.search(doc.get_text())
    anchors = doc.select("a[href]")
    candidate = extract(doc, rule.get("nextContentUrl") or "", url)
    explicit = bool(candidate)
    if not candidate:
        for anchor in anchors:
            label = re.sub(r"\s+|[»›>→]", "", anchor.get_text()).lower()
            if label in NEXT_PAGE_LABELS and not (anchor.has_attr("disabled") or anchor.get("aria-disabled") == "true"):
                candidate = anchor["href"]
                break
    if not candidate:
        if unfinished:
            raise ProbeError("chapter continuation could not be resolved")
        return None
    if candidate == url + "#":
        candidate = "#"
    if candidate == "#":
        if unfinished:
            raise ProbeError("chapter continuation disabled")
        return None
    target = require_http(candidate, url)
    for anchor in anchors:
        if urljoin(url, anchor["href"]) != target:
            continue
        label = anchor.get_text(" ", strip=True).lower()
        if anchor["href"] == "#" or re.search(r"下一章|下章|next chapter", label) or anchor.has_attr("disabled") or anchor.get("aria-disabled") == "true":
            if unfinished:
                raise ProbeError("incomplete chapter before next chapter link")
            return None
    if target == next_chapter:
        if unfinished:
            raise ProbeError("incomplete chapter before next catalogue entry")
        return None
    if urlsplit(target).hostname != urlsplit(first_url).hostname or not explicit and chapter_stem(target) != chapter_stem(first_url):
        raise ProbeError("chapter continuation crossed host or chapter")
    return target


def load_chapter(session, chapter, referer, next_chapter, rule, timeout):
    url, expected = chapter
    first_url, seen, text_pages = None, set(), []
    for page in range(1, MAX_CHAPTER_PAGES + 1):
        doc, final_url = fetch(session, url, referer, timeout)
        if url in seen or final_url in seen:
            raise ProbeError("chapter pagination loop")
        seen.update({url, final_url})
        first_url = first_url or final_url
        if doc.h1:
            actual, desired = chapter_number(doc.h1.get_text()), chapter_number(expected)
            if actual is not None and desired is not None and actual != desired:
                raise ProbeError("chapter title differs from catalogue")
        selector = rule["content"]
        html_selector = selector[:-5] + "@html" if selector.endswith("@text") else selector
        content = extract(doc, html_selector, final_url) or extract(doc, selector, final_url)
        if rule.get("replaceRegex"):
            pattern, _, replacement = rule["replaceRegex"].removeprefix("##").partition("##")
            if pattern:
                content = replace_regex(content, pattern, replacement.split("##", 1)[0])
        prose = BeautifulSoup(content, "lxml").get_text(" ", strip=True)
        compact = normalize_title(prose)
        if len(compact) < 40 or compact in text_pages:
            raise ProbeError("chapter page has little prose or repeats an earlier page")
        text_pages.append(compact)
        next_url = chapter_next(doc, final_url, first_url, next_chapter, rule)
        if next_url is None:
            length = sum(map(len, text_pages))
            if length < 350:
                raise ProbeError("chapter has fewer than 350 letters/digits")
            return length, page, "".join(text_pages), first_url
        url, referer = next_url, final_url
    raise ProbeError("chapter probe page limit")


def check_required_rules(source):
    if source.get("bookSourceType") not in {None, 0}:
        raise ProbeError("not a text source")
    if source.get("enabled") is False:
        raise ProbeError("source disabled upstream")
    if any(source.get(group) is not None and not isinstance(source[group], dict)
           for group in ("ruleSearch", "ruleBookInfo", "ruleToc", "ruleContent")):
        raise ProbeError("invalid rule group")
    for group, fields in {
        "ruleSearch": ("bookList", "name"), "ruleToc": ("chapterList",),
        "ruleContent": ("content",),
    }.items():
        for field in fields:
            if not isinstance((source.get(group) or {}).get(field), str) or not source[group][field].strip():
                raise ProbeError(f"missing {group}.{field}")
    for group, fields in {
        "ruleSearch": ("name", "bookUrl", "author", "intro", "lastChapter", "coverUrl"),
        "ruleBookInfo": ("tocUrl",),
        "ruleToc": ("chapterName", "chapterUrl", "nextTocUrl"),
        "ruleContent": ("content", "nextContentUrl", "replaceRegex"),
    }.items():
        for field in fields:
            value = (source.get(group) or {}).get(field)
            if value and (not isinstance(value, str) or re.search(r"@js:|</?js|\{\{|java\.|@json:", value, re.I)):
                raise ProbeError(f"unsupported by this screen: {group}.{field}")


def probe(source, titles, timeout, required_matches, allow_proxy_addresses=False):
    PROBE_CONTEXT.allow_proxy_addresses = allow_proxy_addresses
    report = {"name": source["bookSourceName"], "url": source["bookSourceUrl"], "status": "failed", "probes": []}
    try:
        base = require_http(source["bookSourceUrl"])
        check_required_rules(source)
        if not isinstance(source.get("searchUrl"), str) or not re.search(r"\{\{?key\}\}?", source["searchUrl"]):
            raise ProbeError("missing static search keyword template")
        for title in titles:
            make_search(source, title)
    except (ProbeError, ValueError, UnicodeError) as error:
        return report | {"status": "unsupported", "reason": str(error)}

    completed = 0
    with requests.Session() as session:
        session.headers.update(HEADERS)
        for title in titles:
            result = {"title": title, "stage": "search"}
            started = time.monotonic()
            try:
                address, method, body = make_search(source, title)
                doc, final_url = fetch(session, address, base, timeout, method, body)
                result["search_ms"] = round((time.monotonic() - started) * 1000)
                book_url = next(possible_book_urls(doc, final_url, source, title), None)
                if not book_url:
                    raise ProbeError("exact title absent in parsed results")
                result["stage"] = "toc"
                chapters, toc_pages, catalogue_url = load_toc(session, book_url, source, timeout)
                result.update({"chapters": len(chapters), "toc_pages": toc_pages, "catalogue_url": catalogue_url, "stage": "chapter"})
                # Probe inside the catalogue to get past the preview/front matter.
                interior = min(len(chapters) - 3, len(chapters) // 4)
                start = next(
                    (index for index in range(interior, min(interior + 8, len(chapters) - 2))
                     if chapter_number(chapters[index][1]) is not None
                     and chapter_number(chapters[index + 1][1]) is not None),
                    interior,
                )
                a, a_pages, a_text, a_url = load_chapter(session, chapters[start], catalogue_url, chapters[start + 1][0], source["ruleContent"], timeout)
                b, b_pages, b_text, b_url = load_chapter(session, chapters[start + 1], catalogue_url, chapters[start + 2][0], source["ruleContent"], timeout)
                if a_text == b_text:
                    raise ProbeError("consecutive chapters returned identical prose")
                result.update({
                    "chapter_lengths": [a, b], "chapter_pages": [a_pages, b_pages],
                    "chapter_urls": [a_url, b_url], "stage": "passed",
                })
                completed += 1
            except (ProbeError, requests.RequestException, SelectorSyntaxError, ValueError, UnicodeError, TimeoutError, regex.error) as error:
                # Do not report upstream HTML or POST data.
                result["reason"] = str(error)[:260]
            result["elapsed_ms"] = round((time.monotonic() - started) * 1000)
            report["probes"].append(result)
            if completed >= required_matches:
                report["status"] = "passed"
                break
    return report


def read_sources(paths):
    seen = set()
    for path in paths:
        with path.open(encoding="utf-8-sig") as file:
            sources = json.load(file)
        if not isinstance(sources, list):
            raise ValueError(f"{path}: expected an array of book sources")
        for source in sources:
            if not isinstance(source, dict) or not all(
                isinstance(source.get(key), str) and source[key].strip()
                for key in ("bookSourceName", "bookSourceUrl")
            ):
                continue
            identity = source["bookSourceUrl"].strip()
            if identity not in seen:
                seen.add(identity)
                yield source


def write_json(path, data):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sources", nargs="+", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--passing-json", type=Path)
    parser.add_argument("--title", action="append", help="sample title; repeat to change the default list")
    parser.add_argument("--require-matches", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=7, help="deadline in seconds per request")
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--limit", type=int, help="screen at most this many entries")
    parser.add_argument("--allow-proxy-addresses", action="store_true",
                        help="opt in if public DNS is routed through your 198.18.0.0/15 proxy")
    args = parser.parse_args()
    titles = list(dict.fromkeys(args.title or DEFAULT_TITLES))
    if not 1 <= args.require_matches <= len(titles) or not 1 <= args.workers <= 32 or args.timeout <= 0:
        parser.error("use positive timeout and match counts, and 1–32 workers")
    if args.limit is not None and args.limit < 1:
        parser.error("limit must be positive")
    targets = [path.resolve() for path in (args.report, args.passing_json) if path]
    if len(set(targets)) != len(targets) or set(targets) & {path.resolve() for path in args.sources}:
        parser.error("use distinct output paths outside the input list")
    sources = list(read_sources(args.sources))[:args.limit]
    if not sources:
        parser.error("the inputs contain no usable book source definitions")
    started = datetime.now(timezone.utc).isoformat()
    results_by_index = {}
    with ThreadPoolExecutor(max_workers=args.workers) as workers:
        pending = {
            workers.submit(probe, source, titles, args.timeout, args.require_matches, args.allow_proxy_addresses): index
            for index, source in enumerate(sources)
        }
        for future in as_completed(pending):
            results_by_index[pending[future]] = future.result()
            if len(results_by_index) % 10 == 0 or len(results_by_index) == len(sources):
                ordered = sorted(results_by_index.items())
                results = [result for _, result in ordered]
                counts = {status: sum(r["status"] == status for r in results) for status in ("passed", "failed", "unsupported")}
                write_json(args.report, {"started": started, "titles": titles, "counts": counts, "results": results})
                if args.passing_json:
                    write_json(args.passing_json, [sources[i] for i, result in ordered if result["status"] == "passed"])
                print(f"Screened {len(results)}/{len(sources)} source definitions: {counts}", file=sys.stderr)


if __name__ == "__main__":
    main()
