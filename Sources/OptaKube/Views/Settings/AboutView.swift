import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            AppIconView(size: 80)
                .padding(.top, 16)

            Text("OptaKube")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(AppInfo.version) (\(AppInfo.build))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Free, native macOS Kubernetes GUI")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider().frame(width: 200)

            VStack(alignment: .leading, spacing: 4) {
                Text("Built with")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    badge("Swift", color: .orange)
                    badge("SwiftUI", color: .blue)
                }
                HStack(spacing: 8) {
                    badge("Yams", color: .green)
                    badge("SwiftTerm", color: .purple)
                }
            }

            Divider().frame(width: 200)

            VStack(spacing: 6) {
                Text("Made by Souris.CLOUD")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("bio.souris.cloud", destination: URL(string: "https://bio.souris.cloud")!)
                    .font(.caption)
                Link(destination: URL(string: "https://ko-fi.com/souriscloud")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "cup.and.saucer.fill")
                        Text("Support on Ko-fi")
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(red: 1.0, green: 0.36, blue: 0.42).opacity(0.15))
                    .foregroundStyle(Color(red: 1.0, green: 0.36, blue: 0.42))
                    .clipShape(Capsule())
                }
            }

            Spacer().frame(height: 8)
        }
        .frame(width: 300, height: 380)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

enum AppInfo {
    /// Single source of truth — reads from Info.plist at runtime, falls back to hardcoded
    static let version: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }()
    static let build: String = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }()
    static let bundleId = "cloud.souris.optakube"
}
