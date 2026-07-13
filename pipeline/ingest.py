#!/usr/bin/env python3
"""The Seminar text pipeline: Gutenberg plain-text -> chapters -> passages -> embeddings.

Contract: docs/CONTRACTS.md §2 (passage IDs / offset space) and §8 (output formats).
Python 3.9 compatible; stdlib + requests only.

Usage:
  python3 ingest.py --url <gutenberg-txt-url> --book-id <id> --title "..." \
      --author "..." [--translator "..."] [--license-note "..."] \
      [--no-embed] [--seed-sql]
"""

import argparse
import hashlib
import json
import os
import re
import sys
import time

import requests

PIPELINE_DIR = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(PIPELINE_DIR, ".cache")
OUTPUT_DIR = os.path.join(PIPELINE_DIR, "output")

# Chunking parameters (CONTRACTS §2). 1 token ~= 0.75 words.
TARGET_TOKENS = 400
OVERLAP_TOKENS = 50
MAX_OVERLAP_TOKENS = 200  # skip overlap when the trailing paragraph exceeds this
# Chapters whose body is below this are treated as table-of-contents / front-
# matter artifacts and dropped (real prose chapters run far longer).
MIN_CHAPTER_TOKENS = 120

VOYAGE_URL = "https://api.voyageai.com/v1/embeddings"
VOYAGE_MODEL = "voyage-3.5"
VOYAGE_BATCH = 128
VOYAGE_DIMS = 1024


# ---------------------------------------------------------------- fetch

