// Reader Profile pipeline (CONTRACTS §11.3).
//
// On completeSession (same job as relationship-memory folding) the server:
//   1) applies exponential decay (×0.98 per day since updated_at) to
//      dimension scores,
//   2) folds the session's accumulated profile_evidence into dimension scores
//      (bounded 0..1; confidence grows with evidence count),
//   3) regenerates narrative_summary with MODEL_LIGHT when cumulative drift
//      since the last summary exceeds 0.15 (~150 words, professor-register,
//      receipts not psychology).
//
// Injection: profileDigest() renders a ~200-token digest (top-2 strengths,
// top-2 growth edges, avoidances with receipts, narrative summary) — only
// when a profile row exists AND some dimension has evidenceCount ≥ 5.

import {
  anthropicClient,
  MAX_TOKENS_SUMMARY,
  MODEL_LIGHT,
} from "./anthropic.ts";
import type { UsageSink } from "./budget.ts";
import { PROFILE_DIMENSIONS } from "./envelope.ts";

// ---------------------------------------------------------------------------
// Shapes (§11.3 dimensions jsonb)
// ---------------------------------------------------------------------------

export interface DimensionEntry {
  score: number; // 0..1
  confidence: number; // 0..1, grows with evidence count
  trend: number; // net score movement in the most recent fold
  evidenceCount: number; // gates injection (≥ 5) — additive to the §11.3 shape
}

export interface Avoidance {
  observation: string;
  evidenceCount: number;
}

export interface ProfileDimensions {
  attention: Record<string, DimensionEntry>;
  habits?: Record<string, number>;
  avoidances?: Avoidance[];
  strengths?: string[];
  growthEdges?: string[];
  /** Internal: cumulative score drift since narrative_summary was last regenerated. */
  _driftSinceSummary?: number;
}

export interface ReaderProfileRow {
  user_id: string;
  dimensions: ProfileDimensions;
  narrative_summary: string;
  updated_at: string;
}

interface EvidenceRow {
  kind: string;
  dimension: string;
  signal: string;
  weight: number;
  created_at: string;
}

// deno-lint-ignore no-explicit-any
type Db = any;

const DECAY_PER_DAY = 0.98;
const LEARNING_RATE = 0.15;
const DRIFT_THRESHOLD = 0.15;
const MIN_EVIDENCE_FOR_INJECTION = 5;
const MIN_EVIDENCE_FOR_CLAIMS = 3;

function clamp01(n: number): number {
  return Math.max(0, Math.min(1, n));
}

function defaultEntry(): DimensionEntry {
  return { score: 0.5, confidence: 0, trend: 0, evidenceCount: 0 };
}

function normalizedDimensions(raw: unknown): ProfileDimensions {
  const dims = (raw && typeof raw === "object" ? raw : {}) as ProfileDimensions;
  const attention: Record<string, DimensionEntry> = {};
  for (const d of PROFILE_DIMENSIONS) {
    const e = dims.attention?.[d];
    attention[d] = e
      ? {
        score: typeof e.score === "number" ? e.score : 0.5,
        confidence: typeof e.confidence === "number" ? e.confidence : 0,
        trend: typeof e.trend === "number" ? e.trend : 0,
        evidenceCount: typeof e.evidenceCount === "number" ? e.evidenceCount : 0,
      }
      : defaultEntry();
  }
  return {
    ...dims,
    attention,
    avoidances: Array.isArray(dims.avoidances) ? dims.avoidances : [],
    strengths: Array.isArray(dims.strengths) ? dims.strengths : [],
    growthEdges: Array.isArray(dims.growthEdges) ? dims.growthEdges : [],
    _driftSinceSummary: typeof dims._driftSinceSummary === "number" ? dims._driftSinceSummary : 0,
  };
}

// ---------------------------------------------------------------------------
// Update pipeline (called from the completeSession path)
// ---------------------------------------------------------------------------

