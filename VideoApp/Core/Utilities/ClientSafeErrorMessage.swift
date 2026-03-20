//
//  ClientSafeErrorMessage.swift
//  Defense-in-depth: user-visible strings must not reveal vendors, models, or infrastructure.
//

import Foundation

enum ClientSafeErrorMessage {
    /// Shown when a raw error is missing, empty, or must not be displayed verbatim.
    static let genericGeneration = "We couldn’t finish your video. Please try again in a moment."

    private static let leakedSubstrings: [String] = [
        "grok", "groq", "gemini", "supabase", "openai", "anthropic", "claude",
        "mistral", "replicate", "nanobanana", "modelslab", "googleapis", "generativelanguage",
        "gpt-", "gpt4", "vertex",
        "x.ai", "api.x.ai",
    ]

    private static let maxLength = 320

    static func sanitizeUserFacing(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.count > maxLength { return genericGeneration }
        if containsHttpURL(raw) { return genericGeneration }
        if containsLeak(raw) { return genericGeneration }
        return raw
    }

    /// Use when a non-empty string is required (e.g. failed generation toasts).
    static func sanitizeUserFacingNonEmpty(_ raw: String?) -> String {
        sanitizeUserFacing(raw) ?? genericGeneration
    }

    private static func containsLeak(_ s: String) -> Bool {
        let lower = s.lowercased()
        return leakedSubstrings.contains { lower.contains($0) }
    }

    private static func containsHttpURL(_ s: String) -> Bool {
        s.range(of: "https?://", options: [.regularExpression, .caseInsensitive]) != nil
    }
}
