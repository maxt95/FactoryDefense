import SwiftUI
import GameSimulation

/// Floating widget shown above a conveyor tile on touch platforms.
/// Provides CW rotate, CCW rotate, reverse, and dismiss buttons.
public struct ConveyorQuickEditWidget: View {
    public let entityID: EntityID
    public let onRotateCW: () -> Void
    public let onRotateCCW: () -> Void
    public let onReverse: () -> Void
    public let onDismiss: () -> Void

    public init(
        entityID: EntityID,
        onRotateCW: @escaping () -> Void,
        onRotateCCW: @escaping () -> Void,
        onReverse: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.entityID = entityID
        self.onRotateCW = onRotateCW
        self.onRotateCCW = onRotateCCW
        self.onReverse = onReverse
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                onRotateCW()
            }) {
                Text("CW")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)

            Button(action: {
                onRotateCCW()
            }) {
                Text("CCW")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)

            Button(action: {
                onReverse()
            }) {
                Text("Rev")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)

            Button(action: {
                onDismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
