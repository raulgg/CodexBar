import CodexBarCore
import Foundation

struct RaycastProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .raycast

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "web" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.raycastCookieSource
        _ = settings.raycastCookieHeader
    }

    @MainActor
    func tokenAccountsVisibility(context: ProviderSettingsContext, support: TokenAccountSupport) -> Bool {
        !support.requiresManualCookieSource || context.settings.raycastCookieSource == .manual
            || !context.settings.tokenAccounts(for: .raycast).isEmpty
    }

    @MainActor
    func applyTokenAccountCookieSource(settings: SettingsStore) {
        settings.raycastCookieSource = .manual
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        [ProviderCookieSourceUI.picker(
            id: "raycast-cookie-source",
            context: context,
            source: \.raycastCookieSource,
            allowsOff: false,
            subtitles: {
                .init(
                    auto: "Automatic imports Chrome or Brave cookies from www.raycast.com.",
                    manual: "Paste a Cookie header captured from the account settings page.",
                    off: "Raycast cookies are disabled.")
            })]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [ProviderSettingsFieldDescriptor(
            id: "raycast-cookie-header",
            title: "Cookie header",
            subtitle: "Paste the Cookie header from a www.raycast.com/settings request. It must contain __raycast_session.",
            kind: .secure,
            placeholder: "__raycast_session=…; csrf_token=…",
            binding: context.binding(\.raycastCookieHeader),
            actions: [.openURL(
                id: "raycast-open-settings",
                title: "Open Raycast Account",
                url: URL(string: "https://www.raycast.com/settings"))],
            isVisible: { context.settings.raycastCookieSource == .manual })]
    }
}
