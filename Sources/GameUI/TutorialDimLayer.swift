#if canImport(SwiftUI)
import SwiftUI

// MARK: - Tutorial Dim Layer with Spotlight Cutout

public struct TutorialDimLayer: View {
    public var spotlightRect: CGRect?
    public var dimOpacity: Double

    public init(spotlightRect: CGRect?, dimOpacity: Double = 0.65) {
        self.spotlightRect = spotlightRect
        self.dimOpacity = dimOpacity
    }

    public var body: some View {
        Canvas { context, size in
            let fullRect = CGRect(origin: .zero, size: size)

            if let spotlight = spotlightRect {
                let cornerRadius: CGFloat = 12
                var path = Path()
                path.addRect(fullRect)
                path.addRoundedRect(
                    in: spotlight,
                    cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
                )

                context.fill(path, with: .color(Color.black.opacity(dimOpacity)), style: FillStyle(eoFill: true))

                // Glow border around cutout
                let borderPath = RoundedRectangle(cornerRadius: cornerRadius)
                    .path(in: spotlight)
                context.stroke(
                    borderPath,
                    with: .color(HUDColor.accentTeal.opacity(0.6)),
                    lineWidth: 2
                )
                context.stroke(
                    borderPath,
                    with: .color(HUDColor.accentTeal.opacity(0.15)),
                    lineWidth: 6
                )
            } else {
                context.fill(
                    Path(fullRect),
                    with: .color(Color.black.opacity(dimOpacity))
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
#endif
