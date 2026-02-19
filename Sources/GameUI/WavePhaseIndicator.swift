#if canImport(SwiftUI)
import SwiftUI

public struct WavePhaseIndicator: View {
    public var snapshot: HUDSnapshot

    public init(snapshot: HUDSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text("Wave \(snapshot.waveIndex)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HUDColor.secondaryText)

            Image(systemName: phaseIcon)
                .font(.system(size: 12))
                .foregroundStyle(phaseColor)

            Text(phaseLabel)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(phaseColor)
        }
    }

    private var phaseIcon: String {
        if snapshot.isGracePeriod { return "hourglass" }
        if snapshot.isWaveActive { return "flame.fill" }
        return "clock"
    }

    private var phaseColor: Color {
        if snapshot.isGracePeriod { return HUDColor.accentBlue }
        if snapshot.isWaveActive { return HUDColor.accentRed }
        return HUDColor.accentAmber
    }

    private var phaseLabel: String {
        if snapshot.isGracePeriod {
            return "Grace \(formatTicks(snapshot.graceRemainingTicks))"
        }
        if snapshot.isWaveActive {
            return "Surge \(formatTicks(snapshot.surgeRemainingTicks))"
        }
        return "Next \(formatTicks(snapshot.nextWaveInTicks))"
    }

    private func formatTicks(_ ticks: UInt64) -> String {
        let totalSeconds = Int(ticks / 20)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }
}
#endif
