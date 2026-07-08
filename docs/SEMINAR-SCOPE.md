# SCOPE DOCUMENT — "THE SEMINAR" (working title)
## An AI literature department in your pocket: professors, syllabi, seminars, and essays with real feedback

> Scope tiers: **[MVP]**, **[V1]**, **[V2]**, **[STRETCH]**; open decisions flagged **[DECISION]** (resolved in DECISIONS.md). The product bet: people don't want "chat about books" — they want the *structure and standards* of a great class (a syllabus, a demanding professor, deadlines-ish, being called on) with none of the tuition or scheduling. Structure is the product; the LLM is the faculty.

---

## 1. Product vision

**One-liner:** Enroll in real literature courses — an 8-week seminar on the Russian novel, a close-reading bootcamp, a Modernism survey — taught by distinct AI professors who lecture, run Socratic discussion on what *you* actually read, assign essays, and grade them against a rubric.

**Why this wins:** ChatGPT-as-tutor is formless; users drift and quit. Great courses have *pedagogical architecture*: sequencing, accountability, a professor with a point of view who pushes back. Meanwhile, the underlying content (the books) is largely **public domain** — Project Gutenberg / Standard Ebooks give us full legal texts of nearly the entire pre-1929 canon, which means the app can quote, excerpt, and assign passages freely and ground every discussion in the actual text (RAG), not vibes.

**Target users:** (a) adults who miss college seminars ("I want to *actually* read Middlemarch this time, with someone making me think"); (b) autodidacts working through the canon; (c) writers studying craft; (d) book clubs wanting a shared professor. Explicitly **not** targeting students seeking homework answers — design against it (§7).

**Platform:** iOS SwiftUI primary; the domain layer (courses, personas, session engine) designed API-first so a web app can follow. iOS-only MVP.

---

## 2. The faculty (persona system)

Each professor is a **Persona**: a rich system-prompt document + voice/style parameters + pedagogical behavior settings + a portrait & bio. Personas are data (versioned markdown + JSON), not code. All are fictional characters — no real academics imitated.

### 2.1 Launch faculty [MVP: 3 professors; V1: 6–8]

1. **Prof. Eleanor Voss — the Formalist Close Reader** [MVP]. Teaches you to slow down to the sentence. Demanding, precise, dry wit. Signature moves: "Read me the sentence again. Which word is doing the work?"; refuses thematic hand-waving until the passage is earned. Courses: *Close Reading Bootcamp*, *The Art of the Sentence*.
2. **Prof. Dmitri Arkady — the Russian-Soul Romantic** [MVP]. Big-hearted, digressive, quotes from memory, connects novels to how you should live. Signature: ends sessions with an unanswerable question. Courses: *The Russian Novel* (Dostoevsky, Tolstoy, Chekhov, Gogol), *Suffering & Grace*.
3. **Prof. June Calloway — the Contemporary Craft Critic** [MVP]. Sharp, funny, MFA-workshop energy; reads like a writer. Signature: "What is this scene *doing*? Cut it and see what breaks." Courses: *How Novels Work*, *Autofiction & the Self on the Page* (public-domain anchors + discussion of modern works without reproducing them — see §7).
4. **Prof. Theodora Blackwood — the Theorist** [V1]. Feminist/psychoanalytic/Marxist lenses as tools, taught accessibly. Courses: *Ways of Reading: Five Lenses*, *Madwomen in the Attic*.
5. **Prof. Sam Okafor — the Classicist** [V1]. Epic, tragedy, myth; genealogies of everything. Courses: *Homer to Joyce*, *Greek Tragedy & Why We Still Flinch*.
6. **Prof. Marguerite Duval — the Modernist** [V1]. Woolf, Proust (public domain in translation — verify per translation), Joyce, Mansfield. Courses: *Stream of Consciousness*, *1922: The Year Everything Broke*.
7. **The Poet-in-Residence** [V2] — poetry-only faculty; scansion, form, memorization challenges.
8. **Guest lecturers** [V2] — one-off personas for single sessions inside courses (a translator persona for the Constance Garnett problem; a historian for context weeks).

### 2.2 Persona engineering

