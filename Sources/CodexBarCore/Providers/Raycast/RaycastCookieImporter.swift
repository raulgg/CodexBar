import Foundation

#if os(macOS)
import SweetCookieKit

public enum RaycastCookieImporter {
    private static let cookieClient = BrowserCookieClient()
    /// Hosts the www.raycast.com account page receives. Exact match excludes sibling hosts
    /// such as backend.raycast.com, whose OIDC session is not the website cookie.
    static let websiteCookieDomains = ["www.raycast.com", "raycast.com"]
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

    public static func importSessions(
        browserDetection: BrowserDetection,
        preferredBrowsers: [Browser] = [],
        logger: ((String) -> Void)? = nil) throws -> [SessionInfo]
    {
        try self.importSessions(
            browserDetection: browserDetection,
            preferredBrowsers: preferredBrowsers,
            logger: logger,
            loadRecords: { browserSource, query, log in
                try self.cookieClient.codexBarRecords(
                    matching: query,
                    in: browserSource,
                    logger: log)
            })
    }

    static func importSessions(
        browserDetection: BrowserDetection,
        preferredBrowsers: [Browser] = [],
        logger: ((String) -> Void)? = nil,
        loadRecords: (Browser, BrowserCookieQuery, ((String) -> Void)?) throws
            -> [BrowserCookieStoreRecords]) throws -> [SessionInfo]
    {
        let log: (String) -> Void = { msg in logger?("[raycast-cookie] \(msg)") }
        let order = preferredBrowsers.isEmpty
            ? RaycastWebCookieSupport.automaticImportOrder(provider: .raycast)
            : preferredBrowsers
        var sessions: [SessionInfo] = []
        var accessDeniedHints: [String] = []

        for browserSource in order.cookieImportCandidates(using: browserDetection) {
            do {
                let query = Self.websiteCookieQuery()
                let sources = try loadRecords(browserSource, query, log)
                for source in sources where !source.records.isEmpty {
                    let httpCookies = Self.cookiesForWebsiteSession(
                        BrowserCookieClient.makeHTTPCookies(source.records, origin: query.origin))
                    guard self.hasSessionCookie(httpCookies) else {
                        log("Skipping \(source.label) cookies: missing \(self.sessionCookieName)")
                        continue
                    }
                    log("Found \(httpCookies.count) Raycast cookies in \(source.label)")
                    sessions.append(SessionInfo(cookies: httpCookies, sourceLabel: source.label))
                }
            } catch {
                BrowserCookieAccessGate.recordIfNeeded(error)
                if let hint = (error as? BrowserCookieError)?.accessDeniedHint {
                    accessDeniedHints.append(hint)
                }
                log("\(browserSource.displayName) cookie import failed: \(error.localizedDescription)")
            }
        }

        guard sessions.isEmpty else { return sessions }
        let details = Array(Set(accessDeniedHints)).sorted().joined(separator: " ")
        throw RaycastSettingsError.missingCookie(details: details.isEmpty ? nil : details)
    }

    static func hasSessionCookie(_ cookies: [HTTPCookie]) -> Bool {
        cookies.contains { $0.name == self.sessionCookieName && !$0.value.isEmpty }
    }

    static func websiteCookieQuery() -> BrowserCookieQuery {
        BrowserCookieQuery(domains: self.websiteCookieDomains, domainMatch: .exact)
    }

    /// Drops cookies from other Raycast hosts and keeps one value per name.
    /// The account-page host wins over a parent-domain cookie of the same name.
    static func cookiesForWebsiteSession(_ cookies: [HTTPCookie]) -> [HTTPCookie] {
        var chosen: [String: HTTPCookie] = [:]
        var order: [String] = []
        for cookie in cookies {
            guard self.isWebsiteHost(cookie.domain) else { continue }
            if let existing = chosen[cookie.name] {
                if self.hostRank(cookie.domain) < self.hostRank(existing.domain) {
                    chosen[cookie.name] = cookie
                }
                continue
            }
            order.append(cookie.name)
            chosen[cookie.name] = cookie
        }
        return order.compactMap { chosen[$0] }
    }

    private static func isWebsiteHost(_ domain: String) -> Bool {
        let host = self.normalizedHost(domain)
        return host == "www.raycast.com" || host == "raycast.com"
    }

    private static func hostRank(_ domain: String) -> Int {
        self.normalizedHost(domain) == "www.raycast.com" ? 0 : 1
    }

    private static func normalizedHost(_ domain: String) -> String {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix(".") else { return trimmed }
        return String(trimmed.dropFirst())
    }
}

#endif
