# The Academy — iOS app

SwiftUI client for the AI philosophy department. iOS 17+, no third-party
dependencies. Implements the iOS contracts in `docs/CONTRACTS.md` §9 (plus §4
SSE, §5 envelope, §7 course JSON, §8 chapter JSON).

## Generate, open, build

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`):

```sh
cd ios
xcodegen generate
open TheAcademy.xcodeproj
```

Command-line build (this machine's `xcode-select` points at
CommandLineTools, so prefix with `DEVELOPER_DIR`):

```sh
DEVELOPER_DIR=/Applications/Xcode.app xcodebuild \
  -project TheAcademy.xcodeproj -scheme TheAcademy \
  -destination 'generic/platform=iOS Simulator' build
```

Re-run `xcodegen generate` whenever files are added or removed under
`TheAcademy/`.

## Mock mode (default)

With no `Secrets.plist` in the bundle the app runs fully offline:

- **Catalog / Reader content** comes from `TheAcademy/Fixtures/` — the two
  Academy course JSONs (§7 + §12.5 specs), the three-professor persona
  registry, and the full `republic-jowett` pipeline output (§8, ten books of
  the Jowett *Republic*).
- **Sessions** are played by `MockSessionClient`, a scripted Prof. Vlachos
  (plus lab/experiment scripts driven by the authored §12.5 specs). It speaks
  the same `AsyncStream<SessionEvent>` protocol as the live client: streamed
  `say` deltas, then a full §5 envelope. Its citation quotes are verbatim
  substrings of the bundled Republic passages, mirroring the server-side RAG
  guarantee.
- The Worldview page ships a fixture Commitment Map (`Fixtures/worldview.json`)
  with one open tension, and the Settings page shows a "Demo mode" indicator
  whenever mock mode is active.

Suggested demo flow: Catalog → *What Is Justice?* → Enroll → My Courses →
**Elenchus** (phase strip walks thesis → definition → counterexample →
revision; the aporia card lands before reflection) → Unit 2 **Experiment**
(Ring of Gyges node cards, tappable choices, a "dial turns" pump card) →
*How Arguments Work* → **Argument Lab** (deterministic argument map pinned on
top; hunt the dashed unstated premise) → Worldview tab (positions by domain,
one open tension, timeline, radar, markdown export). Lecture, Seminar,
Assignment, and the Reader all still work as before, now on the Republic.

## Voice Mode (DECISIONS #11)

Entirely on-device — no new dependencies, no keys, works offline and in mock
mode:

- **Speak to the professor**: the mic button in the session input bar starts
  live transcription (`SFSpeechRecognizer` + `AVAudioEngine`); the transcript
  fills the text field as you talk. Tap the mic again to stop, then edit and
  send yourself — nothing auto-fires.
- **Professor speaks back**: the speaker toggle in the session toolbar turns
  on "Voice replies" (persisted with your other prefs). Streamed `say` deltas
  are buffered and spoken sentence-by-sentence via `AVSpeechSynthesizer`, so
  the professor starts talking before the turn finishes. Only the `say` prose
  is voiced — citations, quote panels, and JSON are never spoken. Envelope
  reconciliation never re-speaks already-spoken text.
- **Per-persona voices** live in `SystemProfessorVoice.profile(for:)` —
  Vlachos is unhurried and deeper; Whitmore British, measured, precise;
  Lindqvist warmer and a touch brighter. Preferred enhanced/premium voice identifiers
  fall back to compact voices, then to the default `en-US` voice, depending
  on what's installed. Everything sits behind the `ProfessorVoice` protocol
  so premium TTS can slot in later.
- Recording and speaking never overlap: opening the mic silences the
  professor, and speech won't start while the mic is live.
- **Permissions**: first mic use prompts for microphone + speech recognition
  (usage strings are set in `project.yml`). If either is denied, the session
  shows a hint and typing keeps working.
- **Simulator note**: professor TTS works fine in the simulator; microphone
  capture and recognition quality are best on a real device.

## Pointing at a real Supabase backend

1. Copy `TheAcademy/Fixtures/Secrets.example.plist` to
   `TheAcademy/Secrets.plist` (sibling of `TheAcademy/App/`, i.e. anywhere
   under `TheAcademy/` outside `Fixtures/`).
2. Fill in `SUPABASE_URL` (`https://<ref>.supabase.co`) and
   `SUPABASE_ANON_KEY`.
3. `xcodegen generate` again so the file is picked up as a bundle resource,
   then rebuild.

