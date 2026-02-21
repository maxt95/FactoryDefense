import CoreGraphics
import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif

public enum GameplayOverlayWindowID: String, CaseIterable, Sendable {
    case buildMenu
    case buildingReference
    case tileLegend
    case onboarding
    case tuningDashboard
}

public struct GameplayOverlayWindowState: Sendable, Equatable {
    public var id: GameplayOverlayWindowID
    public var origin: CGPoint
    public var size: CGSize
    public var zOrder: Int

    public init(
        id: GameplayOverlayWindowID,
        origin: CGPoint,
        size: CGSize,
        zOrder: Int
    ) {
        self.id = id
        self.origin = origin
        self.size = size
        self.zOrder = zOrder
    }
}

public struct GameplayOverlayLayoutState: Sendable {
    public private(set) var windows: [GameplayOverlayWindowID: GameplayOverlayWindowState]
    private var highestZOrder: Int

    public init(windows: [GameplayOverlayWindowID: GameplayOverlayWindowState] = [:], highestZOrder: Int = 0) {
        self.windows = windows
        self.highestZOrder = highestZOrder
    }

    public static func defaultLayout(
        viewportSize: CGSize,
        safeAreaInsets: SafeAreaInsets = .zero
    ) -> GameplayOverlayLayoutState {
        let defaults: [(GameplayOverlayWindowID, CGPoint, CGSize)] = [
            (.buildMenu, CGPoint(x: 16, y: 96), CGSize(width: 320, height: 460)),
            (.buildingReference, CGPoint(x: 348, y: 96), CGSize(width: 300, height: 460)),
            (.tileLegend, CGPoint(x: 1032, y: 96), CGSize(width: 280, height: 240)),
            (.onboarding, CGPoint(x: 660, y: 408), CGSize(width: 360, height: 300)),
            (.tuningDashboard, CGPoint(x: 660, y: 720), CGSize(width: 220, height: 220))
        ]

        var stateByID: [GameplayOverlayWindowID: GameplayOverlayWindowState] = [:]
        var maxZ = 0
        for (index, tuple) in defaults.enumerated() {
            let (id, origin, size) = tuple
            let zOrder = index + 1
            maxZ = max(maxZ, zOrder)
            stateByID[id] = GameplayOverlayWindowState(id: id, origin: origin, size: size, zOrder: zOrder)
        }

        var layout = GameplayOverlayLayoutState(windows: stateByID, highestZOrder: maxZ)
        layout.clampToViewport(viewportSize, safeAreaInsets: safeAreaInsets)
        return layout
    }

    public func windowState(for windowID: GameplayOverlayWindowID) -> GameplayOverlayWindowState? {
        windows[windowID]
    }

    public func zIndex(for windowID: GameplayOverlayWindowID) -> Double {
        Double(windows[windowID]?.zOrder ?? 0)
    }

    public mutating func ensureWindow(
        id: GameplayOverlayWindowID,
        defaultOrigin: CGPoint,
        defaultSize: CGSize,
        viewportSize: CGSize,
        safeAreaInsets: SafeAreaInsets = .zero
    ) {
        guard windows[id] == nil else { return }
        highestZOrder += 1
        windows[id] = GameplayOverlayWindowState(
            id: id,
            origin: defaultOrigin,
            size: defaultSize,
            zOrder: highestZOrder
        )
        clampWindow(id: id, to: viewportSize, safeAreaInsets: safeAreaInsets)
    }

    public mutating func updateWindowSize(
        id: GameplayOverlayWindowID,
        size: CGSize,
        viewportSize: CGSize,
        safeAreaInsets: SafeAreaInsets = .zero
    ) {
        guard var state = windows[id] else { return }
        let width = max(120, size.width)
        let height = max(64, size.height)
        let nextSize = CGSize(width: width, height: height)
        if approximatelyEqual(state.size, nextSize) {
            return
        }
        state.size = nextSize
        windows[id] = state
        clampWindow(id: id, to: viewportSize, safeAreaInsets: safeAreaInsets)
    }

