#!/usr/bin/env python3
"""Unified content validator for The Academy (CONTRACTS sections 7, 11.4,
12.5, 12.6). Absorbs the former check_ontology.py and check_courses.py —
this is the ONE validator all content merges must pass.

Validates:
  - content/ontology/claims.json (section 12.6): schema, unique ids, id/domain
    conventions, edge integrity + conflictsWith symmetry + coherence,
    required course-content ids, per-domain minimums
  - content/courses/*.json (sections 7 + 12.5): base course/unit schema,
    reading spans against ingested books, assignments + rubrics,
    elenchusSpecs / thoughtExperiments / argumentLabs schemas,
    thought-experiment node-graph well-formedness (next targets exist,
    >=1 terminal, no orphans, pumps reference existing nodes),
    argumentLab invariants (supports references; hunt: hiddenPremiseId exists
    with stated:false; collapse: removedPremiseId exists),
    relatedClaims ids cross-checked against the ontology,
    passageIds cross-checked against pipeline/output/*/passages.jsonl
  - content/personas/personas.json + <id>.md: registry shape, required
    persona-doc sections (incl. a course-specific-context section), and
    course personaId -> registry cross-check
  - content/daily/questions.json (section 13.6): bank size, unique ids,
    2-4 options each, ontologyId/relatedClaims -> ontology cross-check,
    personaId -> registry cross-check

Exit code 0 iff clean; nonzero with a readable report otherwise.
"""
import glob
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLAIMS_PATH = ROOT / "content" / "ontology" / "claims.json"
COURSES_DIR = ROOT / "content" / "courses"
PERSONAS_DIR = ROOT / "content" / "personas"
OUTPUT_DIR = ROOT / "pipeline" / "output"

DOMAINS = {"ethics", "epistemology", "metaphysics", "mind", "political", "aesthetics"}
DIFFICULTIES = {"introductory", "intermediate", "advanced"}
ASSIGNMENT_KINDS = {"response", "essay", "closeReading", "imitation"}

errors = []


def err(msg):
    errors.append(msg)


# ---------------------------------------------------------------------------
# Ontology (CONTRACTS section 12.6 — absorbed from check_ontology.py)
# ---------------------------------------------------------------------------

ONTOLOGY_REQUIRED_FIELDS = {"id", "claim", "domain", "summary", "entails", "conflictsWith", "supports"}
ONTOLOGY_EDGE_FIELDS = ("entails", "conflictsWith", "supports")
SLUG_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")

REQUIRED_ONTOLOGY_IDS = {
    "political.justice-advantage-of-stronger", "political.justice-intrinsically-good",
    "ethics.psychological-egoism", "ethics.consequentialism", "ethics.deontology",
    "ethics.moral-realism", "ethics.moral-anti-realism", "ethics.virtue-ethics",
    "epistemology.skepticism-external-world", "epistemology.empiricism",
    "epistemology.rationalism", "epistemology.moral-knowledge-possible",
    "metaphysics.libertarian-free-will", "metaphysics.hard-determinism",
    "metaphysics.compatibilism", "mind.physicalism", "mind.dualism",
    "mind.machine-thought-possible",
}

MIN_PER_DOMAIN = {d: 10 for d in DOMAINS}
MIN_PER_DOMAIN["aesthetics"] = 8


