// Anthropic client construction + model constants (CONTRACTS §6).
//
// CRITICAL API rules for claude-sonnet-5 (MODEL_SEMINAR):
//   * NEVER pass `temperature` / `top_p` / `top_k` — the API returns a 400.
//   * NO assistant prefill (a trailing assistant message returns a 400).
//   * Structured outputs go via
//       output_config: { format: { type: "json_schema", schema: ... } }
//   * Always use client.messages.stream(...) and stream.finalMessage().
//   * On sonnet-5, OMITTING `thinking` runs adaptive thinking. For
//     latency-sensitive turns pass `thinking: { type: "disabled" }` explicitly.
//
// MODEL_LIGHT (claude-haiku-4-5) is used for quiz generation/grading and
// memory summarization. We simply omit `thinking` there (runs without
// thinking on haiku).

import Anthropic from "npm:@anthropic-ai/sdk";

export const MODEL_SEMINAR: string =
  Deno.env.get("MODEL_SEMINAR") ?? "claude-sonnet-5";

export const MODEL_LIGHT: string =
  Deno.env.get("MODEL_LIGHT") ?? "claude-haiku-4-5";

/** max_tokens for a typical professor turn (CONTRACTS §6). */
export const MAX_TOKENS_TURN = 2048;

/** max_tokens for memory / turn summarization with MODEL_LIGHT. */
export const MAX_TOKENS_SUMMARY = 1024;

let cached: Anthropic | null = null;

/** Lazily-constructed singleton Anthropic client (key from Supabase secret). */
export function anthropicClient(): Anthropic {
  if (!cached) {
    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      throw new Error("ANTHROPIC_API_KEY is not set (supabase secrets set ANTHROPIC_API_KEY=...)");
    }
    cached = new Anthropic({ apiKey });
  }
  return cached;
}

export type { Anthropic };
