import Foundation
import GameSimulation

@MainActor
public final class PlacementFeedbackController: ObservableObject {
    @Published public private(set) var overrideResult: PlacementResult?

    private var clearTask: Task<Void, Never>?

    public init() {
        self.overrideResult = nil
    }

    deinit {
        clearTask?.cancel()
    }

    public func consume(events: [SimEvent], durationSeconds: TimeInterval = 1.5) {
        guard let rejected = events.reversed().first(where: { $0.kind == .placementRejected }),
              let reason = rejected.placementReason else {
            return
        }
        show(reason, durationSeconds: durationSeconds)
    }

    public func displayedResult(current: PlacementResult) -> PlacementResult {
        overrideResult ?? current
    }

    private func show(_ result: PlacementResult, durationSeconds: TimeInterval) {
        overrideResult = result
        clearTask?.cancel()
        let duration = max(0, durationSeconds)
        clearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.overrideResult = nil
        }
    }
}
