// Prompt assembly (CONTRACTS §6).
//
// Order (stable -> volatile, for prompt caching):
//   1. persona doc            (system block, cache_control: ephemeral)
//   2. course/unit context    (system block, cache_control on last block)
//   3. engine instruction block (system, uncached — changes every turn)
//   4. messages: summarized older turns -> last N (=12) raw turns ->
//      latest user message carrying the <context> block (relationship memory +
//      session state + retrieved passages with IDs + user annotations) + the
//      user's new input.
//
// Turns older than the last 12 are summarized with MODEL_LIGHT; the summary is
// stored in sessions.state._summary (with _summaryUpto) and reused.

import {
  anthropicClient,
  MAX_TOKENS_SUMMARY,
  MODEL_LIGHT,
} from "./anthropic.ts";
import type { UsageSink } from "./budget.ts";
import type { CourseDoc, CourseUnit, SessionState } from "./engine.ts";
import type { Passage } from "./retrieval.ts";

/** Raw turns kept verbatim in the prompt; older ones are summarized. */
export const KEEP_RAW_TURNS = 12;

export interface TurnRow {
  seq: number;
  role: "user" | "professor";
  content: string;
}

export interface UserAnnotation {
  passageId: string;
  quote?: string;
  note?: string;
}

export interface SystemBlock {
  type: "text";
  text: string;
  cache_control?: { type: "ephemeral" };
}

export interface PromptMessage {
  role: "user" | "assistant";
  content: string;
}

// ---------------------------------------------------------------------------
// Turn summarization (MODEL_LIGHT, reused via state._summary)
// ---------------------------------------------------------------------------

/**
 * Ensure state._summary covers every turn older than the last KEEP_RAW_TURNS.
 * Mutates `state` (_summary, _summaryUpto) when new turns need folding in;
 * returns true if state changed (caller persists it).
 */
