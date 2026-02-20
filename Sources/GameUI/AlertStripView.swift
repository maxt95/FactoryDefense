#if canImport(SwiftUI)
import SwiftUI
import GameSimulation

public struct AlertStripView: View {
    public var alerts: [GroupedBottleneckAlert]
    public var onSelectEntity: ((EntityID) -> Void)?

    public init(alerts: [GroupedBottleneckAlert], onSelectEntity: ((EntityID) -> Void)? = nil) {
        self.alerts = alerts
        self.onSelectEntity = onSelectEntity
    }

    public var body: some View {
        if !alerts.isEmpty {
            HStack(spacing: 8) {
                ForEach(alerts) { alert in
                    alertPill(alert)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 24)
            .background(HUDColor.surface.opacity(0.7))
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.35), value: alerts.map(\.id))
        }
    }

    private func alertPill(_ alert: GroupedBottleneckAlert) -> some View {
        let hasTapTarget = alert.representativeEntityID != nil && onSelectEntity != nil
        let severityColor = HUDColor.severityColor(for: alert.severity)
        return HStack(spacing: 5) {
            Circle()
                .fill(severityColor)
                .frame(width: 6, height: 6)

            Text(alert.message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HUDColor.primaryText)
                .lineLimit(1)

            if hasTapTarget {
                Image(systemName: "location.viewfinder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HUDColor.accentTealBright)
            }
        }
        .padding(.horizontal, hasTapTarget ? 8 : 6)
        .padding(.vertical, 3)
        .background {
            if hasTapTarget {
                RoundedRectangle(cornerRadius: 5)
                    .fill(severityColor.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(severityColor.opacity(0.35), lineWidth: 1)
                    }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let entityID = alert.representativeEntityID {
                onSelectEntity?(entityID)
            }
        }
        #if os(macOS)
        .onHover { hovering in
            if hasTapTarget {
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        #endif
    }
}
#endif
