#if canImport(SwiftUI)
import SwiftUI
import GameContent
import GameSimulation

public struct TechTreeFullScreenView: View {
    @Binding public var techTree: TechTreeViewModel
    public let researchCenterEntityID: EntityID
    public let researchCenterBuffer: [ItemID: Int]
    public let onClose: () -> Void
    public let onUnlock: (String) -> Bool

    public init(
        techTree: Binding<TechTreeViewModel>,
        researchCenterEntityID: EntityID,
        researchCenterBuffer: [ItemID: Int],
        onClose: @escaping () -> Void,
        onUnlock: @escaping (String) -> Bool
    ) {
        self._techTree = techTree
        self.researchCenterEntityID = researchCenterEntityID
        self.researchCenterBuffer = researchCenterBuffer
        self.onClose = onClose
        self.onUnlock = onUnlock
    }

    private var nodes: [TechNodePresentation] {
        techTree.nodes(inventory: researchCenterBuffer)
    }

    private var layout: TechTreeLayout {
        TechTreeLayout(nodeDefs: techTree.nodeDefs, unlockedNodeIDs: techTree.unlockedNodeIDs)
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    let positions = layout.positions
                    let canvasSize = layout.canvasSize

                    ZStack(alignment: .topLeading) {
                        Canvas { context, size in
                            drawEdges(context: context, positions: positions)
                        }
                        .frame(width: canvasSize.width, height: canvasSize.height)

                        ForEach(nodes) { node in
                            if let pos = positions[node.id] {
                                TechNodeCard(
                                    node: node,
                                    buffer: researchCenterBuffer,
                                    onTap: {
                                        if node.status == .available {
                                            _ = onUnlock(node.id)
                                        }
                                    }
                                )
                                .position(x: pos.x, y: pos.y)
                            }
                        }
                    }
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .padding(20)
                }
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Text("Research")
                .font(.title2.weight(.bold))
                .foregroundStyle(HUDColor.primaryText)

            Spacer()

