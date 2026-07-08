import SwiftUI

/// Renders the `recordGrade` stateOp payload (CONTRACTS §5): a filled rubric
/// with per-criterion scores and justifications, margin comments anchored to
/// the student's own sentences, revision directives, and Resubmit.
struct FeedbackView: View {
    @Environment(AppModel.self) private var app

    let course: Course
    let assignment: Assignment
    let record: GradeRecord
    let essayBody: String
    let onResubmit: () -> Void

    private var tint: Color { Theme.tint(for: course.personaId) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                gradeBanner
                rubricSection
                marginSection
                directivesSection
                resubmitButton
            }
            .padding()
        }
        .background(Theme.paper)
    }

    // MARK: grade

    private var gradeBanner: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(record.grade)
                .font(.system(size: 44, weight: .semibold, design: .serif))
                .foregroundStyle(tint)
                .frame(width: 84, height: 84)
                .background(Circle().fill(tint.opacity(0.10)))
                .overlay(Circle().strokeBorder(tint.opacity(0.5), lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 4) {
                Text("Graded by \(app.persona(course.personaId)?.name ?? "your professor")")
                    .overline(tint)
                Text(assignment.prompt)
                    .font(.caption)
                    .fontDesign(.serif)
                    .italic()
                    .lineLimit(3)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bulletinCard(tint: tint)
    }

    // MARK: rubric

    private var rubricSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(text: "Rubric")
            ForEach(record.rubric) { score in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(score.name)
                            .font(.subheadline.weight(.semibold))
                            .fontDesign(.serif)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(scoreLabel(score))
                            .font(.subheadline.monospacedDigit().weight(.medium))
                            .foregroundStyle(tint)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.rule)
                            Capsule().fill(tint)
                                .frame(width: geo.size.width * fraction(score))
                        }
                    }
                    .frame(height: 5)
                    Text(score.justification)
                        .font(.footnote)
                        .fontDesign(.serif)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .bulletinCard()
            }
        }
    }

    private func fraction(_ score: RubricScore) -> Double {
        score.max > 0 ? min(1, score.score / score.max) : 0
    }

    private func scoreLabel(_ score: RubricScore) -> String {
        let s = score.score == score.score.rounded() ? String(Int(score.score)) : String(format: "%.1f", score.score)
        let m = score.max == score.max.rounded() ? String(Int(score.max)) : String(format: "%.1f", score.max)
        return "\(s) / \(m)"
    }

    // MARK: margin comments

    @ViewBuilder
    private var marginSection: some View {
        if !record.marginComments.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(text: "Margin Comments")
                ForEach(record.marginComments) { comment in
                    VStack(alignment: .leading, spacing: 8) {
                        // The student's own sentence, as anchored by the professor.
                        Text("\u{201C}\(comment.anchor)\u{201D}")
                            .font(.footnote)
                            .fontDesign(.serif)
                            .italic()
                            .foregroundStyle(Theme.inkSecondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.highlightWash))
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption)
                                .foregroundStyle(tint)
                                .padding(.top, 2)
                            Text(comment.comment)
                                .font(.subheadline)
                                .fontDesign(.serif)
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .bulletinCard(tint: tint)
                }
            }
        }
    }

    // MARK: directives

    @ViewBuilder
    private var directivesSection: some View {
        if !record.directives.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(text: "Revision Directives")
                ForEach(Array(record.directives.enumerated()), id: \.offset) { index, directive in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline)
                            .fontDesign(.serif)
                            .foregroundStyle(tint)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(tint.opacity(0.12)))
                        Text(directive)
                            .font(.subheadline)
                            .fontDesign(.serif)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .bulletinCard()
        }
    }

    private var resubmitButton: some View {
        Button {
            onResubmit()
        } label: {
            Label("Revise & resubmit", systemImage: "arrow.uturn.backward.circle")
                .font(.headline)
                .fontDesign(.serif)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .padding(.top, 4)
    }
}
