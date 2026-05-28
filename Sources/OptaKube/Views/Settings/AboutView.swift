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
    /// Single source of truth. release.sh keeps this line and Info.plist in sync.
    /// Compile-time constant so it works under `swift run` too (no Info.plist there).
    static let version = "0.3.0"

    /// Derived from version: major*10000 + minor*100 + patch. So 0.2.0 → 200,
    /// 1.2.3 → 10203. Monotonic for Sparkle's CFBundleVersion comparison without
    /// any human increment-by-one.
    static let build: String = {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return "1" }
        return String(parts[0] * 10000 + parts[1] * 100 + parts[2])
    }()

    static let bundleId = "cloud.souris.optakube"
}
