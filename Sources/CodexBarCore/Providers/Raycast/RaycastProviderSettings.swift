import Foundation

public struct RaycastProviderSettings: ProviderCookieSettings {
    public let cookieSource: ProviderCookieSource
    public let manualCookieHeader: String?

    public init(cookieSource: ProviderCookieSource, manualCookieHeader: String?) {
        self.cookieSource = cookieSource
        self.manualCookieHeader = manualCookieHeader
    }
}

public enum RaycastProviderSettingsKey: ProviderSettingsSectionKey {
    public static let providerID = ProviderInstanceID.raycast
    public typealias Section = RaycastProviderSettings
}

extension ProviderSettingsSnapshot {
    public typealias RaycastProviderSettings = CodexBarCore.RaycastProviderSettings
    public var raycast: RaycastProviderSettings? {
        self[RaycastProviderSettingsKey.self]
    }

    public static func make(raycast: RaycastProviderSettings?) -> Self {
        self.make(raycast, for: RaycastProviderSettingsKey.self)
    }
}

extension ProviderSettingsSnapshotContribution {
    public static func raycast(_ section: RaycastProviderSettings) -> Self {
        Self(section, for: RaycastProviderSettingsKey.self)
    }
}