def fetch(url):
    """Download url (with on-disk cache in pipeline/.cache/)."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    key = hashlib.sha256(url.encode("utf-8")).hexdigest()[:16]
    cache_path = os.path.join(CACHE_DIR, key + ".txt")
    if os.path.exists(cache_path):
        print("fetch: cache hit %s" % cache_path)
        with open(cache_path, "r", encoding="utf-8") as f:
            return f.read()
    print("fetch: downloading %s" % url)
    resp = requests.get(url, timeout=60, headers={"User-Agent": "TheSeminar-pipeline/1.0"})
    resp.raise_for_status()
    resp.encoding = "utf-8"
    text = resp.text
    with open(cache_path, "w", encoding="utf-8") as f:
        f.write(text)
    return text


# ---------------------------------------------------------------- normalize

PG_START_RE = re.compile(r"^\*\*\*\s*START OF (?:THE|THIS) PROJECT GUTENBERG.*?\*\*\*\s*$",
                         re.IGNORECASE | re.MULTILINE)
PG_END_RE = re.compile(r"^\*\*\*\s*END OF (?:THE|THIS) PROJECT GUTENBERG.*?\*\*\*\s*$",
                       re.IGNORECASE | re.MULTILINE)

TRANSCRIBER_RE = re.compile(r"^\[(transcriber|illustration|redactor)", re.IGNORECASE)
DECORATIVE_RE = re.compile(r"^[\s*·._\-—]+$")  # e.g. "*       *       *"


def strip_pg_boilerplate(raw):
    """Cut everything outside the *** START/END *** markers."""
    start = PG_START_RE.search(raw)
    end = PG_END_RE.search(raw)
    if start:
        raw = raw[start.end():]
        # re-find end marker relative to the truncated text
        end = PG_END_RE.search(raw)
    if end:
        raw = raw[:end.start()]
    return raw


def normalize_to_paragraphs(raw):
    """PG plain text -> (paragraphs, flush_single_flags).

    - normalize line endings
    - strip underscores used as italics markers
    - unwrap hard-wrapped lines (paragraph = blank-line-separated block)
    - drop transcriber notes and decorative separator lines
    - keep curly quotes as-is
    """
    text = raw.replace("\r\n", "\n").replace("\r", "\n")
    text = text.replace("­", "")          # soft hyphens
    text = re.sub(r"_(.+?)_", r"\1", text, flags=re.DOTALL)  # _italics_ -> italics
    text = text.replace("_", "")               # stray underscores
    text = re.sub(r"\n{3,}", "\n\n", text)     # collapse >2 blank lines

    paragraphs = []
    flush_single = []
    for block in re.split(r"\n\s*\n", text):
        raw_lines = [ln for ln in block.split("\n") if ln.strip()]
        lines = [ln.strip() for ln in raw_lines]
        if not lines:
            continue
        para = " ".join(lines)
        para = re.sub(r"[ \t]{2,}", " ", para).strip()
        if not para:
            continue
        if TRANSCRIBER_RE.match(para):
            continue
        if DECORATIVE_RE.match(para):
            continue
        paragraphs.append(para)
        # single flush-left source line = the shape of a standalone heading.
        # In-story display lines (newspaper headlines, ballad titles) are
        # indented in PG texts, so this flag separates them from headings.
        flush_single.append(len(raw_lines) == 1 and not raw_lines[0][0].isspace())
    return paragraphs, flush_single


# ---------------------------------------------------------------- chapterize

ROMAN = r"[IVXLCDM]+"
LABELED_HEADING_RE = re.compile(
    r"^(LETTER|CHAPTER|STAVE|BOOK|PART|CANTO)\s+(%s|\d+)\.?\s*$" % ROMAN,
    re.IGNORECASE)
ROMAN_ALONE_RE = re.compile(r"^(%s)\.?$" % ROMAN)
# Word-ordinal book headings, e.g. Marcus Aurelius' "THE FIRST BOOK". Anchored
# on the leading "THE" so a bare-ordinal synopsis/contents ("FIRST BOOK") does
# not double the real headings.
WORD_ORDINALS = {
    "FIRST": 1, "SECOND": 2, "THIRD": 3, "FOURTH": 4, "FIFTH": 5, "SIXTH": 6,
    "SEVENTH": 7, "EIGHTH": 8, "NINTH": 9, "TENTH": 10, "ELEVENTH": 11,
    "TWELFTH": 12, "THIRTEENTH": 13, "FOURTEENTH": 14, "FIFTEENTH": 15,
    "SIXTEENTH": 16, "SEVENTEENTH": 17, "EIGHTEENTH": 18, "NINETEENTH": 19,
    "TWENTIETH": 20,
}
ORDINAL_BOOK_RE = re.compile(
    r"^THE\s+(%s)\s+(BOOK|PART)\.?$" % "|".join(WORD_ORDINALS), re.IGNORECASE)
END_OF_VOL_RE = re.compile(r"^\s*END OF (THE )?(VOL|VOLUME)\b", re.IGNORECASE)
THE_END_RE = re.compile(r"^THE END\.?$", re.IGNORECASE)
# Standalone end-matter heading lines (appendices, glossaries, editorial notes)
# that trail the main text with no chapter heading to bound them.
END_MATTER_RE = re.compile(
    r"^(APPENDIX|A?\s*GLOSSARY(\s+OF\b.*)?|NOTES|FOOTNOTES|INDEX)\.?$",
    re.IGNORECASE)

ROMAN_VALUES = {"I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000}


def roman_to_int(s):
    total, prev = 0, 0
    for ch in reversed(s.upper()):
        v = ROMAN_VALUES.get(ch, 0)
        total = total - v if v < prev else total + v
        prev = max(prev, v)
    return total


def is_allcaps_titleish(para):
    """Short single-thought line in all caps: half-titles, 'THE END.', etc."""
    letters = re.sub(r"[^A-Za-z]", "", para)
    return (bool(letters) and letters.isupper()
            and len(para) <= 60 and len(para.split()) <= 8)


SMALL_WORDS = {"a", "an", "and", "at", "but", "by", "for", "in", "nor",
               "of", "on", "or", "the", "to", "with"}


def titlecase(label):
    """ALL-CAPS heading label -> title case with lowercased small words."""
    words = label.lower().split()
    out = [w if (i not in (0, len(words) - 1) and w in SMALL_WORDS) else w.capitalize()
           for i, w in enumerate(words)]
    return " ".join(out)


def find_headings(paragraphs, flush_single, book_title=None):
    """Return list of (index, kind, label) for heading paragraphs.

    book_title: for the all-caps-titles fallback (story collections), a
    flush caps line equal to the book's own title (half-title page) is not a
    story heading and is skipped.
    """
    labeled = []
    for i, p in enumerate(paragraphs):
        m = LABELED_HEADING_RE.match(p)
        if m:
            labeled.append((i, m.group(1).upper(), m.group(2).upper()))
    if len(labeled) >= 3:
        return labeled
    # fallback: bare roman numerals on their own line
    romans = [(i, "CHAPTER", ROMAN_ALONE_RE.match(p).group(1))
              for i, p in enumerate(paragraphs)
              if ROMAN_ALONE_RE.match(p) and len(p) > 1]
    if len(romans) >= 3:
        return romans
    # fallback: word-ordinal "THE <ORDINAL> BOOK/PART" headings (e.g. Marcus
    # Aurelius). Normalized to numeric labels in reading order.
    ordinal_books = []
    for i, p in enumerate(paragraphs):
        m = ORDINAL_BOOK_RE.match(p)
        if m:
            ordinal_books.append((i, m.group(2).upper(), str(WORD_ORDINALS[m.group(1).upper()])))
    if len(ordinal_books) >= 3:
        return ordinal_books
    # fallback: all-caps story titles (collections). Only single flush-left
    # source lines qualify — indented caps lines are in-story display matter.
    title_cf = re.sub(r"[^a-z0-9 ]", "", (book_title or "").casefold()).strip()
    caps = []
    for i, p in enumerate(paragraphs):
        if not (flush_single[i] and is_allcaps_titleish(p)):
            continue
        label_cf = re.sub(r"[^a-z0-9 ]", "", p.casefold()).strip()
        if title_cf and label_cf == title_cf:
            continue  # the book's own half-title, not a story
        caps.append((i, "TITLE", p.rstrip(".")))
    return caps if len(caps) >= 2 else []


def clean_chapter_body(paras):
    """Trim inter-volume title pages / END OF VOL blocks from a chapter body."""
    # truncate at an END OF VOL / end-matter marker: everything after is
    # divider or editorial back-matter, not chapter prose.
    for i, p in enumerate(paras):
        if END_OF_VOL_RE.match(p) or END_MATTER_RE.match(p):
            paras = paras[:i]
            break
    # trim a trailing "THE END."
    while paras and THE_END_RE.match(paras[-1]):
        paras = paras[:-1]
    # trim a trailing half-title block (run of >= 2 consecutive all-caps title
    # paragraphs directly before the next heading). A single trailing all-caps
    # paragraph is kept — it may be real content (e.g. a letter signature).
    run = 0
    while run < len(paras) and is_allcaps_titleish(paras[-1 - run]):
        run += 1
    if run >= 2:
        paras = paras[:len(paras) - run]
    return paras


def chapterize(paragraphs, flush_single, book_title=None):
    """Split paragraphs into chapters. Returns list of (title, [paragraphs]).

    Front matter (everything before the first heading) is excluded. Chapters
    are flattened in reading order; when the same heading label repeats
    (volume-restarted numbering), chapters of that kind are renumbered
    continuously (Chapter 1..N).
    """
    headings = find_headings(paragraphs, flush_single, book_title)
    if not headings:
        raise SystemExit("chapterize: no chapter headings found; adjust heuristics")

    chapters = []
    for n, (idx, kind, label) in enumerate(headings):
        end = headings[n + 1][0] if n + 1 < len(headings) else len(paragraphs)
        body = clean_chapter_body(paragraphs[idx + 1:end])
        if not body:
            continue
        # Drop table-of-contents pseudo-chapters: a heading whose "body" is just
        # the TOC's next entries is a handful of words; real chapters run to
        # hundreds+. Only filter when it leaves enough real chapters, so short
        # genuinely-structured works are not gutted.
        if est_tokens("\n\n".join(body)) < MIN_CHAPTER_TOKENS:
            continue
        chapters.append({"kind": kind, "label": label, "paras": body})

    # renumber duplicated labels (e.g. CHAPTER I appears once per volume)
    seen = {}
    for c in chapters:
        seen.setdefault((c["kind"], c["label"]), 0)
        seen[(c["kind"], c["label"])] += 1
    dup_kinds = set(k for (k, l), n in seen.items() if n > 1)

    counters = {}
    result = []
    for c in chapters:
        kind_word = c["kind"].capitalize()
        if c["kind"] in dup_kinds:
            counters[c["kind"]] = counters.get(c["kind"], 0) + 1
            title = "%s %d" % (kind_word, counters[c["kind"]])
        elif c["kind"] == "TITLE":
            title = titlecase(c["label"])
        else:
            title = "%s %s" % (kind_word, c["label"])
        result.append((title, c["paras"]))
    return result


# ---------------------------------------------------------------- chunk

def est_tokens(text):
    """1 token ~= 0.75 words."""
    words = len(text.split())
    return max(1, int(round(words / 0.75)))


def chunk_chapter(book_id, ch, paras):
    """Greedy ~400-token chunks at paragraph edges, ~50-token overlap.

    Never crosses the chapter boundary. Paragraphs are never split (this
    guarantees passage-ID uniqueness: id = first-paragraph index).
    Returns passage dicts with offsets into "\n\n".join(paras).
    """
    # paragraph char offsets in the chapter text string
    offsets = []
    pos = 0
    for p in paras:
        offsets.append((pos, pos + len(p)))
        pos += len(p) + 2  # "\n\n"
    ptok = [est_tokens(p) for p in paras]

    passages = []
    start = 0
    n = len(paras)
    while start < n:
        total = 0
        end = start
        while end < n and (end == start or total + ptok[end] <= TARGET_TOKENS + OVERLAP_TOKENS):
            total += ptok[end]
            end += 1
            if total >= TARGET_TOKENS:
                break
        text = "\n\n".join(paras[start:end])
        passages.append({
            "id": "%s:%d:%d" % (book_id, ch, start),
            "book_id": book_id,
            "ch": ch,
            "para": start,
            "text": text,
            "char_start": offsets[start][0],
            "char_end": offsets[end - 1][1],
            "token_count": est_tokens(text),
        })
        if end >= n:
            break
        # overlap: back up over trailing paragraphs totaling >= OVERLAP_TOKENS
        overlap = 0
        nxt = end
        while nxt - 1 > start and overlap + ptok[nxt - 1] <= MAX_OVERLAP_TOKENS:
            overlap += ptok[nxt - 1]
            nxt -= 1
            if overlap >= OVERLAP_TOKENS:
                break
        if nxt <= start:  # always make progress
            nxt = start + 1
        start = nxt
    return passages


# ---------------------------------------------------------------- embed

def embed_passages(passages):
    """Batch-embed with Voyage AI. Mutates passages in place (adds "embedding")."""
    key = os.environ.get("VOYAGE_API_KEY")
    if not key:
        print("embed: VOYAGE_API_KEY not set — skipping embeddings "
              "(retrieval will be BM25-only until re-run with a key).")
        return False
    headers = {"Authorization": "Bearer %s" % key, "Content-Type": "application/json"}
    for i in range(0, len(passages), VOYAGE_BATCH):
        batch = passages[i:i + VOYAGE_BATCH]
        payload = {
            "input": [p["text"] for p in batch],
            "model": VOYAGE_MODEL,
            "input_type": "document",
            "output_dimension": VOYAGE_DIMS,
        }
        delay = 2.0
        for attempt in range(6):
            resp = requests.post(VOYAGE_URL, headers=headers, json=payload, timeout=120)
            if resp.status_code == 429:
                print("embed: 429, retrying in %.0fs" % delay)
                time.sleep(delay)
                delay *= 2
                continue
            resp.raise_for_status()
            break
        else:
            raise SystemExit("embed: rate-limited after retries")
        data = resp.json()["data"]
        for p, item in zip(batch, data):
            p["embedding"] = item["embedding"]
        print("embed: %d/%d" % (min(i + VOYAGE_BATCH, len(passages)), len(passages)))
    return True


# ---------------------------------------------------------------- emit

def sql_str(s):
    if s is None:
        return "NULL"
    return "'" + s.replace("'", "''") + "'"


def emit(book, chapters, passages, out_dir, seed_sql):
    os.makedirs(os.path.join(out_dir, "chapters"), exist_ok=True)

    with open(os.path.join(out_dir, "book.json"), "w", encoding="utf-8") as f:
        json.dump(book, f, ensure_ascii=False, indent=2)
        f.write("\n")

    for ch, (title, text) in enumerate(chapters):
        with open(os.path.join(out_dir, "chapters", "%d.json" % ch), "w", encoding="utf-8") as f:
            json.dump({"bookID": book["bookID"], "ch": ch, "title": title, "text": text},
                      f, ensure_ascii=False, indent=2)
            f.write("\n")

    with open(os.path.join(out_dir, "passages.jsonl"), "w", encoding="utf-8") as f:
        for p in passages:
            f.write(json.dumps(p, ensure_ascii=False) + "\n")

    if seed_sql:
        emit_seed_sql(book, chapters, passages, os.path.join(out_dir, "seed.sql"))


def emit_seed_sql(book, chapters, passages, path):
    with open(path, "w", encoding="utf-8") as f:
        f.write("-- generated by pipeline/ingest.py for %s\nbegin;\n\n" % book["bookID"])
        f.write(
            "insert into editions (id, title, author, translator, source, source_url, "
            "license, license_note, chapter_count) values (%s, %s, %s, %s, %s, %s, %s, %s, %d)\n"
            "on conflict (id) do nothing;\n\n" % (
                sql_str(book["bookID"]), sql_str(book["title"]), sql_str(book["author"]),
                sql_str(book["translator"]), sql_str(book["source"]),
                sql_str(book["sourceUrl"]), sql_str(book["license"]),
                sql_str(book["licenseNote"]), book["chapterCount"]))
        for ch, (title, text) in enumerate(chapters):
            f.write(
                "insert into chapters (book_id, ch, title, text, word_count) "
                "values (%s, %d, %s, %s, %d)\non conflict (book_id, ch) do nothing;\n" % (
                    sql_str(book["bookID"]), ch, sql_str(title), sql_str(text),
                    len(text.split())))
        f.write("\n")
        for p in passages:
            emb = p.get("embedding")
            emb_sql = "'[" + ",".join("%.7g" % v for v in emb) + "]'" if emb else "NULL"
            f.write(
                "insert into passages (id, book_id, ch, para, text, char_start, char_end, "
                "token_count, embedding) values (%s, %s, %d, %d, %s, %d, %d, %d, %s)\n"
                "on conflict (id) do nothing;\n" % (
                    sql_str(p["id"]), sql_str(p["book_id"]), p["ch"], p["para"],
                    sql_str(p["text"]), p["char_start"], p["char_end"],
                    p["token_count"], emb_sql))
        f.write("\ncommit;\n")


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description="The Seminar text ingestion pipeline")
    ap.add_argument("--url", required=True, help="Gutenberg plain-text (.txt) URL")
    ap.add_argument("--book-id", required=True, dest="book_id")
    ap.add_argument("--title", required=True)
    ap.add_argument("--author", required=True)
    ap.add_argument("--translator", default=None)
    ap.add_argument("--license-note", dest="license_note", default=None,
                    help="editions.license_note; defaults to a PG public-domain note")
    ap.add_argument("--no-embed", action="store_true", help="skip Voyage embeddings")
    ap.add_argument("--seed-sql", action="store_true", help="also emit seed.sql")
    args = ap.parse_args()

    raw = fetch(args.url)
    body = strip_pg_boilerplate(raw)
    paragraphs, flush_single = normalize_to_paragraphs(body)
    print("normalize: %d paragraphs (front matter included)" % len(paragraphs))

    chapter_list = chapterize(paragraphs, flush_single, args.title)
    chapters = [(title, "\n\n".join(paras)) for title, paras in chapter_list]
    print("chapterize: %d chapters: %s ... %s" % (
        len(chapters), chapters[0][0], chapters[-1][0]))

    passages = []
    for ch, (title, paras) in enumerate(chapter_list):
        passages.extend(chunk_chapter(args.book_id, ch, paras))
    print("chunk: %d passages" % len(passages))

    if args.no_embed:
        print("embed: skipped (--no-embed)")
    else:
        embed_passages(passages)

    license_note = args.license_note
    if license_note is None:
        m = re.search(r"/epub/(\d+)/", args.url)
        pg = " (PG #%s)" % m.group(1) if m else ""
        license_note = ("Public domain in the US. Source: Project Gutenberg%s; "
                        "PG boilerplate stripped per docs/LICENSING.md." % pg)

    book = {
        "bookID": args.book_id,
        "title": args.title,
        "author": args.author,
        "translator": args.translator,
        "source": "gutenberg",
        "sourceUrl": args.url,
        "license": "public-domain-us",
        "licenseNote": license_note,
        "chapterCount": len(chapters),
    }

    out_dir = os.path.join(OUTPUT_DIR, args.book_id)
    emit(book, chapters, passages, out_dir, args.seed_sql)
    print("emit: wrote %s (book.json, chapters/*.json, passages.jsonl%s)" % (
        out_dir, ", seed.sql" if args.seed_sql else ""))


if __name__ == "__main__":
    main()
