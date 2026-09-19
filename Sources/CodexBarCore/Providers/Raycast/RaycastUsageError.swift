import Foundation

public enum RaycastUsageError: LocalizedError, Sendable, Equatable {
    case missingCredentials

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Raycast access token not configured. Add one in Settings, set RAYCAST_ACCESS_TOKEN, or use ~/.config/raycast/config.json."
        }
    }
}
