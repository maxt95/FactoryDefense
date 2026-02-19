#if canImport(SwiftUI)
import SwiftUI

public struct GameClockView: View {
    public var tick: UInt64

    public init(tick: UInt64) {
        self.tick = tick
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 11))
                .foregroundStyle(HUDColor.secondaryText)
            Text(formattedTime)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(HUDColor.primaryText)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(HUDColor.background.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(HUDColor.border, lineWidth: 1)
        }
    }

    private var formattedTime: String {
        let totalSeconds = Int(tick / 20)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }
}
#endif
