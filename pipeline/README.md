# The Seminar — text pipeline

Turns a public-domain plain-text source (Project Gutenberg `.txt`) into the
normalized chapter/passage artifacts defined in `docs/CONTRACTS.md` §2 and §8.

Python 3.9 compatible. Dependencies: stdlib + `requests` (see
`requirements.txt`).

## Usage

```sh
pip3 install -r requirements.txt

python3 ingest.py \
  --url https://www.gutenberg.org/cache/epub/41445/pg41445.txt \
  --book-id frankenstein-1818 \
  --title "Frankenstein; or, The Modern Prometheus (1818)" \
  --author "Mary Wollstonecraft Shelley" \
  [--translator "..."] [--license-note "..."] [--no-embed] [--seed-sql]

python3 verify.py frankenstein-1818 --chapters 27 \
  --first-chapter 4 --first-chapter-prefix "I am by birth a Genevese" \
  --min-passages 250 --max-passages 450
```

Outputs to `pipeline/output/<bookID>/`:

- `book.json` — edition metadata (`bookID`, `title`, `author`, `translator`,
  `source`, `sourceUrl`, `license`, `licenseNote`, `chapterCount`)
- `chapters/<ch>.json` — `{bookID, ch, title, text}`; `text` is paragraphs
  joined with `\n\n` and is **the char-offset space** for all passage spans
- `passages.jsonl` — one passage per line, matching the `passages` table
  columns (`embedding` key omitted when embeddings are skipped)
- `seed.sql` (with `--seed-sql`) — `INSERT ... ON CONFLICT DO NOTHING` for
  `editions`, `chapters`, `passages`, wrapped in a transaction; embeddings as
  pgvector literals `'[...]'` or `NULL`

Downloads are cached in `pipeline/.cache/` (keyed by URL hash); delete the
cache file to force a re-fetch.

## Pipeline stages

1. **Fetch** — download (or read from cache) the Gutenberg plain-text file.
2. **Normalize** — strip PG header/footer (`*** START/END OF ... ***`
   markers; required by `docs/LICENSING.md`), normalize line endings, unwrap
   hard-wrapped lines into blank-line-separated paragraphs, drop transcriber
   notes and decorative `* * *` separators, strip `_italic_` underscores,
   keep curly quotes, collapse extra blank lines.
3. **Chapterize** — split on heading paragraphs (`LETTER I.`, `CHAPTER I.`,
   `Chapter 1`, bare roman numerals, or all-caps story titles as fallbacks).
   Front matter before the first heading (title page, preface) is excluded.
   Inter-volume title pages / `END OF VOL.` blocks / trailing `THE END.` are
   trimmed. When heading labels repeat (numbering restarts per volume),
   chapters are renumbered continuously in reading order.
4. **Chunk** — ~400-token chunks (1 token ≈ 0.75 words), ~50-token overlap,
   never crossing a chapter, boundaries always at paragraph edges (a
   paragraph is never split, which guarantees passage-ID uniqueness). Passage
   id = `{bookID}:{ch}:{para}` where `para` is the chunk's first paragraph
   index; `char_start`/`char_end` index into the chapter `text` string.
   Overlap is skipped when the trailing paragraph alone exceeds ~200 est.
   tokens (chunks are then contiguous at the paragraph boundary).
5. **Embed** — Voyage AI `voyage-3.5` (1024 dims, cosine, `input_type:
   "document"`), batches of 128, exponential backoff on 429. Requires
   `VOYAGE_API_KEY` in the environment; if unset (or `--no-embed`), passages
   are written without embeddings and retrieval degrades to BM25-only.
   Re-run with the key set to produce embedded output.
6. **Emit** — write the artifacts above.

## Invariants (enforced by `verify.py`)

- `book.json` `chapterCount` == number of `chapters/<ch>.json` files,
  contiguous from 0
- passage `id` == `"{book_id}:{ch}:{para}"`, unique
- `chapter_text[char_start:char_end] == passage.text` exactly
- no passage crosses a chapter boundary
- `para` indices strictly increasing within a chapter
- passages cover every chapter from first to last character; consecutive
  passages overlap or are contiguous (≤ 2-char `\n\n` gap)
- embeddings, when present, are 1024 floats

Run `verify.py` after every ingest; iterate on the chapterizer heuristics
until the expected chapter count and openings check out.

## Adding a new book

1. Clear it against `docs/LICENSING.md` (work — and translation, if any —
   PD in the US; Gutenberg or Standard Ebooks source). Record the result in
   the `--license-note`.
2. Find the Gutenberg plain-text URL
   (`https://www.gutenberg.org/cache/epub/<n>/pg<n>.txt`).
3. Pick a `bookID` slug (`docs/CONTRACTS.md` §2), run `ingest.py`.
4. Check the reported chapter count against the actual book structure. If it
   is wrong, inspect the source's heading conventions and extend
   `LABELED_HEADING_RE` / `find_headings` / `clean_chapter_body`.
5. Run `verify.py` with the expected `--chapters` count and a
   `--first-chapter-prefix` spot check.
6. Apply `seed.sql` via `psql` / `supabase db push`.

## Current editions

- `frankenstein-1818` — PG #41445 (1818 first-edition text). 27 chapters in
  flattened reading order: ch 0–3 = Letters I–IV, ch 4–26 = Chapters 1–23
  (three volumes, renumbered continuously). Fallback if #41445 is down:
  PG #84 (1831 revised text, 4 letters + 24 chapters = 28 chapters) — keep
  the same bookID but set the license note to "1831 revised text; PG #84".
- `dubliners` — PG #2814 (Joyce, 1914). 15 chapters = the 15 stories in
  order, The Sisters (ch 0) through The Dead (ch 14). Uses the all-caps
  story-title fallback of the chapterizer: headings must be single
  flush-left caps lines (indented caps lines — newspaper headlines, the
  ballad title in "Ivy Day" — are in-story matter), and the book's own
  half-title caps line is skipped.
