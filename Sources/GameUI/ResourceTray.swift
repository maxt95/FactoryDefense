#if canImport(SwiftUI)
import SwiftUI

public struct ResourceTray: View {
    public var resources: [ResourceChip]

    public init(resources: [ResourceChip]) {
        self.resources = resources
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sortedResources) { chip in
                    resourceChipView(chip)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 28)
    }

    private var sortedResources: [ResourceChip] {
        resources.sorted { lhs, rhs in
            let lhsNonZero = lhs.quantity > 0
            let rhsNonZero = rhs.quantity > 0
            if lhsNonZero != rhsNonZero { return lhsNonZero }
            return false
        }
    }

    private func resourceChipView(_ chip: ResourceChip) -> some View {
        let dimmed = chip.quantity == 0
        return HStack(spacing: 4) {
            Circle()
                .fill(HUDColor.resourceDotColor(for: chip.itemID))
                .frame(width: 6, height: 6)

            Text(chip.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HUDColor.secondaryText)

            Text("\(chip.quantity)")
                .font(.system(size: 12, weight: .regular).monospacedDigit())
                .foregroundStyle(HUDColor.primaryText)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(HUDColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(dimmed ? 0.4 : 1.0)
    }
}
#endif
