import Foundation
#if os(macOS)
import SweetCookieKit
#endif

public enum RaycastProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    private static let credentials = ProviderCredentialAdapter(tokenAccountSupport: TokenAccountSupport(
        title: "Session tokens",
        subtitle: "Store multiple Raycast Cookie headers.",
        placeholder: "Cookie: …",
        injection: .cookieHeader,
        requiresManualCookieSource: true,
        cookieName: nil))

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
            credentials: self.credentials,
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

struct RaycastUsageFetchStrategy: ProviderFetchStrategy {
    let id: String = "raycast.web"
    let kind: ProviderFetchKind = .web

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        guard context.settings?.raycast?.cookieSource != .off else { return false }
        return true
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let cookieSource = context.settings?.raycast?.cookieSource ?? .auto
        do {
            let cookieHeader = try Self.resolveCookieHeader(context: context, allowCached: true)
            let usage = try await RaycastUsageFetcher.fetchUsage(
                cookieHeader: cookieHeader,
                timeout: context.webTimeout)
            return self.makeResult(usage: usage, sourceLabel: "web")
        } catch RaycastUsageError.invalidCredentials where cookieSource != .manual {
            #if os(macOS)
            CookieHeaderCache.clear(provider: .raycast)
            let cookieHeader = try Self.resolveCookieHeader(context: context, allowCached: false)
            let usage = try await RaycastUsageFetcher.fetchUsage(
                cookieHeader: cookieHeader,
                timeout: context.webTimeout)
            return self.makeResult(usage: usage, sourceLabel: "web")
            #else
            throw RaycastUsageError.invalidCredentials
            #endif
        }
    }

    func shouldFallback(on error: Error, context: ProviderFetchContext) -> Bool {
        guard context.sourceMode == .auto else { return false }
        guard context.settings?.raycast?.cookieSource != .manual,
              context.selectedTokenAccountID == nil
        else {
            return false
        }
        return switch error {
        case RaycastSettingsError.missingCookie,
             RaycastSettingsError.invalidCookie,
             RaycastUsageError.invalidCredentials:
            true
        default:
            false
        }
    }

    static func resolveCookieHeader(context: ProviderFetchContext, allowCached: Bool) throws -> String {
        try RaycastWebCookieSupport.resolveCookieHeader(
            context: RaycastWebCookieSupport.Context(
                settings: context.settings?.raycast,
                provider: .raycast,
                browserDetection: context.browserDetection,
                allowCached: allowCached),
            invalidCookie: RaycastSettingsError.invalidCookie,
            missingCookie: RaycastSettingsError.missingCookie)
    }
}