    public mutating func focus(windowID: GameplayOverlayWindowID) {
        guard var state = windows[windowID] else { return }
        highestZOrder += 1
        state.zOrder = highestZOrder
        windows[windowID] = state
    }

    public mutating func setDragPosition(
        windowID: GameplayOverlayWindowID,
        origin: CGPoint,
        viewportSize: CGSize,
        safeAreaInsets: SafeAreaInsets = .zero
    ) {
        guard var state = windows[windowID] else { return }
        state.origin = origin
        windows[windowID] = state
        clampWindow(id: windowID, to: viewportSize, safeAreaInsets: safeAreaInsets)
    }

    public mutating func clampToViewport(
        _ viewportSize: CGSize,
        safeAreaInsets: SafeAreaInsets = .zero
    ) {
        for windowID in windows.keys {
            clampWindow(id: windowID, to: viewportSize, safeAreaInsets: safeAreaInsets)
        }
    }

    private mutating func clampWindow(
        id: GameplayOverlayWindowID,
        to viewportSize: CGSize,
        safeAreaInsets: SafeAreaInsets
    ) {
        guard var state = windows[id] else { return }
        let margin: CGFloat = 12
        #if os(macOS)
        let topInset: CGFloat = 0
        #else
        let topInset = safeAreaInsets.top
        #endif
        let minX = safeAreaInsets.leading + margin
        let minY = topInset + margin
        let availableWidth = max(120, viewportSize.width - safeAreaInsets.leading - safeAreaInsets.trailing - (margin * 2))
        let availableHeight = max(64, viewportSize.height - topInset - safeAreaInsets.bottom - (margin * 2))
        let width = min(state.size.width, availableWidth)
        let height = min(state.size.height, availableHeight)
        state.size = CGSize(width: width, height: height)
        let maxX = viewportSize.width - safeAreaInsets.trailing - width - margin
        let maxY = viewportSize.height - safeAreaInsets.bottom - height - margin
        state.origin.x = min(max(state.origin.x, minX), max(minX, maxX))
        state.origin.y = min(max(state.origin.y, minY), max(minY, maxY))
        windows[id] = state
    }

    private func approximatelyEqual(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }
}

#if canImport(SwiftUI)
public struct GameplayOverlayWindowDefinition: Identifiable, Hashable, Sendable {
    public var id: GameplayOverlayWindowID
    public var title: String
    public var preferredWidth: CGFloat
    public var preferredHeight: CGFloat

    public init(id: GameplayOverlayWindowID, title: String, preferredWidth: CGFloat, preferredHeight: CGFloat) {
        self.id = id
        self.title = title
        self.preferredWidth = preferredWidth
        self.preferredHeight = preferredHeight
    }
}

public struct GameplayOverlayWindowChrome<Content: View>: View {
    public var title: String
    public var onFocus: () -> Void
    public var onDragChanged: (CGSize) -> Void
    public var onDragEnded: (CGSize) -> Void
    public var onResizeChanged: (CGSize) -> Void
    public var onResizeEnded: (CGSize) -> Void
    @ViewBuilder public var content: Content

    public init(
        title: String,
        onFocus: @escaping () -> Void,
        onDragChanged: @escaping (CGSize) -> Void,
        onDragEnded: @escaping (CGSize) -> Void,
        onResizeChanged: @escaping (CGSize) -> Void,
        onResizeEnded: @escaping (CGSize) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.onFocus = onFocus
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.onResizeChanged = onResizeChanged
        self.onResizeEnded = onResizeEnded
        self.content = content()
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HUDColor.primaryText)
                    Spacer(minLength: 8)
                    Image(systemName: "line.3.horizontal")
                        .font(.caption2)
                        .foregroundStyle(HUDColor.secondaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(HUDColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            onDragChanged(value.translation)
                        }
                        .onEnded { value in
                            onDragEnded(value.translation)
                        }
                )
                .simultaneousGesture(
                    TapGesture().onEnded { onFocus() }
                )

