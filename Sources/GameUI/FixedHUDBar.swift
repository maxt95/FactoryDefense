#if canImport(SwiftUI)
import SwiftUI

public struct FixedHUDBar: View {
    public var snapshot: HUDSnapshot
    public var warning: WarningBanner

    public init(snapshot: HUDSnapshot, warning: WarningBanner) {
        self.snapshot = snapshot
        self.warning = warning
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

                Divider()
                    .frame(height: 20)
                    .overlay(HUDColor.border)

                oreRingStrip

                Spacer(minLength: 8)

                powerIndicator

                Divider()
                    .frame(height: 20)
                    .overlay(HUDColor.border)

                currencyDisplay
            }
            .padding(.horizontal, 16)
            .frame(height: 44)

            // Warning banner (conditional)
            WarningBannerView(warning: warning)
                .animation(.spring(response: 0.35), value: warning)

            // Row 2: Resource tray
            Divider()
                .overlay(HUDColor.border)

            ResourceTray(resources: snapshot.allResources)
                .frame(height: 28)
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

    private var oreRingStrip: some View {
        HStack(spacing: 4) {
            ForEach(snapshot.oreRings) { ring in
                VStack(spacing: 0) {
                    Text("R\(ring.ringIndex)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(HUDColor.primaryText)
                    if ring.state == .surveying {
                        Text("\((ring.remainingSurveyTicks + 19) / 20)s")
                            .font(.system(size: 8, weight: .medium).monospacedDigit())
                            .foregroundStyle(HUDColor.secondaryText)
                    } else {
                        Text("\(ring.visiblePatchCount)")
                            .font(.system(size: 8, weight: .medium).monospacedDigit())
                            .foregroundStyle(HUDColor.secondaryText)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(ringBackgroundColor(ringStateRaw: ring.state.rawValue))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func ringBackgroundColor(ringStateRaw: String) -> Color {
        switch ringStateRaw {
        case "locked":
            return HUDColor.border.opacity(0.25)
        case "surveying":
            return HUDColor.accentAmber.opacity(0.30)
        case "revealed":
            return HUDColor.accentGreen.opacity(0.30)
        default:
            return HUDColor.border.opacity(0.25)
        }
    }
}
#endif
