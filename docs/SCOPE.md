# SCOPE — "THE ACADEMY" (working title)
## A philosophy department built on the Seminar engine: Socratic to the bone, and a mirror that holds your own worldview accountable

> **Relationship to the Seminar engine:** This is not a new app from scratch. It reuses the platform built for The Seminar — the persona system (persona docs + relationship memory), the server-side session engine and its `{say, citations[], stateOps[], uiHints}` envelope, the RAG layer (chunked public-domain texts, stable passage IDs, quote-only-from-retrieval contract), the reader, courses/units/enrollments, the reader-profile pipeline, and the authored-spine-plus-generated-flesh philosophy. **Everything below is a delta:** a new corpus, a new faculty, new session types, and one flagship subsystem with no analog in any tutor on earth. (Platform reference: `SEMINAR-SCOPE.md`, `SEMINAR-SCOPE-ADDENDUM.md`, `CONTRACTS.md`.)
>
> Tiers: **[MVP]**, **[V1]**, **[V2]**. Decisions flagged **[DECISION]** (resolved flags live in `DECISIONS.md`).
>
> **Engagement addendum:** the daily loop, the growth ladder, and the seminar-to-life bridge ("Bring me an argument", the Daily Question, the Practice Wing) live in `SCOPE-ADDENDUM.md`, tiered **[E1]–[E3]** with build order E-M1→E-M4.

---

## 1. Why philosophy is the *cleanest* mapping of all

Philosophy has every property that made literature work, and two it doesn't. The corpus is the same *type* — text, and nearly the entire canon through the early 20th century is public domain (Plato, Aristotle, the Stoics, Aquinas, Descartes, Hume, Kant, Mill, Nietzsche, William James, early Russell). The close-read object is the **argument**. Expert disagreement isn't a feature to engineer — it *is* the field's history (analytic vs. continental, ancient vs. modern, rationalist vs. empiricist). And the pedagogy is *literally* Socratic: the method is named after the person we're building.

The two things philosophy has that literature doesn't: (1) **arguments have structure you can operate on** — premises, inferences, hidden assumptions — so the "close reading" is more surgical and more checkable; and (2) **the student is supposed to end up holding positions**, which means the app can build something literature can't — a living map of what *you* believe and whether it hangs together.

**One-liner:** Enroll in real philosophy courses taught by professors from clashing traditions who lead you, Socratically, to the edge of your own certainty — and who quietly build a map of your convictions, then catch you when you contradict yourself.

---

## 2. The Commitment Map — a consistency engine for your own worldview ⭐ (the crown jewel)

This is the feature that makes The Academy unlike anything that exists. The literature app modeled you as a *reader*; this app models you as a *thinker who holds positions* — and holds you to them.

**What it is:** Across every seminar, thought experiment, and essay, the app extracts the **philosophical commitments you actually assert** ("you just argued that morality is mind-independent"), stores them as a structured graph, computes their **entailments** ("moral realism commits you to *some* account of moral knowledge"), and — the magic — **detects when a new position contradicts an old one**: *"Three weeks ago you defended libertarian free will. What you just said about the mind being fully physical is in tension with that. Reconcile it, or give one up."*

**Why it's profound:** Doing philosophy *is* the pursuit of a coherent worldview. No book, course, or chatbot can track the evolving architecture of *your* beliefs and press on its fault lines. This turns the whole app into a decades-long project: your own examined life, examined.

**Data model (new):**
```
Commitment { userID, id, claim,                      // "moral facts are mind-independent"
  domain: ethics|epistemology|metaphysics|mind|political|aesthetics,
  strength: asserted|leaned|explored|abandoned,      // people move; track the arc
  firstAsserted, lastAffirmed, sourceRefs[],          // sessions where it appeared
  entailments: [claimID], tensions: [claimID] }
CommitmentEdge { fromID, toID, kind: entails|conflicts|supports|abandons }
WorldviewSnapshot { userID, date, summary, majorPositions[], openTensions[] }
```
**Pipeline:** a post-session job (extends the enrichment/profile job) parses the transcript for asserted positions → maps each to the canonical claim graph (a curated ontology of ~200 major positions and their classical entailments, authored content — this is the backbone) → updates strengths → recomputes tensions → flags live contradictions for the professor to raise *next* session.

