#if canImport(SwiftUI)
import SwiftUI

public struct HQHealthBar: View {
    public var current: Int
    public var max: Int

    public init(current: Int, max: Int) {
        self.current = current
        self.max = max
    }

    private var fraction: Double {
        guard max > 0 else { return 0 }
        return Double(current) / Double(max)
    }

    private var isCritical: Bool {
        guard max > 0 else { return false }
        return fraction <= 0.2
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isCritical ? "heart.slash.fill" : "heart.fill")
                .font(.system(size: 12))
                .foregroundStyle(isCritical ? HUDColor.accentRed : HUDColor.accentTeal)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 120, height: 22)

                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(barGradient)
                        .frame(width: proxy.size.width * fraction)
                }
                .frame(width: 120, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("\(current) / \(max)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HUDColor.primaryText)
                    .frame(width: 120, height: 22, alignment: .center)
            }
            .frame(width: 120, height: 22)
            .opacity(isCritical ? criticalPulseOpacity : 1)
        }
    }

    private var barGradient: LinearGradient {
        if isCritical {
            return LinearGradient(
                colors: [HUDColor.accentRed, HUDColor.accentRedBright],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        return LinearGradient(
            colors: [HUDColor.accentTeal, HUDColor.accentTealBright],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    @State private var pulseActive = false

    private var criticalPulseOpacity: Double {
        pulseActive ? 0.7 : 1.0
    }
}
#endif
