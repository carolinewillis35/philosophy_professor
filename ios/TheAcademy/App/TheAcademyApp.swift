import SwiftUI

@main
struct TheAcademyApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(app)
                .tint(Theme.accent)
                .task { await app.loadIfNeeded() }
        }
    }
}

struct RootTabView: View {
    private enum Tab: Hashable { case catalog, myCourses, reader, worldview }

    @Environment(AppModel.self) private var app
    @State private var catalogPath = NavigationPath()
    @State private var selectedTab: Tab = .catalog

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $catalogPath) { CatalogView() }
                .tabItem { Label("Catalog", systemImage: "building.columns") }
                .tag(Tab.catalog)
                .task { await handleDemoLaunchArguments() }

            NavigationStack { MyCoursesView() }
                .tabItem { Label("My Courses", systemImage: "graduationcap") }
                .tag(Tab.myCourses)

            NavigationStack { ReaderHomeView() }
                .tabItem { Label("Reader", systemImage: "book") }
                .tag(Tab.reader)

            NavigationStack { WorldviewView() }
                .tabItem { Label("Worldview", systemImage: "point.3.connected.trianglepath.dotted") }
                .tag(Tab.worldview)
        }
    }

    /// Dev affordances: `-demo-elenchus` jumps straight into the mock
    /// elenchus, `-demo-seminar` into a mock seminar, `-demo-worldview`
    /// opens the Worldview tab, `-demo-daily` fronts a fresh Daily Question
    /// card and answers it with the mock professor, `-demo-clinic` opens a
    /// mock Argument Clinic, `-demo-drop` opens this week's drop fresh,
    /// `-demo-steelman` opens a mock steelman session against a fixture
    /// commitment, `-demo-changelog` opens the Worldview tab with the
    /// extended fixture, `-demo-news` opens this week's newsRead session
    /// fresh, `-demo-practice` opens the Practice Wing with the morning flow
    /// pre-run, `-demo-reencounter` opens this week's drop with a seeded
    /// prior-cycle response so the badge and the compare view show,
    /// `-demo-symposium` seeds a before-tap and opens the mock symposium
    /// session (post-completion the movement screen reads the fixture
    /// payload), and `-demo-packs` opens the dinner-party packs shelf
    /// (screenshots/UI checks from the command line).
    private func handleDemoLaunchArguments() async {
        #if DEBUG
        if CommandLine.arguments.contains("-demo-worldview")
            || CommandLine.arguments.contains("-demo-profile")
            || CommandLine.arguments.contains("-demo-changelog") {
            selectedTab = .worldview
            return
        }
        if CommandLine.arguments.contains("-demo-daily") {
            selectedTab = .catalog
            await app.loadIfNeeded()
            app.daily.resetForDemo()
            if let question = app.daily.todayQuestion,
               let option = question.options.first {
                await app.daily.submit(question: question, option: option,
                                       sentence: "", client: app.makeSessionClient())
            }
            return
        }
        if CommandLine.arguments.contains("-demo-clinic") {
            selectedTab = .catalog
            await app.loadIfNeeded()
            catalogPath.append(SessionRoute(standalone: .argumentClinic,
                                            personaId: "whitmore"))
            return
        }
        if CommandLine.arguments.contains("-demo-drop") {
            selectedTab = .catalog
            await app.loadIfNeeded()
            app.drops.resetForDemo()
            if let drop = app.drops.thisWeekDrop {
                catalogPath.append(SessionRoute(drop: drop))
            }
            return
        }
        if CommandLine.arguments.contains("-demo-news") {
            selectedTab = .catalog
            await app.loadIfNeeded()
            if let brief = app.newsBrief {
                catalogPath.append(SessionRoute(news: brief))
            }
            return
        }
        if CommandLine.arguments.contains("-demo-practice") {
            selectedTab = .catalog
            await app.loadIfNeeded()
            app.practice.resetForDemo()
            catalogPath.append(PracticeRoute())
            if let prompt = app.practice.todayMorningPrompt {
                await app.practice.submitMorning(
                    prompt: prompt,
                    intention: "Meet the noon meeting calmly, whatever it brings.",
                    client: app.makeSessionClient(practiceMode: .morning,
                                                  practiceExercise: prompt))
            }
            return
        }
        if CommandLine.arguments.contains("-demo-reencounter") {
            selectedTab = .catalog
            await app.loadIfNeeded()
            app.drops.resetForDemo()
            if let drop = app.drops.thisWeekDrop {
                app.drops.seedPriorResponseForDemo(drop: drop)
                catalogPath.append(SessionRoute(drop: drop))
            }
            return
        }
        if CommandLine.arguments.contains("-demo-symposium") {
            selectedTab = .catalog
            await app.loadIfNeeded()
            app.symposia.resetForDemo()
            if let symposium = app.symposia.thisMonthSymposium {
                // The before-tap precedes the session (§16.6): seed the
                // arrival position the sheet would have captured.
                app.symposia.recordBefore(symposium: symposium, stance: .undecided)
                catalogPath.append(SessionRoute(symposium: symposium,
                                                before: .undecided))
            }
            return
        }
        if CommandLine.arguments.contains("-demo-packs") {
            selectedTab = .catalog
            await app.loadIfNeeded()
            catalogPath.append(PacksRoute())
            return
        }
        if CommandLine.arguments.contains("-demo-steelman") {
            selectedTab = .catalog
            await app.loadIfNeeded()
            app.worldview.loadIfNeeded()
            let target = app.worldview.liveCommitments.first.map {
                SteelmanTarget(claim: $0.claim, ontologyId: $0.ontologyId)
            } ?? SteelmanTarget(
                claim: "Everything that exists, including minds, is ultimately physical.",
                ontologyId: "mind.physicalism")
            catalogPath.append(SessionRoute(steelman: target))
            return
        }
        let kind: SessionKind? =
            CommandLine.arguments.contains("-demo-elenchus") ? .elenchus
            : CommandLine.arguments.contains("-demo-seminar") ? .seminar
            : nil
        guard let kind else { return }
        await app.loadIfNeeded()
        if let course = app.course("what-is-justice") ?? app.courses.first {
            catalogPath.append(SessionRoute(course: course, unit: 0, kind: kind))
        }
        #endif
    }
}

