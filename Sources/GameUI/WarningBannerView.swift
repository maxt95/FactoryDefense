#if canImport(SwiftUI)
import SwiftUI

public struct WarningBannerView: View {
    public var warning: WarningBanner

    public init(warning: WarningBanner) {
        self.warning = warning
    }

    public var body: some View {
        if warning != .none {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                Text(HUDColor.warningMessage(for: warning))
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(HUDColor.warningColor(for: warning).opacity(0.90))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
#endif
