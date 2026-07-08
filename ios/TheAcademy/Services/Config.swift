import Foundation

/// Reads `Secrets.plist` from the app bundle (CONTRACTS §9).
/// Copy `Fixtures/Secrets.example.plist` to `ios/TheAcademy/Secrets.plist`,
/// fill in your Supabase project values, and re-run `xcodegen generate`.
/// When absent (or empty), the app runs in mock mode: bundled fixtures plus a
/// scripted professor, no network.
struct Config {
    static let shared = Config()

    let supabaseURL: URL?
    let supabaseAnonKey: String?

    var isMockMode: Bool { supabaseURL == nil || supabaseAnonKey == nil }

    var sessionEndpoint: URL? {
        supabaseURL?.appendingPathComponent("functions/v1/session")
    }

    init() {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            supabaseURL = nil
            supabaseAnonKey = nil
            return
        }
        let urlString = (plist["SUPABASE_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = (plist["SUPABASE_ANON_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        supabaseURL = urlString.isEmpty ? nil : URL(string: urlString)
        supabaseAnonKey = key.isEmpty ? nil : key
    }
}
