# Corpus sources — reproducing the ingested texts

`pipeline/output/` is gitignored (regenerable). Run these exact commands from
`pipeline/` to rebuild the corpus the courses reference. All are
public-domain-US (see `docs/LICENSING.md`); `--no-embed` keeps retrieval
BM25-only (set `VOYAGE_API_KEY` and drop the flag for hybrid embeddings).

```sh
# Plato, Republic (Jowett) — 10 books, 510 passages
python3 ingest.py --url https://www.gutenberg.org/cache/epub/1497/pg1497.txt \
  --book-id republic-jowett --title "The Republic" --author "Plato" \
  --translator "Benjamin Jowett" --no-embed --seed-sql

# Marcus Aurelius, Meditations (Casaubon) — 12 books, 243 passages
python3 ingest.py --url https://www.gutenberg.org/cache/epub/2680/pg2680.txt \
  --book-id marcus-meditations --title "Meditations" --author "Marcus Aurelius" \
  --translator "Meric Casaubon" \
  --license-note "Marcus Aurelius (2nd c.); Casaubon translation 1634 — public domain (US)." \
  --no-embed --seed-sql

# J.S. Mill, On Liberty — 5 chapters, 127 passages
python3 ingest.py --url https://www.gutenberg.org/cache/epub/34901/pg34901.txt \
  --book-id mill-on-liberty --title "On Liberty" --author "John Stuart Mill" \
  --license-note "Mill d.1873; On Liberty first published 1859 — public domain (US)." \
  --no-embed --seed-sql

# Descartes, Discourse on the Method (Veitch) — 6 parts, 60 passages
python3 ingest.py --url https://www.gutenberg.org/cache/epub/59/pg59.txt \
  --book-id descartes-discourse --title "Discourse on the Method" --author "René Descartes" \
  --translator "John Veitch" \
  --license-note "Descartes d.1650; Veitch translation pre-1894 — public domain (US)." \
  --no-embed --seed-sql
```

## Chapterizer notes (per-text quirks handled in `ingest.py`)

- **Table-of-contents artifacts** — a heading whose body is shorter than
  `MIN_CHAPTER_TOKENS` (120) is dropped (Mill's TOC listed its chapters as
  `CHAPTER I…V`, which otherwise produced phantom chapters).
- **Word-ordinal books** — `THE FIRST BOOK … THE TWELFTH BOOK` (Marcus) are
  matched by `ORDINAL_BOOK_RE`, anchored on the leading `THE` so the bare
  synopsis (`FIRST BOOK`) doesn't double them.
- **Trailing end-matter** — `APPENDIX` / `GLOSSARY` / `NOTES` / `INDEX`
  heading lines truncate the final chapter body (Long's Marcus edition
  appends a biographical glossary after Book 12).

## Deferred

- **Hume, *Enquiry Concerning Human Understanding*** (PG #9662): sections are
  `SECTION I…XII` with `PART I/II` subsections. Needs the chapterizer to treat
  `SECTION` as the chapter delimiter while suppressing `PART` (which currently
  matches `LABELED_HEADING_RE` and would fragment sections). Not yet done.