def validate_ontology():
    """Returns the set of valid claim ids (for course cross-checks)."""
    try:
        data = json.loads(CLAIMS_PATH.read_text())
    except FileNotFoundError:
        err(f"ontology: {CLAIMS_PATH} not found")
        return set()
    except json.JSONDecodeError as e:
        err(f"ontology: invalid JSON: {e}")
        return set()

    if data.get("version") != 1:
        err("ontology: top-level 'version' must be 1")
    claims = data.get("claims")
    if not isinstance(claims, list):
        err("ontology: top-level 'claims' must be a list")
        return set()

    ids = [c.get("id") for c in claims]
    dupes = [i for i, n in Counter(ids).items() if n > 1]
    if dupes:
        err(f"ontology: duplicate ids: {dupes}")
    by_id = {c.get("id"): c for c in claims}

    for c in claims:
        cid = c.get("id", "<missing id>")
        missing = ONTOLOGY_REQUIRED_FIELDS - set(c)
        extra = set(c) - ONTOLOGY_REQUIRED_FIELDS
        if missing:
            err(f"ontology {cid}: missing fields {sorted(missing)}")
        if extra:
            err(f"ontology {cid}: unknown fields {sorted(extra)}")
        domain = c.get("domain")
        if domain not in DOMAINS:
            err(f"ontology {cid}: invalid domain {domain!r}")
        if isinstance(cid, str) and "." in cid:
            prefix, slug = cid.split(".", 1)
            if domain in DOMAINS and prefix != domain:
                err(f"ontology {cid}: id prefix {prefix!r} != domain {domain!r}")
            if not SLUG_RE.match(slug):
                err(f"ontology {cid}: slug {slug!r} is not kebab-case")
        else:
            err(f"ontology {cid}: id must be '<domain>.<kebab-slug>'")
        for field in ("claim", "summary"):
            if not isinstance(c.get(field), str) or not c.get(field, "").strip():
                err(f"ontology {cid}: '{field}' must be a non-empty string")
        for field in ONTOLOGY_EDGE_FIELDS:
            targets = c.get(field, [])
            if not isinstance(targets, list):
                err(f"ontology {cid}: '{field}' must be a list")
                continue
            if len(targets) != len(set(targets)):
                err(f"ontology {cid}: duplicate targets in '{field}'")
            for t in targets:
                if t == cid:
                    err(f"ontology {cid}: self-referencing edge in '{field}'")
                elif t not in by_id:
                    err(f"ontology {cid}: '{field}' references unknown id {t!r}")

    # conflictsWith symmetry
    for c in claims:
        cid = c.get("id")
        for t in c.get("conflictsWith", []):
            other = by_id.get(t)
            if other is not None and cid not in other.get("conflictsWith", []):
                err(f"ontology: conflictsWith not symmetric: {cid} -> {t} but not {t} -> {cid}")

    # no claim entails (or supports) a claim that conflicts with it,
    # and no claim both entails/supports and conflicts with the same target
    for c in claims:
        cid = c.get("id")
        conflicts = set(c.get("conflictsWith", []))
        for field in ("entails", "supports"):
            for t in c.get(field, []):
                other = by_id.get(t)
                if other is not None and cid in other.get("conflictsWith", []):
                    err(f"ontology: incoherent: {cid} {field} {t}, but {t} conflictsWith {cid}")
                if t in conflicts:
                    err(f"ontology: incoherent: {cid} both {field} and conflictsWith {t}")

    missing_required = REQUIRED_ONTOLOGY_IDS - set(by_id)
    if missing_required:
        err(f"ontology: missing required course-content ids: {sorted(missing_required)}")

    domain_counts = Counter(c.get("domain") for c in claims)
    for d in sorted(DOMAINS):
        if domain_counts.get(d, 0) < MIN_PER_DOMAIN[d]:
            err(f"ontology domain {d}: {domain_counts.get(d, 0)} claims, minimum {MIN_PER_DOMAIN[d]}")
    total = len(claims)
    if not (66 <= total <= 80):
        err(f"ontology: total claims {total} outside target range 66-80")

    entail_edges = sum(len(c.get("entails", [])) for c in claims)
    support_edges = sum(len(c.get("supports", [])) for c in claims)
    conflict_entries = sum(len(c.get("conflictsWith", [])) for c in claims)
    print(f"ontology: {total} claims")
    for d in sorted(DOMAINS):
        print(f"  {d}: {domain_counts.get(d, 0)}")
    print(f"  edges: entails={entail_edges}, supports={support_edges}, "
          f"conflictsWith={conflict_entries} entries ({conflict_entries // 2} symmetric pairs)")

    return set(by_id)


# ---------------------------------------------------------------------------
# Pipeline output (passage-ID + span cross-check source)
# ---------------------------------------------------------------------------

def load_books():
    """{bookID: {"chapterCount": int, "passageIds": set}} from pipeline/output/*."""
    books = {}
    for book_json in sorted(glob.glob(str(OUTPUT_DIR / "*" / "book.json"))):
        book_dir = Path(book_json).parent
        try:
            meta = json.loads(Path(book_json).read_text())
        except json.JSONDecodeError as e:
            err(f"{book_json}: invalid JSON — {e}")
            continue
        book_id = meta.get("bookID", book_dir.name)
        passage_ids = set()
        passages_path = book_dir / "passages.jsonl"
        if passages_path.exists():
            with open(passages_path) as fh:
                for line in fh:
                    line = line.strip()
                    if line:
                        passage_ids.add(json.loads(line)["id"])
        else:
            err(f"{book_id}: no passages.jsonl in {book_dir}")
        books[book_id] = {
            "chapterCount": meta.get("chapterCount"),
            "passageIds": passage_ids,
        }
    if not books:
        err(f"no ingested books found under {OUTPUT_DIR} — passage cross-checks impossible")
    return books


