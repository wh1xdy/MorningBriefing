import SwiftUI

struct GradientBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            // Base material
            Rectangle().fill(.ultraThinMaterial)

            // Liquid-glass colour wash — very subtle tints that shift with scheme
            LinearGradient(
                stops: [
                    .init(color: Color(hue: 0.60, saturation: 0.18, brightness: scheme == .dark ? 0.25 : 0.98, opacity: 1), location: 0.0),
                    .init(color: Color(hue: 0.72, saturation: 0.12, brightness: scheme == .dark ? 0.18 : 0.95, opacity: 1), location: 0.5),
                    .init(color: Color(hue: 0.55, saturation: 0.10, brightness: scheme == .dark ? 0.22 : 0.97, opacity: 1), location: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(scheme == .dark ? 0.55 : 0.30)

            // Specular highlight at top edge — gives the "glass" pop
            LinearGradient(
                colors: [Color.white.opacity(scheme == .dark ? 0.06 : 0.45), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.18)
            )
        }
        .ignoresSafeArea()
    }
}
