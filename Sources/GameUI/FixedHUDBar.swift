#if canImport(SwiftUI)
import SwiftUI
import GameSimulation

public struct FixedHUDBar: View {
    public var snapshot: HUDSnapshot
    public var warning: WarningBanner
    public var onSelectEntity: ((EntityID) -> Void)?

    public init(snapshot: HUDSnapshot, warning: WarningBanner, onSelectEntity: ((EntityID) -> Void)? = nil) {
        self.snapshot = snapshot
        self.warning = warning
        self.onSelectEntity = onSelectEntity
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Row 1: Vital stats
            HStack(spacing: 16) {
                HQHealthBar(current: snapshot.hqHealth, max: snapshot.hqMaxHealth)

                Divider()
                    .frame(height: 20)
                    .overlay(HUDColor.border)

                WavePhaseIndicator(snapshot: snapshot)

                Spacer(minLength: 8)

                powerIndicator

                Divider()
                    .frame(height: 20)
                    .overlay(HUDColor.border)

                currencyDisplay
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .allowsHitTesting(false)

            // Warning banner (conditional)
            WarningBannerView(warning: warning)
                .animation(.spring(response: 0.35), value: warning)
                .allowsHitTesting(false)

            // Alert strip (bottleneck signals — interactive, tappable pills)
            AlertStripView(alerts: snapshot.groupedAlerts, onSelectEntity: onSelectEntity)

            // Row 2: Resource tray
            Divider()
                .overlay(HUDColor.border)
                .allowsHitTesting(false)

            ResourceTray(resources: snapshot.allResources)
                .frame(height: 28)
                .allowsHitTesting(false)
        }
        .background(HUDColor.background.opacity(0.85))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HUDColor.border)
                .frame(height: 1)
        }
    }

    private var powerIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12))
                .foregroundStyle(HUDColor.powerYellow)

            Text("\(snapshot.powerAvailable)/\(snapshot.powerDemand)")
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(HUDColor.primaryText)

            let headroom = snapshot.powerHeadroom
            Text("(\(headroom >= 0 ? "+" : "")\(headroom))")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(headroom >= 0 ? HUDColor.accentGreen : HUDColor.accentRed)
        }
    }

    private var currencyDisplay: some View {
        HStack(spacing: 4) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(HUDColor.accentAmber)

            Text("\(snapshot.currency)")
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(HUDColor.primaryText)
                .contentTransition(.numericText())
        }
    }
}
#endif
