// Incremental "say" scanner (DECISIONS #9).
//
// The model emits the full JSON envelope via structured outputs; "say" is the
// FIRST property of the schema, so its string value is the first thing that
// appears in the raw text stream. SayStream is fed raw JSON text deltas and
// yields newly-decoded characters of the say value as they arrive, handling
// escape sequences (\n \t \r \b \f \" \\ \/ \uXXXX — incl. escapes split
// across deltas) and stopping at the closing unescaped quote.
//
// Tests: sayStream_test.ts (deno test).

const SIMPLE_ESCAPES: Record<string, string> = {
  '"': '"',
  "\\": "\\",
  "/": "/",
  b: "\b",
  f: "\f",
  n: "\n",
  r: "\r",
  t: "\t",
};

// Matches the opening of the say value: `"say"` key, colon, opening quote.
const OPENING = /"say"\s*:\s*"/;

type State = "seeking" | "inValue" | "escape" | "unicode" | "done";

export class SayStream {
  private state: State = "seeking";
  /** Buffer used while seeking the opening `"say": "` sequence. */
  private seekBuf = "";
  /** Buffer of hex digits collected for a \uXXXX escape. */
  private hexBuf = "";

  /** True once the closing unescaped quote of the say value has been seen. */
  get finished(): boolean {
    return this.state === "done";
  }

  /**
   * Feed a raw JSON text delta; returns the newly-available decoded
   * characters of the say value (possibly the empty string).
   */
  push(delta: string): string {
    if (this.state === "done" || delta.length === 0) return "";

    if (this.state === "seeking") {
      this.seekBuf += delta;
      const m = OPENING.exec(this.seekBuf);
      if (!m) return "";
      // Everything after the opening quote belongs to the value.
      const rest = this.seekBuf.slice(m.index + m[0].length);
      this.seekBuf = "";
      this.state = "inValue";
      // Re-enter with the remainder.
      return this.consume(rest);
    }

    // inValue / escape / unicode states: consume the delta directly.
    return this.consume(delta);
  }

  private consume(text: string): string {
    let out = "";
    for (let i = 0; i < text.length; i++) {
      const c = text[i];
      switch (this.state) {
        case "inValue": {
          if (c === "\\") {
            this.state = "escape";
          } else if (c === '"') {
            this.state = "done";
            return out;
          } else {
            out += c;
          }
          break;
        }
        case "escape": {
          if (c === "u") {
            this.state = "unicode";
            this.hexBuf = "";
          } else {
            const mapped = SIMPLE_ESCAPES[c];
            // Unknown escapes can't occur in valid JSON; pass through literally.
            out += mapped ?? c;
            this.state = "inValue";
          }
          break;
        }
        case "unicode": {
          this.hexBuf += c;
          if (this.hexBuf.length === 4) {
            const code = parseInt(this.hexBuf, 16);
            // Surrogate halves are emitted as-is; a following \uXXXX low
            // surrogate concatenates into the correct code point.
            out += Number.isNaN(code) ? "" : String.fromCharCode(code);
            this.hexBuf = "";
            this.state = "inValue";
          }
          break;
        }
        default:
          return out; // done / seeking cannot occur here
      }
    }
    return out;
  }
}
