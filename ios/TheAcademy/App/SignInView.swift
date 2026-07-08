import AuthenticationServices
import SwiftUI

/// Bulletin-styled sign-in: Sign in with Apple → Supabase Auth (CONTRACTS
/// §4.1). Shown only in live mode, and only when the student tries to enroll
/// or start a session — browsing the catalog and reader stays open.
struct SignInView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// True when presented inline (e.g. in place of a session) rather than
    /// as a dismissible sheet.
    var inline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !inline {
                HStack {
                    Spacer()
                    Button("Not now") { dismiss() }
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Office of the Registrar").overline(Theme.accent)
                Text("Sign in to enroll")
                    .font(.largeTitle.weight(.semibold))
                    .fontDesign(.serif)
                    .foregroundStyle(Theme.ink)
                Text("An account keeps your enrollments, essays, and progress — and lets your professors remember you between sessions.")
                    .font(.body)
                    .fontDesign(.serif)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.ink.opacity(0.9))
            }

            SignInWithAppleButton(.signIn) { request in
                app.auth.prepare(request)
            } onCompletion: { result in
                Task {
                    await app.auth.handle(result)
                    if app.auth.signedIn, !inline {
                        dismiss()
                    }
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if app.auth.isWorking {
                ProgressView().frame(maxWidth: .infinity)
            }

            if let error = app.auth.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Text("Browsing the catalog and reading the texts stays open without an account.")
                .font(.caption)
                .fontDesign(.serif)
                .italic()
                .foregroundStyle(Theme.inkSecondary)

            if inline { Spacer(minLength: 0) }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paper)
    }
}
