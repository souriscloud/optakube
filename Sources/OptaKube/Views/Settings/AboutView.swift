import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            // App icon
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 80, height: 80)

                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.top, 16)

            Text("OptaKube")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 0.1.0")
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

            Text("A free clone of Aptakube")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 8)
        }
        .frame(width: 300, height: 340)
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
