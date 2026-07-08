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
    /// opens the Worldview tab (screenshots/UI checks from the command line).
    private func handleDemoLaunchArguments() async {
        #if DEBUG
        if CommandLine.arguments.contains("-demo-worldview")
            || CommandLine.arguments.contains("-demo-profile") {
            selectedTab = .worldview
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
    let course: Course
    let unit: Int
    let kind: SessionKind
}

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
    }
}

extension View {
    func academyDestinations() -> some View { modifier(AcademyDestinations()) }
}
