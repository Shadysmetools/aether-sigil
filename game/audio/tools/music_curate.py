"""CC0 music catalogue builder (fallback path for tools/music_build.py).

Searches OpenGameArt.org's advanced search restricted to art type = Music and licence = CC0,
then opens every result page and keeps it only when the page's *only* licence is CC0. Writes
<work>/oga_catalog.json: [{page, title, author, tags, files[], licences[]}].

usage: python music_curate.py <work_dir> [keyword ...]
"""
import html
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

UA = {"User-Agent": "Mozilla/5.0 (AetherSigil music curation; CC0 only)"}
SEARCH = ("https://opengameart.org/art-search-advanced?keys={k}&field_art_type_tid%5B%5D=12"
          "&field_art_licenses_tid%5B%5D=4&sort_by=count&sort_order=DESC&items_per_page=48&page={p}")
KEYWORDS = [
    "orchestral", "fantasy", "battle", "boss", "epic", "adventure", "forest", "nature", "fire",
    "lava", "water", "ocean", "ice", "snow", "winter", "machine", "industrial", "steampunk",
    "wind", "storm", "sky", "dark", "shadow", "ancient", "ruins", "temple", "space", "cosmic",
    "stars", "crystal", "magic", "mystic", "ethereal", "final boss", "victory", "jingle",
    "game over", "defeat", "town", "world map", "exploration", "dungeon", "celtic", "asian",
    "ethnic", "desert", "action", "loop", "ambient", "harp", "flute", "taiko", "choir",
]
SKIP = {"/content/faq", "/content/cc0"}


def get(url, tries=3):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=40) as r:
                return r.read().decode("utf-8", "replace")
        except Exception as e:  # network hiccup: back off and retry
            if i == tries - 1:
                print("  fail", url, e)
                return ""
            time.sleep(2 + 3 * i)


def field(page, name):
    m = re.search(r'field-name-%s.*?</div></div></div>' % re.escape(name), page, re.S)
    if not m:
        return []
    return [html.unescape(t).strip() for t in re.findall(r'<a [^>]*>([^<]+)</a>', m.group(0))]


def licences(page):
    m = re.search(r'field-name-field-art-licenses(.*?)field-name-collect|field-name-field-art-licenses(.*?)$', page, re.S)
    block = (m.group(1) or m.group(2) or "")[:4000] if m else ""
    return [html.unescape(t).strip() for t in re.findall(r"<div class='license-name'>([^<]+)</div>", block)]


def parse(url, page):
    title = re.search(r'<title>([^<|]+)', page)
    author = re.search(r"field-name-author-submitter.*?<span class='username'><a [^>]*>([^<]+)</a>", page, re.S)
    files = sorted(set(re.findall(r'href="(https://opengameart\.org/sites/default/files/[^"]+\.(?:ogg|wav|mp3|flac|zip))"', page)))
    files = [f for f in files if "/styles/" not in f and "audio_preview" not in f]
    return {
        "page": url,
        "title": html.unescape(title.group(1)).strip() if title else url,
        "author": html.unescape(author.group(1)).strip() if author else "",
        "licences": licences(page),
        "tags": [t.lower() for t in field(page, "field-art-tags")],
        "files": files,
    }


def main():
    work = Path(sys.argv[1])
    work.mkdir(parents=True, exist_ok=True)
    kws = sys.argv[2:] or KEYWORDS
    out_path = work / "oga_catalog.json"
    cat = {c["page"]: c for c in json.loads(out_path.read_text())} if out_path.exists() else {}
    pages = set()
    for k in kws:
        for p in range(2):
            s = get(SEARCH.format(k=urllib.parse.quote(k), p=p))
            found = set(re.findall(r'href="(/content/[a-z0-9\-]+)"', s)) - SKIP
            pages |= found
            if len(found) < 40:
                break
        print(f"{k!r}: {len(pages)} pages so far")
    todo = [p for p in sorted(pages) if "https://opengameart.org" + p not in cat]
    for i, p in enumerate(todo):
        url = "https://opengameart.org" + p
        page = get(url)
        if not page:
            continue
        c = parse(url, page)
        cat[url] = c
        if i % 25 == 0:
            print(f"  {i}/{len(todo)}")
            out_path.write_text(json.dumps(list(cat.values()), indent=1))
    out_path.write_text(json.dumps(list(cat.values()), indent=1))
    ok = [c for c in cat.values() if c["licences"] == ["CC0"] and c["files"]]
    print(f"catalogue {len(cat)} pages, {len(ok)} CC0-only with audio files")


if __name__ == "__main__":
    main()