            bufferDisplay

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(HUDColor.secondaryText)
            }
            .buttonStyle(.plain)
        }
    }

    private var bufferDisplay: some View {
        HStack(spacing: 8) {
            ForEach(researchCenterBuffer.sorted(by: { $0.key < $1.key }), id: \.key) { itemID, quantity in
                HStack(spacing: 4) {
                    Circle()
                        .fill(itemColor(itemID))
                        .frame(width: 8, height: 8)
                    Text("\(quantity)x")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(HUDColor.secondaryText)
                    Text(prettify(itemID))
                        .font(.caption)
                        .foregroundStyle(HUDColor.secondaryText)
                }
            }
        }
    }

    private func drawEdges(context: GraphicsContext, positions: [String: CGPoint]) {
        for nodeDef in techTree.nodeDefs {
            guard let toPos = positions[nodeDef.id] else { continue }
            for prereqID in nodeDef.prerequisites {
                guard let fromPos = positions[prereqID] else { continue }

                let bothUnlocked = techTree.unlockedNodeIDs.contains(nodeDef.id)
                    && techTree.unlockedNodeIDs.contains(prereqID)
                let strokeColor = bothUnlocked
                    ? HUDColor.accentGreen.opacity(0.4)
                    : HUDColor.border

                var path = Path()
                path.move(to: CGPoint(x: fromPos.x + 80, y: fromPos.y))
                path.addLine(to: CGPoint(x: toPos.x - 80, y: toPos.y))
                context.stroke(path, with: .color(strokeColor), lineWidth: 2)
            }
        }
    }

    private func itemColor(_ itemID: String) -> Color {
        switch itemID {
        case "plate_iron": return Color(red: 0.65, green: 0.65, blue: 0.70)
        case "plate_copper": return Color(red: 0.85, green: 0.55, blue: 0.30)
        case "plate_steel": return Color(red: 0.50, green: 0.55, blue: 0.60)
        case "gear": return Color(red: 0.60, green: 0.60, blue: 0.55)
        case "circuit": return Color(red: 0.30, green: 0.70, blue: 0.35)
        case "ammo_light": return Color(red: 0.90, green: 0.80, blue: 0.20)
        case "ammo_heavy": return Color(red: 0.90, green: 0.50, blue: 0.15)
        case "ammo_plasma": return Color(red: 0.70, green: 0.30, blue: 0.90)
        case "power_cell": return Color(red: 0.30, green: 0.80, blue: 0.90)
        default: return Color.gray
        }
    }

    private func prettify(_ value: String) -> String {
        value
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

private struct TechNodeCard: View {
    let node: TechNodePresentation
    let buffer: [ItemID: Int]
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(node.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HUDColor.primaryText)

            if !node.costs.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(node.costs, id: \.itemID) { cost in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(costColor(cost, status: node.status))
                                .frame(width: 6, height: 6)
                            Text("\(cost.quantity)x \(prettify(cost.itemID))")
                                .font(.caption2)
                                .foregroundStyle(HUDColor.secondaryText)
                        }
                    }
                }
            }

            Text(statusLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(statusTextColor)
        }
        .frame(width: 160, alignment: .leading)
        .padding(10)
        .background(isHovered ? hoverBackgroundColor : backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isHovered ? hoverBorderColor : borderColor, lineWidth: isHovered ? 2 : 1.5)
        }
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .shadow(color: isHovered ? shadowColor : .clear, radius: 8, y: 2)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onTap()
        }
        .opacity(node.status == .locked ? 0.6 : 1.0)
    }

    private var statusLabel: String {
        switch node.status {
        case .locked: return "Locked"
        case .available: return "Available"
        case .unlocked: return "Unlocked"
        }
    }

    private var statusTextColor: Color {
        switch node.status {
        case .locked: return HUDColor.secondaryText
        case .available: return HUDColor.accentAmber
        case .unlocked: return HUDColor.accentGreen
        }
    }

    private var backgroundColor: Color {
        switch node.status {
        case .locked: return HUDColor.surface
        case .available: return HUDColor.accentAmber.opacity(0.20)
        case .unlocked: return HUDColor.accentGreen.opacity(0.20)
        }
    }

    private var borderColor: Color {
        switch node.status {
        case .locked: return HUDColor.border
        case .available: return HUDColor.accentAmber.opacity(0.6)
        case .unlocked: return HUDColor.accentGreen.opacity(0.6)
        }
    }

    private var hoverBackgroundColor: Color {
        switch node.status {
        case .locked: return HUDColor.surface.opacity(0.9)
        case .available: return HUDColor.accentAmber.opacity(0.30)
        case .unlocked: return HUDColor.accentGreen.opacity(0.30)
        }
    }

    private var hoverBorderColor: Color {
        switch node.status {
        case .locked: return HUDColor.secondaryText.opacity(0.5)
        case .available: return HUDColor.accentAmber.opacity(0.9)
        case .unlocked: return HUDColor.accentGreen.opacity(0.9)
        }
    }

    private var shadowColor: Color {
        switch node.status {
        case .locked: return Color.white.opacity(0.05)
        case .available: return HUDColor.accentAmber.opacity(0.3)
        case .unlocked: return HUDColor.accentGreen.opacity(0.3)
        }
    }

    private func costColor(_ cost: ItemStack, status: TechNodeStatus) -> Color {
        if status == .unlocked { return HUDColor.accentGreen }
        let has = buffer[cost.itemID, default: 0] >= cost.quantity
        return has ? HUDColor.accentGreen : HUDColor.accentRed
    }

    private func prettify(_ value: String) -> String {
        value
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

private struct TechTreeLayout {
    let nodeDefs: [TechNodeDef]
    let unlockedNodeIDs: Set<String>

    private let columnSpacing: CGFloat = 220
    private let rowSpacing: CGFloat = 110
    private let padding: CGFloat = 120

    var positions: [String: CGPoint] {
        let depths = computeDepths()
        let columns = groupByDepth(depths)
        let maxDepth = depths.values.max() ?? 0

        var result: [String: CGPoint] = [:]
        for depth in 0...maxDepth {
            let nodesInColumn = columns[depth] ?? []
            let columnHeight = CGFloat(nodesInColumn.count) * rowSpacing
            let startY = padding + (canvasSize.height - 2 * padding - columnHeight) / 2
            for (row, nodeID) in nodesInColumn.enumerated() {
                let x = padding + CGFloat(depth) * columnSpacing
                let y = startY + CGFloat(row) * rowSpacing + rowSpacing / 2
                result[nodeID] = CGPoint(x: x, y: y)
            }
        }
        return result
    }

    var canvasSize: CGSize {
        let depths = computeDepths()
        let maxDepth = depths.values.max() ?? 0
        let columns = groupByDepth(depths)
        let maxColumnCount = columns.values.map(\.count).max() ?? 1

        let width = padding * 2 + CGFloat(maxDepth) * columnSpacing + 180
        let height = padding * 2 + CGFloat(maxColumnCount) * rowSpacing
        return CGSize(width: max(600, width), height: max(400, height))
    }

    private func computeDepths() -> [String: Int] {
        let byID = Dictionary(uniqueKeysWithValues: nodeDefs.map { ($0.id, $0) })
        var depths: [String: Int] = [:]
        var visited: Set<String> = []

        func depthOf(_ nodeID: String) -> Int {
            if let cached = depths[nodeID] { return cached }
            guard let node = byID[nodeID] else { return 0 }
            guard !visited.contains(nodeID) else { return 0 }
            visited.insert(nodeID)

            let maxPrereqDepth = node.prerequisites.map { depthOf($0) }.max() ?? -1
            let d = maxPrereqDepth + 1
            depths[nodeID] = d
            return d
        }

        for node in nodeDefs {
            _ = depthOf(node.id)
        }
        return depths
    }

    private func groupByDepth(_ depths: [String: Int]) -> [Int: [String]] {
        var columns: [Int: [String]] = [:]
        for node in nodeDefs {
            let depth = depths[node.id] ?? 0
            columns[depth, default: []].append(node.id)
        }
        return columns
    }
}
#endif