**How professors use it:** the persona contract gains a `commitment_move` — at most one per session, the professor may surface a tension. Framing is Socratic, never gotcha: not "you're wrong," but "these two things you believe pull against each other — which gives?" Abandoning a position is celebrated as progress, not failure (tracked as an arc, so "you moved from X to Y over four months" becomes a visible intellectual autobiography).

**The Worldview page [user-facing]:** a gorgeous map of your positions by domain, the tensions glowing between them, and a timeline of how your mind has changed. Fully transparent (you see everything), contestable ("I don't actually hold that" edits the graph and is itself philosophical work), and exportable. **[V1]** a "steelman my opposite" button: the app constructs the best case *against* your current worldview and a professor argues it.

**Guardrails:** the ontology encodes *classical* entailments conservatively; the app flags *tensions to examine*, never declares you incoherent. Minimum-evidence before surfacing (a position must be asserted, not merely explored, and affirmed ≥2×). It maps your reasoning, never psychoanalyzes you.

**Effort:** ~3 weeks (ontology authoring is the long pole) + pipeline. Build the ontology first; it's the asset.

---

## 3. Faculty (personas — clashing on purpose)

Fictional professors, each a tradition incarnate. Launch **[MVP: 3; V1: 6]**:

1. **Prof. Sokratis Vlachos — the Socratic** [MVP]. Claims to know nothing; leads you by questions until you contradict yourself (aporia) and *thanks you for it*. The house style. Courses: *The Examined Life*, *What Is Justice?* (the *Republic*).
2. **Prof. Ada Whitmore — the Analytic** [MVP]. Precise, argument-mapping, allergic to vagueness. "Define your terms. Which premise carries the weight?" Courses: *How Arguments Work*, *Knowledge & Its Limits*.
3. **Prof. Íris Lindqvist — the Continental** [MVP]. Reads philosophy as lived, historical, embodied; suspicious of Whitmore's tidy premises. Courses: *Existence & Meaning* (Kierkegaard→Camus), *Suspicion* (Nietzsche, Marx, Freud as the "masters of suspicion").
4. **Prof. Aurelius Bede — the Ancient/Stoic** [V1]. Philosophy as a way of life, not a seminar exercise. Courses: *The Stoic Gymnasium*, *Aristotle on Flourishing*.
5. **Prof. Hannah Reyes — the Political Philosopher** [V1]. Rawls-to-Nozick-to-critique. Courses: *The Just Society*, *Liberty & Its Enemies*.
6. **Prof. Kojima — the Philosopher of Mind** [V1]. Consciousness, personal identity, the hard problem. Courses: *What Am I?*, *Do Machines Think?* (Turing/Searle — delicious for an AI to teach).

The disputation feature (from the lit addendum) is *core* here, not optional: Whitmore vs. Lindqvist on the same Nietzsche passage is the product.

---

## 4. Session types (deltas on the engine)

Reuse seminar, lecture, close-reading, essay, disputation, co-reading. **New, philosophy-native:**

