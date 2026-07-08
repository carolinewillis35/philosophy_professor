#!/usr/bin/env python3
"""Sanity-check pipeline output against the CONTRACTS §2/§8 invariants.

Usage:
  python3 verify.py <bookID> [--chapters N] [--first-chapter-prefix "..."]
                    [--min-passages N] [--max-passages N]

Asserts:
  - book.json chapterCount matches chapters/*.json count (and --chapters if given)
  - every passage id == "{bookID}:{ch}:{para}"
  - chapter_text[char_start:char_end] == passage text (exact offset space)
  - no passage crosses a chapter boundary (0 <= char_start < char_end <= len)
  - within each chapter, para indices strictly increase and passage ids unique
  - passages cover each chapter from its first to its last character
  - passages.jsonl line count within the expected range
  - optional: a given chapter's text starts with an expected prefix
"""

import argparse
import json
import os
import sys

PIPELINE_DIR = os.path.dirname(os.path.abspath(__file__))

checks = {"passed": 0}


def ok(cond, msg):
    if not cond:
        print("FAIL: %s" % msg)
        sys.exit(1)
    checks["passed"] += 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("book_id")
    ap.add_argument("--chapters", type=int, default=None)
    ap.add_argument("--first-chapter", type=int, default=None,
                    help="chapter index for --first-chapter-prefix")
    ap.add_argument("--first-chapter-prefix", default=None)
    ap.add_argument("--min-passages", type=int, default=None)
    ap.add_argument("--max-passages", type=int, default=None)
    args = ap.parse_args()

    out = os.path.join(PIPELINE_DIR, "output", args.book_id)
    with open(os.path.join(out, "book.json"), encoding="utf-8") as f:
        book = json.load(f)
    ok(book["bookID"] == args.book_id, "book.json bookID mismatch")

    ch_dir = os.path.join(out, "chapters")
    ch_files = sorted(int(n[:-5]) for n in os.listdir(ch_dir) if n.endswith(".json"))
    n_ch = len(ch_files)
    ok(ch_files == list(range(n_ch)), "chapter files not contiguous 0..%d" % (n_ch - 1))
    ok(book["chapterCount"] == n_ch,
       "chapterCount %d != %d chapter files" % (book["chapterCount"], n_ch))
    if args.chapters is not None:
        ok(n_ch == args.chapters, "expected %d chapters, got %d" % (args.chapters, n_ch))

    chapters = {}
    for ch in ch_files:
        with open(os.path.join(ch_dir, "%d.json" % ch), encoding="utf-8") as f:
            d = json.load(f)
        ok(d["bookID"] == args.book_id and d["ch"] == ch, "chapter %d metadata mismatch" % ch)
        ok(isinstance(d["text"], str) and len(d["text"]) > 0, "chapter %d empty" % ch)
        ok("\n\n\n" not in d["text"], "chapter %d has >2 consecutive newlines" % ch)
        chapters[ch] = d

    if args.first_chapter_prefix is not None:
        ch = args.first_chapter if args.first_chapter is not None else 0
        ok(chapters[ch]["text"].startswith(args.first_chapter_prefix),
           "chapter %d does not start with %r (got %r)" % (
               ch, args.first_chapter_prefix, chapters[ch]["text"][:60]))

    with open(os.path.join(out, "passages.jsonl"), encoding="utf-8") as f:
        passages = [json.loads(line) for line in f if line.strip()]
    ok(len(passages) > 0, "no passages")
    if args.min_passages is not None:
        ok(len(passages) >= args.min_passages,
           "only %d passages (expected >= %d)" % (len(passages), args.min_passages))
    if args.max_passages is not None:
        ok(len(passages) <= args.max_passages,
           "%d passages (expected <= %d)" % (len(passages), args.max_passages))

    seen_ids = set()
    per_ch = {}
    for p in passages:
        pid = p["id"]
        ok(pid == "%s:%d:%d" % (p["book_id"], p["ch"], p["para"]),
           "passage id %r inconsistent with fields" % pid)
        ok(p["book_id"] == args.book_id, "passage %s wrong book_id" % pid)
        ok(pid not in seen_ids, "duplicate passage id %s" % pid)
        seen_ids.add(pid)
        ok(p["ch"] in chapters, "passage %s references missing chapter" % pid)
        text = chapters[p["ch"]]["text"]
        ok(0 <= p["char_start"] < p["char_end"] <= len(text),
           "passage %s span [%d,%d) outside chapter (len %d)" % (
               pid, p["char_start"], p["char_end"], len(text)))
        ok(text[p["char_start"]:p["char_end"]] == p["text"],
           "passage %s text != chapter_text[char_start:char_end]" % pid)
        ok(p["token_count"] > 0, "passage %s token_count <= 0" % pid)
        if "embedding" in p:
            ok(isinstance(p["embedding"], list) and len(p["embedding"]) == 1024,
               "passage %s embedding not 1024 floats" % pid)
        per_ch.setdefault(p["ch"], []).append(p)

    ok(set(per_ch) == set(chapters), "some chapters have no passages")
    for ch, plist in per_ch.items():
        paras = [p["para"] for p in plist]
        ok(paras == sorted(paras) and len(set(paras)) == len(paras),
           "chapter %d para indices not strictly increasing" % ch)
        ok(plist[0]["char_start"] == 0, "chapter %d not covered from char 0" % ch)
        ok(max(p["char_end"] for p in plist) == len(chapters[ch]["text"]),
           "chapter %d not covered to final char" % ch)
        # consecutive passages must overlap or at least be contiguous
        # (+2 allows the "\n\n" paragraph separator between contiguous chunks)
        for a, b in zip(plist, plist[1:]):
            ok(b["char_start"] <= a["char_end"] + 2,
               "gap between %s and %s" % (a["id"], b["id"]))

    print("verify: OK — %d chapters, %d passages, %d checks passed" % (
        len(chapters), len(passages), checks["passed"]))


if __name__ == "__main__":
    main()