# ---------------------------------------------------------------------------
# Courses (CONTRACTS sections 7 + 12.5 — absorbed from check_courses.py)
# ---------------------------------------------------------------------------

REQUIRED_COURSE_FIELDS = ["id", "title", "personaId", "description", "difficulty", "estWeeks", "texts", "units"]
REQUIRED_UNIT_FIELDS = ["number", "title", "reading", "lectureOutline", "seminarQuestionBank", "assignments", "recapNotes"]

all_passage_ids = []


def check_passage_id(pid, ctx, books):
    """A passage id must exist in an ingested book's passages.jsonl."""
    if not isinstance(pid, str) or pid.count(":") != 2:
        err(f"{ctx}: passageId {pid!r} is not of the form bookID:ch:para")
        return
    book_id = pid.split(":", 1)[0]
    book = books.get(book_id)
    if book is None:
        err(f"{ctx}: passageId {pid!r} references unknown book {book_id!r}")
    elif pid not in book["passageIds"]:
        err(f"{ctx}: passageId {pid!r} not found in pipeline/output/{book_id}/passages.jsonl")
    else:
        all_passage_ids.append(pid)


def check_span(span, ctx, books):
    book_id = span.get("bookID")
    ch_start, ch_end = span.get("chStart", -1), span.get("chEnd", -1)
    book = books.get(book_id)
    if book is None:
        err(f"{ctx}: span references unknown bookID {book_id!r}")
        return
    max_ch = (book["chapterCount"] or 0) - 1
    if not (isinstance(ch_start, int) and isinstance(ch_end, int) and 0 <= ch_start <= ch_end <= max_ch):
        err(f"{ctx}: span out of range ch 0-{max_ch}: {span}")


def check_claims(claims, ctx, claim_ids):
    if not isinstance(claims, list):
        err(f"{ctx}: relatedClaims is not a list")
        return
    for c in claims:
        if c not in claim_ids:
            err(f"{ctx}: relatedClaims id {c!r} not in content/ontology/claims.json")


def check_rubric(assignment, ctx):
    rubric = assignment.get("rubric")
    if not isinstance(rubric, list) or not rubric:
        err(f"{ctx}: missing or empty rubric")
        return
    total = 0.0
    for i, row in enumerate(rubric):
        for f in ("name", "weight", "descriptors"):
            if f not in row:
                err(f"{ctx} rubric[{i}]: missing field {f!r}")
        d = row.get("descriptors", {})
        for grade in ("A", "B", "C"):
            if grade not in d:
                err(f"{ctx} rubric[{i}]: missing descriptor {grade!r}")
        total += float(row.get("weight", 0))
    if abs(total - 1.0) > 0.01:
        err(f"{ctx}: rubric weights sum to {total}, expected ~1.0")


def check_elenchus(el, ctx, books, claim_ids):
    for f in ("id", "openingQuestion", "span", "passageIds", "classicMoves", "relatedClaims", "reflectionPrompt"):
        if f not in el:
            err(f"{ctx}: missing field {f!r}")
    check_span(el.get("span", {}), ctx, books)
    pids = el.get("passageIds", [])
    if not (1 <= len(pids) <= 3):
        err(f"{ctx}: passageIds count {len(pids)}, expected 1-3")
    for pid in pids:
        check_passage_id(pid, f"{ctx} passageIds", books)
    for i, m in enumerate(el.get("classicMoves", [])):
        for f in ("definition", "counterexample"):
            if f not in m:
                err(f"{ctx} classicMoves[{i}]: missing {f!r}")
    check_claims(el.get("relatedClaims", []), ctx, claim_ids)


