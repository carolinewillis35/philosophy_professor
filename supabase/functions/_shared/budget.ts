// Usage budget (CONTRACTS §4.3).
//
// Env-tunable limits; the budget check runs once per request (before any
// model call) via the record_usage RPC with zero deltas — a single upsert-read
// round trip. Token usage from every model call in the request is accumulated
// in memory and recorded with ONE final record_usage upsert (turns +1).

export const DAILY_TURN_LIMIT: number = parseLimit("DAILY_TURN_LIMIT", 150);
export const DAILY_OUTPUT_TOKEN_LIMIT: number = parseLimit(
  "DAILY_OUTPUT_TOKEN_LIMIT",
  120_000,
);

/** Soft threshold: ≥80% of either limit — degrade gracefully, never cut off. */
export const SOFT_THRESHOLD = 0.8;

function parseLimit(env: string, fallback: number): number {
  const raw = Deno.env.get(env);
  const n = raw ? parseInt(raw, 10) : NaN;
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

export interface UsageRow {
  user_id: string;
  day: string;
  turns: number;
  input_tokens: number;
  output_tokens: number;
}

/** Accumulates usage across the model calls made while serving one request. */
export class UsageAccumulator {
  inputTokens = 0;
  outputTokens = 0;
  modelCalls = 0;

  add(usage: { input_tokens?: number | null; output_tokens?: number | null } | null | undefined): void {
    if (!usage) return;
    this.modelCalls += 1;
    this.inputTokens += usage.input_tokens ?? 0;
    this.outputTokens += usage.output_tokens ?? 0;
  }
}

/** Minimal sink interface so _shared modules don't depend on the class. */
export interface UsageSink {
  add(usage: { input_tokens?: number | null; output_tokens?: number | null } | null | undefined): void;
}

// deno-lint-ignore no-explicit-any
type Db = any;

/**
 * Upsert-read today's usage row for the user (creates it at zero if missing).
 * Exactly one DB round trip.
 */
export async function readTodayUsage(db: Db, userId: string): Promise<UsageRow> {
  const { data, error } = await db.rpc("record_usage", {
    p_user_id: userId,
    p_turns: 0,
    p_input_tokens: 0,
    p_output_tokens: 0,
  });
  if (error) throw new Error(`record_usage read failed: ${error.message}`);
  return data as UsageRow;
}

/** Record one served turn + the request's accumulated token usage. */
export async function recordUsage(
  db: Db,
  userId: string,
  acc: UsageAccumulator,
): Promise<void> {
  if (acc.modelCalls === 0) return; // nothing served — don't count a turn
  const { error } = await db.rpc("record_usage", {
    p_user_id: userId,
    p_turns: 1,
    p_input_tokens: acc.inputTokens,
    p_output_tokens: acc.outputTokens,
  });
  if (error) throw new Error(`record_usage write failed: ${error.message}`);
}

export type BudgetKind = "turns" | "tokens";

export interface BudgetStatus {
  /** Which hard limit is exceeded, if any. */
  exceeded: BudgetKind | null;
  /** ≥80% of either limit — ask the professor for tighter, shorter replies. */
  soft: boolean;
}

export function checkBudget(row: UsageRow): BudgetStatus {
  const exceeded: BudgetKind | null = row.turns >= DAILY_TURN_LIMIT
    ? "turns"
    : row.output_tokens >= DAILY_OUTPUT_TOKEN_LIMIT
    ? "tokens"
    : null;
  const soft = row.turns >= DAILY_TURN_LIMIT * SOFT_THRESHOLD ||
    row.output_tokens >= DAILY_OUTPUT_TOKEN_LIMIT * SOFT_THRESHOLD;
  return { exceeded, soft };
}

/** Shown verbatim in the app — warm and short. */
export const BUDGET_MESSAGES: Record<BudgetKind, string> = {
  turns:
    "You've reached today's discussion limit — your professor will be here tomorrow, same seat.",
  tokens:
    "That's a full day of seminar. Rest your eyes — your professor will pick this up tomorrow.",
};

/** One-line note appended to the engine instruction block at ≥80% budget. */
export const SOFT_BUDGET_NOTE =
  "\n\nNOTE: The student is close to today's usage budget. Keep your replies " +
  "noticeably tighter and shorter this session (never cut a discussion off " +
  "mid-thought, and do not mention the budget).";
