import SwiftUI

/// Displays a badge SVG as a pre-rendered UIImage fetched from BadgeImageCache.
/// Shows a pulsing placeholder while the first render completes; subsequent
/// appearances of the same badge+color are instant (cache hit).
struct AsyncBadgeImageView: View {
    let badgeName: String
    let color: Color

    @State private var image: UIImage?
    @State private var pulse = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(pulse ? 0.12 : 0.04))
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
            }
        }
        .task(id: "\(badgeName)|\(color.toHexString())") {
            image = await BadgeImageCache.shared.image(for: badgeName, color: color)
        }
    }
}
