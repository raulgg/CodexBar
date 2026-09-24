import Foundation
import Testing
@testable import CodexBarCore
#if os(macOS)
import SweetCookieKit
#endif

#if os(macOS)
struct RaycastCookieImporterTests {
    @Test
    func `website query matches the account host exactly`() {
        let query = RaycastCookieImporter.websiteCookieQuery()

        #expect(query.domainMatch == .exact)
        #expect(query.domains == ["www.raycast.com", "raycast.com"])
    }

    @Test
    func `website session keeps the account cookie and drops the backend host`() {
        let cookies = Self.cookies([
            ("backend.raycast.com", "__raycast_session", "backend-session"),
            ("www.raycast.com", "__raycast_session", "account-session"),
            ("www.raycast.com", "csrf_token", "account-csrf"),
            (".raycast.com", "ph_posthog", "analytics"),
            ("developers.raycast.com", "__gitbook_cookie_granted", "docs"),
        ])

        let selected = RaycastCookieImporter.cookiesForWebsiteSession(cookies)
        let header = selected.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")

        #expect(header == "__raycast_session=account-session; csrf_token=account-csrf; ph_posthog=analytics")
    }

    @Test
    func `account host wins when the parent domain has the same cookie name`() {
        let cookies = Self.cookies([
            (".raycast.com", "__raycast_session", "parent-session"),
            ("www.raycast.com", "__raycast_session", "account-session"),
        ])

        let selected = RaycastCookieImporter.cookiesForWebsiteSession(cookies)

        #expect(selected.map(\.value) == ["account-session"])
    }

    @Test
    func `import keeps a later profile when an earlier session cookie is empty`() throws {
        let sessions = try RaycastCookieImporter.importSessions(
            browserDetection: Self.detection,
            preferredBrowsers: [.safari],
            loadRecords: { _, _, _ in
                [
                    Self.store("Safari Empty", id: "empty", cookies: [
                        ("www.raycast.com", "__raycast_session", ""),
                        ("www.raycast.com", "csrf_token", "ignored"),
                    ]),
                    Self.store("Safari Valid", id: "valid", cookies: [
                        ("www.raycast.com", "__raycast_session", "valid-session"),
                        ("www.raycast.com", "csrf_token", "csrf"),
                        ("backend.raycast.com", "__raycast_session", "backend"),
                    ]),
                ]
            })

        #expect(sessions.map(\.sourceLabel) == ["Safari Valid"])
        #expect(
            RaycastWebCookieSupport.requestCookieHeader(from: sessions.first?.cookieHeader)
                == "__raycast_session=valid-session; csrf_token=csrf")
    }

    @Test
    func `import with no session uses the shared sign in message`() throws {
        do {
            _ = try RaycastCookieImporter.importSessions(
                browserDetection: Self.detection,
                preferredBrowsers: [.safari],
                loadRecords: { _, _, _ in [] })
            Issue.record("Expected a missing session")
        } catch let error as RaycastSettingsError {
            #expect(error == .missingCookie())
            #expect(error.localizedDescription == RaycastSettingsError.missingCookieMessage)
        }
    }

    @Test
    func `import keeps an access denial when no browser session can be read`() throws {
        do {
            _ = try RaycastCookieImporter.importSessions(
                browserDetection: Self.detection,
                preferredBrowsers: [.safari],
                loadRecords: { browser, _, _ in
                    throw BrowserCookieError.accessDenied(
                        browser: browser,
                        details: "Safari cookie file exists but is not readable. Enable Full Disk Access.")
                })
            Issue.record("Expected an access denial")
        } catch let error as RaycastSettingsError {
            #expect(error.localizedDescription.hasPrefix(RaycastSettingsError.missingCookieMessage))
            #expect(error.localizedDescription.contains("Full Disk Access"))
            #expect(error.localizedDescription.contains("Safari"))
        }
    }

    private static let detection = BrowserDetection(
        homeDirectory: "/tmp/codexbar-raycast-browser-test",
        cacheTTL: 0,
        fileExists: { _ in false },
        directoryContents: { _ in nil })

    private static func store(
        _ label: String,
        id: String,
        cookies: [(String, String, String)]) -> BrowserCookieStoreRecords
    {
        BrowserCookieStoreRecords(
            store: BrowserCookieStore(
                browser: .safari,
                profile: BrowserProfile(id: id, name: label),
                kind: .primary,
                label: label,
                databaseURL: nil),
            records: cookies.map { domain, name, value in
                BrowserCookieRecord(
                    domain: domain,
                    name: name,
                    path: "/",
                    value: value,
                    expires: Date(timeIntervalSince1970: 1_900_000_000),
                    isSecure: true,
                    isHTTPOnly: true)
            })
    }

    private static func cookies(_ rows: [(String, String, String)]) -> [HTTPCookie] {
        rows.compactMap { domain, name, value in
            HTTPCookie(properties: [
                .domain: domain,
                .path: "/",
                .name: name,
                .value: value,
                .secure: true,
            ])
        }
    }
}
#endif
