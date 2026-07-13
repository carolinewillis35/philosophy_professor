// THE ACADEMY — session engine Edge Function (CONTRACTS §4–§6, §10, §12).
//
// POST /functions/v1/session  { action: "start" | "turn", ... }
// Response: text/event-stream — events: session (start only), say (repeated),
// envelope (once), error, done.

import {
  anthropicClient,
  MAX_TOKENS_TURN,
  MODEL_SEMINAR,
} from "../_shared/anthropic.ts";
import {
  ENVELOPE_SCHEMA,
  type Envelope,
  minimalEnvelope,
  parseEnvelope,
  PROFILE_DIMENSIONS,
  PROFILE_EVIDENCE_KINDS,
  type ProfileOp,
} from "../_shared/envelope.ts";
import { SayStream } from "../_shared/sayStream.ts";
import {
  callerClient,
  type Passage,
  retrievePassages,
  serviceClient,
} from "../_shared/retrieval.ts";
import {
  applyStateOps,
  CO_READING_MAX_PER_CHAPTER,
  type CoReadingRequest,
  type CourseDoc,
  type CourseUnit,
  type CraftLabSpec,
  type DisputeSpec,
  generateQuizQuestions,
  gradeQuizAnswer,
  initialState,
  instructionBlock,
  type KindSpec,
  type QuizQuestion,
  type SessionKind,
  type SessionState,
  summarizeRelationshipMemory,
} from "../_shared/engine.ts";
import type { ElenchusSpec } from "../_shared/kinds_academy.ts";
import type { DailyQuestionSpec } from "../_shared/kinds_engagement.ts";
import {
  buildPracticeDigest,
  type PracticeExerciseDoc,
  type PracticeSpec,
} from "../_shared/kinds_life.ts";
import { generateNewsBrief, loadNewsBrief } from "../_shared/news.ts";
import {
  loadReaderProfile,
  profileDigest,
  updateReaderProfile,
} from "../_shared/profile.ts";
import { type CommitmentOp, validateCommitmentOps } from "../_shared/commitments.ts";
import {
  buildUserCommitmentDigest,
  type ClaimRow,
  loadClaims,
  persistCommitmentOps,
  runCommitmentPipeline,
} from "../_shared/commitments_pipeline.ts";
import {
  buildContextBlock,
  buildPrompt,
  courseContextBlock,
  ensureTurnSummary,
  KEEP_RAW_TURNS,
  type TurnRow,
  type UserAnnotation,
} from "../_shared/prompt.ts";
import {
  BUDGET_MESSAGES,
  checkBudget,
  readTodayUsage,
  recordUsage,
  SOFT_BUDGET_NOTE,
  UsageAccumulator,
} from "../_shared/budget.ts";

// ---------------------------------------------------------------------------
// CORS (iOS client sends authorization, apikey, content-type)
// ---------------------------------------------------------------------------

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SSE_HEADERS: Record<string, string> = {
  ...CORS_HEADERS,
  "Content-Type": "text/event-stream; charset=utf-8",
  "Cache-Control": "no-cache",
  "Connection": "keep-alive",
};

const KINDS: SessionKind[] = [
  "lecture",
  "seminar",
  "closeReading",
  "officeHours",
  "essay",
  "quiz",
  "disputation",
  "craftLab",
  "coReading",
  "elenchus",
  "thoughtExperiment",
  "argumentLab",
  "dailyQuestion",
  "argumentClinic",
  "steelman",
  "newsRead",
  "practice",
  "practiceReview",
];

/** Standalone kinds (§13.1): no enrollment, no course, no retrieval.
 * thoughtExperiment ALSO runs standalone when started as a weekly drop
 * (§14.3, request carries dropId). */
const STANDALONE_KINDS: SessionKind[] = [
  "dailyQuestion",
  "argumentClinic",
  "steelman",
  "newsRead",
  "practice",
  "practiceReview",
];

/** Session kinds driven by an authored spec from the course unit JSON. */
const SPEC_KINDS: SessionKind[] = [
  "disputation",
  "craftLab",
  "elenchus",
  "thoughtExperiment",
  "argumentLab",
];

interface RequestBody {
  action?: "start" | "turn";
  sessionId?: string;
  enrollmentId?: string;
  kind?: SessionKind;
  unit?: number;
  userText?: string;
  userAnnotations?: UserAnnotation[];
  essayBody?: string;
  /** Spec-driven kinds (disputation / craftLab / elenchus / thoughtExperiment
   * / argumentLab): which authored spec to run (default: unit's first). */
  specId?: string;
  /** coReading extras (CONTRACTS §11.2). */
  waypointId?: string;
  position?: { ch: number; para: number };
  trigger?: string;
  /** Standalone kinds (§13.1): argumentClinic professor (default whitmore). */
  personaId?: string;
  /** dailyQuestion start extras (§13.2). */
  questionId?: string;
  optionId?: string;
  localDate?: string;
  /** Weekly-drop start extra (§14.3): runs thoughtExperiment standalone. */
  dropId?: string;
  /** steelman start extras (§14.4). */
  targetClaim?: string;
  targetOntologyId?: string;
  /** practice start extras (§15.3). */
  mode?: "morning" | "evening" | "visualization";
  exerciseId?: string;
}