def check_thought_experiment(te, ctx, books, claim_ids):
    for f in ("id", "title", "setup", "philosophicalPayload", "sourceRefs", "nodes", "pumps", "interrogation", "relatedClaims"):
        if f not in te:
            err(f"{ctx}: missing field {f!r}")
    words = len(te.get("setup", "").split())
    if not (150 <= words <= 300):
        err(f"{ctx}: setup is {words} words, expected 150-300")
    for pid in te.get("sourceRefs", []):
        check_passage_id(pid, f"{ctx} sourceRefs", books)
    check_claims(te.get("relatedClaims", []), ctx, claim_ids)

    # node-graph well-formedness: next targets exist, >=1 terminal, no orphans
    nodes = te.get("nodes", [])
    node_ids = [n.get("id") for n in nodes]
    if len(node_ids) != len(set(node_ids)):
        err(f"{ctx}: duplicate node ids")
    node_set = set(node_ids)
    terminals = [n for n in nodes if n.get("terminal")]
    if not terminals:
        err(f"{ctx}: no terminal node")
    edges = {}
    for n in nodes:
        nid = n.get("id")
        edges[nid] = []
        if n.get("terminal"):
            if n.get("options"):
                err(f"{ctx}: terminal node {nid!r} has options")
            continue
        opts = n.get("options", [])
        if not opts:
            err(f"{ctx}: non-terminal node {nid!r} has no options")
        for o in opts:
            nxt = o.get("next")
            if nxt not in node_set:
                err(f"{ctx}: node {nid!r} option points to nonexistent node {nxt!r}")
            else:
                edges[nid].append(nxt)
    if nodes:
        root = nodes[0]["id"]
        seen = set()
        stack = [root]
        while stack:
            cur = stack.pop()
            if cur in seen:
                continue
            seen.add(cur)
            stack.extend(edges.get(cur, []))
        orphans = node_set - seen
        if orphans:
            err(f"{ctx}: orphan nodes unreachable from {root!r}: {sorted(orphans)}")
    # pumps reference existing nodes
    for p in te.get("pumps", []):
        for f in ("id", "afterNode", "variation", "testsPrinciple"):
            if f not in p:
                err(f"{ctx} pump: missing field {f!r}")
        if p.get("afterNode") not in node_set:
            err(f"{ctx}: pump {p.get('id')!r} afterNode {p.get('afterNode')!r} does not exist")


def check_argument_lab(lab, ctx, books, claim_ids):
    for f in ("id", "title", "source", "conclusion", "premises", "mode", "pedagogicalPoint", "elicitationQuestions", "relatedClaims"):
        if f not in lab:
            err(f"{ctx}: missing field {f!r}")
    src = lab.get("source", {})
    if src.get("bookID") not in books:
        err(f"{ctx}: source bookID {src.get('bookID')!r} not among ingested books")
    for pid in src.get("passageIds", []):
        check_passage_id(pid, f"{ctx} source", books)
    check_claims(lab.get("relatedClaims", []), ctx, claim_ids)

    ids = {lab.get("conclusion", {}).get("id")}
    premises = lab.get("premises", [])
    for p in premises:
        ids.add(p.get("id"))
    for p in premises:
        for f in ("id", "text", "stated", "supports"):
            if f not in p:
                err(f"{ctx} premise {p.get('id')!r}: missing field {f!r}")
        if p.get("supports") not in ids:
            err(f"{ctx}: premise {p.get('id')!r} supports nonexistent id {p.get('supports')!r}")

    mode = lab.get("mode")
    if mode not in ("hunt", "collapse"):
        err(f"{ctx}: mode {mode!r} not in hunt|collapse")
    premise_by_id = {p.get("id"): p for p in premises}
    if mode == "hunt":
        hid = lab.get("hiddenPremiseId")
        if hid not in premise_by_id:
            err(f"{ctx}: hunt mode hiddenPremiseId {hid!r} not among premises")
        elif premise_by_id[hid].get("stated") is not False:
            err(f"{ctx}: hidden premise {hid!r} must have stated:false")
        if lab.get("removedPremiseId") is not None:
            err(f"{ctx}: hunt mode should have removedPremiseId null")
    if mode == "collapse":
        rid = lab.get("removedPremiseId")
        if rid not in premise_by_id:
            err(f"{ctx}: collapse mode removedPremiseId {rid!r} not among premises")


