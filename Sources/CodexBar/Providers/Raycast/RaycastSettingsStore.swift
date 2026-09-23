import CodexBarCore
import Foundation

extension SettingsStore {
    var raycastCookieHeader: String {
        get { self[providerConfig: .raycast, field: .cookieHeader] }
        set { self[providerConfig: .raycast, field: .cookieHeader] = newValue }
    }

    var raycastCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .raycast, fallback: .auto) }
        set { self.setCookieSource(newValue, provider: .raycast) }
    }
}