export async function updateReaderProfile(
  db: Db,
  userId: string,
  sessionId: string,
  usage?: UsageSink,
): Promise<void> {
  // Evidence persisted for this session by the turn handler.
  const { data: evidenceData, error: evErr } = await db
    .from("profile_evidence")
    .select("kind, dimension, signal, weight, created_at")
    .eq("user_id", userId)
    .contains("ref", { sessionId });
  if (evErr) throw new Error(`profile evidence load failed: ${evErr.message}`);
  const evidence = (evidenceData ?? []) as EvidenceRow[];

  const { data: profileRow, error: pErr } = await db
    .from("reader_profiles")
    .select("*")
    .eq("user_id", userId)
    .maybeSingle();
  if (pErr) throw new Error(`reader profile load failed: ${pErr.message}`);

  if (!profileRow && evidence.length === 0) return; // nothing to do

  const dims = normalizedDimensions(profileRow?.dimensions);
  let drift = 0;

  // 1) Exponential decay on dimension scores: ×0.98 per day since updated_at.
  if (profileRow?.updated_at) {
    const days = Math.max(
      0,
      (Date.now() - new Date(profileRow.updated_at).getTime()) / 86_400_000,
    );
    const factor = Math.pow(DECAY_PER_DAY, days);
    for (const d of PROFILE_DIMENSIONS) {
      const entry = dims.attention[d];
      const before = entry.score;
      entry.score = clamp01(entry.score * factor);
      drift += Math.abs(entry.score - before);
    }
  }

  // 2) Fold this session's evidence into the dimension scores.
  const latestSignalByDim: Record<string, string> = {};
  for (const d of PROFILE_DIMENSIONS) dims.attention[d].trend = 0;
  for (const e of evidence) {
    const entry = dims.attention[e.dimension];
    if (!entry) continue; // unknown dimension already filtered at write time
    const w = clamp01(e.weight);
    const before = entry.score;
    entry.score = clamp01(before + LEARNING_RATE * w * (1 - before));
    entry.evidenceCount += 1;
    entry.confidence = clamp01(1 - Math.pow(0.85, entry.evidenceCount));
    entry.trend += entry.score - before;
    drift += Math.abs(entry.score - before);
    latestSignalByDim[e.dimension] = e.signal;
  }

  // Derive strengths / growth edges / avoidances (receipts, not psychology).
  const ranked = PROFILE_DIMENSIONS
    .map((d) => ({ d, e: dims.attention[d] }))
    .filter(({ e }) => e.evidenceCount >= MIN_EVIDENCE_FOR_CLAIMS);
  const byScoreDesc = [...ranked].sort((a, b) => b.e.score - a.e.score);
  dims.strengths = byScoreDesc.slice(0, 2).map(({ d, e }) =>
    `${d}: attends reliably (${e.evidenceCount} signals${
      latestSignalByDim[d] ? `; latest: "${latestSignalByDim[d]}"` : ""
    })`
  );
  dims.growthEdges = byScoreDesc.slice(-2).reverse()
    .filter(({ e }) => e.score < 0.6)
    .map(({ d, e }) =>
      `${d}: under-attended (score ${e.score.toFixed(2)}, ${e.evidenceCount} signals${
        latestSignalByDim[d] ? `; latest: "${latestSignalByDim[d]}"` : ""
      })`
    );
  dims.avoidances = ranked
    .filter(({ e }) => e.score < 0.3)
    .map(({ d, e }) => ({
      observation: `rarely engages ${d}${
        latestSignalByDim[d] ? ` — e.g., "${latestSignalByDim[d]}"` : ""
      }`,
      evidenceCount: e.evidenceCount,
    }));

  // 3) Regenerate the narrative summary when cumulative drift exceeds 0.15.
  dims._driftSinceSummary = (dims._driftSinceSummary ?? 0) + drift;
  let narrative = profileRow?.narrative_summary ?? "";
  if (dims._driftSinceSummary > DRIFT_THRESHOLD) {
    narrative = await regenerateNarrative(db, userId, dims, usage);
    dims._driftSinceSummary = 0;
  }

  const { error: upErr } = await db.from("reader_profiles").upsert({
    user_id: userId,
    dimensions: dims,
    narrative_summary: narrative,
    updated_at: new Date().toISOString(),
  });
  if (upErr) throw new Error(`reader profile upsert failed: ${upErr.message}`);
}