1. **Elenchus (the Socratic gauntlet)** ⭐ **[MVP]** — the flagship session. You state a position; the professor extracts your definition, finds a counterexample, drives you to contradiction, and sits with you in the productive discomfort of *not knowing* before rebuilding. State machine: `thesis → definition → counterexample → revision → (loop until aporia or robust position) → reflection`. The engine *tolerates and aims for aporia* — most tutors are constitutionally unable to let you be productively stuck; this one is designed for it. Feeds the Commitment Map directly.
2. **The Thought-Experiment Lab** ⭐ **[MVP]** — interactive, branching intuition-pumps: the Trolley Problem, the Experience Machine, the Chinese Room, Gettier cases, the Ship of Theseus, Rawls' Veil. You make the call; the app *pumps the intuition harder* (changes the numbers, the framing) to test whether your principle survives, then a professor interrogates *why* you chose. Authored `ThoughtExperimentSpec { setup, branch_points, intuition_pumps, the_philosophical_payload }`. These are shareable, replayable, and screenshot-bait.
3. **Argument reconstruction & the hidden-premise hunt** **[MVP]** — the counterfactual craft-lab, philosophy edition. Take a passage of argument; the app renders it as an argument map (premises→conclusion); *a premise is hidden* and you must find the load-bearing assumption the author never stated. Or: the app removes a premise and you feel the argument collapse. Deterministic argument-diagram rendering + authored `ArgumentSpec`.
4. **The Dialogue** **[V1]** — you enter a Platonic-style dialogue as an interlocutor (Glaucon to the professor's Socrates), co-authoring the argument turn by turn in the original form. Then the professor breaks frame to show you what the dialogue was doing.
5. **Recreate the discovery** **[V1]** — walk Descartes' method of doubt yourself until *you* derive the cogito; reason to Hume's problem of induction before being told it's a problem. Guided rediscovery — you have the insight; the professor is the midwife (Socrates' own metaphor).

---

## 5. Corpus & the ontology asset

- **Texts [MVP]:** ingest via the existing pipeline — Plato & Aristotle (public-domain translations, **[DECISION]** verify each: Jowett Plato is clear), the Stoics, Descartes' *Meditations*, Hume, Kant (older translations), Mill, Nietzsche (Kaufmann is *not* PD — use Common/Zimmern/Ludovici, verify), William James, early Russell. Same `license` review checklist as the Seminar.
- **The claim ontology [MVP — the differentiator]:** ~200 canonical positions across the six domains with their classical entailments and tensions, hand-authored (with Claude's help, human-reviewed). This is what powers the Commitment Map and the argument maps. It is the single most valuable and hardest asset — budget accordingly.
- **Argument-map primitives:** a small deterministic renderer for premise/inference structure (nodes + inference edges), reused by session types 3 and 4.

---

## 6. Build order

1. **M1 — Repoint + Socratic core:** ingest the starter corpus; Vlachos + Whitmore; the **Elenchus** session on one short text (a *Republic* passage on justice). This proves the app can make you productively uncomfortable.
2. **M2 — The Commitment Map v1:** ontology (start ~60 positions), extraction pipeline, the Worldview page, the one-per-session commitment move. The moat begins accreting from day one of use.
3. **M3 — Thought-Experiment Lab + argument reconstruction:** the two most shareable session types. → **MVP**.
4. **M4 (V1):** Lindqvist + disputations (analytic vs. continental — the trailer), the Dialogue, recreate-the-discovery, steelman-my-opposite, full 6-professor faculty.
5. **M5 (V2):** political & mind wings, cross-tradition "great debates" (staged historical disputes: the Frege-Husserl split, the Davos encounter — framed as constructed reconstructions, always cited, never fabricated quotes).

## 7. Risks & guardrails

- **The app must not have a philosophy.** On contested questions it presents the strongest cases from multiple traditions and returns judgment to the student; the faculty disagree *with each other* precisely so no single "house view" leaks. This is both intellectually honest and the anti-sycophancy mechanism.
- **Commitment Map false contradictions:** the ontology encodes entailments *conservatively*; when unsure, the professor asks whether there's a tension rather than asserting one. Never declare a person incoherent.
- **Aporia vs. discouragement:** productive not-knowing is the goal, despair is not — the Elenchus always ends with a reflection that names what was learned in the dismantling. Intensity dial (gentle/standard/rigorous) as in the Seminar.
- **Hallucinated scholarship:** quote-from-retrieval contract holds; professors argue in their own voice and cite the canon by passage ID, never invent citations. The claim ontology keeps entailment-claims grounded in curated content, not model improvisation.