// MARK: - Navigation routes

struct SessionRoute: Hashable {
    /// nil for standalone sessions (§13.1): no course, no unit doc.
    let course: Course?
    let unit: Int
    let kind: SessionKind
    /// Standalone sessions carry the student-picked professor directly.
    let personaId: String?
    /// §14.3: the weekly drop this session runs (standalone
    /// thoughtExperiment against the drop's own spec).
    let drop: Drop?
    /// §14.4: the student's own commitment a steelman session takes aim at.
    let steelmanTarget: SteelmanTarget?
    /// §15.2: the week's brief a newsRead session teaches from.
    let newsBrief: NewsBrief?
    /// §15.3: the practice mode + rotated exercise (persona is bede
    /// server-side; the route pins it for the UI).
    let practiceMode: PracticeMode?
    let practiceExercise: PracticeExercise?
    /// §16.2: the month's symposium and the before-tap's position — captured
    /// BEFORE the session and carried only by the start request.
    let symposium: SymposiumSpec?
    let symposiumBefore: SymposiumStance?

    init(course: Course, unit: Int, kind: SessionKind) {
        self.course = course
        self.unit = unit
        self.kind = kind
        self.personaId = nil
        self.drop = nil
        self.steelmanTarget = nil
        self.newsBrief = nil
        self.practiceMode = nil
        self.practiceExercise = nil
        self.symposium = nil
        self.symposiumBefore = nil
    }

    /// §13.1 standalone route (dailyQuestion, argumentClinic — and §15.3
    /// practiceReview, whose persona is bede).
    init(standalone kind: SessionKind, personaId: String) {
        self.course = nil
        self.unit = 0
        self.kind = kind
        self.personaId = personaId
        self.drop = nil
        self.steelmanTarget = nil
        self.newsBrief = nil
        self.practiceMode = nil
        self.practiceExercise = nil
        self.symposium = nil
        self.symposiumBefore = nil
    }

