import Foundation

/// Resolves the base URL of the *active* stokd environment.
///
/// `local`, `stage`, and `saas` are different hosts, so anything that builds a
/// stokd URL has to ask which environment is current rather than assume the
/// local one. The env-to-host mapping lives in the stokd CLI, not in config, so
/// the CLI is the source of truth and this type parses its answer.
///
/// Parsing is deliberately shape-agnostic: it takes the first absolute http(s)
/// URL in the output. `stokd env` prints the resolved API URL in both its JSON
/// and human forms, and keying on "the first URL" survives either, plus any
/// future relabelling of the field. A wrong guess here sends the user to
/// another environment's data, so an unparseable answer yields `nil` and the
/// caller falls back rather than inventing a host.
enum StokdEnvironmentBaseURL {
    /// Extracts the environment's base URL from `stokd env` output.
    ///
    /// - Parameter cliOutput: stdout of `stokd env` (JSON or plain text).
    /// - Returns: The origin (scheme + host + port) of the first absolute
    ///   http(s) URL found, or `nil` when the output contains none.
    static func parse(cliOutput: String) -> URL? {
        guard let match = firstURLString(in: cliOutput),
              var components = URLComponents(string: match),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false else {
            return nil
        }
        // Keep only the origin: callers append their own paths, and a trailing
        // "/api" from the CLI's answer would double up.
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func firstURLString(in text: String) -> String? {
        // Stop at characters that cannot appear in a bare URL token so quotes,
        // commas, and trailing punctuation from JSON or prose are dropped.
        let terminators = CharacterSet(charactersIn: "\"' \t\n\r,;)]}<>")
        guard let start = text.range(
            of: "https?://",
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }
        let tail = text[start.lowerBound...]
        let end = tail.rangeOfCharacter(from: terminators)?.lowerBound ?? tail.endIndex
        let candidate = String(tail[..<end])
        return candidate.isEmpty ? nil : candidate
    }
}