function jsonResponse(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

type Send = (event: string, data: unknown) => void;

// ---------------------------------------------------------------------------
// Data loading helpers (service client — ownership checked explicitly)
// ---------------------------------------------------------------------------

// deno-lint-ignore no-explicit-any
type Db = any;

interface LoadedContext {
  // deno-lint-ignore no-explicit-any
  enrollment: any; // standalone sessions carry a synthetic enrollment (§13.1)
  // deno-lint-ignore no-explicit-any
  course: any;
  courseDoc: CourseDoc;
  // deno-lint-ignore no-explicit-any
  persona: any;
  unitDef: CourseUnit;
  /** §13.1 standalone session: no course, no retrieval, no profile digest,
   * no relationship memory. */
  standalone?: boolean;
  /** dailyQuestion authored spec, loaded from the daily_questions catalog. */
  standaloneSpec?: KindSpec;
}

/** Synthetic unit/course for standalone sessions — keeps the turn pipeline's
 * shape without a real enrollment (§13.1). */
const STANDALONE_UNIT: CourseUnit = { number: 0, title: "", reading: [] };

function standaloneCourseDoc(personaId: string): CourseDoc {
  return { id: "standalone", title: "", personaId, units: [STANDALONE_UNIT] };
}

// deno-lint-ignore no-explicit-any
function syntheticEnrollment(userId: string): any {
  return {
    id: null,
    user_id: userId,
    pace: "standard",
    relationship_memory: "",
    started_at: null,
  };
}

async function loadStandaloneContext(
  db: Db,
  userId: string,
  // deno-lint-ignore no-explicit-any
  session: any,
): Promise<LoadedContext> {
  if (session.user_id !== userId) throw new Error("forbidden: not your session");
  const { data: persona, error: pErr } = await db
    .from("personas").select("*").eq("id", session.persona_id).maybeSingle();
  if (pErr || !persona) {
    throw new Error(`persona load failed: ${pErr?.message ?? "not found"}`);
  }
  let standaloneSpec: KindSpec | undefined;
  if (session.kind === "dailyQuestion" && session.state?.questionId) {
    const { data: q } = await db
      .from("daily_questions").select("doc")
      .eq("id", session.state.questionId).maybeSingle();
    if (q) standaloneSpec = q.doc as DailyQuestionSpec;
  } else if (session.kind === "thoughtExperiment" && session.state?.dropId) {
    // Weekly drop (§14.3): the spec lives in the drops catalog.
    const { data: d } = await db
      .from("drops").select("doc").eq("id", session.state.dropId).maybeSingle();
    if (d) standaloneSpec = (d.doc as { experiment: KindSpec }).experiment;
  } else if (session.kind === "newsRead" && typeof session.state?.week === "number") {
    const brief = await loadNewsBrief(db, session.state.week);
    if (brief) standaloneSpec = { brief };
  } else if (session.kind === "practice" && session.state?.exerciseId) {
    const { data: ex } = await db
      .from("practice_exercises").select("doc")
      .eq("id", session.state.exerciseId).maybeSingle();
    if (ex) {
      standaloneSpec = {
        mode: session.state.mode,
        exercise: ex.doc as PracticeExerciseDoc,
      } as PracticeSpec;
    }
  }
  return {
    enrollment: syntheticEnrollment(userId),
    course: null,
    courseDoc: standaloneCourseDoc(session.persona_id),
    persona,
    unitDef: STANDALONE_UNIT,
    standalone: true,
    standaloneSpec,
  };
}

function resolveUnit(courseDoc: CourseDoc, unit: number): CourseUnit {
  const byIndex = courseDoc.units?.[unit];
  if (byIndex) return byIndex;
  const byNumber = courseDoc.units?.find((u) => u.number === unit);
  if (byNumber) return byNumber;
  throw new Error(`unit ${unit} not found in course`);
}

async function loadEnrollmentContext(
  db: Db,
  userId: string,
  enrollmentId: string,
  unit: number,
): Promise<LoadedContext> {
  const { data: enrollment, error: eErr } = await db
    .from("enrollments").select("*").eq("id", enrollmentId).maybeSingle();
  if (eErr) throw new Error(`enrollment load failed: ${eErr.message}`);
  if (!enrollment) throw new Error("enrollment not found");
  if (enrollment.user_id !== userId) throw new Error("forbidden: not your enrollment");

  const { data: course, error: cErr } = await db
    .from("courses").select("*").eq("id", enrollment.course_id).maybeSingle();
  if (cErr || !course) throw new Error(`course load failed: ${cErr?.message ?? "not found"}`);
  const courseDoc = course.doc as CourseDoc;

  const { data: persona, error: pErr } = await db
    .from("personas").select("*").eq("id", course.persona_id).maybeSingle();
  if (pErr || !persona) throw new Error(`persona load failed: ${pErr?.message ?? "not found"}`);

  return { enrollment, course, courseDoc, persona, unitDef: resolveUnit(courseDoc, unit) };
}

function courseBookIds(courseDoc: CourseDoc, unitDef: CourseUnit): string[] {
  const fromCourse = (courseDoc.texts ?? []).map((t) => t.bookID).filter(Boolean);
  if (fromCourse.length > 0) return fromCourse;
  return [...new Set((unitDef.reading ?? []).map((r) => r.bookID))];
}

/** Resolve the authored spec for spec-driven sessions (§11.2 + §12.1):
 * the requested spec id when the client sends one, else the unit's first. */
function resolveSpec(
  kind: SessionKind,
  unitDef: CourseUnit,
  wantedId?: string | null,
): KindSpec | undefined {
  const pick = <T extends { id: string }>(list: T[] | undefined): T | undefined => {
    const l = list ?? [];
    return (wantedId ? l.find((s) => s.id === wantedId) : undefined) ?? l[0];
  };
  switch (kind) {
    case "disputation":
      return pick(unitDef.disputations);
    case "craftLab":
      return pick(unitDef.craftLabs);
    case "elenchus":
      return pick(unitDef.elenchusSpecs);
    case "thoughtExperiment":
      return pick(unitDef.thoughtExperiments);
    case "argumentLab":
      return pick(unitDef.argumentLabs);
    default:
      return undefined;
  }
}

/** Ontology domains touched by a unit's authored Academy specs (§12.4.1) —
 * derived from relatedClaims id prefixes (`<domain>.<slug>`). */
function unitClaimDomains(unitDef: CourseUnit): string[] {
  const ids = [
    ...(unitDef.elenchusSpecs ?? []).flatMap((s) => s.relatedClaims ?? []),
    ...(unitDef.thoughtExperiments ?? []).flatMap((s) => s.relatedClaims ?? []),
    ...(unitDef.argumentLabs ?? []).flatMap((s) => s.relatedClaims ?? []),
  ];
  return [...new Set(ids.map((id) => id.split(".")[0]).filter(Boolean))];
}

/**
 * Persona docs for the system prompt. Disputation sessions carry BOTH
 * personas' docs (§11.2); everything else uses the course persona.
 */
async function loadPersonaDocs(
  db: Db,
  ctx: LoadedContext,
  kind: SessionKind,
  spec: KindSpec | undefined,
): Promise<string[]> {
  if (kind === "disputation" && spec) {
    const ds = spec as DisputeSpec;
    const { data: rows, error } = await db
      .from("personas")
      .select("id, doc")
      .in("id", [ds.personaA, ds.personaB]);
    if (error) throw new Error(`disputation persona load failed: ${error.message}`);
    const byId = new Map(
      ((rows ?? []) as { id: string; doc: string }[]).map((r) => [r.id, r.doc]),
    );
    const docA = byId.get(ds.personaA);
    const docB = byId.get(ds.personaB);
    if (docA && docB) return [docA, docB];
    throw new Error(
      `disputation personas missing: ${!docA ? ds.personaA : ""} ${!docB ? ds.personaB : ""}`.trim(),
    );
  }
  return [ctx.persona.doc as string];
}

// ---------------------------------------------------------------------------
// The professor turn pipeline (shared by "start" opening and "turn")
// ---------------------------------------------------------------------------

interface TurnContext {
  db: Db;
  // deno-lint-ignore no-explicit-any
  session: any;
  ctx: LoadedContext;
  userText: string;
  annotations: UserAnnotation[];
  essayBody: string | null;
  isOpening: boolean;
  /** ≥80% of a daily budget limit — ask for tighter, shorter replies (§4.3). */
  softBudget: boolean;
  /** Accumulates token usage across every model call in this request. */
  usage: UsageAccumulator;
  /** coReading request extras (waypointId / position / trigger). */
  coReading?: CoReadingRequest;
}

async function runProfessorTurn(tc: TurnContext, send: Send): Promise<void> {
  const { db, session, ctx } = tc;
  const kind = session.kind as SessionKind;
  const state: SessionState = structuredClone(session.state ?? {});
  const enrollment = ctx.enrollment;

  // Claims catalog, loaded lazily and at most once per request (§12.2).
  let claimsCache: Promise<ClaimRow[]> | null = null;
  const claimsCatalog = (): Promise<ClaimRow[]> => {
    if (!claimsCache) claimsCache = loadClaims(db);
    return claimsCache;
  };

  // --- coReading interjection cap (§11.2) -----------------------------------
  // Over CO_READING_MAX_PER_CHAPTER for this chapter: return a silent no-op
  // envelope — no model call, no persisted turns, no budget burned (the usage
  // accumulator stays at zero model calls, so no turn is recorded).
  if (kind === "coReading" && !tc.isOpening) {
    const ch = tc.coReading?.position?.ch;
    const counts: Record<string, number> = state.perChapterCounts ?? {};
    if (ch != null && (counts[String(ch)] ?? 0) >= CO_READING_MAX_PER_CHAPTER) {
      send("envelope", minimalEnvelope(""));
      return;
    }
    if (ch != null) {
      counts[String(ch)] = (counts[String(ch)] ?? 0) + 1;
      state.perChapterCounts = counts;
    }
  }

  // --- kind-specific authored spec (§11.2 disputation/craftLab, §12.1
  //     elenchus/thoughtExperiment/argumentLab, §13.2 dailyQuestion) ----------
  const spec = ctx.standaloneSpec ??
    resolveSpec(kind, ctx.unitDef, state.disputeId ?? state.labId ?? state.specId);

  // --- essay submission bookkeeping (phase machine, CONTRACTS §5) ----------
  if (kind === "essay" && tc.essayBody) {
    const assignmentId: string = state.assignmentId ??
      ctx.unitDef.assignments?.[0]?.id ?? "unassigned";
    const { count } = await db
      .from("essays")
      .select("id", { count: "exact", head: true })
      .eq("enrollment_id", enrollment.id)
      .eq("assignment_id", assignmentId);
    const revision = (count ?? 0) + 1;
    const { error: insErr } = await db.from("essays").insert({
      enrollment_id: enrollment.id,
      assignment_id: assignmentId,
      revision,
      body: tc.essayBody,
    });
    if (insErr) throw new Error(`essay insert failed: ${insErr.message}`);
    state.assignmentId = assignmentId;
    state.phase = "submitted";
    state._latestRevision = revision;
  }

  // --- quiz answer grading (MODEL_LIGHT, server-side) ----------------------
  if (kind === "quiz" && !tc.isOpening) {
    const questions: QuizQuestion[] = state.questions ?? [];
    const answered: number = state.answered ?? 0;
    if (answered < questions.length && tc.userText.trim()) {
      const grading = await gradeQuizAnswer(questions[answered], tc.userText, tc.usage);
      state.answered = answered + 1;
      if (grading.correct) state.correct = (state.correct ?? 0) + 1;
      state.lastGrading = {
        questionIndex: answered,
        correct: grading.correct,
        note: grading.note,
      };
    }
  }

  // --- load prior turns, persist the user turn -----------------------------
  const { data: priorTurnsData, error: tErr } = await db
    .from("turns")
    .select("seq, role, content")
    .eq("session_id", session.id)
    .order("seq", { ascending: true });
  if (tErr) throw new Error(`turns load failed: ${tErr.message}`);
  const priorTurns = (priorTurnsData ?? []) as TurnRow[];

  let seq = priorTurns.length > 0 ? priorTurns[priorTurns.length - 1].seq + 1 : 1;

  if (!tc.isOpening) {
    const userContent = tc.userText.trim() ||
      (tc.essayBody ? `[submitted essay draft, revision ${state._latestRevision ?? 1}]` : "") ||
      (tc.coReading?.position
        ? `[reader at ch ${tc.coReading.position.ch}, para ${tc.coReading.position.para}${
          tc.coReading.trigger ? ` — ${tc.coReading.trigger}` : ""
        }]`
        : "");
    const { error: utErr } = await db.from("turns").insert({
      session_id: session.id,
      seq,
      role: "user",
      content: userContent,
    });
    if (utErr) throw new Error(`user turn insert failed: ${utErr.message}`);
    seq += 1;
  }

  // --- summarize turns older than the last 12 (MODEL_LIGHT, reused) --------
  await ensureTurnSummary(state, priorTurns, tc.usage);

  // --- retrieval, biased to the unit span (kind specs override the focus) ---
  // disputation focuses its spec span; craftLab its source chapter; elenchus
  // its authored span (§12.5).
  let span = ctx.unitDef.reading?.[0];
  if (kind === "disputation" && spec) {
    const s = (spec as DisputeSpec).span;
    span = s;
  } else if (kind === "craftLab" && spec) {
    const s = (spec as CraftLabSpec).span;
    span = { bookID: (spec as CraftLabSpec).bookID, chStart: s.ch, chEnd: s.ch };
  } else if (kind === "elenchus" && spec) {
    span = (spec as ElenchusSpec).span;
  }
  const query = tc.userText.trim() ||
    `${ctx.unitDef.title} ${ctx.unitDef.lectureOutline?.[state.segment ?? 0] ?? ""}`;
  let passages: Passage[] = [];
  // Standalone kinds skip retrieval by contract (§13.2/§13.3 — citations
  // stay empty; the quote guardrail holds trivially).
  if (!ctx.standalone) {
    try {
      passages = await retrievePassages(db, {
        query,
        bookIds: courseBookIds(ctx.courseDoc, ctx.unitDef),
        focusChStart: span?.chStart ?? null,
        focusChEnd: span?.chEnd ?? null,
        matchCount: 8,
      });
    } catch (e) {
      console.error("retrieval failed (continuing without passages):", e);
    }
  }

  // --- reader profile digest (§11.3 — gated on evidenceCount ≥ 5; skipped
  //     for standalone sessions, §13.1) --------------------------------------
  let digest: string | null = null;
  if (!ctx.standalone) {
    try {
      digest = profileDigest(await loadReaderProfile(db, enrollment.user_id));
    } catch (e) {
      console.error("profile digest failed (continuing without):", e);
    }
  }

  // --- commitment digest (§12.2 — gated on ≥3 non-abandoned commitments) ----
  let commitmentDigest: string | null = null;
  let commitmentDigestCarriedTension = false;
  // The one tension markTensionReconciled may resolve this session (§14.2):
  // raised by an earlier turn's digest (persisted on state) or by this one.
  let raisedTensionId: string | null = typeof state._raisedTensionId === "string"
    ? state._raisedTensionId
    : null;
  try {
    const cd = await buildUserCommitmentDigest(
      db,
      enrollment.user_id,
      session.id,
      state._commitmentMoveUsed === true,
    );
    if (cd) {
      commitmentDigest = cd.digest;
      commitmentDigestCarriedTension = cd.carriedTension;
      if (cd.raisedTensionId) raisedTensionId = cd.raisedTensionId;
    }
  } catch (e) {
    console.error("commitment digest failed (continuing without):", e);
  }

  // --- practice digest (§15.3): last 7 days of entries, practiceReview only -
  let practiceDigest: string | null = null;
  if (kind === "practiceReview") {
    try {
      const since = new Date(Date.now() - 7 * 86_400_000).toISOString().slice(0, 10);
      const { data: entries } = await db
        .from("practice_entries")
        .select("mode, entry, local_date")
        .eq("user_id", enrollment.user_id)
        .gte("local_date", since)
        .order("local_date", { ascending: false });
      practiceDigest = buildPracticeDigest(entries ?? []);
    } catch (e) {
      console.error("practice digest failed (continuing without):", e);
    }
  }

  // --- marginalia time-travel (§11.5): past-self highlights on the unit span
  let pastHighlights: { bookId: string; ch: number; note?: string | null }[] = [];
  const marginaliaSpan = ctx.unitDef.reading?.[0];
  if (marginaliaSpan && enrollment.started_at) {
    try {
      const { data: past } = await db
        .from("highlights")
        .select("book_id, ch, note")
        .eq("user_id", enrollment.user_id)
        .eq("book_id", marginaliaSpan.bookID)
        .gte("ch", marginaliaSpan.chStart)
        .lte("ch", marginaliaSpan.chEnd)
        .lt("created_at", enrollment.started_at)
        .order("created_at", { ascending: false })
        .limit(6);
      pastHighlights = ((past ?? []) as { book_id: string; ch: number; note: string | null }[])
        .map((h) => ({ bookId: h.book_id, ch: h.ch, note: h.note }));
    } catch (e) {
      console.error("past-highlight lookup failed (continuing without):", e);
    }
  }

  // --- assemble the prompt ---------------------------------------------------
  const corrections: string[] = Array.isArray(state._corrections) ? state._corrections : [];
  delete state._corrections; // consumed this turn

  const contextBlock = buildContextBlock({
    relationshipMemory: enrollment.relationship_memory ?? "",
    state,
    passages,
    annotations: tc.annotations,
    corrections,
    essayBody: tc.essayBody ?? undefined,
    profileDigest: digest,
    commitmentDigest,
    practiceDigest,
    pastHighlights,
    alteredText: kind === "craftLab" && spec
      ? {
        labId: (spec as CraftLabSpec).id,
        transform: (spec as CraftLabSpec).transform,
        text: (spec as CraftLabSpec).damagedText,
      }
      : undefined,
  });

  const personaDocs = await loadPersonaDocs(db, ctx, kind, spec);

  const openingText =
    "[The student has just joined the session. Greet them briefly, in character, and begin.]";
  const prompt = buildPrompt({
    personaDocs,
    courseContext: ctx.standalone
      ? `STANDALONE SESSION: no course context — this is a ${kind} session ` +
        `between the student and Prof. ${ctx.persona.name}.`
      : courseContextBlock(ctx.courseDoc, ctx.unitDef),
    engineInstructions: instructionBlock(kind, state, {
      unit: ctx.unitDef,
      pace: enrollment.pace,
      spec,
      coReading: tc.coReading,
      profileDigestPresent: !!digest,
      commitmentDigestPresent: !!commitmentDigest,
      practiceDigestPresent: !!practiceDigest,
    }) + (tc.softBudget ? SOFT_BUDGET_NOTE : ""),
    summary: state._summary ?? null,
    rawTurns: priorTurns.slice(-KEEP_RAW_TURNS),
    contextBlock,
    userText: tc.isOpening ? openingText : (tc.userText.trim() ||
      (tc.coReading?.position
        ? `[reader at ch ${tc.coReading.position.ch}, para ${tc.coReading.position.para}${
          tc.coReading.trigger ? ` — trigger: ${tc.coReading.trigger}` : ""
        }]`
        : tc.userText)),
  });

  // --- stream from Anthropic -------------------------------------------------
  // claude-sonnet-5: no temperature/top_p/top_k, no prefill; thinking disabled
  // explicitly for this latency-sensitive turn; envelope via structured output.
  const client = anthropicClient();
  const requestParams = {
    model: MODEL_SEMINAR,
    max_tokens: MAX_TOKENS_TURN,
    thinking: { type: "disabled" as const },
    // deno-lint-ignore no-explicit-any
    system: prompt.system as any,
    messages: prompt.messages,
    output_config: {
      format: { type: "json_schema" as const, schema: ENVELOPE_SCHEMA },
    },
    // deno-lint-ignore no-explicit-any
  } as any;

  const stream = client.messages.stream(requestParams);
  const sayScanner = new SayStream();
  for await (const event of stream) {
    if (
      event.type === "content_block_delta" &&
      event.delta.type === "text_delta"
    ) {
      const chunk = sayScanner.push(event.delta.text);
      if (chunk) send("say", { delta: chunk });
    }
  }
  const final = await stream.finalMessage();
  tc.usage.add(final.usage);
  const rawText = final.content
    .filter((b) => b.type === "text")
    // deno-lint-ignore no-explicit-any
    .map((b) => (b as any).text as string)
    .join("");

  // --- parse / validate the envelope ----------------------------------------
  let envelope: Envelope;
  if (final.stop_reason === "refusal") {
    // Graceful in-character deferral.
    envelope = minimalEnvelope(
      "I'd rather not take the discussion in that direction. Let's get back " +
        "to the text — pick up where we left off, or bring me a passage " +
        "you want to look at closely.",
    );
  } else {
    try {
      envelope = parseEnvelope(rawText);
    } catch (_firstErr) {
      // Malformed envelope: retry once WITHOUT streaming, then fall back to a
      // plain reply wrapped in a minimal envelope.
      try {
        const retry = await client.messages.create(requestParams);
        tc.usage.add(retry.usage);
        const retryText = retry.content
          .filter((b: { type: string }) => b.type === "text")
          // deno-lint-ignore no-explicit-any
          .map((b: any) => b.text as string)
          .join("");
        envelope = parseEnvelope(retryText);
      } catch (_secondErr) {
        const fallbackSay = rawText.trim() ||
          "Forgive me — I lost my thread. Say that once more and we'll pick it back up.";
        envelope = minimalEnvelope(fallbackSay.slice(0, 4000));
      }
    }
  }

  // --- verify citations: quote must be a verbatim substring of the retrieved
  //     passage with that ID; drop invalid ones and queue a correction note.
  const passageById = new Map(passages.map((p) => [p.id, p]));
  const newCorrections: string[] = [];
  envelope.citations = envelope.citations.filter((c) => {
    const passage = passageById.get(c.passageId);
    if (!passage) {
      newCorrections.push(
        `Your citation of ${c.passageId} was dropped: that passage was not among the retrieved passages. Cite only passage IDs listed in <retrievedPassages>.`,
      );
      return false;
    }
    if (!passage.text.includes(c.quote)) {
      newCorrections.push(
        `Your citation of ${c.passageId} was dropped: the quote was not a verbatim substring of the passage. Copy quotes exactly.`,
      );
      return false;
    }
    return true;
  });

  // --- validate + persist profileOps (§11.1): known dimensions, weight 0..1,
  //     ≤2 per turn (extras dropped).
  const validProfileOps: ProfileOp[] = [];
  for (const p of envelope.profileOps ?? []) {
    if (validProfileOps.length >= 2) break; // extras dropped
    if (
      p.op === "evidence" &&
      (PROFILE_EVIDENCE_KINDS as readonly string[]).includes(p.kind) &&
      (PROFILE_DIMENSIONS as readonly string[]).includes(p.dimension) &&
      typeof p.weight === "number" && p.weight >= 0 && p.weight <= 1 &&
      typeof p.signal === "string" && p.signal.trim().length > 0
    ) {
      validProfileOps.push(p);
    }
  }
  envelope.profileOps = validProfileOps.length > 0 ? validProfileOps : undefined;
  if (validProfileOps.length > 0) {
    const { error: peErr } = await db.from("profile_evidence").insert(
      validProfileOps.map((p) => ({
        user_id: enrollment.user_id,
        kind: p.kind,
        dimension: p.dimension,
        signal: p.signal,
        weight: p.weight,
        ref: { sessionId: session.id, turnSeq: seq },
      })),
    );
    if (peErr) console.error("profile evidence insert failed:", peErr.message);
  }

  // --- validate commitmentOps (§12.2): known domains, known ontologyIds,
  //     ≤2 per turn (extras dropped) — persisted after state ops apply.
  let validCommitmentOps: ReturnType<typeof validateCommitmentOps> = [];
  if (envelope.commitmentOps && envelope.commitmentOps.length > 0) {
    try {
      const knownClaimIds = new Set((await claimsCatalog()).map((c) => c.id));
      validCommitmentOps = validateCommitmentOps(envelope.commitmentOps, knownClaimIds);
    } catch (e) {
      console.error("commitment op validation failed (ops dropped):", e);
    }
  }
  envelope.commitmentOps = validCommitmentOps.length > 0 ? validCommitmentOps : undefined;

  // --- apply state ops (unknown ops rejected) --------------------------------
  const applied = applyStateOps(kind, state, envelope.stateOps);
  const newState = applied.state;
  // §13.4 "the ritual stays small": a dailyQuestion session auto-completes on
  // its single reply, whether or not the model remembered completeSession.
  // §15.3: the morning intention has the same one-reply shape.
  if (
    !applied.completeSession &&
    (kind === "dailyQuestion" ||
      (kind === "practice" && state.mode === "morning" && !tc.isOpening))
  ) {
    applied.completeSession = true;
  }
  for (const rejected of applied.rejectedOps) {
    newCorrections.push(
      `Your stateOp "${rejected}" was rejected: unknown op. Use only the ops defined in the envelope contract.`,
    );
  }
  if (applied.completionRefused) {
    newCorrections.push(
      "Your completeSession was dropped: this session kind cannot complete " +
        "from its current phase. Reach the closing phase (reflection / " +
        "debrief / rebuild) with the student first, then complete.",
    );
    envelope.uiHints.endOfSession = false;
  }
  if (newCorrections.length > 0) {
    newState._corrections = newCorrections;
  }

  // One profile-aware move per session: after the first turn generated with
  // the digest in context, the move is considered spent (§11.3).
  if (digest && !newState._profileMoveUsed) {
    newState._profileMoveUsed = true;
  }

  // One commitment move per session: spent after the first turn whose digest
  // carried a tension (§12.2).
  if (commitmentDigestCarriedTension && !newState._commitmentMoveUsed) {
    newState._commitmentMoveUsed = true;
  }

  // --- markTensionReconciled (§14.2): bound to the session's raised tension.
  if (applied.tensionResolution) {
    if (raisedTensionId) {
      const { error: trErr } = await db
        .from("commitment_tensions")
        .update({
          status: "reconciled",
          resolution: applied.tensionResolution,
          resolved_at: new Date().toISOString(),
        })
        .eq("id", raisedTensionId)
        .eq("user_id", enrollment.user_id)
        .in("status", ["open", "raised"]);
      if (trErr) {
        console.error("tension reconcile failed:", trErr.message);
      } else {
        raisedTensionId = null; // consumed — single use per session
      }
    } else {
      newCorrections.push(
        "Your markTensionReconciled was dropped: no tension was raised this session. Reconcile only the tension the digest surfaced.",
      );
      newState._corrections = newCorrections;
    }
  }
  if (raisedTensionId) newState._raisedTensionId = raisedTensionId;
  else delete newState._raisedTensionId;

  // --- recordSteelmanScore (§14.4): persist once, when the kind accepted it.
  if (
    kind === "steelman" && applied.steelmanScore &&
    state.level == null && newState.level != null
  ) {
    const { error: ssErr } = await db.from("steelman_scores").insert({
      user_id: enrollment.user_id,
      target_ontology_id: newState.targetOntologyId ?? null,
      target_claim: newState.targetClaim ?? "",
      level: applied.steelmanScore.level,
      justification: applied.steelmanScore.justification,
      session_id: session.id,
    });
    if (ssErr) console.error("steelman score insert failed:", ssErr.message);
  }

  // --- persist commitmentOps (§12.2): foldOp semantics, upsert by
  //     (user_id, ontology_id) else normalized claim; source_refs appended.
  //     Bookkeeping on state feeds the §12.4 sweep (in-turn ops win).
  if (validCommitmentOps.length > 0) {
    try {
      const persisted = await persistCommitmentOps(db, enrollment.user_id, validCommitmentOps, {
        sessionId: session.id,
        turnSeq: seq,
      });
      const touched = newState._commitmentTouched ?? { ids: [], claims: [], domains: [] };
      touched.ids = [...new Set([...touched.ids, ...persisted.touchedOntologyIds])];
      touched.claims = [...new Set([...touched.claims, ...persisted.touchedClaims])];
      touched.domains = [
        ...new Set([...touched.domains, ...validCommitmentOps.map((o) => o.domain)]),
      ];
      newState._commitmentTouched = touched;
      if (persisted.strengthChanged) newState._commitmentDrift = true;
    } catch (e) {
      console.error("commitment ops persist failed:", e);
    }
  }

  // --- persist a recorded grade into the essays table ------------------------
  if (applied.gradeRecord) {
    const gr = applied.gradeRecord;
    const { data: essayRow } = await db
      .from("essays")
      .select("id")
      .eq("enrollment_id", enrollment.id)
      .eq("assignment_id", gr.assignmentId)
      .order("revision", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (essayRow) {
      await db.from("essays").update({
        feedback: {
          rubric: gr.rubric,
          marginComments: gr.marginComments,
          directives: gr.directives,
        },
        grade: gr.grade,
      }).eq("id", essayRow.id);
    } else {
      // recordGrade without a submitted draft is invalid (CONTRACTS §10).
      newState._corrections = [
        ...(newState._corrections ?? []),
        "recordGrade was ignored: no submitted draft exists for that assignment.",
      ];
      newState.phase = session.state?.phase ?? "assigned";
    }
  }

  // --- completeSession: fold memory buffer into relationship memory ----------
  if (applied.completeSession) {
    // Relationship memory + reader profile are enrollment-bound; standalone
    // sessions (§13.1) skip both at MVP.
    if (!ctx.standalone) {
      const buffer: string[] = Array.isArray(newState._memoryBuffer) ? newState._memoryBuffer : [];
      const merged = await summarizeRelationshipMemory(
        enrollment.relationship_memory ?? "",
        buffer,
        tc.usage,
      );
      await db.from("enrollments")
        .update({ relationship_memory: merged })
        .eq("id", enrollment.id);
    }
    await db.from("sessions")
      .update({ status: "completed", completed_at: new Date().toISOString() })
      .eq("id", session.id);
    envelope.uiHints.endOfSession = true;
    delete newState._memoryBuffer;

    // Practice (§15.3): journal the completed session. The entry is the
    // student's own words; the reply is kept for the morning's one response.
    // Never fails the turn; the unique constraint absorbs duplicates.
    if (ctx.standalone && kind === "practice" && newState.localDate) {
      const userWords = [
        ...priorTurns.filter((t) => t.role === "user").map((t) => t.content),
        ...(tc.userText.trim() ? [tc.userText.trim()] : []),
      ].filter((t) => t.trim());
      if (userWords.length > 0) {
        const { error: peErr } = await db.from("practice_entries").insert({
          user_id: enrollment.user_id,
          mode: newState.mode,
          exercise_id: newState.exerciseId ?? null,
          entry: userWords.join("\n"),
          reply: newState.mode === "morning" ? envelope.say : "",
          local_date: newState.localDate,
          session_id: session.id,
        });
        if (peErr && peErr.code !== "23505") {
          console.error("practice entry insert failed:", peErr.message);
        }
      }
    }

    // Weekly drop (§14.3): record the response for the crowd aggregate.
    // Never fails the turn; the unique constraint absorbs duplicates.
    if (ctx.standalone && kind === "thoughtExperiment" && newState.dropId) {
      const path = Array.isArray(newState.path) ? newState.path : [];
      const { error: drErr } = await db.from("drop_responses").insert({
        user_id: enrollment.user_id,
        drop_id: newState.dropId,
        week: typeof newState.week === "number" ? newState.week : 0,
        path,
        first_choice: path[0]?.choice ?? "",
        session_id: session.id,
      });
      if (drErr && drErr.code !== "23505") {
        console.error("drop response insert failed:", drErr.message);
      }
    }

    // Reader-profile pipeline (§11.3): decay, fold this session's evidence,
    // regenerate the narrative on drift. Never fails the turn.
    if (!ctx.standalone) {
      try {
        await updateReaderProfile(db, enrollment.user_id, session.id, tc.usage);
      } catch (e) {
        console.error("reader profile update failed:", e);
      }
    }

    // Commitment pipeline (§12.4): extraction sweep over the transcript →
    // fold (in-turn ops win) → recompute/reconcile tensions → worldview
    // snapshot when anything material changed. Never fails the turn.
    try {
      const transcript = [
        ...priorTurns.map((t) =>
          `${t.role === "user" ? "STUDENT" : "PROFESSOR"}: ${t.content}`
        ),
        ...(tc.isOpening || !tc.userText.trim() ? [] : [`STUDENT: ${tc.userText}`]),
        `PROFESSOR: ${envelope.say}`,
      ].join("\n\n");
      const touched = newState._commitmentTouched ?? { ids: [], claims: [], domains: [] };
      await runCommitmentPipeline(db, {
        userId: enrollment.user_id,
        sessionId: session.id,
        turnSeq: seq,
        transcript,
        touchedOntologyIds: touched.ids,
        touchedClaims: touched.claims,
        domains: [
          ...new Set([
            ...unitClaimDomains(ctx.unitDef),
            ...touched.domains,
            // §13.2: the daily question's own domain scopes the sweep.
            ...(kind === "dailyQuestion" && spec
              ? [(spec as DailyQuestionSpec).domain]
              : []),
          ]),
        ],
        strengthChangedInTurn: newState._commitmentDrift === true,
        claims: await claimsCatalog(),
        usage: tc.usage,
      });
    } catch (e) {
      console.error("commitment pipeline failed:", e);
    }
    delete newState._commitmentTouched;
    delete newState._commitmentDrift;
  }

  // --- persist state + professor turn ----------------------------------------
  const { error: stErr } = await db.from("sessions")
    .update({ state: newState })
    .eq("id", session.id);
  if (stErr) throw new Error(`state persist failed: ${stErr.message}`);

  // Persisted envelopes carry a server-stamped "v": 2 marker (§11.1 — not part
  // of the model-facing schema).
  const persistedEnvelope: Envelope = { ...envelope, v: 2 };

  const { error: ptErr } = await db.from("turns").insert({
    session_id: session.id,
    seq,
    role: "professor",
    content: envelope.say,
    envelope: persistedEnvelope,
  });
  if (ptErr) throw new Error(`professor turn insert failed: ${ptErr.message}`);

  send("envelope", persistedEnvelope);
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/** Days since 1970-01-01 for a YYYY-MM-DD local date (§13.2/§14.3). */
function daysSinceEpoch(localDate: string): number {
  return Math.floor(Date.parse(`${localDate}T00:00:00Z`) / 86_400_000);
}

/** §13.1 standalone starts: dailyQuestion (one round trip: tap + sentence in,
 * single reply out), argumentClinic + steelman (normal opening turn), and
 * weekly drops (§14.3 — thoughtExperiment with a dropId). */
async function handleStandaloneStart(
  db: Db,
  userId: string,
  body: RequestBody,
  send: Send,
  softBudget: boolean,
  usage: UsageAccumulator,
): Promise<void> {
  const kind = body.kind as SessionKind;

  let spec: KindSpec | undefined;
  let dailySpec: DailyQuestionSpec | undefined;
  let option: DailyQuestionSpec["options"][number] | undefined;
  let personaId: string;
  let dropWeek: number | null = null;

  if (kind === "dailyQuestion") {
    if (!body.questionId || !body.optionId) {
      throw new Error("dailyQuestion start requires questionId and optionId");
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(body.localDate ?? "")) {
      throw new Error("dailyQuestion start requires localDate (YYYY-MM-DD)");
    }
    const { data: qRow, error: qErr } = await db
      .from("daily_questions").select("doc").eq("id", body.questionId).maybeSingle();
    if (qErr) throw new Error(`daily question load failed: ${qErr.message}`);
    if (!qRow) throw new Error("daily question not found");
    dailySpec = qRow.doc as DailyQuestionSpec;
    spec = dailySpec;
    option = dailySpec.options.find((o) => o.id === body.optionId);
    if (!option) throw new Error("unknown option for that question");
    personaId = dailySpec.personaId;
  } else if (kind === "thoughtExperiment") {
    // §14.3 weekly drop.
    if (!body.dropId) throw new Error("standalone thoughtExperiment requires dropId");
    if (!/^\d{4}-\d{2}-\d{2}$/.test(body.localDate ?? "")) {
      throw new Error("drop start requires localDate (YYYY-MM-DD)");
    }
    const { data: dRow, error: dErr } = await db
      .from("drops").select("doc").eq("id", body.dropId).maybeSingle();
    if (dErr) throw new Error(`drop load failed: ${dErr.message}`);
    if (!dRow) throw new Error("drop not found");
    const doc = dRow.doc as { personaId: string; experiment: KindSpec };
    spec = doc.experiment;
    personaId = doc.personaId;
    dropWeek = Math.floor(daysSinceEpoch(body.localDate!) / 7);
  } else if (kind === "steelman") {
    // §14.4: the target is one of the student's own positions.
    if (!body.targetClaim?.trim()) throw new Error("steelman start requires targetClaim");
    if (body.targetOntologyId) {
      const { data: claimRow } = await db
        .from("claims").select("id").eq("id", body.targetOntologyId).maybeSingle();
      if (!claimRow) throw new Error(`unknown targetOntologyId: ${body.targetOntologyId}`);
    }
    personaId = body.personaId ?? "whitmore";
  } else if (kind === "newsRead") {
    // §15.2: teach from the week's cached brief; generate it on first start.
    if (!/^\d{4}-\d{2}-\d{2}$/.test(body.localDate ?? "")) {
      throw new Error("newsRead start requires localDate (YYYY-MM-DD)");
    }
    const week = Math.floor(daysSinceEpoch(body.localDate!) / 7);
    let brief = await loadNewsBrief(db, week);
    if (!brief) {
      try {
        brief = await generateNewsBrief(db, week, usage);
      } catch (e) {
        console.error("news brief generation failed:", e);
        throw new Error("this week's question isn't ready — try again shortly");
      }
    }
    spec = { brief };
    dropWeek = week; // reuse the stamp below
    personaId = body.personaId ?? "whitmore";
  } else if (kind === "practice") {
    // §15.3: the Stoic wing runs with Bede, always.
    if (!/^\d{4}-\d{2}-\d{2}$/.test(body.localDate ?? "")) {
      throw new Error("practice start requires localDate (YYYY-MM-DD)");
    }
    const mode = body.mode;
    if (mode !== "morning" && mode !== "evening" && mode !== "visualization") {
      throw new Error("practice start requires mode (morning|evening|visualization)");
    }
    const exerciseId = mode === "evening" ? "examen" : body.exerciseId;
    if (!exerciseId) throw new Error(`practice ${mode} requires exerciseId`);
    const { data: exRow, error: exErr } = await db
      .from("practice_exercises").select("kind, doc").eq("id", exerciseId).maybeSingle();
    if (exErr) throw new Error(`exercise load failed: ${exErr.message}`);
    if (!exRow) throw new Error(`unknown exerciseId: ${exerciseId}`);
    const wantKind = mode === "evening" ? "examen" : mode;
    if (exRow.kind !== wantKind) {
      throw new Error(`exercise ${exerciseId} is not a ${wantKind} exercise`);
    }
    spec = { mode, exercise: exRow.doc as PracticeExerciseDoc } as PracticeSpec;
    personaId = "bede";
  } else if (kind === "practiceReview") {
    personaId = "bede";
  } else {
    personaId = body.personaId ?? "whitmore";
  }

  const { data: persona, error: pErr } = await db
    .from("personas").select("*").eq("id", personaId).maybeSingle();
  if (pErr || !persona) {
    throw new Error(`persona load failed: ${pErr?.message ?? `not found: ${personaId}`}`);
  }

  const state = initialState(kind, STANDALONE_UNIT, { spec });
  if (kind === "dailyQuestion") state.optionId = body.optionId;
  if (kind === "thoughtExperiment" && body.dropId) {
    state.dropId = body.dropId;
    state.week = dropWeek;
  }
  if (kind === "steelman") {
    state.targetClaim = body.targetClaim!.trim();
    state.targetOntologyId = body.targetOntologyId ?? null;
  }
  if (kind === "newsRead") state.week = dropWeek;
  if (kind === "practice") state.localDate = body.localDate;

  const { data: session, error: sErr } = await db
    .from("sessions")
    .insert({ user_id: userId, persona_id: personaId, unit: 0, kind, state })
    .select()
    .single();
  if (sErr) throw new Error(`session create failed: ${sErr.message}`);

  if (kind === "dailyQuestion" && dailySpec && option) {
    // One answer per user per local date (§13.2) — the unique constraint is
    // the gate; on conflict the just-created session is removed again.
    const { error: aErr } = await db.from("daily_answers").insert({
      user_id: userId,
      question_id: dailySpec.id,
      question_date: body.localDate,
      option_id: option.id,
      sentence: (body.userText ?? "").trim(),
      session_id: session.id,
    });
    if (aErr) {
      await db.from("sessions").delete().eq("id", session.id);
      if (aErr.code === "23505") {
        throw new Error("you already answered today's question");
      }
      throw new Error(`daily answer insert failed: ${aErr.message}`);
    }

    // Deterministic commitment write (§13.2 / A17): the tap enters the map at
    // 'lean' via the normal fold; 'assert' only ever comes from the model
    // reading the typed sentence.
    if (option.ontologyId) {
      try {
        const claims = await loadClaims(db);
        const claim = claims.find((c) => c.id === option!.ontologyId);
        if (claim) {
          const persisted = await persistCommitmentOps(db, userId, [{
            op: "lean",
            claim: claim.claim,
            domain: claim.domain as CommitmentOp["domain"],
            ontologyId: claim.id,
            evidence: `Daily Question ${dailySpec.id}: tapped "${option.label}"`,
          }], { sessionId: session.id, turnSeq: 1 });
          state._commitmentTouched = {
            ids: persisted.touchedOntologyIds,
            claims: persisted.touchedClaims,
            domains: [claim.domain],
          };
          if (persisted.strengthChanged) state._commitmentDrift = true;
          await db.from("sessions").update({ state }).eq("id", session.id);
          session.state = state;
        }
      } catch (e) {
        console.error("daily deterministic commitment failed (continuing):", e);
      }
    }
  }

  send("session", { sessionId: session.id, kind: session.kind, unit: session.unit });

  const ctx: LoadedContext = {
    enrollment: syntheticEnrollment(userId),
    course: null,
    courseDoc: standaloneCourseDoc(personaId),
    persona,
    unitDef: STANDALONE_UNIT,
    standalone: true,
    standaloneSpec: spec,
  };

  // dailyQuestion: the tap + sentence IS the user turn; the reply completes
  // the session. argumentClinic: normal in-character opening.
  await runProfessorTurn(
    {
      db,
      session,
      ctx,
      userText: kind === "dailyQuestion" && option
        ? `[tapped: "${option.label}"] ${(body.userText ?? "").trim()}`.trim()
        : "",
      annotations: [],
      essayBody: null,
      isOpening: kind !== "dailyQuestion",
      softBudget,
      usage,
    },
    send,
  );
}

async function handleStart(
  db: Db,
  userId: string,
  body: RequestBody,
  send: Send,
  softBudget: boolean,
  usage: UsageAccumulator,
): Promise<void> {
  if (
    body.kind &&
    (STANDALONE_KINDS.includes(body.kind) ||
      (body.kind === "thoughtExperiment" && body.dropId))
  ) {
    return handleStandaloneStart(db, userId, body, send, softBudget, usage);
  }
  if (!body.enrollmentId) throw new Error("start requires enrollmentId");
  if (!body.kind || !KINDS.includes(body.kind)) {
    throw new Error(`start requires kind (one of ${KINDS.join("|")})`);
  }
  if (typeof body.unit !== "number") throw new Error("start requires unit (number)");

  const ctx = await loadEnrollmentContext(db, userId, body.enrollmentId, body.unit);

  // Quiz questions are generated with MODEL_LIGHT from the unit's reading-span
  // passages (SCOPE §3.2.6).
  let quizQuestions: QuizQuestion[] | undefined;
  if (body.kind === "quiz") {
    const span = ctx.unitDef.reading?.[0];
    if (span) {
      const { data: spanPassages } = await db
        .from("passages")
        .select("id, text")
        .eq("book_id", span.bookID)
        .gte("ch", span.chStart)
        .lte("ch", span.chEnd)
        .order("ch", { ascending: true })
        .order("para", { ascending: true })
        .limit(12);
      quizQuestions = await generateQuizQuestions(ctx.unitDef, spanPassages ?? [], usage);
    } else {
      quizQuestions = [];
    }
  }

  // Spec-driven kinds (disputation / craftLab / elenchus / thoughtExperiment
  // / argumentLab) load their authored spec (request may carry specId; else
  // the unit's first spec of that kind).
  let spec: KindSpec | undefined;
  if (SPEC_KINDS.includes(body.kind)) {
    spec = resolveSpec(body.kind, ctx.unitDef, body.specId);
    if (!spec) {
      throw new Error(`this unit has no ${body.kind} spec${body.specId ? ` "${body.specId}"` : ""}`);
    }
  }

  const state = initialState(body.kind, ctx.unitDef, { quizQuestions, spec });

  const { data: session, error: sErr } = await db
    .from("sessions")
    .insert({
      enrollment_id: ctx.enrollment.id,
      unit: body.unit,
      kind: body.kind,
      state,
    })
    .select()
    .single();
  if (sErr) throw new Error(`session create failed: ${sErr.message}`);

  send("session", { sessionId: session.id, kind: session.kind, unit: session.unit });

  // Opening professor turn (lecture segment 1 / first seminar question / ...).
  await runProfessorTurn(
    {
      db,
      session,
      ctx,
      userText: "",
      annotations: [],
      essayBody: null,
      isOpening: true,
      softBudget,
      usage,
      coReading: body.kind === "coReading"
        ? { waypointId: body.waypointId, position: body.position, trigger: body.trigger }
        : undefined,
    },
    send,
  );
}

async function handleTurn(
  db: Db,
  userId: string,
  body: RequestBody,
  send: Send,
  softBudget: boolean,
  usage: UsageAccumulator,
): Promise<void> {
  if (!body.sessionId) throw new Error("turn requires sessionId");

  const { data: session, error: sErr } = await db
    .from("sessions").select("*").eq("id", body.sessionId).maybeSingle();
  if (sErr) throw new Error(`session load failed: ${sErr.message}`);
  if (!session) throw new Error("session not found");
  if (session.status !== "active") throw new Error("session is completed");

  const ctx = session.enrollment_id
    ? await loadEnrollmentContext(db, userId, session.enrollment_id, session.unit)
    : await loadStandaloneContext(db, userId, session);

  const userText = (body.userText ?? "").trim();
  const essayBody = (body.essayBody ?? "").trim() || null;

  // coReading turns are trigger-driven and may carry no text — position /
  // trigger / annotations are the payload (§11.2).
  if (!userText && !essayBody && session.kind !== "coReading") {
    throw new Error("turn requires userText (or essayBody for essay sessions)");
  }

  // Guardrail (CONTRACTS §10, mechanical): grading requires a non-empty
  // student draft. In an essay session no draft is on file until the first
  // submission — reject draftless turns while the assignment is outstanding.
  if (session.kind === "essay" && !essayBody && session.state?.phase === "assigned") {
    throw new Error(
      "essay sessions require your draft: include a non-empty essayBody " +
        "(the professor won't discuss an unwritten essay)",
    );
  }

  await runProfessorTurn(
    {
      db,
      session,
      ctx,
      userText,
      annotations: body.userAnnotations ?? [],
      essayBody,
      isOpening: false,
      softBudget,
      usage,
      coReading: session.kind === "coReading"
        ? { waypointId: body.waypointId, position: body.position, trigger: body.trigger }
        : undefined,
    },
    send,
  );
}

// ---------------------------------------------------------------------------
// HTTP entry point
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "POST only" });
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { error: "invalid JSON body" });
  }
  if (body.action !== "start" && body.action !== "turn") {
    return jsonResponse(400, { error: "action must be 'start' or 'turn'" });
  }

  // Verify the caller's JWT via supabase-js with the incoming Authorization
  // header (CONTRACTS §4).
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse(401, { error: "missing Authorization header" });
  }
  let userId: string;
  try {
    const caller = callerClient(authHeader);
    const { data, error } = await caller.auth.getUser();
    if (error || !data?.user) {
      return jsonResponse(401, { error: "invalid or expired JWT" });
    }
    userId = data.user.id;
  } catch (e) {
    return jsonResponse(401, { error: `auth failed: ${(e as Error).message}` });
  }

  const db = serviceClient();

  // --- usage budget check (CONTRACTS §4.3) ----------------------------------
  // One upsert-read round trip via the record_usage RPC, before the SSE stream
  // opens — a hard-limit hit returns HTTP 429 JSON here. (If a limit were ever
  // detected after streaming begins, the catch below emits event:error with
  // code "budget_exceeded" instead.) "start" counts as a turn too.
  let softBudget = false;
  try {
    const usageRow = await readTodayUsage(db, userId);
    const status = checkBudget(usageRow);
    if (status.exceeded) {
      return jsonResponse(429, {
        code: "budget_exceeded",
        message: BUDGET_MESSAGES[status.exceeded],
      });
    }
    softBudget = status.soft;
  } catch (e) {
    // Fail open: never block a student because the ledger hiccupped.
    console.error("budget check failed (continuing):", e);
  }

  const usage = new UsageAccumulator();
  const encoder = new TextEncoder();

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const send: Send = (event, data) => {
        controller.enqueue(
          encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`),
        );
      };
      try {
        if (body.action === "start") {
          await handleStart(db, userId, body, send, softBudget, usage);
        } else {
          await handleTurn(db, userId, body, send, softBudget, usage);
        }
      } catch (e) {
        console.error("session function error:", e);
        const err = e as Error & { code?: string };
        send("error", {
          ...(err.code ? { code: err.code } : {}),
          message: err.message ?? "internal error",
        });
      } finally {
        // Record this request's usage: one turn + all model-call tokens, in a
        // single upsert (skipped when no model call was made).
        try {
          await recordUsage(db, userId, usage);
        } catch (e) {
          console.error("usage recording failed:", e);
        }
        send("done", {});
        controller.close();
      }
    },
  });

  return new Response(stream, { headers: SSE_HEADERS });
});