    /// §14.3 weekly-drop route: the drop's persona teaches the case.
    init(drop: Drop) {
        self.course = nil
        self.unit = 0
        self.kind = .thoughtExperiment
        self.personaId = drop.personaId
        self.drop = drop
        self.steelmanTarget = nil
        self.newsBrief = nil
        self.practiceMode = nil
        self.practiceExercise = nil
        self.symposium = nil
        self.symposiumBefore = nil
    }

    /// §14.4 steelman route: default persona whitmore, silently.
    init(steelman target: SteelmanTarget, personaId: String = "whitmore") {
        self.course = nil
        self.unit = 0
        self.kind = .steelman
        self.personaId = personaId
        self.drop = nil
        self.steelmanTarget = target
        self.newsBrief = nil
        self.practiceMode = nil
        self.practiceExercise = nil
        self.symposium = nil
        self.symposiumBefore = nil
    }

    /// §15.2 newsRead route: the week's brief, the server's default
    /// professor unless the student picked one.
    init(news brief: NewsBrief, personaId: String = "whitmore") {
        self.course = nil
        self.unit = 0
        self.kind = .newsRead
        self.personaId = personaId
        self.drop = nil
        self.steelmanTarget = nil
        self.newsBrief = brief
        self.practiceMode = nil
        self.practiceExercise = nil
        self.symposium = nil
        self.symposiumBefore = nil
    }

    /// §15.3 practice route: Bede's wing, always (the server forces the
    /// persona; evening needs no exercise — the examen is fixed).
    init(practice mode: PracticeMode, exercise: PracticeExercise? = nil) {
        self.course = nil
        self.unit = 0
        self.kind = .practice
        self.personaId = "bede"
        self.drop = nil
        self.steelmanTarget = nil
        self.newsBrief = nil
        self.practiceMode = mode
        self.practiceExercise = exercise
        self.symposium = nil
        self.symposiumBefore = nil
    }

    /// §16.2 symposium route: the month's debate, entered ONLY through the
    /// before-tap (§16.6) — `before` was recorded before this route existed.
    /// The route pins personaA for the room's default tint; both voices
    /// render from the spec.
    init(symposium: SymposiumSpec, before: SymposiumStance) {
        self.course = nil
        self.unit = 0
        self.kind = .symposium
        self.personaId = symposium.personaA
        self.drop = nil
        self.steelmanTarget = nil
        self.newsBrief = nil
        self.practiceMode = nil
        self.practiceExercise = nil
        self.symposium = symposium
        self.symposiumBefore = before
    }

    /// The professor in the room, however the route was built.
    var resolvedPersonaId: String? { personaId ?? course?.personaId }
}

/// The Practice Wing surface (§15.5) — pushable from anywhere on the stack.
struct PracticeRoute: Hashable {}

/// The dinner-party packs shelf (§16.5) — pushable from anywhere on the
/// stack; packs themselves push as `Pack` values from the shelf.
struct PacksRoute: Hashable {}

struct ReaderRoute: Hashable {
    let bookID: String
    let ch: Int?
}

struct EssayRoute: Hashable {
    let course: Course
    let unitNumber: Int
    let assignment: Assignment
}

/// Attach once per NavigationStack so any screen can push these.
struct AcademyDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Course.self) { CourseDetailView(course: $0) }
            .navigationDestination(for: SessionRoute.self) { SessionView(route: $0) }
            .navigationDestination(for: ReaderRoute.self) { ReaderView(route: $0) }
            .navigationDestination(for: EssayRoute.self) { EssayEditorView(route: $0) }
            .navigationDestination(for: PracticeRoute.self) { _ in PracticeWingView() }
            .navigationDestination(for: PacksRoute.self) { _ in PacksShelfView() }
    }
}

extension View {
    func academyDestinations() -> some View { modifier(AcademyDestinations()) }
}
