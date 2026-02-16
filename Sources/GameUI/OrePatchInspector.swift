import Foundation
import GameSimulation

public struct OrePatchInspectorViewModel: Identifiable, Sendable {
    public var id: Int { patchID }
    public var patchID: Int
    public var title: String
    public var subtitle: String
    public var anchorPosition: GridPosition
    public var anchorHeightTiles: Int
    public var sections: [ObjectInspectorSection]

    public init(
        patchID: Int,
        title: String,
        subtitle: String,
        anchorPosition: GridPosition,
        anchorHeightTiles: Int,
        sections: [ObjectInspectorSection]
    ) {
        self.patchID = patchID
        self.title = title
        self.subtitle = subtitle
        self.anchorPosition = anchorPosition
        self.anchorHeightTiles = max(1, anchorHeightTiles)
        self.sections = sections
    }
}

public struct OrePatchInspectorBuilder: Sendable {
    public init() {}

    public func build(patchID: Int, in world: WorldState) -> OrePatchInspectorViewModel? {
        guard let patch = world.orePatches.first(where: { $0.id == patchID }) else { return nil }

        let depositRows = [
            ObjectInspectorRow(label: "Type", value: OrePresentation.displayName(for: patch.oreType)),
            ObjectInspectorRow(label: "Richness", value: patch.richness.rawValue.capitalized),
            ObjectInspectorRow(label: "Stage", value: patch.visualStage.rawValue.capitalized)
        ]

        let statusRows = [
            ObjectInspectorRow(label: "Miner", value: patch.boundMinerID.map { "#\($0)" } ?? "Unbound"),
            ObjectInspectorRow(label: "State", value: patch.isExhausted ? "Exhausted" : "Active")
        ]

        return OrePatchInspectorViewModel(
            patchID: patch.id,
            title: OrePresentation.displayName(for: patch.oreType),
            subtitle: "Ore Deposit",
            anchorPosition: patch.position,
            anchorHeightTiles: 1,
            sections: [
                ObjectInspectorSection(title: "Deposit", rows: depositRows),
                ObjectInspectorSection(title: "Status", rows: statusRows)
            ]
        )
    }
}

#if canImport(SwiftUI)
import SwiftUI

public struct OrePatchInspectorPopup: View {
    public var model: OrePatchInspectorViewModel
    public var onClose: (() -> Void)?

    public init(model: OrePatchInspectorViewModel, onClose: (() -> Void)? = nil) {
        self.model = model
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title)
                        .font(.headline)
                    Text(model.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(model.sections) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(section.rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text(row.value)
                                .font(.caption.monospacedDigit())
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
    }
}
#endif
