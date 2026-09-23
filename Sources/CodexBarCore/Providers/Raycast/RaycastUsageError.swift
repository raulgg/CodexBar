import Foundation

public enum RaycastUsageError: LocalizedError, Sendable, Equatable {
    case missingCredentials

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "No Raycast website session found. Sign in at www.raycast.com/settings in Chrome or Brave, or paste a Cookie header that includes __raycast_session."
        }
    }
}
