import Foundation

/// What a pasted PAT must look like before onboarding saves it (no network check here;
/// `SyncModel.replaceToken` in Settings validates online).
enum PATFormat {
    /// Trims whitespace/newlines; returns nil unless it looks like a GitHub token
    /// (`github_pat_…` fine-grained, or classic `ghp_…`).
    static func normalized(_ input: String) -> String? {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("github_pat_") || t.hasPrefix("ghp_"), t.count >= 20,
              t.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return nil }
        return t
    }
}
