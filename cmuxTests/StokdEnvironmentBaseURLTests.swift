import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Resolving the active stokd environment's host.
///
/// The bug this covers: the repo-detail launcher hard-coded localhost:8167, so
/// on `saas` it opened a local URL for a remote environment.
@Suite struct StokdEnvironmentBaseURLTests {
    @Test func parsesTheURLFromJSONOutput() {
        let json = #"{"env":"saas","api_url":"https://api.stokd.cloud","overlay":null}"#

        #expect(StokdEnvironmentBaseURL.parse(cliOutput: json)?.absoluteString == "https://api.stokd.cloud")
    }

    @Test func parsesTheURLFromHumanOutput() {
        let text = """
        env:      saas
        api url:  https://api.stokd.cloud
        overlay:  none
        """

        #expect(StokdEnvironmentBaseURL.parse(cliOutput: text)?.absoluteString == "https://api.stokd.cloud")
    }

    @Test func keepsThePortForLocalEnvironments() {
        let json = #"{"env":"local","api_url":"http://localhost:8167"}"#

        #expect(StokdEnvironmentBaseURL.parse(cliOutput: json)?.absoluteString == "http://localhost:8167")
    }

    /// Callers append their own path, so a path on the CLI's answer must be
    /// dropped or the result would be e.g. `/api/repos/owner/repo`.
    @Test func reducesToTheOrigin() {
        let json = #"{"api_url":"https://api.stokd.cloud/api/v2?x=1#frag"}"#

        #expect(StokdEnvironmentBaseURL.parse(cliOutput: json)?.absoluteString == "https://api.stokd.cloud")
    }

    @Test func takesTheFirstURLWhenSeveralAppear() {
        let json = #"{"api_url":"https://api.stokd.cloud","docs":"https://docs.stokd.cloud"}"#

        #expect(StokdEnvironmentBaseURL.parse(cliOutput: json)?.host == "api.stokd.cloud")
    }

    /// Guessing a host would silently point the user at another environment's
    /// data, so unparseable output must resolve to nothing.
    @Test func returnsNilRatherThanGuessing() {
        for output in ["", "env: saas", "not a url", "ftp://files.example.com", "{}"] {
            #expect(StokdEnvironmentBaseURL.parse(cliOutput: output) == nil, "expected nil for \(output)")
        }
    }

    @Test func toleratesSurroundingPunctuationAndWhitespace() {
        #expect(
            StokdEnvironmentBaseURL.parse(cliOutput: "  (https://api.stokd.cloud), ok  ")?.absoluteString
                == "https://api.stokd.cloud"
        )
    }
}
