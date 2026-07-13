// Seed personas + courses + claim ontology from content/ into the database
// (service role).
//
// Usage (from the repo root):
//   SUPABASE_URL=https://<ref>.supabase.co \
//   SUPABASE_SERVICE_ROLE_KEY=... \
//   deno run --allow-env --allow-read --allow-net supabase/scripts/seed_content.ts
//
// Reads:
//   content/personas/personas.json   — registry [{id, name, title, blurb, ...}]
//   content/personas/<id>.md         — full persona doc per registry entry
//   content/courses/*.json           — course JSON (CONTRACTS §7 + §12.5)
//   content/ontology/claims.json     — claim ontology (CONTRACTS §12.6)
//   content/daily/questions.json     — daily-question bank (CONTRACTS §13.2)
//   content/drops/drops.json         — weekly thought-experiment drops (§14.3)
//   content/practice/exercises.json  — Practice Wing exercises (§15.3)
//   content/news/lenses.json         — news lens pairs (§15.2)
//   content/symposia/symposia.json   — monthly symposia (§16.1)
//   content/packs/packs.json         — dinner-party packs (§16.4)
//
// Book text (editions/chapters/passages) is seeded separately via the
// pipeline's seed.sql — see supabase/README.md.

import { createClient } from "npm:@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL");
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!url || !key) {
  console.error("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY");
  Deno.exit(1);
}
const db = createClient(url, key, { auth: { persistSession: false } });

interface PersonaEntry {
  id: string;
  name: string;
  title?: string;
  blurb?: string;
  version?: number;
}

// --- personas ---------------------------------------------------------------

const registryPath = "content/personas/personas.json";
let personas: PersonaEntry[] = [];
try {
  personas = JSON.parse(await Deno.readTextFile(registryPath));
} catch {
  console.warn(`no ${registryPath} — skipping personas`);
}

for (const p of personas) {
  const doc = await Deno.readTextFile(`content/personas/${p.id}.md`);
  const { error } = await db.from("personas").upsert({
    id: p.id,
    name: p.name,
    title: p.title ?? null,
    blurb: p.blurb ?? null,
    doc,
    version: p.version ?? 1,
  });
  if (error) {
    console.error(`persona ${p.id}: ${error.message}`);
    Deno.exit(1);
  }
  console.log(`persona ${p.id} ✓`);
}

// --- courses ------------------------------------------------------------------

try {
  for await (const entry of Deno.readDir("content/courses")) {
    if (!entry.isFile || !entry.name.endsWith(".json")) continue;
    const doc = JSON.parse(
      await Deno.readTextFile(`content/courses/${entry.name}`),
    );
    const { error } = await db.from("courses").upsert({
      id: doc.id,
      title: doc.title,
      persona_id: doc.personaId,
      description: doc.description ?? null,
      difficulty: doc.difficulty ?? null,
      est_weeks: doc.estWeeks ?? null,
      texts: (doc.texts ?? []).map((t: { bookID: string }) => t.bookID),
      doc,
      is_free: doc.isFree ?? false,
    });
    if (error) {
      console.error(`course ${doc.id}: ${error.message}`);
      Deno.exit(1);
    }
    console.log(`course ${doc.id} ✓`);
  }
} catch {
  console.warn("no content/courses directory — skipping courses");
}

// --- claim ontology (CONTRACTS §12.6 -> claims + claim_edges) ----------------

interface OntologyClaim {
  id: string;
  claim: string;
  domain: string;
  summary?: string;
  entails?: string[];
  conflictsWith?: string[];
  supports?: string[];
}

const ontologyPath = "content/ontology/claims.json";
let ontology: { version?: number; claims: OntologyClaim[] } | null = null;
try {
  ontology = JSON.parse(await Deno.readTextFile(ontologyPath));
} catch {
  console.warn(`no ${ontologyPath} — skipping ontology`);
}

if (ontology) {
  const claims = ontology.claims ?? [];
  const { error: cErr } = await db.from("claims").upsert(
    claims.map((c) => ({
      id: c.id,
      claim: c.claim,
      domain: c.domain,
      summary: c.summary ?? "",
      version: ontology.version ?? 1,
    })),
  );
  if (cErr) {
    console.error(`claims: ${cErr.message}`);
    Deno.exit(1);
  }
  console.log(`claims: ${claims.length} ✓`);

  // Edges: entails/supports are directed; conflictsWith is symmetric — the
  // authored file lists it on both sides (validator enforces), so iterating
  // every claim emits one row per direction; the PK (from_id, to_id, kind)
  // upsert dedupes.
  const edgeRows: { from_id: string; to_id: string; kind: string }[] = [];
  const pushEdges = (from: string, targets: string[] | undefined, kind: string) => {
    for (const to of targets ?? []) edgeRows.push({ from_id: from, to_id: to, kind });
  };
  for (const c of claims) {
    pushEdges(c.id, c.entails, "entails");
    pushEdges(c.id, c.supports, "supports");
    pushEdges(c.id, c.conflictsWith, "conflicts");
  }
  const { error: eErr } = await db
    .from("claim_edges")
    .upsert(edgeRows, { onConflict: "from_id,to_id,kind" });
  if (eErr) {
    console.error(`claim_edges: ${eErr.message}`);
    Deno.exit(1);
  }
  console.log(`claim_edges: ${edgeRows.length} ✓`);
}