                ScrollView(.vertical, showsIndicators: true) {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
            .background(HUDColor.background.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(HUDColor.border, lineWidth: 1)
            }
            .simultaneousGesture(
                TapGesture().onEnded { onFocus() }
            )

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(HUDColor.secondaryText)
                .padding(6)
                .background(HUDColor.surface, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        onResizeChanged(value.translation)
                    }
                    .onEnded { value in
                        onResizeEnded(value.translation)
                    }
                )
                .simultaneousGesture(
                    TapGesture().onEnded { onFocus() }
                )
                .padding(10)
        }
    }
}

public struct GameplayOverlayHost<Content: View>: View {
    @Binding private var layoutState: GameplayOverlayLayoutState
    private var viewportSize: CGSize
    private var safeAreaInsets: SafeAreaInsets
    private var windowDefinitions: [GameplayOverlayWindowDefinition]
    private var content: (GameplayOverlayWindowID) -> Content

    public init(
        layoutState: Binding<GameplayOverlayLayoutState>,
        viewportSize: CGSize,
        safeAreaInsets: SafeAreaInsets = .zero,
        windows: [GameplayOverlayWindowDefinition],
        @ViewBuilder content: @escaping (GameplayOverlayWindowID) -> Content
    ) {
        self._layoutState = layoutState
        self.viewportSize = viewportSize
        self.safeAreaInsets = safeAreaInsets
        self.windowDefinitions = windows
        self.content = content
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(windowDefinitions) { definition in
                if let state = layoutState.windowState(for: definition.id) {
                    GameplayOverlayWindowInstance(
                        state: state,
                        title: definition.title,
                        viewportSize: viewportSize,
                        safeAreaInsets: safeAreaInsets,
                        onFocus: {
                            layoutState.focus(windowID: definition.id)
                        },
                        onCommit: { finalOrigin in
                            layoutState.setDragPosition(
                                windowID: definition.id,
                                origin: finalOrigin,
                                viewportSize: viewportSize,
                                safeAreaInsets: safeAreaInsets
                            )
                        },
                        onResizeCommit: { finalSize in
                            layoutState.updateWindowSize(
                                id: definition.id,
                                size: finalSize,
                                viewportSize: viewportSize,
                                safeAreaInsets: safeAreaInsets
                            )
                        }
                    ) {
                        content(definition.id)
                    }
                    .zIndex(layoutState.zIndex(for: definition.id))
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            layoutState.focus(windowID: definition.id)
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            bootstrapWindows()
        }
        .onChange(of: viewportSize) { _, _ in
            bootstrapWindows()
            layoutState.clampToViewport(viewportSize, safeAreaInsets: safeAreaInsets)
        }
    }

    private func preferredWidth(for definition: GameplayOverlayWindowDefinition) -> CGFloat {
        let margin: CGFloat = 12
        let available = max(180, viewportSize.width - safeAreaInsets.leading - safeAreaInsets.trailing - (margin * 2))
        return min(definition.preferredWidth, available)
    }

    private func bootstrapWindows() {
        for definition in windowDefinitions {
            layoutState.ensureWindow(
                id: definition.id,
                defaultOrigin: defaultOrigin(for: definition.id),
                defaultSize: CGSize(width: preferredWidth(for: definition), height: definition.preferredHeight),
                viewportSize: viewportSize,
                safeAreaInsets: safeAreaInsets
            )
        }
    }

    private func defaultOrigin(for windowID: GameplayOverlayWindowID) -> CGPoint {
        switch windowID {
        case .buildMenu:
            return CGPoint(x: 16, y: 96)
        case .buildingReference:
            return CGPoint(x: 348, y: 96)
        case .tileLegend:
            return CGPoint(x: 1032, y: 96)
        case .onboarding:
            return CGPoint(x: 660, y: 408)
        case .tuningDashboard:
            return CGPoint(x: 660, y: 720)
        }
    }
}

private struct GameplayOverlayWindowInstance<Content: View>: View {
    var state: GameplayOverlayWindowState
    var title: String
    var viewportSize: CGSize
    var safeAreaInsets: SafeAreaInsets
    var onFocus: () -> Void
    var onCommit: (CGPoint) -> Void
    var onResizeCommit: (CGSize) -> Void
    @ViewBuilder var content: Content

