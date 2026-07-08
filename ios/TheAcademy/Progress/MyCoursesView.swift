import SwiftUI

/// Enrollments with unit progress and continue buttons into lecture,
/// seminar, reading, and the current unit's assignment.
struct MyCoursesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if app.userStore.enrollments.isEmpty {
                    ContentUnavailableView {
                        Label("Not yet enrolled", systemImage: "graduationcap")
                    } description: {
                        Text("Browse the catalog and enroll in a course. What Is Justice? is free.")
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(app.userStore.enrollments) { enrollment in
                        if let course = app.course(enrollment.courseId) {
                            EnrollmentCard(course: course, enrollment: enrollment)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Theme.paper)
        .navigationTitle("My Courses")
        .academyDestinations()
    }
}

private struct EnrollmentCard: View {
    @Environment(AppModel.self) private var app
    let course: Course
    let enrollment: Enrollment

    private var tint: Color { Theme.tint(for: course.personaId) }
    private var unit: Unit? {
        course.units.first { $0.number == enrollment.currentUnit + 1 }
    }
    private var isFinished: Bool { enrollment.currentUnit >= course.units.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.persona(course.personaId)?.name ?? "").overline(tint)
                    Text(course.title)
                        .font(.title3.weight(.semibold))
                        .fontDesign(.serif)
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
                MonogramPortrait(persona: app.persona(course.personaId), size: 40)
            }

            // Unit progress
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if isFinished {
                        Text("Course complete").overline(tint)
                    } else if let unit {
                        Text("Unit \(unit.number) of \(course.units.count): \(unit.title)")
                            .font(.footnote.weight(.medium))
                            .fontDesign(.serif)
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Text(enrollment.pace.displayName)
                        .font(.caption2)
                        .fontDesign(.default)
                        .foregroundStyle(Theme.inkSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.rule)
                        Capsule().fill(tint)
                            .frame(width: geo.size.width * progressFraction)
                    }
                }
                .frame(height: 4)
            }

            if let unit, !isFinished {
                continueButtons(unit: unit)
            }

            if !isFinished {
                Button {
                    app.userStore.setCurrentUnit(enrollment.currentUnit + 1, for: course.id)
                } label: {
                    Label("Mark unit complete", systemImage: "checkmark.circle")
                        .font(.caption.weight(.medium))
                        .fontDesign(.default)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .bulletinCard(tint: tint)
    }

    private var progressFraction: Double {
        guard !course.units.isEmpty else { return 0 }
        return min(1, Double(enrollment.currentUnit) / Double(course.units.count))
    }

    private func continueButtons(unit: Unit) -> some View {
        let unitIndex = unit.number - 1
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                NavigationLink(value: SessionRoute(course: course, unit: unitIndex, kind: .lecture)) {
                    Label("Lecture", systemImage: SessionKind.lecture.symbolName)
                }
                NavigationLink(value: SessionRoute(course: course, unit: unitIndex, kind: .seminar)) {
                    Label("Seminar", systemImage: SessionKind.seminar.symbolName)
                }
                NavigationLink(value: SessionRoute(course: course, unit: unitIndex, kind: .officeHours)) {
                    Label("Office Hrs", systemImage: SessionKind.officeHours.symbolName)
                }
            }
            // Academy kinds (§12.1), present when the unit authored them.
            if unit.elenchusSpecs?.isEmpty == false
                || unit.thoughtExperiments?.isEmpty == false
                || unit.argumentLabs?.isEmpty == false {
                HStack(spacing: 8) {
                    if unit.elenchusSpecs?.isEmpty == false {
                        NavigationLink(value: SessionRoute(course: course, unit: unitIndex, kind: .elenchus)) {
                            Label("Elenchus", systemImage: SessionKind.elenchus.symbolName)
                        }
                    }
                    if unit.thoughtExperiments?.isEmpty == false {
                        NavigationLink(value: SessionRoute(course: course, unit: unitIndex, kind: .thoughtExperiment)) {
                            Label("Experiment", systemImage: SessionKind.thoughtExperiment.symbolName)
                        }
                    }
                    if unit.argumentLabs?.isEmpty == false {
                        NavigationLink(value: SessionRoute(course: course, unit: unitIndex, kind: .argumentLab)) {
                            Label("Argument Lab", systemImage: SessionKind.argumentLab.symbolName)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                if let span = unit.reading.first {
                    NavigationLink(value: ReaderRoute(bookID: span.bookID, ch: span.chStart)) {
                        Label("Reading", systemImage: "book")
                    }
                }
                if let assignment = unit.assignments.first {
                    NavigationLink(value: EssayRoute(course: course, unitNumber: unit.number, assignment: assignment)) {
                        Label("Assignment", systemImage: SessionKind.essay.symbolName)
                    }
                }
            }
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(tint)
    }
}
