import SwiftUI
import Foundation

struct PortForwardMenuBarView: View {
    var pfManager = PortForwardManager.shared
    var windowManager = WindowManager.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Active cluster windows
            if !windowManager.activeWindows.isEmpty {
                ForEach(Array(windowManager.activeWindows.values), id: \.id) { vm in
                    let name = vm.activeConnections.first?.name ?? "Cluster"
                    Button {
                        showWindow(for: vm)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                            Text(name)
                                .lineLimit(1)
                            Spacer()
                            Text("Show")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider().padding(.vertical, 4)
            }

            // Port forwards
            if pfManager.activeForwards.isEmpty {
                HStack {
                    Image(systemName: "network")
                        .foregroundStyle(.secondary)
                    Text("No active port forwards")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } else {
                Text("Port Forwards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                ForEach(pfManager.activeForwards) { pf in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(pf.isRunning ? .green : .red)
                            .frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(pf.podName)
                                .font(.caption)
                                .lineLimit(1)
                            Text("localhost:\(pf.localPort) → \(pf.remotePort)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            pfManager.remove(pf)
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }

                if pfManager.activeForwards.count > 1 {
                    Button("Stop All Forwards") {
                        pfManager.stopAll()
                    }
                    .padding(.top, 4)
                }

                Divider().padding(.vertical, 4)
            }

            // Global actions
            Divider().padding(.vertical, 4)

            Button {
                showWelcome()
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Connect to Cluster...")
                }
            }

            Button {
                showWelcome()
            } label: {
                HStack {
                    Image(systemName: "house")
                    Text("Welcome Screen")
                }
            }

            Divider().padding(.vertical, 4)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                    Text("Quit OptaKube")
                }
            }
        }
        .padding(8)
        .frame(width: 240)
    }

    private func showWindow(for vm: AppViewModel) {
        windowManager.bringWindowToFront(vm.id)
    }

    private func showWelcome() {
        windowManager.showWelcomeWindow()
    }
}
