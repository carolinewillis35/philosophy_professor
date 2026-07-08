// Hybrid retrieval: Voyage AI query embedding + search_passages RPC.
//
// Embeddings: Voyage AI voyage-3.5, 1024 dims, input_type "query"
// (CONTRACTS §8 / DECISIONS #4). If VOYAGE_API_KEY is unset (or the request
// fails) we pass a null embedding and the RPC degrades to BM25-only.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

export interface Passage {
  id: string;
  bookId: string;
  ch: number;
  para: number;
  text: string;
  charStart: number;
  charEnd: number;
  score: number;
}

/** Service-role client for server-side DB access (bypasses RLS — the session
 *  function performs its own ownership authorization). */
export function serviceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set");
  }
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Client bound to the caller's JWT — used only for auth.getUser(). */
export function callerClient(authorizationHeader: string): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anon) throw new Error("SUPABASE_URL / SUPABASE_ANON_KEY not set");
  return createClient(url, anon, {
    global: { headers: { Authorization: authorizationHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/**
 * Embed a query with Voyage AI (voyage-3.5, input_type "query").
 * Returns null when no key is configured or the request fails — callers pass
 * the null through to search_passages for the BM25-only fallback.
 */
export async function embedQuery(text: string): Promise<number[] | null> {
  const key = Deno.env.get("VOYAGE_API_KEY");
  if (!key) return null;
  try {
    const res = await fetch("https://api.voyageai.com/v1/embeddings", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "voyage-3.5",
        input: [text],
        input_type: "query",
      }),
    });
    if (!res.ok) {
      console.error(`voyage embeddings failed: ${res.status} ${await res.text()}`);
      return null;
    }
    const json = await res.json();
    const embedding = json?.data?.[0]?.embedding;
    return Array.isArray(embedding) ? embedding : null;
  } catch (e) {
    console.error("voyage embeddings error:", e);
    return null;
  }
}

export interface RetrievalOptions {
  query: string;
  bookIds: string[];
  /** Current unit span bias (inclusive) — rows in span get score × 1.25. */
  focusChStart?: number | null;
  focusChEnd?: number | null;
  matchCount?: number;
}

interface SearchPassagesRow {
  id: string;
  book_id: string;
  ch: number;
  para: number;
  text: string;
  char_start: number;
  char_end: number;
  score: number;
}

/** Call the search_passages RPC (hybrid RRF; BM25-only when embedding null). */
export async function retrievePassages(
  supabase: SupabaseClient,
  opts: RetrievalOptions,
): Promise<Passage[]> {
  if (opts.bookIds.length === 0 || !opts.query.trim()) return [];

  const embedding = await embedQuery(opts.query);

  const { data, error } = await supabase.rpc("search_passages", {
    query_text: opts.query,
    query_embedding: embedding, // null => BM25-only
    book_ids: opts.bookIds,
    focus_ch_start: opts.focusChStart ?? null,
    focus_ch_end: opts.focusChEnd ?? null,
    match_count: opts.matchCount ?? 8,
  });
  if (error) throw new Error(`search_passages failed: ${error.message}`);

  return ((data ?? []) as SearchPassagesRow[]).map((r) => ({
    id: r.id,
    bookId: r.book_id,
    ch: r.ch,
    para: r.para,
    text: r.text,
    charStart: r.char_start,
    charEnd: r.char_end,
    score: r.score,
  }));
}
