import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct RaycastNativeSupportTests {
    @Test
    func `request cookie header requires a nonempty session cookie`() {
        #expect(RaycastWebCookieSupport.requestCookieHeader(from: "csrf_token=only") == nil)
        #expect(RaycastWebCookieSupport.requestCookieHeader(from: "__raycast_session=; csrf_token=x") == nil)
        #expect(
            RaycastWebCookieSupport.requestCookieHeader(
                from: "theme=dark; __raycast_session=abc; csrf_token=tok; other=1")
                == "__raycast_session=abc; csrf_token=tok")
    }

    @Test
    func `descriptor uses website cookies instead of a public API key`() {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .raycast)
        #expect(!descriptor.metadata.defaultEnabled)
        #expect(descriptor.fetchPlan.sourceModes == Set([.auto, .web]))
        #expect(descriptor.cli.name == "raycast")
        #expect(descriptor.metadata.usesDetailBackedWindow)
        #expect(descriptor.presentation.menuCard.showsPrimaryBalanceDescription)
        #expect(descriptor.presentation.menuCard.hidesPrimaryResetWithoutDate)
        #expect(descriptor.credentials?.tokenAccountSupport == nil)
        #expect(TokenAccountSupportCatalog.support(for: .raycast) == nil)
        #if os(macOS)
        #expect(descriptor.metadata.browserCookieOrder == ProviderBrowserCookieDefaults.defaultImportOrder)
        #endif
    }

    @Test
    func `plugin http timeout clamps into the one through thirty second range`() {
        #expect(RaycastUsageFetchStrategy.pluginHTTPTimeoutSeconds(0) == 1)
        #expect(RaycastUsageFetchStrategy.pluginHTTPTimeoutSeconds(22.4) == 22)
        #expect(RaycastUsageFetchStrategy.pluginHTTPTimeoutSeconds(90) == 30)
    }

    @Test
    func `plugin runtime timeout covers the http call and the caller budget`() {
        #expect(RaycastUsageFetchStrategy.pluginRuntimeTimeout(0) == 1)
        #expect(RaycastUsageFetchStrategy.pluginRuntimeTimeout(22.4) == 22.4)
        #expect(RaycastUsageFetchStrategy.pluginRuntimeTimeout(90) == 90)
        let httpTimeout = TimeInterval(RaycastUsageFetchStrategy.pluginHTTPTimeoutSeconds(22.4))
        #expect(RaycastUsageFetchStrategy.pluginRuntimeTimeout(22.4) >= httpTimeout)
    }

    @Test
    func `strategy does not retry authentication failures for manual cookies`() async {
        final class Counter: @unchecked Sendable {
            var value = 0
        }
        let counter = Counter()
        let strategy = RaycastUsageFetchStrategy(usageLoader: { _, _ in
            counter.value += 1
            throw ProviderFetchClassifiedError(
                kind: .authenticationExpired,
                message: "expired",
                retryAfterSeconds: nil)
        })
        let settings = ProviderSettingsSnapshot.make(raycast: .init(
            cookieSource: .manual,
            manualCookieHeader: "__raycast_session=fixture"))
        do {
            _ = try await strategy.fetch(Self.makeContext(settings: settings))
            Issue.record("Expected authentication expired")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == .authenticationExpired)
            #expect(counter.value == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func `strategy does not treat permission denied as a cookie retry`() async {
        let strategy = RaycastUsageFetchStrategy(usageLoader: { _, _ in
            throw ProviderFetchClassifiedError(
                kind: .permissionDenied,
                message: "denied",
                retryAfterSeconds: nil)
        })
        let settings = ProviderSettingsSnapshot.make(raycast: .init(
            cookieSource: .manual,
            manualCookieHeader: "__raycast_session=fixture"))
        do {
            _ = try await strategy.fetch(Self.makeContext(settings: settings))
            Issue.record("Expected permission denied")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == .permissionDenied)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func `strategy is unavailable when cookies are off`() async {
        let settings = ProviderSettingsSnapshot.make(raycast: .init(
            cookieSource: .off,
            manualCookieHeader: nil))
        let available = await RaycastUsageFetchStrategy().isAvailable(Self.makeContext(settings: settings))
        #expect(!available)
    }

    @Test
    func `authentication failure clears only the observed cache and tries every candidate`() async throws {
        let log = Log()
        let cached = CookieHeaderCache.Entry(
            cookieHeader: "__raycast_session=cached",
            storedAt: Self.now,
            sourceLabel: "old")
        let strategy = RaycastUsageFetchStrategy(
            usageLoader: { cookie, _ in
                log.append(cookie)
                guard cookie == "__raycast_session=valid" else {
                    throw ProviderFetchClassifiedError(kind: .authenticationExpired, message: "fixture")
                }
                return Self.usage()
            },
            sessionLoader: { _ in [
                .init(cookieHeader: "__raycast_session=expired; csrf_token=optional", sourceLabel: "Chrome A"),
                .init(cookieHeader: "__raycast_session=valid", sourceLabel: "Chrome B"),
            ] },
            cacheLoader: { .authoritative(cached) },
            cacheClearer: { expected in
                #expect(expected == cached)
                return true
            },
            cacheWriter: { expected, session in
                #expect(expected.entry == nil)
                #expect(session.sourceLabel == "Chrome B")
                log.append("stored")
            })
        _ = try await strategy.fetch(Self.makeContext(settings: Self.autoSettings))
        #expect(log.values == [
            "__raycast_session=cached",
            "__raycast_session=expired; csrf_token=optional",
            "__raycast_session=valid",
            "stored",
        ])
    }

    @Test(arguments: [ProviderFetchClassifiedError.Kind.networkFailure, .parseFailure, .rateLimited])
    func `non authentication failures preserve the cached session`(kind: ProviderFetchClassifiedError.Kind) async {
        let error = ProviderFetchClassifiedError(kind: kind, message: "fixture")
        let strategy = RaycastUsageFetchStrategy(
            usageLoader: { _, _ in throw error },
            sessionLoader: { _ in
                Issue.record("unexpected session import")
                return []
            },
            cacheLoader: { .authoritative(.init(
                cookieHeader: "__raycast_session=cached",
                storedAt: Self.now,
                sourceLabel: "Chrome")) },
            cacheClearer: { _ in
                Issue.record("unexpected cache clear")
                return false
            },
            cacheWriter: { _, _ in Issue.record("unexpected cache write") })
        await #expect(throws: error) {
            try await strategy.fetch(Self.makeContext(settings: Self.autoSettings))
        }
    }

    @Test
    func `pinned cached session never falls back after authentication failure`() async {
        let error = ProviderFetchClassifiedError(kind: .authenticationExpired, message: "fixture")
        let strategy = RaycastUsageFetchStrategy(
            usageLoader: { _, _ in throw error },
            sessionLoader: { _ in
                Issue.record("unexpected pinned session fallback")
                return []
            },
            cacheLoader: { .authoritative(.init(
                cookieHeader: "__raycast_session=pinned",
                storedAt: Self.now,
                sourceLabel: "pinned",
                authenticationFailurePolicy: .stopFallback)) },
            cacheClearer: { _ in
                Issue.record("unexpected pinned cache clear")
                return false
            },
            cacheWriter: { _, _ in Issue.record("unexpected pinned cache write") })
        await #expect(throws: error) {
            try await strategy.fetch(Self.makeContext(settings: Self.autoSettings))
        }
    }

    @Test
    func `missing session message names the sign in page and keeps access denial details`() {
        let base = RaycastSettingsError.missingCookie()
        #expect(base.localizedDescription == RaycastSettingsError.missingCookieMessage)
        #expect(!base.localizedDescription.contains("Chrome"))
        let denied = RaycastSettingsError.missingCookie(
            details: "Safari cookie file exists but is not readable. Enable Full Disk Access.")
        #expect(denied.localizedDescription.hasPrefix(RaycastSettingsError.missingCookieMessage))
        #expect(denied.localizedDescription.contains("Full Disk Access"))
    }

    private struct StubClaudeFetcher: ClaudeUsageFetching {
        func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
            throw ClaudeUsageError.parseFailed("stub")
        }

        func debugRawProbe(model _: String) async -> String { "stub" }
        func detectVersion() -> String? { nil }
    }

    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []
        func append(_ entry: String) { self.lock.withLock { self.entries.append(entry) } }
        var values: [String] {
            self.lock.withLock { self.entries }
        }
    }

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let autoSettings = ProviderSettingsSnapshot.make(raycast: .init(
        cookieSource: .auto,
        manualCookieHeader: nil))

    private static func usage() -> UsageSnapshot {
        UsageSnapshot(primary: nil, secondary: nil, updatedAt: self.now)
    }

    private static func makeContext(settings: ProviderSettingsSnapshot?) -> ProviderFetchContext {
        ProviderFetchContext(
            runtime: .app,
            sourceMode: .web,
            includeCredits: false,
            webTimeout: 15,
            webDebugDumpHTML: false,
            verbose: false,
            env: [:],
            settings: settings,
            fetcher: UsageFetcher(environment: [:]),
            claudeFetcher: StubClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }
}
