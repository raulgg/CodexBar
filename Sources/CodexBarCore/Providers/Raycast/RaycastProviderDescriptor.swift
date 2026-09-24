import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if os(macOS)
import SweetCookieKit
#endif

public enum RaycastProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .raycast,
            menuBarMetrics: ProviderMenuBarMetricCapabilities(supported: [.automatic, .primary]),
            settingsSection: .init(
                RaycastProviderSettingsKey.self,
                cookieSettings: { settings in
                    CookieProviderSettings(
                        cookieSource: settings.cookieSource,
                        manualCookieHeader: settings.manualCookieHeader)
                },
                credentialSettings: { context in
                    let settings = context.cookieSettings(for: .raycast)
                    return RaycastProviderSettings(
                        cookieSource: settings.cookieSource,
                        manualCookieHeader: settings.manualCookieHeader)
                }),
            metadata: ProviderMetadata(
                id: .raycast,
                displayName: "Raycast",
                sessionLabel: "Credits",
                weeklyLabel: "Plan",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Raycast usage",
                cliName: "raycast",
                defaultEnabled: false,
                widgetSelectable: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                usesDetailBackedWindow: true,
                browserCookieOrder: ProviderBrowserCookieDefaults.defaultImportOrder,
                dashboardURL: "https://www.raycast.com/settings",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .raycast),
                iconResourceName: "ProviderIcon-raycast",
                color: ProviderColor(hex: 0xFF6363),
                confettiPalette: [
                    ProviderColor(hex: 0xFF6363),
                    ProviderColor(hex: 0xFF8C8C),
                    ProviderColor(hex: 0x1A1A1A),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Raycast AI credits are a monthly allowance, not a cost history." }),
            presentation: ProviderUsagePresentation(
                menuCard: ProviderMenuCardPresentation(
                    showsPrimaryBalanceDescription: true,
                    hidesPrimaryResetWithoutDate: true),
                menu: ProviderMenuDescriptorPresentation(
                    primaryDescriptionIsDetail: { _ in true }),
                planRow: ProviderPlanRowPresentation(label: "Plan")),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .web],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in
                    [RaycastUsageFetchStrategy()]
                })),
            cli: ProviderCLIConfig(
                name: "raycast",
                versionDetector: nil,
                browserSupportExemption: { _, _, settings in
                    settings?.raycast?.cookieSource == .manual
                }))
    }
}

struct RaycastResolvedSession: Sendable {
    let cookieHeader: String
    let sourceLabel: String
}

struct RaycastUsageFetchStrategy: ProviderFetchStrategy {
    typealias UsageLoader = @Sendable (String, TimeInterval) async throws -> UsageSnapshot
    typealias SessionLoader = @Sendable (BrowserDetection) throws -> [RaycastResolvedSession]
    typealias CacheObservation = CookieHeaderCache.ConditionalMutationObservation
    typealias CacheLoader = @Sendable () -> CacheObservation
    typealias CacheClearer = @Sendable (CookieHeaderCache.Entry?) -> Bool
    typealias CacheWriter = @Sendable (CacheObservation, RaycastResolvedSession) -> Void

    let id: String = "raycast.web"
    let kind: ProviderFetchKind = .web
    private let usageLoader: UsageLoader
    private let sessionLoader: SessionLoader
    private let cacheLoader: CacheLoader
    private let cacheClearer: CacheClearer
    private let cacheWriter: CacheWriter

    init(
        usageLoader: @escaping UsageLoader = RaycastUsageFetchStrategy.fetchUsage,
        sessionLoader: @escaping SessionLoader = RaycastUsageFetchStrategy.loadSessions,
        cacheLoader: @escaping CacheLoader = { CookieHeaderCache.observeForConditionalMutation(provider: .raycast) },
        cacheClearer: @escaping CacheClearer = { CookieHeaderCache.clearIfCurrent(provider: .raycast, expected: $0) },
        cacheWriter: @escaping CacheWriter = { expected, session in
            CookieHeaderCache.storeIfObservationCurrent(
                provider: .raycast,
                expected: expected,
                cookieHeader: session.cookieHeader,
                sourceLabel: session.sourceLabel)
        })
    {
        self.usageLoader = usageLoader
        self.sessionLoader = sessionLoader
        self.cacheLoader = cacheLoader
        self.cacheClearer = cacheClearer
        self.cacheWriter = cacheWriter
    }

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        context.settings?.raycast?.cookieSource != .off
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        try Task.checkCancellation()
        let settings = context.settings?.raycast
        guard settings?.cookieSource != .off else { throw RaycastSettingsError.disabled }
        if settings?.cookieSource == .manual {
            guard let header = RaycastWebCookieSupport.requestCookieHeader(from: settings?.manualCookieHeader) else {
                throw RaycastSettingsError.invalidCookie
            }
            let usage = try await self.usageLoader(header, context.webTimeout)
            try Task.checkCancellation()
            return self.makeResult(usage: usage, sourceLabel: "web")
        }

