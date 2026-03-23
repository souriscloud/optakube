import SwiftUI

struct ResourceStatusBadge: View {
    let status: ResourceStatus

    var body: some View {
        Image(systemName: status.systemImage)
            .foregroundStyle(status.color)
            .imageScale(.small)
            .help(status.rawValue)
    }
}