- Persona doc structure: `identity & backstory · intellectual commitments · speech patterns w/ 10+ exemplar exchanges · pedagogical behaviors (when to praise, push, redirect) · red lines (never summarizes assigned reading before the student attempts; never invents quotations — must cite retrieved passage IDs) · course-specific context`.
- **Consistency across sessions:** persona doc + a rolling *relationship memory* (facts the professor "knows" about this student: name, goals, past insights, weaknesses — stored per enrollment, injected each session, capped ~800 tokens, LLM-summarized after each session).
- **Anti-hallucination contract:** any verbatim quotation must come from the RAG layer (passage IDs); the client renders quotes only from retrieved text, so a fabricated quote cannot render as a quote. Professors *may* paraphrase from general knowledge but the UI visually distinguishes sourced quotes (with book/chapter/line link) from paraphrase.

---

## 3. Courses & the syllabus engine

### 3.1 Course anatomy

See CONTRACTS.md §7 for the JSON schema. Courses are **authored content** (written with Claude's help at build time, then human-curated), not generated on the fly — this is what makes quality consistent and the catalog a real asset. Runtime generation personalizes *within* the authored structure.

**[MVP catalog: 4 courses]** Close Reading Bootcamp (3 wks, short texts — perfect first course), The Russian Novel (10 wks), How Novels Work (6 wks), a 1-book intensive: *Frankenstein in Two Weeks* (low commitment on-ramp). **[V1: 10–12 courses]** including *Middlemarch Slowly* (the "finally finish it" market is real), *Five Lenses*, *1922*, Shakespeare seminar. **[V2]** electives, poetry, custom courses (§5.6).

### 3.2 Session types (the pedagogical engine) [MVP unless noted]

1. **Lecture** — professor delivers the unit lecture: streamed, chunked into segments with inline text passages (side-by-side quote panels), periodic check-in questions ("Before I go on — what do you make of the narrator here?"). Not a wall of text: lecture segments are ~150–250 words each, advancing on user tap/answer. Feels like being talked to, not reading an article.
2. **Socratic seminar** — the crown jewel. Professor asks; student answers in free text; professor pushes back, asks for textual evidence ("Where? Show me the line"), offers the passage picker (retrieved candidates) if the student is lost, escalates depth. Engine enforces: professor speaks < 40% of tokens; never lets a vague answer pass twice; ends with the student summarizing their own position.
3. **Close-reading workshop** — one passage on screen, annotatable (tap-highlight words/phrases + margin notes); professor responds to *the student's annotations* ("You highlighted 'gray' three times — follow that").
4. **Office hours** — freeform chat with the professor, but in character and text-grounded; also where the student can ask "I fell behind, restructure my plan" (professor adjusts pacing — writes to Enrollment).
5. **Essay cycle** [MVP-lite: response papers; V1: full essays] — assignment → student writes (in-app editor with autosave, or paste) → **rubric-based grading**: professor returns margin comments anchored to sentences, a filled rubric with per-criterion scores + justification, 2 concrete revision directives, and an invitation to resubmit (revision tracked; grade can improve — teaches revision, the actual skill).
6. **Quiz / recall** [V1] — quick comprehension checks before seminars (5 questions, generated from the reading span, answered before the seminar unlocks — keeps discussions honest).
7. **Exam / defense** [V2] — end-of-course oral exam: professor cross-examines the student's own essays. Passing grants the course credential (§5.4).

### 3.3 Reading experience [MVP]

- Built-in reader for the assigned texts: typographically excellent, progress-synced to the syllabus ("You're 60% through this week's reading"), highlights & notes that flow into seminars automatically ("I saw you marked the Grand Inquisitor section — let's start there" — *this moment is the product demo*).
- Reading pace math: onboarding asks minutes/day → app schedules the unit reading into daily chunks with a nightly nudge. Pace switchable anytime; professor acknowledges pace changes in character.
- **[V1]** Audiobook mode: LibriVox public-domain audio synced by chapter (best-effort alignment), for commute reading.

---

## 4. Technical architecture

See CONTRACTS.md for the authoritative interfaces. SwiftUI client · Supabase (Postgres for catalog/enrollments/sessions, Storage for book/persona/course assets, Edge Functions as LLM orchestration — API key server-side, streaming over SSE) · Claude API (Sonnet 5 for seminars/lectures; Haiku 4.5 for quizzes/recall) · pgvector for passage embeddings (Voyage AI).

- Ingestion pipeline (build-time): Gutenberg/Standard Ebooks → normalized chapters → ~400-token passage chunks with stable IDs `bookID:ch:para` → embeddings → pgvector. Char offsets stored so client can highlight exact spans.
- Retrieval: hybrid (BM25 + vector) scoped to the course's texts, biased to the current unit's span; top-k passages injected with IDs; persona contract requires quoting by ID.
- Session engine: state machine per session type; state in Postgres; each turn assembles persona doc + course/unit context + relationship memory + session state + retrieved passages + last N turns (summarize older). Envelope-validated responses (CONTRACTS §5). Malformed → retry once → fallback plain reply.
- All texts verified public domain in the US; translations verified individually (Garnett: yes; newer: no). `license` field per Edition; checklist in docs/LICENSING.md.

---

## 5. Product features users will love

1. **The course catalog as a place** [MVP] — designed like a beautiful university bulletin: departments, course cards with reading lists and hour estimates, professor portraits (illustration style), "students also took."
2. **Cold-calling, opt-in** [V1] — professor occasionally opens a seminar with "You've been quiet about Kitty. What do you make of her?" based on what the user has *avoided*.
3. **Marginalia that matters** [MVP] — your highlights are course material (§3.3). Also: **professor marginalia mode** [V1]: after you finish a chapter, reveal the professor's own margin notes on that chapter.
4. **Transcripts & credentials** [V1] — transcript page (courses, grades, essay archive), shareable completion cards. [V2] "Defense passed" credential.
5. **Commonplace book** [V1] — every highlight collects into an exportable, beautifully typeset personal anthology (PDF/print).
6. **Custom course generator** [V2] — "I want 4 weeks on doomed marriages in 19th-c. novels": pipeline drafts a syllabus from the ingested library, assigns a fitting professor. Paid-tier flagship.
7. **Book club mode** [V2] — shared enrollment; professor moderates group seminars, cold-calls the lurker. (Realtime via Supabase channels.)
8. **Semester rhythm** [V1] — optional cohort start dates purely for motivation; solo-pace always available.
9. **"Why this book" trailers** [V1] — each course opens with the professor's 90-second pitch. Doubles as marketing content.

**Monetization:** free = Frankenstein intensive + office hours taste; subscription ($8–10/mo) = full catalog, essay grading, transcripts; custom courses & book club on the higher tier.

---

## 6. Build order

1. **M1 — Text foundation:** ingestion pipeline, books in pgvector, reader with highlights.
2. **M2 — Session engine:** Edge Function orchestration, JSON envelope contract, streaming client chat with quote panels. One professor (Voss), one session type (seminar) on one short text. *This milestone proves the product.*
3. **M3 — Course structure:** syllabus engine, lecture + close-reading sessions, progress/pacing, Close Reading Bootcamp end-to-end.
4. **M4 — MVP catalog:** 3 professors, 4 courses, response-paper cycle, onboarding, catalog UI. → TestFlight.
5. **M5 (V1):** full essay grading with margin comments, quizzes, relationship memory polish, commonplace book, transcripts, audiobook sync, 12-course catalog, cold-calling, semester cohorts.
6. **M6 (V2):** oral exams, custom courses, book club mode, poetry faculty.

## 7. Risks, ethics & guardrails

- **Homework-cheating misuse:** personas never write essays for students, never produce full summaries of assigned reading on demand ("Do the reading; then let's talk"), and grading requires the student's own draft. Marketing targets adult learners.
- **Copyright:** runtime quotation restricted to ingested public-domain texts. Contemporary works may be *discussed* (themes, craft) but never excerpted beyond fair-use-scale fragments; the RAG-only-quote contract enforces this mechanically.
- **Hallucinated scholarship:** professors cite critics only from a curated, ingested set of public-domain criticism [V1] or speak in their own voice; never invent citations (persona red line + envelope validation).
- **Persona drift over long enrollments** → relationship-memory summarization + persona doc re-injection every turn; automated persona-consistency evals (fixed probe set, run per prompt/model change).
- **Cost:** seminars are token-hungry; mitigate with turn summarization, Haiku for low-stakes surfaces, per-tier budgets.
- **Tone risk:** "demanding professor" must never become discouraging — personas include explicit calibration (push on ideas, warmth toward the person); user-settable intensity dial ("gentle / standard / rigorous").
