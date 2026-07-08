import SwiftUI

/// The Academy design system — a university bulletin, not a chat app.
/// Warm paper grounds, ink-dark type set in serif, one restrained accent per
/// professor. Everything else stays out of the way.
enum Theme {

    // MARK: palette

    /// Warm paper ground (soft charcoal in dark mode).
    static let paper = dynamic(light: UIColor(red: 0.972, green: 0.958, blue: 0.929, alpha: 1),
                               dark: UIColor(red: 0.110, green: 0.102, blue: 0.090, alpha: 1))

    /// Slightly brighter card stock sitting on the paper ground.
    static let card = dynamic(light: UIColor(red: 0.993, green: 0.986, blue: 0.970, alpha: 1),
                              dark: UIColor(red: 0.157, green: 0.145, blue: 0.128, alpha: 1))

    /// Primary ink.
    static let ink = dynamic(light: UIColor(red: 0.145, green: 0.125, blue: 0.102, alpha: 1),
                             dark: UIColor(red: 0.925, green: 0.906, blue: 0.870, alpha: 1))

    /// Secondary ink for captions, bylines, rubric descriptors.
    static let inkSecondary = dynamic(light: UIColor(red: 0.420, green: 0.388, blue: 0.345, alpha: 1),
                                      dark: UIColor(red: 0.660, green: 0.635, blue: 0.595, alpha: 1))

    /// Hairline rules, like a well-set bulletin page.
    static let rule = dynamic(light: UIColor(red: 0.145, green: 0.125, blue: 0.102, alpha: 0.14),
                              dark: UIColor(red: 0.925, green: 0.906, blue: 0.870, alpha: 0.16))

    /// Department accent — a deep academy green.
    static let accent = dynamic(light: UIColor(red: 0.153, green: 0.322, blue: 0.263, alpha: 1),
                                dark: UIColor(red: 0.416, green: 0.624, blue: 0.514, alpha: 1))

    /// Highlighter wash for reader marginalia.
    static let highlightWash = dynamic(light: UIColor(red: 0.910, green: 0.812, blue: 0.494, alpha: 0.32),
                                       dark: UIColor(red: 0.910, green: 0.812, blue: 0.494, alpha: 0.20))

    // MARK: per-professor tints (DECISIONS #6: monogram/tint placeholder art)

    static func tint(for personaID: String?) -> Color {
        switch personaID {
        case "vlachos": // the gadfly: bottle green
            return dynamic(light: UIColor(red: 0.153, green: 0.322, blue: 0.263, alpha: 1),
                           dark: UIColor(red: 0.435, green: 0.647, blue: 0.545, alpha: 1))
        case "whitmore": // the analytic: slate indigo
            return dynamic(light: UIColor(red: 0.216, green: 0.263, blue: 0.427, alpha: 1),
                           dark: UIColor(red: 0.545, green: 0.596, blue: 0.796, alpha: 1))
        case "lindqvist": // the continental: oxblood
            return dynamic(light: UIColor(red: 0.478, green: 0.176, blue: 0.157, alpha: 1),
                           dark: UIColor(red: 0.796, green: 0.478, blue: 0.443, alpha: 1))
        default:
            return accent
        }
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

// MARK: - Reusable dressing

struct BulletinCard: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.rule, lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if let tint {
                    UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                        .fill(tint)
                        .frame(width: 3)
                }
            }
    }
}

extension View {
    /// Card stock with a hairline border and optional professor-tint spine.
    func bulletinCard(tint: Color? = nil) -> some View {
        modifier(BulletinCard(tint: tint))
    }

    /// Small-caps sans label, the bulletin's wayfinding voice.
    func overline(_ color: Color = Theme.inkSecondary) -> some View {
        self.font(.caption.weight(.semibold))
            .fontDesign(.default)
            .textCase(.uppercase)
            .kerning(1.1)
            .foregroundStyle(color)
    }
}

/// Section heading with a hairline rule, as in a printed bulletin.
struct SectionHeading: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).overline()
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
    }
}

/// Circular monogram placeholder portrait with the professor's tint.
struct MonogramPortrait: View {
    let persona: Persona?
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle().fill(Theme.tint(for: persona?.id).opacity(0.14))
            Circle().strokeBorder(Theme.tint(for: persona?.id).opacity(0.55), lineWidth: 1.5)
            Text(persona?.monogram ?? "?")
                .font(.system(size: size * 0.38, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.tint(for: persona?.id))
        }
        .frame(width: size, height: size)
    }
}
