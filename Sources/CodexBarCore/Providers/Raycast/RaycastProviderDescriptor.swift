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

    /// Chrome first (CodexBar default). Brave is included because this provider was proven against a
    /// Brave www.raycast.com session; other Chromium forks stay Manual-only.
    private static var browserCookieOrder: BrowserCookieImportOrder? {
        #if os(macOS)
        [.brave, .chrome]
        #else
        nil
        #endif
    }

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .raycast,
            menuBarMetrics: ProviderMenuBarMetricCapabilities(supported: [.automatic, .primary]),
            settingsSection: .init(RaycastProviderSettingsKey.self, cookieSettings: RaycastProviderSettings.self),
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
                browserCookieOrder: self.browserCookieOrder,
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
                    [ScriptFetchStrategy(
                        id: "raycast.js",
                        provider: .raycast,
                        bundledPlugin: "raycast",
                        sourceLabel: "web",
                        kind: .web,
                        resolveValues: { context in
                            guard context.settings?.raycast?.cookieSource != .off else { return nil }
                            return ScriptFetchStrategy.Values()
                        },
                        isEnabled: { _ in true })]
                })),
            cli: ProviderCLIConfig(
                name: "raycast",
                versionDetector: nil,
                browserSupportExemption: { _, _, settings in
                    settings?.raycast?.cookieSource == .manual
                }))
    }
}