        var observation = self.cacheLoader()
        guard case .authoritative = observation else { throw RaycastSettingsError.cacheUnavailable }
        if let cached = observation.entry {
            if let header = RaycastWebCookieSupport.requestCookieHeader(from: cached.cookieHeader) {
                do {
                    let usage = try await self.usageLoader(header, context.webTimeout)
                    try Task.checkCancellation()
                    return self.makeResult(usage: usage, sourceLabel: "web")
                } catch {
                    try Task.checkCancellation()
                    guard Self.isAuthenticationFailure(error) else { throw error }
                    guard cached.authenticationFailurePolicy != .stopFallback else { throw error }
                    if self.cacheClearer(cached) { observation = observation.afterOwnedClear() }
                }
            } else if cached.authenticationFailurePolicy == .stopFallback {
                throw RaycastSettingsError.invalidCookie
            } else if self.cacheClearer(cached) {
                observation = observation.afterOwnedClear()
            }
        }

        try Task.checkCancellation()
        let sessions = try self.sessionLoader(context.browserDetection)
        guard !sessions.isEmpty else { throw RaycastSettingsError.missingCookie() }
        return try await ProviderCandidateRetryRunner.run(
            sessions,
            shouldRetry: Self.isAuthenticationFailure,
            attempt: { session in
                try Task.checkCancellation()
                let usage = try await self.usageLoader(session.cookieHeader, context.webTimeout)
                try Task.checkCancellation()
                self.cacheWriter(observation, session)
                return self.makeResult(usage: usage, sourceLabel: "web")
            })
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool { false }

    static func fetchUsage(cookieHeader: String, timeout: TimeInterval) async throws -> UsageSnapshot {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = ProviderHTTPClient.redirectGuardedSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let httpTimeout = Self.pluginHTTPTimeoutSeconds(timeout)
        let runtime = try ProviderPluginRuntime(
            bundledPlugin: "raycast",
            transport: ProviderHTTPClient(session: session),
            timeout: Self.pluginRuntimeTimeout(timeout))
        return try await runtime.fetchUsage(
            settings: ["webTimeoutSeconds": String(httpTimeout)],
            cookieResolver: { provider, domain in
                guard provider == .raycast, domain == "www.raycast.com" else {
                    throw RaycastSettingsError.invalidCookie
                }
                return cookieHeader
            })
    }

    static func pluginHTTPTimeoutSeconds(_ timeout: TimeInterval) -> Int {
        Int(min(30, max(1, timeout.rounded())))
    }

    /// Keeps the script alive for the caller's web budget, and at least as long as the clamped HTTP timeout.
    static func pluginRuntimeTimeout(_ timeout: TimeInterval) -> TimeInterval {
        let httpTimeout = TimeInterval(self.pluginHTTPTimeoutSeconds(timeout))
        guard timeout.isFinite else { return httpTimeout }
        return max(timeout, httpTimeout)
    }

    private static func isAuthenticationFailure(_ error: Error) -> Bool {
        (error as? ProviderFetchClassifiedError)?.kind == .authenticationExpired
    }

    private static func loadSessions(browserDetection: BrowserDetection) throws -> [RaycastResolvedSession] {
        #if os(macOS)
        let imported = try RaycastCookieImporter.importSessions(
            browserDetection: browserDetection,
            preferredBrowsers: RaycastWebCookieSupport.automaticImportOrder(provider: .raycast))
        let sessions = imported.compactMap { session -> RaycastResolvedSession? in
            guard let header = RaycastWebCookieSupport.requestCookieHeader(from: session.cookieHeader) else {
                return nil
            }
            return RaycastResolvedSession(cookieHeader: header, sourceLabel: session.sourceLabel)
        }
        guard !sessions.isEmpty else { throw RaycastSettingsError.missingCookie() }
        return sessions
        #else
        throw RaycastSettingsError.missingCookie()
        #endif
    }
}

enum RaycastSettingsError: LocalizedError, Equatable {
    static let missingCookieMessage =
        "No Raycast session cookies found. Sign in at www.raycast.com/settings or paste a Cookie header."

    case missingCookie(details: String? = nil)
    case invalidCookie
    case disabled
    case cacheUnavailable

    var errorDescription: String? {
        switch self {
        case let .missingCookie(details):
            guard let details, !details.isEmpty else { return Self.missingCookieMessage }
            return "\(Self.missingCookieMessage) \(details)"
        case .invalidCookie:
            return "Raycast cookie header is invalid."
        case .disabled:
            return "Raycast cookies are disabled."
        case .cacheUnavailable:
            return "Raycast's saved session is temporarily unavailable. Unlock the Keychain and retry."
        }
    }
}
