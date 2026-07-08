// deno test supabase/functions/_shared/sayStream_test.ts
import { assertEquals } from "jsr:@std/assert@1";
import { SayStream } from "./sayStream.ts";

/** Feed `raw` to a fresh SayStream in chunks of `size`; concatenate output. */
function run(raw: string, size: number): { text: string; finished: boolean } {
  const s = new SayStream();
  let text = "";
  for (let i = 0; i < raw.length; i += size) {
    text += s.push(raw.slice(i, i + size));
  }
  return { text, finished: s.finished };
}

const ENVELOPE =
  '{"say":"Hello, reader.\\nRead \\"slowly\\" \\u2014 backslash: \\\\ done.","citations":[],"stateOps":[],"uiHints":{"showPassagePicker":false,"checkInQuestion":null,"endOfSession":false}}';

const EXPECTED = 'Hello, reader.\nRead "slowly" — backslash: \\ done.';

Deno.test("extracts say across every chunking granularity", () => {
  for (const size of [1, 2, 3, 5, 7, 11, 64, ENVELOPE.length]) {
    const { text, finished } = run(ENVELOPE, size);
    assertEquals(text, EXPECTED, `chunk size ${size}`);
    assertEquals(finished, true, `chunk size ${size} finished`);
  }
});

Deno.test("handles whitespace around key/colon and pretty-printed JSON", () => {
  const raw = '{\n  "say" : "hi there",\n  "citations": []\n}';
  const { text, finished } = run(raw, 4);
  assertEquals(text, "hi there");
  assertEquals(finished, true);
});

Deno.test("stops at the closing unescaped quote (later fields ignored)", () => {
  const s = new SayStream();
  s.push('{"say":"done"');
  assertEquals(s.finished, true);
  assertEquals(s.push(',"citations":[{"quote":"not say"}]}'), "");
});

Deno.test("escape sequence split across deltas", () => {
  const s = new SayStream();
  let out = s.push('{"say":"a\\');
  out += s.push('nb"');
  assertEquals(out, "a\nb");
  assertEquals(s.finished, true);
});

Deno.test("unicode escape split across deltas, incl. surrogate pair", () => {
  const s = new SayStream();
  let out = s.push('{"say":"x\\u26');
  out += s.push("03");
  // Surrogate pair for 😀 (U+1F600) split mid-escape
  out += s.push('\\uD83D\\uDE0');
  out += s.push('0y"');
  assertEquals(out, "x☃\u{1F600}y");
  assertEquals(s.finished, true);
});

Deno.test("empty say value", () => {
  const { text, finished } = run('{"say":"","citations":[]}', 3);
  assertEquals(text, "");
  assertEquals(finished, true);
});

Deno.test("opening sequence split across deltas", () => {
  const s = new SayStream();
  let out = s.push('{"sa');
  out += s.push('y"');
  out += s.push(' : "ok"');
  assertEquals(out, "ok");
  assertEquals(s.finished, true);
});