def check_course(path, books, claim_ids, persona_ids):
    with open(path) as fh:
        course = json.load(fh)
    cid = course.get("id", path)

    for f in REQUIRED_COURSE_FIELDS:
        if f not in course:
            err(f"{cid}: missing required course field {f!r}")
    if course.get("difficulty") not in DIFFICULTIES:
        err(f"{cid}: difficulty {course.get('difficulty')!r} not in enum")
    if persona_ids and course.get("personaId") not in persona_ids:
        err(f"{cid}: personaId {course.get('personaId')!r} not in personas.json registry")
    for t in course.get("texts", []):
        for f in ("bookID", "title", "author", "source", "sourceUrl", "license", "licenseNote"):
            if f not in t:
                err(f"{cid}: texts entry missing {f!r}")

    units = course.get("units", [])
    for i, u in enumerate(units):
        uctx = f"{cid} unit {u.get('number', i + 1)}"
        if u.get("number") != i + 1:
            err(f"{uctx}: unit numbers not sequential (got {u.get('number')}, expected {i + 1})")
        for f in REQUIRED_UNIT_FIELDS:
            if f not in u:
                err(f"{uctx}: missing required unit field {f!r}")
        for r in u.get("reading", []):
            check_span(r, f"{uctx} reading", books)
        lo = u.get("lectureOutline", [])
        if not (5 <= len(lo) <= 8):
            err(f"{uctx}: lectureOutline has {len(lo)} segments, expected 5-8")
        sq = u.get("seminarQuestionBank", [])
        if not (6 <= len(sq) <= 10):
            err(f"{uctx}: seminarQuestionBank has {len(sq)} questions, expected 6-10")
        for pid in u.get("closeReadingPassages", []):
            check_passage_id(pid, f"{uctx} closeReadingPassages", books)
        for a in u.get("assignments", []):
            actx = f"{uctx} assignment {a.get('id')!r}"
            for f in ("id", "kind", "prompt", "lengthWords", "rubric"):
                if f not in a:
                    err(f"{actx}: missing field {f!r}")
            if a.get("kind") not in ASSIGNMENT_KINDS:
                err(f"{actx}: kind {a.get('kind')!r} not in enum")
            check_rubric(a, actx)
        for el in u.get("elenchusSpecs", []):
            check_elenchus(el, f"{uctx} elenchus {el.get('id')!r}", books, claim_ids)
        for te in u.get("thoughtExperiments", []):
            check_thought_experiment(te, f"{uctx} thoughtExperiment {te.get('id')!r}", books, claim_ids)
        for lab in u.get("argumentLabs", []):
            check_argument_lab(lab, f"{uctx} argumentLab {lab.get('id')!r}", books, claim_ids)
        # Inherited platform specs (section 11.4), if a unit ever carries them.
        for d in u.get("disputations", []):
            dctx = f"{uctx} disputation {d.get('id')!r}"
            for f in ("id", "personaA", "personaB", "span", "positionA", "positionB", "crux"):
                if f not in d:
                    err(f"{dctx}: missing field {f!r}")
            if "span" in d:
                check_span(d["span"], dctx, books)
            for pid in d.get("passageIds", []):
                check_passage_id(pid, dctx, books)
        for cl in u.get("craftLabs", []):
            lctx = f"{uctx} craftLab {cl.get('id')!r}"
            for f in ("id", "bookID", "span", "transform", "damagedText"):
                if f not in cl:
                    err(f"{lctx}: missing field {f!r}")
            if not str(cl.get("damagedText", "")).strip():
                err(f"{lctx}: damagedText is empty")
    return cid


# ---------------------------------------------------------------------------
# Personas (persona docs' required sections — CONTRACTS sections 6, 11.4)
# ---------------------------------------------------------------------------

REQUIRED_PERSONA_SECTIONS = [
    "## Identity & Backstory",
    "## Intellectual Commitments",
    "## Speech Patterns",
    "## Pedagogical Behaviors",
    "## Red Lines",
    "## In Disputation",
]
# The course-context section names its course in the heading; do not hardcode
# course titles — any "## Course-Specific Context — ..." heading passes.
COURSE_CONTEXT_RE = re.compile(r"^##\s+Course-Specific Context\b", re.MULTILINE)


