import Foundation

public enum RaycastProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    private static let credentials = ProviderCredentialAdapter.apiKey(
        environmentKey: RaycastSettingsReader.apiKeyEnvironmentKey,
        resolve: { RaycastSettingsReader.apiKey(environment: $0) },
        missingCredentialMessage: { _ in RaycastUsageError.missingCredentials.errorDescription })

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .raycast,
            menuBarMetrics: ProviderMenuBarMetricCapabilities(supported: [.automatic, .primary]),
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
                dashboardURL: "https://www.raycast.com",
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
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in
                    [ScriptFetchStrategy(
                        id: "raycast.js",
                        provider: .raycast,
                        bundledPlugin: "raycast",
                        secretKey: RaycastSettingsReader.apiKeyEnvironmentKey,
                        sourceLabel: "api",
                        resolveSecret: { environment in
                            self.credentials.resolveToken(environment: environment)?.token
                        },
                        isEnabled: { _ in true })]
                })),
            cli: ProviderCLIConfig(
                name: "raycast",
                versionDetector: nil))
    }
}
