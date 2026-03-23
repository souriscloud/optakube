import SwiftUI

enum ResourceStatus: String, Sendable {
    case running = "Running"
    case pending = "Pending"
    case succeeded = "Succeeded"
    case failed = "Failed"
    case warning = "Warning"
    case unknown = "Unknown"

    var color: Color {
        switch self {
        case .running: return .green
        case .pending: return .orange
        case .succeeded: return .blue
        case .failed: return .red
        case .warning: return .yellow
        case .unknown: return .gray
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "checkmark.circle.fill"
        case .pending: return "clock.fill"
        case .succeeded: return "checkmark.seal.fill"
        case .failed: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}