def validate_personas():
    """Returns the set of registry persona ids (for course cross-checks)."""
    registry_path = PERSONAS_DIR / "personas.json"
    try:
        registry = json.loads(registry_path.read_text())
    except FileNotFoundError:
        err(f"personas: {registry_path} not found")
        return set()
    except json.JSONDecodeError as e:
        err(f"personas: invalid JSON: {e}")
        return set()
    if not isinstance(registry, list):
        err("personas: registry must be a list")
        return set()

    ids = set()
    for p in registry:
        pid = p.get("id", "<missing id>")
        ids.add(pid)
        for f in ("id", "name", "title", "blurb"):
            if not isinstance(p.get(f), str) or not p.get(f, "").strip():
                err(f"persona {pid}: registry field {f!r} must be a non-empty string")
        doc_path = PERSONAS_DIR / f"{pid}.md"
        if not doc_path.exists():
            err(f"persona {pid}: {doc_path} not found")
            continue
        doc = doc_path.read_text()
        for section in REQUIRED_PERSONA_SECTIONS:
            if not re.search(rf"^{re.escape(section)}\b", doc, re.MULTILINE):
                err(f"persona {pid}: missing required section {section!r}")
        if not COURSE_CONTEXT_RE.search(doc):
            err(f"persona {pid}: missing '## Course-Specific Context — ...' section")
    print(f"personas: {len(ids)} registered ({', '.join(sorted(ids))})")
    return ids


# ---------------------------------------------------------------------------
# Daily-question bank (CONTRACTS section 13.6)
# ---------------------------------------------------------------------------

DAILY_PATH = ROOT / "content" / "daily" / "questions.json"
DAILY_MIN_BANK = 14


def validate_daily(claim_ids, persona_ids):
    try:
        bank = json.loads(DAILY_PATH.read_text())
    except FileNotFoundError:
        err(f"daily: {DAILY_PATH} not found")
        return
    except json.JSONDecodeError as e:
        err(f"daily: invalid JSON: {e}")
        return

    questions = bank.get("questions", [])
    if len(questions) < DAILY_MIN_BANK:
        err(f"daily: bank has {len(questions)} questions; contract minimum is {DAILY_MIN_BANK}")

    seen = Counter(q.get("id", "<missing>") for q in questions)
    for qid, n in seen.items():
        if n > 1:
            err(f"daily: duplicate question id {qid!r}")

    for q in questions:
        qid = q.get("id", "<missing id>")
        ctx = f"daily {qid}"
        if not str(q.get("question", "")).strip():
            err(f"{ctx}: question text is empty")
        if q.get("domain") not in DOMAINS:
            err(f"{ctx}: domain {q.get('domain')!r} not one of {sorted(DOMAINS)}")
        if q.get("personaId") not in persona_ids:
            err(f"{ctx}: personaId {q.get('personaId')!r} not in the persona registry")
        options = q.get("options", [])
        if not 2 <= len(options) <= 4:
            err(f"{ctx}: needs 2-4 options, has {len(options)}")
        opt_ids = Counter(o.get("id", "<missing>") for o in options)
        for oid, n in opt_ids.items():
            if n > 1:
                err(f"{ctx}: duplicate option id {oid!r}")
        for o in options:
            octx = f"{ctx} option {o.get('id')!r}"
            if not str(o.get("label", "")).strip():
                err(f"{octx}: label is empty")
            if "ontologyId" not in o:
                err(f"{octx}: ontologyId must be present (use null when unmapped)")
            elif o["ontologyId"] is not None and o["ontologyId"] not in claim_ids:
                err(f"{octx}: ontologyId {o['ontologyId']!r} not in the ontology")
        check_claims(q.get("relatedClaims", []), ctx, claim_ids)

    mapped = sum(
        1 for q in questions for o in q.get("options", []) if o.get("ontologyId")
    )
    print(f"daily: {len(questions)} questions, {mapped} claim-mapped options")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    claim_ids = validate_ontology()
    books = load_books()
    persona_ids = validate_personas()
    validate_daily(claim_ids, persona_ids)

    course_files = sorted(glob.glob(str(COURSES_DIR / "*.json")))
    if not course_files:
        err(f"no course files found under {COURSES_DIR}")
    course_ids = []
    for path in course_files:
        try:
            course_ids.append(check_course(path, books, claim_ids, persona_ids))
        except json.JSONDecodeError as e:
            err(f"{path}: invalid JSON — {e}")
    print(f"courses: {len(course_ids)} checked ({', '.join(course_ids)})")
    print(f"passage IDs cross-checked: {len(set(all_passage_ids))} unique, all present in pipeline output")

    if errors:
        print(f"\nFAIL — {len(errors)} violation(s):")
        for e in errors:
            print(f"  - {e}")
        return 1
    print("\nOK: ontology, courses, personas, and the daily bank all pass.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
