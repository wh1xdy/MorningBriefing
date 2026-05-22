import SwiftUI

/// Reusable frosted-glass background: ultraThinMaterial + low-opacity adaptive gradient.
/// Dark: indigo → purple. Light: white → secondary. Never hardcoded RGB.
struct GradientBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: scheme == .dark
                    ? [Color.indigo.opacity(0.18), Color.purple.opacity(0.12)]
                    : [Color.white.opacity(0.5),   Color.secondary.opacity(0.06)],
                startPoint: .topLeading,
                endPoint:   .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}
