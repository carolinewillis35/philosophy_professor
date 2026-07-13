import SwiftUI

/// The course bulletin: the catalog as a place (SCOPE §5.1).
struct CatalogView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let error = app.loadError {
                    ContentUnavailableView("Catalog unavailable",
                                           systemImage: "books.vertical",
                                           description: Text(error))
                } else if !app.isLoaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    // The sixty-second ritual opens the day (§13.5): the
                    // Daily Question card sits at the top of the bulletin.
                    DailyQuestionCard()

                    // The weekly drop sits right under it (§14.5): one
                    // authored case per week, crowd after answering.
                    DropCard()

                    // The news, read philosophically (§15.2/§15.5): the
                    // week's live question, right under the drop. No
                    // aggregates on news, ever.
                    NewsCard()

                    // The monthly Symposium (§16.2/§16.5): the event of the
                    // month — two professors, one question, your ruling.
                    SymposiumCard()

                    // "Bring me an argument" — the clinic door (§13.5).
                    ClinicEntryCard()

                    // Bede's wing (§15.3/§15.5): the daily practice rooms.
                    PracticeWingCard()

                    ForEach(app.courses) { course in
                        NavigationLink(value: course) {
                            CourseCard(course: course)
                        }
                        .buttonStyle(.plain)
                    }

                    // Dinner-party packs (§16.4/§16.5): a low-key shelf door
                    // below the cards — the questions leave the app;
                    // nothing about them is tracked (§16.6).
                    PacksEntryCard()

                    facultySection
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.paper)
        .navigationTitle("The Academy")
        .toolbarTitleDisplayMode(.large)
        .academyDestinations()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Department of Philosophy").overline(Theme.accent)
            Text("Course Bulletin — \(bulletinTerm)")
                .font(.subheadline)
                .fontDesign(.serif)
                .italic()
                .foregroundStyle(Theme.inkSecondary)
            Rectangle().fill(Theme.rule).frame(height: 1).padding(.top, 6)
        }
        .padding(.top, 4)
    }

    /// The whole faculty, including professors whose courses are still in
    /// preparation — the catalog is a place, and the people live here.
    private var facultySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(text: "Faculty")
                .padding(.top, 8)
            ForEach(app.personas) { persona in
                ProfessorCard(persona: persona)
            }
        }
    }

    private var bulletinTerm: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return "Open Enrollment \(formatter.string(from: Date()))"
    }
}

// MARK: - Course card

struct CourseCard: View {
    @Environment(AppModel.self) private var app
    let course: Course

    private var persona: Persona? { app.persona(course.personaId) }
    private var tint: Color { Theme.tint(for: course.personaId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(course.difficulty.capitalized).overline(tint)
                        if app.freeCourseIDs.contains(course.id) {
                            Text("Free")
                                .font(.caption2.weight(.bold))
                                .fontDesign(.default)
                                .textCase(.uppercase)
                                .kerning(0.8)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(tint))
                                .foregroundStyle(Theme.card)
                        }
                    }
                    Text(course.title)
                        .font(.title3.weight(.semibold))
                        .fontDesign(.serif)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                MonogramPortrait(persona: persona, size: 44)
            }

            if let persona {
                Text("\(persona.name) · \(persona.title)")
                    .font(.footnote)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
            }

            Text(course.description)
                .font(.subheadline)
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink.opacity(0.9))
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            Rectangle().fill(Theme.rule).frame(height: 1)

            HStack(spacing: 14) {
                Label("\(course.estWeeks) wk", systemImage: "calendar")
                Label("\(course.units.count) units", systemImage: "list.number")
                Label(readingList, systemImage: "book.closed")
                    .lineLimit(1)
            }
            .font(.caption)
            .fontDesign(.default)
            .foregroundStyle(Theme.inkSecondary)
        }
        .bulletinCard(tint: tint)
    }

    private var readingList: String {
        course.texts.map { shortTitle($0.title) }.joined(separator: "; ")
    }

    private func shortTitle(_ title: String) -> String {
        title.components(separatedBy: CharacterSet(charactersIn: ";:")).first ?? title
    }
}
