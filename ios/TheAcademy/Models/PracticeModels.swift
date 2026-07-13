import Foundation

// MARK: - The Practice Wing (CONTRACTS §15.3)

/// The three practice modes — mirrors `PracticeMode` in kinds_life.ts.
/// Training, never therapy: the register everywhere is the gymnasium.
enum PracticeMode: String, Codable, Hashable, CaseIterable {
    case morning, evening, visualization

    var displayName: String {
        switch self {
        case .morning: return "Morning Intention"
        case .evening: return "Evening Examen"
        case .visualization: return "The Rehearsal"
        }
    }

    var symbolName: String {
        switch self {
        case .morning: return "sunrise"
        case .evening: return "moon.stars"
        case .visualization: return "eye"
        }
    }
}

/// One authored exercise (`content/practice/exercises.json`, bundled as
/// `Fixtures/practice-exercises.json`) — mirrors `PracticeExerciseDoc` in
/// kinds_life.ts: morning entries carry `prompt`; visualizations carry
/// `title` / `exercise` / `debrief`.
struct PracticeExercise: Decodable, Identifiable, Hashable {
    let id: String
    let prompt: String?
    let title: String?
    let exercise: String?
    let debrief: String?

    init(id: String, prompt: String? = nil, title: String? = nil,
         exercise: String? = nil, debrief: String? = nil) {
        self.id = id
        self.prompt = prompt
        self.title = title
        self.exercise = exercise
        self.debrief = debrief
    }
}

/// The bank asset wrapper: `{ version, morning, examen, visualizations }`.
struct PracticeBank: Decodable {
    struct Examen: Decodable {
        let questions: [String]
    }

    let version: Int
    let morning: [PracticeExercise]
    let examen: Examen
    let visualizations: [PracticeExercise]
}

/// The 3 fixed examen questions — mirror of EXAMEN_QUESTIONS in
/// kinds_life.ts; the bank's `examen.questions` is the authored source, this
/// is the offline fallback.
enum Examen {
    static let questions = [
        "What disturbed you today?",
        "Was it in your control?",
        "What would you do differently?",
    ]
}

/// The practiceReview state machine (§15.3): review → reflection; a session
/// may complete from `reflection` only. Client mirror of PracticeReviewState
/// in kinds_life.ts.
enum PracticeReviewPhase: String, Decodable, Hashable, CaseIterable {
    case review, reflection

    var displayName: String {
        switch self {
        case .review: return "Review"
        case .reflection: return "Reflection"
        }
    }
}

// MARK: - Deterministic rotation (§15.3: A16 arithmetic, same as the daily
// question and the weekly drop)

extension PracticeExercise {
    /// Today's morning prompt: bank sorted by id, indexed by
    /// `daysSinceEpoch % bank.count` — the DailyQuestion arithmetic exactly.
    static func todayMorning(in bank: [PracticeExercise], date: Date = Date(),
                             calendar: Calendar = .current) -> PracticeExercise? {
        guard !bank.isEmpty else { return nil }
        let sorted = bank.sorted { $0.id < $1.id }
        return sorted[DailyQuestion.daysSinceEpoch(for: date, calendar: calendar) % sorted.count]
    }

    /// This week's visualization: `weeksSinceEpoch % bank.count`, the Drop
    /// arithmetic exactly.
    static func thisWeekVisualization(in bank: [PracticeExercise],
                                      date: Date = Date(),
                                      calendar: Calendar = .current) -> PracticeExercise? {
        guard !bank.isEmpty else { return nil }
        let sorted = bank.sorted { $0.id < $1.id }
        return sorted[Drop.weeksSinceEpoch(for: date, calendar: calendar) % sorted.count]
    }
}

// MARK: - Journal entries (local mirror of `practice_entries`, §15.3)

/// One line of the practice journal: the student's words for one mode on one
/// local date. Local store in mock mode; in live mode the server writes the
/// `practice_entries` row on completion and this remains the optimistic
/// cache — the daily/drop store pattern.
struct PracticeEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let localDate: String
    let mode: PracticeMode
    let exerciseId: String?
    /// The student's words: intention / examen answers / reflection.
    let entry: String
    /// Bede's single morning reply (empty elsewhere, like the table default).
    let reply: String

    init(localDate: String, mode: PracticeMode, exerciseId: String?,
         entry: String, reply: String = "") {
        self.id = UUID()
        self.localDate = localDate
        self.mode = mode
        self.exerciseId = exerciseId
        self.entry = entry
        self.reply = reply
    }
}