async function regenerateNarrative(
  db: Db,
  userId: string,
  dims: ProfileDimensions,
  usage?: UsageSink,
): Promise<string> {
  // Recent receipts for the summary.
  const { data: recent } = await db
    .from("profile_evidence")
    .select("dimension, signal, weight")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(12);

  const table = PROFILE_DIMENSIONS
    .map((d) => {
      const e = dims.attention[d];
      return `${d}: score ${e.score.toFixed(2)}, confidence ${e.confidence.toFixed(2)}, n=${e.evidenceCount}`;
    })
    .join("\n");
  const receipts = ((recent ?? []) as EvidenceRow[])
    .map((r) => `- [${r.dimension}] ${r.signal}`)
    .join("\n");

  const client = anthropicClient();
  const stream = client.messages.stream({
    model: MODEL_LIGHT,
    max_tokens: MAX_TOKENS_SUMMARY,
    system:
      "Write a reader profile in a professor's register — about 150 words, " +
      "plain text. Describe how this student READS: what they reliably " +
      "notice, what they walk past, citing the concrete receipts provided " +
      "(observations of reading behavior), never psychologizing the person. " +
      "Honest, warm, specific. Output ONLY the profile text.",
    messages: [{
      role: "user",
      content: `Attention dimensions:\n${table}\n\nRecent evidence (receipts):\n${
        receipts || "(none)"
      }`,
    }],
  });
  const final = await stream.finalMessage();
  usage?.add(final.usage);
  return final.content
    .filter((b: { type: string }) => b.type === "text")
    // deno-lint-ignore no-explicit-any
    .map((b: any) => b.text as string)
    .join("")
    .trim();
}

// ---------------------------------------------------------------------------
// Injection digest (~200 tokens)
// ---------------------------------------------------------------------------

/**
 * Render the profile digest for prompt injection, or null when the gate fails
 * (no profile row / no dimension with evidenceCount ≥ 5).
 */
export function profileDigest(profile: ReaderProfileRow | null): string | null {
  if (!profile) return null;
  const dims = normalizedDimensions(profile.dimensions);
  const surfaced = PROFILE_DIMENSIONS.filter(
    (d) => dims.attention[d].evidenceCount >= MIN_EVIDENCE_FOR_INJECTION,
  );
  if (surfaced.length === 0) return null;

  const parts: string[] = [];
  if (dims.strengths && dims.strengths.length > 0) {
    parts.push(`Strengths: ${dims.strengths.slice(0, 2).join(" | ")}`);
  }
  if (dims.growthEdges && dims.growthEdges.length > 0) {
    parts.push(`Growth edges: ${dims.growthEdges.slice(0, 2).join(" | ")}`);
  }
  if (dims.avoidances && dims.avoidances.length > 0) {
    parts.push(
      `Avoidances: ${
        dims.avoidances
          .slice(0, 3)
          .map((a) => `${a.observation} (n=${a.evidenceCount})`)
          .join(" | ")
      }`,
    );
  }
  if (profile.narrative_summary) {
    parts.push(`Summary: ${profile.narrative_summary}`);
  }
  if (parts.length === 0) return null;
  return parts.join("\n").slice(0, 1200); // ≈ 200-300 tokens hard cap
}

/** Load the caller's reader profile row (service client). */
export async function loadReaderProfile(
  db: Db,
  userId: string,
): Promise<ReaderProfileRow | null> {
  const { data, error } = await db
    .from("reader_profiles")
    .select("*")
    .eq("user_id", userId)
    .maybeSingle();
  if (error) {
    console.error("reader profile load failed:", error.message);
    return null;
  }
  return (data as ReaderProfileRow) ?? null;
}
