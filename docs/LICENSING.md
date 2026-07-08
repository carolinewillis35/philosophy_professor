# Text licensing checklist — The Academy

Every edition ingested MUST pass this checklist before shipping. Record the
result in `editions.license` / `editions.license_note`.

## Checklist (per edition, not per work)

- [ ] Underlying work published before **January 1, 1930** (PD in the US as of 2026)?
- [ ] If a translation: was the **translation itself** published before Jan 1, 1930?
      (The translation is a separate copyrightable work.)
- [ ] Source is Project Gutenberg or Standard Ebooks (US-cleared)?
- [ ] Gutenberg boilerplate/header/footer stripped before ingestion?
      (The PG license applies to their trademark/boilerplate, not the text.)
- [ ] Translator's editorial apparatus (introductions, analyses, notes) either
      PD alongside the translation or excluded by chapterization? (Jowett's
      Republic Introduction is PD but excluded as front matter anyway.)
- [ ] `source_url` recorded; `license = 'public-domain-us'`; note edition/translator.

## Known-good translators/editions (pre-1930)

- **Benjamin Jowett** — Plato (d. 1893; 3rd ed. 1892) ✅
- **W.D. Ross** — Aristotle *Nicomachean Ethics* (1925, Oxford) ✅ (verify per-volume; Ross d. 1971 but publication pre-1930 governs US PD)
- **George Long** — Marcus Aurelius *Meditations* (1862), Epictetus ✅
- **John Veitch** — Descartes *Meditations*, *Discourse* (1850s) ✅
- **Elizabeth Haldane & G.R.T. Ross** — Descartes (1911) ✅
- **Hume, Mill, Berkeley, Locke, William James, early Russell** — wrote in English; pre-1930 works PD ✅ (Russell: *Problems of Philosophy* 1912 ✅; anything 1930+ ❌)
- **Thomas Common** — Nietzsche *Thus Spake Zarathustra* (PG #1998) ✅
- **Helen Zimmern** — Nietzsche *Beyond Good and Evil* (PG #4363) ✅
- **Anthony Ludovici** — Nietzsche (various, pre-1930) ✅ (verify per-volume)
- **T.K. Abbott** — Kant *Groundwork/Critique of Practical Reason* ✅;
  **J.M.D. Meiklejohn** / **Norman Kemp Smith** — Kant CPR: Meiklejohn (1855) ✅, Kemp Smith (1929) ✅ verify edition

## Known-NOT-usable

- **Walter Kaufmann** (all Nietzsche) ❌ — scope calls this out explicitly
- **G.M.A. Grube, Allan Bloom, C.D.C. Reeve** (Plato) ❌
- **Terence Irwin, Roger Crisp** (Aristotle) ❌
- **Gregory Hays** (Marcus Aurelius) ❌
- **John Cottingham** (Descartes) ❌
- Any translation first published 1930+ ❌
- Contemporary philosophy (Rawls, Nozick, Searle, Nagel, Chalmers…): **discussion
  only, no ingestion, no excerpting** — enforced mechanically by the
  RAG-only-quote contract. Thought experiments PARAPHRASE (Chinese Room, Veil
  of Ignorance, Experience Machine are describable ideas; the prose is not ours
  to quote).

## Current editions

| bookID | source | status |
|---|---|---|
| `republic-jowett` | Project Gutenberg #1497 (Jowett tr., d. 1893) | ✅ PD-US — **ingested** (10 books, 510 passages) |
| `apology-jowett` | Project Gutenberg #1656 (Jowett tr.) | ✅ PD-US — planned (M1, *The Examined Life*) |
| `euthyphro-jowett` | Project Gutenberg #1642 (Jowett tr.) | ✅ PD-US — planned |
| `meditations-descartes-veitch` | Project Gutenberg #59 (Veitch tr., 1850s) | ✅ PD-US — planned (V1, rediscovery: the cogito) |
| `enquiry-hume` | Project Gutenberg #9662 (Hume, 1748, English original) | ✅ PD-US — planned (V1, problem of induction) |
| `nicomachean-ethics-ross` | Wikisource/PG (Ross tr., 1925) | ⚠️ verify source text cleanliness — planned (V1, Bede) |
| `zarathustra-common` | Project Gutenberg #1998 (Common tr.) | ✅ PD-US — planned (V1, Lindqvist) |
| `beyond-good-and-evil-zimmern` | Project Gutenberg #4363 (Zimmern tr.) | ✅ PD-US — planned (V1, Lindqvist) |
| `utilitarianism-mill` | Project Gutenberg #11224 (Mill, 1863) | ✅ PD-US — planned |
| `problems-of-philosophy-russell` | Project Gutenberg #5827 (Russell, 1912) | ✅ PD-US — planned (Whitmore, *Knowledge & Its Limits*) |
