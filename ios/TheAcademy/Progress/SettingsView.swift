import SwiftUI

/// Pace picker, intensity dial (SCOPE §7 tone calibration), the mock-mode
/// indicator, and account controls (sign in/out, §4.2 account deletion).
/// Reached from the Worldview page — the identity surface itself is
/// WorldviewView (DECISIONS A14).
struct SettingsView: View {
    @Environment(AppModel.self) private var app

    @State private var showSignIn = false
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var accountError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                studentCard
                paceSection
                intensitySection
                connectionSection
                accountSection
                aboutSection
            }
            .padding()
        }
        .background(Theme.paper)
        .navigationTitle("Settings")
        .sheet(isPresented: $showSignIn) {
            SignInView()
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            app.config.isMockMode
                ? "Erase all local data? This removes your enrollments, essay drafts, highlights, and reading progress from this device."
                : "Delete your account? This permanently erases your enrollments, essays, highlights, and reading progress — on this device and on the server.",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(app.config.isMockMode ? "Erase local data" : "Delete account",
                   role: .destructive) {
                Task { await performDelete() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: account (§4.1 sign in/out, §4.2 deletion)

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(text: "Account")

            if app.config.isMockMode {
                Text("Demo mode stores everything on this device only.")
                    .font(.caption)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
            } else if app.auth.signedIn {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Signed in with Apple")
                            .font(.subheadline.weight(.semibold))
                            .fontDesign(.serif)
                            .foregroundStyle(Theme.ink)
                        Text(app.auth.userId ?? "")
                            .font(.caption2.monospaced())
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Button {
                    Task { await app.auth.signOut() }
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            } else {
                Text("Sign in to enroll, hold seminars, and submit essays. Browsing stays open without an account.")
                    .font(.caption)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
                Button {
                    showSignIn = true
                } label: {
                    Label("Sign in with Apple", systemImage: "apple.logo")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
            }

            Rectangle().fill(Theme.rule).frame(height: 1)

            // §4.2 — destructive, always available. In demo mode it only
            // clears this device.
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                if isDeleting {
                    ProgressView()
                } else {
                    Label(app.config.isMockMode ? "Erase local data" : "Delete account",
                          systemImage: "trash")
                        .font(.subheadline.weight(.medium))
                }
            }
            .disabled(isDeleting || (!app.config.isMockMode && !app.auth.signedIn))

            if let accountError {
                Label(accountError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .bulletinCard()
    }

    private func performDelete() async {
        isDeleting = true
        accountError = nil
        do {
            try await app.deleteAccount()
        } catch {
            accountError = error.localizedDescription
        }
        isDeleting = false
    }

    private var studentCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.12))
                Circle().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1.5)
                Image(systemName: "person.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text("Student").overline(Theme.accent)
                Text("\(app.userStore.enrollments.count) enrollment\(app.userStore.enrollments.count == 1 ? "" : "s") · \(app.highlightStore.highlights.count) highlight\(app.highlightStore.highlights.count == 1 ? "" : "s")")
                    .font(.footnote)
                    .fontDesign(.serif)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bulletinCard()
    }

    private var paceSection: some View {
        @Bindable var userStore = app.userStore
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "Reading Pace")
            Picker("Pace", selection: $userStore.pace) {
                ForEach(Pace.allCases) { pace in
                    Text(pace.displayName).tag(pace)
                }
            }
            .pickerStyle(.segmented)
            Text(paceBlurb)
                .font(.caption)
                .fontDesign(.serif)
                .italic()
                .foregroundStyle(Theme.inkSecondary)
        }
        .bulletinCard()
    }

    private var intensitySection: some View {
        @Bindable var userStore = app.userStore
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "Professor Intensity")
            Picker("Intensity", selection: $userStore.intensity) {
                ForEach(Intensity.allCases) { intensity in
                    Text(intensity.displayName).tag(intensity)
                }
            }
            .pickerStyle(.segmented)
            Text(intensityBlurb)
                .font(.caption)
                .fontDesign(.serif)
                .italic()
                .foregroundStyle(Theme.inkSecondary)
        }
        .bulletinCard()
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "Connection")
            if app.config.isMockMode {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "theatermasks")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Demo mode")
                            .font(.subheadline.weight(.semibold))
                            .fontDesign(.serif)
                            .foregroundStyle(Theme.ink)
                        Text("No Secrets.plist found — sessions are played by a scripted professor and content comes from bundled fixtures. Add SUPABASE_URL and SUPABASE_ANON_KEY to go live.")
                            .font(.caption)
                            .fontDesign(.serif)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.icloud")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connected to Supabase")
                            .font(.subheadline.weight(.semibold))
                            .fontDesign(.serif)
                            .foregroundStyle(Theme.ink)
                        Text(app.config.supabaseURL?.absoluteString ?? "")
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
        }
        .bulletinCard()
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The Academy")
                .font(.headline)
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)
            Text("An AI philosophy department in your pocket. All assigned texts are verified US public domain; verbatim quotation is grounded in the retrieved text, always — and the app itself has no philosophy.")
                .font(.caption)
                .fontDesign(.serif)
                .italic()
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bulletinCard()
    }

    private var paceBlurb: String {
        switch app.userStore.pace {
        case .relaxed: return "Longer runway per unit; your professor schedules lighter daily reading."
        case .standard: return "The syllabus as designed — estimated weeks hold."
        case .intensive: return "Compressed schedule; expect more reading per sitting."
        }
    }

    private var intensityBlurb: String {
        switch app.userStore.intensity {
        case .gentle: return "Pushback softened; more scaffolding before hard questions."
        case .standard: return "Push on ideas, warmth toward the person."
        case .rigorous: return "No vague answer survives. You asked for it."
        }
    }
}
