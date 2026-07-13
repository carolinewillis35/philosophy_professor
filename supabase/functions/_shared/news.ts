// news.ts — the weekly news brief (CONTRACTS §15.2 / DECISIONS A25).
//
// One MODEL_LIGHT + web_search call per week, cached in news_briefs. The
// seminar model never searches; it teaches from the cached brief. The brief
// embeds its authored lens pair so the session is self-contained.

import { anthropicClient, MODEL_LIGHT } from "./anthropic.ts";
import type { UsageSink } from "./budget.ts";
import type { LensPair, NewsBrief } from "./kinds_life.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

export async function loadLensPairs(db: Db): Promise<LensPair[]> {
  const { data, error } = await db.from("news_lenses").select("doc");
  if (error) throw new Error(`lens load failed: ${error.message}`);
  return ((data ?? []) as { doc: LensPair }[]).map((r) => r.doc);
}

/** Cached brief for the week, or null. */
export async function loadNewsBrief(db: Db, week: number): Promise<NewsBrief | null> {
  const { data, error } = await db
    .from("news_briefs").select("doc").eq("week", week).maybeSingle();
  if (error) throw new Error(`news brief load failed: ${error.message}`);
  return data ? (data.doc as NewsBrief) : null;
}

const BRIEF_PROMPT = (pairs: LensPair[]) =>
  `You prepare the weekly brief for a philosophy seminar that reads one live
public story philosophically. Use web search to find ONE story from the past
week that carries a genuine philosophical question — an AI-rights or
machine-consciousness development, a free-speech case, a medical-ethics
dilemma, a justice/liberty policy fight, an authenticity-in-art dispute.
Prefer a story with real stakes and two defensible sides; avoid partisan
horse-race coverage and celebrity noise.

Then output ONLY a JSON object (no prose, no markdown fence):
{
  "headline": "neutral, ≤12 words",
  "summary": "≤200 words, strictly neutral register: the verifiable facts and what is disputed; no adjectives of approval or alarm; no crowd numbers or poll results",
  "question": "the single live philosophical question inside the story, one sentence",
  "domain": "ethics|epistemology|metaphysics|mind|political|aesthetics",
  "sourceUrls": ["2-4 URLs of the coverage you actually used"],
  "lensPairId": "the id of the ONE authored lens pair below that best fits the question"
}

Authored lens pairs (pick lensPairId from EXACTLY this list):
${
    pairs.map((p) =>
      `- ${p.id} (${p.domain}): ${p.a.name} vs ${p.b.name} — ${p.splitHint}`
    ).join("\n")
  }`;

/** Generate + cache the week's brief. Throws when generation fails —
 * newsRead start fails gracefully upstream (§15.2). */
export async function generateNewsBrief(
  db: Db,
  week: number,
  usage: UsageSink,
): Promise<NewsBrief> {
  const pairs = await loadLensPairs(db);
  if (pairs.length === 0) throw new Error("no lens pairs seeded");

  const client = anthropicClient();
  // deno-lint-ignore no-explicit-any
  const resp: any = await client.messages.create({
    model: MODEL_LIGHT,
    max_tokens: 1024,
    tools: [{ type: "web_search_20250305", name: "web_search", max_uses: 4 }],
    messages: [{ role: "user", content: BRIEF_PROMPT(pairs) }],
    // deno-lint-ignore no-explicit-any
  } as any);
  usage.add(resp.usage);

  const text = (resp.content as { type: string; text?: string }[])
    .filter((b) => b.type === "text")
    .map((b) => b.text ?? "")
    .join("");
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end <= start) throw new Error("brief generation returned no JSON");
  const raw = JSON.parse(text.slice(start, end + 1)) as Omit<NewsBrief, "lensPair">;

  if (!raw.headline?.trim() || !raw.summary?.trim() || !raw.question?.trim()) {
    throw new Error("brief generation returned an incomplete brief");
  }
  const pair = pairs.find((p) => p.id === raw.lensPairId) ??
    pairs.find((p) => p.domain === raw.domain) ??
    pairs[0];

  const brief: NewsBrief = {
    headline: raw.headline.trim(),
    summary: raw.summary.trim(),
    question: raw.question.trim(),
    domain: pair.domain,
    sourceUrls: Array.isArray(raw.sourceUrls) ? raw.sourceUrls.slice(0, 4) : [],
    lensPairId: pair.id,
    lensPair: pair,
  };

  // Cache; a concurrent first-start losing the PK race just reuses the winner.
  const { error } = await db.from("news_briefs").insert({ week, doc: brief });
  if (error && error.code !== "23505") {
    console.error("news brief cache failed:", error.message);
  } else if (error?.code === "23505") {
    const winner = await loadNewsBrief(db, week);
    if (winner) return winner;
  }
  return brief;
}