When both values are present, `LiveSessionClient` POSTs the §4 body to
`{SUPABASE_URL}/functions/v1/session` with `Authorization: Bearer <user
access token>` (from Sign in with Apple, below) and `apikey: <anon key>`
headers and parses the SSE `event:`/`data:` frames hand-rolled over
`URLSession.bytes(for:)`. `Secrets.plist` is gitignored — never commit it.

Note: catalog/reader content still loads from bundled fixtures in this build;
`ContentStore` is a protocol, and a Supabase-backed implementation slots in
behind the same async API when the backend tables are live.

## Auth: Sign in with Apple (CONTRACTS §4.1)

Hand-rolled Supabase Auth REST — no SDK. `AuthClient` runs the Apple flow
with a SHA256-hashed nonce, exchanges the identity token at
`POST /auth/v1/token?grant_type=id_token` (provider `apple`, raw nonce),
keeps `access_token`/`refresh_token`/expiry in the Keychain, auto-refreshes
within ~60s of expiry, and signs out via `POST /auth/v1/logout`.

What's gated: **only live enrollment and session/essay calls**. The catalog
and reader stay browsable signed-out (the free-taste funnel and App Review
both want this). Mock mode never shows sign-in at all.

Setup for live SIWA:

1. **Apple Developer portal**: enable the *Sign in with Apple* capability on
   the App ID `com.theacademy.app`.
2. **Xcode**: set your development team in Signing & Capabilities (the
   entitlement file `TheAcademy/TheAcademy.entitlements` is generated by
   XcodeGen). Simulator/CI builds stay unsigned via `CODE_SIGNING_ALLOWED=NO`;
   a real device needs the team.
3. **Supabase dashboard** → Authentication → Providers → Apple: enable it and
   add `com.theacademy.app` to **Authorized Client IDs** (for the native
   `id_token` flow no client secret is required).
4. Account deletion (App Store requirement) calls
   `POST /functions/v1/delete-account` (§4.2) with the user JWT, then clears
   the Keychain and all local stores. In demo mode the same Settings row is
   labeled "Erase local data" and only wipes the device.

Daily usage budgets (§4.3): a `budget_exceeded` SSE error or an HTTP 429 is
rendered as a gentle in-session notice ("Class is out for today"), never an
alert or a lockout.

The app ships a privacy manifest (`TheAcademy/PrivacyInfo.xcprivacy`): no
tracking; collected data = user ID + user content (both app-functionality,
linked, no tracking); required-reason APIs declared for UserDefaults
(CA92.1) and app-container file timestamps (C617.1).

## Layout

```
project.yml                  XcodeGen spec (app target TheAcademy, iOS 17.0)
TheAcademy/
  App/        TheAcademyApp (TabView), Theme (bulletin design system)
  Models/     CONTRACTS §5 envelope, §7 course, §8 chapter, personas, view models
  Services/   Config, ContentStore, SessionClient (SSE), MockSessionClient,
              HighlightStore, UserStore, AppModel
  Catalog/    CatalogView, CourseDetailView, ProfessorCard
  Session/    SessionView, SessionViewModel, QuotePanel, ElenchusViews,
              ThoughtExperimentViews, ArgumentMapView (deterministic renderer)
  Reader/     ReaderView (+ bookshelf, highlight composer), MarginaliaView
  Essays/     EssayEditorView (autosave, submit), FeedbackView (rubric render)
  Progress/   MyCoursesView, WorldviewView (Commitment Map), SettingsView
  Fixtures/   placeholder content (folder reference; subpaths preserved)
```

## Implementation notes / deliberate choices

- **Free badge**: course JSON (§7) carries no `is_free` field (that lives in
  the `courses` table), so the client mirrors DECISIONS #7 with a local
  constant (`AppModel.freeCourseIDs`) until live mode supplies it.
- **Highlights** store `(bookID, ch, charStart, charEnd, note)` char offsets
  into the chapter's canonical `text` string (§8). Long-press granularity is
  the paragraph; offsets are computed from the paragraph's position in the
  text, so they remain exact for server sync.
- **Quote styling** is confined to `QuotePanel` (citations) and the student's
  own anchored sentences in essay feedback — professor prose is never
  block-quoted, per §9.
- **Enrollments / reading progress / profile prefs** persist to JSON in
  Documents (`UserStore`, `HighlightStore`), shaped to match the §3 tables
  for a straightforward swap to Supabase.
