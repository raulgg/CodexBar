import AppKit
import CodexBarCore
import Foundation

struct RaycastProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .raycast

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "api" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings[providerConfig: .raycast, field: .apiKey]
    }

    @MainActor
    func isAvailable(context: ProviderAvailabilityContext) -> Bool {
        if RaycastSettingsReader.apiKey(environment: context.environment) != nil {
            return true
        }
        return !context.settings[providerConfig: .raycast, field: .apiKey]
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "raycast-access-token",
                title: "Access token",
                subtitle: "Raycast has no public usage API key. Paste the account access token the desktop app "
                    + "sends to backend.raycast.com, set RAYCAST_ACCESS_TOKEN, or use a legacy "
                    + "~/.config/raycast/config.json file.",
                kind: .secure,
                placeholder: "Paste access token…",
                binding: context.providerConfigBinding(.apiKey),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "raycast-open-account",
                        title: "Open Raycast",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            NSWorkspace.shared.open(RaycastURLs.site)
                        }),
                ],
                isVisible: nil),
        ]
    }
}

enum RaycastURLs {
    static let site = URL(string: "https://www.raycast.com")!
}
