import SwiftUI

/// Consistent app icon used across Welcome screen, About window, etc.
struct AppIconView: View {
    var size: CGFloat = 80

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25)
                .fill(LinearGradient(
                    colors: [Color(red: 0.25, green: 0.55, blue: 1.0), Color(red: 0.12, green: 0.32, blue: 0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)

            // Cube wireframe matching the actual .icns
            Canvas { context, canvasSize in
                let s = canvasSize.width
                let cx = s / 2, cy = s / 2, sz = s * 0.28
                let lw = s * 0.02

                let top = CGPoint(x: cx, y: cy - sz * 0.65)
                let mid = CGPoint(x: cx, y: cy + sz * 0.05)
                let bot = CGPoint(x: cx, y: cy + sz * 0.75)
                let left = CGPoint(x: cx - sz * 0.7, y: cy - sz * 0.25)
                let right = CGPoint(x: cx + sz * 0.7, y: cy - sz * 0.25)
                let botLeft = CGPoint(x: cx - sz * 0.7, y: cy + sz * 0.45)
                let botRight = CGPoint(x: cx + sz * 0.7, y: cy + sz * 0.45)

                // Top face fill
                var topFace = Path()
                topFace.move(to: top); topFace.addLine(to: right); topFace.addLine(to: mid); topFace.addLine(to: left); topFace.closeSubpath()
                context.fill(topFace, with: .color(.white.opacity(0.15)))

                // Left face fill
                var leftFace = Path()
                leftFace.move(to: left); leftFace.addLine(to: mid); leftFace.addLine(to: bot); leftFace.addLine(to: botLeft); leftFace.closeSubpath()
                context.fill(leftFace, with: .color(.white.opacity(0.08)))

                // Right face fill
                var rightFace = Path()
                rightFace.move(to: right); rightFace.addLine(to: mid); rightFace.addLine(to: bot); rightFace.addLine(to: botRight); rightFace.closeSubpath()
                context.fill(rightFace, with: .color(.white.opacity(0.04)))

                // Edges
                let edges: [(CGPoint, CGPoint)] = [
                    (top, right), (top, left), (left, botLeft), (right, botRight),
                    (mid, left), (mid, right), (mid, bot), (botLeft, bot), (botRight, bot)
                ]
                for (a, b) in edges {
                    var line = Path()
                    line.move(to: a); line.addLine(to: b)
                    context.stroke(line, with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: size, height: size)
        }
    }
}