// --- daily-question bank (CONTRACTS §13.2 -> daily_questions) ----------------

const dailyPath = "content/daily/questions.json";
let daily: { version?: number; questions: { id: string }[] } | null = null;
try {
  daily = JSON.parse(await Deno.readTextFile(dailyPath));
} catch {
  console.warn(`no ${dailyPath} — skipping daily questions`);
}

if (daily) {
  const questions = daily.questions ?? [];
  const { error: dErr } = await db.from("daily_questions").upsert(
    questions.map((q) => ({
      id: q.id,
      doc: q,
      version: daily.version ?? 1,
    })),
  );
  if (dErr) {
    console.error(`daily_questions: ${dErr.message}`);
    Deno.exit(1);
  }
  console.log(`daily_questions: ${questions.length} ✓`);
}

// --- weekly drops (CONTRACTS §14.3 -> drops) ---------------------------------

const dropsPath = "content/drops/drops.json";
let dropsBank: { version?: number; drops: { id: string }[] } | null = null;
try {
  dropsBank = JSON.parse(await Deno.readTextFile(dropsPath));
} catch {
  console.warn(`no ${dropsPath} — skipping drops`);
}

if (dropsBank) {
  const drops = dropsBank.drops ?? [];
  const { error: dropErr } = await db.from("drops").upsert(
    drops.map((d) => ({
      id: d.id,
      doc: d,
      version: dropsBank.version ?? 1,
    })),
  );
  if (dropErr) {
    console.error(`drops: ${dropErr.message}`);
    Deno.exit(1);
  }
  console.log(`drops: ${drops.length} ✓`);
}

// --- Practice Wing exercises (CONTRACTS §15.3 -> practice_exercises) ---------

const exercisesPath = "content/practice/exercises.json";
// deno-lint-ignore no-explicit-any
let exercises: any = null;
try {
  exercises = JSON.parse(await Deno.readTextFile(exercisesPath));
} catch {
  console.warn(`no ${exercisesPath} — skipping practice exercises`);
}

if (exercises) {
  const version = exercises.version ?? 1;
  const rows = [
    // deno-lint-ignore no-explicit-any
    ...(exercises.morning ?? []).map((m: any) => ({
      id: m.id,
      kind: "morning",
      doc: m,
      version,
    })),
    {
      id: "examen",
      kind: "examen",
      doc: { id: "examen", questions: exercises.examen?.questions ?? [] },
      version,
    },
    // deno-lint-ignore no-explicit-any
    ...(exercises.visualizations ?? []).map((v: any) => ({
      id: v.id,
      kind: "visualization",
      doc: v,
      version,
    })),
  ];
  const { error: exErr } = await db.from("practice_exercises").upsert(rows);
  if (exErr) {
    console.error(`practice_exercises: ${exErr.message}`);
    Deno.exit(1);
  }
  console.log(`practice_exercises: ${rows.length} ✓`);
}

// --- News lens pairs (CONTRACTS §15.2 -> news_lenses) ------------------------

const lensesPath = "content/news/lenses.json";
let lenses: { version?: number; pairs: { id: string }[] } | null = null;
try {
  lenses = JSON.parse(await Deno.readTextFile(lensesPath));
} catch {
  console.warn(`no ${lensesPath} — skipping lenses`);
}

if (lenses) {
  const pairs = lenses.pairs ?? [];
  const { error: lnErr } = await db.from("news_lenses").upsert(
    pairs.map((p) => ({ id: p.id, doc: p, version: lenses.version ?? 1 })),
  );
  if (lnErr) {
    console.error(`news_lenses: ${lnErr.message}`);
    Deno.exit(1);
  }
  console.log(`news_lenses: ${pairs.length} ✓`);
}

// --- monthly symposia + dinner-party packs (CONTRACTS §16) -------------------

async function seedCatalog(
  path: string,
  listKey: string,
  table: string,
): Promise<void> {
  // deno-lint-ignore no-explicit-any
  let bank: any = null;
  try {
    bank = JSON.parse(await Deno.readTextFile(path));
  } catch {
    console.warn(`no ${path} — skipping ${table}`);
    return;
  }
  // deno-lint-ignore no-explicit-any
  const items: any[] = bank[listKey] ?? [];
  const { error } = await db.from(table).upsert(
    items.map((it) => ({ id: it.id, doc: it, version: bank.version ?? 1 })),
  );
  if (error) {
    console.error(`${table}: ${error.message}`);
    Deno.exit(1);
  }
  console.log(`${table}: ${items.length} ✓`);
}

await seedCatalog("content/symposia/symposia.json", "symposia", "symposia");
await seedCatalog("content/packs/packs.json", "packs", "packs");

console.log("done");