    @State private var dragStartOrigin: CGPoint?
    @State private var dragTranslation: CGSize = .zero
    @State private var resizeStartSize: CGSize?
    @State private var resizeTranslation: CGSize = .zero

    var body: some View {
        let origin = resolvedOrigin
        let size = resolvedSize
        GameplayOverlayWindowChrome(
            title: title,
            onFocus: onFocus,
            onDragChanged: { translation in
                if dragStartOrigin == nil {
                    dragStartOrigin = state.origin
                    onFocus()
                }
                dragTranslation = translation
            },
            onDragEnded: { translation in
                if dragStartOrigin == nil {
                    dragStartOrigin = state.origin
                    onFocus()
                }
                dragTranslation = translation
                let finalOrigin = resolvedOrigin
                onCommit(finalOrigin)
                dragStartOrigin = nil
                dragTranslation = .zero
            },
            onResizeChanged: { translation in
                if resizeStartSize == nil {
                    resizeStartSize = state.size
                    onFocus()
                }
                resizeTranslation = translation
            },
            onResizeEnded: { translation in
                if resizeStartSize == nil {
                    resizeStartSize = state.size
                    onFocus()
                }
                resizeTranslation = translation
                onResizeCommit(resolvedSize)
                resizeStartSize = nil
                resizeTranslation = .zero
            }
        ) {
            content
        }
        .tutorialAnchor(state.id.rawValue)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .offset(x: origin.x, y: origin.y)
        .onChange(of: state.origin) { _, _ in
            guard dragStartOrigin == nil else { return }
            dragTranslation = .zero
        }
        .onChange(of: state.size) { _, _ in
            guard resizeStartSize == nil else { return }
            resizeTranslation = .zero
        }
    }

    private var resolvedOrigin: CGPoint {
        let base = dragStartOrigin ?? state.origin
        let next = CGPoint(
            x: base.x + dragTranslation.width,
            y: base.y + dragTranslation.height
        )
        return clamped(origin: next, windowSize: state.size)
    }

    private var resolvedSize: CGSize {
        let base = resizeStartSize ?? state.size
        let next = CGSize(
            width: base.width + resizeTranslation.width,
            height: base.height + resizeTranslation.height
        )
        return clamped(size: next, origin: resolvedOrigin)
    }

    private func clamped(origin: CGPoint, windowSize: CGSize) -> CGPoint {
        let margin: CGFloat = 12
        #if os(macOS)
        let topInset: CGFloat = 0
        #else
        let topInset = safeAreaInsets.top
        #endif
        let minX = safeAreaInsets.leading + margin
        let minY = topInset + margin
        let maxX = viewportSize.width - safeAreaInsets.trailing - windowSize.width - margin
        let maxY = viewportSize.height - safeAreaInsets.bottom - windowSize.height - margin
        return CGPoint(
            x: min(max(origin.x, minX), max(minX, maxX)),
            y: min(max(origin.y, minY), max(minY, maxY))
        )
    }

    private func clamped(size: CGSize, origin: CGPoint) -> CGSize {
        let margin: CGFloat = 12
        let minWidth: CGFloat = 120
        let minHeight: CGFloat = 64
        let availableWidth = viewportSize.width - safeAreaInsets.trailing - margin - origin.x
        let availableHeight = viewportSize.height - safeAreaInsets.bottom - margin - origin.y
        let maxWidth = max(minWidth, availableWidth)
        let maxHeight = max(minHeight, availableHeight)
        return CGSize(
            width: min(max(size.width, minWidth), maxWidth),
            height: min(max(size.height, minHeight), maxHeight)
        )
    }
}
#endif
