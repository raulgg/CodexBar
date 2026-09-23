import Foundation

#if os(macOS)
import SweetCookieKit

public enum RaycastCookieImporter {
    private static let cookieClient = BrowserCookieClient()
    private static let cookieDomains = ["raycast.com", "www.raycast.com"]
    private static let sessionCookieName = "__raycast_session"

    public struct SessionInfo: Sendable {
        public let cookies: [HTTPCookie]
        public let sourceLabel: String

        public init(cookies: [HTTPCookie], sourceLabel: String) {
            self.cookies = cookies
            self.sourceLabel = sourceLabel
        }

        public var cookieHeader: String {
            self.cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
    }

    public static func importSession(
        browserDetection: BrowserDetection,
        preferredBrowsers: [Browser] = [.chrome],
        logger: ((String) -> Void)? = nil) throws -> SessionInfo
    {
        let log: (String) -> Void = { msg in logger?("[raycast-cookie] \(msg)") }
        let installedBrowsers = preferredBrowsers.isEmpty
            ? (ProviderDefaults.metadata[.raycast]?.browserCookieOrder ?? Browser.defaultImportOrder)
                .cookieImportCandidates(using: browserDetection)
            : preferredBrowsers.cookieImportCandidates(using: browserDetection)

        for browserSource in installedBrowsers {
            do {
                let query = BrowserCookieQuery(domains: self.cookieDomains)
                let sources = try Self.cookieClient.codexBarRecords(
                    matching: query,
                    in: browserSource,
                    logger: log)
                for source in sources where !source.records.isEmpty {
                    let httpCookies = BrowserCookieClient.makeHTTPCookies(source.records, origin: query.origin)
                    if !httpCookies.isEmpty {
                        let hasSessionCookie = httpCookies.contains { cookie in
                            cookie.name == self.sessionCookieName
                        }
                        if !hasSessionCookie {
                            log("Skipping \(source.label) cookies: missing \(self.sessionCookieName)")
                            continue
                        }
                        log("Found \(httpCookies.count) Raycast cookies in \(source.label)")
                        return SessionInfo(cookies: httpCookies, sourceLabel: source.label)
                    }
                }
            } catch {
                BrowserCookieAccessGate.recordIfNeeded(error)
                log("\(browserSource.displayName) cookie import failed: \(error.localizedDescription)")
            }
        }

        throw RaycastCookieImportError.noCookies
    }
}

enum RaycastCookieImportError: LocalizedError {
    case noCookies

    var errorDescription: String? {
        switch self {
        case .noCookies:
            "No Raycast session cookies found in browsers."
        }
    }
}
#endif
