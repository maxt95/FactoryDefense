import CoreGraphics
import Foundation

public struct SafeAreaInsets: Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat

    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public static let zero = SafeAreaInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
}

public enum AspectClass: String, Sendable {
    case compact
    case standard
    case wide
}

public struct LayoutProfile: Sendable {
    public var viewportSize: CGSize
    public var safeAreaInsets: SafeAreaInsets
    public var aspectClass: AspectClass
    public var hudScale: CGFloat
    public var radialMenuEnabled: Bool

    public init(
        viewportSize: CGSize,
        safeAreaInsets: SafeAreaInsets,
        aspectClass: AspectClass,
        hudScale: CGFloat,
        radialMenuEnabled: Bool
    ) {
        self.viewportSize = viewportSize
        self.safeAreaInsets = safeAreaInsets
        self.aspectClass = aspectClass
        self.hudScale = hudScale
        self.radialMenuEnabled = radialMenuEnabled
    }

    public var fixedHUDHeight: CGFloat {
        switch aspectClass {
        case .compact: return 96
        case .standard: return 80
        case .wide: return 80
        }
    }

    public var resourceTrayVisible: Bool {
        aspectClass != .compact || viewportSize.width >= 400
    }

    public static func resolve(viewportSize: CGSize, safeAreaInsets: SafeAreaInsets) -> LayoutProfile {
        let aspect = max(0.1, viewportSize.width / max(1, viewportSize.height))

        let aspectClass: AspectClass
        if aspect < 1.0 {
            aspectClass = .compact
        } else if aspect < 1.6 {
            aspectClass = .standard
        } else {
            aspectClass = .wide
        }

        let hudScale: CGFloat
        switch aspectClass {
        case .compact:
            hudScale = 0.9
        case .standard:
            hudScale = 1.0
        case .wide:
            hudScale = 1.1
        }

        let radialMenuEnabled = viewportSize.width < 900

        return LayoutProfile(
            viewportSize: viewportSize,
            safeAreaInsets: safeAreaInsets,
            aspectClass: aspectClass,
            hudScale: hudScale,
            radialMenuEnabled: radialMenuEnabled
        )
    }
}
