#if canImport(SwiftUI)
import SwiftUI

// MARK: - Preference Key

public struct TutorialAnchorKey: PreferenceKey {
    nonisolated(unsafe) public static var defaultValue: [String: CGRect] = [:]

    public static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - View Extension

public extension View {
    func tutorialAnchor(_ key: String) -> some View {
        self.background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: TutorialAnchorKey.self,
                        value: [key: proxy.frame(in: .global)]
                    )
            }
        )
    }
}
#endif