export async function ensureTurnSummary(
  state: SessionState,
  turns: TurnRow[],
  usage?: UsageSink,
): Promise<boolean> {
  if (turns.length <= KEEP_RAW_TURNS) return false;

  const older = turns.slice(0, turns.length - KEEP_RAW_TURNS);
  const coveredUpto: number = state._summaryUpto ?? -1;
  const fresh = older.filter((t) => t.seq > coveredUpto);
  if (fresh.length === 0) return false; // existing summary already covers them

  const transcript = fresh
    .map((t) => `${t.role === "user" ? "STUDENT" : "PROFESSOR"}: ${t.content}`)
    .join("\n\n");

  const client = anthropicClient();
  const stream = client.messages.stream({
    model: MODEL_LIGHT,
    max_tokens: MAX_TOKENS_SUMMARY,
    system:
      "Summarize this teaching-session transcript segment into compact plain " +
      "text (max ~300 words) a professor can use to continue seamlessly: " +
      "positions the student took, evidence cited, corrections made, open " +
      "threads, commitments. Merge with the prior summary if given. Output " +
      "ONLY the summary text.",
    messages: [{
      role: "user",
      content: `PRIOR SUMMARY:\n${state._summary ?? "(none)"}\n\nNEW TRANSCRIPT SEGMENT:\n${transcript}`,
    }],
  });
  const final = await stream.finalMessage();
  usage?.add(final.usage);
  const text = final.content
    .filter((b) => b.type === "text")
    .map((b) => (b as { text: string }).text)
    .join("")
    .trim();

  if (text) {
    state._summary = text;
    state._summaryUpto = older[older.length - 1].seq;
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Course/unit context block (stable per unit -> cacheable)
// ---------------------------------------------------------------------------

export function courseContextBlock(course: CourseDoc, unit: CourseUnit): string {
  const reading = (unit.reading ?? [])
    .map((r) => `${r.bookID} chapters ${r.chStart}-${r.chEnd} (inclusive)`)
    .join("; ");
  const texts = (course.texts ?? [])
    .map((t) => `${t.bookID}${t.title ? ` — ${t.title}` : ""}${t.author ? ` (${t.author})` : ""}`)
    .join("\n  ");
  return `COURSE CONTEXT
Course: ${course.title} (${course.id})${course.difficulty ? ` — ${course.difficulty}` : ""}
${course.description ?? ""}
Texts:
  ${texts || "(none)"}
Current unit ${unit.number}: ${unit.title}
Assigned reading this unit: ${reading || "(none)"}
${unit.recapNotes ? `Unit recap notes: ${unit.recapNotes}` : ""}`;
}

// ---------------------------------------------------------------------------
// <context> block (inside the latest user message)
// ---------------------------------------------------------------------------

export interface PastHighlight {
  bookId: string;
  ch: number;
  note?: string | null;
}

export interface AlteredText {
  labId: string;
  transform: string;
  text: string;
}

export interface ContextBlockInput {
  relationshipMemory: string;
  state: SessionState;
  passages: Passage[];
  annotations?: UserAnnotation[];
  /** Correction notes queued from the previous turn (dropped citations etc). */
  corrections?: string[];
  essayBody?: string;
  /** Reader-profile digest (§11.3) — injected right after relationship memory. */
  profileDigest?: string | null;
  /** Commitment digest (§12.2) — injected right after the profile digest,
   * only when the user has ≥3 non-abandoned commitments. Already wrapped in
   * <commitments> tags by buildCommitmentDigest. */
  commitmentDigest?: string | null;
  /** Practice digest (§15.3): last 7 days of practice entries, for
   * practiceReview sessions. */
  practiceDigest?: string | null;
  /** Marginalia time-travel: highlights from a PRIOR enrollment (§11.5). */
  pastHighlights?: PastHighlight[];
  /** craftLab damaged text (§11.2) — clearly marked as the ALTERED version. */
  alteredText?: AlteredText;
}

export function buildContextBlock(input: ContextBlockInput): string {
  const parts: string[] = [];

  parts.push(
    `<relationshipMemory>\n${input.relationshipMemory || "(first sessions — no memory yet)"}\n</relationshipMemory>`,
  );

  if (input.profileDigest) {
    parts.push(
      `<readerProfile note="how this student reads — observations with receipts; at most ONE profile-aware move per session">\n${input.profileDigest}\n</readerProfile>`,
    );
  }

  if (input.commitmentDigest) {
    parts.push(input.commitmentDigest);
  }

  if (input.practiceDigest) {
    parts.push(`<practiceDigest>\n${input.practiceDigest}\n</practiceDigest>`);
  }

  // Session state without internal bookkeeping fields.
  const publicState = Object.fromEntries(
    Object.entries(input.state).filter(([k]) => !k.startsWith("_")),
  );
  parts.push(`<sessionState>\n${JSON.stringify(publicState)}\n</sessionState>`);

  const passageText = input.passages.length
    ? input.passages
      .map((p) => `<passage id="${p.id}" book="${p.bookId}" ch="${p.ch}">\n${p.text}\n</passage>`)
      .join("\n")
    : "(no passages retrieved this turn)";
  parts.push(
    `<retrievedPassages note="quotes in citations MUST be verbatim substrings of these, cited by id">\n${passageText}\n</retrievedPassages>`,
  );

  const annotationLines: string[] = [];
  for (const a of input.annotations ?? []) {
    annotationLines.push(
      `<annotation passageId="${a.passageId}">${a.quote ? ` highlighted: "${a.quote}"` : ""}${a.note ? ` note: "${a.note}"` : ""}</annotation>`,
    );
  }
  // Marginalia time-travel: past-self notes ride in as annotations tagged past:true.
  for (const h of (input.pastHighlights ?? []).slice(0, 6)) {
    annotationLines.push(
      `<annotation past="true" book="${h.bookId}" ch="${h.ch}">${h.note ? ` note: "${h.note}"` : " (highlight, no note)"}</annotation>`,
    );
  }
  if (annotationLines.length > 0) {
    parts.push(
      `<userAnnotations note="annotations with past='true' are the student's own marginalia from a PREVIOUS enrollment — you may reference them ('past you marked this')">\n${
        annotationLines.join("\n")
      }\n</userAnnotations>`,
    );
  }

  if (input.alteredText) {
    parts.push(
      `<alteredText labId="${input.alteredText.labId}" transform="${input.alteredText.transform}" note="THIS IS THE DAMAGED/ALTERED VERSION authored for the craft lab — NEVER the author's text, NEVER quotable via citations">\n${input.alteredText.text}\n</alteredText>`,
    );
  }

  if (input.corrections && input.corrections.length > 0) {
    parts.push(
      `<serverCorrections note="issues with your previous turn — do better this turn">\n- ${
        input.corrections.join("\n- ")
      }\n</serverCorrections>`,
    );
  }

  if (input.essayBody) {
    parts.push(`<essayBody>\n${input.essayBody}\n</essayBody>`);
  }

  return `<context>\n${parts.join("\n")}\n</context>`;
}

// ---------------------------------------------------------------------------
// Full prompt
// ---------------------------------------------------------------------------

export interface BuildPromptInput {
  /** One or more persona docs — disputation sessions carry BOTH personas. */
  personaDocs: string[];
  courseContext: string;
  engineInstructions: string;
  summary: string | null;
  rawTurns: TurnRow[]; // the last KEEP_RAW_TURNS raw turns
  contextBlock: string;
  userText: string;
}

export function buildPrompt(input: BuildPromptInput): {
  system: SystemBlock[];
  messages: PromptMessage[];
} {
  const system: SystemBlock[] = [
    // 1. persona doc(s) — stable; one block per persona, cache breakpoint on
    //    the LAST persona block (a breakpoint caches the whole prefix, so one
    //    marker covers all persona docs).
    ...input.personaDocs.map((doc, i): SystemBlock => (
      i === input.personaDocs.length - 1
        ? { type: "text", text: doc, cache_control: { type: "ephemeral" } }
        : { type: "text", text: doc }
    )),
    // 2. course/unit context — stable per unit; cache breakpoint on the last
    //    course-context block (CONTRACTS §6)
    {
      type: "text",
      text: input.courseContext,
      cache_control: { type: "ephemeral" },
    },
    // 3. engine instructions — volatile (contains current state), uncached
    { type: "text", text: input.engineInstructions },
  ];

  const messages: PromptMessage[] = [];

  if (input.summary) {
    messages.push({
      role: "user",
      content: `<summaryOfEarlierTurns>\n${input.summary}\n</summaryOfEarlierTurns>`,
    });
  }

  for (const t of input.rawTurns) {
    messages.push({
      role: t.role === "user" ? "user" : "assistant",
      content: t.content,
    });
  }

  // Latest user message: <context> block + the student's new input.
  messages.push({
    role: "user",
    content: `${input.contextBlock}\n\n${input.userText}`,
  });

  // The API requires the first message to be role "user" (and claude-sonnet-5
  // forbids assistant prefill, so the last message must be user — it is).
  if (messages[0].role !== "user") {
    messages.unshift({
      role: "user",
      content: "[Session in progress — transcript resumes below.]",
    });
  }

  return { system, messages };
}
